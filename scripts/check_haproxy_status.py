#!/usr/bin/env python3

## This script takes in a directory of files from the haproxy-status.yml matching:
## haproxy-table-nodes* - result of `show table nodes` on all haproxies in a single environment
## haproxy-stat* - result of `show stat` on all haproxies in a single environment
##
## The status is used for server inventory and health indicators.  The stick tables are analyzed
## for both missing rooms and split brain scenarios (rooms assigned to multiple shards at once)
## The output of this script is a JSON file which can be fed into to set-haproxy-stick-table.sh script
## attempting to keep the tables in sync
##
## in addition this script outputs metrics to cloudwatch directly in the HAProxy metric namespace
## stick_table_error - 0 for OK or 1 if any errors were found
## missing_rooms - number of total missing rooms from all proxies
## split_brain_rooms - number of split brain rooms from all proxies
## stick_table_fixes_missing - number of stick table fixes output related to missing rooms
## stick_table_fixes_split_brain - number of fixes output related to split brains

import sys
import argparse
import logging
import json

class AppFilter(logging.Filter):
    def filter(self, record):
        global environment
        record.environment = environment
        return True

#logging.basicConfig(filename='haproxy_status.log',level=logging.DEBUG)

logger = logging.getLogger('haproxy_status')
logger.addFilter(AppFilter())

logger.setLevel(logging.DEBUG)

# create console handler and set level to debug
ch = logging.StreamHandler()
ch.setLevel(logging.DEBUG)

# create formatter
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(environment)s - %(message)s')

# add formatter to ch
ch.setFormatter(formatter)

# add ch to logger
logger.addHandler(ch)

from hcvlib import *

from pprint import pprint

import os

#when reading the current directory, stick table files look so:
table_file_prefix='haproxy-table-nodes'
#and the same for server status status files
stats_file_prefix='haproxy-stat'

#counter starts at 300000
expire_threshhold=250000
#expire_threshhold=350000

#if the meeting is too new (within 2 seconds of creation) or too old (expires in 1 minute) then don't error if it's missing
expire_threshhold_max=298000
expire_threshhold_min=60000
#if the meeting entry isn't within a few seconds of the others, then something is amiss
expire_threshhold_diff=10000

global environment

def log_print(msg,lvl=logging.INFO):
    log(msg=msg,lvl=lvl)
#    print(msg)

def log_debug(msg):
    log(msg=msg,lvl=logging.DEBUG)

def log_info(msg):
    log(msg=msg,lvl=logging.INFO)

def log_warning(msg):
    log(msg=msg,lvl=logging.WARNING)

def log_error(msg):
    log(msg=msg,lvl=logging.ERROR)

def log(msg,lvl=logging.INFO):
    global logger
    logger.log(level=lvl,msg=msg)

def usage():
    print("Usage:")
    print((sys.argv[0] +' --environment <environment string> --directory <path to directory containing haproxy status files>'))
    return 1

#utility function to split up haproxy-reported stats into a structured object
def load_stats_file(dirpath, sfile):
    with open(dirpath+'/'+sfile, 'r') as f:
        header_line=f.readline()
        #headers look like "# pxname,svname,qcur,qmax,scur,smax,slim,stot,bin,bout,dreq,dresp,ereq,econ,eresp,wretr,wredis,status,weight,act,bck,chkfail,chkdown,lastchg,downtime,qlimit,pid,iid,sid,throttle,lbtot,tracked,type,rate,rate_lim,rate_max,check_status,check_code,check_duration,hrsp_1xx,hrsp_2xx,hrsp_3xx,hrsp_4xx,hrsp_5xx,hrsp_other,hanafail,req_rate,req_rate_max,req_tot,cli_abrt,srv_abrt,comp_in,comp_out,comp_byp,comp_rsp,lastsess,last_chk,last_agt,qtime,ctime,rtime,ttime,"
                            # pxname,svname,qcur,qmax,scur,smax,slim,stot,bin,bout,dreq,dresp,ereq,econ,eresp,wretr,wredis,status,weight,act,bck,chkfail,chkdown,lastchg,downtime,qlimit,pid,iid,sid,throttle,lbtot,tracked,type,rate,rate_lim,rate_max,check_status,check_code,check_duration,hrsp_1xx,hrsp_2xx,hrsp_3xx,hrsp_4xx,hrsp_5xx,hrsp_other,hanafail,req_rate,req_rate_max,req_tot,cli_abrt,srv_abrt,comp_in,comp_out,comp_byp,comp_rsp,lastsess,last_chk,last_agt,qtime,ctime,rtime,ttime,agent_status,agent_code,agent_duration,check_desc,agent_desc,check_rise,check_fall,check_health,agent_rise,agent_fall,agent_health,addr,cookie,mode,algo,conn_rate,conn_rate_max,conn_tot,intercepted,dcon,dses,
        #so skip the first two characters, trim the rest of whitespace, make a list from the string on comma and return an array of headers
        headers=[ x for x in header_line[2:].strip().split(',') if len(x)>0 ]
        stats_info = {}
        stats_lines = []
        #read the rest of the file
        for line in f:
            stats_line={}
            line_split=line.strip().split(',')
            if len(line_split)>1:
                #build a dict for each line based on the headers and this line's values
                stats_line=dict(list(zip(headers,line_split)))
                stats_lines.append(stats_line)

    #build structure for return
    stats_info['frontends'] = []
    stats_info['backends'] = []
    stats_info['servers'] = []
    stats_info['frontend_stats'] = {}
    stats_info['backend_stats'] = {}
    stats_info['server_stats'] = {}

    #each stat in the list has different types of information based on the pxname and svname fields
    #examples of lines below:
