#!/usr/bin/env python

# pip install troposphere boto3

from templatelib import *

import boto3, re, argparse, json, os
from troposphere import Parameter, Ref, Template, Join, Tags, Base64, Output, GetAtt,cloudformation
from troposphere.ec2 import Instance, NetworkInterfaceProperty, Volume, VolumeAttachment
from troposphere.ec2 import BlockDeviceMapping as ec2BlockDeviceMapping, EBSBlockDevice as ec2EBSBlockDevice
from troposphere.ec2 import SecurityGroupEgress,SecurityGroup,SecurityGroupIngress
from troposphere.autoscaling import Tag, AutoScalingGroup, LaunchConfiguration, BlockDeviceMapping, EBSBlockDevice, NotificationConfigurations, MetricsCollection, ScalingPolicy
from troposphere.route53 import RecordSetType, HealthCheck, HealthCheckConfiguration
from troposphere.cloudwatch import Alarm, MetricDimension
from troposphere.iam import Role, InstanceProfile

from awacs.aws import Allow, Statement, Principal, Policy
from awacs.sts import AssumeRole


def pull_network_stack_vars(region, regionalias, stackprefix, az_letter):

    global vpc_id
    global public_subnetA
    global public_subnetB
    global ssh_security_group
    global signal_security_group
    global jvb_security_group
    global jvb_zone_id
    global subnetId

    stack_name = regionalias + "-" + stackprefix + "-network"

    client = boto3.client( 'cloudformation', region_name=region )
    response = client.describe_stacks(
        StackName=stack_name
    )

    for stack in response["Stacks"]:
            outputs =  dict([(x['OutputKey'], x['OutputValue']) for x in stack['Outputs']])
            vpc_id = outputs.get('VPC')

            ssh_security_group = outputs.get('SSHSecurityGroup')

            public_subnetA = outputs.get("PublicSubnetA")
            public_subnetB = outputs.get("PublicSubnetB")

            if az_letter ==  "a":
                subnetId =public_subnetA
            elif az_letter in ["b", "c"]:
                subnetId = public_subnetB

def pull_bash_network_vars(az_letter):

    global vpc_id
    global public_subnetA
    global public_subnetB
    global ssh_security_group
    global signal_security_group
    global jvb_security_group
    global jvb_zone_id
    global subnetId

    vpc_id = os.environ['EC2_VPC_ID']
    signal_security_group = os.environ['SIGNAL_SECURITY_GROUP']
    public_subnetA = os.environ['DEFAULT_PUBLIC_SUBNET_ID_a']
    public_subnetB = os.environ['DEFAULT_PUBLIC_SUBNET_ID_b']
    ssh_security_group = os.environ['SSH_SECURITY_GROUP']
    jvb_security_group = os.environ['JVB_SECURITY_GROUP']


    if az_letter == "a":
        subnetId = public_subnetA
        jvb_zone_id = os.environ['DEFAULT_DC_SUBNET_IDS_a']
    elif az_letter in ["b", "c"]:
        subnetId = public_subnetB
        jvb_zone_id= os.environ['DEFAULT_DC_SUBNET_IDS_b']

def add_iam_role(t):
    cfnrole = t.add_resource(Role(
        "StandaloneRole",
        AssumeRolePolicyDocument=Policy(
            Statement=[
                Statement(
                    Effect=Allow,
                    Action=[AssumeRole],
                    Principal=Principal("Service", ["ec2.amazonaws.com"])
                )
            ]
        )
    ))

    cfninstanceprofile = t.add_resource(InstanceProfile(
        "StandaloneInstanceProfile",
        Roles=[Ref(cfnrole)]
    ))


