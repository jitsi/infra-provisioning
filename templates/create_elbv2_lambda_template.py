#!/usr/bin/env python

# pip install troposphere boto3
import boto3
import argparse, json
from templatelib import pull_network_stack_vars, create_template, add_stack_name_region_alias_parameters, add_default_tag_parameters
from troposphere import Parameter, Ref, Join, Output, GetAtt, Export, Tags
from troposphere.elasticloadbalancingv2 import LoadBalancer
from troposphere.ec2 import SecurityGroup, SecurityGroupIngress, SecurityGroupEgress
from troposphere.awslambda import Function, Code, Environment, Permission
from troposphere.sns import SubscriptionResource

def get_asg_sns_topics(region):
    sns = boto3.client('sns', region_name=region)
    
    describe_sns_topics = sns.list_topics()

    asg_topics = {}
    for topic in describe_sns_topics['Topics']:
         if "ASG" in topic['TopicArn'].split(':')[5]:
             asg_topics[topic['TopicArn'].split(':')[5]] = topic['TopicArn']
    
    return asg_topics

def get_networks(region):
    cft = boto3.client('cloudformation', region_name=region)
    describe_network_stacks = cft.describe_stacks()

    stacks_outputs={}
    for stack in describe_network_stacks['Stacks']:
        for tag in stack['Tags']:
            if tag['Key'] == 'stack-role':
                if tag['Value'] == 'network':
                    outputs =  dict([(x['OutputKey'], x['OutputValue']) for x in stack['Outputs']])
                    stacks_outputs[stack['StackName']] = outputs
    return stacks_outputs
    
def get_lambda_role_arn(lambda_iam_role_name):
    
    global lambda_iam_role_arn
    
    client = boto3.client('iam')
    response = client.get_role(
        RoleName=lambda_iam_role_name
    )
    
    lambda_iam_role_arn = response['Role']['Arn']
    
def add_parameters(t):
    
    awslabda_function_name = t.add_parameter(Parameter(
        "AWSLambdaFunctionName",
        Description="AWS Lambda function name",
        Type="String"
    ))
    
    elb_name_param = t.add_parameter(Parameter(
        "ELBv2Name",
        Description="ELBv2 name",
        Type="String"
    ))

    elbv2_ssl_cert_arn = t.add_parameter(Parameter(
        "SSLCertARN",
        Description="SSL Certificate ARN",
        Type="String"
    ))

    elbv2_ssl_policy = t.add_parameter(Parameter(
        "SSLPolicy",
        Description="ELB SSL Security Policy",
        Type="String"
    ))

    core_target_group_name = t.add_parameter(Parameter(
        "CoreTargetGroupName",
        Description="Name of Core Target Group",
        Type="String"
    ))

def add_security(t, opts):
    global alb_sec_group
    i = 0
    alb_sec_group={}
    for opt in list(opts.values()):
        alb_sec_group[opt.get('VPC')] = "ALBSecurityGroup"+str(i)
        lb_security_group = t.add_resource(SecurityGroup(
            "ALBSecurityGroup"+str(i),
            GroupDescription=Join(' ', ["Load Balancer nodes", Ref("RegionAlias"),
                                        Ref("StackNamePrefix"), i]),
            VpcId=opt.get('VPC'),
            Tags=Tags(
                Name=Join("-",[Ref("RegionAlias"), "ALBGroup", i]),
                Environment=Ref("TagEnvironmentType"),
                Service=Ref("TagService"),
                Owner=Ref("TagOwner"),
                Team=Ref("TagTeam"),
                Product=Ref("TagProduct"),
                role='lambda'
            )
        ))
        ingress1 = t.add_resource(SecurityGroupIngress(
            "ingress"+str(17+i),
            GroupId=opt.get('JVBSecurityGroup'),
            IpProtocol="tcp",
            FromPort="9090",
            ToPort="9090",
            CidrIp='0.0.0.0/0'
        ))
        ingress2 = t.add_resource(SecurityGroupIngress(
            "ingress"+str(i),
            GroupId=Ref("ALBSecurityGroup"+str(i)),
            IpProtocol="tcp",
            FromPort="443",
            ToPort="443",
            CidrIp='0.0.0.0/0'
        ))
        ingress3 = t.add_resource(SecurityGroupIngress(
            "ingress"+str(i+len(list(opts.values()))),
            GroupId=Ref("ALBSecurityGroup"+str(i)),
            IpProtocol="tcp",
            FromPort="9090",
            ToPort="9090",
            CidrIp='0.0.0.0/0'
        ))
        i+=1