# admin,FRONTEND,,,0,1,2000,14401,2265341,11516963,0,0,0,,,,,OPEN,,,,,,,,,1,2,0,,,,0,1,0,2,,,,0,14401,0,0,0,0,,1,2,14401,,,0,0,0,0,,,,,,,,
# admin,BACKEND,0,0,0,0,200,0,2265341,11516963,0,0,,0,0,0,0,UP,0,0,0,,0,57080,0,,1,2,0,,0,,1,0,,0,,,,0,0,0,0,0,0,,,,,0,0,0,0,0,0,8,,,0,0,0,0,
# www-http,FRONTEND,,,0,8,2000,170,17818,26503,0,0,86,,,,,OPEN,,,,,,,,,1,3,0,,,,0,0,0,6,,,,0,0,84,86,0,0,,0,6,170,,,0,0,0,0,,,,,,,,
# www-https,FRONTEND,,,19,29,2000,2716,30956979,52627976,0,0,552,,,,,OPEN,,,,,,,,,1,4,0,,,,0,0,0,6,,,,0,35066,75,571,3,20,,1,10,35743,,,0,0,0,0,,,,,,,,
# nodes,hcv-meetjitsi-ap-se-2a-s2,0,0,5,11,,18771,16346506,33179741,,0,,0,0,0,0,UP,1,1,0,0,0,56270,810,,1,5,12,,978,,2,1,,9,L7OK,200,4,0,18660,75,19,3,0,0,,,,12,0,,,,,0,OK,,0,1,7195,9112,

    #split stats into categories based on svname and sid (server ID)
    for sline in stats_lines:
        #FRONTEND are the listeners bound to port 8080,80,443
        if sline['svname']=='FRONTEND':
            if sline['pxname'] not in stats_info['frontends']:
                stats_info['frontends'].append(sline['pxname'])
                stats_info['frontend_stats'][sline['pxname']]=sline
        #BACKEND is only relevant for the admin endpoint, used for statistics gathering and health checking the haproxy
        elif sline['svname']=='BACKEND':
            if sline['pxname'] not in stats_info['backends']:
                stats_info['backends'].append(sline['pxname'])
                stats_info['backend_stats'][sline['pxname']]= sline
        #anything else is a real server backing the cluster, so split on server ID
        else:
            if sline['sid'] not in stats_info['servers']:
                stats_info['servers'].append(sline['sid'])
            stats_info['server_stats'][sline['sid']]=sline
#    stats_info['stats_lines'] = stats_lines
#    pprint(stats_info)

    return stats_info

