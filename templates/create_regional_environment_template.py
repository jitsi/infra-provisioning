#!/usr/bin/env python

# pip install troposphere boto3

from distutils.util import strtobool
from templatelib import *
import troposphere.sns as sns
import argparse


def add_cloudwatch_params(t):


    environment = t.add_parameter(Parameter(
        "Environment",
        Description="Environment name",
        Type="String",
    ))

    asg_alarm_sns = t.add_parameter(Parameter(
        "ASGAlarmSNS",
        Description="SNS topic for environment-specific Autoscaling Group notifications",
        Type="String",
    ))

    health_alarm_sns = t.add_parameter(Parameter(
        "HealthAlarmSNS",
        Description="SNS topic name for environment-specific health failure Alarms",
        Type="String",
    ))


def add_stick_table_alarms(t):


    stick_table_alarm = t.add_resource(Alarm(
        "StickTableAlarm",
        AlarmDescription=Join(" ", ["Stick Table error on",Ref("Environment"),"environment"]),
        AlarmName=Join("-",[Ref("Environment"), "stick-table-error"]),
        ComparisonOperator="GreaterThanThreshold",
        EvaluationPeriods=5,
        MetricName="stick_table_error",
        Namespace="HAProxy",
        Period=60,
        TreatMissingData="missing",
        Statistic="Maximum",
        Unit="Count",
        Threshold="0",
        AlarmActions=[
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("HealthAlarmSNS")])
        ],
        OKActions=[
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("HealthAlarmSNS")])
        ],
        InsufficientDataActions=[
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("HealthAlarmSNS")])
        ],
        Dimensions=[
            MetricDimension(
                Name="Environment",
                Value=Ref("Environment")
            )
        ]
    ))


    split_brain_alarm = t.add_resource(Alarm(
        "SplitBrainAlarm",
        AlarmDescription=Join(" ", ["HAProxy Split Brain: Run Update Load Balancers for", Ref("Environment")]),
        AlarmName=Join("-",["split-brain", Ref("Environment")]),
        ComparisonOperator="GreaterThanThreshold",
        EvaluationPeriods=3,
        MetricName="split_brain_rooms",
        Namespace="HAProxy",
        Period=60,
        TreatMissingData="missing",
        Statistic="Maximum",
        Unit="Count",
        Threshold="0",
        AlarmActions=[
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("HealthAlarmSNS")])
        ],
        OKActions=[
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("HealthAlarmSNS")])
        ],
        InsufficientDataActions=[
            Join(":", ["arn:aws:sns", Ref("AWS::Region"), Ref("AWS::AccountId"), Ref("HealthAlarmSNS")])
        ],
        Dimensions=[
            MetricDimension(
                Name="Environment",
                Value=Ref("Environment")
            )
        ]
    ))


def add_outputs(t):

    t.add_output([
        Output(
            'ASGSNSTopic',
            Description="The ASG SNS Topic ID",
            Value=Ref("ASGSNSTopic"),
        ),
        Output(
            'HealthSNSTopic',
            Description="The Health SNS Topic ID",
            Value=Ref("HealthSNSTopic"),
        )
    ])


def create_regional_environment(filepath, stick_table_alarms=False):


    t = create_template()

    add_cloudwatch_params(t)

    if stick_table_alarms:
        add_stick_table_alarms(t)

    add_health_sns_topic = t.add_resource(sns.Topic(
        "HealthSNSTopic",
        Subscription=[sns.Subscription(
            Endpoint="oncall@jitsi.net",
            Protocol="email"
        )],
        TopicName=Ref("HealthAlarmSNS")
    ))

    add_asg_sns_topic = t.add_resource(sns.Topic(
        "ASGSNSTopic",
        Subscription=[],
        TopicName=Ref("ASGAlarmSNS")
    ))

    add_outputs(t)

    write_template_json(t=t, filepath=filepath)


def main():
    parser = argparse.ArgumentParser(description='Create the AWS CloudWatch stick table alarms template')
    parser.add_argument('--filepath', action='store',
                        help='Path to tenmplate file', required=True)
    parser.add_argument('--stick_table_alarms', action='store', type=strtobool, default=False,
                        help='Enable stick-table and split-brain sns errors', required=True)
    args = parser.parse_args()

    if not args.filepath:
        print ('No path to template file')
        exit(1)

    create_regional_environment(filepath=args.filepath, stick_table_alarms=args.stick_table_alarms)


if __name__ == '__main__':
    main()
