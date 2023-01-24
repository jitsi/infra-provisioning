#!/usr/bin/env python

# pip install troposphere boto3

import boto3, re, argparse, json, os
from botocore.exceptions import ClientError
from troposphere import Parameter, Ref, Template, Join, Base64, cloudformation, Tags, GetAtt, Output, Export

from troposphere.autoscaling import Tag, AutoScalingGroup, LaunchConfiguration, BlockDeviceMapping, EBSBlockDevice, NotificationConfigurations, MetricsCollection, ScalingPolicy
from troposphere.cloudwatch import Alarm, MetricDimension, MetricDataQuery, MetricStat, Metric
from troposphere.ec2 import SecurityGroup, SecurityGroupIngress, SecurityGroupEgress

def pull_network_stack_vars(region, region_alias, stackprefix):

    global vpc_id
    global ssh_security_group
    global jibri_subnets
    global public_subnetA
    global public_subnetB
    global sip_jibri_subnets

    stack_name = region_alias + "-" + stackprefix + "-network"

    client = boto3.client( 'cloudformation', region_name=region )
    response = client.describe_stacks(
        StackName=stack_name
    )

    for stack in response["Stacks"]:
            outputs =  dict([(x['OutputKey'], x['OutputValue']) for x in stack['Outputs']])
            vpc_id = outputs.get('VPC')
            jibri_subnets = outputs.get('PublicSubnetsIDs')
            sip_jibri_subnets = outputs.get('PublicSubnetsIDs')
            ssh_security_group = outputs.get('SSHSecurityGroup')
            public_subnetA = outputs.get('PublicSubnetA')
            public_subnetB = outputs.get('PublicSubnetB')

    stack_name = region_alias + "-" + stackprefix + "-NAT-network"
    try:
        client = boto3.client( 'cloudformation', region_name=region )
        response = client.describe_stacks(
            StackName=stack_name
        )

        for stack in response["Stacks"]:
                outputs =  dict([(x['OutputKey'], x['OutputValue']) for x in stack['Outputs']])
                jibri_subnets = outputs.get('NATSubnetA') + ','+outputs.get('NATSubnetB')
                sip_jibri_subnets = jibri_subnets
    except ClientError as e:
        print((e.response['Error']['Message']))

    stack_name = region_alias + "-" + stackprefix + "-sip-jibri-network"
    try:
        client = boto3.client( 'cloudformation', region_name=region )
        response = client.describe_stacks(
            StackName=stack_name
        )

        for stack in response["Stacks"]:
                outputs =  dict([(x['OutputKey'], x['OutputValue']) for x in stack['Outputs']])
                sip_jibri_subnets = outputs.get('SipJibriSubnetsIds')
    except ClientError as e:
        print((e.response['Error']['Message']))

def pull_bash_network_vars():

    global vpc_id
    global ssh_security_group
    global jibri_subnets
    global public_subnetA
    global public_subnetB
    global sip_jibri_subnets

    vpc_id = os.environ['EC2_VPC_ID']
    ssh_security_group = os.environ['SSH_SECURITY_GROUP']
    public_subnetA = os.environ['DEFAULT_PUBLIC_SUBNET_ID_a']
    public_subnetB = os.environ['DEFAULT_PUBLIC_SUBNET_ID_b']

    if 'DEFAULT_NAT_SUBNET_ID_a' in os.environ:
        nat_subnetA = os.environ['DEFAULT_NAT_SUBNET_ID_a']
        nat_subnetB = os.environ['DEFAULT_NAT_SUBNET_ID_b']
        jibri_subnets = nat_subnetA + "," + nat_subnetB
    else:
        jibri_subnets = public_subnetA + "," + public_subnetB

    if 'DEFAULT_SIP_JIBRI_SUBNET_ID_a' in os.environ:
        sip_jibri_subnetA = os.environ['DEFAULT_SIP_JIBRI_SUBNET_ID_a']
        sip_jibri_subnetB = os.environ['DEFAULT_SIP_JIBRI_SUBNET_ID_b']
        sip_jibri_subnets = sip_jibri_subnetA + "," + sip_jibri_subnetB
    else:
        sip_jibri_subnets = public_subnetA + "," + public_subnetB