#utility function to build summary stats from a set of individual servers stats provided by each proxy
def combine_server_stats(stats,stat_key):

    #pull the first item off the list to use as a base object
    new_stats = list(stats[0][stat_key].values())[0].copy()
    new_server_stats = {}
    stats_items = []
    stats_server_items = {}
    #these are the dictionary keys to combine values (sum) into a single value
    combine_keys= ['scur','qcur','smax','qmax','bin','bout','dreq','dresp','ereq','econ','eresp','wretr','redisp','chkfail','chkdown','rate','req_rate','req_rate_max','req_tot','cli_abrt','srv_abrt']
    #these are the dictionary keys to build a single average (sum/count) value
    average_keys=['qtime','ctime','rtime','ttime','check_duration']

    #loop through all files in the collection
    for stat_file in stats:

        stats_items.extend(list(stat_file[stat_key].values()))
        for sid in list(stat_file[stat_key].keys()):
            if not sid in stats_server_items:
                stats_server_items[sid] = []
            stats_server_items[sid].extend([stat_file[stat_key][sid]])

    for sid in list(stats_server_items.keys()):
        server_item = stats_server_items[sid][0].copy()
        new_server_stats[sid] = server_item
        for stat in combine_keys:
            items = [ int(sstat[stat]) for sstat in stats_server_items[sid] if stat in sstat and sstat[stat] ]
            new_server_stats[sid][stat] = sum(items)

        for stat in average_keys:
            items = [ int(sstat[stat]) for sstat in stats_server_items[sid] if stat in sstat and sstat[stat] ]
            if len(items):
                new_server_stats[sid][stat] = sum(items)/len(items)

    for stat in combine_keys:
        items = [ int(sstat[stat]) for sstat in stats_items if stat in sstat and sstat[stat] ]
        new_stats[stat] = sum(items)
    for stat in average_keys:
        items = [ int(sstat[stat]) for sstat in stats_items if stat in sstat and sstat[stat] ]
        if len(items):
            new_stats[stat] = sum(items)/len(items)


    #loop again through all files in the collection
    health_status = {}
    healthy_statuses = ['UP', 'DRAIN']
    healthy_agent_statuses = ['1']
    skip_sv_health_names = ['FRONTEND','BACKEND','local']
    proxy_count = len(stats)
    for stat_file in stats:
        for sid in list(stat_file[stat_key].keys()):
            #set healthy count to 0
            if not sid in health_status:
                health_status[sid] = 0.0
            if stat_file[stat_key][sid]['status'] in healthy_statuses or stat_file[stat_key][sid]['agent_health'] in healthy_agent_statuses:
                health_status[sid] += 1
            else:
                if stat_file[stat_key][sid]['svname'] not in skip_sv_health_names:
                    log_info('unhealthy server {} - status: {}, agent_health: {}'.format(stat_file[stat_key][sid]['svname'], stat_file[stat_key][sid]['status'], stat_file[stat_key][sid]['agent_health']))
    #now normalize the health status back to 1 (if all proxies see as healthy)
    for sid in list(health_status.keys()):
        health_status[sid] = health_status[sid] / proxy_count

    new_server_stats['health'] = health_status
    new_server_stats['totals'] = new_stats
    return new_server_stats

#utility function to combine all stats from all proxies into a single set
def combine_stats(stats):
    combined_stats = {}
    combined_stats['frontends'] = []
    combined_stats['backends'] = []
    combined_stats['servers'] = []
    combined_stats['frontend_stats'] = {}
    combined_stats['backend_stats'] = {}
    combined_stats['server_stats'] = {}

    for stat in stats:
        for frontend in stat['frontends']:
            if frontend not in combined_stats['frontends']:
                combined_stats['frontends'].append(frontend)
        for backend in stat['backends']:
            if backend not in combined_stats['backends']:
                combined_stats['backends'].append(backend)
        for server in stat['servers']:
            if server not in combined_stats['servers']:
                combined_stats['servers'].append(server)

    combined_stats['frontend_stats'] = combine_server_stats(stats,'frontend_stats')
    combined_stats['backend_stats'] = combine_server_stats(stats,'backend_stats')
    combined_stats['server_stats'] = combine_server_stats(stats,'server_stats')

    return combined_stats

