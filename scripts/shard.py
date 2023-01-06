#!/usr/bin/env python

# pip install boto3 awscli

import argparse
import pprint
from hcvlib import *


parser = argparse.ArgumentParser(description='Produce a list of AMIs for use in jitsi infrastructure')
parser.add_argument('--new', action='store_true', default=False,
                   help='Outputs only the shard numbers which are next in the sequence.  Meant for use in other tools')
parser.add_argument('--list', action='store_true', default=False,
                   help='Lists shards for environment')
parser.add_argument('--list_releases', action='store_true', default=False,
                   help='Lists releases for environment')
parser.add_argument('--batch', action='store_true', default=False,
                   help='Batch mode used for --list action, outputs shards comma-separated, and silent when no shards found')
parser.add_argument('--versions', action='store_true', default=False,
                   help='Lists image versions for environment')
parser.add_argument('--shard_region', action='store_true', default=False,
                    help='Find shard region')
parser.add_argument('--shard_provider', action='store_true', default=False,
                    help='Find shard cloud provider')
parser.add_argument('--shard_tag', action='store_true', default=False,
                   help='Outputs shard tag for shard name')
parser.add_argument('--delete', action='store_true', default=False,
                   help='Marks a shard for deletion.  Will prompt for confirmation unless --yes is provided.  Requires --shard and --environment to be set')
parser.add_argument('--yes', action='store_true', default=False,
                   help='Auto-confirms shard deletion.  Destructive, use with care.')
parser.add_argument('--count', action='store', default=1,
                   help='Count of new shards, only for use with --new')
parser.add_argument('--environment', action='store',
                   help='Environment of shards', default=False)
parser.add_argument('--release', action='store', default=False,
                    help='Release number of shards with which to filter shards, only for use with --list')
parser.add_argument('--jvb_image_id', action='store',
                   help='JVB Image ID with which to filter shards, only for use with --list', default=False)
parser.add_argument('--signal_image_id', action='store',
                   help='Signal Image ID with which to filter shards, only for use with --list', default=False)
parser.add_argument('--inverse', action='store_true',
                   help='List returns all non-matches (release,jvb,signal image ids), only for use with --list', default=False)
parser.add_argument('--shard', action='store',
                   help='Shard name', default=False)
parser.add_argument('--oracle', action='store_true',
                   help='Keep oracle region name when detecting shard region', default=False)
parser.add_argument('--fix_alarms', action='store_true',
                   help='Fix Route53 alarms on all stacks in the environment', default=False)
parser.add_argument('--shard_state', action='store',
                   help='Shard state to filter', default=None)
parser.add_argument('--cloud_provider', action='store',
                   help='Cloud provider to filter', default=None)
parser.add_argument('--region', action='store',
                   help='AWS Region name, used for shard delete', default=False)
args = parser.parse_args()



if not args.environment:
    print("No environment provided, exiting...")
    exit(1)


#pprint.pprint(shard_numbers)
#loop through all regions

if args.fix_alarms:
    #always look in us-east-1 for cloudwatch alarms
    cloudwatch = boto3.resource('cloudwatch', region_name='us-east-1')
    client=boto3.client('cloudwatch',region_name='us-east-1')
    stacks = get_shard_stacks(environment=args.environment,shard=args.shard,region=args.region)
    for stack in stacks:
        if stack.outputs:
            print(('Checking Alarms for Stack: %s'%(stack.stack_name)))
            #got a health check ID, so confirm there's an alarm set up in us-east-1 for this ID
            alarm_prefix="%s-Route53XMPPHealthCheckFailedAlarm"%stack.stack_name
            out_alarms = []
            alarms=cloudwatch.alarms.filter(AlarmNamePrefix=alarm_prefix)
            for alarm in alarms:
                out_alarms.append(alarm)
            if len(out_alarms)==0:
                cloudwatch_regional =boto3.resource('cloudwatch', region_name=stack.region)
                #first go find the existing alarm
                alarms=cloudwatch_regional.alarms.filter(AlarmNamePrefix=alarm_prefix)
                out_alarms = [] 
                for alarm in alarms:
                    out_alarms.append(alarm)
                if len(out_alarms) == 0:
                    #no existing regional alarm, so make up the values
                    print('No existing regional alarm, failing...')
                else:
                    regional_alarm = out_alarms[0]
                    ok_actions = []
                    alarm_actions = []
                    insufficient_data_actions = []
                    for action in regional_alarm.ok_actions:
                        ok_actions.append(action.replace(stack.region,'us-east-1'))
                    for action in regional_alarm.alarm_actions:
                        alarm_actions.append(action.replace(stack.region,'us-east-1'))
                    for action in regional_alarm.insufficient_data_actions:
                        insufficient_data_actions.append(action.replace(stack.region,'us-east-1'))

                    #no alarm, so gotta go make one
                    response = client.put_metric_alarm(
                        AlarmName=regional_alarm.name,
                        AlarmDescription=regional_alarm.alarm_description,
                        ActionsEnabled=regional_alarm.actions_enabled,
                        OKActions=ok_actions,
                        AlarmActions=alarm_actions,
                        InsufficientDataActions=insufficient_data_actions,
                        MetricName=regional_alarm.metric_name,
                        Namespace=regional_alarm.namespace,
                        Statistic=regional_alarm.statistic,
                        Dimensions=regional_alarm.dimensions,
                        Period=regional_alarm.period,
                        Unit=str(regional_alarm.unit),
                        EvaluationPeriods=regional_alarm.evaluation_periods,
                        Threshold=regional_alarm.threshold,
                        ComparisonOperator=regional_alarm.comparison_operator
                    )
                    if response and 'ResponseMetadata' in response:
                        if response['ResponseMetadata']['HTTPStatusCode'] == 200:
                            print(('Alarm create SUCCESS: %s'%regional_alarm.name))
                        else:
                            print(('Alarm create FAILED: %s'%regional_alarm.name))
                            pprint.pprint(response)
                    else:
                        print('Alarm create FAILED: UNKNOWN')
                        pprint.pprint(response)
            else:
                #do nothing since we already have an alarm
                print(('Alarm %s already exists'%out_alarms[0]))