def add_security(t):

    jibri_security_group = t.add_resource(SecurityGroup(
        "JibriSecurityGroup",
        GroupDescription=Join(' ', [Ref("JibriType"), "nodes", Ref("TagEnvironment"), Ref("RegionAlias"),
                                    Ref("StackNamePrefix")]),
        VpcId=vpc_id,
        Tags=Tags(
            Name=Join("-", [Ref("TagEnvironment"), Ref("RegionAlias"), Ref("StackNamePrefix"), "JibriGroup"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role=Ref("JibriType"),
        )
    ))

    ingress1 = t.add_resource(SecurityGroupIngress(
        "ingress1",
        GroupId=Ref("JibriSecurityGroup"),
        IpProtocol="tcp",
        FromPort="22",
        ToPort="22",
        SourceSecurityGroupId= ssh_security_group,
        SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
    ))

    egress1 = t.add_resource(SecurityGroupEgress(
        "egress1",
        GroupId=Ref("JibriSecurityGroup"),
        IpProtocol="-1",
        CidrIp='0.0.0.0/0',
        FromPort='-1',
        ToPort='-1'
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

    domain_name_param = t.add_parameter(Parameter(
        "DomainName",
        Description="HC Video internal domain name",
        Type="String",
        Default="hcv-us-east-1.infra.jitsi.net"
    ))

    jibri_image_id = t.add_parameter(Parameter(
        'JibriImageId',
        Description= "Jibri instance AMI id",
        Type= "AWS::EC2::Image::Id",
        ConstraintDescription= "must be a valid and allowed AMI id."
    ))

    jibri_type_param = t.add_parameter(Parameter(
        'JibriType',
        Description= "Jibri Type",
        Type= "String",
        ConstraintDescription= "meant to be 'jibri' 'sip-jibri' or 'java-jibri'"
    ))

    jibri_instance_type = t.add_parameter(Parameter(
        "JibriInstanceType",
        Description="Jibri server instance type",
        Type="String",
        Default= "c5.xlarge",
        AllowedValues=[
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
            "c4.2xlarge",
            "c5.large",
            "c5.xlarge",
            "c5.2xlarge"
        ],
        ConstraintDescription= "must be a valid and allowed EC2 instance type."
    ))

    jibri_instance_virtualization = t.add_parameter(Parameter(
        'JibriInstanceVirtualization',
        Description="Jibri server instance virtualization",
        Type="String",
        Default="PV",
        AllowedValues=["HVM", "PV"],
        ConstraintDescription="Must be a valid and allowed virtualization type."
    ))

    jibri_availability_zone = t.add_parameter(Parameter(
        "JibriAvailabilityZones",
        Description="AZ for Jibri ASG",
        Type="List<AWS::EC2::AvailabilityZone::Name>",
        Default= "us-east-1a,us-east-1b",
        ConstraintDescription="must be a valid and allowed availability zone."
    ))

    jibri_asg_alarm_sns = t.add_parameter(Parameter(
        "JibriASGAlarmSNS",
        Description= "SNS topic for ASG Alarms related to Jibri",
        Type= "String",
        Default= "meet-jitsi-ASG-alarms"
    ))

    jibri_health_alarm_sns = t.add_parameter(Parameter(
        "JibriHealthAlarmSNS",
        Description= "SNS topic for Health Alarms related to Jibri",
        Type= "String",
        Default= "MeetJitsi-Health-Check-List"
    ))

    page_durty_sns_topic_name = t.add_parameter(Parameter(
        "PagerDutySNSTopicName",
        Description= "String Name for SNS topic to notify PagerDuty",
        Type= "String",
        Default= "PagerDutyAlarms"
    ))

    jibri_server_security_instance_profile = t.add_parameter(Parameter(
        "JibriServerSecurityInstanceProfile",
        Description= "Jibri Security Instance Profile",
        Type= "String",
        Default= "HipChat-Video-Jibri"
    ))

    jibri_instance_available_count = t.add_parameter(Parameter(
        "JibriInstanceAvailableCount",
        Description= "Number of Jibri instances to try to keep available",
        Type= "Number",
        Default= "8"
    ))
    jibri_instance_available_count = t.add_parameter(Parameter(
        "JibriInstanceDesiredCount",
        Description= "Number of Jibri instances to launch immediately",
        Type= "Number",
        Default= "2"
    ))

    jibri_instance_min_count = t.add_parameter(Parameter(
        "JibriInstanceMinCount",
        Description= "Number of Jibri instances at minimum",
        Type= "Number",
        Default= "8"
    ))

    jibri_instance_available_count = t.add_parameter(Parameter(
        "JibriInstanceInitialCount",
        Description= "Initial Number of Jibri instances to try to keep available",
        Type= "Number",
        Default= "2"
    ))

    jibri_instance_downscale_count = t.add_parameter(Parameter(
        "JibriInstanceAvailableDownscaleCount",
        Description= "Number of Jibri unused/available instances at which we scale down",
        Type= "Number",
        Default= "5"
    ))

    jibri_instance_max_count = t.add_parameter(Parameter(
        "JibriInstanceMaxCount",
        Description="Max Number of Jibri instances to allow in environment",
        Type="Number",
        Default="20"
    ))

    jibri_instance_available_alarm_threshold = t.add_parameter(Parameter(
        "JibriUnavailableAlarmThreshold",
        Description= "Number of available jibris under which to alarm",
        Type= "Number",
        Default= "1"
    ))

    jibri_scaling_increase_rate = t.add_parameter(Parameter(
        "JibriScalingIncreaseRate",
        Description= "Number of jibris to scale up when below threshold",
        Type= "Number",
        Default= "3"
    ))

    jibri_scaling_decrease_rate = t.add_parameter(Parameter(
        "JibriScalingDecreaseRate",
        Description= "Number of jibris to scale down when above threshold",
        Type= "Number",
        Default= "1"
    ))


    jibri_boot_script_path = t.add_parameter(Parameter(
        "JibriBootScriptPath",
        Description="Jibri Script Path for Boot-time configuration",
        Type="String",
        Default="/home/jibri/scripts/aws-hook-boot.sh"
    ))

    jibri_instance_tenancy = t.add_parameter(Parameter(
        "JibriPlacementTenancy",
        Description="Jibri placement tenancy",
        Type= "String",
        Default= "default",
        AllowedValues= [
                "default",
                "dedicated"
        ],
        ConstraintDescription= "must be a valid and allowed EC2 instance placement tenancy."
    ))

    tag_name_param= t.add_parameter(Parameter(
        "TagName",
        Description="Tag: Name",
        Type="String",
        Default="hc-video-jibri"
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
        Default="all"
    ))

    tag_domain_name_param = t.add_parameter(Parameter(
        "TagDomainName",
        Description="Tag: domain_name",
        Type="String",
        Default=""
    ))

    tag_git_branch_param = t.add_parameter(Parameter(
        "TagGitBranch",
        Description="Tag: git_branch",
        Type="String",
        Default="main"
    ))

    tag_cloud_name_param = t.add_parameter(Parameter(
        "TagCloudName",
        Description="Tag: cloud_name",
        Type="String"
    ))

def create_jibri_template(filepath,enable_pagerduty_alarms=False,release_number=False,jibri_type=False):

    global t

    t = Template()

    t.add_version("2010-09-09")

    t.add_description(
        "Template for the provisioning AWS resources for the Jibri livestreaming component to an HC Video environment"
    )

    # Add params
    add_parameters(t)

    add_security(t)

    if jibri_type == 'sip-jibri':
        asg_subnets = sip_jibri_subnets
    else:
        asg_subnets = jibri_subnets

    jibri_launch_group = t.add_resource(LaunchConfiguration(
        "JibriLaunchGroup",
        ImageId=Ref("JibriImageId"),
        InstanceType=Ref("JibriInstanceType"),
        IamInstanceProfile=Ref("JibriServerSecurityInstanceProfile"),
        PlacementTenancy=Ref("JibriPlacementTenancy"),
        KeyName=Ref("KeyName"),
        SecurityGroups=[Ref("JibriSecurityGroup")],
        AssociatePublicIpAddress=False,
        InstanceMonitoring=False,
        BlockDeviceMappings=[BlockDeviceMapping(
            DeviceName="/dev/sda1",
            Ebs=EBSBlockDevice(
                VolumeSize=25
            )
        )],
        UserData=Base64(Join("", [

            "#!/bin/bash -v\n",
            "EXIT_CODE=0\n",
            "set -x\n",
            "status_code=0\n",
            "tmp_msg_file='/tmp/cfn_signal_message'\n",

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

            "export AWS_DEFAULT_REGION=", Ref("AWS::Region"), "\n",
            "export CLOUD_NAME=\"",Ref("TagCloudName"), "\"\n",
            "function install_apps(){\n",
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
            "status_code=0 && \\\n",
            "wget -P /root https://s3.amazonaws.com/cloudformation-examples/$CFN_FILE && \\\n",
            "mkdir -p /root/aws-cfn-bootstrap-latest && \\\n",
            "tar xvfz /root/$CFN_FILE --strip-components=1 -C /root/aws-cfn-bootstrap-latest --strip-components=1 -C /root/aws-cfn-bootstrap-latest && \\\n",
            "easy_install /root/aws-cfn-bootstrap-latest/ || status_code=1\n",
            "if [ $status_code -eq 1 ]; then echo 'Install apps stage failed' > $tmp_msg_file; return $status_code;fi\n"
            "}\n",

            "function provisioning(){\n",
            "status_code=0 && \\\n",
            Ref("JibriBootScriptPath")," >> /var/log/bootstrap.log 2>&1 || status_code=1\n",
            "if [ $status_code -eq 1 ]; then echo 'Provisioning stage failed' > $tmp_msg_file; return $status_code;fi;\n"
            "}\n",

            "( retry install_apps && retry provisioning ) ||  EXIT_CODE=1\n"

            "if [ ! -f /tmp/cfn_signal_message ]; then err_message='Server configuration';else err_message=$(cat $tmp_msg_file);fi\n",

            "if [ ! $EXIT_CODE -eq 0 ]; then /usr/local/bin/dump-jibri.sh;fi\n"

            "# Send signal about finishing configuring server\n",
            "/usr/local/bin/cfn-signal -e $EXIT_CODE -r \"$err_message\" '", Ref("JibriClientWaitHandle"), "'|| true\n",

            "if [ ! $EXIT_CODE -eq 0 ]; then shutdown -h now;fi\n"
        ]))

    ))

    jibri_client_wait_handle = t.add_resource(cloudformation.WaitConditionHandle(
        'JibriClientWaitHandle'
    ))

    jibri_client_wait_condition = t.add_resource(cloudformation.WaitCondition(
        'JibriClientWaitCondition',
        DependsOn="JibriAutoScaleGroup",
        Handle= Ref("JibriClientWaitHandle"),
        Timeout= 1800,
        Count= Ref("JibriInstanceInitialCount")
    ))

    jibri_tags = [
            Tag("Name", Join("-", [Ref("TagEnvironment"), Ref("AWS::Region"), Ref("JibriType")]), False),
            Tag("Environment",Ref("TagEnvironmentType"),True),
            Tag("Service",Ref("TagService"),True),
            Tag("Owner",Ref("TagOwner"),True),
            Tag("Team",Ref("TagTeam"),True),
            Tag("Product",Ref("TagProduct"),True),
            Tag("environment", Ref("TagEnvironment"), True),
            Tag("domain", Ref("TagDomainName"), True),
            Tag("shard-role",  Ref("JibriType"), True),
            Tag("git_branch", Ref("TagGitBranch"), True),
            Tag("cloud_name", Ref("TagCloudName"), True),
            Tag("datadog", Ref("DatadogEnabled"), True)
        ]

    if release_number:
        jibri_tags.append(Tag("jibri_release_number",release_number, True))

    jibri_autoscale_group = t.add_resource(AutoScalingGroup(
        "JibriAutoScaleGroup",
        AvailabilityZones= Ref("JibriAvailabilityZones"),
        Cooldown=600,
        DesiredCapacity= Ref("JibriInstanceDesiredCount"),
        HealthCheckGracePeriod=300,
        HealthCheckType="EC2",
        MaxSize= Ref("JibriInstanceMaxCount"),
        MinSize= Ref("JibriInstanceMinCount"),
        VPCZoneIdentifier=[asg_subnets],
        NotificationConfigurations=[NotificationConfigurations(
            TopicARN=Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("JibriASGAlarmSNS")]),
            NotificationTypes=[ "autoscaling:EC2_INSTANCE_LAUNCH", "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",  "autoscaling:EC2_INSTANCE_TERMINATE", "autoscaling:EC2_INSTANCE_TERMINATE_ERROR" ]
        )],
        LaunchConfigurationName=Ref("JibriLaunchGroup"),
        MetricsCollection=[MetricsCollection(
            Granularity="1Minute",
            Metrics=[
              "GroupDesiredCapacity",
              "GroupTerminatingInstances",
              "GroupInServiceInstances",
              "GroupMinSize",
              "GroupTotalInstances",
              "GroupMaxSize",
              "GroupPendingInstances"
            ]
        )],
        TerminationPolicies=["Default"],
        Tags=jibri_tags,
    ))

    scaling_increase_jibris = t.add_resource(ScalingPolicy(
        'scalingIncreaseJibris',
        ScalingAdjustment= Ref("JibriScalingIncreaseRate"),
        AdjustmentType= "ChangeInCapacity",
        AutoScalingGroupName= Ref("JibriAutoScaleGroup")
    ))

    scaling_decrease_jibris = t.add_resource(ScalingPolicy(
        'scalingDecreaseJibris',
        ScalingAdjustment=Join("",["-",Ref("JibriScalingDecreaseRate")]),
        AdjustmentType="ChangeInCapacity",
        AutoScalingGroupName=Ref("JibriAutoScaleGroup")
    ))

    high_jibri_usage = t.add_resource(Alarm(
        'HighJibriUsage',
        ActionsEnabled= True,
        ComparisonOperator= "LessThanThreshold",
        EvaluationPeriods= 2,
        MetricName= "jibri_available",
        Namespace=  "Video",
        Period= 60,
        Statistic= "Sum",
        Threshold= Ref("JibriInstanceAvailableCount"),
        OKActions= [
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("JibriASGAlarmSNS")])
        ],
        AlarmActions= [
          Join(":",["arn:aws:sns",Ref("AWS::Region"),Ref("AWS::AccountId"),Ref("JibriASGAlarmSNS")]),Ref("scalingIncreaseJibris")
        ],
        Dimensions= [MetricDimension(
            Name= "AutoScalingGroupName",
            Value= Ref("JibriAutoScaleGroup")
        )]
    ))

    low_jibri_usage = t.add_resource(Alarm(
        'LowJibriUsage',
        ActionsEnabled=True,
        ComparisonOperator="GreaterThanThreshold",
        EvaluationPeriods=10,
        MetricName="jibri_available",
        Namespace="Video",
        Period=60,
        Statistic="Sum",
        Threshold=Ref("JibriInstanceAvailableDownscaleCount"),
        OKActions=[
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("JibriASGAlarmSNS")])
        ],
        AlarmActions=[
            Ref("scalingDecreaseJibris"), Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("JibriASGAlarmSNS")])
        ],
        Dimensions=[MetricDimension(
            Name="AutoScalingGroupName",
            Value=Ref("JibriAutoScaleGroup")
        )]
    ))

    alarm_sns=[Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("JibriHealthAlarmSNS")])]
    pd_alarm_sns = alarm_sns.copy()

    if enable_pagerduty_alarms:
        pd_alarm_sns.append(Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("PagerDutySNSTopicName")]))

    unavailable_health_check = t.add_resource(Alarm(
        'JibriAvailableCheck',
        DependsOn=["JibriClientWaitCondition"],
        ComparisonOperator="LessThanThreshold",
        AlarmName=Join("-",[Ref("TagEnvironment"), Ref("RegionAlias"), Ref("StackNamePrefix"), Ref("JibriType"), "-Available-Hosts"]),
        EvaluationPeriods=5,
        MetricName="jibri_available",
        Namespace="Video",
        Period=60,
        TreatMissingData="missing",
        Statistic="Sum",
        Unit="Count",
        Threshold=Ref("JibriUnavailableAlarmThreshold"),
        AlarmActions=pd_alarm_sns,
        OKActions=pd_alarm_sns,
        InsufficientDataActions=pd_alarm_sns,
        Dimensions=[MetricDimension(
            Name="AutoScalingGroupName",
            Value=Ref("JibriAutoScaleGroup")
        )]
    ))

    unhealthy_count_health_check = t.add_resource(Alarm(
        'JibriUnhealthyCheck',
        DependsOn=["JibriClientWaitCondition"],
        ComparisonOperator="GreaterThanThreshold",
        AlarmName=Join("-",[Ref("TagEnvironment"), Ref("RegionAlias"), Ref("StackNamePrefix"), Ref("JibriType"), "-Unhealthy-Hosts"]),
        EvaluationPeriods=5,
        Threshold=0,
        Metrics=[
            MetricDataQuery(
                Expression="m2-m1",
                Id="e1",
                Label="unhealthy_jibris",
                ReturnData=True
            ),
            MetricDataQuery(
                Id="m1",
                ReturnData=False,
                MetricStat=MetricStat(
                    Stat="Sum",
                    Period=60,
                    Unit="Count",
                    Metric=Metric(
                        Namespace="Video",
                        MetricName="jibri_healthy",
                        Dimensions=[MetricDimension(
                            Name="AutoScalingGroupName",
                            Value=Ref("JibriAutoScaleGroup")
                        )]
                    )
                )
            ),
            MetricDataQuery(
                Id="m2",
                ReturnData=False,
                MetricStat=MetricStat(
                    Stat="SampleCount",
                    Period=60,
                    Unit="Count",
                    Metric=Metric(
                        Namespace="Video",
                        MetricName="jibri_healthy",
                        Dimensions=[MetricDimension(
                            Name="AutoScalingGroupName",
                            Value=Ref("JibriAutoScaleGroup")
                        )]
                    )
                )
            )
        ],
        TreatMissingData="missing",
        AlarmActions=alarm_sns,
        OKActions=alarm_sns,
        InsufficientDataActions=alarm_sns
    ))

    t.add_output([
        Output(
            'JibriAutoScaleGroup',
            Description="Jibri auto-scale group",
            Value=Ref("JibriAutoScaleGroup"),
        )
    ])

    data = json.loads(re.sub('shard_','shard-',t.to_json()))

    with open (filepath, 'w+') as outfile:
        json.dump(data, outfile)

