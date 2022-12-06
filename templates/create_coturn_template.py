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

def create_custom_resource(t, route53_resource_names, route53_reference_name_pool, enable_ipv6=False):  
    
    add_custom_resource= t.add_resource(CustomResource(
        "LambdaCustomDelayFunction",
        DependsOn=route53_resource_names,
        ServiceToken= Join("", ["arn:aws:lambda:", Ref("AWS::Region"), ":",
                           Ref("AWS::AccountId"),
                           ":function:",Ref("CoturnLambdaFunctionName")]),
        AlarmHealthSNS=[Ref('CoturnHealthAlarmSNS')],
        NoDataHealthSNS=[Ref('CoturnHealthAlarmSNS')],
        OkHealthSNS=[Ref('CoturnHealthAlarmSNS')],
        HealthChecksID=route53_reference_name_pool,
        StackRegion=Ref("RegionAlias"),
        AccountId=Ref("AWS::AccountId"),
        StackRole="coturn",
        Environment=Ref("TagEnvironment"),
        Shard=Ref("TagEnvironment")
    ))

    if enable_ipv6:
        add_custom_resource= t.add_resource(CustomResource(
            "CleanRoute53Ipv6DDNS",
            ServiceToken= Join("", ["arn:aws:lambda:", Ref("AWS::Region"), ":",
                            Ref("AWS::AccountId"),
                            ":function:",Ref("CoturnIPv6DDNSLambdaName")]),
            StackRegion=Ref("RegionAlias"),
            TURNDnsName=Ref('TURNDnsName'),
            DnsZoneId=Ref('DnsZoneID')
        ))

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

    dns_zone_id = t.add_parameter(Parameter(
        "DnsZoneID",
        Description="DnsZoneID",
        Type="String",
    ))

    dns_zone_domain_name = t.add_parameter(Parameter(
        "DnsZoneDomainName",
        Description="DnsZoneDomainName",
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

    coturn_image_id_param = t.add_parameter(Parameter(
        "CoturnImageId",
        Description="Coturn instance AMI id",
        Type="AWS::EC2::Image::Id",
        ConstraintDescription="must be a valid and allowed AMI id."
    ))

    coturn_instance_type = t.add_parameter(Parameter(
        "CoturnInstanceType",
        Description="Coturn server instance type",
        Type="String",
        Default="t3.large",
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
            "m4.large",
            "m5.large",
            "c4.xlarge",
            "c5.xlarge"
        ],
        ConstraintDescription="must be a valid and allowed EC2 instance type."
    ))

    coturn_instance_virt_param = t.add_parameter(Parameter(
        "CoturnInstanceVirtualization",
        Description="Coturn server instance virtualization",
        Type="String",
        Default="PV",
        AllowedValues=[
            "HVM",
            "PV"
        ],
        ConstraintDescription="Must be a valid and allowed virtualization type."
    ))

    coturn_desired_capacity_param = t.add_parameter(Parameter(
        "CoturnDesiredCapacity",
        Description="Coturn ASG desired capacity",
        Type="Number",
        Default=2
    ))

    coturn_az_param = t.add_parameter(Parameter(
        "CoturnAvailabilityZones",
        Description="AZ for JVB ASG",
        Type="List<AWS::EC2::AvailabilityZone::Name>",
        Default="us-east-1a,us-east-1b",
        ConstraintDescription="must be a valid and allowed availability zone."
    ))

    coturn_health_alarm_sns_param = t.add_parameter(Parameter(
        "CoturnHealthAlarmSNS",
        Description="SNS topic for ASG Alarms related to Coturn",
        Type="String",
        Default="Coturn-Health-Check-List"
    ))

    coturn_asg_alarm_sns_param = t.add_parameter(Parameter(
        "CoturnASGAlarmSNS",
        Description="SNS topic for ASG Alarms related to Coturn",
        Type="String",
        Default="Coturn-ASG-alarms"
    ))

    coturn_server_security_instance_profile_param = t.add_parameter(Parameter(
        "CoturnServerSecurityInstanceProfile",
        Description="Coturn Security Instance Profile",
        Type="String",
        Default="HipChatVideo-Coturn"
    ))

    coturn_lambda_function_name = t.add_parameter(Parameter(
        'CoturnLambdaFunctionName',
        Description= "Lambda function name that CF custom resources use when create a stack",
        Type= "String",
        Default= "all-cf-update-route53",
    ))

    coturn_ipv6_ddns_lambda_name = t.add_parameter(Parameter(
        'CoturnIPv6DDNSLambdaName',
        Description= "Lambda function name that CF custom resources use when create a stack",
        Type= "String",
        Default= "all-cf-asg-coturn-ipv6-ddns",
    ))

    network_security_group_param = t.add_parameter(Parameter(
        "NetworkSecurityGroup",
        Description="Core Security Group",
        Type="String",
        Default="sg-a075cac6"
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
        Default="master"
    ))

    tag_cloud_name_param = t.add_parameter(Parameter(
        "TagCloudName",
        Description="Tag: cloud_name",
        Type="String"
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

def add_route53_records(t, eip_names, enable_ipv6=False):
    
    # resource_records = [rs for rs in resource_records if rs!=','] 

    route53_resource_names = []
    route53_reference_names = {}
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

    if enable_ipv6:
        add_route53_latency_alias = t.add_resource(route53.RecordSetType(
            'TURNRoute53LatencyAliasIpv61',
            DependsOn='CoturnAutoScaleGroup',
            AliasTarget=route53.AliasTarget(
                HostedZoneId=Ref('DnsZoneID'),
                DNSName=Ref('TURNDnsName'),
                EvaluateTargetHealth=True
            ),
            HostedZoneId=Ref('DnsZoneID'),
            Region=Ref("AWS::Region"),
            Comment='DNS record for TURN server',
            Name=Ref('TURNDnsAliasName'),
            Type="AAAA",
            SetIdentifier=Join(" ", [ 'coturn',Ref("AWS::Region"),'ipv6' ]),
        ))

    tmp_number=1
    for ip in eip_names:

        route53_resource_name = 'Route53TURNHealthCheck'+str(tmp_number)
        route53_record_name = 'TURNRoute53Record'+str(tmp_number)

        add_route53_record = t.add_resource(route53.RecordSetType(
            route53_record_name,
            DependsOn=eip_names,
            HostedZoneId=Ref('DnsZoneID'),
            Comment='DNS record for TURN server',  
            Name=Ref('TURNDnsName'),
            Type="A",
            TTL="60",
            Weight="10",
            SetIdentifier=Join(" ", [ 'coturn',Ref("AWS::Region"),route53_record_name ]),
            ResourceRecords=[Ref(ip)],
            HealthCheckId=Ref(route53_resource_name)
        ))

        route53_turn_health_check = t.add_resource(route53.HealthCheck(
            route53_resource_name,
            DependsOn= "CoturnAutoScaleGroup",
            HealthCheckConfig= route53.HealthCheckConfiguration(
                IPAddress=Ref(ip),
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

    create_custom_resource(t,route53_resource_names, route53_reference_name_pool, enable_ipv6)

def add_security(opts):

    coturn_security_group = t.add_resource(SecurityGroup(
        "CoturnSecurityGroup",
        GroupDescription=Join(' ', ["Coturn nodes", Ref("TagEnvironment"), Ref("RegionAlias"),
                                    Ref("StackNamePrefix")]),
        VpcId=opts['vpc_id'],
        Tags=Tags(
            Name=Join("-", [Ref("TagEnvironment"), Ref("RegionAlias"), Ref("StackNamePrefix"), "CoturnGroup"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role="coturn",
        )
    ))

    ingress12 = t.add_resource(SecurityGroupIngress(
        "ingress12",
        GroupId=Ref("CoturnSecurityGroup"),
        IpProtocol="tcp",
        FromPort="443",
        ToPort="443",
        CidrIp="0.0.0.0/0"
    ))

    ingress13 = t.add_resource(SecurityGroupIngress(
        "ingress13",
        GroupId=Ref("CoturnSecurityGroup"),
        IpProtocol="udp",
        FromPort="443",
        ToPort="443",
        CidrIp="0.0.0.0/0"
    ))

    ingress14 = t.add_resource(SecurityGroupIngress(
        "ingress14",
        GroupId=Ref("CoturnSecurityGroup"),
        IpProtocol="tcp",
        FromPort="443",
        ToPort="443",
        CidrIpv6="::/0"
    ))

    ingress15 = t.add_resource(SecurityGroupIngress(
        "ingress15",
        GroupId=Ref("CoturnSecurityGroup"),
        IpProtocol="udp",
        FromPort="443",
        ToPort="443",
        CidrIpv6="::/0"
    ))
 

    ingress16 = t.add_resource(SecurityGroupIngress(
        "ingress16",
        GroupId=Ref("CoturnSecurityGroup"),
        IpProtocol="tcp",
        FromPort="22",
        ToPort="22",
        SourceSecurityGroupId= opts['ssh_security_group'],
        SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
    ))

    egress1 = t.add_resource(SecurityGroupEgress(
        "egress1",
        GroupId=Ref("CoturnSecurityGroup"),
        IpProtocol="-1",
        CidrIp='0.0.0.0/0',
        FromPort='-1',
        ToPort='-1'
    ))

def add_cloudwatch_event(t):

    add_cloudwatch_event = t.add_resource(cloudwatch_events.Rule(
        "CoturnCloudwatchEvent",
        Description="Rule for the Coturn ASG that triggers Route53 lambda function.",
        Name=Join("-", [Ref("TagEnvironment"), Ref("RegionAlias"), Ref("StackNamePrefix"), "coturn-asg-event"]),
        EventPattern={
            "source": ["aws.autoscaling"],
            "detail-type": [
                "EC2 Instance-terminate Lifecycle Action"
            ],
            "detail": {
                "AutoScalingGroupName": [Ref('CoturnAutoScaleGroup')]
            }
        },
        Targets=[cloudwatch_events.Target(
            Arn=Join("", ["arn:aws:lambda:", Ref("AWS::Region"), ":",
                          Ref("AWS::AccountId"),
                          ":function:",Ref('CoturnIPv6DDNSLambdaName')]),
            Id=Join('-',[Select('2', Split('-', Ref('CoturnAutoScaleGroup'))), 'ipv6', 'ddns'])
        )]
    ))

    t.add_resource(awslambda.Permission(
        "CoturnRetrierEventTriggerPermission",
        Action="lambda:InvokeFunction",
        FunctionName=Join("", ["arn:aws:lambda:", Ref("AWS::Region"), ":",
                          Ref("AWS::AccountId"),
                          ":function:",Ref('CoturnIPv6DDNSLambdaName')]),
        Principal="events.amazonaws.com",
        SourceArn=GetAtt("CoturnCloudwatchEvent", "Arn")
    ))

def create_coturn_template(filepath, opts, eip_number=2, enable_ipv6=False):

    global t

    t = Template()

    t.add_version("2010-09-09")

    t.add_description(
        "Template for the provisioning TURN resources for the HC Video"
    )

    # Add params
    add_parameters()

    eip_address_pool = []
    eip_names = []

    for eip in range(1,eip_number+1): 
        resource_name = 'CoturnEIP'+str(eip)

        cotrun_eip = t.add_resource(EIP(
            resource_name
        ))
        
        reference_name = {"Ref":resource_name}


        eip_address_pool.append(reference_name)
        eip_address_pool.append(',')
        eip_names.append(resource_name)
    del eip_address_pool[-1]

    add_route53_records(t,eip_names, enable_ipv6)
    
    if enable_ipv6:
        add_cloudwatch_event(t)

    #add security
    add_security(opts=opts)

    coturn_launch_group = t.add_resource(LaunchConfiguration(
        'CoturnLaunchGroup',
        ImageId= Ref("CoturnImageId"),
        InstanceType= Ref("CoturnInstanceType"),
        IamInstanceProfile= Ref("CoturnServerSecurityInstanceProfile"),
        KeyName= Ref("KeyName"),
        SecurityGroups= [Ref("CoturnSecurityGroup")],
        AssociatePublicIpAddress= True,
        InstanceMonitoring= False,
        BlockDeviceMappings= [BlockDeviceMapping(
            DeviceName= "/dev/sda1",
            Ebs=EBSBlockDevice(
                VolumeSize= 8
            )
        )],
        UserData= Base64(Join('',[
            "#!/bin/bash -v\n",
            "set -e\n",
            "set -x\n",
            "EXIT_CODE=0\n",
            "status_code=0\n",
            "tmp_msg_file='/tmp/cfn_signal_message'\n",

            "function get_metadata(){\n",
            "export AWS_DEFAULT_REGION=", {"Ref": "AWS::Region"}, "\n",
            "export CLOUD_NAME=\"", {"Ref": "TagCloudName"}, "\"\n",
            "instance_id=$(curl http://169.254.169.254/latest/meta-data/instance-id)\n",
            "}\n",
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
            "easy_install /root/aws-cfn-bootstrap-latest/ && \\\n",
            "pip install aws-ec2-assign-elastic-ip || status_code=1\n",
            "echo \"[Boto]\" > /etc/boto.cfg && echo \"use_endpoint_heuristics = True\" >> /etc/boto.cfg\n",
            "if [ $status_code -eq 1 ]; then echo 'Install apps stage failed' > $tmp_msg_file; exit $status_code;fi\n"
            "}\n",

            "function check_emi(){\n",
            "set +e\n",
            "counter=1\n",
            "eip_status=1\n",
            "while [ $counter -le 20 ]; do\n",
            "aws-ec2-assign-elastic-ip --region ", {"Ref": "AWS::Region"}, " --valid-ips "]+ eip_address_pool + [" |  grep --line-buffered -s 'is already assigned an Elastic IP'|grep -q \"$instance_id\"\n",
            "if [ $? -eq 0 ];then eip_status=0;break\n",
            "else\n",
            "sleep 30\n",
            "((counter++))\n",
            "fi; done\n",
            "if [ $eip_status -eq 1 ];then echo 'EIP still not avaible' > $tmp_msg_file;exit $eip_status\n",
            "else return $eip_status; fi\n"
            "}\n",

            "function provisioning(){\n",
            "status_code=0 && \\\n",
            "/usr/local/bin/postinstall-coturn.sh || status_code=1\n",
            "if [ $status_code -eq 1 ]; then echo 'Provisioning stage failed' > $tmp_msg_file; /usr/local/bin/dump-boot.sh > /var/log/dump_boot.log 2>&1; exit $status_code;fi;\n"
            "}\n",

            "( get_metadata && install_apps && check_emi && provisioning ) ||  EXIT_CODE=1\n"
            
            "if [ ! -f /tmp/cfn_signal_message ]; then err_message='Server configuration';else err_message=$(cat $tmp_msg_file);fi\n",

            "# Send signal about finishing configuring server\n",
            "/usr/local/bin/cfn-signal -e $EXIT_CODE -r \"$err_message\" --resource CoturnAutoScaleGroup --stack '", {"Ref": "AWS::StackName"}, "' --region ", { "Ref" : "AWS::Region" }, "|| true\n",

            "if [ $EXIT_CODE -eq 1 ]; then shutdown -h now;fi\n"
        ]))
    ))

    coturn_autoscale_group= t.add_resource(AutoScalingGroup(
        'CoturnAutoScaleGroup',
        DependsOn=eip_names,
        AvailabilityZones=Ref("CoturnAvailabilityZones"),
        Cooldown=300,
        DesiredCapacity=Ref('CoturnDesiredCapacity'),
        HealthCheckGracePeriod=300,
        HealthCheckType="EC2",
        MaxSize=eip_number + 1,
        MinSize=1,
        VPCZoneIdentifier= [opts['public_subnetA'], opts['public_subnetB']],
        NotificationConfigurations= [NotificationConfigurations(
            TopicARN= Join(":",["arn:aws:sns", Ref("AWS::Region"),Ref("AWS::AccountId"),Ref("CoturnASGAlarmSNS")]),
            NotificationTypes= ["autoscaling:EC2_INSTANCE_LAUNCH", "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",  "autoscaling:EC2_INSTANCE_TERMINATE", "autoscaling:EC2_INSTANCE_TERMINATE_ERROR"]
        )],
        LaunchConfigurationName= Ref("CoturnLaunchGroup"),
        Tags=[
            Tag("Name",Join("-", [Ref("TagEnvironment"), Ref("RegionAlias"), Ref("StackNamePrefix"), "coturn"]), False),
            Tag("Environment",Ref("TagEnvironmentType"),True),
            Tag("Service",Ref("TagService"),True),
            Tag("Owner",Ref("TagOwner"),True),
            Tag("Team",Ref("TagTeam"),True),
            Tag("Product",Ref("TagProduct"),True),
            Tag("environment",Ref("TagEnvironment"), True),
            Tag("domain",Ref("TagDomainName"), True),
            Tag("shard-role","coturn", True),
            Tag("git_branch", Ref("TagGitBranch"), True ),
            Tag("cloud_name", Ref("TagCloudName"), True ),
            Tag("datadog", Ref("DatadogEnabled"), True)
        ],
        MetricsCollection= [MetricsCollection(
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
                        Count=Ref("CoturnDesiredCapacity"),
                        Timeout='PT30M'))
    ))

    coturn_asg_lifecycle_hook = t.add_resource(LifecycleHook (
        'CoturnTerminationLifecyleHook',
        AutoScalingGroupName=Ref('CoturnAutoScaleGroup'),
        DefaultResult='CONTINUE',
        HeartbeatTimeout='30',
        LifecycleHookName='CoturnTerminationForLambda',
        LifecycleTransition='autoscaling:EC2_INSTANCE_TERMINATING'
    ))

    provisioning_coturn_check_terminating = t.add_resource(Alarm(
        'ProvisioningCoturnCheckTerminating',
        ComparisonOperator="GreaterThanOrEqualToThreshold",
        EvaluationPeriods=1,
        MetricName="GroupTerminatingInstances",
        Namespace="AWS/AutoScaling",
        Period=300,
        TreatMissingData="ignore",
        Statistic="Sum",
        Threshold="2",
        AlarmActions=[
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("CoturnHealthAlarmSNS")])
        ],
        OKActions=[
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("CoturnHealthAlarmSNS")])
        ],
        Dimensions=[MetricDimension(
            Name="AutoScalingGroupName",
            Value=Ref("CoturnAutoScaleGroup")
        )]
    ))

    provisioning_coturn_check_pending = t.add_resource(Alarm(
        'ProvisioningCoturnCheckPending',
        ComparisonOperator="GreaterThanOrEqualToThreshold",
        EvaluationPeriods=1,
        MetricName="GroupPendingInstances",
        Namespace="AWS/AutoScaling",
        Period=300,
        TreatMissingData="ignore",
        Statistic="Sum",
        Threshold="2",
        AlarmActions=[
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("CoturnHealthAlarmSNS")])
        ],
        OKActions=[
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("CoturnHealthAlarmSNS")])
        ],
        Dimensions=[MetricDimension(
            Name="AutoScalingGroupName",
            Value=Ref("CoturnAutoScaleGroup")
        )]
    ))

    for eip_name in eip_names:
        t.add_output([
                Output(
                    eip_name,
                    Description=eip_name,
                    Value=Ref(eip_name),
                )
        ])

    write_template_json(filepath=filepath, t=t)


