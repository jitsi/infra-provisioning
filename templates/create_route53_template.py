#!/usr/bin/env python

# pip install troposphere boto3

import boto3, re, argparse, json
from troposphere import Parameter, Ref, Template
from troposphere import Join
from troposphere.route53 import RecordSetType, AliasTarget, GeoLocation

def create_default_geo_alias(hosted_zone_id, domain, environment,record_prefix,region_suffix,default_suffix):
    cont_code = {'CountryCode': '*'}
    client = boto3.client('route53')

    response = client.change_resource_record_sets(
        HostedZoneId=hosted_zone_id,
        ChangeBatch={
            'Comment': 'Create default alias for %s-%s'%(record_prefix,region_suffix),
            'Changes': [{
                    'Action': 'CREATE',
                    'ResourceRecordSet': {
                        'Name': "%s-%s.%s"%(record_prefix,region_suffix,domain),
                        'Type': 'A',
                        'SetIdentifier': environment + ' default',
                        'GeoLocation': cont_code,
                        'AliasTarget': {
                                'HostedZoneId': hosted_zone_id,
                                'DNSName': "%s-%s.%s"%(record_prefix,default_suffix,domain),
                                'EvaluateTargetHealth': False
                            }
                        }
                },
            ]
        }
    )
def pull_alb_per_environment(region, environment, shardbase, stackprefix):
    client = boto3.client( 'elbv2', region_name=region )
    response = client.describe_load_balancers()

    alb_zoneid_per_env = {}

    lb_arns = []
    lbs_by_index=[]

    #build a list of names and complete descriptions
    for r in response["LoadBalancers"]:
        lb_arns.append(r["LoadBalancerArn"])
        lbs_by_index.append(r)

    if lb_arns:
        #add tags to LB list, append them to complete descriptions
        lb_tags = client.describe_tags(ResourceArns=lb_arns)
        for t in lb_tags['TagDescriptions']:
            i=lb_arns.index(t['ResourceArn'])
            lbs_by_index[i]['Tags']={}
            for tv in t['Tags']:
                lbs_by_index[i]['Tags'][tv['Key']]=tv['Value']

        for i in lbs_by_index:
            #make sure we only use the appropriate ELB, not the jigasi ELB or a different environments ELB
            if ('environment' in i['Tags']) and (i['Tags']['environment'] == environment) and ('stack-role' in i['Tags']) and (i['Tags']['stack-role'] == 'haproxy'):
                #make sure we are in the right VPC within the region
                if re.search(stackprefix, i['Tags']["Name"]):
                    alb_zoneid_per_env[(i["CanonicalHostedZoneId"])] = i["DNSName"]

    return alb_zoneid_per_env

def pull_elb_per_environment(region, environment, shardbase, stackprefix):
    """ Pull ELB id and name per region and environment

    :param region:
    :param shardbase:
    :param stackprefix:
    :return list of elb_id:
    """
    client = boto3.client( 'elb', region_name=region )
    response = client.describe_load_balancers()

    elb_zoneid_per_env = {}

    lb_names = []
    lbs_by_index=[]
    #build a list of names and complete descriptions
    for r in response["LoadBalancerDescriptions"]:
        lb_names.append(r["LoadBalancerName"])
        lbs_by_index.append(r)

    if lb_names:
        #add tags to LB list, append them to complete descriptions
        lb_tags = client.describe_tags(LoadBalancerNames=lb_names)
        for t in lb_tags['TagDescriptions']:
            i=lb_names.index(t['LoadBalancerName'])
            lbs_by_index[i]['Tags']={}
            for tv in t['Tags']:
                lbs_by_index[i]['Tags'][tv['Key']]=tv['Value']

        for i in lbs_by_index:
            #make sure we only use the appropriate ELB, not the jigasi ELB or a different environments ELB
            if ('environment' in i['Tags']) and (i['Tags']['environment'] == environment) and ('aws:cloudformation:logical-id' in i['Tags']) and (i['Tags']['aws:cloudformation:logical-id'] == 'ProxyELB'):
                #make sure we are in the right VPC within the region
                if re.search(stackprefix, i["LoadBalancerName"]):
                    elb_zoneid_per_env[(i["CanonicalHostedZoneNameID"])] = i["CanonicalHostedZoneName"]

    return elb_zoneid_per_env

