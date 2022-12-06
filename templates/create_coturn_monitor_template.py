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

    region_alias_param = t.add_parameter(Parameter(
        "RegionAlias",
        Description="Alias for AWS Region",
        Type="String",
    ))

    base_image_id_param = t.add_parameter(Parameter(
        "BaseImageId",
        Description="Base instance AMI id",
        Type="AWS::EC2::Image::Id",
        ConstraintDescription="must be a valid and allowed AMI id."
    ))

    coturn_monitor_instance_type = t.add_parameter(Parameter(
        "CoturnMonitorInstanceType",
        Description="Coturn Monitor server instance type",
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
            "t3.xlarge"
            ],
        ConstraintDescription="must be a valid and allowed EC2 instance type."
    ))

    coturn_monitor_instance_virt_param = t.add_parameter(Parameter(
        "CoturnMonitorInstanceVirtualization",
        Description="Coturn Monitor server instance virtualization",
        Type="String",
        Default="PV",
        AllowedValues=[
            "HVM",
            "PV"
        ],
        ConstraintDescription="Must be a valid and allowed virtualization type."
    ))

    coturn_monitor_az_param = t.add_parameter(Parameter(
        "CoturnMonitorAvailabilityZones",
        Description="AZ for Coturn Monitor ASG",
        Type="List<AWS::EC2::AvailabilityZone::Name>",
        Default="us-east-1a,us-east-1b",
        ConstraintDescription="must be a valid and allowed availability zone."
    ))

    coturn_monitor_server_security_instance_profile_param = t.add_parameter(Parameter(
        "CoturnMonitorServerSecurityInstanceProfile",
        Description="Coturn Monitor Security Instance Profile",
        Type="String",
        Default="HipChatVideo-Coturn"
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
        Default="hc-video-coturnmonitor"
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

def add_security(opts):

    coturn_monitor_security_group = t.add_resource(SecurityGroup(
        "CoturnMonitorSecurityGroup",
        GroupDescription=Join(' ', ["Coturn monitor nodes", Ref("TagEnvironment"), Ref("RegionAlias"),
                                    Ref("StackNamePrefix")]),
        VpcId=opts['vpc_id'],
        Tags=Tags(
            Name=Join("-", [Ref("TagEnvironment"), Ref("RegionAlias"), Ref("StackNamePrefix"), "CoturnMonitorGroup"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role="coturn-monitor",
        )
    ))

    ingress12 = t.add_resource(SecurityGroupIngress(
        "ingress12",
        GroupId=Ref("CoturnMonitorSecurityGroup"),
        IpProtocol="tcp",
        FromPort="443",
        ToPort="443",
        CidrIp="0.0.0.0/0"
    ))

    ingress13 = t.add_resource(SecurityGroupIngress(
        "ingress13",
        GroupId=Ref("CoturnMonitorSecurityGroup"),
        IpProtocol="udp",
        FromPort="443",
        ToPort="443",
        CidrIp="0.0.0.0/0"
    ))

    ingress14 = t.add_resource(SecurityGroupIngress(
        "ingress14",
        GroupId=Ref("CoturnMonitorSecurityGroup"),
        IpProtocol="tcp",
        FromPort="443",
        ToPort="443",
        CidrIpv6="::/0"
    ))

    ingress15 = t.add_resource(SecurityGroupIngress(
        "ingress15",
        GroupId=Ref("CoturnMonitorSecurityGroup"),
        IpProtocol="udp",
        FromPort="443",
        ToPort="443",
        CidrIpv6="::/0"
    ))


    ingress16 = t.add_resource(SecurityGroupIngress(
        "ingress16",
        GroupId=Ref("CoturnMonitorSecurityGroup"),
        IpProtocol="tcp",
        FromPort="22",
        ToPort="22",
        SourceSecurityGroupId= opts['ssh_security_group'],
        SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
    ))

    ingress17 = t.add_resource(SecurityGroupIngress(
        "ingress17",
        GroupId=Ref("CoturnMonitorSecurityGroup"),
        IpProtocol="udp",
        FromPort="444",
        ToPort="444",
        CidrIp="0.0.0.0/0"
    ))

    egress1 = t.add_resource(SecurityGroupEgress(
        "egress1",
        GroupId=Ref("CoturnMonitorSecurityGroup"),
        IpProtocol="-1",
        CidrIp='0.0.0.0/0',
        FromPort='-1',
        ToPort='-1'
    ))

    egress2 = t.add_resource(SecurityGroupEgress(
        "egress2",
        GroupId=Ref("CoturnMonitorSecurityGroup"),
        IpProtocol="-1",
        CidrIpv6='::/0',
        FromPort='-1',
        ToPort='-1'
    ))

def create_coturn_monitor_template(filepath, opts):

    global t

    t = Template()

    t.add_version("2010-09-09")

    t.add_description(
        "Template for the provisioning TURN Monitor resources for the HC Video"
    )

    # Add params
    add_parameters()

    #add security
    add_security(opts=opts)

    coturn_launch_group = t.add_resource(LaunchConfiguration(
        'CoturnMonitorLaunchGroup',
        ImageId= Ref("BaseImageId"),
        InstanceType= Ref("CoturnMonitorInstanceType"),
        IamInstanceProfile= Ref("CoturnMonitorServerSecurityInstanceProfile"),
        KeyName= Ref("KeyName"),
        SecurityGroups= [Ref("CoturnMonitorSecurityGroup")],
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
            "instance_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)\n",
            "local_ip=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)\n",
            "MY_COMPONENT_ID=\"coturn-monitor-$(echo $local_ip | awk -F. '{print $4}')\"\n",
            "MY_HOSTNAME=\"all-${AWS_DEFAULT_REGION}-${MY_COMPONENT_ID}\"\n",
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
            "if [ $status_code -eq 1 ]; then echo 'Install apps stage failed' > $tmp_msg_file; exit $status_code;fi\n"
            "}\n",

            "function provisioning(){\n",
            "status_code=0 && \\\n",
            "hostname $MY_HOSTNAME\n",
            "/usr/local/bin/aws ec2 create-tags --resources $instance_id --tags Key=Name,Value=\"$MY_HOSTNAME\"\n",
            "grep $MY_HOSTNAME /etc/hosts || echo \"$local_ip  $MY_HOSTNAME\" >> /etc/hosts\n",
            "export GIT_BRANCH=$(/usr/local/bin/aws ec2 describe-tags --region ", {"Ref": "AWS::Region"}," --filters \"Name=resource-id,Values=$instance_id\" \"Name=key,Values=git_branch\"|jq -r .Tags[].Value)\n",
            "/usr/local/bin/aws s3 cp s3://jitsi-bootstrap-assets/vault-password /root/.vault-password\n",
            "/usr/local/bin/aws s3 cp s3://jitsi-bootstrap-assets/id_rsa_jitsi_deployment /root/.ssh/id_rsa\n",
            "chmod 400 /root/.ssh/id_rsa\n",
            "echo '[all]' > /root/ansible_inventory\n",
            "echo '127.0.0.1' >> /root/ansible_inventory\n",
            "ansible-pull -v -U git@github.com:8x8Cloud/jitsi-video-infrastructure.git \
            -d /tmp/bootstrap --purge \
            -i \"/root/ansible_inventory\" \
            --vault-password-file=/root/.vault-password \
            --accept-host-key \
            -C \"$GIT_BRANCH\" \
            --tags \"all\" \
            ansible/configure-coturn-monitor-local.yml >> /var/log/bootstrap.log 2>&1 || status_code=1\n",

            "if [ $status_code -eq 1 ]; then echo 'Provisioning stage failed' > $tmp_msg_file; exit $status_code;fi;\n"
            "}\n",

            "( get_metadata && install_apps && provisioning ) ||  EXIT_CODE=1\n"
            
            "if [ ! -f /tmp/cfn_signal_message ]; then err_message='Server configuration';else err_message=$(cat $tmp_msg_file);fi\n",

            "# Send signal about finishing configuring server\n",
            "/usr/local/bin/cfn-signal -e $EXIT_CODE -r \"$err_message\" '", {"Ref": "ClientWaitHandle"}, "'|| true\n",

            "#if [ $EXIT_CODE -eq 1 ]; then shutdown -h now;fi\n"
        ]))
    ))

    clientWaitHandle= t.add_resource(cloudformation.WaitConditionHandle(
        'ClientWaitHandle',
    ))

    clientWaitCondition= t.add_resource(cloudformation.WaitCondition(
        'ClientWaitCondition',
        DependsOn= "CoturnMonitorAutoScaleGroup",
        Handle= Ref("ClientWaitHandle"),
        Timeout= 3600,
        Count= 1
    ))

    coturn_monitor_autoscale_group= t.add_resource(AutoScalingGroup(
        'CoturnMonitorAutoScaleGroup',
        AvailabilityZones=Ref("CoturnMonitorAvailabilityZones"),
        Cooldown=300,
        DesiredCapacity=1,
        HealthCheckGracePeriod=300,
        HealthCheckType="EC2",
        MaxSize=1,
        MinSize=1,
        VPCZoneIdentifier= [opts['public_subnetA'], opts['public_subnetB']],
        LaunchConfigurationName= Ref("CoturnMonitorLaunchGroup"),
        Tags=[
            Tag("Name",Join("-", [Ref("TagEnvironment"), Ref("RegionAlias"), Ref("StackNamePrefix"), "coturn-monitor"]), False),
            Tag("Environment",Ref("TagEnvironmentType"),True),
            Tag("Service",Ref("TagService"),True),
            Tag("Owner",Ref("TagOwner"),True),
            Tag("Team",Ref("TagTeam"),True),
            Tag("Product",Ref("TagProduct"),True),
            Tag("environment",Ref("TagEnvironment"), True),
            Tag("domain",Ref("TagDomainName"), True),
            Tag("shard-role","coturnmonitor", True),
            Tag("git_branch", Ref("TagGitBranch"), True )
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
        TerminationPolicies=["Default"]

    ))

    write_template_json(filepath=filepath, t=t)

def main():
    parser = argparse.ArgumentParser(description='Create Coturn Monitor stack template')
    parser.add_argument('--region', action='store',
                        help='AWS region)', default=False, required=True)
    parser.add_argument('--regionalias', action='store',
                        help='AWS region)', default=False)
    parser.add_argument('--stackprefix', action='store',
                        help='Stack prefix name', default=False, required=False)
    parser.add_argument('--filepath', action='store',
                        help='Path to tenmplate file', default=False, required=False),
    parser.add_argument('--pull_network_stack', action='store',
                        help='Pull network variables from a network stack', default='true', required=True)
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
        create_coturn_monitor_template(filepath=args.filepath, opts=opts)

if __name__ == '__main__':
    main()