def add_parameters(t):

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
        Description="XMPP Domain Name",
        Type="String",
        Default="hcv-us-east-1.infra.jitsi.net"
    ))


    test_id = t.add_parameter(Parameter(
        'TestId',
        Description= "Standalone Id",
        Type= "String"
    ))

    public_dns_name_param = t.add_parameter(Parameter(
        "PublicDNSName",
        Description="Public DNS name",
        Type="String",
        Default="example.jitsi.net"
    ))

    public_dns_hosted_zone_id_param = t.add_parameter(Parameter(
        "PublicDNSHostedZoneId",
        Description="public hosted zone Id",
        Type="String",
        Default=""
    ))


    internal_domain_name_param = t.add_parameter(Parameter(
        "InternalDomainName",
        Description="Internal DNS Domain Name",
        Type="String",
        Default="infra.jitsi.net"
    ))

    internal_dns_hosted_zone_id_param = t.add_parameter(Parameter(
        "InternalDNSHostedZoneId",
        Description="HC Video public hosted zone Id",
        Type="String",
        Default="ZP3DAJR109E5U"
    ))

    image_id = t.add_parameter(Parameter(
        "ImageId",
        Description= "Base instance AMI id",
        Type=  "AWS::EC2::Image::Id",
        ConstraintDescription= "must be a valid and allowed AMI id."
    ))

    jvb_availability_zone_letter = t.add_parameter(Parameter(
        "AvailabilityZoneLetter",
        Description=  "AZ letter for Standalone instance",
        AllowedValues= ["a","b","c"],
        Type= "String",
        ConstraintDescription= "must be a valid AZ zone."
    ))

    jvb_availability_zone = t.add_parameter(Parameter(
        "AvailabilityZone",
        Description= "AZ for JVB ASG",
        Type="AWS::EC2::AvailabilityZone::Name",
        Default= "us-east-1a",
        ConstraintDescription="must be a valid and allowed availability zone."
    ))

    instance_type = t.add_parameter(Parameter(
        "InstanceType",
        Description= "Standalone server instance type",
        Type= "String",
        Default= "t3.large",
        AllowedValues= [
                             "t2.micro",
                             "t2.small",
                             "t2.medium",
                             "t2.large",
                             "t2.xlarge",
                             "t3.micro",
                             "t3.small",
                             "t3.medium",
                             "t3.large",
                             "t3.xlarge",
                             "c5.medium",
                             "c5.large",
                             "c5.xlarge",
                             "c5.2xlarge",
                             "c4.large",
                             "c4.xlarge",
                             "c4.2xlarge",
                            "z1d.large",
                            "z1d.xlarge",
                            "z1d.2xlarge",
                            "c6g.medium",
                            "c6g.large",
                            "c6g.xlarge",
                            "c6g.2xlarge",
                            "m6g.large",
                            "m6g.xlarge",
                            "m6g.2xlarge",
                            "t4g.medium",
                            "t4g.large",
                            "t4g.xlarge",
                            "t4g.2xlarge"                             
                         ],
        ConstraintDescription= "must be a valid and allowed EC2 instance type."
    ))

    instance_virtualization = t.add_parameter(Parameter(
        'InstanceVirtualization',
        Description= "App server instance virtualization",
        Type= "String",
        Default= "PV",
        AllowedValues= ["HVM","PV"],
        ConstraintDescription= "Must be a valid and allowed virtualization type."
    ))

    server_security_instance_profile = t.add_parameter(Parameter(
        "ServerSecurityInstanceProfile",
        Description= "Standalone Security Instance Profile",
        Type= "String",
        Default= "HipChatVideo-StandAlone"
    ))

    server_instance_tenancy = t.add_parameter(Parameter(
        "InstanceTenancy",
        Description="Server placement tenancy",
        Type= "String",
        Default= "default",
        AllowedValues= [
                "default",
                "dedicated",
                "host"
        ],
        ConstraintDescription= "must be a valid and allowed EC2 instance placement tenancy."
    ))

    region_alias_param = t.add_parameter(Parameter(
        "RegionAlias",
        Description="Alias for AWS Region",
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
    ))

    tag_git_branch_param = t.add_parameter(Parameter(
        "TagGitBranch",
        Description="Tag: git_branch",
        Type="String",
        Default="master"
    ))

    datadog_enabled_param = t.add_parameter(Parameter(
        "DatadogEnabled",
        Description="Datadog flag",
        Type="String",
        Default="false",
        AllowedValues= [
                "true",
                "false"
        ]
    ))