def pull_all_regions(region):
    """ Pull resource location and sublocation per region

    :param region:
    :return list :
    """

    us_regions = {'us-east-1': [{'countryCode':'US'},{'continentCode':['NA']},{'subdivisionCode':['']}],
                  'us-west-1': [{'countryCode':'US'},{'continentCode':['']},{'subdivisionCode':['AK', 'AZ', 'CA', 'CO', 'HI', 'ID', 'MT', 'NM', 'NV', 'OR', 'UT', 'WA', 'WY']}],
                  'us-west-2': [{'countryCode':'US'},{'continentCode':['']},{'subdivisionCode':['AK', 'AZ', 'CA', 'CO', 'HI', 'ID', 'MT', 'NM', 'NV', 'OR', 'UT', 'WA', 'WY']}]}

    other_regions = {'ap-south-1':[{'countryCode':''},{'continentCode':['AS', 'OC']},{'subdivisionCode':['']}],
                     'eu-west-2': [{'countryCode':''},{'continentCode':['EU']},{'subdivisionCode':['']}],
                     'eu-west-1': [{'countryCode':'IE'},{'continentCode':['EU']},{'subdivisionCode':['']}],
                     'ap-northeast-2': [{'countryCode':''},{'continentCode':['']},{'subdivisionCode':['']}],
                     'ap-northeast-1': [{'countryCode':''},{'continentCode':['']},{'subdivisionCode':['']}],
                     'sa-east-1': [{'countryCode':''},{'continentCode':['']},{'subdivisionCode':['']}],
                     'ca-central-1': [{'countryCode':'CA'},{'continentCode':['NA']},{'subdivisionCode':['']}],
                     'ap-southeast-1': [{'countryCode':''},{'continentCode':['AS', 'OC']},{'subdivisionCode':['']}],
                     'ap-southeast-2': [{'countryCode':''},{'continentCode':['AS', 'OC']},{'subdivisionCode':['']}],
                     'eu-central-1': [{'countryCode':''},{'continentCode':['EU']},{'subdivisionCode':['']}]}

    if re.search('us',region):
        return us_regions.get(region)
    else:
        return other_regions.get(region)

def pull_accelerator_details(accelerator_arn):
    client = boto3.client('globalaccelerator')
    response = client.describe_accelerator(
        AcceleratorArn=accelerator_arn
    )
    if 'Accelerator' in response:
        return response['Accelerator']
    else:
        return False

def generate_template_for_us(elb_zoneid, region):
    """ Create alias for resource with sublocation in the GeoLocation.
        It uses if we are IN US region.

    :param elb_zoneid:
    :return:
    """
    alias_num = 0
    for id, elb_name in list(elb_zoneid.items()):
        if len(subdivision_code) > 0 and subdivision_code[0] != '':
            for s in subdivision_code:
                name = "AliasDNSRecords" +s + str(alias_num)
                aliasname = t.add_resource(RecordSetType(
                    name,
                    HostedZoneId=Ref(public_dns_hosted_zone_id_param),
                    Comment="Create alias for the elb per env",
                    SetIdentifier=Join(" ", [Ref("Environment"), Ref(region_alias_param), s] ),
                    Name=Join("",[Ref("DNSRecordPrefix"),'-',Ref("DNSRecordRegionSuffix"),'.',Ref("DomainName")]),
                    Type="A",
                    GeoLocation=GeoLocation(
                        CountryCode=country_code,
                        SubdivisionCode=s,
                    ),
                    AliasTarget=AliasTarget(
                        HostedZoneId=id,
                        DNSName="dualstack."+ elb_name,
                        EvaluateTargetHealth=True
                    )
                ))
                alias_num += 1
        else:
            for c in continent_code:
                name = "AliasDNSRecords" +c + str(alias_num)
                aliasname = t.add_resource(RecordSetType(
                    name,
                    HostedZoneId=Ref(public_dns_hosted_zone_id_param),
                    Comment="Create alias for the elb per env",
                    SetIdentifier=Join(" ", [Ref("Environment"), Ref(region_alias_param), c] ),
                    Name=Join("",[Ref("DNSRecordPrefix"),'-',Ref("DNSRecordRegionSuffix"),'.',Ref("DomainName")]),
                    Type="A",
                    GeoLocation=GeoLocation(
                    ContinentCode=c,
                     ),
                    AliasTarget=AliasTarget(
                        HostedZoneId=id,
                        DNSName="dualstack."+ elb_name,
                        EvaluateTargetHealth=True
                    )
                ))
                alias_num += 1