#builds the collection of items in the stick table from a path
def load_table_file(dirpath, tfile):
    filepath = dirpath+'/'+tfile
    with open(filepath, 'r') as f:
        header=f.readline()
        file_info = {}
        servers_by_room = {}
        expire_by_room = {}
        rooms_by_server = {}
        for line in f:
            # old line looks like "0x22cd484: key=leecee use=0 exp=299198 server_id=6518987"
            # new line looks like "0x55925131cac0: key=zzzzblah use=0 exp=283168 server_id=12 server_name=jitsi-net-us-west-2a-s2"
            if len(line.strip())>0:
                #extract fields from the line by first spliting it on ' ' then taking each key/value and splitting it on =,taking the last item (value) and removing whitespace
                table_fields = [ x.split('=')[-1].strip() for x in line.split(' ') ]
                tkey=table_fields[0]
                room=table_fields[1]
                use=table_fields[2]
                expires=table_fields[3]
                server=table_fields[4]
                #split the list by room, storing server and expiry
                servers_by_room[room]=server
                expire_by_room[room]=expires
                #split the room list by hosting server
                if not server in rooms_by_server:
                    rooms_by_server[server] = []
                rooms_by_server[server].append(room)

    file_info['filename'] = tfile
    file_info['timestamp'] = os.path.getmtime(filepath)
    file_info['proxy_server'] = tfile[len(table_file_prefix)+1:]
    file_info['servers_by_room'] = servers_by_room
    file_info['rooms_by_server'] = rooms_by_server
    file_info['expire_by_room'] = expire_by_room
    #keep a list of only the rooms which have had activity recently
    file_info['active_rooms'] = limit_active_rooms(expire_by_room)

    return file_info

#take a list of parsed stick tables and compare them for problems
def compare_table_files(tfiles,combined_stats):
    x=0
    servers_by_room={}
    compare_success=True
    compare_results = {'list_inconsistent_count': 0}
    split_brain_count=0
    room_missing_count=0
    fixes_count=0
    missing_rooms = {}
    split_brain_rooms = {}


    server_health = combined_stats['server_stats']['health']
#    log_info("Server Health:")
#    pprint(server_health)
    if len(tfiles) > 0:
        #start with the first file
        x=0
        for file_info in tfiles:
            for r in file_info['servers_by_room']:
                #ensure that the server in question isn't marked as DOWN by any servers
                if (file_info['servers_by_room'][r] in server_health):
                    if (server_health[file_info['servers_by_room'][r]] == 1):
                        servers_by_room[r] = file_info['servers_by_room'][r]
                    else:
                      #  log_info("Skipping servers_by_room assignment for %s, server %s health %s"%(r,file_info['servers_by_room'][r],server_health[file_info['servers_by_room'][r]]))
                        servers_by_room[r] = False
                else:
                 #   log_info("Missing servers_by_room assignment for %s, server %s"%(r,file_info['servers_by_room'][r]))
                    servers_by_room[r] = False

            if file_info['proxy_server'] not in split_brain_rooms:
                split_brain_rooms[file_info['proxy_server']] = []
            if file_info['proxy_server'] not in missing_rooms:
                missing_rooms[file_info['proxy_server']] = []
            #only compare files later in the list than the current file
            x=x+1
    #        print "Active Rooms: "+str(len(file_info['active_rooms']))
            for second_file in tfiles[x:]:
                if second_file['proxy_server'] not in split_brain_rooms:
                    split_brain_rooms[second_file['proxy_server']] = []
                if second_file['proxy_server'] not in missing_rooms:
                    missing_rooms[second_file['proxy_server']] = []
    #            print "Comparing "+file_info['proxy_server']+ ' and ' +second_file['proxy_server']
                if file_info['servers_by_room'] != second_file['servers_by_room']:
                    log_error("Server lists inconsistent between %s and %s"%(file_info['proxy_server'],second_file['proxy_server']))
                    for room in file_info['servers_by_room']:
                        if room not in second_file['servers_by_room']:
                            if int(file_info['expire_by_room'][room]) >= expire_threshhold_min:
                                compare_success=False
                                if room not in missing_rooms[second_file['proxy_server']]:
                                    missing_rooms[second_file['proxy_server']].append(room)
                                    room_missing_count+=1
                                # log_error("Room %s (expires in %s) present on %s missing from %s"%(room, file_info['expire_by_room'][room], file_info['proxy_server'],second_file['proxy_server']))
                            # else:
                            #     log_info("Ignoring Room %s (expires in %s) present on %s missing from %s"%(room, file_info['expire_by_room'][room], file_info['proxy_server'],second_file['proxy_server']))
                        else:
                            if file_info['servers_by_room'][room] != second_file['servers_by_room'][room]:
                                compare_success=False
                                #no match on server, so split brain
                                if room not in split_brain_rooms[file_info['proxy_server']]:
                                    split_brain_rooms[file_info['proxy_server']].append(room)
                                    split_brain_count+=1
                                    log_error("Split brain detected between %s | %s, room %s server %s | %s"%(file_info['proxy_server'],second_file['proxy_server'],room,file_info['servers_by_room'][room],second_file['servers_by_room'][room]))

                    for room in second_file['servers_by_room']:
                        if room not in file_info['servers_by_room']:
                            if int(second_file['expire_by_room'][room]) >= expire_threshhold_min:
                                compare_success=False
                                if room not in missing_rooms[file_info['proxy_server']]:
                                    missing_rooms[file_info['proxy_server']].append(room)
                                    room_missing_count+=1
                                # log_error("Room %s (expires in %s) present on %s missing from %s"%(room, second_file['expire_by_room'][room], second_file['proxy_server'],file_info['proxy_server']))
                            # else:
                            #     log_info("Ignoring Room %s (expires in %s) present on %s missing from %s"%(room, second_file['expire_by_room'][room], second_file['proxy_server'],file_info['proxy_server']))
                        else:
                            if second_file['servers_by_room'][room] != file_info['servers_by_room'][room]:
                                compare_success=False
                                #no match on server, so split brain
                                if room not in split_brain_rooms[second_file['proxy_server']]:
                                    split_brain_rooms[second_file['proxy_server']].append(room)
                                    split_brain_count+=1
                                    log_error("Split brain detected between %s | %s, room %s server %s | %s"%(file_info['proxy_server'],second_file['proxy_server'],room,file_info['servers_by_room'][room],second_file['servers_by_room'][room]))

                if file_info['expire_by_room'] != second_file['expire_by_room']:
                    expiry_diff_rooms = {}
                    #compare the expiry time on each room, ensure they are within the allowed difference
                    rooms=set(list(file_info['expire_by_room'].keys())+list(second_file['expire_by_room'].keys()))
                    for room in rooms:
                        if room in file_info['expire_by_room'] and room in second_file['expire_by_room']:
                            expire_difference=abs(int(file_info['expire_by_room'][room])-int(second_file['expire_by_room'][room]))
                            if expire_difference > expire_threshhold_diff:
                                #expiry is too far apart, something may be wrong
                                #assume the server with the lower value is wrong
                                #this may not be true in the case of an haproxy which has been reset
                                #the stick table is delivered up reboot but the expiry time resets, but only one that one node
                                #so if a conference is halfway to expired and then an haproxy restarts, it may have that conference in the list
                                #for longer than the others which have not restarted
                                if file_info['expire_by_room'][room] > second_file['expire_by_room'][room]:
                                    if not second_file['proxy_server'] in expiry_diff_rooms:
                                        expiry_diff_rooms[second_file['proxy_server']] = []
                                    expiry_diff_rooms[second_file['proxy_server']].append(room)
                                else:
                                    if not file_info['proxy_server'] in expiry_diff_rooms:
                                        expiry_diff_rooms[file_info['proxy_server']] = []
                                    expiry_diff_rooms[file_info['proxy_server']].append(room)
