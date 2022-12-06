#!/usr/bin/env python

from templatelib import *
from troposphere.kinesis import *


def add_kinesis_params(t):

   kinesis_sream_name = t.add_parameter(Parameter(
       "KinesisStreamName",
       Description="Kinesis stream name",
       Type="String",
       Default="conference-events"
   ))

   kinesis_retention_period = t.add_parameter(Parameter(
       "KinesisRetentionPeriod",
       Description="Kinesis retention period",
       Type="Number",
       Default="24"
   ))

   kinesis_shard_count = t.add_parameter(Parameter(
       "KinesisShardCount",
       Description="Kinesis shard count",
       Type="Number",
       Default="2"
   ))


def add_kinesis(t):

    add_kinesis = t.add_resource(Stream(
        "CreateKinesisStream",
        Name=Ref("KinesisStreamName"),
        RetentionPeriodHours=Ref("KinesisRetentionPeriod"),
        ShardCount=Ref("KinesisShardCount")
    ))


def kinesis_main(t):
    add_kinesis_params(t)
    add_kinesis(t)
