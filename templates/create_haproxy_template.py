#!/usr/bin/env python

# pip install troposphere boto3

import distutils.util
import boto3, re, argparse, json, os, sys
import troposphere.elasticloadbalancingv2 as elasticloadbalancingv2

hcvlib_path=os.path.dirname(os.path.realpath(__file__))+"/../bin"
sys.path.insert(0, hcvlib_path)

import hcvlib

from botocore.exceptions import ClientError
from pprint import pprint
from troposphere import Parameter, Ref, Template, Join, Tags, Base64, Output, Export, GetAtt,cloudformation
from troposphere.ec2 import EIP,SecurityGroup, SecurityGroupIngress
from troposphere.elasticloadbalancing import *
from troposphere.autoscaling import Tag, AutoScalingGroup, LaunchConfiguration, BlockDeviceMapping, EBSBlockDevice, NotificationConfigurations, MetricsCollection
from troposphere.cloudwatch import Alarm, MetricDimension
from troposphere.cloudformation import CustomResource
from troposphere.policies import (
    CreationPolicy, ResourceSignal
)

def create_custom_resource(t, regions, create_eip=True):
    kwargs = {
        'DependsOn': ['ProxyAutoScaleGroup','LBSecurityGroup'],
        'ServiceToken': Join("", ["arn:aws:lambda:", Ref("AWS::Region"), ":", Ref("AWS::AccountId"), ":function:", Ref("ProxyLambdaFunctionName")]),
        'StackRegion': Ref("AWS::Region"),
        'AccountId': Ref("AWS::AccountId"),
        'StackRole': 'haproxy',
        'Role': 'haproxy',
        'Environment': Ref("TagEnvironment"),
        'SG': GetAtt("LBSecurityGroup", "GroupId"),
        'Regions': regions,
    }

    if create_eip:
        kwargs['IpAddresses'] = [Ref('ProxyEIP1'), Ref('ProxyEIP2')]

    add_custom_resource= t.add_resource(CustomResource("LambdaCustomDelayFunction",), **kwargs)

def pull_all_vpc_peering_networks(local_region, stackprefix):

    vpcs_per_region = {}

    ec2 = boto3.client('ec2', region_name=local_region)

    # Retrieves all regions/endpoints that work with EC2
    response = ec2.describe_regions()

    for r in response['Regions']:
        region=r.get('RegionName')
        try:
            out=pull_network_stack_vars(region,stackprefix,hcvlib.get_region_alias(region))
        except ClientError as e:
            continue

        vpcs_per_region[region]=out

    return vpcs_per_region

def pull_network_stack_vars(region, stackprefix, regionalias=False):

    vpc = {}

    if not regionalias:
        regionalias = region
    stack_name = regionalias + "-" + stackprefix + "-network"

    client = boto3.client( 'cloudformation', region_name=region )
    response = client.describe_stacks(
        StackName=stack_name
    )
    for stack in response["Stacks"]:
            outputs =  dict([(x['OutputKey'], x['OutputValue']) for x in stack['Outputs']])
            params = dict([(x['ParameterKey'], x['ParameterValue']) for x in stack['Parameters']])
            vpc_id = outputs.get('VPC')
            vpc[vpc_id]={}
            ssh_security_group = outputs.get('SSHSecurityGroup')
            public_subnetA = outputs.get("PublicSubnetA")
            public_subnetB = outputs.get("PublicSubnetB")
            vpc[vpc_id]['PublicSubnetA']=public_subnetA
            vpc[vpc_id]['PublicSubnetB']=public_subnetB
            vpc[vpc_id]['SSHSecurityGroup']=ssh_security_group
            vpc[vpc_id]['PublicSubnetACidr']=params.get("PublicSubnetACidr")
            vpc[vpc_id]['PublicSubnetBCidr']=params.get("PublicSubnetBCidr")

    return vpc

