#!/usr/bin/env python

# pip install troposphere boto3
import boto3
import argparse, json, os
from troposphere import Parameter, Ref, Template, Join, Output, GetAtt, cloudformation, Export
from troposphere.cloudformation import WaitCondition, WaitConditionHandle
from troposphere.awslambda import Function, Code, Environment, Permission, EventSourceMapping
from troposphere.sns import SubscriptionResource

def get_lambda_role_arn(lambda_iam_role_name):
    
    global lambda_iam_role_arn
    
    client = boto3.client('iam')
    response = client.get_role(
        RoleName=lambda_iam_role_name
    )
    
    lambda_iam_role_arn = response['Role']['Arn']
    
def add_parameters():
    
    region_alias_param = t.add_parameter(Parameter(
        "RegionAlias",
        Description="Alias for AWS Region",
        Type="String",
    ))
    
    awslabda_function_name = t.add_parameter(Parameter(
        "AWSLambdaFunctionName",
        Description="AWS Lambda function name",
        Type="String"
    ))
    
    ok_topics = t.add_parameter(Parameter(
        "OkTopics",
        Description="AWS Lambda Ok topics",
        Type="String"
    ))
    
    alarm_topics = t.add_parameter(Parameter(
        "AlarmTopics",
        Description="AWS Lambda Alarm topics",
        Type="String"
    ))
    
    insufficient_data_topics = t.add_parameter(Parameter(
        "InsufficientDataTopics",
        Description="AWS Lambda Insufficient Data topics",
        Type="String"
    ))
    
    alarm_disk_path = t.add_parameter(Parameter(
        "AlarmDiskPath",
        Description="Disk path for alarms",
        Type="String"
    ))
    
    alarm_asg_sns_topic = t.add_parameter(Parameter(
        "ASGAlarmSNS",
        Description="ASGAlarmSNS topic name",
        Type="String"
    ))
    
def create_lambda_template(filepath):
    
    global t
    
    t = Template()

    t.add_version("2010-09-09")

    t.add_description(
        "Template for the provisioning AWS Lambda scripts for creating CloudWatch alarms by SNS events"
    )

    # Add params
    add_parameters()

    awslambda_function = t.add_resource(Function(
        "CreateAWSLambdaFunction",
        Description="Create AWS Lambda function for ASG cloudwatch alerts",
        Code=Code(
            ZipFile=" "
        ),
        Role=lambda_iam_role_arn,
        Runtime= "nodejs4.3",
        Timeout= 180,
        Handler='index.handler',
        FunctionName=Ref("AWSLambdaFunctionName"),
        Environment=Environment(
            Variables= {
                "INSUFFICIENT_DATA_TOPICS":Ref("InsufficientDataTopics"),
                "ALARM_TOPICS":Ref("AlarmTopics"),
                "OK_TOPICS":Ref("OkTopics"),
                "DISK_PATH":Ref("AlarmDiskPath"),
                "REGION_ALIAS":Ref("RegionAlias")
            }
        )
    ))

    invoke_awslambda_permission = t.add_resource(Permission(
        "InvokeAWSLambdaPermission",
        DependsOn="CreateAWSLambdaFunction",
        FunctionName=Ref("AWSLambdaFunctionName"),
        Action="lambda:InvokeFunction",
        Principal="sns.amazonaws.com",
        SourceArn= Join(":",["arn:aws:sns", Ref("AWS::Region"),Ref("AWS::AccountId"),Ref("ASGAlarmSNS")]),
    ))
    
    aws_lambda_create_subscribtion = t.add_resource(SubscriptionResource(
        "CreateLambdaSNSSubscribtion",
        DependsOn="InvokeAWSLambdaPermission",
        Endpoint=GetAtt("CreateAWSLambdaFunction","Arn"),
        TopicArn=Join(":",["arn:aws:sns", Ref("AWS::Region"),Ref("AWS::AccountId"),Ref("ASGAlarmSNS")]),
        Protocol="lambda"
    ))
    
    t.add_output([
        Output(
            "AWSLambdaFunctionName",
            Description="Lambda function name",
            Value=Ref("AWSLambdaFunctionName"),
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
        create_lambda_template(filepath=args.filepath)

if __name__ == '__main__':
    main()
