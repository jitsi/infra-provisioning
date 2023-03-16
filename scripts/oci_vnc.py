#!/usr/bin/env python3
''' helper tool to interact with oracle virtual network client'''

import sys
import json
from typing import Tuple
import time
import concurrent
from concurrent.futures import ThreadPoolExecutor
import pprint
import click
import oci
import hcvlib

def init_click_context(ctx: click.Context, environment: str, debug: bool):
    '''
    initialize the context object
    \b
    ctx.obj['OCI_VN_CLIENT']   OCI VirtualNetwork clients per region (dict)
    ctx.obj['ENVIRONMENT']     jitsi environment
    '''
    ctx.ensure_object(dict)
    ctx.obj['OCI_VN_CLIENT'] = {}
    ctx.obj['ENVIRONMENT'] = environment
    ctx.obj['DEBUG'] = debug

    if ctx.obj['DEBUG']:
        click.echo("## DEBUG: create an oracle VirtualNetworkClient for each region in OCI")
    oci_config = oci.config.from_file()

    ctx.obj['COMPARTMENT'] = hcvlib.get_oracle_compartment_by_environment(ctx.obj['ENVIRONMENT'])
    for region in hcvlib.oracle_regions_by_environment(ctx.obj['ENVIRONMENT']):
        vn_client = oci.core.VirtualNetworkClient(oci_config)
        vn_client.base_client.set_region(region)
        ctx.obj['OCI_VN_CLIENT'][region] = vn_client

    if ctx.obj['DEBUG']:
        click.echo("## DEBUG: create a retry strategy for oracle calls to prevent fails during SCALING")
    checker_container=oci.retry.retry_checkers.RetryCheckerContainer(checkers=[oci.retry.retry_checkers.TimeoutConnectionAndServiceErrorRetryChecker()])
    ctx.obj['RETRY_STRATEGY'] = oci.retry.retry.ExponentialBackOffWithDecorrelatedJitterRetryStrategy(
        base_sleep_time_seconds=20,
        exponent_growth_factor=2,
        max_wait_between_calls_seconds=180,
        checker_container=checker_container
    )

def load_vcns(ctx: click.Context):
    '''load VCNs to 'OCI_VCNS' in the context in an environment based on filters'''
    if ctx.obj['DEBUG']:
        click.echo("## DEBUG: entering load_vcns")
    ctx.obj['OCI_VCNS'] = {}

    for region in ctx.obj['OCI_VN_CLIENT'].keys():
        vn_client = ctx.obj['OCI_VN_CLIENT'][region]
        ctx.obj['OCI_VCNS'][region] = vn_client.list_vcns(compartment_id=ctx.obj['COMPARTMENT'].id,
            retry_strategy=ctx.obj['RETRY_STRATEGY']).data

def load_security_lists(ctx: click.Context):
    '''load security lists to 'SECURITY_LISTS' in the context in an environment based on filters'''
    if ctx.obj['DEBUG']:
        click.echo("## DEBUG: entering load_security_lists")
        if 'SECLIST_FILTER' in ctx.obj:
            click.echo(f"## DEBUG: filtering on {ctx.obj['SECLIST_FILTER']}")
    if 'OCI_VCNS' not in ctx.obj:
        click.echo("## ERROR: no VCNs in context, load_vcns() first")
        sys.exit(1)

    ctx.obj['SECURITY_LISTS'] = {}
    for region in ctx.obj['OCI_VN_CLIENT'].keys():
        vn_client = ctx.obj['OCI_VN_CLIENT'][region]
        for vcn in ctx.obj['OCI_VCNS'][region]:
            vcn_seclists = vn_client.list_security_lists(
                compartment_id=ctx.obj['COMPARTMENT'].id,
                vcn_id=vcn.id
            ).data
            for seclist in vcn_seclists:
                if 'SECLIST_FILTER' in ctx.obj:
                    if ctx.obj['SECLIST_FILTER'] not in seclist.display_name:
                        if ctx.obj['DEBUG']:
                            click.echo(f"## DEBUG: skipping {seclist.display_name} since filter did not match")
                        continue
                if ctx.obj['DEBUG']:
                    click.echo(f"## DEBUG: adding security list {seclist.display_name}")
                if region not in ctx.obj['SECURITY_LISTS']:
                    ctx.obj['SECURITY_LISTS'][region] = [seclist]
                else:
                    ctx.obj['SECURITY_LISTS'][region].append(seclist)

def print_security_lists(ctx: click.Context):
    '''pretty print summary info for loaded security lists'''
    for region in ctx.obj['SECURITY_LISTS'].keys():
        if len(ctx.obj['SECURITY_LISTS'][region]) < 1:
            continue
        for seclist in ctx.obj['SECURITY_LISTS'][region]:
            pprint.pprint(seclist)