elif args.list_releases:
    releases = []
    stacks=get_shard_stacks(environment=args.environment)
    for stack in stacks:
        #pull shard name from tags, e.g. 'hcv-meetjitsi-us-east-1a-s0'
        release = extract_tag(stack.tags,RELEASE_NUMBER_TAG)
        releases.append(int(release))

    #sort the list (not really neccessary)
    releases = list(set(releases))
    releases.sort()
    #output space separate list for use in a bash loop
    delim = "\n"
    if args.batch:
        #batch mode, separate list with ,
        delim=" "
    print((delim.join(map(str,releases))))

elif args.new:
    shard_numbers = []
    stacks=get_shard_stacks(environment=args.environment)
    #build a list of current shard numbers for this environment
    for stack in stacks:
        #pull shard name from tags, e.g. 'hcv-meetjitsi-us-east-1a-s0'
        shard = extract_tag(stack.tags,SHARD_TAG)
        #break into array by '-', e.g. ['hcv','meetjitsi','us', 'east', '1a', 's0']
        shard_pieces = shard.split('-')
        #take the last part 's0'
        shard_number = shard_pieces[-1]
        #drop the 's' if our string starts with s, e.g. '0'
        if shard_number.startswith('s'):
            shard_number = shard_number[1:]
        #append newly discovered shard number to list as integer, e.g. 0
        shard_numbers.append(int(shard_number))

    #sort the list (not really neccessary)
    shard_numbers.sort()

    #new shard numbering
    out = []
    i = int(args.count)
    #search for a new shard number until we run out of items requested
    while (i>0):
        #start with shard 1
        check_number=1
        while check_number in shard_numbers:
            #keep incrementing until we find one that isn't in the list
            check_number = check_number + 1

        #add shard to our output and to shard_numbers collection so it won't be re-used
        out.append(check_number)
        shard_numbers.append(check_number)
        i=i-1

    #output space separate list for use in a bash loop
    print((' '.join(map(str,out))))
elif args.shard_region:
    if args.shard:
        map_to_aws = True
        if args.oracle:
            map_to_aws = False
        shard_region = shard_region_from_name(args.shard, map_to_aws)
        print(shard_region)
        exit(0)
    print('')
    exit(1)

elif args.delete:
    if not args.yes:
        #check for conirmation first
        print("Are you sure you want to delete shard? If so add --yes and run this command again.")
    else:
        #woops they said yes!
        if not args.shard:
            #phew we don't delete yet
            print("No shard provided, exiting...")
        if not args.region:
            #phew we don't delete yet
            print("No region provided, exiting...")

        #do we have a contender?
        cf = get_cloudformation_by_shard(shard_name=args.shard, region=args.region)
        if cf:
            #only the one, good
            print("DELETING: {}".format(cf.name))
            delete_route53_alarm(cf_region=args.region, stack_name=cf.name)
            try:
                terminate_jvb_instances_by_stack(region=args.region, stack_name=cf.name)
            except Exception as e:
                print('Exception while terminating instances, skipping instance termination for shard')
                print(e)

            cf.delete()
            print("DELETE STARTED, WAITING FOR COMPLETE ON {}".format(cf.name))
            wait_stack_delete_complete(cf.name, region=args.region)
            print("DELETE COMPLETED")
        else:
            print("Shard not found: {}".format(args.shard))