def pull_bash_network_vars():

    ssh_security_group = os.environ['SSH_SECURITY_GROUP']
    public_subnetA = os.environ['DEFAULT_PUBLIC_SUBNET_ID_a']
    public_subnetB = os.environ['DEFAULT_PUBLIC_SUBNET_ID_b']

    vpc = {}

    vpc_id = os.environ['EC2_VPC_ID']
    vpc[vpc_id]={}

    vpc[vpc_id]['PublicSubnetA']=public_subnetA
    vpc[vpc_id]['PublicSubnetB']=public_subnetB
    vpc[vpc_id]['SSHSecurityGroup']=ssh_security_group

    return vpc

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

    elb_name_param = t.add_parameter(Parameter(
        "ELBName",
        Description="Name of ELB",
        Type="String",
        MinLength=1,
        MaxLength=64,
        AllowedPattern="[-_ a-zA-Z0-9]*",
        ConstraintDescription="can contain only alphanumeric characters, spaces, dashes and underscores.",
        Default="haproxyELB"
    ))

    domain_name_param = t.add_parameter(Parameter(
        "DomainName",
        Description="HC Video internal domain name",
        Type="String",
        Default="hcv-us-east-1.infra.jitsi.net"
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

    public_dns_hosted_zone_id_param = t.add_parameter(Parameter(
        "PublicDNSHostedZoneId",
        Description="HC Video public hosted zone Id",
        Type="String",
    ))

    proxy_image_id_param = t.add_parameter(Parameter(
        "ProxyImageId",
        Description="HAProxy instance AMI id",
        Type="AWS::EC2::Image::Id",
        ConstraintDescription="must be a valid and allowed AMI id."
    ))

    proxy_instance_type = t.add_parameter(Parameter(
        "ProxyInstanceType",
        Description="Proxy server instance type",
        Type="String",
        Default="t3.medium",
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
            "c5.large",
            "c5.xlarge",
            "c5.2xlarge",
            "c5.4xlarge",
            "c5.9xlarge",
            "m5.xlarge"
        ],
        ConstraintDescription="must be a valid and allowed EC2 instance type."
    ))

    proxy_count_param = t.add_parameter(Parameter(
        "ProxyCount",
        Description="Count of proxies to launch",
        Type="Number",
        Default=2,
        MinValue=1,
        ConstraintDescription="Must be at least 1 proxy instance."
    ))

    proxy_instance_virt_param = t.add_parameter(Parameter(
        "ProxyInstanceVirtualization",
        Description="Proxy server instance virtualization",
        Type="String",
        Default="PV",
        AllowedValues=[
            "HVM",
            "PV"
        ],
        ConstraintDescription="Must be a valid and allowed virtualization type."
    ))

    proxy_az_param = t.add_parameter(Parameter(
        "ProxyAvailabilityZones",
        Description="AZ for JVB ASG",
        Type="List<AWS::EC2::AvailabilityZone::Name>",
        Default="us-east-1a,us-east-1b",
        ConstraintDescription="must be a valid and allowed availability zone."
    ))

    proxy_health_alarm_sns_param = t.add_parameter(Parameter(
        "ProxyHealthAlarmSNS",
        Description="SNS topic for ASG Alarms related to HAProxy",
        Type="String",
        Default="chaos-Health-Check-List"
    ))

    proxy_asg_alarm_sns_param = t.add_parameter(Parameter(
        "ProxyASGAlarmSNS",
        Description="SNS topic for ASG Alarms related to HAProxy",
        Type="String",
        Default="chaos-ASG-alarms"
    ))

    proxy_server_security_instance_profile_param = t.add_parameter(Parameter(
        "ProxyServerSecurityInstanceProfile",
        Description="Proxy Security Instance Profile",
        Type="String",
        Default="HipChatVideo-LoadBalancer"
    ))

    proxy_lambda_function_name = t.add_parameter(Parameter(
        'ProxyLambdaFunctionName',
        Description= "Lambda function name that CF custom resources use when create a stack",
        Type= "String",
        Default= "all-cf-update-haproxy-sg",
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
        Default="hc-video-proxy"
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

    tag_git_branch_param = t.add_parameter(Parameter(
        "TagGitBranch",
        Description="Tag: git_branch",
        Type="String",
        Default="master"
    ))

    tag_git_branch_param = t.add_parameter(Parameter(
        "TagCloudName",
        Description="Tag: cloud_name",
        Type="String"
    ))

    tag_proxy_release_param = t.add_parameter(Parameter(
        "TagProxyReleaseNumber",
        Description="Tag: proxy release number",
        Type="String",
        Default="master"
    ))

def add_alb_parameters(t):

    alb_name_param = t.add_parameter(Parameter(
        "ALBName",
        Description="Name of ALB",
        Type="String",
        MinLength=1,
        MaxLength=64,
        AllowedPattern="[-_ a-zA-Z0-9]*",
        ConstraintDescription="can contain only alphanumeric characters, spaces, dashes and underscores.",
        Default="haproxyALB"
    ))

def add_alb_resources(t, vpc_id, public_subnetA, public_subnetB, ssl_arn, ssl_extra_arn_list, haproxy_frontend_count, limit_origin_flag=False, limit_origins=[], blacklist_domains=None, ssl_policy=None, health_check_map_port_flag=False):
    if not ssl_policy:
        # aws default value
        ssl_policy = 'ELBSecurityPolicy-2016-08'

    proxy_alb = t.add_resource(elasticloadbalancingv2.LoadBalancer(
        'ProxyALB',
        Name= Ref("ALBName"),
        IpAddressType='dualstack',
        Scheme= "internet-facing",
        SecurityGroups= [ Ref("LBSecurityGroup"),],
        LoadBalancerAttributes=[elasticloadbalancingv2.LoadBalancerAttributes(Key="idle_timeout.timeout_seconds",Value='90')],
        Subnets= list(set([public_subnetA, public_subnetB])),
        Tags = Tags(
            Name = Join("-", [Ref("TagEnvironment"), Ref("RegionAlias"),Ref("StackNamePrefix"), "haproxy" ]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            public_domain=Ref("TagPublicDomainName"),
            domain= Ref("TagDomainName"),
            shard_role="ALB",
            cf_stack_id=Ref("AWS::StackId"),
            cf_stack_name=Ref("AWS::StackName")
        )
    ))

    health_check_path='/haproxy_health'
    health_check_port='8080'

    if health_check_map_port_flag:
        health_check_port='8081'

    proxy_alb_tg_http = {}
    for i in range(haproxy_frontend_count):
        proxy_alb_tg_http[i] = t.add_resource(elasticloadbalancingv2.TargetGroup(
            'ProxyAlbTgHttp%s'%i,
            Name=Join('',[Ref('ALBName'),'web%s'%i]),
            Protocol='HTTP',
            Port=80+i,
            VpcId=vpc_id,
            HealthCheckIntervalSeconds=5,
            HealthCheckTimeoutSeconds=2,
            UnhealthyThresholdCount=2,
            HealthCheckPath=health_check_path,
            HealthCheckPort=health_check_port,
            HealthCheckProtocol='HTTP',
            TargetGroupAttributes=[
                elasticloadbalancingv2.TargetGroupAttribute(
                    Key='deregistration_delay.timeout_seconds',
                    Value='30'
                )]
        ))
    proxy_alb_listener_http = t.add_resource(elasticloadbalancingv2.Listener(
        'ListenerHTTP',
        LoadBalancerArn=Ref(proxy_alb),
        Port=80,
        Protocol='HTTP',
        DefaultActions=[
            elasticloadbalancingv2.Action(
                Type='redirect',
                RedirectConfig=elasticloadbalancingv2.RedirectConfig(
                    Protocol='HTTPS',
                    Port='443',
                    Host='#{host}',
                    Path='/#{path}',
                    Query='#{query}',
                    StatusCode='HTTP_301'
                )
            )
        ]
    ))


    forwardtgs = []
    for i in proxy_alb_tg_http.keys():
        forwardtgs.append(elasticloadbalancingv2.TargetGroupTuple(
                TargetGroupArn=Ref(proxy_alb_tg_http[i]),
                Weight=1
            ))

    proxy_alb_listener_https = t.add_resource(elasticloadbalancingv2.Listener(
        'ListenerHTTPS',
        LoadBalancerArn=Ref(proxy_alb),
        Port=443,
        Protocol='HTTPS',
        SslPolicy=ssl_policy,
        DefaultActions=[elasticloadbalancingv2.Action(Type='forward', ForwardConfig=elasticloadbalancingv2.ForwardConfig(TargetGroups=forwardtgs))],
        Certificates=[elasticloadbalancingv2.Certificate(
            CertificateArn=ssl_arn
        )]
    ))

    if blacklist_domains:
        i=0
        for bd in blacklist_domains:
            deny_origin_rule = t.add_resource(elasticloadbalancingv2.ListenerRule(
                "DenySiteListenerRule%s"%i,
                ListenerArn=Ref(proxy_alb_listener_https),
                Actions=[elasticloadbalancingv2.Action(
                    Type='fixed-response',
                    FixedResponseConfig=elasticloadbalancingv2.FixedResponseConfig(
                        ContentType='text/plain',
                        MessageBody='You have exceeded your free JaaS limits, please reach out to set up a business account at https://jaas.8x8.vc/',
                        StatusCode='403'
                ))],
                Conditions=[
                    elasticloadbalancingv2.Condition(
                        Field='http-header', 
                        HttpHeaderConfig=
                            elasticloadbalancingv2.HttpHeaderConfig(HttpHeaderName='Referer', Values=['http*://%s*'%bd])
                    )
                ],
                Priority=20+i
            ))
            i=i+1
    # add additional listener rules for limiting request by origin
    if limit_origin_flag:
        allow_origin_rule = t.add_resource(elasticloadbalancingv2.ListenerRule(
            "AllowOriginWebsocketListenerRule",
            ListenerArn=Ref(proxy_alb_listener_https),
            Actions=[elasticloadbalancingv2.Action(
                Type='forward', 
                ForwardConfig=elasticloadbalancingv2.ForwardConfig(TargetGroups=forwardtgs)
            )],
            Conditions=[
                elasticloadbalancingv2.Condition(
                    Field='path-pattern',
                    PathPatternConfig=
                        elasticloadbalancingv2.PathPatternConfig(Values=['/xmpp-websocket'])
                ),
                elasticloadbalancingv2.Condition(
                    Field='http-header', 
                    HttpHeaderConfig=
                        elasticloadbalancingv2.HttpHeaderConfig(HttpHeaderName='Origin', Values=['https://%s'%limit_origin for limit_origin in limit_origins])
                )
            ],
            Priority=5
        ))
        allow_origin_tenant_rule = t.add_resource(elasticloadbalancingv2.ListenerRule(
            "AllowOriginTenantWebsocketListenerRule",
            ListenerArn=Ref(proxy_alb_listener_https),
            Actions=[elasticloadbalancingv2.Action(
                Type='forward', 
                ForwardConfig=elasticloadbalancingv2.ForwardConfig(TargetGroups=forwardtgs)
            )],
            Conditions=[
                elasticloadbalancingv2.Condition(
                    Field='path-pattern',
                    PathPatternConfig=
                        elasticloadbalancingv2.PathPatternConfig(Values=['/*/xmpp-websocket'])
                ),
                elasticloadbalancingv2.Condition(
                    Field='http-header', 
                    HttpHeaderConfig=
                        elasticloadbalancingv2.HttpHeaderConfig(HttpHeaderName='Origin', Values=['https://%s'%limit_origin for limit_origin in limit_origins])
                )
            ],
            Priority=10
        ))
        deny_origin_rule = t.add_resource(elasticloadbalancingv2.ListenerRule(
            "DenyWebsocketListenerRule",
            ListenerArn=Ref(proxy_alb_listener_https),
            Actions=[elasticloadbalancingv2.Action(
                Type='fixed-response',
                FixedResponseConfig=elasticloadbalancingv2.FixedResponseConfig(
                    ContentType='text/plain',
                    MessageBody='Denied',
                    StatusCode='403'
            ))],
            Conditions=[
                elasticloadbalancingv2.Condition(
                    Field='path-pattern', 
                    PathPatternConfig=
                        elasticloadbalancingv2.PathPatternConfig(Values=['/xmpp-websocket','/*/xmpp-websocket'])
                )
            ],
            Priority=15
        ))

    if len(ssl_extra_arn_list) > 0:
      for num,sarn in enumerate(ssl_extra_arn_list):
        t.add_resource(elasticloadbalancingv2.ListenerCertificate(
            'ListenerHTTPSExtraCerts%s'%num,
            ListenerArn=Ref('ListenerHTTPS'),
            Certificates=[elasticloadbalancingv2.Certificate(
                CertificateArn=sarn
            )]
        ))

    alb_hosts_health_check = t.add_resource(Alarm(
        'ALBHostHealthCheck',
        DependsOn=["ProxyALB","ProxyAutoScaleGroup"],
        ComparisonOperator="GreaterThanThreshold",
        AlarmName=Join("-",["awsalb", Ref("TagEnvironment"), Ref("RegionAlias"), Ref("StackNamePrefix"), "ALB-High-Unhealthy-Hosts"]),
        EvaluationPeriods=1,
        MetricName="UnHealthyHostCount",
        Namespace="AWS/ApplicationELB",
        Period=60,
        TreatMissingData="breaching",
        Statistic="Average",
        Unit="Count",
        Threshold="1",
        AlarmActions=[
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("ProxyHealthAlarmSNS")])
        ],
        OKActions=[
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("ProxyHealthAlarmSNS")])
        ],
        Dimensions=[MetricDimension(
            Name="LoadBalancer",
            Value=GetAtt("ProxyALB","LoadBalancerFullName")
        ),
        MetricDimension(
            Name="TargetGroup",
            Value=GetAtt("ProxyAlbTgHttp0","TargetGroupFullName")
        )]
    ))

    alb_target_connection_health_check = t.add_resource(Alarm(
        'ALBHTTPCodeELB5XXCountHealthCheck',
        DependsOn=["ProxyALB","ProxyAutoScaleGroup"],
        ComparisonOperator="GreaterThanThreshold",
        AlarmName=Join("-",["awsalb", Ref("TagEnvironment"), Ref("RegionAlias"), Ref("StackNamePrefix"), "ALB-5XX-Count"]),
        EvaluationPeriods=3,
        MetricName="HTTPCode_ELB_5XX_Count",
        Namespace="AWS/ApplicationELB",
        Period=60,
        TreatMissingData="notBreaching",
        Statistic="Sum",
        Unit="Count",
        Threshold="10",
        AlarmActions=[
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("ProxyHealthAlarmSNS")])
        ],
        OKActions=[
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("ProxyHealthAlarmSNS")])
        ],
        Dimensions=[MetricDimension(
            Name="LoadBalancer",
            Value=GetAtt("ProxyALB","LoadBalancerFullName")
        )]
    ))

