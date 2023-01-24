#!/usr/bin/env python

# pip install troposphere boto3

import boto3, re, argparse, json, os
from troposphere import Parameter, Ref, Template, Join, Base64, cloudformation, Tags, Output, GetAtt
from troposphere.autoscaling import Tag, AutoScalingGroup, LaunchConfiguration, BlockDeviceMapping, EBSBlockDevice, NotificationConfigurations, MetricsCollection, ScalingPolicy
from troposphere.cloudwatch import Alarm, MetricDimension
from troposphere.ec2 import SecurityGroupEgress,SecurityGroup,SecurityGroupIngress
from troposphere.elasticloadbalancing import LoadBalancer, ConnectionSettings, Listener, HealthCheck
from troposphere.policies import (
    AutoScalingReplacingUpdate, AutoScalingRollingUpdate, UpdatePolicy, CreationPolicy, ResourceSignal
)

def pull_network_stack_vars(region, region_alias, stackprefix):
    global vpc_id
    global ssh_security_group
    global nat_subnet_a
    global nat_subnet_b
    global jigasi_subnet_a
    global jigasi_subnet_b
    global jigasi_subnet_list
    global public_subnet_a
    global public_subnet_b

    if not region_alias:
        region_alias = region

    stack_name = region_alias + "-" + stackprefix + "-network"
    stack_name_jigasi = region_alias + "-" + stackprefix + "-jigasi-network"
    stack_name_nat = region_alias + "-" + stackprefix + "-NAT-network"

    client = boto3.client( 'cloudformation', region_name= region )
    response = client.describe_stacks(
        StackName= stack_name
    )
    response_jigasi = client.describe_stacks(
        StackName=stack_name_jigasi
    )
    response_nat = client.describe_stacks(
        StackName=stack_name_nat
    )

    for stack in response["Stacks"]:
            outputs = dict([(x['OutputKey'], x['OutputValue']) for x in stack['Outputs']])
            vpc_id = outputs.get('VPC')
            ssh_security_group = outputs.get('SSHSecurityGroup')
            public_subnet_a = outputs.get('PublicSubnetA')
            public_subnet_b = outputs.get('PublicSubnetB')

    for stack in response_jigasi["Stacks"]:
            outputs = dict([(x['OutputKey'], x['OutputValue']) for x in stack['Outputs']])
            jigasi_subnet_a = outputs.get('JigasiSubnetA')
            jigasi_subnet_b = outputs.get('JigasiSubnetB')
            jigasi_subnet_list = outputs.get('JigasiSubnetsIds').split(',')

    for stack in response_nat["Stacks"]:
            outputs = dict([(x['OutputKey'], x['OutputValue']) for x in stack['Outputs']])
            nat_subnet_a = outputs.get('NATSubnetA')
            nat_subnet_b = outputs.get('NATSubnetB')


def pull_bash_network_vars():

    global vpc_id
    global ssh_security_group
    global jigasi_subnet_a
    global jigasi_subnet_b
    global nat_subnet_a
    global nat_subnet_b
    global public_subnet_a
    global public_subnet_b

    vpc_id = os.environ['EC2_VPC_ID']
    ssh_security_group = os.environ['SSH_SECURITY_GROUP']
    jigasi_subnet_a = os.environ['DEFAULT_JIGASI_SUBNET_ID_a']
    jigasi_subnet_b = os.environ['DEFAULT_JIGASI_SUBNET_ID_b']
    public_subnet_a = os.environ['DEFAULT_PUBLIC_SUBNET_ID_a']
    public_subnet_b = os.environ['DEFAULT_PUBLIC_SUBNET_ID_b']


