#!/usr/bin/env python

# pip install troposphere boto3

from templatelib import *

import boto3, re, argparse, json, os
from troposphere import Parameter, Ref, Template, Join, Tags, Base64, Output, GetAtt,cloudformation
from troposphere.ec2 import Instance, NetworkInterfaceProperty
from troposphere.ec2 import SecurityGroupEgress,SecurityGroup,SecurityGroupIngress
from troposphere.autoscaling import Tag, AutoScalingGroup, LaunchConfiguration, BlockDeviceMapping, EBSBlockDevice, NotificationConfigurations, MetricsCollection, ScalingPolicy
from troposphere.route53 import RecordSetType, HealthCheck, HealthCheckConfiguration
from troposphere.cloudwatch import Alarm, MetricDimension
from troposphere.cloudformation import CustomResource
from troposphere.policies import (
    CreationPolicy, ResourceSignal
)


def create_custom_resource(t, enable_pagerduty_alarms=False, enable_alarm_sns_on_create=True):

    alarm_health_sns=[Ref('JVBHealthAlarmSNS')]
    no_data_health_sns=[Ref('JVBHealthAlarmSNS')]
    ok_health_sns=[Ref('JVBHealthAlarmSNS')]

    if enable_pagerduty_alarms:
        alarm_health_sns.append(Ref('PagerDutySNSTopicName'))
        no_data_health_sns.append(Ref('PagerDutySNSTopicName'))
        ok_health_sns.append(Ref('PagerDutySNSTopicName'))

    add_custom_resource= t.add_resource(CustomResource(
        "LambdaCustomDelayFunction",
        DependsOn="Route53XMPPHealthCheck",
        ServiceToken= Join("", ["arn:aws:lambda:", Ref("AWS::Region"), ":",
                           Ref("AWS::AccountId"),
                           ":function:",Ref("AppLambdaFunctionName")]),
        ActionsEnabled=enable_alarm_sns_on_create,
        AlarmHealthSNS=alarm_health_sns,
        NoDataHealthSNS=no_data_health_sns,
        OkHealthSNS=ok_health_sns,
        AnyAlarmHealthSNS=[Ref('JVBHealthAlarmSNS')],
        AnyNoDataHealthSNS=[Ref('JVBHealthAlarmSNS')],
        AnyOkHealthSNS=[Ref('JVBHealthAlarmSNS')],
        HealthChecksID=[Ref("Route53XMPPHealthCheck")],
        StackRegion=Ref("RegionAlias"),
        AccountId=Ref("AWS::AccountId"),
        StackRole="xmpp",
        Environment=Ref("TagEnvironment"),
        Shard=Ref("TagShard")
    ))


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
            jvb_security_group = outputs.get("JVBSecurityGroup")
            signal_security_group = outputs.get('SignalSecurityGroup')

            jvb_subnets_A = outputs.get("JVBSubnetsA")
            jvb_subnets_B = outputs.get("JVBSubnetsB")

            public_subnetA = outputs.get("PublicSubnetA")
            public_subnetB = outputs.get("PublicSubnetB")

            if az_letter == "a":
                subnetId =public_subnetA
                jvb_zone_id = jvb_subnets_A
            elif az_letter in ["b","c"]:
                subnetId = public_subnetB
                jvb_zone_id= jvb_subnets_B

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
    elif az_letter in ["b","c"]:
        subnetId = public_subnetB
        jvb_zone_id= os.environ['DEFAULT_DC_SUBNET_IDS_b']

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
        AllowedValues= ["a","b","c","d"],
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
        Default= "t3.large",
        AllowedValues= [
            "t1.micro",
            "t2.small",
            "t2.medium",
            "t3.medium",
            "t3.large",
            "m1.small",
            "m1.medium",
            "m1.large",
            "m3.large",
            "m4.large",
            "m5.large",
            "m5.xlarge",
            "c5.large",
            "c5.xlarge",
            "c5.2xlarge",
            "c5.4xlarge",
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

    app_instance_virtualization = t.add_parameter(Parameter(
        'AppInstanceVirtualization',
        Description= "App server instance virtualization",
        Type= "String",
        Default= "PV",
        AllowedValues= ["HVM","PV"],
        ConstraintDescription= "Must be a valid and allowed virtualization type."
    ))

    app_lambda_function_name = t.add_parameter(Parameter(
        'AppLambdaFunctionName',
        Description= "Lambda function name that CF custom resources use when create a stack",
        Type= "String",
        Default= "all-cf-update-route53",
    ))

    jvb_image_id = t.add_parameter(Parameter(
        "JVBImageId",
        Description= "JVB server instance AMI id",
        Type= "String",
        ConstraintDescription= "must be a valid and allowed AMI id."
    ))

    jvb_instance_type = t.add_parameter(Parameter(
        "JVBInstanceType",
        Description="JVB server instance type",
        Type= "String",
        Default= "c5.xlarge",
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
                "c5.large",
                "c5.xlarge",
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

    jvb_instance_tenancy = t.add_parameter(Parameter(
        "JVBPlacementTenancy",
        Description="JVB placement tenancy",
        Type= "String",
        Default= "default",
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

    jvb_eip_pool = t.add_parameter(Parameter(
        "JVBEIPPool",
        Description="Pool of EIPs for the JVB instances. Must be a CIDR block",
        Type="String",
        Default="false"
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

    app_server_root_device = t.add_parameter(Parameter(
        "XMPPServerRootDevice",
        Description= "Device for mounting / on XMPP server, used for cloudwatch alarms around disk utilization",
        Type= "String",
        Default= "/dev/nvme0n1p1"
    ))

    app_server_root_device = t.add_parameter(Parameter(
        "JVBRootDevice",
        Description= "Device for mounting / on JVB server, used for cloudwatch alarms around disk utilization",
        Type= "String",
        Default= "/dev/nvme0n1p1"
    ))

    jvb_server_security_instance_profile = t.add_parameter(Parameter(
        "JVBServerSecurityInstanceProfile",
        Description= "JVB Security Instance Profile",
        Type= "String",
        Default= "HipChatVideo-VideoBridgeNode"
    ))

    jvb_min_count_param = t.add_parameter(Parameter(
        "JVBMinCount",
        Description="Count of JVBs at Minimum",
        Type="Number",
        Default=2,
        MinValue=1,
        ConstraintDescription="Must be at least 1 JVB instance."
    ))

    jvb_max_count_param = t.add_parameter(Parameter(
        "JVBMaxCount",
        Description="Count of JVBs at Maximum",
        Type="Number",
        Default=8,
        MinValue=1,
        ConstraintDescription="Must be at least 1 JVB instance."
    ))

    jvb_desired_count_param = t.add_parameter(Parameter(
        "JVBDesiredCount",
        Description="Count of JVBs at the moment",
        Type="Number",
        Default=2,
        MinValue=1,
        ConstraintDescription="Must be at least 1 JVB instance."
    ))

    region_alias_param = t.add_parameter(Parameter(
        "RegionAlias",
        Description="Alias for AWS Region",
        Type="String",
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
        Default="master"
    ))

    tag_shard_unseen_param = t.add_parameter(Parameter(
        "TagShardUnseen",
        Description="Tag: shard-unseen",
        Type="String",
        Default="true"
    ))

    tag_cloud_name_param = t.add_parameter(Parameter(
        "TagCloudName",
        Description="Tag: cloud_name",
        Type="String"
    ))

    tag_cloud_provider_param = t.add_parameter(Parameter(
        "TagCloudProvider",
        Description="Tag: cloud_provider",
        Type="String"
    ))

def create_app_shard_template(filepath, enable_pagerduty_alarms=False, release_number=False, enable_ec2_recovery=False, enable_jvb_asg=True, enable_alarm_sns_on_create=True):

    global t
    global subnetId

    t = Template()

    t.add_version("2010-09-09")

    t.add_description(
        "Template for the provisioning AWS resources for the HC Video shard"
    )

    # Add params
    add_parameters()
    #Add custom resource for triggering lambda function
    create_custom_resource(t, enable_pagerduty_alarms, enable_alarm_sns_on_create)

    xmpp_server_tags = Tags(
            Name = Join("-",[
                Ref("TagEnvironment"),Ref("JVBAvailabilityZone"),Ref("StackNamePrefix"), Join("", ["s",Ref("ShardId")]),"core"
                    ]),
            Environment= Ref("TagEnvironmentType"),
            Product= Ref("TagProduct"),
            Service= Ref("TagService"),
            Team= Ref("TagTeam"),
            Owner= Ref("TagOwner"),
            Type= "jitsi-meet-signal",
            environment= Ref("TagEnvironment"),
            domain= Ref("TagDomainName"),
            shard= Ref("TagShard"),
            shard_role= "core",
            shard_state= "drain",
            shard_tested= "untested",
            git_branch= Ref("TagGitBranch"),
            datadog= Ref("DatadogEnabled"),
            shard_unseen= Ref("TagShardUnseen"),
            cloud_name=Ref("TagCloudName"),
            cloud_provider=Ref("TagCloudProvider")
        )


    if release_number:
        xmpp_server_tags += (Tags(release_number=release_number))

    xmpp_server = t.add_resource(Instance(
        'XMPPServer',
        ImageId= Ref("SignalImageId"),
        KeyName= Ref("KeyName"),
        InstanceType= Ref("AppInstanceType"),
        Monitoring= False,
        NetworkInterfaces= [
            NetworkInterfaceProperty(
                AssociatePublicIpAddress= True,
                DeviceIndex= 0,
                GroupSet= [signal_security_group],
                SubnetId= subnetId
            )
        ],
        BlockDeviceMappings= [BlockDeviceMapping(
            DeviceName= "/dev/sda1",
            Ebs=EBSBlockDevice(
                VolumeSize= 20
            )
        )],
        IamInstanceProfile= Ref("AppServerSecurityInstanceProfile"),
        Tags= xmpp_server_tags,
        UserData=Base64(Join("",[
            "#!/bin/bash -v\n",
            "EXIT_CODE=0\n",
            "status_code=0\n",
            "set -x\n",
            "tmp_msg_file='/tmp/cfn_signal_message'\n",

            "function get_metadata(){\n",
            "export AWS_DEFAULT_REGION=", {"Ref": "AWS::Region"}, "\n",
            "export CLOUD_NAME=\"", {"Ref": "TagCloudName"}, "\"\n",
            "export CLOUD_PROVIDER=\"", {"Ref": "TagCloudProvider"}, "\"\n",
            "}\n",

            "function install_apps(){\n",
            "status_code=0 && \\\n",
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
            "mkdir -p /root/aws-cfn-bootstrap-latest && \\\n",
            "tar xvfz /root/$CFN_FILE --strip-components=1 -C /root/aws-cfn-bootstrap-latest\n",
            "easy_install /root/aws-cfn-bootstrap-latest/ && \\\n",
            "if [ $status_code -eq 1 ]; then echo 'Install apps stage failed' > $tmp_msg_file; return $status_code;fi\n"
            "}\n",

            "function provisioning(){\n",
            "status_code=0 && \\\n",
            "/usr/local/bin/postinstall-jicofo.sh >> /var/log/bootstrap.log 2>&1 || status_code=1\n",
            "[ $status_code -eq 0 ] || /usr/local/bin/dump-jicofo.sh > /var/log/dump_jicofo.log 2>&1 || DUMP_CODE=1\n",
            "if [ $status_code -eq 1 ]; then echo 'Provisioning stage failed' > $tmp_msg_file; return $status_code;fi;\n"
            "}\n",

            "function retry(){\n",
            "n=0\n",
            "until [ $n -ge 5 ];do\n",
            "$1\n",
            "if [ $? -eq 0 ];then\n",
            "> $tmp_msg_file;break\n",
            "fi\n",
            "n=$[$n+1];sleep 1;done\n",
            "if [ $n -eq 5 ];then\n",
            "return $n\n",
            "else\n",
            "return 0;fi\n"
            "}\n",

            "( retry get_metadata && retry install_apps && retry provisioning ) ||  EXIT_CODE=1\n"

            "if [ ! -f /tmp/cfn_signal_message ]; then err_message='Server configuration';else err_message=$(cat $tmp_msg_file);fi\n",

            "if [ ! $EXIT_CODE -eq 0 ]; then /usr/local/bin/dump-jicofo.sh;fi\n"

            "# Send signal about finishing configuring server\n",
            "/usr/local/bin/cfn-signal -e $EXIT_CODE -r \"$err_message\" '", {"Ref": "XMPPClientWaitHandle"}, "'|| true\n",

            "if [ ! $EXIT_CODE -eq 0 ]; then shutdown -h now;fi\n"
        ]))
    ))


    xmpp_client_wait_handle = t.add_resource(cloudformation.WaitConditionHandle(
        'XMPPClientWaitHandle'
    ))

    xmpp_client_wait_condition = t.add_resource(cloudformation.WaitCondition(
        'XMPPClientWaitCondition',
        Handle= Ref("XMPPClientWaitHandle"),
        Timeout= 3600,
        Count= 1
    ))

    xmpp_dns_record = t.add_resource(RecordSetType(
        "XmppDNSRecord",
        DependsOn= ["XMPPServer"],
        HostedZoneId= Ref("PublicDNSHostedZoneId"),
        Comment= "The XMPP server host name",
        Name= Join("",[ Join("-",[Ref("TagShard"), "core"]),".",Ref("DomainName"),"."]),
        Type= "A",
        TTL= 300,
        ResourceRecords= [GetAtt("XMPPServer", "PublicIp")]
    ))

    xmpp_dns_record_internal = t.add_resource(RecordSetType(
        "InternalXmppDNSRecord",
        DependsOn=["XMPPServer"],
        HostedZoneId=Ref("PublicDNSHostedZoneId"),
        Comment="The XMPP server host name",
        Name= Join("", [ Join("-", [Ref("TagEnvironment"), Ref("RegionAlias"), Ref("StackNamePrefix"), Join("",["s", Ref("ShardId")])]), ".internal.", Ref("DomainName") ]),
        Type="A",
        TTL=300,
        ResourceRecords= [GetAtt("XMPPServer", "PrivateIp")]
    ))

    internal_focus_dns_record = t.add_resource(RecordSetType(
        "InternalFocusDNSRecord",
        DependsOn=["XMPPServer"],
        HostedZoneId=Ref("PublicDNSHostedZoneId"),
        Comment="The Internal Focus server host name",
        Name=Join("", [ "focus.", Join( "-",[ Ref("TagEnvironment"), Ref("RegionAlias"), Ref("StackNamePrefix"), Join("",["s", Ref("ShardId")]) ]),".internal.", Ref("DomainName"),"."]),
        Type="A",
        TTL=300,
        ResourceRecords= [GetAtt("XMPPServer", "PrivateIp")]
    ))

    route53_xmpp_health_check = t.add_resource(HealthCheck(
        'Route53XMPPHealthCheck',
        DependsOn=["JVBAutoScaleGroup" if enable_jvb_asg else "XMPPClientWaitCondition"],
        HealthCheckConfig= HealthCheckConfiguration(
            IPAddress= GetAtt( "XMPPServer", "PublicIp"),
            Port= 443,
            Type= "HTTPS",
            ResourcePath= "/about/health",
            FullyQualifiedDomainName= Ref("TagPublicDomainName"),
            RequestInterval= 30,
            FailureThreshold= 1
        ),
        HealthCheckTags= Tags(
            Name= Join("-", [Ref("TagEnvironment"), Ref("RegionAlias"), Ref("StackNamePrefix"),
                                Join("", ["s", Ref("ShardId")]), "R53Health"]),
            Environment= Ref("TagEnvironmentType"),
            Product= Ref("TagProduct"),
            Service= Ref("TagService"),
            Team= Ref("TagTeam"),
            Owner= Ref("TagOwner"),
            Type= "jitsi-meet-signal-health",
            environment=Ref("TagEnvironment"),
            domain=Ref("TagDomainName"),
            shard=Ref("TagShard")
        )
    ))

    alarm_actions=[
        Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("JVBHealthAlarmSNS")])
    ]
    if enable_pagerduty_alarms:
        alarm_actions.append(Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("PagerDutySNSTopicName")]))

    system_failed_actions=alarm_actions.copy()

    if enable_ec2_recovery:
        system_failed_actions.append(Join("", ["arn:aws:automate:", Ref("AWS::Region"),":ec2:recover"]))

    alarm_xmpp_system_failed = t.add_resource(Alarm(
        'AlarmXMPPSystemFailed',
        ActionsEnabled=True,
        AlarmDescription= "System failure rebuild check on XMPP node",
        ComparisonOperator="GreaterThanOrEqualToThreshold",
        EvaluationPeriods=5,
        MetricName="StatusCheckFailed_System",
        Namespace="AWS/EC2",
        Period=60,
        Statistic="Maximum",
        Threshold="1.0",
        AlarmActions=system_failed_actions,
        OKActions=alarm_actions,
        InsufficientDataActions=system_failed_actions,
        Dimensions= [MetricDimension(
            Name="InstanceId",
            Value=Ref("XMPPServer")
        )]
    ))


    if enable_jvb_asg:
        jvb_launch_group = t.add_resource(LaunchConfiguration(
            "JVBLaunchGroup",
            DependsOn=["XMPPClientWaitCondition"],
            ImageId= Ref("JVBImageId"),
            InstanceType= Ref("JVBInstanceType"),
            IamInstanceProfile= Ref("JVBServerSecurityInstanceProfile"),
            PlacementTenancy= Ref("JVBPlacementTenancy"),
            KeyName= Ref("KeyName"),
            SecurityGroups= [jvb_security_group],
            AssociatePublicIpAddress= Ref("JVBAssociatePublicIpAddress"),
            InstanceMonitoring= False,
            BlockDeviceMappings= [BlockDeviceMapping(
                DeviceName= "/dev/sda1",
                Ebs=EBSBlockDevice(
                    VolumeSize= 20
                )
            )],
            UserData= Base64(Join("",[
                "#!/bin/bash -v\n",
                "EXIT_CODE=0\n",
                "status_code=0\n"
                "set -x\n",
                "tmp_msg_file='/tmp/cfn_signal_message'\n",

                "function get_metadata(){\n",
                "export AWS_DEFAULT_REGION=", {"Ref": "AWS::Region"}, "\n",
                "export CLOUD_NAME=\"", {"Ref": "TagCloudName"}, "\"\n",
                "export CLOUD_PROVIDER=\"", {"Ref": "TagCloudProvider"}, "\"\n",
                "}\n",

                "function install_apps(){\n",
                "PYTHON_MAJOR=$(python -c 'import platform; print(platform.python_version())' | cut -d '.' -f1)\n",
                "PYTHON_IS_3=false\n",
                "PIP_BIN=/usr/bin/pip\n",
                "if [[ \"$PYTHON_MAJOR\" -eq 3 ]]; then\n", 
                "PYTHON_IS_3=true\n",
                "PIP_BIN=/usr/bin/pip3\n",
                "fi\n",
                "if $PYTHON_IS_3; then\n",
                "CFN_FILE=\"aws-cfn-bootstrap-py3-latest.tar.gz\"\n",
                "else\n",
                "CFN_FILE=\"aws-cfn-bootstrap-latest.tar.gz\"\n",
                "fi\n",
                "wget -P /root https://s3.amazonaws.com/cloudformation-examples/$CFN_FILE\n",
                "mkdir -p /root/aws-cfn-bootstrap-latest && \\\n",
                "tar xvfz /root/$CFN_FILE --strip-components=1 -C /root/aws-cfn-bootstrap-latest\n",
                "easy_install /root/aws-cfn-bootstrap-latest/ || status_code=1\n",
                "if [ $status_code -eq 1 ]; then echo 'Install apps stage failed' > $tmp_msg_file; exit $status_code;fi\n"
                "echo \"[Boto]\" > /etc/boto.cfg && echo \"use_endpoint_heuristics = True\" >> /etc/boto.cfg\n",
                "$PIP_BIN install aws-ec2-assign-elastic-ip || status_code=1\n",
                "if [ $status_code -eq 1 ]; then echo 'Install apps stage failed' > $tmp_msg_file; exit $status_code;fi\n"
                "}\n",

                "function check_eip(){\n",
                "if [ \"", {"Ref": "JVBEIPPool"} ,"\" == \"false\" ]; then return 0; fi\n",
                "counter=1\n",
                "eip_status=1\n",
                "while [ $counter -le 20 ]; do\n",
                "aws-ec2-assign-elastic-ip --region ", {"Ref": "AWS::Region"}, " --valid-ips ", {"Ref": "JVBEIPPool"},
                " |  grep --line-buffered -s 'is already assigned an Elastic IP'|grep -q \"$instance_id\"\n",
                "if [ $? -eq 0 ];then eip_status=0;break\n",
                "else\n",
                "sleep 30\n",
                "((counter++))\n",
                "fi; done\n",
                "if [ $eip_status -eq 1 ];then echo \"EIP still not available status: $eip_status\" > $tmp_msg_file;return 0\n",
                "else return $eip_status; fi\n"
                "}\n",

                "function provisioning(){\n",
                "/usr/local/bin/postinstall-jvb.sh >> /var/log/bootstrap.log 2>&1 || status_code=1\n",
                "if [ $status_code -eq 1 ]; then echo 'Provisioning stage failed' > $tmp_msg_file; exit $status_code;fi;\n"
                "}\n",

                "function retry(){\n",
                "n=0\n",
                "until [ $n -ge 5 ];do\n",
                "$1\n",
                "if [ $? -eq 0 ];then\n",
                "> $tmp_msg_file;break\n",
                "fi\n",
                "n=$[$n+1];sleep 1;done\n",
                "if [ $n -eq 5 ];then\n",
                "return $n\n",
                "else\n",
                "return 0;fi\n"
                "}\n",

                "( retry get_metadata && retry install_apps && retry check_eip && retry provisioning ) ||  EXIT_CODE=1\n"

                "if [ ! -f /tmp/cfn_signal_message ]; then err_message='Server configuration';else err_message=$(cat $tmp_msg_file);fi\n",

                "if [ ! $EXIT_CODE -eq 0 ]; then /usr/local/bin/dump-jvb.sh;fi\n"

                "# Send signal about finishing configuring server\n",
                "/usr/local/bin/cfn-signal -e $EXIT_CODE -r \"$err_message\" --resource JVBAutoScaleGroup --stack '", {"Ref": "AWS::StackName"}, "' --region ", { "Ref" : "AWS::Region" }, "|| true\n",

                "if [ ! $EXIT_CODE -eq 0 ]; then shutdown -h now;fi\n"
            ]))

        ))

        jvb_tags = [
                Tag("Name", Join("-", [Ref("TagEnvironment"), Ref("RegionAlias"), Ref("StackNamePrefix"), Join("", ["s",Ref("ShardId")])]),
                    False),
                Tag("Environment", Ref("TagEnvironmentType"), True),
                Tag("Product", Ref("TagProduct"), True),
                Tag("Service", Ref("TagService"), True),
                Tag("Team", Ref("TagTeam"), True),
                Tag("Owner", Ref("TagOwner"), True),
                Tag("Type", "jitsi-jvb", True),
                Tag("environment", Ref("TagEnvironment"), True),
                Tag("service_tier", "Public", True),
                Tag("public_domain", Ref("TagPublicDomainName"), True),
                Tag("domain", Ref("TagDomainName"), True),
                Tag("shard-role", "JVB", True),
                Tag("cloud_name", Ref("TagCloudName"), True),
                Tag("cloud_provider", Ref("TagCloudProvider"), False),
                Tag("shard", Ref("TagShard"), True),
                Tag("git_branch", Ref("TagGitBranch"), True),
                Tag("datadog", Ref("DatadogEnabled"), True)
            ]

        if release_number:
            jvb_tags.append(
                Tag("release_number", release_number, True)
            )

        jvb_autoscale_group = t.add_resource(AutoScalingGroup(
            "JVBAutoScaleGroup",
            DependsOn= "XMPPServer",
            AvailabilityZones= [ Ref("JVBAvailabilityZone")] ,
            Cooldown= 300,
            DesiredCapacity= Ref("JVBDesiredCount"),
            HealthCheckGracePeriod= 300,
            HealthCheckType= "EC2",
            MaxSize= Ref("JVBMaxCount"),
            MinSize= Ref("JVBMinCount"),
            VPCZoneIdentifier= [jvb_zone_id],
            NotificationConfigurations= [NotificationConfigurations(
                TopicARN= Join(":", [ "arn:aws:sns",Ref("AWS::Region"),Ref("AWS::AccountId"),Ref("JVBASGAlarmSNS") ]),
                NotificationTypes= ["autoscaling:EC2_INSTANCE_LAUNCH", "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
                                    "autoscaling:EC2_INSTANCE_TERMINATE", "autoscaling:EC2_INSTANCE_TERMINATE_ERROR"]
            )],
            LaunchConfigurationName= Ref("JVBLaunchGroup"),
            MetricsCollection= [MetricsCollection(
                Granularity= "1Minute",
                Metrics= [
                    "GroupDesiredCapacity",
                    "GroupTerminatingInstances",
                    "GroupInServiceInstances",
                    "GroupMinSize",
                    "GroupTotalInstances",
                    "GroupMaxSize",
                    "GroupPendingInstances"
                ]
            )],
            TerminationPolicies= ["Default"],
            Tags=jvb_tags,
            CreationPolicy=CreationPolicy(
                ResourceSignal=ResourceSignal(
                    Count=Ref("JVBMinCount"),
                    Timeout='PT30M'))

        ))

        scaling_high_network_traffic = t.add_resource(ScalingPolicy(
            'scalingHighLoad',
            ScalingAdjustment= 5,
            Cooldown= 300,
            AdjustmentType= "ChangeInCapacity",
            AutoScalingGroupName= Ref("JVBAutoScaleGroup")
        ))

        scaling_low_network_traffic = t.add_resource(ScalingPolicy(
            'scalingLowLoad',
            ScalingAdjustment=-1,
            AdjustmentType="ChangeInCapacity",
            AutoScalingGroupName=Ref("JVBAutoScaleGroup")
        ))

        high_network_out = t.add_resource(Alarm(
            'HighLoad',
            ActionsEnabled= True,
            ComparisonOperator= "GreaterThanOrEqualToThreshold",
            EvaluationPeriods= 2,
            MetricName= "JVB_load_1",
            Namespace=  "Video",
            Period=60,
            Statistic= "Average",
            Threshold= "2.0",
            AlarmActions= [
            Join(":",["arn:aws:sns",Ref("AWS::Region"),Ref("AWS::AccountId"),Ref("JVBASGAlarmSNS")]),Ref("scalingHighLoad")
            ],
            OKActions= [
            Join(":",["arn:aws:sns",Ref("AWS::Region"),Ref("AWS::AccountId"),Ref("JVBASGAlarmSNS")])
            ],
            Dimensions= [MetricDimension(
                Name= "AutoScalingGroupName",
                Value= Ref("JVBAutoScaleGroup")
            )]
        ))

        low_network_out = t.add_resource(Alarm(
            'LowLoad',
            ActionsEnabled=True,
            ComparisonOperator="LessThanThreshold",
            EvaluationPeriods=360,
            MetricName="JVB_load_1",
            Namespace="Video",
            Period=60,
            Statistic="Average",
            Threshold="2.0",
            AlarmActions=[
                Ref("scalingLowLoad"),
                Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("JVBASGAlarmSNS")])
            ],
            OKActions=[
                Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("JVBASGAlarmSNS")])
            ],
            Dimensions=[MetricDimension(
                Name="AutoScalingGroupName",
                Value=Ref("JVBAutoScaleGroup")
            )]
        ))


    t.add_output([
        Output(
            'EnvironmentVPCId',
            Description="Stack VPC Id",
            Value= vpc_id,
        ),
        Output(
            'XMPPServer',
            Description= "The instance ID for the XMPP Server",
            Value= Ref("XMPPServer"),
        ),
        Output(
            'XMPPServerPublicIP',
            Description= "The Public IP for the XMPP Server",
            Value= GetAtt("XMPPServer", "PublicIp"),
        ),
        Output(
            'XMPPServerPrivateIP',
            Description= "The Private IP for the XMPP Server",
            Value= GetAtt("XMPPServer", "PrivateIp"),
        ),
        Output(
            'Route53HealthCheckId',
            Description= "The ID for the Route53 Health Check",
            Value= Ref("Route53XMPPHealthCheck"),
        ),
    ])



    data = json.loads(re.sub('shard_','shard-',t.to_json()))

    with open (filepath, 'w+') as outfile:
        json.dump(data, outfile)