def add_security(t):

    standalone_security_group = t.add_resource(SecurityGroup(
        "MeetSecurityGroup",
        GroupDescription=Join(' ', ["Standalone SG",Ref("TestId"), Ref("TagEnvironment"), Ref("RegionAlias"),
                                    Ref("StackNamePrefix")]),
        VpcId=vpc_id,
        Tags=Tags(
            Name=Join("-", [Ref("TagEnvironment"), Ref("RegionAlias"), Ref("StackNamePrefix"),Ref("TestId"), "SG"]),
            Environment= Ref("TagEnvironmentType"),
            Product= Ref("TagProduct"),
            Service= Ref("TagService"),
            Team= Ref("TagTeam"),
            Owner= Ref("TagOwner"),
            Type= "jitsi-meet-standalone-sg",
            environment=Ref("TagEnvironment"),
            role="standalone",
        )
    ))

    ingress_ssl = t.add_resource(SecurityGroupIngress(
        "SSLingress",
        GroupId=Ref("MeetSecurityGroup"),
        IpProtocol="tcp",
        FromPort="443",
        ToPort="443",
        CidrIp='0.0.0.0/0'
    ))

    ingress_web = t.add_resource(SecurityGroupIngress(
        "Webingress",
        GroupId=Ref("MeetSecurityGroup"),
        IpProtocol="tcp",
        FromPort="80",
        ToPort="80",
        CidrIp='0.0.0.0/0'
    ))

    ingress_jvb_health = t.add_resource(SecurityGroupIngress(
        "JVBHealthingress",
        GroupId=Ref("MeetSecurityGroup"),
        IpProtocol="tcp",
        FromPort="8080",
        ToPort="8080",
        CidrIp='0.0.0.0/0'
    ))

    ingress_jicofo_health = t.add_resource(SecurityGroupIngress(
        "JicofoHealthingress",
        GroupId=Ref("MeetSecurityGroup"),
        IpProtocol="tcp",
        FromPort="8888",
        ToPort="8888",
        CidrIp='10.0.0.0/8'
    ))

    ingress_prosody_component = t.add_resource(SecurityGroupIngress(
        "ProsodyComponentingress",
        GroupId=Ref("MeetSecurityGroup"),
        IpProtocol="tcp",
        FromPort="5347",
        ToPort="5347",
        CidrIp='0.0.0.0/0'
    ))

    ingress_prosody_client = t.add_resource(SecurityGroupIngress(
        "ProsodyClientingress",
        GroupId=Ref("MeetSecurityGroup"),
        IpProtocol="tcp",
        FromPort="5222",
        ToPort="5222",
        CidrIp='0.0.0.0/0'
    ))

    ingress_prosody_jvb_client = t.add_resource(SecurityGroupIngress(
        "ProsodyJVBClientingress",
        GroupId=Ref("MeetSecurityGroup"),
        IpProtocol="tcp",
        FromPort="6222",
        ToPort="6222",
        CidrIp='0.0.0.0/0'
    ))

    ingress_jvbudp = t.add_resource(SecurityGroupIngress(
        'JVBUDPingress',
        GroupId=Ref("MeetSecurityGroup"),
        IpProtocol="udp",
        FromPort="10000",
        ToPort="20000",
        CidrIp="0.0.0.0/0"
    ))

    ingress_jvbudpipv6 = t.add_resource(SecurityGroupIngress(
        'JVBUDPIPv6ingress',
        GroupId=Ref("MeetSecurityGroup"),
        IpProtocol="udp",
        FromPort="10000",
        ToPort="20000",
        CidrIpv6="::/0"
    ))

    ingress_jvbssl = t.add_resource(SecurityGroupIngress(
        "JVBSSLingress",
        GroupId=Ref("MeetSecurityGroup"),
        IpProtocol="tcp",
        FromPort="4443",
        ToPort="4443",
        CidrIp='0.0.0.0/0'
    ))

    ingress_turn_tcp = t.add_resource(SecurityGroupIngress(
        "TURNTCPIngress",
        GroupId=Ref("MeetSecurityGroup"),
        IpProtocol="tcp",
        FromPort="3478",
        ToPort="3478",
        CidrIp='0.0.0.0/0'
    ))

    ingress_turn_udp = t.add_resource(SecurityGroupIngress(
        "TURNUDPIngress",
        GroupId=Ref("MeetSecurityGroup"),
        IpProtocol="udp",
        FromPort="3478",
        ToPort="3478",
        CidrIp='0.0.0.0/0'
    ))

    ingress_ssh = t.add_resource(SecurityGroupIngress(
        "SSHingress",
        GroupId=Ref("MeetSecurityGroup"),
        IpProtocol="tcp",
        FromPort="22",
        ToPort="22",
        SourceSecurityGroupId= ssh_security_group,
        SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
    ))

    egress1 = t.add_resource(SecurityGroupEgress(
        "egress1",
        GroupId=Ref("MeetSecurityGroup"),
        IpProtocol="-1",
        CidrIp='0.0.0.0/0',
        FromPort='-1',
        ToPort='-1'
    ))