def generate_record_for_region(elb_zoneid, alb_zoneid, region, accelerator_ips=False):
    alias_num = 0
    if len(alb_zoneid) == 0:
        for id, elb_name in list(elb_zoneid.items()):
            name = "AliasDNSRecordsLatency%s"%alias_num
            aliasname = t.add_resource(RecordSetType(
                name,
                HostedZoneId=Ref(public_dns_hosted_zone_id_param),
                Comment="Create alias for the elb per env",
                SetIdentifier=Join(" ", [Ref("Environment"), Ref(region_alias_param), "ELB", alias_num]),
                Name=Join("",[Ref("DNSRecordPrefix"),'-',Ref("DNSRecordRegionSuffix"),'.',Ref(domain_name_param)]),
                Type="A",
                Region=region,
                AliasTarget=AliasTarget(
                    HostedZoneId=id,
                    DNSName="dualstack."+ elb_name,
                    EvaluateTargetHealth=True
                )
            ))
    else:
        for id, alb_dns in list(alb_zoneid.items()):
            name = "AliasDNSRecordsLatency%s"%alias_num
            # check if we have no accelerator IPs, if not then fall back to ALB alias
            # no global accelerator support yet in sa-east-1, so fallback to alias for that region
            if region == 'sa-east-1' or not accelerator_ips:
                aliasnamev4 = t.add_resource(RecordSetType(
                    name,
                    HostedZoneId=Ref(public_dns_hosted_zone_id_param),
                    Comment="ipv4 Alias for the ALB",
                    SetIdentifier=Join(" ", [Ref("Environment"), Ref(region_alias_param), "ALB", alias_num]),
                    Name=Join("",[Ref("DNSRecordPrefix"),'-',Ref("DNSRecordRegionSuffix"),'.',Ref(domain_name_param)]),
                    Type="A",
                    Region=region,
                    AliasTarget=AliasTarget(
                        HostedZoneId=id,
                        DNSName="dualstack."+ alb_dns,
                        EvaluateTargetHealth=True
                    )
                ))
            else:
                # use the accelerator IPs for DNS instead of ALB alias
                aliasnamev4 = t.add_resource(RecordSetType(
                    name,
                    HostedZoneId=Ref(public_dns_hosted_zone_id_param),
                    Comment="ipv4 for global accelerator",
                    SetIdentifier=Join(" ", [Ref("Environment"), Ref(region_alias_param), "ALB", alias_num]),
                    Name=Join("",[Ref("DNSRecordPrefix"),'-',Ref("DNSRecordRegionSuffix"),'.',Ref(domain_name_param)]),
                    Type="A",
                    Region=region,
                    TTL=300,
                    ResourceRecords=accelerator_ips
                ))

            name = "AliasAAAADNSRecordsLatency%s"%alias_num
            aliasnamev6 = t.add_resource(RecordSetType(
                name,
                HostedZoneId=Ref(public_dns_hosted_zone_id_param),
                Comment="ipv6 Alias for the ALB",
                SetIdentifier=Join(" ", [Ref("Environment"), Ref(region_alias_param), "ALB", alias_num]),
                Name=Join("",[Ref("DNSRecordPrefix"),'-',Ref("DNSRecordRegionSuffix"),'.',Ref(domain_name_param)]),
                Type="AAAA",
                Region=region,
                AliasTarget=AliasTarget(
                    HostedZoneId=id,
                    DNSName="dualstack."+ alb_dns,
                    EvaluateTargetHealth=True
                )
            ))
            #don't loop here, even if we got more than one, since more than one latency record will fail
            break