elif args.versions:
    #find all shards in the environment
    if not args.environment:
        print("No environment provided, exiting...")
        exit(1)
    else:
        signal_images = set()
        jvb_images = set()
        #grab all shards for the environment in all regions
        shard_instances = get_instances_by_role(role_name=SHARD_CORE_ROLE,environment_name=args.environment,shard_name=args.shard,shard_state=args.shard_state,release_number=args.release)
        for instance in shard_instances:
            ec2 = init_ec2(instance.region)
            shard = [t for t in instance.tags if t['Key'] == SHARD_TAG][0]['Value']
            shard_state = [t for t in instance.tags if t['Key'] == SHARD_STATE_TAG][0]['Value']
            signal_image_id = instance.image_id
            signal_image = ec2.Image(signal_image_id)
            signal_image_name = [t for t in signal_image.tags if t['Key'] == 'Version'][0]['Value']
            signal_images.add(signal_image_name)
            jvb_instances = get_instances_by_role(role_name=SHARD_JVB_ROLE,environment_name=args.environment,shard_name=shard,region=instance.region)
            for jvb_instance in jvb_instances:
                jvb_image_id=jvb_instance.image_id
                jvb_image = ec2.Image(jvb_image_id)
                jvb_image_name = [t for t in jvb_image.tags if t['Key'] == 'Version'][0]['Value']
                jvb_images.add(jvb_image_name)

        print(('export SIGNAL_VERSIONS=%s'%' '.join(signal_images)))
        print(('export JVB_VERSIONS=%s'%' '.join(jvb_images)))

elif args.list:
    #find all shards in the environment
    if not args.environment:
        print("No environment provided, exiting...")
        exit(1)
    else:
        output_shards = []
        if args.release and not args.inverse:
            cfs = get_cloudformation_by_release(args.environment,args.release,args.region,cloud_provider=args.cloud_provider)
            for cf in cfs:
                output_shards.append(cf.name)

        #grab all shards for the environment in all regions
        shard_instances = get_instances_by_role(role_name=SHARD_CORE_ROLE,environment_name=args.environment,region=args.region,cloud_provider=args.cloud_provider)
        for instance in shard_instances:
            region = instance.region
            shard = extract_tag(instance.tags, SHARD_TAG)
            if args.release:
                release_number = extract_tag(instance.tags, RELEASE_NUMBER_TAG)
                if release_number == args.release:
                    shard_matches = True
                else:
                    shard_matches = False
                if (shard_matches and not args.inverse) or (not shard_matches and args.inverse):
                    if args.shard_tag:
                        output_shards.append(shard)
                    else:
                        cf = get_cloudformation_by_shard(shard_name=shard, region=region)
                        if cf:
                            output_shards.append(cf.name)
            elif args.jvb_image_id or args.signal_image_id:
                signal_image_id = instance.image_id

                jvb_instances = get_instances_by_role(role_name=SHARD_JVB_ROLE,environment_name=args.environment,shard_name=shard,region=region)
                for jvb_instance in jvb_instances:
                    jvb_image_id=jvb_instance.image_id

                if args.jvb_image_id:
                    if jvb_image_id == args.jvb_image_id:
                        jvb_matches = True
                else:
                    jvb_matches = True

                if args.signal_image_id:
                    if signal_image_id == args.signal_image_id:
                        signal_matches = True
                else:
                    signal_matches = True

                if (signal_matches and jvb_matches and not args.inverse) or (args.inverse and ((not signal_matches and jvb_matches) or (not jvb_matches and signal_matches) or (not signal_matches and not jvb_matches))):
                    if args.shard_tag:
                        output_shards.append(shard)
                    else:
                        cf = get_cloudformation_by_shard(shard_name=shard, region=region)
                        if cf:
                            output_shards.append(cf.name)
            else:
                # no filters provided so just output the shard
                if args.shard_tag:
                    output_shards.append(shard)
                else:
                    cf = get_cloudformation_by_shard(shard_name=shard, region=region)
                    if cf:
                        output_shards.append(cf.name)

        if len(output_shards)>0:
            delim = "\n"
            if args.batch:
                delim = " "
            output_shards = list(set(output_shards))
            print(delim.join(output_shards));
        else:
            if not args.batch:
                print("No shards found.")
            if args.inverse:
                exit(0)
            else:
                exit(1)
#            print 'SIGNAL: %s' % instance.image_id
#            print 'JVB: %s'% jvb_image_id
elif args.shard_tag:
    cf = get_cloudformation_by_shard(shard_name=args.shard)
    if cf:
        print([t for t in cf.tags if t['Key'] == SHARD_TAG][0]['Value'])

elif args.shard_provider:
    cf = get_cloudformation_by_shard(shard_name=args.shard)
    if cf:
        print([t for t in cf.tags if t['Key'] == CLOUD_PROVIDER_TAG][0]['Value'])

else:
    if not args.shard:
        print("No shard provided, exiting...")
    else:
        print('Shard')
        cf = get_cloudformation_by_shard(shard_name=args.shard)
        pprint.pprint(cf)
        #output shard details