def add_elb_resources(t, public_subnetA, public_subnetB):

    proxy_elb = t.add_resource(LoadBalancer(
        'ProxyELB',
        CrossZone= "false",
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
                InstancePort= "80",
                InstanceProtocol= "TCP",
                LoadBalancerPort= "80",
                Protocol= "TCP"
            ),
            Listener(
                InstancePort="443",
                InstanceProtocol="TCP",
                LoadBalancerPort="443",
                Protocol="TCP"
            )
        ],
        HealthCheck= HealthCheck(
            HealthyThreshold= 10,
            Interval= "5",
            Target= 'HTTPS:443/about/health?list_jvb=true',
            Timeout= "2",
            UnhealthyThreshold= "2"
        ),
        Scheme= "internet-facing",
        SecurityGroups= [ Ref("LBSecurityGroup"),],
        Subnets= list(set([public_subnetA, public_subnetB])),
        Tags = Tags(
                Name = Join("-", [Ref("TagEnvironment"), Ref("RegionAlias"),Ref("StackNamePrefix"), "haproxy" ]),
                Environment=Ref("TagEnvironmentType"),
                Service=Ref("TagService"),
                Owner=Ref("TagOwner"),
                Team=Ref("TagTeam"),
                Product=Ref("TagProduct"),
                environment=Ref("TagEnvironment"),
                public_domain=Ref("TagPublicDomainName"),
                domain= Ref("TagDomainName"),
                shard_role= "ELB",
        )
    ))

    elb_hosts_health_check = t.add_resource(Alarm(
        'ELBHostHealthCheck',
        DependsOn=["ProxyELB","ProxyAutoScaleGroup"],
        ComparisonOperator="GreaterThanThreshold",
        AlarmName=Join("-",["awselb", Ref("TagEnvironment"), Ref("RegionAlias"), Ref("StackNamePrefix"), "ELB-High-Unhealthy-Hosts"]),
        EvaluationPeriods=1,
        MetricName="UnHealthyHostCount",
        Namespace="AWS/ELB",
        Period=60,
        TreatMissingData="breaching",
        Statistic="Average",
        Unit="Count",
        Threshold="1",
        AlarmActions=[
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("ProxyHealthAlarmSNS")])
        ],
        OKActions=[
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("ProxyHealthAlarmSNS")])
        ],
        Dimensions=[MetricDimension(
            Name="LoadBalancerName",
            Value=Ref("ProxyELB")
        )]
    ))

