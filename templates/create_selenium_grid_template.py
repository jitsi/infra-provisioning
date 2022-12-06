#!/usr/bin/env python

from templatelib import *

import boto3, re, argparse, json, os
from troposphere import Parameter, Ref, Template, Join, Tags, Base64, Output, GetAtt,cloudformation

from troposphere.elasticloadbalancing import *

from troposphere.ec2 import Instance, SecurityGroup
from troposphere.autoscaling import Tag, AutoScalingGroup, LaunchConfiguration, BlockDeviceMapping, EBSBlockDevice, NotificationConfigurations, MetricsCollection, ScalingPolicy

from troposphere.route53 import RecordSetType

# whitelist of incoming requests for the grid
global elb_whitelist
elb_whitelist = [
'54.244.50.32/27', #aws mobile testfarm
'52.91.10.63/32', #beta.meet.mit.si
'35.153.254.119/32', #ci.jitsi.org
'52.90.18.53/32', #prtorture
'34.192.231.140/32', #jenkins2
'72.48.156.248/29', #atlassian austin office
'54.158.246.50/32', #george fatline
'54.162.112.248/32', #george BWE
'52.41.182.55/32', # jenkins.infra.jitsi.net
'52.36.229.3/32', #new beta
'35.163.97.98/32', #new ci
'54.148.120.38/32', #new pr-torturer
'192.84.19.225/32', #new san jose office IP
'195.110.73.55/32' #new london office IP
]

global hub_whitelist
hub_whitelist = [
'172.16.0.0/12', #internal
'10.0.0.0/8', #internal
'192.168.0.0/16' # internal
]

def add_selenim_grid_output(t, opts):
    t.add_output([
        Output(
            'SeleniumGridELBDNS',
            Description="ELB DNS Name for Selenium Grid",
            Value=Join("",[ Join("-",[Ref("TagGridName"), "grid"]),".",Ref("DomainName")]),
        )
    ])