def create_standalone_template(filepath, include_dns_entry=False, disk_size=8):

    global t

    t = Template()

    t.add_version("2010-09-09")

    t.add_description(
        "Standalone Jitsi Meet Instance"
    )

    # Add params
    add_parameters(t)

    # Add security
    add_security(t)

    meet_server = t.add_resource(Instance(
        'MeetServer',
        DependsOn= ["MeetSecurityGroup"],
        ImageId= Ref("ImageId"),
        KeyName= Ref("KeyName"),
        InstanceType= Ref("InstanceType"),
        Monitoring= False,
        Tenancy= Ref("InstanceTenancy"),
        BlockDeviceMappings=[ec2BlockDeviceMapping(DeviceName="/dev/sda1",Ebs=ec2EBSBlockDevice(VolumeSize=disk_size))],
        NetworkInterfaces= [
            NetworkInterfaceProperty(
                AssociatePublicIpAddress= True,
                DeviceIndex= 0,
                GroupSet= [Ref("MeetSecurityGroup")],
                SubnetId= subnetId
            )
        ],
        IamInstanceProfile= Ref("ServerSecurityInstanceProfile"),
        Tags= Tags(
            Name = Join("-",[
                Ref("TagEnvironment"),Ref("RegionAlias"),Ref("StackNamePrefix"), Ref("TestId")
                    ]),
            Environment= Ref("TagEnvironmentType"),
            Product= Ref("TagProduct"),
            Service= Ref("TagService"),
            Team= Ref("TagTeam"),
            Owner= Ref("TagOwner"),
            Type= "jitsi-meet-standalone",
            environment= Ref("TagEnvironment"),
            domain= Ref("TagDomainName"),
            test_id = Ref("TestId"),
            shard_role= "all",
            git_branch= Ref("TagGitBranch"),
            datadog= Ref("DatadogEnabled")
        ),
        UserData=Base64(Join("",[
            "#!/bin/bash -v\n",
            "EXIT_CODE=0\n",
            "set -e\n",
            "set -x\n",

            "export AWS_DEFAULT_REGION=", {"Ref": "AWS::Region"}, "\n",
            "PYTHON_MAJOR=$(python -c 'import platform; print(platform.python_version())' | cut -d '.' -f1)\n",
            "PYTHON_IS_3=false\n",
            "if [[ \"$PYTHON_MAJOR\" -eq 3 ]]; then\n", 
            "PYTHON_IS_3=true\n",
            "fi\n",
            "if $PYTHON_IS_3; then\n",
            "CFN_FILE=\"aws-cfn-bootstrap-py3-latest.tar.gz\"\n",
            "else\n",
            "CFN_FILE=\"aws-cfn-bootstrap-latest.tar.gz\"\n",
            "fi\n",

            "wget -P /root https://s3.amazonaws.com/cloudformation-examples/$CFN_FILE\n",
            "mkdir -p /root/aws-cfn-bootstrap-latest\n",
            "tar xvfz /root/$CFN_FILE --strip-components=1 -C /root/aws-cfn-bootstrap-latest\n",
            "easy_install /root/aws-cfn-bootstrap-latest/\n",
            "# Send signal about finishing configuring server\n",
            "/usr/local/bin/cfn-signal -e $EXIT_CODE -r 'Server configuration' '", {"Ref": "ClientWaitHandle"},
            "'\n"
        ]))
    ))

    client_wait_handle = t.add_resource(cloudformation.WaitConditionHandle(
        'ClientWaitHandle'
    ))

    client_wait_condition = t.add_resource(cloudformation.WaitCondition(
        'ClientWaitCondition',
        DependsOn= ["MeetServer"],
        Handle= Ref("ClientWaitHandle"),
        Timeout= 3600,
        Count= 1
    ))

    if include_dns_entry:

        xmpp_dns_record = t.add_resource(RecordSetType(
            "MeetDNSRecord",
            DependsOn= ["MeetServer"],
            HostedZoneId= Ref("PublicDNSHostedZoneId"),
            Comment= "The standalone server host name",
            Name=Ref("PublicDNSName"),
            Type= "A",
            TTL= 300,
            ResourceRecords= [GetAtt("MeetServer", "PublicIp")]
        ))

    xmpp_dns_record_internal = t.add_resource(RecordSetType(
        "InternalXmppDNSRecord",
        DependsOn=["MeetServer"],
        HostedZoneId=Ref("InternalDNSHostedZoneId"),
        Comment="The Meet server internal DNS name",
        Name= Join("", [Ref("TestId"),".", Join("-", [Ref("RegionAlias"), Ref("StackNamePrefix")]), ".internal.", Ref("InternalDomainName") ]),
        Type="A",
        TTL=300,
        ResourceRecords= [GetAtt("MeetServer", "PrivateIp")]
    ))

    outputs = [
        Output(
            'EnvironmentVPCId',
            Description="Stack VPC Id",
            Value= vpc_id,
        ),
        Output(
            'MeetServer',
            Description= "The instance ID for the Meet Server",
            Value= Ref("MeetServer"),
        ),
        Output(
            'PublicIp',
            Description= "The public IP for the Meet Server",
            Value= GetAtt("MeetServer", "PublicIp"),
        ),
        Output(
            'PrivateIp',
            Description= "The private IP for the Meet Server",
            Value= GetAtt("MeetServer", "PrivateIp"),
        ),
        Output(
            'InternalDNSRecord',
            Description= "The Internal DNS Record",
            Value= Ref("InternalXmppDNSRecord"),
        ),
    ]

    if include_dns_entry:
        outputs.append(Output(
            'PublicDNSRecord',
            Description= "The Internal XMPP DNS Record",
            Value= Ref("PublicDNSName"),
        ))

    t.add_output(outputs)



    data = json.loads(re.sub('test_id','test-id',re.sub('shard_','shard-',t.to_json())))

    with open (filepath, 'w+') as outfile:
        json.dump(data, outfile)