def add_security(vpc_peering, region, stackprefix, vpc_id, ssh_security_group, haproxy_frontend_count ):

    lb_security_group = t.add_resource(SecurityGroup(
        "LBSecurityGroup",
        GroupDescription=Join(' ', ["Load Balancer nodes", Ref("TagEnvironment"), Ref("RegionAlias"),
                                    Ref("StackNamePrefix")]),
        VpcId=vpc_id,
        Tags=Tags(
            Name=Join("-", [Ref("TagEnvironment"), Ref("RegionAlias"), Ref("StackNamePrefix"), "LBGroup"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role="haproxy",
        )
    ))

    ingress12 = t.add_resource(SecurityGroupIngress(
        "ingress12",
        GroupId=Ref("LBSecurityGroup"),
        IpProtocol="tcp",
        FromPort="443",
        ToPort="443",
        CidrIp='0.0.0.0/0'
    ))

    toport = 80 + (haproxy_frontend_count-1);
    ingress13 = t.add_resource(SecurityGroupIngress(
        "ingress13",
        GroupId=Ref("LBSecurityGroup"),
        IpProtocol="tcp",
        FromPort="80",
        ToPort="%s"%toport,
        CidrIp='0.0.0.0/0'
    ))

    ingress14 = t.add_resource(SecurityGroupIngress(
        "ingress14",
        GroupId=Ref("LBSecurityGroup"),
        IpProtocol="tcp",
        FromPort="22",
        ToPort="22",
        SourceSecurityGroupId= ssh_security_group,
        SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
    ))

    ingress15 = t.add_resource(SecurityGroupIngress(
        "ingress15",
        GroupId=Ref("LBSecurityGroup"),
        IpProtocol="tcp",
        FromPort="8080",
        ToPort="8080",
        SourceSecurityGroupId=Ref("LBSecurityGroup"),
        SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
    ))


    toport = 80 + (haproxy_frontend_count-1);
    ingress16 = t.add_resource(SecurityGroupIngress(
        "ingress16",
        GroupId=Ref("LBSecurityGroup"),
        IpProtocol="tcp",
        FromPort="80",
        ToPort="%s"%toport,
        CidrIpv6="::/0"
    ))

    ingress17 = t.add_resource(SecurityGroupIngress(
        "ingress17",
        GroupId=Ref("LBSecurityGroup"),
        IpProtocol="tcp",
        FromPort="443",
        ToPort="443",
        CidrIpv6="::/0"
    ))

    ingress18 = t.add_resource(SecurityGroupIngress(
        "ingress18",
        GroupId=Ref("LBSecurityGroup"),
        IpProtocol="tcp",
        FromPort="8081",
        ToPort="8081",
        SourceSecurityGroupId=Ref("LBSecurityGroup"),
        SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
    ))

    if vpc_peering:
        vpc_peering_ingress_rule = t.add_resource(SecurityGroupIngress(
            "peeringingress",
            GroupId=Ref("LBSecurityGroup"),
            IpProtocol="tcp",
            FromPort="1024",
            ToPort="1024",
            CidrIp='10.0.0.0/8'
        ))
        vpc_peering_ingress_rule = t.add_resource(SecurityGroupIngress(
            "serfingresstcp",
            GroupId=Ref("LBSecurityGroup"),
            IpProtocol="tcp",
            FromPort="7946",
            ToPort="7946",
            CidrIp='10.0.0.0/8'
        ))
        vpc_peering_ingress_rule = t.add_resource(SecurityGroupIngress(
            "serfingressudp",
            GroupId=Ref("LBSecurityGroup"),
            IpProtocol="udp",
            FromPort="7946",
            ToPort="7946",
            CidrIp='10.0.0.0/8'
        ))

def add_outputs(t, use_elb, use_alb, create_eip, haproxy_frontend_count=4):
    output=[]

    if create_eip:
        eip_output=[
            Output(
                'ProxyEIP1',
                Description="First ElasticIP",
                Value=Ref("ProxyEIP1"),
            ),
            Output(
                'ProxyEIP2',
                Description="Second ElasticIP",
                Value=Ref("ProxyEIP2"),
            )
        ]
        output += eip_output

    if use_elb:
        elb_output=[
            Output(
                'ELB',
                Description="The ELB ID",
                Value=Ref("ProxyELB"),
                Export=Export(
                    Join("-",["ProxyELB",Ref("TagEnvironment"),Ref("AWS::Region"), Ref("StackNamePrefix")])
                )
            ),
            Output(
                'ELBHostedZoneNameID',
                Description="ELB CanonicalHostedZoneNameID",
                Value=GetAtt("ProxyELB", "CanonicalHostedZoneNameID"),
            ),
            Output(
                'ELBDNSName',
                Description="The ELB Endpoint",
                Value=GetAtt("ProxyELB", "DNSName"),
            )
        ]
        output += elb_output

    if use_alb:
        alb_output=[
            Output(
                'ALB',
                Description="The ALB ID",
                Value=Ref("ProxyALB"),
                Export=Export(
                    Join("-",["ProxyALB",Ref("TagEnvironment"),Ref("AWS::Region"), Ref("StackNamePrefix")])
                )
            ),
            Output(
                'ALBHostedZoneNameID',
                Description="ALB CanonicalHostedZoneID",
                Value=GetAtt("ProxyALB", "CanonicalHostedZoneID"),
            ),
            Output(
                'ALBDNSName',
                Description="The ALB Endpoint",
                Value=GetAtt("ProxyALB", "DNSName"),
            ),
            Output(
                'TargetGroups',
                Description="Target Groups for HAProxy Servers",
                Value=Join(",",[Ref("ProxyAlbTgHttp%s"%i) for i in range(haproxy_frontend_count)])
            )
        ]
        output += alb_output

    t.add_output(output)

def create_haproxy_template(network_vars, local_region, stackprefix, filepath, regions,
                            use_elb=False, use_alb=False, use_eip=False, create_eip=True, vpc_peering=False,
                            ssl_arn=False, ssl_extra_arns=False, haproxy_frontend_count=4,
                            limit_origin_flag=False, limit_origins=[], blacklist_domains=None, ssl_policy=None, health_check_map_port_flag=False):
    haproxy_frontend_count = int(haproxy_frontend_count)
    global t
    vpc_id = list(network_vars.keys())[0]
    public_subnetA = network_vars.get(vpc_id).get('PublicSubnetA')
    public_subnetB = network_vars.get(vpc_id).get('PublicSubnetB')
    ssh_security_group = network_vars.get(vpc_id).get('SSHSecurityGroup')

    #unique list of ARNs to use
    if ssl_extra_arns:
        ssl_extra_arn_list = list(set(ssl_extra_arns.split(',')))
    else:
        ssl_extra_arn_list = []

    if ssl_arn in ssl_extra_arn_list:
        ssl_extra_arn_list.remove(ssl_arn)

    t = Template()

    t.set_version("2010-09-09")

    t.set_description(
        "Template for the provisioning HAproxy resources for the HC Video"
    )

    # Add params
    add_parameters()

    add_alb_parameters(t)
    if use_alb:
        add_alb_resources(t, vpc_id, public_subnetA, public_subnetB, ssl_arn, ssl_extra_arn_list, haproxy_frontend_count,
                          limit_origin_flag=limit_origin_flag, limit_origins=limit_origins,
                          blacklist_domains=blacklist_domains, ssl_policy=ssl_policy, health_check_map_port_flag=health_check_map_port_flag)

    if use_elb:
        add_elb_resources(t, public_subnetA, public_subnetB)

    add_outputs(t, use_elb, use_alb, create_eip, haproxy_frontend_count)

    if create_eip:
        proxy_eip1 = t.add_resource(EIP('ProxyEIP1',))
        proxy_eip2 = t.add_resource(EIP('ProxyEIP2',))

    #add security
    add_security(vpc_peering, local_region, stackprefix, vpc_id, ssh_security_group, haproxy_frontend_count)

    if not vpc_peering:
        create_custom_resource(t, regions)

    proxy_launch_group = t.add_resource(LaunchConfiguration(
        'ProxyLaunchGroup',
        ImageId= Ref("ProxyImageId"),
        InstanceType= Ref("ProxyInstanceType"),
        IamInstanceProfile= Ref("ProxyServerSecurityInstanceProfile"),
        KeyName= Ref("KeyName"),
        SecurityGroups= [Ref("LBSecurityGroup")],
        AssociatePublicIpAddress= True,
        InstanceMonitoring= False,
        BlockDeviceMappings= [BlockDeviceMapping(
            DeviceName= "/dev/sda1",
            Ebs=EBSBlockDevice(
                VolumeSize= 20
            )
        )],
        UserData = Base64(Join('',[\
'''#!/bin/bash -v
set -e
set -x
EXIT_CODE=0
status_code=0
tmp_msg_file='/tmp/cfn_signal_message'
export CLOUD_NAME="''', {"Ref": "TagCloudName"}, '''"
export ENVIRONMENT="''', {"Ref": "TagEnvironment"}, '''"
export DOMAIN="''', {"Ref": "TagDomainName"}, '''"

function get_metadata(){
    export AWS_DEFAULT_REGION=''', {"Ref": "AWS::Region"}, '''
    instance_id=$(curl http://169.254.169.254/latest/meta-data/instance-id)
}

function install_apps(){
    PYTHON_MAJOR=$(python -c 'import platform; print(platform.python_version())' | cut -d '.' -f1)
    PYTHON_IS_3=false
    if [[ "$PYTHON_MAJOR" -eq 3 ]]; then
        PYTHON_IS_3=true
    fi
    if $PYTHON_IS_3; then
        CFN_FILE="aws-cfn-bootstrap-py3-latest.tar.gz"
    else
        CFN_FILE="aws-cfn-bootstrap-latest.tar.gz"
    fi

    status_code=0 && \\
        wget -P /root https://s3.amazonaws.com/cloudformation-examples/$CFN_FILE && \\
        mkdir -p /root/aws-cfn-bootstrap-latest && \\
        tar xvfz /root/$CFN_FILE --strip-components=1 -C /root/aws-cfn-bootstrap-latest --strip-components=1 -C /root/aws-cfn-bootstrap-latest && \\
        easy_install /root/aws-cfn-bootstrap-latest/ && \\
        pip install aws-ec2-assign-elastic-ip || status_code=1

    echo "[Boto]" > /etc/boto.cfg && echo "use_endpoint_heuristics = True" >> /etc/boto.cfg
    if [ $status_code -eq 1 ]; then echo 'Install apps stage failed' > $tmp_msg_file; return $status_code;fi
}

function check_emi(){
    set +e
    counter=1
    eip_status=1
    while [ $counter -le 5 ]; do
        aws-ec2-assign-elastic-ip --region ''', {"Ref": "AWS::Region"}, ' --valid-ips ', {"Ref": "ProxyEIP1"},',', {"Ref": "ProxyEIP2"}, ''' | grep --line-buffered -s 'is already assigned an Elastic IP' | grep -q "$instance_id"
        if [ $? -eq 0 ];then eip_status=0;break
        else
            sleep 30
            ((counter++))
        fi; done
        if [ $eip_status -eq 1 ];then echo 'EIP still not avaible' > $tmp_msg_file;return 0
        else return $eip_status; fi
}

function provisioning(){
    status_code=0 && \\
        /usr/local/bin/hook-boot-haproxy.sh >> /var/log/bootstrap.log 2>&1 || status_code=1
    [ $status_code -eq 0 ] || /usr/local/bin/dump-boot.sh > /var/log/dump_boot.log 2>&1 || DUMP_CODE=1
    if [ $status_code -eq 1 ]; then echo 'Provisioning stage failed' > $tmp_msg_file; return $status_code;fi;
}

function retry(){
    n=0
    until [ $n -ge 5 ];do
    $1
    if [ $? -eq 0 ];then
        > $tmp_msg_file;break
    fi
    n=$[$n+1];sleep 1;done
    if [ $n -eq 5 ];then
        return $n
    else
    return 0;fi
}''', f'''

( retry get_metadata && retry install_apps && { 'retry check_emi && ' if use_eip else '' }retry provisioning ) || EXIT_CODE=1

if [ ! -f /tmp/cfn_signal_message ]; then err_message='Server configuration';else err_message=$(cat $tmp_msg_file);fi
[ $EXIT_CODE -eq 0 ] || /usr/local/bin/dump-boot.sh

# Send signal about finishing configuring server
/usr/local/bin/cfn-signal -e $EXIT_CODE -r "$err_message" --resource ProxyAutoScaleGroup --stack \'''', {"Ref": "AWS::StackName"}, '\' --region ', {"Ref": "AWS::Region"}, ''' || true

if [ $EXIT_CODE -eq 1 ]; then shutdown -h now;fi''']))
    ))

    proxy_autoscale_group= t.add_resource(AutoScalingGroup(
        'ProxyAutoScaleGroup',
        AvailabilityZones=Ref("ProxyAvailabilityZones"),
        Cooldown=300,
        DesiredCapacity=Ref("ProxyCount"),
        HealthCheckGracePeriod=300,
        HealthCheckType="EC2",
        MaxSize=Ref("ProxyCount"),
        MinSize=Ref("ProxyCount"),
        VPCZoneIdentifier= list(set([public_subnetA, public_subnetB])),
        NotificationConfigurations= [NotificationConfigurations(
            TopicARN= Join(":",["arn:aws:sns", Ref("AWS::Region"),Ref("AWS::AccountId"),Ref("ProxyASGAlarmSNS")]),
            NotificationTypes= ["autoscaling:EC2_INSTANCE_LAUNCH", "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",  "autoscaling:EC2_INSTANCE_TERMINATE", "autoscaling:EC2_INSTANCE_TERMINATE_ERROR"]
        )],
        LaunchConfigurationName= Ref("ProxyLaunchGroup"),
        Tags=[
            Tag("Name",Join("-", [Ref("TagEnvironment"), Ref("RegionAlias"), Ref("StackNamePrefix"), "haproxy"]), False),
            Tag("Environment",Ref("TagEnvironmentType"),True),
            Tag("Service",Ref("TagService"),True),
            Tag("Owner",Ref("TagOwner"),True),
            Tag("Team",Ref("TagTeam"),True),
            Tag("Product",Ref("TagProduct"),True),
            Tag("environment",Ref("TagEnvironment"), True),
            Tag("public_domain",Ref("TagPublicDomainName"),True),
            Tag("domain",Ref("TagDomainName"), True),
            Tag("shard-role","haproxy", True),
            Tag("git_branch", Ref("TagGitBranch"), True),
            Tag("cloud_name", Ref("TagCloudName"), True),
            Tag("datadog","true", True),
            Tag("haproxy_release_number", Ref("TagProxyReleaseNumber"), True)
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
                        Count=Ref("ProxyCount"),
                        Timeout='PT30M'))
    ))

    #add elb or alb into ASG
    if use_elb:
        proxy_autoscale_group.properties['LoadBalancerNames']=[Ref('ProxyELB')]
    if use_alb:
        tgarns = []
        for i in range(haproxy_frontend_count):
            tgarns.append(Ref('ProxyAlbTgHttp%s'%i))

        proxy_autoscale_group.properties['TargetGroupARNs']=tgarns

    provisioning_proxy_check_terminating = t.add_resource(Alarm(
        'ProvisioningProxyCheckTerminating',
        ComparisonOperator="GreaterThanOrEqualToThreshold",
        EvaluationPeriods=1,
        MetricName="GroupTerminatingInstances",
        Namespace="AWS/AutoScaling",
        Period=300,
        TreatMissingData="ignore",
        Statistic="Sum",
        Threshold="1",
        AlarmActions=[
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("ProxyASGAlarmSNS")]),
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("ProxyHealthAlarmSNS")])
        ],
        OKActions=[
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("ProxyASGAlarmSNS")]),
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("ProxyHealthAlarmSNS")])
        ],
        InsufficientDataActions=[
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("ProxyASGAlarmSNS")]),
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("ProxyHealthAlarmSNS")])
        ],
        Dimensions=[MetricDimension(
            Name="AutoScalingGroupName",
            Value=Ref("ProxyAutoScaleGroup")
        )]
    ))

    provisioning_proxy_check_pending = t.add_resource(Alarm(
        'ProvisioningProxyCheckPending',
        ComparisonOperator="GreaterThanOrEqualToThreshold",
        EvaluationPeriods=1,
        MetricName="GroupPendingInstances",
        Namespace="AWS/AutoScaling",
        Period=300,
        TreatMissingData="ignore",
        Statistic="Sum",
        Threshold="1",
        AlarmActions=[
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("ProxyASGAlarmSNS")]),
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("ProxyHealthAlarmSNS")])
        ],
        OKActions=[
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("ProxyASGAlarmSNS")]),
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("ProxyHealthAlarmSNS")])
        ],
        InsufficientDataActions=[
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("ProxyASGAlarmSNS")]),
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("ProxyHealthAlarmSNS")])
        ],
        Dimensions=[MetricDimension(
            Name="AutoScalingGroupName",
            Value=Ref("ProxyAutoScaleGroup")
        )]
    ))

    data = json.loads(re.sub('shard_role','shard-role',t.to_json()))

    with open (filepath, 'w+') as outfile:
        json.dump(data, outfile)