#                    if len(expiry_diff_rooms) > 0:
#                        log_info("Threshhold violations of expiry times between %s %s"%(file_info['proxy_server'],second_file['proxy_server']))
#                        pprint(expiry_diff_rooms)
#                    else:
                        #nothing went wrong?  how boring
#                        pass
#                        log_debug("No expiry threshhold violations found between %s %s"%(file_info['proxy_server'],second_file['proxy_server']))
                else:
                    #no differences at all?  even more boring!
                    pass
#                    log_debug("Identical room expiry data found between %s %s"%(file_info['proxy_server'],second_file['proxy_server']))
#                    pprint(file_info['expire_by_room'])

    else:
        print('No files to compare')
        log_error("Proxy check run with no files to compare")
        compare_success=False


    fix_rooms_missing = {}
    fix_rooms_split_brain = {}
    if (len(split_brain_rooms) > 0):
        for s in split_brain_rooms:
            for r in split_brain_rooms[s]:
                if r in servers_by_room and (servers_by_room[r] != False):
                    fix_rooms_split_brain[r] = {"key":r,"id":int(servers_by_room[r])}
                else:
                    print('split brain room not fixed: %s missing from server : %s'%(r,s))

    if (len(missing_rooms) > 0):
        for s in missing_rooms:
            for r in missing_rooms[s]:
                if r in servers_by_room and (servers_by_room[r] != False):
                    fix_rooms_missing[r] = {"key":r,"id":int(servers_by_room[r])}


    compare_results['fix_rooms_missing'] = fix_rooms_missing
    compare_results['fix_rooms_split_brain'] = fix_rooms_split_brain
    compare_results['room_missing_count'] = room_missing_count
    compare_results['split_brain_count'] = split_brain_count
    compare_results['compare_success'] = compare_success
    return compare_results