def add_parameters(use_haproxy=False, use_pagerduty=False, use_elb=True):
    s3_bucket_name_param = t.add_parameter(Parameter(
        "S3BucketName",
        Description= "Name of the bucket with assets for bootstrapping",
        Type= "String",
        Default=" jitsi-bootstrap-assets"
    ))

    s3_dump_bucket_name_param = t.add_parameter(Parameter(
        "S3DumpBucketName",
        Description= "Name of the bucket with dump details",
        Type= "String",
        Default="jitsi-infra-dumps"
    ))

    key_name_param = t.add_parameter(Parameter(
        "KeyName",
        Description= "Name of an existing EC2 KeyPair to enable SSH access to the ec2 hosts",
        Type= "String",
        MinLength= 1,
        MaxLength= 64,
        AllowedPattern= "[-_ a-zA-Z0-9]*",
        ConstraintDescription= "can contain only alphanumeric characters, spaces, dashes and underscores."

    ))

    if use_elb:
        elb_name_param = t.add_parameter(Parameter(
            "ELBName",
            Description= "Name of ELB",
            Type= "String",
            MinLength= 1,
            MaxLength = 32,
            AllowedPattern= "[-_ a-zA-Z0-9]*",
            ConstraintDescription= "can contain only alphanumeric characters, spaces, dashes and underscores.",
            Default= "JigasiELB"
        ))
        jigasi_ssl_certificate_id_param = t.add_parameter(Parameter(
            "JigasiSSLCertificateID",
            Description= "SSL Certificate ID to use for Jigasi ELB",
            Type= "String"
        ))

    region_alias_param = t.add_parameter(Parameter(
        "RegionAlias",
        Description= "Alias for AWS Region",
        Type= "String"
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

    stack_name_prefix_param = t.add_parameter(Parameter(
        "StackNamePrefix",
        Description= "Prefix for stack",
        Type= "String",
        Default= "vaas",
    ))



    jigasi_image_id_param = t.add_parameter(Parameter(
        "JigasiImageId",
        Description= "Jigasi instance AMI id",
        Type= "AWS::EC2::Image::Id",
        ConstraintDescription= "must be a valid and allowed AMI id."
    ))

    jigasi_instance_type_param = t.add_parameter(Parameter(
        "JigasiInstanceType",
        Description= "Jigasi server instance type",
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
            "m4.large",
            "m5.large",
            "c4.large",
            "c4.xlarge",
            "c5.xlarge",
            "c5.2xlarge",
            "c5.4xlarge",
            "c5.9xlarge"
         ],
        ConstraintDescription= "must be a valid and allowed EC2 instance type."
    ))
    if use_haproxy:
        haproxy_image_id_param = t.add_parameter(Parameter(
            "HAProxyImageId",
            Description= "HAProxy instance AMI id",
            Type= "AWS::EC2::Image::Id",
            ConstraintDescription= "must be a valid and allowed AMI id."
        ))

        haproxy_instance_type_param = t.add_parameter(Parameter(
            "HAProxyInstanceType",
            Description= "HAProxy load-balancing server instance type",
            Type= "String",
            Default= "t3.small",
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
                "m4.large",
                "m5.large",
                "c4.large",
                "c4.xlarge",
                "c5.xlarge"
            ],
            ConstraintDescription= "must be a valid and allowed EC2 instance type."
        ))
        haproxy_asg_desired_count_param = t.add_parameter(Parameter(
            "HAProxyASGDesiredCount",
            Description= "Desired count of haproxy",
            Type= "Number",
            Default=2
        ))
        haproxy_server_security_instance_profile_param = t.add_parameter(Parameter(
            "HAProxyServerSecurityInstanceProfile",
            Description= "Jigasi Security Instance Profile",
            Type= "String",
            Default= "HipChatVideo-LoadBalancer"
        ))


    jigasi_instance_virtualization_param = t.add_parameter(Parameter(
        "JigasiInstanceVirtualization",
        Description= "Jigasi server instance virtualization",
        Default= "PV",
        Type= "String",
        AllowedValues= ["HVM", "PV"],
        ConstraintDescription= "Must be a valid and allowed virtualization type."
    ))

    jigasi_availability_zone_param = t.add_parameter(Parameter(
        "JigasiAvailabilityZones",
        Description= "AZ for Jigasi ASG",
        Type= "List<AWS::EC2::AvailabilityZone::Name>",
        Default= "us-east-1a,us-east-1b",
        ConstraintDescription= "must be a valid and allowed availability zone."
    ))

    jigasi_health_alarm_sns_param = t.add_parameter(Parameter(
        "JigasiHealthAlarmSNS",
        Description= "SNS topic for ASG Alarms related to Jigasi",
        Type= "String",
        Default= "chaos-Health-Check-List"  

    ))

    jigasi_asg_alarm_sns_param = t.add_parameter(Parameter(
        "JigasiASGAlarmSNS",
        Description= "SNS topic for ASG Alarms related to Jigasi",
        Type= "String",
        Default= "chaos-ASG-alarms"

    ))

    if use_pagerduty:
        jigasi_pagerduty_alarm_sns_param = t.add_parameter(Parameter(
            "PagerDutyJigasiSNSTopic",
            Description= "SNS topic for PagerDuty Alarms related to Jigasi",
            Type= "String",
            Default= "PagerDutyJigasiAlarms"
        ))

    jigasi_asg_desired_count_param = t.add_parameter(Parameter(
        "JigasiASGDesiredCount",
        Description= "Desired count of jigasis",
        Type= "Number",
        Default=2
    ))

    jigasi_asg_initial_count_param = t.add_parameter(Parameter(
        "JigasiASGInitialCount",
        Description= "Initial count of jigasis",
        Type= "Number",
        Default=2
    ))


    jigasi_asg_max_count_param = t.add_parameter(Parameter(
        "JigasiASGMaxCount",
        Description= "Maximum count of jigasis",
        Type= "Number",
        Default=20
    ))

    jigasi_asg_min_count_param = t.add_parameter(Parameter(
        "JigasiASGMinCount",
        Description= "Minimum count of jigasis",
        Type= "Number",
        Default=2
    ))

    jigasi_server_security_instance_profile_param = t.add_parameter(Parameter(
        "JigasiServerSecurityInstanceProfile",
        Description= "Jigasi Security Instance Profile",
        Type= "String",
        Default= "HipChatVideo-Jigasi"
    ))

    network_security_group_param = t.add_parameter(Parameter(
        'NetworkSecurityGroup',
        Description= "Core Security Group",
        Type= "String",
        Default= "sg-a075cac6"
    ))
    associate_public_ip = t.add_parameter(Parameter(
        'JigasiAssociatePublicIpAddress',
        Description= "Indicates whether to include public IP for jigasi",
        Type= "String",
        Default= "false"
    ))

    tag_name_param = t.add_parameter(Parameter(
        "TagStartingWeight",
        Description= "Tag: jigasi_weight",
        Type= "String",
        Default= "255"
    ))

    tag_name_param = t.add_parameter(Parameter(
        "TagName",
        Description= "Tag: Name",
        Type= "String",
        Default= "hc-video-jigasi"
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
        Description= "Tag: environment",
        Type= "String",
        Default=  "all"
    ))

    tag_domain_name_param = t.add_parameter(Parameter(
        "TagDomainName",
        Description= "Tag: domain_name",
        Type= "String",
        Default= ""
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
        Type="String",
        Default="dc1"
    ))