def generate_alias_for_other(elb_zoneid, region):
    """ Create alias for resource without sublocation in the GeoLocation.
        It uses if we are NOT in US region.

     :param elb_zoneid:
     :return:
     """

    alias_num = 0
    for id, elb_name in list(elb_zoneid.items()):
        for c in continent_code:
            name = "AliasDNSRecords" + c + str(alias_num)
            aliasname = t.add_resource(RecordSetType(
                name,
                HostedZoneId=Ref(public_dns_hosted_zone_id_param),
                Comment="Create alias for the elb per env",
                SetIdentifier=Join(" ", [Ref("Environment"), Ref(region_alias_param), c]),
                Name=Join("",[Ref("DNSRecordPrefix"),'-',Ref("DNSRecordRegionSuffix"),'.',Ref(domain_name_param)]),
                Type="A",
                GeoLocation=GeoLocation(
                    ContinentCode=c,
                ),
                AliasTarget=AliasTarget(
                    HostedZoneId=id,
                    DNSName="dualstack."+ elb_name,
                    EvaluateTargetHealth=True
                )
            ))
            alias_num += 1

def create_route53_template(elb_zoneid, alb_zoneid, filepath, region_codes, region, region_suffix, route_method='geo', accelerator=False):

    global t
    global region_alias_param
    global domain_name_param
    global public_dns_hosted_zone_id_param
    global country_code
    global continent_code
    global subdivision_code

    if accelerator:
        accelerator_ips = []
        accelerator_details = pull_accelerator_details(accelerator)
        for s in accelerator_details['IpSets']:
            accelerator_ips = accelerator_ips + s['IpAddresses']

        # if no ips were found then accelerator isn't available
        if len(accelerator_ips) == 0:
            accelerator_ips=False

    else:
        accelerator_ips = False

    country_code = region_codes[0].get("countryCode")
    continent_code = region_codes[1].get("continentCode")
    subdivision_code = region_codes[2].get("subdivisionCode")

    weight = 10

    t = Template()

    t.add_version("2010-09-09")

    t.add_description(
        "Template for the provisioning Route53 resources for the HC Video"
    )

    domain_name_param = t.add_parameter(Parameter(
     "DomainName",
        Description="HC Video internal domain name "
                    "access to the instance",
        Type="String",
    ))

    record_prefix_param = t.add_parameter(Parameter(
     "DNSRecordPrefix",
        Description="unique prefix for name part of DNS record",
        Type="String",
        Default="video",
    ))


    record_region_suffix_param = t.add_parameter(Parameter(
     "DNSRecordRegionSuffix",
        Description="suffix for regional DNS records",
        Type="String",
        Default=region_suffix,
    ))

    record_default_suffix_param = t.add_parameter(Parameter(
     "DNSRecordDefaultSuffix",
        Description="suffix for regional DNS records",
        Type="String",
        Default="default",
    ))


    public_dns_hosted_zone_id_param = t.add_parameter(Parameter(
        "PublicDNSHostedZoneId",
        Description="HC Video public hosted zone Id",
        Type="String",
    ))

    stack_name_prefix_param = t.add_parameter(Parameter(
        "StackNamePrefix",
        Description="Prefix for stack",
        Type="String",
        Default="vaas",
    ))

    region_alias_param = t.add_parameter(Parameter(
        "RegionAlias",
        Description="Alias for AWS Region",
        Type="String",
    ))

    environment_param = t.add_parameter(Parameter(
        "Environment",
        Description="Environment",
        Type="String",
    ))

    tag_environment_type_param = t.add_parameter(Parameter(
        "TagEnvironmentType",
        Description="Tag: EnvironmentType",
        Type="String",
        Default="dev"
    ))

    tag_product_param = t.add_parameter(Parameter(
        "TagProduct",
        Description="Tag: Product",
        Type="String",
        Default="meetings"
    ))

    tag_service_param = t.add_parameter(Parameter(
        "TagService",
        Description="Tag: Service",
        Type="String",
        Default="jitsi-meet"
    ))

    tag_team_param = t.add_parameter(Parameter(
        "TagTeam",
        Description="Tag: Team",
        Type="String",
        Default="meet@8x8.com"
    ))

    tag_owner_param = t.add_parameter(Parameter(
        "TagOwner",
        Description="Tag: Owner",
        Type="String",
        Default="Meetings"
    ))

    if route_method=='geo':
        #for the geo routing method, create geo routes as well as a weighted list for failover/default
        if country_code == "US":
            generate_template_for_us(elb_zoneid, region)
        else:
            generate_alias_for_other(elb_zoneid, region)

        for id, name in list(elb_zoneid.items()):
            defaultDNSRecord = t.add_resource(RecordSetType(
                "DefaultDNSRecord",
                HostedZoneId= Ref(public_dns_hosted_zone_id_param),
                Comment="Create default record per ELB in a region",
                Name=Join("", [Ref("DNSRecordPrefix"),"-",Ref("DNSRecordDefaultSuffix"),".", Ref(domain_name_param)]),
                Type="A",
                SetIdentifier=Join(" ", [Ref("Environment"), Ref(region_alias_param),"default"]),
                Weight=weight,
                AliasTarget = AliasTarget(
                    HostedZoneId =  id,
                    DNSName = "dualstack."+ name,
                    EvaluateTargetHealth = True)
                )
            )

    elif route_method=='latency':
        #latency based routing does not require a default, routes to the nearest healthy shard
        generate_record_for_region(elb_zoneid, alb_zoneid, region, accelerator_ips)

    data = json.loads(t.to_json())

    with open (filepath, 'w+') as outfile:
        json.dump(data, outfile)