def main():
    parser = argparse.ArgumentParser(description='Create standalone stack template')
    parser.add_argument('--region', action='store',
                        help='AWS region)', default=False, required=True)
    parser.add_argument('--regionalias', action='store',
                        help='AWS region alias)', default=False)
    parser.add_argument('--stackprefix', action='store',
                        help='Stack prefix name', default=False, required=False)
    parser.add_argument('--az_letter', action='store',
                         help='AZ letter', default=False, required=True)
    parser.add_argument('--filepath', action='store',
                        help='Path to tenmplate file', default=False, required=False)
    parser.add_argument('--pull_network_stack', action='store',
                        help='Pull network variables from a network stack', default='true', required=True)
    parser.add_argument('--include_dns_entry', action='store',
                        help='Enable Public DNS Entry for stack', default=False)
    parser.add_argument('--disk_size', action='store', type=int,
                        help='GB of disk', default=8, required=False)

    args = parser.parse_args()

    if not args.region:
        print('No AWS region specified, exiting...')
        exit(1)
    elif not args.filepath:
        print ('No path to template file')
        exit(2)
    elif not args.az_letter:
        print ('No AZ letter')
        exit(3)
    else:
        if not args.regionalias:
            regionalias = args.region
        else:
            regionalias=args.regionalias

        if args.pull_network_stack.lower() == "true":
            pull_network_stack_vars(region=args.region, regionalias=regionalias, stackprefix=args.stackprefix, az_letter=args.az_letter)
        else:
            pull_bash_network_vars(az_letter=args.az_letter)
        
        if args.include_dns_entry.lower() == "true":
            include_dns_entry=True
        else:
            include_dns_entry=False

        create_standalone_template(filepath=args.filepath, include_dns_entry=include_dns_entry, disk_size=args.disk_size)

if __name__ == '__main__':
    main()
