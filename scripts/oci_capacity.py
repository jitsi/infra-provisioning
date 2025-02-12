#!/usr/bin/env python3
''' helper tool to interact with oracle compute client'''

import sys
import pprint
import copy
import click
import oci
import hcvlib

def init_click_context(ctx: click.Context, environment: str, debug: bool):
    '''
    initialize the context object
    \b
    ctx.obj['OCI_CC_CLIENT']   OCI ComputeClient clients per region (dict)
    ctx.obj['ENVIRONMENT']     jitsi environment
    '''
    ctx.ensure_object(dict)
    ctx.obj['OCI_ID_CLIENT'] = {}  # OCI IdentityClient clients per region (dict)
    ctx.obj['OCI_CC_CLIENT'] = {}  # OCI ComputeClient clients per region (dict)
    ctx.obj['ENVIRONMENT'] = environment
    ctx.obj['DEBUG'] = debug

    if ctx.obj['DEBUG']:
        click.echo("## DEBUG: init oracle config")
    oci_config = oci.config.from_file()

    if ctx.obj['DEBUG']:
        click.echo("## DEBUG: create a retry strategy for oracle calls")
    checker_container=oci.retry.retry_checkers.RetryCheckerContainer(checkers=[oci.retry.retry_checkers.TimeoutConnectionAndServiceErrorRetryChecker()])
    ctx.obj['RETRY_STRATEGY'] = oci.retry.retry.ExponentialBackOffWithDecorrelatedJitterRetryStrategy(
        base_sleep_time_seconds=20,
        exponent_growth_factor=2,
        max_wait_between_calls_seconds=180,
        checker_container=checker_container)

    if ctx.obj['DEBUG']:
        click.echo("## create an oracle IdentityClient")
    ctx.obj['COMPARTMENT'] = hcvlib.get_oracle_compartment_by_environment(ctx.obj['ENVIRONMENT'])
    for region in hcvlib.oracle_regions_by_environment(ctx.obj['ENVIRONMENT']):
      id_client = oci.identity.IdentityClient(oci_config)
      id_client.base_client.set_region(region)
      ctx.obj['OCI_ID_CLIENT'][region] = id_client
    
    if ctx.obj['DEBUG']:
        click.echo("## DEBUG: create an oracle ComputeClient for each region in OCI")
    for region in hcvlib.oracle_regions_by_environment(ctx.obj['ENVIRONMENT']):
        cc_client = oci.core.ComputeClient(oci_config)
        cc_client.base_client.set_region(region)
        ctx.obj['OCI_CC_CLIENT'][region] = cc_client

def load_availability_domains(ctx: click.Context):
    '''load ADs to 'OCI_ADS' '''
    if ctx.obj['DEBUG']:
        click.echo("## DEBUG: entering load_ads")
    ctx.obj['OCI_ADS'] = {}

    for region in ctx.obj['OCI_ID_CLIENT'].keys():
        id_client = ctx.obj['OCI_ID_CLIENT'][region]
        ctx.obj['OCI_ADS'][region] = id_client.list_availability_domains(compartment_id=ctx.obj['COMPARTMENT'].id,
            retry_strategy=ctx.obj['RETRY_STRATEGY']).data

def print_availability_domains(ctx: click.Context):
    '''pretty print summary info for availability domains'''

    if ctx.obj['DEBUG']:
        click.echo("## DEBUG: entering print_ads")

    for region in ctx.obj['OCI_ADS'].keys():
        if len(ctx.obj['OCI_ADS'][region]) < 1:
            continue
        for adlist in ctx.obj['OCI_ADS'][region]:
            pprint.pprint(adlist)

def print_compute_capacity(ctx: click.Context):
    '''pretty print summary info for availability domains'''

    if ctx.obj['DEBUG']:
        click.echo("## DEBUG: entering print_ccs")

    capacity_report = {}
    
    A1_Shape_config = oci.core.models.CapacityReportInstanceShapeConfig(memory_in_gbs=24, ocpus=4)
    A1_Shape = oci.core.models.CreateCapacityReportShapeAvailabilityDetails(instance_shape='VM.Standard.A1.Flex',instance_shape_config=A1_Shape_config)

    for region in ctx.obj['OCI_ADS'].keys():
        if len(ctx.obj['OCI_ADS'][region]) < 1:
            continue
        for adlist in ctx.obj['OCI_ADS'][region]:
            ccr_details = oci.core.models.CreateComputeCapacityReportDetails(availability_domain=adlist.name,
                compartment_id=ctx.obj['COMPARTMENT'].id ,shape_availabilities=[A1_Shape])
            capacity_report[region] = ctx.obj['OCI_CC_CLIENT'][region].create_compute_capacity_report(create_compute_capacity_report_details=ccr_details,
                retry_strategy=ctx.obj['RETRY_STRATEGY']).data
            pprint.pprint(capacity_report[region])

@click.group(invoke_without_command=False, context_settings=dict(max_content_width=120))
@click.option('--environment', required=True, envvar=['ENVIRONMENT', 'HCV_ENVIRONMENT'], help='jitsi environment')
@click.option('--debug', '-d', envvar=['DEBUG'], is_flag=True, default=False, help='debug mode')
@click.pass_context
def cli(ctx: click.Context, environment: str, debug: bool):
    '''helper tool to interact with oci compute client'''
    if debug:
        click.echo("# starting oci_compute.py")
        click.echo("## DEBUG: init context")
    init_click_context(ctx, environment, debug)
    #if ctx.obj['DEBUG']:
    #    click.echo("## DEBUG: loading vcns")
    #load_vcns(ctx)

@cli.command('list_availability_domains', short_help='list availability domains')
@click.pass_context
def list_ads_cmd(ctx: click.Context):
    '''list availability domains'''
    if ctx.obj['DEBUG']:
        click.echo("## DEBUG: loading availability domains")

    load_availability_domains(ctx)
    print_availability_domains(ctx)

@cli.command('list_compute_capacity', short_help='list compute capacity across availability domains')
@click.pass_context
def list_ads_cmd(ctx: click.Context):
    '''list compute capacity'''
    if ctx.obj['DEBUG']:
        click.echo("## DEBUG: loading availability domains")
    load_availability_domains(ctx)
    print_compute_capacity(ctx)

if __name__ == '__main__':
    cli()
