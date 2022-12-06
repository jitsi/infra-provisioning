#!/usr/bin/env python

# pip install troposphere boto3

from troposphere.dynamodb import (KeySchema, AttributeDefinition, ProvisionedThroughput, Table, TimeToLiveSpecification,
                                  GlobalSecondaryIndex, Projection)
from troposphere import applicationautoscaling as applicationautoscaling
from troposphere.applicationautoscaling import ScalableTarget, TargetTrackingScalingPolicyConfiguration
from troposphere import iam as iam
from awacs.aws import Allow, Statement, Principal, Policy, Action
from awacs.sts import AssumeRole
from templatelib import *


def add_dynamo_db_params(t):
    
    conf_readunits = t.add_parameter(Parameter(
        "ConferencesByJidReadCapacityUnits",
        Description="Provisioned read throughput",
        Type="Number",
        Default="5",
        MinValue="5",
        MaxValue="10000",
        ConstraintDescription="should be between 5 and 10000"
    ))

    conf_writeunits = t.add_parameter(Parameter(
        "ConferencesByJidWriteCapacityUnits",
        Description="Provisioned write throughput",
        Type="Number",
        Default="8",
        MinValue="5",
        MaxValue="10000",
        ConstraintDescription="should be between 5 and 10000"
    ))

    conf_info_readunits = t.add_parameter(Parameter(
        "ConferencesInfoByJidReadCapacityUnits",
        Description="Provisioned read throughput",
        Type="Number",
        Default="5",
        MinValue="5",
        MaxValue="10000",
        ConstraintDescription="should be between 5 and 10000"
    ))

    conf_info_writeunits = t.add_parameter(Parameter(
        "ConferencesInfoByJidWriteCapacityUnits",
        Description="Provisioned write throughput",
        Type="Number",
        Default="5",
        MinValue="5",
        MaxValue="10000",
        ConstraintDescription="should be between 5 and 10000"
    ))

    conf_by_jid_tableIndexName = t.add_parameter(Parameter(
        "ConferencesByJidPrimaryKey",
        Description="Table: Primary Key Field",
        Type="String",
        Default="conference",
        AllowedPattern="[a-zA-Z0-9]*",
        MinLength="1",
        MaxLength="2048",
        ConstraintDescription="must contain only alphanumberic characters"
    ))

    conf_by_jid_tableIndexDataType = t.add_parameter(Parameter(
        "ConferencesByJidPrimaryKeyDataType",
        Description=" Table: Primary Key Data Type",
        Type="String",
        Default="S",
        AllowedPattern="[S|N|B]",
        MinLength="1",
        MaxLength="1",
        ConstraintDescription="S for string data, N for numeric data, or B for "
                            "binary data"
    ))

    conf_info_by_jid_tableIndexName = t.add_parameter(Parameter(
        "ConferencesInfoByJidPrimaryKey",
        Description="Table: Primary Key Field",
        Type="String",
        Default="conference",
        AllowedPattern="[a-zA-Z0-9]*",
        MinLength="1",
        MaxLength="2048",
        ConstraintDescription="must contain only alphanumberic characters"
    ))

    conf_info_by_jid_tableIndexDataType = t.add_parameter(Parameter(
        "ConferencesInfoByJidPrimaryKeyDataType",
        Description=" Table: Primary Key Data Type",
        Type="String",
        Default="S",
        AllowedPattern="[S|N|B]",
        MinLength="1",
        MaxLength="1",
        ConstraintDescription="S for string data, N for numeric data, or B for "
                            "binary data"
    ))

    global_secondaryIndexHashName = t.add_parameter(Parameter(
        "ConferencesByJidPrimaryGSI",
        Description="Global Secondary Index: Primary Key Field",
        Type="String",
        Default="id",
        AllowedPattern="[a-zA-Z0-9]*",
        MinLength="1",
        MaxLength="2048",
        ConstraintDescription="must contain only alphanumberic characters"
    ))

    global_secondaryIndexHashDataType = t.add_parameter(Parameter(
        "ConferencesByJidPrimaryGSIDataType",
        Description="Global Secondary Index: Primary Key Data Type",
        Type="String",
        Default="N",
        AllowedPattern="[S|N|B]",
        MinLength="1",
        MaxLength="1",
        ConstraintDescription="S for string data, N for numeric data, or B for "
                            "binary data"
    ))