def add_selenium_grid_cft_parameters(t, opts):
    tag_az1_letter_param = t.add_parameter(Parameter(
        "AZ1Letter",
        Description="Ending letter for initial availability zone in region",
        Type="String",
        Default="a"
    ))
    tag_az2_letter_param = t.add_parameter(Parameter(
        "AZ2Letter",
        Description="Ending letter for second availability zone in region",
        Type="String",
        Default="b"
    ))
    key_name_param = t.add_parameter(Parameter(
        "KeyName",
        Description="Name of an existing EC2 KeyPair to enable SSH access to the ec2 hosts",
        Type="String",
        MinLength=1,
        MaxLength=64,
        AllowedPattern="[-_ a-zA-Z0-9]*",
        ConstraintDescription="can contain only alphanumeric characters, spaces, dashes and underscores."

    ))

    elb_name = t.add_parameter(Parameter(
        "ELBName",
        Description="Name of the ELB",
        Type="String",
        Default="SeleniumGrid-ELB"
    ))

    public_dns_hosted_zone_id_param = t.add_parameter(Parameter(
        "PublicDNSHostedZoneId",
        Description="DNS Zone for public hosted zone Id",
        Type="String",
    ))

    domain_name_param = t.add_parameter(Parameter(
        "DomainName",
        Description="DNS base for CNAME of ELB",
        Type="String",
        Default="infra.jitsi.net"
    ))

    grid_node_initial_param = t.add_parameter(Parameter(
        "GridNodeInitialCount",
        Description="Count of grid nodes when first launching grid",
        Type="String",
        Default="3"
    ))

    grid_node_wait_param = t.add_parameter(Parameter(
        "GridNodeWaitCount",
        Description="Count of grid nodes to wait on when first launching grid",
        Type="String",
        Default="1"
    ))

    grid_node_max_param = t.add_parameter(Parameter(
        "GridNodeMaxCount",
        Description="Count of grid nodes at maxium",
        Type="String",
        Default="100"
    ))

    environment_tag_param = t.add_parameter(Parameter(
        "TagEnvironment",
        Description="Environment tag value",
        Type="String",
        Default="all"
    ))


    tag_grid_iam_role = t.add_parameter(Parameter(
        "GridServerSecurityInstanceProfile",
        Description="IAM Profile for grid nodes",
        Type="String",
        Default="HipChatVideo-SeleniumGrid"
    ))

    grid_image_id_param = t.add_parameter(Parameter(
        "GridImageId",
        Description="Selenium Grid instance AMI id",
        Type="AWS::EC2::Image::Id",
        ConstraintDescription="must be a valid and allowed AMI id."
    ))

    hub_instance_type = t.add_parameter(Parameter(
        "GridHubInstanceType",
        Description="Grid Hub server instance type",
        Type="String",
        Default="t2.micro",
        AllowedValues=[
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
            "c4.large",
            "c4.xlarge",
            "c5.large",
            "c5.xlarge",
            "m5.large",
            "m4.large"
        ],
        ConstraintDescription="must be a valid and allowed EC2 instance type."
    ))

    node_instance_type = t.add_parameter(Parameter(
        "GridNodeInstanceType",
        Description="Grid Node server instance type",
        Type="String",
        Default="t2.micro",
        AllowedValues=[
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
            "c4.large",
            "c4.xlarge",
            "c5.large",
            "c5.xlarge",
            "m4.large",
            "p2.xlarge"],
        ConstraintDescription="must be a valid and allowed EC2 instance type."
    ))

    grid_instance_virt_param = t.add_parameter(Parameter(
        "GridInstanceVirtualization",
        Description="Proxy server instance virtualization",
        Type="String",
        Default="PV",
        AllowedValues=[
            "HVM",
            "PV"
        ],
        ConstraintDescription="Must be a valid and allowed virtualization type."
    ))

    tag_grid_asg_sns = t.add_parameter(Parameter(
        "GridASGAlarmSNS",
        Description="Name of SNS Topic for ASG events",
        ConstraintDescription="Only the name part of the SNS ARN",
        Type="String",
        Default="chaos-ASG-alarms"
    ))

    tag_grid_asg_sns = t.add_parameter(Parameter(
        "GridHealthCheckSNS",
        Description="Name of SNS Topic for Health events",
        ConstraintDescription="Only the name part of the SNS ARN",
        Type="String",
        Default="chaos-Health-Check-List"
    ))

    tag_grid = t.add_parameter(Parameter(
        "TagGridName",
        Description="Name of Selenium Grid",
        ConstraintDescription="Tag used to differentiate clusters",
        Type="String",
        Default="default"
    ))

    tag_git_branch_param = t.add_parameter(Parameter(
        "TagGitBranch",
        Description="Tag: git_branch",
        Type="String",
        Default="master"
    ))