def add_security(use_haproxy=False, use_elb=True, jigasi_role="jigasi"):
    group_name = "JigasiGroup"
    group_desc = "Jigasi nodes"
    if jigasi_role == "jigasi-transcriber":
        group_name="TranscriberGroup"
        group_desc = "Jigasi transcriber nodes"

    jigasi_security_group = t.add_resource(SecurityGroup(
        "JigasiSecurityGroup",
        GroupDescription=Join(' ', [group_desc, Ref("TagEnvironment"), Ref("RegionAlias"),
                                    Ref("StackNamePrefix")]),
        VpcId=vpc_id,
        Tags=Tags(
            Name=Join("-", [Ref("TagEnvironment"), Ref("RegionAlias"), Ref("StackNamePrefix"), group_name]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role=jigasi_role,
        )
    ))

    ingress14 = t.add_resource(SecurityGroupIngress(
        "ingress14",
        GroupId=Ref("JigasiSecurityGroup"),
        IpProtocol="tcp",
        FromPort="22",
        ToPort="22",
        SourceSecurityGroupId= ssh_security_group,
        SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
    ))

    egress1 = t.add_resource(SecurityGroupEgress(
        "egress1",
        GroupId=Ref("JigasiSecurityGroup"),
        IpProtocol="-1",
        CidrIp='0.0.0.0/0',
        FromPort='-1',
        ToPort='-1'
    ))

    if use_elb:
        jigasi_security_group = t.add_resource(SecurityGroup(
            "JigasiLBSecurityGroup",
            GroupDescription=Join(' ', ["Jigasi LB", Ref("TagEnvironment"), Ref("RegionAlias"),
                                        Ref("StackNamePrefix")]),
            VpcId=vpc_id,
            Tags=Tags(
                Name=Join("-", [Ref("TagEnvironment"), Ref("RegionAlias"), Ref("StackNamePrefix"), "JigasiLBGroup"]),
                Environment=Ref("TagEnvironmentType"),
                Service=Ref("TagService"),
                Owner=Ref("TagOwner"),
                Team=Ref("TagTeam"),
                Product=Ref("TagProduct"),
                environment=Ref("TagEnvironment"),
                role="jigasi-lb",
            )
        ))

        ingress10 = t.add_resource(SecurityGroupIngress(
            "ingress10",
            GroupId=Ref("JigasiSecurityGroup"),
            IpProtocol="tcp",
            FromPort="443",
            ToPort="443",
            SourceSecurityGroupId=Ref("JigasiLBSecurityGroup"),
            SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
        ))

        ingress11 = t.add_resource(SecurityGroupIngress(
            "ingress11",
            GroupId=Ref("JigasiSecurityGroup"),
            IpProtocol="tcp",
            FromPort="80",
            ToPort="80",
            SourceSecurityGroupId=Ref("JigasiLBSecurityGroup"),
            SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
        ))
        ingress12 = t.add_resource(SecurityGroupIngress(
            "ingress12",
            GroupId=Ref("JigasiLBSecurityGroup"),
            IpProtocol="tcp",
            FromPort="443",
            ToPort="443",
            CidrIp='0.0.0.0/0'
        ))

        ingress13 = t.add_resource(SecurityGroupIngress(
            "ingress13",
            GroupId=Ref("JigasiLBSecurityGroup"),
            IpProtocol="tcp",
            FromPort="80",
            ToPort="80",
            CidrIp='0.0.0.0/0'
        ))
    

        ingress16 = t.add_resource(SecurityGroupIngress(
            "ingress16",
            GroupId=Ref("JigasiLBSecurityGroup"),
            IpProtocol="tcp",
            FromPort="80",
            ToPort="80",
            CidrIpv6="::/0"
        ))

        ingress17 = t.add_resource(SecurityGroupIngress(
            "ingress17",
            GroupId=Ref("JigasiLBSecurityGroup"),
            IpProtocol="tcp",
            FromPort="443",
            ToPort="443",
            CidrIpv6="::/0"
        ))

        egress2 = t.add_resource(SecurityGroupEgress(
            "egress2",
            GroupId=Ref("JigasiLBSecurityGroup"),
            IpProtocol="-1",
            CidrIp='0.0.0.0/0',
            FromPort='-1',
            ToPort='-1'
        ))



    if use_haproxy:
        jigasi_haproxy_security_group = t.add_resource(SecurityGroup(
            "JigasiHAProxySecurityGroup",
            GroupDescription=Join(' ', ["Jigasi haproxy", Ref("TagEnvironment"), Ref("RegionAlias"),
                                        Ref("StackNamePrefix")]),
            VpcId=vpc_id,
            Tags=Tags(
                Name=Join("-", [Ref("TagEnvironment"), Ref("RegionAlias"), Ref("StackNamePrefix"), "JigasiHAProxy"]),
                Environment=Ref("TagEnvironmentType"),
                Service=Ref("TagService"),
                Owner=Ref("TagOwner"),
                Team=Ref("TagTeam"),
                Product=Ref("TagProduct"),
                environment=Ref("TagEnvironment"),
                role="jigasi-haproxy",
            )
        ))
        ingress18 = t.add_resource(SecurityGroupIngress(
            "ingress18",
            GroupId=Ref("JigasiSecurityGroup"),
            IpProtocol="tcp",
            FromPort="80",
            ToPort="80",
            SourceSecurityGroupId=Ref("JigasiHAProxySecurityGroup"),
            SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
        ))

        ingress19 = t.add_resource(SecurityGroupIngress(
            "ingress19",
            GroupId=Ref("JigasiSecurityGroup"),
            IpProtocol="tcp",
            FromPort="443",
            ToPort="443",
            SourceSecurityGroupId=Ref("JigasiHAProxySecurityGroup"),
            SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
        ))

        ingress20 = t.add_resource(SecurityGroupIngress(
            "ingress20",
            GroupId=Ref("JigasiHAProxySecurityGroup"),
            IpProtocol="tcp",
            FromPort="443",
            ToPort="443",
            CidrIp='0.0.0.0/0'
        ))

        ingress21 = t.add_resource(SecurityGroupIngress(
            "ingress21",
            GroupId=Ref("JigasiHAProxySecurityGroup"),
            IpProtocol="tcp",
            FromPort="80",
            ToPort="80",
            CidrIp='0.0.0.0/0'
        ))

        ingress22 = t.add_resource(SecurityGroupIngress(
            "ingress22",
            GroupId=Ref("JigasiHAProxySecurityGroup"),
            IpProtocol="tcp",
            FromPort="80",
            ToPort="80",
            CidrIpv6="::/0"
        ))

        ingress23 = t.add_resource(SecurityGroupIngress(
            "ingress23",
            GroupId=Ref("JigasiHAProxySecurityGroup"),
            IpProtocol="tcp",
            FromPort="443",
            ToPort="443",
            CidrIpv6="::/0"
        ))

        ingress24 = t.add_resource(SecurityGroupIngress(
            "ingress24",
            GroupId=Ref("JigasiHAProxySecurityGroup"),
            IpProtocol="tcp",
            FromPort="22",
            ToPort="22",
            SourceSecurityGroupId= ssh_security_group,
            SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
        ))

        ingress25 = t.add_resource(SecurityGroupIngress(
            "ingress25",
            GroupId=Ref("JigasiHAProxySecurityGroup"),
            IpProtocol="tcp",
            FromPort="8080",
            ToPort="8080",
            SourceSecurityGroupId=Ref("JigasiLBSecurityGroup"),
            SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
        ))

        ingress26 = t.add_resource(SecurityGroupIngress(
            "ingress26",
            GroupId=Ref("JigasiSecurityGroup"),
            IpProtocol="tcp",
            FromPort="7070",
            ToPort="7070",
            SourceSecurityGroupId=Ref("JigasiHAProxySecurityGroup"),
            SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
        ))

        egress3 = t.add_resource(SecurityGroupEgress(
            "egress3",
            GroupId=Ref("JigasiHAProxySecurityGroup"),
            IpProtocol="-1",
            CidrIp='0.0.0.0/0',
            FromPort='-1',
            ToPort='-1'
        ))

def create_jigasi_template(filepath, use_haproxy=False, use_pagerduty=False, use_elb=True, jigasi_role="jigasi"):

    global t

    t = Template()

    t.add_version("2010-09-09")

    t.add_description(
        "Template for Jigasi SIP functionality for one environment in one region"
    )

    # Add params
    add_parameters(use_haproxy=use_haproxy,use_pagerduty=use_pagerduty,use_elb=use_elb)

    # Add security rules
    add_security(use_haproxy=use_haproxy, use_elb=use_elb, jigasi_role=jigasi_role)

    if use_elb:
        elb_health_target="HTTP:80/about/health"
        if use_haproxy:
            elb_health_target="HTTP:8080/haproxy_health"

        jigasi_elb = t.add_resource(LoadBalancer(
            "JigasiELB",
            LoadBalancerName= Ref("ELBName"),
            CrossZone= True,
            ConnectionSettings= ConnectionSettings(
                IdleTimeout= 30
            ),
            Listeners= [
                Listener(
                    InstancePort= 80,
                    InstanceProtocol= "HTTP",
                    LoadBalancerPort= 80,
                    Protocol= "HTTP"
                ),
                Listener(
                    InstancePort=80,
                    InstanceProtocol="HTTP",
                    LoadBalancerPort=443,
                    SSLCertificateId= Join("", ["arn:aws:iam::",Ref("AWS::AccountId"),
                    ":server-certificate/",Ref("JigasiSSLCertificateID")]),
                    Protocol="HTTPS"
                )
            ],
            HealthCheck= HealthCheck(
                HealthyThreshold= 10,
                Interval= 5,
                Target= elb_health_target,
                Timeout= 2,
                UnhealthyThreshold= 2
            ),
            Scheme= "internet-facing",
            SecurityGroups= [Ref("JigasiLBSecurityGroup")],
            Subnets= [public_subnet_a, public_subnet_b],
            Tags=Tags(
                Name=Join("-", [Ref("TagEnvironment"), Ref("RegionAlias"), Ref("StackNamePrefix"), "jigasi"]),
                Environment=Ref("TagEnvironmentType"),
                Service=Ref("TagService"),
                Owner=Ref("TagOwner"),
                Team=Ref("TagTeam"),
                Product=Ref("TagProduct"),
                environment=Ref("TagEnvironment"),
                domain=Ref("TagDomainName"),
                shard_role="ELB",
            )
        ))

    jigasi_launch_group = t.add_resource(LaunchConfiguration(
        "JigasiLaunchGroup",
        ImageId=Ref("JigasiImageId"),
        InstanceType=Ref("JigasiInstanceType"),
        IamInstanceProfile=Ref("JigasiServerSecurityInstanceProfile"),
        KeyName=Ref("KeyName"),
        SecurityGroups=[Ref("JigasiSecurityGroup")],
        AssociatePublicIpAddress=Ref("JigasiAssociatePublicIpAddress"),
        InstanceMonitoring=False,
        BlockDeviceMappings=[BlockDeviceMapping(
            DeviceName="/dev/sda1",
            Ebs=EBSBlockDevice(
                VolumeSize=8
            )
        )],
        UserData=Base64(Join('', [
            "#!/bin/bash -v\n",
            "EXIT_CODE=0\n",
            "set -x\n",

            "export AWS_DEFAULT_REGION=", {"Ref": "AWS::Region"}, "\n",
            "export CLOUD_NAME=\"", {"Ref": "TagCloudName"}, "\"\n",

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
            "easy_install /root/aws-cfn-bootstrap-latest/\n",

            "/usr/local/bin/postinstall-jigasi.sh >> /var/log/bootstrap.log 2>&1 || EXIT_CODE=1\n",

            "if [ ! $EXIT_CODE -eq 0 ]; then /usr/local/bin/dump-jigasi.sh;fi\n"

            "# Send signal about finishing configuring server\n",
            "/usr/local/bin/cfn-signal -e $EXIT_CODE -r 'Server configuration' --resource JigasiAutoScaleGroup --stack '", {"Ref": "AWS::StackName"}, "' --region ", { "Ref" : "AWS::Region" }, " || true\n",

            "if [ ! $EXIT_CODE -eq 0 ]; then shutdown -h now;fi\n"
        ]))
    ))

    if use_haproxy:
        haproxy_launch_group = t.add_resource(LaunchConfiguration(
            "HAProxyLaunchGroup",
            ImageId=Ref("HAProxyImageId"),
            InstanceType=Ref("HAProxyInstanceType"),
            IamInstanceProfile=Ref("HAProxyServerSecurityInstanceProfile"),
            KeyName=Ref("KeyName"),
            SecurityGroups=[Ref("JigasiHAProxySecurityGroup")],
            AssociatePublicIpAddress=Ref("JigasiAssociatePublicIpAddress"),
            InstanceMonitoring=False,
            UserData=Base64(Join('', [
                "#!/bin/bash -v\n",
                "EXIT_CODE=0\n",
                "set -x\n",

                "export AWS_DEFAULT_REGION=\"", {"Ref": "AWS::Region"}, "\"\n",
                "export CLOUD_NAME=\"", {"Ref": "TagCloudName"}, "\"\n",
                "export ENVIRONMENT=\"", {"Ref": "TagEnvironment"}, "\"\n",
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

                "S3_BUCKET=\"",Ref("S3BucketName"),"\"\n",
                "DUMP_BUCKET=\"",Ref("S3DumpBucketName"),"\"\n",
                "/usr/local/bin/aws s3 cp s3://$S3_BUCKET/vault-password /root/.vault-password\n",
                "/usr/local/bin/aws s3 cp s3://$S3_BUCKET/id_rsa_jitsi_deployment /root/.ssh/id_rsa\n",
                "chmod 400 /root/.ssh/id_rsa\n",

                "ansible-pull -v -U git@github.com:8x8Cloud/jitsi-video-infrastructure.git -d /tmp/bootstrap -i \"127.0.0.1,\" ",
                "--vault-password-file=/root/.vault-password --accept-host-key -C ",Ref("TagGitBranch"),
                " --extra-vars \"cloud_name=$CLOUD_NAME hcv_environment=$ENVIRONMENT\"",
                " ansible/configure-jigasi-haproxy-local.yml >> /var/log/bootstrap.log 2>&1 || EXIT_CODE=1\n",

                "if [ ! $EXIT_CODE -eq 0 ]; then\n",
                  "DUMP=\"$(hostname)-$(date +%s)\"\n",
                  "/usr/local/bin/aws s3 cp /var/log/bootstrap.log s3://$DUMP_BUCKET/jigasi/$DUMP-bootstrap.log\n",
                  "/usr/local/bin/aws s3 cp /var/log/cloud-init-output.log s3://$DUMP_BUCKET/jigasi/$DUMP-cloud-init-output.log\n",
                  "/usr/local/bin/aws s3 cp /var/log/syslog s3://$DUMP_BUCKET/jigasi/$DUMP-syslog\n",
                "fi\n",

                "# Send signal about finishing configuring server\n",
                "/usr/local/bin/cfn-signal -e $EXIT_CODE -r 'Server configuration' --resource HAProxyAutoScaleGroup --stack '", {"Ref": "AWS::StackName"}, "' --region ", { "Ref" : "AWS::Region" }, " || true\n",

                "if [ ! $EXIT_CODE -eq 0 ]; then shutdown -h now;fi\n"
            ]))
        ))

        haproxy_autoscale_group = t.add_resource(AutoScalingGroup(
            "HAProxyAutoScaleGroup",
            AvailabilityZones=Ref("JigasiAvailabilityZones"),
            Cooldown=300,
            DesiredCapacity=Ref("HAProxyASGDesiredCount"),
            HealthCheckGracePeriod=300,
            HealthCheckType="EC2",
            MaxSize=Ref("HAProxyASGDesiredCount"),
            MinSize=Ref("HAProxyASGDesiredCount"),
            LoadBalancerNames=[Ref("JigasiELB")],
            VPCZoneIdentifier=[nat_subnet_a, nat_subnet_b],
            LaunchConfigurationName=Ref("HAProxyLaunchGroup"),
            Tags=[
                Tag("Name", Join("-", [Ref("TagEnvironment"), Ref("RegionAlias"), Ref("StackNamePrefix"), "jigasi-haproxy"]),
                    False),
                Tag("Environment",Ref("TagEnvironmentType"),True),
                Tag("Service",Ref("TagService"),True),
                Tag("Owner",Ref("TagOwner"),True),
                Tag("Team",Ref("TagTeam"),True),
                Tag("Product",Ref("TagProduct"),True),
                Tag("environment", Ref("TagEnvironment"), True),
                Tag("domain", Ref("TagDomainName"), True),
                Tag("shard-role", "jigasi-haproxy", True),
                Tag("git_branch", Ref("TagGitBranch"), True),
                Tag("datadog", Ref("DatadogEnabled"), True),
                Tag("cloud_name", Ref("TagCloudName"), True),
                Tag("jigasi_asg",Ref("JigasiAutoScaleGroup"), True)
            ],
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
            CreationPolicy=CreationPolicy(
                ResourceSignal=ResourceSignal(
                    Count=Ref("HAProxyASGDesiredCount"),
                    Timeout='PT60M'))
        ))

    #only attach the jigasi autoscaling group directly to the ELB if no haproxy is enabled
    lb_names = []
    if use_elb:
        if not use_haproxy:
            lb_names = [Ref("JigasiELB")]

    if jigasi_role == 'jigasi-transcriber':
        # don't use a load balancer if in transcriber mode
        jigasi_subnets = [nat_subnet_a, nat_subnet_b]
    else:
        jigasi_subnets = jigasi_subnet_list

    jigasi_autoscale_group = t.add_resource(AutoScalingGroup(
        "JigasiAutoScaleGroup",
        AvailabilityZones=Ref("JigasiAvailabilityZones"),
        Cooldown=300,
        DesiredCapacity=Ref("JigasiASGDesiredCount"),
        HealthCheckGracePeriod=300,
        HealthCheckType="EC2",
        LoadBalancerNames=lb_names,
        MaxSize=Ref("JigasiASGMaxCount"),
        MinSize=Ref("JigasiASGMinCount"),
        VPCZoneIdentifier=jigasi_subnets,
        NotificationConfigurations=[NotificationConfigurations(
            TopicARN=Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("JigasiASGAlarmSNS")]),

            NotificationTypes=[ "autoscaling:EC2_INSTANCE_LAUNCH", "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
                                "autoscaling:EC2_INSTANCE_TERMINATE", "autoscaling:EC2_INSTANCE_TERMINATE_ERROR" ]
        )],
        LaunchConfigurationName=Ref("JigasiLaunchGroup"),
        Tags=[
            Tag("Name", Join("-", [Ref("TagEnvironment"), Ref("RegionAlias"), Ref("StackNamePrefix"),jigasi_role]),
                False),
            Tag("Environment",Ref("TagEnvironmentType"),True),
            Tag("Service",Ref("TagService"),True),
            Tag("Owner",Ref("TagOwner"),True),
            Tag("Team",Ref("TagTeam"),True),
            Tag("Product",Ref("TagProduct"),True),
            Tag("environment", Ref("TagEnvironment"), True),
            Tag("domain", Ref("TagDomainName"), True),
            Tag("shard-role", jigasi_role, True),
            Tag("git_branch", Ref("TagGitBranch"), True),
            Tag("datadog", Ref("DatadogEnabled"), True),
            Tag("cloud_name", Ref("TagCloudName"), True),
            Tag("jigasi_weight", Ref("TagStartingWeight"), True)
        ],
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
        CreationPolicy=CreationPolicy(
            ResourceSignal=ResourceSignal(
                Count=Ref("JigasiASGDesiredCount"),
                Timeout='PT60M'))

    ))

    scaling_high_participants = t.add_resource(ScalingPolicy(
        "scalingHighParticipants",
        ScalingAdjustment= 1,
        AdjustmentType= "ChangeInCapacity",
        AutoScalingGroupName= Ref("JigasiAutoScaleGroup")
    ))

    scaling_low_participants = t.add_resource(ScalingPolicy(
        "scalingLowParticipants",
        ScalingAdjustment= -1,
        AdjustmentType= "ChangeInCapacity",
        AutoScalingGroupName= Ref("JigasiAutoScaleGroup")
    ))

    high_jigasi_participants = t.add_resource(Alarm(
        "HighJigasiParticipants",
        ActionsEnabled= True,
        ComparisonOperator= "GreaterThanOrEqualToThreshold",
        EvaluationPeriods= 1,
        MetricName= "jigasi_participants",
        Namespace=  "Video",
        Period= 60,
        Statistic= "Average",
        Threshold= "100.0",
        AlarmActions= [
            Join(":", [ "arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("JigasiASGAlarmSNS")]),
            Ref("scalingHighParticipants")
        ],
        OKActions= [
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("JigasiASGAlarmSNS")]),
        ],
        Dimensions= [MetricDimension(
            Name= "AutoScalingGroupName",
            Value= Ref("JigasiAutoScaleGroup")
        )

        ]

    ))

    low_jigasi_participants = t.add_resource(Alarm(
        "LowJigasiParticipants",
        ActionsEnabled=True,
        ComparisonOperator="LessThanThreshold",
        EvaluationPeriods=360,
        MetricName="jigasi_participants",
        Namespace="Video",
        Period=60,
        Statistic="Average",
        Threshold="50.0",
        AlarmActions=[
            Ref("scalingLowParticipants"),
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("JigasiASGAlarmSNS")])
        ],
        OKActions=[
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("JigasiASGAlarmSNS")]),
        ],
        Dimensions=[MetricDimension(
            Name="AutoScalingGroupName",
            Value=Ref("JigasiAutoScaleGroup")
        )

        ]

    ))

    if use_elb:
        elb_health_depends = ["JigasiELB"]
        elb_health_threshold = Ref("JigasiASGMinCount")
        elb_health_name = "jigasi-Unhealthy"

        if use_haproxy:
            elb_health_depends.append("HAProxyAutoScaleGroup")
            elb_health_threshold = Ref("HAProxyASGDesiredCount")
            elb_health_name = "jigasi-haproxy-Unhealthy"

        elb_health_actions=[Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("JigasiHealthAlarmSNS")])]
        if use_pagerduty:
            elb_health_actions.append(Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("PagerDutyJigasiSNSTopic")]))

        elb_hosts_health_check = t.add_resource(Alarm(
            'ELBHostHealthCheck',
            DependsOn=elb_health_depends,
            ComparisonOperator="LessThanThreshold",
            AlarmName=Join("-",[Ref("TagEnvironment"), Ref("RegionAlias"), Ref("StackNamePrefix"), elb_health_name]),
            EvaluationPeriods=2,
            MetricName="HealthyHostCount",
            Namespace="AWS/ELB",
            Period=60,
            TreatMissingData="missing",
            Statistic="Minimum",
            Unit="Count",
            Threshold=elb_health_threshold,
            AlarmActions=elb_health_actions,
            OKActions=elb_health_actions,
            InsufficientDataActions=elb_health_actions,
            Dimensions=[MetricDimension(
                Name="LoadBalancerName",
                Value=Ref("ELBName")
            )]
        ))


        t.add_output([
            Output(
                "ELB",
                Description= "The ELB ID",
                Value= Ref("JigasiELB")
            ),
            Output(
                "ELBDNSName",
                Description= "The ELB Endpoint",
                Value= GetAtt("JigasiELB", "DNSName")
            )
        ])


    data = json.loads(re.sub('shard_','shard-',t.to_json()))

    with open (filepath, 'w+') as outfile:
        json.dump(data, outfile)