def add_dynamo_db_as_params(t):

    write_as_info_conf_by_jid_min_capacity = t.add_parameter(Parameter(
        "WriteAsInfoConferencesByJidMinCapacity",
        Description="AS write min capacity",
        Type="Number",
        Default="8"
    ))

    write_as_info_conf_by_jid_max_capacity = t.add_parameter(Parameter(
        "WriteAsInfoConferencesByJidMaxCapacity",
        Description="AS write max capacity",
        Type="Number",
        Default="40000"
    ))

    read_as_info_conf_by_jid_min_capacity = t.add_parameter(Parameter(
        "ReadAsInfoConferencesByJidMinCapacity",
        Description="AS read min capacity",
        Type="Number",
        Default="5"
    ))

    read_as_info_conf_by_jid_max_capacity = t.add_parameter(Parameter(
        "ReadAsInfoConferencesByJidMaxCapacity",
        Description="AS read max capacity",
        Type="Number",
        Default="40000"
    ))


def add_dynamo_db(t):
    
    add_dynamo_db_resource = t.add_resource(Table(
        "CreateTableConferencesByJid",
        TableName="conferences_by_jid",
        AttributeDefinitions=[
            AttributeDefinition(
                AttributeName=Ref("ConferencesByJidPrimaryKey"),
                AttributeType=Ref("ConferencesByJidPrimaryKeyDataType")
            ),
            AttributeDefinition(
                AttributeName=Ref("ConferencesByJidPrimaryGSI"),
                AttributeType=Ref("ConferencesByJidPrimaryGSIDataType")
            ),
            AttributeDefinition(
                AttributeName="expires",
                AttributeType="N"
            ),
        ],
        KeySchema=[
            KeySchema(
                AttributeName=Ref("ConferencesByJidPrimaryKey"),
                KeyType="HASH"
            )
        ],
        ProvisionedThroughput=ProvisionedThroughput(
            ReadCapacityUnits=Ref("ConferencesByJidReadCapacityUnits"),
            WriteCapacityUnits=Ref("ConferencesByJidWriteCapacityUnits")
        ),
        TimeToLiveSpecification=TimeToLiveSpecification(
            AttributeName="expires",
            Enabled=True
        ),
         GlobalSecondaryIndexes=[
            GlobalSecondaryIndex(
                IndexName="id-index",
                KeySchema=[
                    KeySchema(
                        AttributeName=Ref("ConferencesByJidPrimaryGSI"),
                        KeyType="HASH"
                    )
                ],
                Projection=Projection(ProjectionType="ALL"),
                ProvisionedThroughput=ProvisionedThroughput(
                    ReadCapacityUnits=Ref("ConferencesByJidReadCapacityUnits"),
                    WriteCapacityUnits=Ref("ConferencesByJidWriteCapacityUnits")
                )
            )
        ]
    ))


    add_dynamo_db_resource = t.add_resource(Table(
        "CreateTableInfoConferencesByJid",
        TableName="conferences_info_by_jid",
        AttributeDefinitions=[
            AttributeDefinition(
                AttributeName=Ref("ConferencesInfoByJidPrimaryKey"),
                AttributeType=Ref("ConferencesInfoByJidPrimaryKeyDataType")
            ),
            AttributeDefinition(
                AttributeName="domain",
                AttributeType="S"
            ),
            AttributeDefinition(
                AttributeName="expire",
                AttributeType="N"
            ),
            AttributeDefinition(
                AttributeName="group",
                AttributeType="B"
            ),
            AttributeDefinition(
                AttributeName="latestEvent",
                AttributeType="N"
            ),
            AttributeDefinition(
                AttributeName="room",
                AttributeType="S"
            ),
            AttributeDefinition(
                AttributeName="tenant",
                AttributeType="B"
            ),
            AttributeDefinition(
                AttributeName="url",
                AttributeType="S"
            ),
        ],
        KeySchema=[
            KeySchema(
                AttributeName=Ref("ConferencesInfoByJidPrimaryKey"),
                KeyType="HASH"
            )
        ],
        ProvisionedThroughput=ProvisionedThroughput(
            ReadCapacityUnits=Ref("ConferencesInfoByJidReadCapacityUnits"),
            WriteCapacityUnits=Ref("ConferencesInfoByJidWriteCapacityUnits")
        ),
        TimeToLiveSpecification=TimeToLiveSpecification(
            AttributeName="expire",
            Enabled=True
        )
    ))

    add_write_capacity_scalable_target = t.add_resource(ScalableTarget(
        "WriteCapacityScalableTarget",
        MaxCapacity=Ref("WriteAsInfoConferencesByJidMaxCapacity"),
        MinCapacity=Ref("WriteAsInfoConferencesByJidMinCapacity"),
        ResourceId=Join("/",["table", Ref("CreateTableInfoConferencesByJid")]),
        RoleARN=GetAtt("DynamoDBAutoscaleRole", "Arn"),
        ScalableDimension="dynamodb:table:WriteCapacityUnits",
        ServiceNamespace="dynamodb"
    ))

    add_read_capacity_scalable_target = t.add_resource(ScalableTarget(
        "ReadCapacityScalableTarget",
        MaxCapacity=Ref("ReadAsInfoConferencesByJidMaxCapacity"),
        MinCapacity=Ref("ReadAsInfoConferencesByJidMinCapacity"),
                ResourceId=Join("/",["table", Ref("CreateTableInfoConferencesByJid")]),
        RoleARN=GetAtt("DynamoDBAutoscaleRole", "Arn"),
        ScalableDimension="dynamodb:table:ReadCapacityUnits",
        ServiceNamespace="dynamodb"
    ))

    add_write_scaling_policy = t.add_resource(applicationautoscaling.ScalingPolicy(
        "WriteScalingPolicy",
        PolicyName="WriteAutoScalingPolicy",
        PolicyType="TargetTrackingScaling",
        ScalingTargetId=Ref("WriteCapacityScalableTarget"),
        TargetTrackingScalingPolicyConfiguration=TargetTrackingScalingPolicyConfiguration(
            TargetValue=70.0
        )
    ))

    add_read_scaling_policy = t.add_resource(applicationautoscaling.ScalingPolicy(
        "ReadScalingPolicy",
        PolicyName="ReadAutoScalingPolicy",
        PolicyType="TargetTrackingScaling",
        ScalingTargetId=Ref("ReadCapacityScalableTarget"),
        TargetTrackingScalingPolicyConfiguration=TargetTrackingScalingPolicyConfiguration(
            TargetValue=70.0
        )
    ))


def add_dynamo_db_scaling_role(t):
    add_dynamo_db_scaling_role = t.add_resource(iam.Role(
        "DynamoDBAutoscaleRole",
        AssumeRolePolicyDocument=Policy(
            Statement=[
                Statement(
                Effect=Allow,
                Action=[AssumeRole],
                Principal=Principal("Service", ["application-autoscaling.amazonaws.com"])
            )
            ]
        ),
        Path="/",
        Policies=[iam.Policy(
            PolicyName="root",
            PolicyDocument=(Policy(
            Statement=[Statement(
                Effect=Allow,
                Action=[
                    Action("dynamodb", "DescribeTable"),
                    Action("dynamodb", "UpdateTable"),
                    Action("cloudwatch", "PutMetricAlarm"),
                    Action("cloudwatch", "DescribeAlarms"),
                    Action("cloudwatch", "GetMetricStatistics"),
                    Action("cloudwatch", "SetAlarmState"),
                    Action("cloudwatch", "DeleteAlarms")
                ],
                Resource=["*"]
            )]))
        )
        ]
    ))


def dynamo_db_main(t):
    add_dynamo_db_params(t)
    add_dynamo_db_as_params(t)
    add_dynamo_db_scaling_role(t)
    add_dynamo_db(t)
