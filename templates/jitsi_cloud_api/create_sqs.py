#!/usr/bin/env python

from templatelib import *
from troposphere.sqs import Queue,RedrivePolicy


def add_sqs_parameters(t):
    conf_events_delaysec = t.add_parameter(Parameter(
        "ConfEventsDelaySec",
        Default=0,
        Type="Number",
        MaxValue=900,
        MinValue=0,
        ConstraintDescription="Value must be between 0 and 900 seconds"
    ))

    conf_events_deadletter_delaysec = t.add_parameter(Parameter(
        "ConfEventsDeadletterDelaySec",
        Default=0,
        Type="Number",
        MaxValue=900,
        MinValue=0,
        ConstraintDescription="Value must be between 0 and 900 seconds"
    ))

    conf_events_max_mess_size = t.add_parameter(Parameter(
        "ConfEventsMaxMessageSize",
        Default=262144,
        Type="Number",
        MaxValue=262144,
        MinValue=1024,
        ConstraintDescription="Value must be between 1024 and 262144 bytes"
    ))

    conf_events_deadletter_max_mess_size = t.add_parameter(Parameter(
        "ConfEventsDeadletterMaxMessageSize",
        Default=262144,
        Type="Number",
        MaxValue=262144,
        MinValue=1024,
        ConstraintDescription="Value must be between 1024 and 262144 bytes"
    ))

    conf_events_retention_period = t.add_parameter(Parameter(
        "ConfEventsRetentionPeriod",
        Default=345600,
        Type="Number",
        MaxValue=1209600,
        MinValue=60,
        ConstraintDescription="Value must be between 60(1 minute) and 1209600(14 days) seconds"
    ))

    conf_events_deadletter_retention_period = t.add_parameter(Parameter(
        "ConfEventsDeadletterRetentionPeriod",
        Default=345600,
        Type="Number",
        MaxValue=1209600,
        MinValue=60,
        ConstraintDescription="Value must be between 60(1 minute) and 1209600(14 days) seconds"
    ))

    conf_events_wait_time = t.add_parameter(Parameter(
        "ConfEventsWaitTime",
        Default=0,
        Type="Number",
        MaxValue=20,
        MinValue=0,
        ConstraintDescription="Value must be between 0 and 20 seconds"
    ))

    conf_events_deadletter_wait_time= t.add_parameter(Parameter(
        "ConfEventsDeadletterWaitTime",
        Default=0,
        Type="Number",
        MaxValue=20,
        MinValue=0,
        ConstraintDescription="Value must be between 0 and 20 seconds"
    ))

    conf_events_visibility_timeout = t.add_parameter(Parameter(
        "ConfEventsVisibilityTimeout",
        Default=60,
        Type="Number",
        MaxValue=43200,
        MinValue=0,
        ConstraintDescription="Value must be between 0 and 43200 seconds"
    ))

    conf_events_deadletter_visibility_timeout = t.add_parameter(Parameter(
        "ConfEventsDeadletterVisibilityTimeout",
        Default=60,
        Type="Number",
        MaxValue=43200,
        MinValue=0,
        ConstraintDescription="Value must be between 0 and 43200 seconds"
    ))

    conf_events_max_receive_count = t.add_parameter(Parameter(
        "ConfEventsMaxReceiveCount",
        Default=5,
        Type="Number"
    ))


def add_sqs_queues(t):

    add_conf_events_sqs_queue = t.add_resource(Queue(
        "CreateConfEventsQueue",
        DependsOn="CreateConfEventsDeadletterQueue",
        DelaySeconds= Ref("ConfEventsDelaySec"),
        FifoQueue= False,
        MaximumMessageSize= Ref("ConfEventsMaxMessageSize"),
        MessageRetentionPeriod= Ref("ConfEventsRetentionPeriod"),
        QueueName="conference-events",
        ReceiveMessageWaitTimeSeconds= Ref("ConfEventsWaitTime"),
        RedrivePolicy= RedrivePolicy(
            deadLetterTargetArn=GetAtt("CreateConfEventsDeadletterQueue", "Arn"),
            maxReceiveCount=Ref("ConfEventsMaxReceiveCount")
        ),
        VisibilityTimeout= Ref("ConfEventsVisibilityTimeout"),

    ))

    add_conf_events_deadletter_sqs_queue = t.add_resource(Queue(
        "CreateConfEventsDeadletterQueue",
        DelaySeconds=Ref("ConfEventsDeadletterDelaySec"),
        FifoQueue=False,
        MaximumMessageSize=Ref("ConfEventsDeadletterMaxMessageSize"),
        MessageRetentionPeriod=Ref("ConfEventsDeadletterRetentionPeriod"),
        QueueName="conference-events-deadletter",
        ReceiveMessageWaitTimeSeconds=Ref("ConfEventsDeadletterWaitTime"),
        VisibilityTimeout=Ref("ConfEventsDeadletterVisibilityTimeout"),

    ))


def sqs_main(t):
    add_sqs_parameters(t)
    add_sqs_queues(t)
    