def main():
    parser = argparse.ArgumentParser(description= 'Create Jigasi stack template')
    parser.add_argument('--region', action= 'store',
                        help= 'AWS region', default= False, required= True)
    parser.add_argument('--region_alias', action= 'store',
                        help= 'AWS region alias', default= False, required= True)
    parser.add_argument('--stackprefix', action= 'store',
                        help= 'Stack prefix name', default= False, required= False)
    parser.add_argument('--filepath', action= 'store',
                        help= 'Path to tenmplate file', default= False, required= False)
    parser.add_argument('--pull_network_stack', action='store',
                       help='Pull network variables from a network stack', default='true', required=True)
    parser.add_argument('--use_haproxy', action='store_true',
                        help= 'Flag to control whether to include haproxy instances or load balance jigasi directly', default=False, required=False)
    parser.add_argument('--use_pagerduty', action='store_true',
                        help= 'Flag to control whether to send alarms to pagerduty', default=False, required=False)
    parser.add_argument('--transcriber', action='store_true',
                        help= 'Flag to control whether to operate in transcriber mode', default=False, required=False)
    args = parser.parse_args()

    if not args.region:
        print('No AWS region specified, exiting...')
        exit(1)
    elif not args.filepath:
        print ('No path to template file')
        exit(2)
    else:
        if args.pull_network_stack.lower() == "true":
            pull_network_stack_vars(region= args.region, region_alias= args.region_alias, stackprefix= args.stackprefix)
        else:
            pull_bash_network_vars()

        # by default include an ELB for an inbound jigasi selector
        use_elb = True
        use_haproxy = args.use_haproxy
        jigasi_role="jigasi"
        if args.transcriber:
            # in transcriber mode do not include an elb, set custom role
            use_elb = False
            use_haproxy = False
            jigasi_role="jigasi-transcriber"

        create_jigasi_template(filepath= args.filepath, use_haproxy=use_haproxy, use_pagerduty=args.use_pagerduty, use_elb=use_elb, jigasi_role=jigasi_role)

if __name__ == '__main__':
    main()
