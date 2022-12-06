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
    
def create_empty_ambda_template(filepath, runtime, handler):
    
    global t
    
    t = Template()

    t.set_version("2010-09-09")

    t.set_description(
        "Template for the provisioning AWS Lambda scripts for Video team"
    )

    # Add params
    add_parameters()
        

    awslambda_function = t.add_resource(Function(
        "CreateAWSLambdaFunction",
        Description="Create AWS Lambda function for Video team",
        Code=Code(
            ZipFile=" "
        ),
        Role=lambda_iam_role_arn,
        Runtime=runtime,
        Timeout=180,
        Handler=handler,
        FunctionName=Ref("AWSLambdaFunctionName")
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
    parser = argparse.ArgumentParser(description='Create Lambda stack template')
    parser.add_argument('--region', action='store',
                        help='AWS region)', default=False, required=True)
    parser.add_argument('--regionalias', action='store',
                        help='AWS region alias)', default=False)
    parser.add_argument('--iamrole', action='store',
                        help='Lambda IAM role name',default=False, required=True)
    parser.add_argument('--runtime', action='store',
                        help='Lambda runtime',default=False, required=True)
    parser.add_argument('--handler', action='store',
                        help='Lambda handler',default='index.handler', required=True)
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
        create_empty_ambda_template(filepath=args.filepath, runtime=args.runtime, handler=args.handler)

if __name__ == '__main__':
    main()