def build_ingress_security_rule(description: str, source: str, source_type: str, protocol: str, dest_port: int, source_port: int, stateless: bool) -> oci.core.models.IngressSecurityRule:
    '''builds a simple ingress security rule'''
    if dest_port:
        dest_port_range = oci.core.models.PortRange(
            max=dest_port,
            min=dest_port
        )
    else:
        dest_port_range=None

    if source_port:
        source_port_range = oci.core.models.PortRange(
            max=source_port,
            min=source_port
        )
    else:
        source_port_range=None

    if protocol == "TCP":
        ingress_rule = oci.core.models.IngressSecurityRule(
            description=description,
            protocol="6",
            source=source,
            source_type=source_type,
            is_stateless=stateless,
            tcp_options=oci.core.models.TcpOptions(
                destination_port_range=dest_port_range,
                source_port_range=source_port_range
            )
        )
    elif protocol == "UDP":
        ingress_rule = oci.core.models.IngressSecurityRule(
            description=description,
            protocol="17",
            source=source,
            source_type=source_type,
            is_stateless=stateless,
            tcp_options=oci.core.models.UdpOptions(
                destination_port_range=dest_port_range,
                source_port_range=source_port_range
            )
        )
    return ingress_rule

def add_ingress_rule_to_security_lists(ctx: click.Context, new_ingress_rule: oci.core.models.IngressSecurityRule):
    '''add a rule to the ingress security lists'''
    click.echo(f"## adding new rule to security lists:\n{new_ingress_rule}")
    for region in ctx.obj['SECURITY_LISTS'].keys():
        if len(ctx.obj['SECURITY_LISTS'][region]) < 1:
            if ctx.obj['DEBUG']:
                click.echo(f"## DEBUG: skipping add_rule in {region} because there are no existing security lists")
            continue
        for seclist in ctx.obj['SECURITY_LISTS'][region]:
            click.echo(f"## updating {region} security list {seclist.display_name}")
            import copy
            new_ingress_security_rules = copy.deepcopy(seclist.ingress_security_rules)
            new_ingress_security_rules.append(new_ingress_rule)
            response = ctx.obj['OCI_VN_CLIENT'][region].update_security_list(
                security_list_id=seclist.id,
                update_security_list_details=oci.core.models.UpdateSecurityListDetails(
                    display_name = seclist.display_name,
                    defined_tags = seclist.defined_tags,
                    freeform_tags = seclist.freeform_tags,
                    egress_security_rules = seclist.egress_security_rules,
                    ingress_security_rules = new_ingress_security_rules,
                )
            )
            if ctx.obj['DEBUG']:
                click.echo(f"## DEBUG: update_security_list response:\n{response.data}")
            
@click.group(invoke_without_command=False, context_settings=dict(max_content_width=120))
@click.option('--environment', required=True, envvar=['ENVIRONMENT', 'HCV_ENVIRONMENT'], help='jitsi environment')
@click.option('--debug', '-d', envvar=['DEBUG'], is_flag=True, default=False, help='debug mode')
@click.pass_context
def cli(ctx: click.Context, environment: str, debug: bool):
    '''helper tool to interact with oci virtual networks across all regions'''
    if debug:
        click.echo("# starting oci_vnc.py")
        click.echo("## DEBUG: init context")
    init_click_context(ctx, environment, debug)
    if ctx.obj['DEBUG']:
        click.echo("## DEBUG: loading vcns")
    load_vcns(ctx)

@cli.command('list_security_lists', short_help='list security lists')
@click.option('--filter', envvar=['SECLIST_FILTER'], default=None, help='string to filter security lists against')
@click.pass_context
def list_seclist_cmd(ctx: click.Context, filter: str):
    '''list security lists'''
    if ctx.obj['DEBUG']:
        click.echo("## DEBUG: loading security lists")
    if filter:
        ctx.obj['SECLIST_FILTER'] = filter

    load_security_lists(ctx)
    print_security_lists(ctx)

@cli.command('add_seclist_ingress_rule', short_help='add a security list rule')
@click.option('--filter', envvar=['SECLIST_FILTER'], default=None, help='string to filter security lists against')
@click.option('--description', default="", help="description of the rule")
@click.option('--dest_port', default=None, help="port the traffic is going to, defaults to all")
@click.option('--protocol', required=True, help="TCP or UDP")
@click.option('--source', required=True, help="source of traffic")
@click.option('--source_type', default="CIDR_BLOCK", help="type of source")
@click.option('--source_port', default=None, help="port the traffic is coming from, defaults to all")
@click.option('--stateless', is_flag=True, help="is the protocol in use stateless")
@click.pass_context
def add_seclist_rule_cmd(ctx: click.Context, filter: str, description: str, source: str, source_type: str, protocol: str, dest_port: int, source_port: int, stateless: bool):
    if ctx.obj['DEBUG']:
        click.echo("## DEBUG: loading security lists")
    if filter:
        ctx.obj['SECLIST_FILTER'] = filter
    
    if not (protocol.upper == "TCP" or protocol.upper != "UDP"):
        click.echo(f"## ERROR: bad protocol {protocol}")
        sys.exit(1)

    if dest_port:
        dest_port = int(dest_port)
    if source_port:
        source_port = int(source_port)

    load_security_lists(ctx)
    ingress_security_rule = build_ingress_security_rule(description, source, source_type, protocol, dest_port, source_port, stateless)
    add_ingress_rule_to_security_lists(ctx, ingress_security_rule)

if __name__ == '__main__':
    cli()
