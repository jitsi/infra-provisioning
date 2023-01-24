#!/usr/bin/env python

# pip install troposphere boto3

import sys, os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from templatelib import *
from create_dynamo_db import *
from create_kinesis import kinesis_main
from create_sqs import sqs_main


def add_parameters():

    key_name_param = t.add_parameter(Parameter(
        "KeyName",
        Description="Name of an existing EC2 KeyPair to enable SSH access to the ec2 hosts",
        Type="String",
        MinLength=1,
        MaxLength=64,
        AllowedPattern="[-_ a-zA-Z0-9]*",
        ConstraintDescription="can contain only alphanumeric characters, spaces, dashes and underscores."

    ))

    stack_name_prefix_param = t.add_parameter(Parameter(
        "StackNamePrefix",
        Description="Prefix for stack",
        Type="String",
        Default="vaas",
    ))

    domain_name_param = t.add_parameter(Parameter(
        "DomainName",
        Description="HC Video internal domain name",
        Type="String",
        Default="hcv-us-east-1.infra.jitsi.net"
    ))

    shard_id = t.add_parameter(Parameter(
        'ShardId',
        Description= "HC Video shard Id",
        Type= "Number",
        Default= "0",

    ))

    public_dns_hosted_zone_id_param = t.add_parameter(Parameter(
        "PublicDNSHostedZoneId",
        Description="HC Video public hosted zone Id",
        Type="String",
    ))

    jvb_associate_public_ip_address = t.add_parameter(Parameter(
        "JVBAssociatePublicIpAddress",
        Description="Associate Public IP address for JVB instance",
        Type='String',
        Default='false'
    ))

    signal_image_id = t.add_parameter(Parameter(
        "SignalImageId",
        Description= "Signal server instance AMI id",
        Type=  "AWS::EC2::Image::Id",
        ConstraintDescription= "must be a valid and allowed AMI id."
    ))

    jvb_availability_zone_letter = t.add_parameter(Parameter(
        "JVBAvailabilityZoneLetter",
        Description=  "AZ letter for JVB ASG",
        AllowedValues= ["a","b"],
        Type= "String",
        ConstraintDescription= "must be a valid AZ zone."
    ))

    jvb_availability_zone = t.add_parameter(Parameter(
        "JVBAvailabilityZone",
        Description= "AZ for JVB ASG",
        Type="AWS::EC2::AvailabilityZone::Name",
        Default= "us-east-1a",
        ConstraintDescription="must be a valid and allowed availability zone."
    ))

    app_instance_type = t.add_parameter(Parameter(
        "AppInstanceType",
        Description= "App server instance type",
        Type= "String",
        Default= "m3.large",
        AllowedValues= [
                             "t1.micro",
                             "t2.small",
                             "t2.medium",
                             "m1.small",
                             "m1.medium",
                             "m1.large",
                             "m3.large",
                             "m5.large",
                             "m4.large"
                         ],
        ConstraintDescription= "must be a valid and allowed EC2 instance type."
    ))

    app_instance_virtualization = t.add_parameter(Parameter(
        'AppInstanceVirtualization',
        Description= "App server instance virtualization",
        Type= "String",
        Default= "PV",
        AllowedValues= ["HVM","PV"],
        ConstraintDescription= "Must be a valid and allowed virtualization type."
    ))

    jvb_image_id = t.add_parameter(Parameter(
        "JVBImageId",
        Description= "JVB server instance AMI id",
        Type= "AWS::EC2::Image::Id",
        ConstraintDescription= "must be a valid and allowed AMI id."
    ))

    jvb_instance_type = t.add_parameter(Parameter(
        "JVBInstanceType",
        Description="JVB server instance type",
        Type= "String",
        Default= "t3.large",
        AllowedValues= [
                "t2.micro",
                "t2.medium",
                "t2.large",
                "t2.xlarge",
                "t3.micro",
                "t3.medium",
                "t3.large",
                "t3.xlarge",
                "c4.large",
                "c4.xlarge",
                "c5.xlarge"
        ],
        ConstraintDescription= "must be a valid and allowed EC2 instance type."
    ))

    jvb_instance_tenancy = t.add_parameter(Parameter(
        "JVBPlacementTenancy",
        Description="JVB placement tenancy",
        Type= "String",
        Default= "dedicated",
        AllowedValues= [
                "default",
                "dedicated"
        ],
        ConstraintDescription= "must be a valid and allowed EC2 instance placement tenancy."
    ))

    jvb_instance_virtualization = t.add_parameter(Parameter(
        "JVBInstanceVirtualization",
        Description= "JVB server instance virtualization",
        Type= "String",
        Default= "HVM",
        AllowedValues = [
            "HVM",
            "PV"
        ],
        ConstraintDescription= "Must be a valid and allowed virtualization type."
    ))

    jvb_health_alarm_sns = t.add_parameter(Parameter(
        "JVBHealthAlarmSNS",
        Description="SNS topic for ASG Alarms related to JVB",
        Type= "String",
        Default= "chaos-Health-Check-List"
    ))

    jvb_asg_alarm_sns = t.add_parameter(Parameter(
        "JVBASGAlarmSNS",
        Description= "SNS topic for ASG Alarms related to JVB",
        Type= "String",
        Default= "chaos-ASG-alarms"

    ))

    page_durty_sns_topic_name = t.add_parameter(Parameter(
        "PagerDutySNSTopicName",
        Description= "String Name for SNS topic to notify PagerDuty",
        Type= "String",
        Default= "PagerDutyAlarms"
    ))

    app_server_security_instance_profile = t.add_parameter(Parameter(
        "AppServerSecurityInstanceProfile",
        Description= "Core Security Instance Profile",
        Type= "String",
        Default= "HipChatVideo-SignalNode"
    ))

    jvb_server_security_instance_profile = t.add_parameter(Parameter(
        "JVBServerSecurityInstanceProfile",
        Description= "JVB Security Instance Profile",
        Type= "String",
        Default= "HipChatVideo-VideoBridgeNode"
    ))

    region_alias_param = t.add_parameter(Parameter(
        "RegionAlias",
        Description="Alias for AWS Region",
        Type="String",
    ))


    tag_name_param= t.add_parameter(Parameter(
        "TagName",
        Description="Tag: Name",
        Type="String",
        Default="hc-video"
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

    tag_public_domain_name_param = t.add_parameter(Parameter(
        "TagPublicDomainName",
        Description="Tag: public_domain_name",
        Type="String",
        Default="chaos.jitsi.net"
    ))

    tag_domain_name_param = t.add_parameter(Parameter(
        "TagDomainName",
        Description="Tag: domain_name",
        Type="String",
        Default="chaos.jitsi.net"
    ))

    tag_shard_param = t.add_parameter(Parameter(
        "TagShard",
        Description="Tag: shard",
        Type="String",
        Default="hcv-chaos-default"
    ))

    tag_git_branch_param = t.add_parameter(Parameter(
        "TagGitBranch",
        Description="Tag: git_branch",
        Type="String",
        Default="main"
    ))
    
    tag_shard_unseen_param = t.add_parameter(Parameter(
        "TagShardUnseen",
        Description="Tag: shard-unseen",
        Type="String",
        Default="true"
    ))


def create_jitsi_cloud_api_template(filepath):

    t = create_template()

    #Add services
    dynamo_db_main(t)
    kinesis_main(t)
    sqs_main(t)

    write_template_json(filepath=filepath, t=t)


def main():
    parser = argparse.ArgumentParser(description='Create Haproxy stack template')
    parser.add_argument('--region', action='store',
                        help='AWS region)', default=False, required=True)
    parser.add_argument('--regionalias', action='store',
                        help='AWS region alias)', default=False)
    parser.add_argument('--filepath', action='store',
                        help='Path to tenmplate file', default=False, required=False)

    args = parser.parse_args()

    if not args.region:
        print('No AWS region specified, exiting...')
        exit(1)
    elif not args.filepath:
        print ('No path to template file')
        exit(2)
    else:
        if not args.regionalias:
            regionalias = args.region
        else:
            regionalias=args.regionalias

    create_jitsi_cloud_api_template(filepath=args.filepath)


if __name__ == '__main__':
    main()