def add_selenium_grid_security(t,opts):

    lb_security_group = t.add_resource(SecurityGroup(
        "GridLBSecurityGroup",
        GroupDescription=Join(' ', ["Selenium Grid ELB ", Ref("RegionAlias"),
                                    Ref("StackNamePrefix"),Ref("TagGridName")]),
        VpcId=opts['vpc_id'],
        Tags=Tags(
            Name=Join("-", [Ref("RegionAlias"), Ref("StackNamePrefix"),Ref("TagGridName"), "ELBGroup"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role="selenium-grid",
            grid=Ref("TagGridName")
        )
    ))

    hub_security_group = t.add_resource(SecurityGroup(
        "GridHubSecurityGroup",
        GroupDescription=Join(' ', ["Selenium Grid Hub", Ref("RegionAlias"),
                                    Ref("StackNamePrefix"),Ref("TagGridName")]),
        VpcId=opts['vpc_id'],
        Tags=Tags(
            Name=Join("-", [Ref("RegionAlias"), Ref("StackNamePrefix"),Ref("TagGridName"), "HubGroup"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role="selenium-grid",
            grid=Ref("TagGridName")
        )
    ))

    node_security_group = t.add_resource(SecurityGroup(
        "GridNodeSecurityGroup",
        GroupDescription=Join(' ', ["Selenium Grid Nodes", Ref("RegionAlias"),
                                    Ref("StackNamePrefix"),Ref("TagGridName")]),
        VpcId=opts['vpc_id'],
        Tags=Tags(
            Name=Join("-", [Ref("RegionAlias"), Ref("StackNamePrefix"),Ref("TagGridName"), "NodeGroup"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role="selenium-grid",
            grid=Ref("TagGridName")
        )
    ))

    i=0
    elb_ingress=[]
    for whitelist_cidr in elb_whitelist:
        elb_ingress.append(t.add_resource(SecurityGroupIngress(
            "ELBIngress%s"%i,
            GroupId=Ref("GridLBSecurityGroup"),
            IpProtocol="tcp",
            FromPort="4444",
            ToPort="4444",
            CidrIp=whitelist_cidr
        )))
        i=i+1

    for whitelist_cidr in elb_whitelist:
        elb_ingress.append(t.add_resource(SecurityGroupIngress(
            "ELBIngress%s"%i,
            GroupId=Ref("GridLBSecurityGroup"),
            IpProtocol="tcp",
            FromPort="3000",
            ToPort="3000",
            CidrIp=whitelist_cidr
        )))
        i=i+1

    node_ingress = t.add_resource(SecurityGroupIngress(
        "NodeIngress",
        GroupId=Ref("GridNodeSecurityGroup"),
        IpProtocol="tcp",
        FromPort="0",
        ToPort="65535",
        SourceSecurityGroupId= Ref("GridHubSecurityGroup"),
        SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
    ))

    grid_node_ssh_ingress = t.add_resource(SecurityGroupIngress(
        "NodeSSHIngress",
        GroupId=Ref("GridNodeSecurityGroup"),
        IpProtocol="tcp",
        FromPort="22",
        ToPort="22",
        SourceSecurityGroupId= opts['ssh_security_group'],
        SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
    ))

    grid_hub_ssh_ingress = t.add_resource(SecurityGroupIngress(
        "HubSSHIngress",
        GroupId=Ref("GridHubSecurityGroup"),
        IpProtocol="tcp",
        FromPort="22",
        ToPort="22",
        SourceSecurityGroupId= opts['ssh_security_group'],
        SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
    ))

    grid_hub_ssh_forward_ingress = t.add_resource(SecurityGroupIngress(
        "HubSSHForwardIngress",
        GroupId=Ref("GridHubSecurityGroup"),
        IpProtocol="tcp",
        FromPort="4444",
        ToPort="4444",
        SourceSecurityGroupId= opts['ssh_security_group'],
        SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
    ))

    grid_hub_ssh_forward_ingress2 = t.add_resource(SecurityGroupIngress(
        "HubSSHForwardIngress2",
        GroupId=Ref("GridHubSecurityGroup"),
        IpProtocol="tcp",
        FromPort="3000",
        ToPort="3000",
        SourceSecurityGroupId= opts['ssh_security_group'],
        SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
    ))

    i=0
    hub_ingress=[]
    for whitelist_cidr in hub_whitelist:
        hub_ingress.append(t.add_resource(SecurityGroupIngress(
            "HubIngress%s"%i,
            GroupId=Ref("GridHubSecurityGroup"),
            IpProtocol="tcp",
            FromPort="4444",
            ToPort="4444",
            CidrIp=whitelist_cidr
        )))
        i=i+1

    for whitelist_cidr in hub_whitelist:
        hub_ingress.append(t.add_resource(SecurityGroupIngress(
            "HubIngress%s"%i,
            GroupId=Ref("GridHubSecurityGroup"),
            IpProtocol="tcp",
            FromPort="3000",
            ToPort="3000",
            CidrIp=whitelist_cidr
        )))
        i=i+1


    hub_ingress_elb = t.add_resource(SecurityGroupIngress(
        "HubELBIngress",
        GroupId=Ref("GridHubSecurityGroup"),
        IpProtocol="tcp",
        FromPort="4444",
        ToPort="4444",
        SourceSecurityGroupId=Ref("GridLBSecurityGroup"),
        SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
    ))

    hub_ingress_elb = t.add_resource(SecurityGroupIngress(
        "HubELBIngress2",
        GroupId=Ref("GridHubSecurityGroup"),
        IpProtocol="tcp",
        FromPort="3000",
        ToPort="3000",
        SourceSecurityGroupId=Ref("GridLBSecurityGroup"),
        SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
    ))

    hub_ingress_elb = t.add_resource(SecurityGroupIngress(
        "HubNodeIngress",
        GroupId=Ref("GridHubSecurityGroup"),
        IpProtocol="tcp",
        FromPort="4444",
        ToPort="4444",
        SourceSecurityGroupId=Ref("GridNodeSecurityGroup"),
        SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
    ))

    hub_ingress_elb = t.add_resource(SecurityGroupIngress(
        "HubNodeIngress2",
        GroupId=Ref("GridHubSecurityGroup"),
        IpProtocol="tcp",
        FromPort="3000",
        ToPort="3000",
        SourceSecurityGroupId=Ref("GridNodeSecurityGroup"),
        SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
    ))

    egress_elb = t.add_resource(SecurityGroupEgress(
        "EgressELB",
        GroupId=Ref("GridLBSecurityGroup"),
        IpProtocol="-1",
        CidrIp='0.0.0.0/0',
        FromPort='-1',
        ToPort='-1'
    ))

    egress_node = t.add_resource(SecurityGroupEgress(
        "EgressNode",
        GroupId=Ref("GridNodeSecurityGroup"),
        IpProtocol="-1",
        CidrIp='0.0.0.0/0',
        FromPort='-1',
        ToPort='-1'
    ))


    egress_hub = t.add_resource(SecurityGroupEgress(
        "EgressHub",
        GroupId=Ref("GridHubSecurityGroup"),
        IpProtocol="-1",
        CidrIp='0.0.0.0/0',
        FromPort='-1',
        ToPort='-1'
    ))


def add_selenium_grid_cft_resources(t,opts):

    grid_elb = t.add_resource(LoadBalancer(
        'GridELB',
        CrossZone= "true",
        LoadBalancerName= Ref("ELBName"),
        ConnectionSettings= ConnectionSettings(
            IdleTimeout= 90,
        ),
        ConnectionDrainingPolicy= ConnectionDrainingPolicy(
            Enabled = True,
            Timeout = 90
        ),
        Listeners = [
            Listener(
                InstancePort= "4444",
                InstanceProtocol= "HTTP",
                LoadBalancerPort= "4444",
                Protocol= "HTTP"
            ),
            Listener(
                InstancePort="3000",
                InstanceProtocol="HTTP",
                LoadBalancerPort="3000",
                Protocol="HTTP"
            )
        ],
        HealthCheck=HealthCheck(
            HealthyThreshold= 10,
            Interval= "30",
            Target= 'TCP:4444',
            Timeout= "5",
            UnhealthyThreshold="2"
        ),
        Scheme= "internet-facing",
        SecurityGroups= [ Ref("GridLBSecurityGroup"),],
        Subnets= [opts['public_subnetA'], opts['public_subnetB']],
        Tags = Tags(
                Name = Join("-", [Ref("RegionAlias"),Ref("StackNamePrefix"), "grid" ]),
                Environment=Ref("TagEnvironmentType"),
                Service=Ref("TagService"),
                Owner=Ref("TagOwner"),
                Team=Ref("TagTeam"),
                Product=Ref("TagProduct"),
                shard_role= "selenium-grid",
        )


    ))

    grid_elb_hub_health_check = t.add_resource(Alarm(
        'GridELBHubHealthCheck',
        DependsOn=["GridELB","HubWaitCondition"],
        ComparisonOperator="GreaterThanOrEqualToThreshold",
        AlarmName=Join("-",[Ref("ELBName"), "High-Unhealthy-Hosts"]),
        EvaluationPeriods=1,
        MetricName="UnHealthyHostCount",
        Namespace="AWS/ELB",
        Period=60,
        TreatMissingData="breaching",
        Statistic="Average",
        Unit="Count",
        Threshold="1",
        AlarmActions=[
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("GridHealthCheckSNS")])
        ],
        OKActions=[
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("GridHealthCheckSNS")])
        ],
        Dimensions=[MetricDimension(
            Name="LoadBalancerName",
            Value=Ref("GridELB")
        )]
    ))

    hubWaitHandle= t.add_resource(cloudformation.WaitConditionHandle(
        'HubWaitHandle',
    ))
    nodeWaitHandle= t.add_resource(cloudformation.WaitConditionHandle(
        'NodeWaitHandle',
    ))

    hub_launch_group = t.add_resource(LaunchConfiguration(
        'GridHubLaunchGroup',
        ImageId= Ref("GridImageId"),
        InstanceType= Ref("GridHubInstanceType"),
        IamInstanceProfile= Ref("GridServerSecurityInstanceProfile"),
        KeyName= Ref("KeyName"),
        SecurityGroups= [Ref("GridHubSecurityGroup")],
        BlockDeviceMappings= [BlockDeviceMapping(
            DeviceName= "/dev/sda1",
            Ebs=EBSBlockDevice(
                VolumeSize= 20
            )
        )],
        UserData= Base64(Join('',[
            "#!/bin/bash -v\n",
            "EXIT_CODE=0\n",
            "set -e\n",
            "set -x\n",

            "export AWS_DEFAULT_REGION=", {"Ref": "AWS::Region"}, "\n",
            "export AWS_BIN=\"/usr/local/bin/aws\"\n",
            "export EC2_METADATA_BIN=\"/usr/bin/ec2metadata\"\n",

            "export EC2_INSTANCE_ID=$($EC2_METADATA_BIN --instance-id)\n",

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

            "/usr/local/bin/configure-selenium-grid.sh >> /var/log/bootstrap.log 2>&1 || EXIT_CODE=1\n",

            "# Send signal about finishing configuring server\n",
            "/usr/local/bin/cfn-signal -e $EXIT_CODE -r 'Server configuration' '", Ref("HubWaitHandle"), "'\n"
            "[ $EXIT_CODE == 0 ] || $AWS_BIN autoscaling set-instance-health --instance-id $EC2_INSTANCE_ID --health-status Unhealthy\n"
        ]))
    ))
    if opts['selenium_dedicated']:
        nodeTenancy='dedicated'
    else:
        nodeTenancy='default'

    node_launch_group = t.add_resource(LaunchConfiguration(
        'GridNodeLaunchGroup',
        ImageId= Ref("GridImageId"),
        InstanceType= Ref("GridNodeInstanceType"),
        IamInstanceProfile= Ref("GridServerSecurityInstanceProfile"),
        KeyName= Ref("KeyName"),
        PlacementTenancy= nodeTenancy,
        SecurityGroups= [Ref("GridNodeSecurityGroup")],
        BlockDeviceMappings= [BlockDeviceMapping(
            DeviceName= "/dev/sda1",
            Ebs=EBSBlockDevice(
                VolumeSize= 20
            )
        )],
        UserData= Base64(Join('',[
            "#!/bin/bash -v\n",
            "EXIT_CODE=0\n",
            "set -e\n",
            "set -x\n",

            "export AWS_DEFAULT_REGION=", {"Ref": "AWS::Region"}, "\n",
            "export AWS_BIN=\"/usr/local/bin/aws\"\n",
            "export EC2_METADATA_BIN=\"/usr/bin/ec2metadata\"\n",

            "export EC2_INSTANCE_ID=$($EC2_METADATA_BIN --instance-id)\n",

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

            "/usr/local/bin/configure-selenium-grid.sh >> /var/log/bootstrap.log 2>&1 || EXIT_CODE=1\n",

            "# Send signal about finishing configuring server\n",
            "/usr/local/bin/cfn-signal -e $EXIT_CODE -r 'Server configuration' '", Ref("NodeWaitHandle"), "'\n"
            "# Mark instance as unhealth if the configuration failed\n",
            "[ $EXIT_CODE == 0 ] || $AWS_BIN autoscaling set-instance-health --instance-id $EC2_INSTANCE_ID --health-status Unhealthy\n"
        ]))
    ))


    hubWaitCondition= t.add_resource(cloudformation.WaitCondition(
        'HubWaitCondition',
        DependsOn= "GridHubAutoScaleGroup",
        Handle= Ref("HubWaitHandle"),
        Timeout= 3600,
        Count= 1
    ))

    nodeWaitCondition= t.add_resource(cloudformation.WaitCondition(
        'NodeWaitCondition',
        DependsOn= "GridNodeAutoScaleGroup",
        Handle= Ref("NodeWaitHandle"),
        Timeout= 3600,
        Count= Ref("GridNodeWaitCount")
    ))

    hub_autoscale_group= t.add_resource(AutoScalingGroup(
        'GridHubAutoScaleGroup',
        AvailabilityZones=[Join("",[Ref("AWS::Region"),Ref("AZ1Letter")]),Join("",[Ref("AWS::Region"),Ref("AZ2Letter")])],
        Cooldown=300,
        DesiredCapacity=1,
        HealthCheckGracePeriod=300,
        HealthCheckType="EC2",
        MaxSize=1,
        MinSize=1,
        LoadBalancerNames=[Ref("GridELB")],
        VPCZoneIdentifier= [opts['nat_subnetA'], opts['nat_subnetB']],
        NotificationConfigurations= [NotificationConfigurations(
            TopicARN= Join(":",["arn:aws:sns", Ref("AWS::Region"),Ref("AWS::AccountId"),Ref("GridASGAlarmSNS")]),
            NotificationTypes= ["autoscaling:EC2_INSTANCE_LAUNCH", "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",  "autoscaling:EC2_INSTANCE_TERMINATE", "autoscaling:EC2_INSTANCE_TERMINATE_ERROR"]
        )],
        LaunchConfigurationName= Ref("GridHubLaunchGroup"),
        Tags=[
            Tag("Name",Join("-", [Ref("RegionAlias"), Ref("StackNamePrefix"), Ref("TagGridName"), "hub"]), False),
            Tag("Environment",Ref("TagEnvironmentType"),True),
            Tag("Service",Ref("TagService"),True),
            Tag("Owner",Ref("TagOwner"),True),
            Tag("Team",Ref("TagTeam"),True),
            Tag("Product",Ref("TagProduct"),True),
            Tag("environment", Ref("TagEnvironment"), True),
            Tag("shard-role","selenium-grid", True),
            Tag("grid-role","hub", True),
            Tag("grid", Ref("TagGridName"), True ),
            Tag("git_branch", Ref("TagGitBranch"), True )
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
        TerminationPolicies=["Default"]

    ))

    node_autoscale_group= t.add_resource(AutoScalingGroup(
        'GridNodeAutoScaleGroup',
        DependsOn= "HubWaitCondition",
        AvailabilityZones=[Join("",[Ref("AWS::Region"),Ref("AZ1Letter")]),Join("",[Ref("AWS::Region"),Ref("AZ2Letter")])],
        Cooldown=300,
        DesiredCapacity=Ref("GridNodeInitialCount"),
        HealthCheckGracePeriod=300,
        HealthCheckType="EC2",
        MaxSize=Ref("GridNodeMaxCount"),
        MinSize=Ref("GridNodeInitialCount"),
        VPCZoneIdentifier= [opts['nat_subnetA'], opts['nat_subnetB']],
        NotificationConfigurations= [NotificationConfigurations(
            TopicARN= Join(":",["arn:aws:sns", Ref("AWS::Region"),Ref("AWS::AccountId"),Ref("GridASGAlarmSNS")]),
            NotificationTypes= ["autoscaling:EC2_INSTANCE_LAUNCH", "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",  "autoscaling:EC2_INSTANCE_TERMINATE", "autoscaling:EC2_INSTANCE_TERMINATE_ERROR"]
        )],
        LaunchConfigurationName= Ref("GridNodeLaunchGroup"),
        Tags=[
            Tag("Name",Join("-", [Ref("RegionAlias"), Ref("StackNamePrefix"), Ref("TagGridName"), "nodes"]), False),
            Tag("Environment",Ref("TagEnvironmentType"),True),
            Tag("Service",Ref("TagService"),True),
            Tag("Owner",Ref("TagOwner"),True),
            Tag("Team",Ref("TagTeam"),True),
            Tag("Product",Ref("TagProduct"),True),
            Tag("environment", Ref("TagEnvironment"), True),
            Tag("shard-role","selenium-grid", True),
            Tag("grid-role","node", True),
            Tag("grid", Ref("TagGridName"), True ),
            Tag("git_branch", Ref("TagGitBranch"), True )
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
        TerminationPolicies=["Default"]

    ))

    elb_dns_record = t.add_resource(RecordSetType(
        "ELBDNSRecord",
        DependsOn= ["GridELB"],
        HostedZoneId= Ref("PublicDNSHostedZoneId"),
        Comment= "The Grid ELB DNS server host name",
        Name= Join("",[ Join("-",[Ref("TagGridName"), "grid"]),".",Ref("DomainName"),"."]),
        Type= "CNAME",
        TTL= 300,
        ResourceRecords= [GetAtt("GridELB", "DNSName")]
    ))


#this generates a CFT which builds two large NAT subnets behind a NAT gateway for use with services that do not require public IP addresses
def create_selenium_grid_template(filepath,opts):
    t  = create_template()
    add_default_tag_parameters(t)
    add_stack_name_region_alias_parameters(t)
    add_selenium_grid_cft_parameters(t,opts)
    add_selenium_grid_security(t,opts)
    add_selenium_grid_cft_resources(t,opts)

    add_selenim_grid_output(t,opts)
    write_template_json(filepath,t)



def main():
    parser = argparse.ArgumentParser(description='Create Haproxy stack template')
    parser.add_argument('--region', action='store',
                        help='AWS region)', default=False, required=True)
    parser.add_argument('--regionalias', action='store',
                        help='AWS region alias)', default=False)
    parser.add_argument('--stackprefix', action='store',
                        help='Stack prefix name', default=False, required=False)
    parser.add_argument('--filepath', action='store',
                        help='Path to tenmplate file', default=False, required=False)
    parser.add_argument('--pull_network_stack', action='store',
                        help='Pull network variables from a network stack', default='true', required=True)
    parser.add_argument('--dedicated', action='store',
                        help='Create nodes as dedicated instances', default='false', required=False)

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

        if args.pull_network_stack.lower() == "true":
            opts=pull_network_stack_vars(region=args.region, regionalias=regionalias, stackprefix=args.stackprefix)
            opts=fill_in_bash_network_vars(opts)
        else:
            opts=pull_bash_network_vars()

        if args.dedicated.lower() == "true":
            opts['selenium_dedicated'] = True
        else:
            opts['selenium_dedicated'] = False

        create_selenium_grid_template(filepath=args.filepath,opts=opts)

if __name__ == '__main__':
    main()