def diff(a, b):
    b = set(b)
    return [aa for aa in a if aa not in b]

def stat_details(stats,sid,field):
    sdetails=' ('
    sdetails+=' '.join([ str(stat['server_stats'][sid][field]) for stat in stats if sid in stat['server_stats'] ])

    sdetails+=')'
    return sdetails

def limit_active_rooms(expire_by_room):
    active_rooms = [x for x in list(expire_by_room.keys()) if int(expire_by_room[x])>expire_threshhold ]
    return active_rooms

def compare_with_old_tables(table_files):
    log_print("comparing new and old tables")
    if len(table_files) % 2 != 0:
        log_print("something is weird - there should be an even number of tables. aborting chronlogical comparison")
        return

    chronological_files = sorted(table_files, key=lambda i: i['timestamp'])

    oldrooms = set()
    newrooms = set()

    for i in range(len(table_files)//2):
        for k in table_files[i]['servers_by_room'].keys():  ### just outputting keys, want k,v
            oldrooms.add((k, table_files[i]['servers_by_room'][k]))
        for k in table_files[i + len(table_files)//2]['servers_by_room']:
            newrooms.add((k, table_files[i + len(table_files)//2]['servers_by_room'][k]))

    oldrooms_keys = [i[0] for i in oldrooms]
    newrooms_keys = [i[0] for i in newrooms]

    old_gone_count = 0
    old_moved_count = 0
    for room in oldrooms:
        if room not in newrooms:
            if room[0] not in newrooms_keys:
                old_gone_count += 1
            else:
                old_moved_count += 1

    new_room_count = 0
    for room in newrooms:
        if room not in oldrooms:
            new_room_count += 1

    log_print('there were {} rooms before and {} rooms after the scale down'.format(len(oldrooms), len(newrooms)))
    log_print('{} pre-scale down rooms are no longer in the stick tables'.format(old_gone_count))
    log_print('{} rooms were added to the stick tables during or after the scale down'.format(new_room_count))
    if old_moved_count > 0:
        log_warning('{} rooms changed shards during the scale down'.format(old_moved_count))
    else:
        log_print('{} rooms changed shards during the scale down'.format(old_moved_count))

def main():
    global environment
    stat_files=[]
    table_files=[]


    parser = argparse.ArgumentParser(description='Process haproxy tables/stats and send stats to CloudWatch')
    parser.add_argument('--environment', action='store',
                       help='Environment of node', default=False)
    parser.add_argument('--directory', action='store',
                       help='Path to HAProxy files', default=False)
    parser.add_argument('--region', action='store',
                       help='EC2 Region', default=AWS_DEFAULT_REGION)
    parser.add_argument('--compare_old', action='store',
                        help='Mode where old stick tables are compared with new', default=False)
    args = parser.parse_args()


    if args.directory:
        status_path = args.directory
    else:
        usage()
        exit(1)

    if args.environment:
        environment = args.environment
    else:
        usage()
        exit(1)


    if os.path.isdir(status_path):
        log_info('Parsing data from %s'%status_path)
    else:
        log_info('No directory found: %s'%status_path)
        usage()

    fix_file_path = status_path + '/stick-table-fixes.json'
    #delete any previous stick table fixes before we get started
    try:
        os.remove(fix_file_path)
    except OSError:
        pass
    metric_data = []

    for (dirpath, dirnames, filenames) in os.walk(status_path):
        for filename in filenames:
            if filename.startswith(stats_file_prefix):
                stat_files.append(filename)
            if filename.startswith(table_file_prefix):
                table_files.append(filename)


    stats=[]
    if len(stat_files) > 0:
        for sfile in stat_files:
            stats.append(load_stats_file(dirpath, sfile))

        combined_stats = combine_stats(stats)
    else:
        log_info('no stat files found; haproxy-status may be locked')

    tables=[]
    if len(table_files) > 0:
        for tfile in table_files:
            tables.append(load_table_file(dirpath, tfile))

        if len(tables)>0:
            if args.compare_old:
                compare_with_old_tables(tables)
                sys.exit()
            result = compare_table_files(tables,combined_stats)
            if not result['compare_success']:
                #handle the failure
                log_error("Table comparisons failed! DETAIL: %s missing rooms, %s split brain rooms"%(result['room_missing_count'],result['split_brain_count']))
            else:
                log_print("Table comparisons succeeded.")

            fixes=[]
            if result['fix_rooms_missing']:
                log_print("Fixes found for missing rooms")
#                pprint(result['fix_rooms_missing'])
                for r in result['fix_rooms_missing']:
                    fixes.append(result['fix_rooms_missing'][r])

            if result['fix_rooms_split_brain']:
                log_print("Fixes found for split brain")
#                pprint(result['fix_rooms_split_brain'])
                for r in result['fix_rooms_split_brain']:
                    fixes.append(result['fix_rooms_split_brain'][r])

            #write the fix rooms out to a file for later use if they exist
            if len(fixes) > 0:
                with open(fix_file_path, 'w') as ffile:
                    json.dump(fixes,ffile)

            #overall success/failure metric
            metric='stick_table_error'
            metric_unit='Count'
            metric_namespace='HAProxy'
            if result['compare_success']:
                metric_value=0
            else:
                metric_value=1
            metric_data.append(create_metric_item(metric=metric, metric_value=metric_value, metric_unit=metric_unit, environment=environment))

            #missing room count
            metric='missing_rooms'
            metric_unit='Count'
            metric_namespace='HAProxy'
            metric_value=result['room_missing_count']
            metric_data.append(create_metric_item(metric=metric, metric_value=metric_value, metric_unit=metric_unit, environment=environment))

            #split brain room count
            metric='split_brain_rooms'
            metric_unit='Count'
            metric_namespace='HAProxy'
            metric_value=result['split_brain_count']
            metric_data.append(create_metric_item(metric=metric, metric_value=metric_value, metric_unit=metric_unit, environment=environment))

            #stick table fix count for missing rooms
            metric='stick_table_fixes_missing'
            metric_unit='Count'
            metric_namespace='HAProxy'
            metric_value=len(result['fix_rooms_missing'])
            metric_data.append(create_metric_item(metric=metric, metric_value=metric_value, metric_unit=metric_unit, environment=environment))

            #stick table fix count for split brain
            metric='stick_table_fixes_split_brain'
            metric_unit='Count'
            metric_namespace='HAProxy'
            metric_value=len(result['fix_rooms_split_brain'])
            metric_data.append(create_metric_item(metric=metric, metric_value=metric_value, metric_unit=metric_unit, environment=environment))

    #missing room count
    metric='monitor_hosts'
    metric_unit='Count'
    metric_namespace='HAProxy'
    metric_value=len(tables)
    metric_data.append(create_metric_item(metric=metric, metric_value=metric_value, metric_unit=metric_unit, environment=environment))

    if len(stats)>0 and len(tables)>0:
        last_table=tables[-1]
        last_stats=stats[-1]


#        pprint(combined_stats['frontend_stats']['www-https'])
        
        log_print("Stat File count: %s"%len(stats))
        log_print("Table File count: %s"%len(tables))
        log_print("Total rooms: %s"%str(len(last_table['servers_by_room'])))
        log_print("Total sessions: %s"%str(combined_stats['server_stats']['totals']['scur']))
        log_print("Current server request rate: %s"%str(combined_stats['server_stats']['totals']['rate']))
        log_print("Current frontend request rate: %s"%str(combined_stats['frontend_stats']['www-https']['req_rate']))
        for server in list(last_table['rooms_by_server'].keys()):
            sname = 'UNKNOWN'
            scount = 0
            if (server in last_stats['server_stats']):
                sname = last_stats['server_stats'][server]['svname']
                scount = str(combined_stats['server_stats'][server]['scur'])
            sdetails= stat_details(stats,server,'scur')
            stdetails = stat_details(stats,server,'ttime')
            scdetails = stat_details(stats,server,'ctime')
            srdetails = stat_details(stats,server,'rtime')
            rdetails = stat_details(stats,server,'rate')
#            log_print("Shard: %s  room count: %s session count: %s%s  rate:%s timing total:%s connect:%s reply:%s"%(sname,str(len(last_table['rooms_by_server'][server])),scount,sdetails,rdetails,stdetails,scdetails,srdetails))

    #whatever happened, throw the stats we have discovered
    put_metrics(metric_data,namespace=metric_namespace,region=args.region)

if __name__ == "__main__":
    main()