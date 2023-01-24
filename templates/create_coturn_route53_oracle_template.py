#!/usr/bin/env python

# pip install troposphere boto3
from templatelib import *
from troposphere import Parameter, Ref, Template, Join, Tags, Base64, Output, cloudformation, Split, Select
from troposphere.cloudformation import CustomResource
from troposphere.ec2 import EIP,SecurityGroup, SecurityGroupIngress, SecurityGroupEgress
from troposphere.autoscaling import Tag,AutoScalingGroup, LifecycleHook, LaunchConfiguration, BlockDeviceMapping, EBSBlockDevice, NotificationConfigurations, MetricsCollection
from troposphere.cloudwatch import Alarm, MetricDimension
from troposphere import events as cloudwatch_events
import troposphere.route53 as route53
import troposphere.awslambda as awslambda
import distutils.util
from troposphere.policies import (
    AutoScalingReplacingUpdate, AutoScalingRollingUpdate, UpdatePolicy, CreationPolicy, ResourceSignal
)

def add_parameters():
    dns_zone_id = t.add_parameter(Parameter(
        "DnsZoneID",
        Description="DnsZoneID",
        Type="String",
    ))

    coturn_dns_name = t.add_parameter(Parameter(
        "TURNDnsName",
        Description="TURN dns name",
        Type="String",
    ))

    coturn_dns_alias_name = t.add_parameter(Parameter(
        "TURNDnsAliasName",
        Description="Alias for the TURN dns",
        Type="String",
    ))

    region_alias_param = t.add_parameter(Parameter(
        "RegionAlias",
        Description="Alias for AWS Region",
        Type="String",
    ))

    coturn_health_alarm_sns_param = t.add_parameter(Parameter(
        "CoturnHealthAlarmSNS",
        Description="SNS topic for ASG Alarms related to Coturn",
        Type="String",
        Default="Coturn-Health-Check-List"
    ))

    coturn_lambda_function_name = t.add_parameter(Parameter(
        'CoturnLambdaFunctionName',
        Description= "Lambda function name that CF custom resources use when create a stack",
        Type= "String",
        Default= "all-cf-update-route53",
    ))

    tag_name_param= t.add_parameter(Parameter(
        "TagName",
        Description="Tag: Name",
        Type="String",
        Default="hc-video-coturn"
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

    tag_environment_param = t.add_parameter(Parameter(
        "TagEnvironment",
        Description="Tag: environment",
        Type="String",
        Default="hcv-chaos"
    ))

    tag_domain_name_param = t.add_parameter(Parameter(
        "TagDomainName",
        Description="Tag: domain_name",
        Type="String",
        Default="jitsi.net"
    ))

    tag_git_branch_param = t.add_parameter(Parameter(
        "TagGitBranch",
        Description="Tag: git_branch",
        Type="String",
        Default="main"
    ))

def add_route53_records(t, oracle_public_ip_list, route53_turn_tcp=False):

    # resource_records = [rs for rs in resource_records if rs!=',']

    route53_resource_names = []
    route53_reference_name_pool = []

    # Must add '1' as suffix for route53_latency_alias name if we want to be backward compatible with the resource that is already created; same for ipv6
    add_route53_latency_alias = t.add_resource(route53.RecordSetType(
        'TURNRoute53LatencyAliasIpv41',
        AliasTarget=route53.AliasTarget(
            HostedZoneId=Ref('DnsZoneID'),
            DNSName=Ref('TURNDnsName'),
            EvaluateTargetHealth=True
        ),
        HostedZoneId=Ref('DnsZoneID'),
        Region=Ref("AWS::Region"),
        Comment='DNS record for TURN server',
        Name=Ref('TURNDnsAliasName'),
        Type="A",
        SetIdentifier=Join(" ", [ 'coturn',Ref("AWS::Region") ]),
    ))

    tmp_number=1
    for public_ip in oracle_public_ip_list:

        route53_resource_name = 'Route53TURNHealthCheck'+str(tmp_number)
        route53_record_name = 'TURNRoute53Record'+str(tmp_number)

        add_route53_record = t.add_resource(route53.RecordSetType(
            route53_record_name,
            HostedZoneId=Ref('DnsZoneID'),
            Comment='DNS record for TURN server',
            Name=Ref('TURNDnsName'),
            Type="A",
            TTL="60",
            Weight="10",
            SetIdentifier=Join(" ", [ 'coturn',Ref("AWS::Region"),route53_record_name ]),
            ResourceRecords=[public_ip],
            HealthCheckId=Ref(route53_resource_name)
        ))

        if (route53_turn_tcp):
            route53_turn_health_check = t.add_resource(route53.HealthCheck(
                route53_resource_name,
                HealthCheckConfig= route53.HealthCheckConfiguration(
                    IPAddress=public_ip,
                    Port= 443,
                    Type= "TCP",
                    RequestInterval= 30,
                    FailureThreshold= 3
                ),
                HealthCheckTags= Tags(
                    Name= Join("-", [Ref('TURNDnsName'),"R53Health",tmp_number]),
                    Environment=Ref("TagEnvironmentType"),
                    Service=Ref("TagService"),
                    Owner=Ref("TagOwner"),
                    Team=Ref("TagTeam"),
                    Product=Ref("TagProduct"),
                    environment=Ref("TagEnvironment"),
                    domain=Ref("TagDomainName")
                )
            ))
        else:
            route53_turn_health_check = t.add_resource(route53.HealthCheck(
                route53_resource_name,
                HealthCheckConfig= route53.HealthCheckConfiguration(
                    IPAddress=public_ip,
                    Port= 443,
                    Type= "HTTP",
                    FullyQualifiedDomainName=Ref('TURNDnsName'),
                    ResourcePath= "/",
                    RequestInterval= 30,
                    FailureThreshold= 3
                ),
                HealthCheckTags= Tags(
                    Name= Join("-", [Ref('TURNDnsName'),"R53Health",tmp_number]),
                    Environment=Ref("TagEnvironmentType"),
                    Service=Ref("TagService"),
                    Owner=Ref("TagOwner"),
                    Team=Ref("TagTeam"),
                    Product=Ref("TagProduct"),
                    environment=Ref("TagEnvironment"),
                    domain=Ref("TagDomainName")
                )
            ))

        route53_resource_names.append(route53_resource_name)
        route53_reference_name_pool.append({"Ref":route53_resource_name})
        tmp_number += 1


def create_coturn_template(filepath, oracle_public_ip_list=[], route53_turn_tcp=False):

    global t

    t = Template()
    t.add_version("2010-09-09")
    t.add_description(
        "Template for the provisioning Oracle TURN Route53 resources"
    )

    # Add params
    add_parameters()

    add_route53_records(t,oracle_public_ip_list, route53_turn_tcp=route53_turn_tcp)

    tmp_number=1
    for public_ip in oracle_public_ip_list:
        t.add_output([
            Output(
                "OraclePublicIP"+str(tmp_number),
                Description="Oracle Coturn Public IP",
                Value=public_ip,
            )
        ])
        tmp_number+=1

    write_template_json(filepath=filepath, t=t)


def main():
    parser = argparse.ArgumentParser(description='Create Coturn stack template')
    parser.add_argument('--region', action='store',
                        help='AWS region)', default=False, required=True)
    parser.add_argument('--regionalias', action='store',
                        help='AWS region)', default=False)
    parser.add_argument('--filepath', action='store',
                        help='Path to tenmplate file', default=False, required=False),
    parser.add_argument('--turn_tcp', action='store_true',
                        help='Flag to make TCP health checks instead of HTTP', default=False, required=False),
    parser.add_argument('--oracle_public_ip_list',action='store', required=True)
    args = parser.parse_args()

    if not args.region:
        print('No AWS region specified, exiting...')
        exit(1)
    elif not args.filepath:
        print ('No path to template file')
        exit(2)
    else:
        oracle_public_ip_as_array=args.oracle_public_ip_list.split(',')
        create_coturn_template(filepath=args.filepath, oracle_public_ip_list=oracle_public_ip_as_array, route53_turn_tcp=args.turn_tcp)


if __name__ == '__main__':
    main()