def main():
    parser = argparse.ArgumentParser(description='Create jibri stack template')
    parser.add_argument('--region', action='store',
                        help='AWS region)', default=False, required=True)
    parser.add_argument('--stackprefix', action='store',
                        help='Stack prefix name', default=False, required=False)
    parser.add_argument('--region_alias', action='store',
                        help='region_alias name', default=False, required=False)
    parser.add_argument('--filepath', action='store',
                        help='Path to template file', default=False, required=False)
    parser.add_argument('--pull_network_stack', action='store',
                        help='Pull network variables from a network stack', default='true', required=True)
    parser.add_argument('--enable_pagerduty_alarms', action='store',
                        help='Enable PagerDuty alarms for stack', default=False)
    parser.add_argument('--release_number', action='store',
                        help='Release number', default=False)
    parser.add_argument('--jibri_type', action='store',
                        help='Type of jibri', default='java-jibri')

    args = parser.parse_args()

    if not args.region:
        print('No AWS region specified, exiting...')
        exit(1)
    elif not args.filepath:
        print ('No path to template file')
        exit(2)
    else:
        if args.pull_network_stack.lower() == "true":
            pull_network_stack_vars(region=args.region, region_alias=args.region_alias, stackprefix=args.stackprefix)
        else:
            pull_bash_network_vars()

        if args.enable_pagerduty_alarms.lower() == "true":
            enable_pagerduty_alarms=True
        else:
            enable_pagerduty_alarms=False

        if args.release_number.isspace():
            release_number=False
        else:
            release_number=args.release_number

        create_jibri_template(filepath=args.filepath,enable_pagerduty_alarms=enable_pagerduty_alarms,release_number=release_number,jibri_type=args.jibri_type)

if __name__ == '__main__':
    main()