def create_elbv2(t, region, regionalias, opts):
    i = 0
    for opt in list(opts.values()):
        add_elv2 = t.add_resource(LoadBalancer(
            "CreateALB"+str(i),
            Name=Join("-",[Ref("ELBv2Name"), Ref("StackNamePrefix")]),
            Scheme="internet-facing",
            Subnets=[opt.get('PublicSubnetA'), opt.get('PublicSubnetB')],
            SecurityGroups=[Ref(alb_sec_group.get(opt.get('VPC')))]
        ))
        i+=1

def create_lambda_template(filepath, region, regionalias, opts, asg_topics):
    t = create_template()

    # Add params
    add_parameters(t)
    
    add_stack_name_region_alias_parameters(t)
    
    add_default_tag_parameters(t)
    
    add_security(t, opts)

    create_elbv2(t, region, regionalias, opts)

    awslambda_function = t.add_resource(Function(
        "CreateAWSLambdaFunction",
        Description="Create AWS Lambda function for JVB ELBv2 ",
        Code=Code(
            ZipFile=" "  
        ),
        Role=lambda_iam_role_arn,
        Runtime= "python2.7",
        Timeout= 180,
        Handler='lambda_function.lambda_handler',
        FunctionName=Ref("AWSLambdaFunctionName"),
        Environment=Environment(
            Variables= {
                "REGION_ALIAS":Ref("RegionAlias"),
                "SSLCertARN":Ref("SSLCertARN"),
                "SSLPolicy":Ref("SSLPolicy")
            }
        )
    ))
    
    i=0
    for topic_arn in list(asg_topics.values()): 
        invoke_awslambda_permission = t.add_resource(Permission(
            "InvokeAWSLambdaPermission"+str(i),
            DependsOn="CreateAWSLambdaFunction",
            FunctionName=Ref("AWSLambdaFunctionName"),
            Action="lambda:InvokeFunction",
            Principal="sns.amazonaws.com",
            SourceArn= topic_arn
        ))
        
        aws_lambda_create_subscribtion = t.add_resource(SubscriptionResource(
            "CreateLambdaSNSSubscribtion"+str(i),
            DependsOn="InvokeAWSLambdaPermission"+str(i),
            Endpoint=GetAtt("CreateAWSLambdaFunction","Arn"),
            TopicArn=topic_arn,
            Protocol="lambda"
        ))
        i+=1
        
    t.add_output([
        Output(
            "AWSLambdaFunctionName",
            Description="Lambda function name",
            Value=Ref("AWSLambdaFunctionName"),
            Export=Export(name=Ref("AWSLambdaFunctionName"))
        )
    ])
    data = json.loads(t.to_json())
    with open (filepath, 'w+') as outfile:
        json.dump(data, outfile)
    
def main():
    parser = argparse.ArgumentParser(description='Create Haproxy stack template')
    parser.add_argument('--region', action='store',
                        help='AWS region)', default=False, required=True)
    parser.add_argument('--regionalias', action='store',
                        help='AWS region alias)', default=False)
    parser.add_argument('--iamrole', action='store',
                        help='Lambda IAM role name',default=False, required=True)
    parser.add_argument('--filepath', action='store',
                        help='Path to tenmplate file', default=False, required=False)

    args = parser.parse_args()

    if not args.region:
        print('No AWS region specified, exiting...')
        exit(1)
    elif not args.filepath:
        print ('No path to template file')
        exit(2)
    elif not args.iamrole:
        print ('No Lambda IAM role name')
        exit(3)
    else:
        if not args.regionalias:
            regionalias = args.region
        else:
            regionalias=args.regionalias
        get_lambda_role_arn(lambda_iam_role_name=args.iamrole)
        opts = get_networks(region=args.region)
        asg_topics = get_asg_sns_topics(region=args.region)
        create_lambda_template(filepath=args.filepath, region=args.region, regionalias=regionalias, opts=opts, asg_topics=asg_topics)

if __name__ == '__main__':
    main()