def main():
    parser = argparse.ArgumentParser(description='Create Haproxy stack template')
    parser.add_argument('--region', action='store',
                        help='AWS region)', default=False, required=True)
    parser.add_argument('--regionalias', action='store',
                        help='AWS region)', default=False)
    parser.add_argument('--stackprefix', action='store',
                        help='Stack prefix name', default=False, required=False)
    parser.add_argument('--filepath', action='store',
                        help='Path to tenmplate file', default=False, required=False)
    parser.add_argument('--default_regions', nargs='+',
                        help='List of default aws regions', required=True)
    parser.add_argument('--pull_network_stack', action='store',
                        help='Pull network variables from a network stack', default='true', required=True)
    parser.add_argument('--use_elb', action='store', type=distutils.util.strtobool, help='Use ELB for the HaProxy stack',
                        default=False)
    parser.add_argument('--use_alb', action='store', type=distutils.util.strtobool, help='Use ALB for the HaProxy stack',
                        default=False)
    parser.add_argument('--use_eip', action='store', type=distutils.util.strtobool, help='Use EIP for the HaProxy stack',
                        default=False)
    parser.add_argument('--create_eip', action='store', type=distutils.util.strtobool, help='Create EIP for the HaProxy stack',
                        default=True)
    parser.add_argument('--vpc_peering', action='store', type=distutils.util.strtobool, help='Use VPC peering',
                        default=False)
    parser.add_argument('--ssl_arn', action='store',
                        help='SSL Certificate name', required=True)
    parser.add_argument('--ssl_extra_arns', action='store',
                        help='SSL Extra Certificate names (comma separated)', required=False, default=False)
    parser.add_argument('--haproxy_frontend_count', action='store',
                        help='Count of ports HAProxy listens on', default=4)
    parser.add_argument('--limit_origin', action='store',
                        help='Origin to allow websockets on', required=False, default='')
    parser.add_argument('--limit_origins', action='store',
                        help='Additional origins to allow websockets on', required=False, default='')
    parser.add_argument('--limit_origin_flag', action='store_true',
                        help='Limit origin to --limit_origin to deny websockets to all others', required=False, default=False)
    parser.add_argument('--blacklist_domains', action='store',
                        help='List of domains to blacklist by referer', required=False, default=None)
    parser.add_argument('--ssl_policy', action='store',
                        help='Name of security policy to use in SSL on ALB', required=False, default=None)
    parser.add_argument('--health_check_map_port_flag', action='store_true',
                        help='Limit origin to --limit_origin to deny websockets to all others', required=False, default=False)

    args = parser.parse_args()

    args.use_elb = bool(args.use_elb)
    args.use_alb = bool(args.use_alb)
    args.use_eip = bool(args.use_eip)
    args.create_eip = bool(args.create_eip)
    args.vpc_peering = bool(args.vpc_peering)
    blacklist_domains = None
    if args.blacklist_domains:
        blacklist_domains = args.blacklist_domains.split(',')

    if not args.region:
        print('No AWS region specified, exiting...')
        exit(1)
    elif not args.filepath:
        print ('No path to template file')
        exit(2)
    else:
        if args.pull_network_stack.lower() == "true":
            network_vars=pull_network_stack_vars(region=args.region, stackprefix=args.stackprefix, regionalias=args.regionalias)
        else:
            network_vars=pull_bash_network_vars()

    if args.limit_origin:
        limit_origins = [args.limit_origin]
    else:
        limit_origins = []

    if args.limit_origins:
        limit_origins.extend(args.limit_origins.split(','))

    limit_origins=list(set(limit_origins));
    create_haproxy_template(network_vars, local_region=args.region, stackprefix=args.stackprefix, filepath=args.filepath, regions=args.default_regions, use_elb=args.use_elb, use_alb=args.use_alb, vpc_peering=args.vpc_peering, ssl_arn=args.ssl_arn, ssl_extra_arns=args.ssl_extra_arns, haproxy_frontend_count=args.haproxy_frontend_count, limit_origin_flag=args.limit_origin_flag, limit_origins=limit_origins, blacklist_domains=blacklist_domains, ssl_policy=args.ssl_policy, health_check_map_port_flag=args.health_check_map_port_flag)

if __name__ == '__main__':
    main()