def main():
    parser = argparse.ArgumentParser(description='Create Haproxy stack template')
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
    parser.add_argument('--enable_pagerduty_alarms', action='store',
                        help='Enable PagerDuty alarms for stack', default=False)
    parser.add_argument('--enable_ec2_recovery', action='store',
                        help='Enable EC2 Recovery for signal node in stack', default=False)
    parser.add_argument('--enable_jvb_asg', action='store',
                        help='Enable creation of AWS ASG with JVBs', default=True) 
    parser.add_argument('--enable_alarm_sns_on_create', action='store',
                        help='Enable route53 health alarms subscription to SNS topics on stack creation', default=True) 
    parser.add_argument('--release_number', action='store',
                        help='Release number', default=False)

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

        if args.enable_pagerduty_alarms.lower() == "true":
            enable_pagerduty_alarms=True
        else:
            enable_pagerduty_alarms=False

        if args.enable_ec2_recovery.lower() == "true":
            enable_ec2_recovery=True
        else:
            enable_ec2_recovery=False

        if args.release_number.isspace():
            release_number=False
        else:
            release_number=args.release_number

        if args.enable_jvb_asg.lower() == "false":
            enable_jvb_asg=False
        else:
            enable_jvb_asg=True

        if args.enable_alarm_sns_on_create.lower() == "false":
            enable_alarm_sns_on_create=False
        else:
            enable_alarm_sns_on_create=True

        create_app_shard_template(filepath=args.filepath, enable_pagerduty_alarms=enable_pagerduty_alarms, release_number=release_number, enable_ec2_recovery=enable_ec2_recovery, enable_jvb_asg=enable_jvb_asg, enable_alarm_sns_on_create=enable_alarm_sns_on_create)

if __name__ == '__main__':
    main()