def main():
    parser = argparse.ArgumentParser(description='Create Coturn stack template')
    parser.add_argument('--region', action='store',
                        help='AWS region)', default=False, required=True)
    parser.add_argument('--regionalias', action='store',
                        help='AWS region)', default=False)
    parser.add_argument('--stackprefix', action='store',
                        help='Stack prefix name', default=False, required=False)
    parser.add_argument('--filepath', action='store',
                        help='Path to tenmplate file', default=False, required=False),
    parser.add_argument('--eip_number',action='store', default=2, type=int, required=False),
    parser.add_argument('--pull_network_stack', action='store',
                        help='Pull network variables from a network stack', default='true', required=True)
    parser.add_argument('--enable_ipv6', action='store', type=distutils.util.strtobool, help='Enable IPv6',
                        default=False)
    args = parser.parse_args()

    if not args.region:
        print('No AWS region specified, exiting...')
        exit(1)
    elif not args.filepath:
        print ('No path to template file')
        exit(2)
    else:
        if args.pull_network_stack.lower() == "true":
            opts = pull_network_stack_vars(region=args.region, stackprefix=args.stackprefix, regionalias=args.regionalias)
        else:
            opts = pull_bash_network_vars()
        create_coturn_template(filepath=args.filepath, opts=opts, eip_number=args.eip_number, enable_ipv6=args.enable_ipv6)


if __name__ == '__main__':
    main()
