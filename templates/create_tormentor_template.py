#!/usr/bin/env python

from templatelib import *

import boto3, re, argparse, json, os
from troposphere import Parameter, Ref, Template, Join, Tags, Base64, Output, GetAtt,cloudformation

from troposphere.elasticloadbalancing import *

from troposphere.ec2 import Instance, SecurityGroup
from troposphere.autoscaling import Tag, AutoScalingGroup, LaunchConfiguration, BlockDeviceMapping, EBSBlockDevice, NotificationConfigurations, MetricsCollection, ScalingPolicy

from troposphere.route53 import RecordSetType


def add_tormentor_cft_parameters(t, opts):
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

    node_initial_param = t.add_parameter(Parameter(
        "TormentorInitialCount",
        Description="Count of tormentor nodes",
        Type="String",
        Default="1"
    ))

    node_wait_param = t.add_parameter(Parameter(
        "TormentorWaitCount",
        Description="Count of nodes to wait on when first launching stack",
        Type="String",
        Default="1"
    ))

    node_max_param = t.add_parameter(Parameter(
        "TormentorMaxCount",
        Description="Count of nodes at maxium",
        Type="String",
        Default="1"
    ))

    iam_role = t.add_parameter(Parameter(
        "TormentorSecurityInstanceProfile",
        Description="IAM Profile for tormentor nodes",
        Type="String",
        Default="HipChat-Video-Torturer"
    ))

    image_id_param = t.add_parameter(Parameter(
        "TormentorImageId",
        Description="Utility instance AMI id",
        Type="AWS::EC2::Image::Id",
        ConstraintDescription="must be a valid and allowed AMI id."
    ))

    hub_instance_type = t.add_parameter(Parameter(
        "TormentorInstanceType",
        Description="Tormentor instance type",
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
            "c4.large",
            "c4.xlarge",
            "c5.large",
            "c5.xlarge",
            "m5.large",
            "m4.large"
        ],
        ConstraintDescription="must be a valid and allowed EC2 instance type."
    ))

    instance_virt_param = t.add_parameter(Parameter(
        "InstanceVirtualization",
        Description="Proxy server instance virtualization",
        Type="String",
        Default="PV",
        AllowedValues=[
            "HVM",
            "PV"
        ],
        ConstraintDescription="Must be a valid and allowed virtualization type."
    ))

    asg_sns = t.add_parameter(Parameter(
        "ASGAlarmSNS",
        Description="Name of SNS Topic for ASG events",
        ConstraintDescription="Only the name part of the SNS ARN",
        Type="String",
        Default="JitsiNet-ASG-alarms"
    ))

    asg_sns = t.add_parameter(Parameter(
        "HealthCheckSNS",
        Description="Name of SNS Topic for Health events",
        ConstraintDescription="Only the name part of the SNS ARN",
        Type="String",
        Default="JitsiNet-Health-Check-List"
    ))

    tag_git_branch_param = t.add_parameter(Parameter(
        "TagGitBranch",
        Description="Tag: git_branch",
        Type="String",
        Default="main"
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

def add_tormentor_security(t,opts):

    instance_security_group = t.add_resource(SecurityGroup(
        "InstanceSecurityGroup",
        GroupDescription=Join(' ', ["Tormentor Nodes", Ref("RegionAlias"),
                                    Ref("StackNamePrefix")]),
        VpcId=opts['vpc_id'],
        Tags=Tags(
            Name=Join("-", [Ref("RegionAlias"), Ref("StackNamePrefix"), "TormentorGroup"]),
            Environment=Ref("TagEnvironmentType"),
            Service=Ref("TagService"),
            Owner=Ref("TagOwner"),
            Team=Ref("TagTeam"),
            Product=Ref("TagProduct"),
            environment=Ref("TagEnvironment"),
            role="tormentor"
        )
    ))

    node_ssh_ingress = t.add_resource(SecurityGroupIngress(
        "NodeSSHIngress",
        GroupId=Ref("InstanceSecurityGroup"),
        IpProtocol="tcp",
        FromPort="22",
        ToPort="22",
        SourceSecurityGroupId= opts['ssh_security_group'],
        SourceSecurityGroupOwnerId=Ref("AWS::AccountId")
    ))


    egress_instance = t.add_resource(SecurityGroupEgress(
        "EgressInstance",
        GroupId=Ref("InstanceSecurityGroup"),
        IpProtocol="-1",
        CidrIp='0.0.0.0/0',
        FromPort='-1',
        ToPort='-1'
    ))



def add_tormentor_cft_resources(t,opts):

    nodeWaitHandle= t.add_resource(cloudformation.WaitConditionHandle(
        'NodeWaitHandle',
    ))

    launch_group = t.add_resource(LaunchConfiguration(
        'InstanceLaunchGroup',
        ImageId= Ref("TormentorImageId"),
        InstanceType= Ref("TormentorInstanceType"),
        IamInstanceProfile= Ref("TormentorSecurityInstanceProfile"),
        KeyName= Ref("KeyName"),
        SecurityGroups= [Ref("InstanceSecurityGroup")],
        BlockDeviceMappings= [BlockDeviceMapping(
            DeviceName= "/dev/sda1",
            Ebs=EBSBlockDevice(
                VolumeSize= 8
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

            "GIT_BRANCH_TAG=\"git_branch\"\n",
            "GIT_BRANCH=$(/usr/local/bin/aws ec2 describe-tags --filters \"Name=resource-id,Values=${EC2_INSTANCE_ID}\" \"Name=key,Values=${GIT_BRANCH_TAG}\" | jq .Tags[0].Value -r)\n",

            "[ \"$GIT_BRANCH\" == \"null\" ] && GIT_BRANCH=\"master\"\n",

            "[ -z \"$GIT_BRANCH\" ] && GIT_BRANCH=\"master\"\n",

            "/usr/local/bin/aws s3 cp s3://jitsi-bootstrap-assets/vault-password /root/.vault-password\n",
            "/usr/local/bin/aws s3 cp s3://jitsi-bootstrap-assets/id_rsa_jitsi_deployment /root/.ssh/id_rsa\n",
            "chmod 400 /root/.ssh/id_rsa\n",
            "echo '[tag_shard","_","role_tormentor]' > /root/ansible_inventory\n",
            "echo '127.0.0.1' >> /root/ansible_inventory\n",
            "ansible-pull -v -U git@github.com:8x8Cloud/jitsi-video-infrastructure.git \
            -d /tmp/bootstrap --purge \
            -i \"/root/ansible_inventory\" \
            --vault-password-file=/root/.vault-password \
            --accept-host-key \
            -C \"$GIT_BRANCH\" \
            ansible/configure-tormentor.yml >> /var/log/bootstrap.log 2>&1 || EXIT_CODE=1\n",
            "# Send signal about finishing configuring server\n",
            
            "/usr/local/bin/cfn-signal -e $EXIT_CODE -r 'Server configuration' '", {"Ref": "NodeWaitHandle"}, "'\n",
            "rm /root/.vault-password /root/.ssh/id_rsa /root/ansible_inventory\n"
        ]))
    ))

    nodeWaitCondition= t.add_resource(cloudformation.WaitCondition(
        'NodeWaitCondition',
        DependsOn= "NodeAutoScaleGroup",
        Handle= Ref("NodeWaitHandle"),
        Timeout= 3600,
        Count= Ref("TormentorWaitCount")
    ))

    node_autoscale_group= t.add_resource(AutoScalingGroup(
        'NodeAutoScaleGroup',
        AvailabilityZones=[Join("",[Ref("AWS::Region"),Ref("AZ1Letter")]),Join("",[Ref("AWS::Region"),Ref("AZ2Letter")])],
        Cooldown=300,
        DesiredCapacity=Ref("TormentorInitialCount"),
        HealthCheckGracePeriod=300,
        HealthCheckType="EC2",
        MaxSize=Ref("TormentorMaxCount"),
        MinSize=Ref("TormentorInitialCount"),
        VPCZoneIdentifier= [opts['nat_subnetA'], opts['nat_subnetB']],
        NotificationConfigurations= [NotificationConfigurations(
            TopicARN= Join(":",["arn:aws:sns", Ref("AWS::Region"),Ref("AWS::AccountId"),Ref("ASGAlarmSNS")]),
            NotificationTypes= ["autoscaling:EC2_INSTANCE_LAUNCH", "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",  "autoscaling:EC2_INSTANCE_TERMINATE", "autoscaling:EC2_INSTANCE_TERMINATE_ERROR"]
        )],
        LaunchConfigurationName= Ref("InstanceLaunchGroup"),
        Tags=[
            Tag("Name",Join("-", [Ref("RegionAlias"), Ref("StackNamePrefix"), "tormentor"]), False),
            Tag("Environment",Ref("TagEnvironmentType"),True),
            Tag("Service",Ref("TagService"),True),
            Tag("Owner",Ref("TagOwner"),True),
            Tag("Team",Ref("TagTeam"),True),
            Tag("Product",Ref("TagProduct"),True),
            Tag("environment", Ref("TagEnvironment"), True),
            Tag("shard-role","tormentor", True),
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

#this generates a CFT which builds two large NAT subnets behind a NAT gateway for use with services that do not require public IP addresses
def create_tormentor_template(filepath,opts):
    t  = create_template()
    add_tormentor_cft_parameters(t,opts)
    add_tormentor_security(t,opts)
    add_tormentor_cft_resources(t,opts)

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

        create_tormentor_template(filepath=args.filepath,opts=opts)

if __name__ == '__main__':
    main()