def main():
    parser = argparse.ArgumentParser(description='Create the AWS Route53 template')
    parser.add_argument('--region', action='store',
                        help='AWS region)', default=False, required=True)
    parser.add_argument('--regionalias', action='store',
                        help='AWS region alias)', default=False)
    parser.add_argument('--shardbase', action='store',
                        help='Shard Base name', default=False, required=True)
    parser.add_argument('--stackprefix', action='store',
                        help='Stack prefix name', default=False, required=False)
    parser.add_argument('--create_default_geo_alias', action='store',
                        help='Create default Geo alias for PREFIX-allregions ', default='False', required=False)
    parser.add_argument('--hosted_zone_id', action='store',
                        help='Hosted Zone ID', default=False, required=False)
    parser.add_argument('--domain', action='store',
                        help='Domain name', default=False, required=False)
    parser.add_argument('--environment', action='store',
                        help='Environment name', default=False, required=False)
    parser.add_argument('--region_suffix', action='store',
                        help='Suffix for region record', default=False, required=False)
    parser.add_argument('--route_method', action='store',
                        help='Routing method to use.  Currently supports geo and latency', default='geo', required=False)
    parser.add_argument('--default_suffix', action='store',
                        help='Suffix for default record', default='default', required=False)
    parser.add_argument('--filepath', action='store',
                        help='Path to tenmplate file', default=False, required=False)
    parser.add_argument('--skipalb', action='store_true',
                        help='Flag to skip ALB search', default=False)
    parser.add_argument('--accelerator', action='store',
                        help='Name of global accelerator if in use', default=False)

    args = parser.parse_args()

    if not args.region_suffix:
        if args.route_method=='latency':
            args.region_suffix = 'latency'
        else:
            args.region_suffix = 'allregions'

    if not args.region:
        print('No AWS region specified, exiting...')
        exit(1)
    elif not args.environment:
        print('No Environment specified, exiting...')
        exit(2)
    elif not args.shardbase:
        print('No ShardBase specified, exiting...')
        exit(2)
    elif args.create_default_geo_alias == "True":
        create_default_geo_alias(hosted_zone_id=args.hosted_zone_id, domain=args.domain, environment=args.environment, record_prefix=args.shardbase, region_suffix=args.region_suffix, default_suffix=args.default_suffix)
    else:
        if not args.filepath:
            print ('No path to template file')
            exit(3)
        else:
            alb_zoneid = {}
            elb_zoneid = pull_elb_per_environment(region=args.region, environment=args.environment, shardbase=args.shardbase, stackprefix=args.stackprefix)
            if not args.skipalb:
                alb_zoneid = pull_alb_per_environment(region=args.region, environment=args.environment, shardbase=args.shardbase, stackprefix=args.stackprefix)
            create_route53_template(elb_zoneid=elb_zoneid, alb_zoneid=alb_zoneid, filepath=args.filepath,region=args.region, region_suffix=args.region_suffix, region_codes=pull_all_regions(region=args.region), route_method=args.route_method, accelerator=args.accelerator)

if __name__ == '__main__':
    main()
