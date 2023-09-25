#!/usr/bin/env python3
''' helper tool to interact with oracle virtual network client'''

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

def list_vcns(ctx: click.Context):
    '''list VCNs that have been loaded with load_vcns()'''
    if 'OCI_VCNS' not in ctx.obj:
        click.echo("## ERROR: no VCNs in context, load_vcns() first")
        sys.exit(1)
    for region in ctx.obj['OCI_VCNS']:
        for vcn in ctx.obj['OCI_VCNS'][region]:
            pprint.pprint(vcn)

def load_security_lists(ctx: click.Context) -> bool:
    '''load security lists to 'SECURITY_LISTS' in the context in an environment based SECLIST_FILTER'''
    found_seclists = False
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
                found_seclists=True
                if ctx.obj['DEBUG']:
                    click.echo(f"## DEBUG: adding security list {seclist.display_name}")
                if region not in ctx.obj['SECURITY_LISTS']:
                    ctx.obj['SECURITY_LISTS'][region] = [seclist]
                else:
                    ctx.obj['SECURITY_LISTS'][region].append(seclist)

    if ctx.obj['DEBUG']:
        click.echo(f"## DEBUG: loaded security_lists:\n{ctx.obj['SECURITY_LISTS']}")

    return found_seclists

def print_security_lists(ctx: click.Context):
    '''pretty print summary info for loaded security lists'''
    for region in ctx.obj['SECURITY_LISTS'].keys():
        if len(ctx.obj['SECURITY_LISTS'][region]) < 1:
            continue
        for seclist in ctx.obj['SECURITY_LISTS'][region]:
            if ctx.obj['SECLIST_SSH_FLAG']:
                print(f"ssh audit for {seclist.display_name} in {region} -- {seclist.id}")
                for rule in seclist.ingress_security_rules:
                    if rule.tcp_options and rule.tcp_options.destination_port_range and rule.tcp_options.destination_port_range.max == 22:
                        print(f"{rule.description} has source {rule.source}")
                print("")
            else:
                pprint.pprint(seclist)

def load_network_security_groups(ctx: click.Context) -> bool:
    '''load network security groups to 'NETWORK_SECURITY_GROUPS' in the context in an environment based NSG_FILTER'''
    found_seclists = False
    if ctx.obj['DEBUG']:
        click.echo("## DEBUG: entering load_security_lists")
        if 'NSG_FILTER' in ctx.obj:
            click.echo(f"## DEBUG: filtering on {ctx.obj['NSG_FILTER']}")
    if 'OCI_VCNS' not in ctx.obj:
        click.echo("## ERROR: no VCNs in context, load_vcns() first")
        sys.exit(1)

    ctx.obj['NETWORK_SECURITY_GROUPS'] = {}
    for region in ctx.obj['OCI_VN_CLIENT'].keys():
        vn_client = ctx.obj['OCI_VN_CLIENT'][region]
        for vcn in ctx.obj['OCI_VCNS'][region]:
            vcn_nsgs = vn_client.list_network_security_groups(
                compartment_id=ctx.obj['COMPARTMENT'].id,
                vcn_id=vcn.id
            ).data
            for nsg in vcn_nsgs:
                if 'NSG_FILTER' in ctx.obj:
                    if ctx.obj['NSG_FILTER'] not in nsg.display_name:
                        if ctx.obj['DEBUG']:
                            click.echo(f"## DEBUG: skipping {nsg.display_name} since filter did not match")
                        continue
                found_nsgs=True
                if ctx.obj['DEBUG']:
                    click.echo(f"## DEBUG: adding security list {nsg.display_name}")
                if region not in ctx.obj['NETWORK_SECURITY_GROUPS']:
                    ctx.obj['NETWORK_SECURITY_GROUPS'][region] = [nsg]
                else:
                    ctx.obj['NETWORK_SECURITY_GROUPS'][region].append(nsg)
                if ctx.obj['NETWORK_SECURITY_GROUP_RULES_FLAG']:
                    nsgr = vn_client.list_network_security_group_security_rules(network_security_group_id=nsg.id).data
                    ctx.obj['NETWORK_SECURITY_GROUP_RULES'][nsg.id] = nsgr


    if ctx.obj['DEBUG']:
        click.echo(f"## DEBUG: loaded network_security_groups:\n{ctx.obj['NETWORK_SECURITY_GROUPS']}")

    return found_nsgs

def print_network_security_groups(ctx: click.Context):
    '''pretty print summary info for loaded network security groups'''
    for region in ctx.obj['NETWORK_SECURITY_GROUPS'].keys():
        if len(ctx.obj['NETWORK_SECURITY_GROUPS'][region]) < 1:
            continue
        for nsg in ctx.obj['NETWORK_SECURITY_GROUPS'][region]:
            print(f"-=- {nsg.id} -=-")
            if ctx.obj['NETWORK_SECURITY_GROUP_SSH_FLAG']:
                print(f"ssh audit for {nsg.display_name}")
            else:
                pprint.pprint(nsg)
            if ctx.obj['NETWORK_SECURITY_GROUP_RULES_FLAG']:
                for ruleset in ctx.obj['NETWORK_SECURITY_GROUP_RULES'][nsg.id]:
                    if ctx.obj['NETWORK_SECURITY_GROUP_SSH_FLAG']:
                        if ruleset.tcp_options and ruleset.tcp_options.destination_port_range and ruleset.tcp_options.destination_port_range.max == 22:
                            print(f"{ruleset.description}, source: {ruleset.source}")
                    else:
                        pprint.pprint(ruleset)
            print("")

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

def load_subnets(ctx: click.Context) -> bool:
    '''
    load subnets to 'OCI_SUBNETS' in the context in an environment based on
    SUBNET_FILTER if it exists, or all subnets if it does not
    '''
    found_subnets = False
    if ctx.obj['DEBUG']:
        click.echo("## DEBUG: entering load_subnets")
    ctx.obj['OCI_SUBNETS'] = {}

    for region in ctx.obj['OCI_VN_CLIENT'].keys():
        ctx.obj['OCI_SUBNETS'][region] = []
        vn_client = ctx.obj['OCI_VN_CLIENT'][region]
        region_subnets = vn_client.list_subnets(compartment_id=ctx.obj['COMPARTMENT'].id,
            retry_strategy=ctx.obj['RETRY_STRATEGY']).data
        for subnet in region_subnets:
            if ctx.obj['SUBNET_FILTER']:
                if ctx.obj['SUBNET_FILTER'] not in subnet.display_name:
                    continue
            found_subnets = True
            ctx.obj['OCI_SUBNETS'][region].append(subnet)

    if ctx.obj['DEBUG']:
        click.echo(f"## DEBUG: loaded subnets:\n{ctx.obj['OCI_SUBNETS']}")

    return found_subnets

def list_subnets(ctx: click.Context):
    '''lists subnets in 'OCI_SUBNETS' '''
    if ctx.obj['DEBUG']:
        click.echo("## DEBUG: entering list_subnets")
    for region in ctx.obj['OCI_SUBNETS']:
        for subnet in ctx.obj['OCI_SUBNETS'][region]:
            pprint.pprint(subnet)

def add_seclists_to_subnets(ctx: click.Context):
    '''add ctx SECURITY_LISTS to ctx OCI_SUBNETS'''
    click.echo(f"## adding security lists matching filter {ctx.obj['SECLIST_FILTER']} to subnets matching filter {ctx.obj['SUBNET_FILTER']}")
    for region in ctx.obj['OCI_SUBNETS'].keys():
        seclist_ids_to_add = [seclist.id for seclist in ctx.obj['SECURITY_LISTS'][region]]
        for subnet in ctx.obj['OCI_SUBNETS'][region]:
            new_ids=False
            for id in seclist_ids_to_add:
                if id not in subnet.security_list_ids:
                    new_ids=True
            if new_ids:
                new_seclist_ids = list(set(subnet.security_list_ids + seclist_ids_to_add))
                click.echo(f"## changing seclists for subnet {subnet.display_name}:\n### old: {subnet.security_list_ids}\n### new: {new_seclist_ids}")
                ctx.obj['OCI_VN_CLIENT'][region].update_subnet(
                    subnet_id=subnet.id,
                    update_subnet_details=oci.core.models.UpdateSubnetDetails(security_list_ids=new_seclist_ids)
                )
            else:
                click.echo(f"## no update needed for subnet {subnet.display_name} in region {region}")

def remove_seclists_from_subnets(ctx: click.Context):
    '''remove ctx SECURITY_LISTS from ctx OCI_SUBNETS'''
    click.echo(f"## removing security lists matching filter {ctx.obj['SECLIST_FILTER']} from subnets matching filter {ctx.obj['SUBNET_FILTER']}")
    for region in ctx.obj['OCI_SUBNETS'].keys():
        seclist_ids_to_rm = [seclist.id for seclist in ctx.obj['SECURITY_LISTS'][region]]
        for subnet in ctx.obj['OCI_SUBNETS'][region]:
            new_seclist_ids = [id for id in subnet.security_list_ids]
            for id in seclist_ids_to_rm:
                if id in new_seclist_ids:
                    new_seclist_ids.remove(id)
            if set(new_seclist_ids) != set(subnet.security_list_ids):
                click.echo(f"## changing seclists for subnet {subnet.display_name}:\n### old: {subnet.security_list_ids}\n### new: {new_seclist_ids}")
                ctx.obj['OCI_VN_CLIENT'][region].update_subnet(
                    subnet_id=subnet.id,
                    update_subnet_details=oci.core.models.UpdateSubnetDetails(
                        security_list_ids=new_seclist_ids
                    )
                )
            else:
                click.echo(f"## no change needed for subnet {subnet.display_name} in region {region}")
            
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
@click.option('--seclist_filter', envvar=['SECLIST_FILTER'], default=None, help='string to filter security lists against')
@click.option('--audit_ssh', is_flag=True, default=False, help='audit ssh ingress')
@click.pass_context
def list_seclist_cmd(ctx: click.Context, seclist_filter: str, audit_ssh: bool):
    '''list security lists'''
    if ctx.obj['DEBUG']:
        click.echo("## DEBUG: loading security lists")
    if seclist_filter:
        ctx.obj['SECLIST_FILTER'] = seclist_filter
    ctx.obj['SECLIST_SSH_FLAG'] = audit_ssh

    load_security_lists(ctx)
    print_security_lists(ctx)

@cli.command('add_seclist_ingress_rule', short_help='add a security list rule')
@click.option('--seclist_filter', envvar=['SECLIST_FILTER'], default=None, help='string to filter security lists against')
@click.option('--description', default="", help="description of the rule")
@click.option('--dest_port', default=None, help="port the traffic is going to, defaults to all")
@click.option('--protocol', required=True, type=click.Choice(['TCP', 'UDP'], case_sensitive=False), help="protocol for rule")
@click.option('--source', required=True, help="source of traffic")
@click.option('--source_type', default="CIDR_BLOCK", help="type of source")
@click.option('--source_port', default=None, help="port the traffic is coming from, defaults to all")
@click.option('--stateless', is_flag=True, help="is the protocol in use stateless")
@click.pass_context
def add_seclist_ingress_rule_cmd(ctx: click.Context, seclist_filter: str, description: str, source: str, source_type: str, protocol: str, dest_port: int, source_port: int, stateless: bool):
    '''add ingress rule to security list'''
    if ctx.obj['DEBUG']:
        click.echo("## starting add_seclist_ingress_rule")
    if seclist_filter:
        ctx.obj['SECLIST_FILTER'] = seclist_filter

    if dest_port:
        dest_port = int(dest_port)
    if source_port:
        source_port = int(source_port)

    load_security_lists(ctx)
    ingress_security_rule = build_ingress_security_rule(description, source, source_type, protocol, dest_port, source_port, stateless)
    add_ingress_rule_to_security_lists(ctx, ingress_security_rule)

@cli.command('list_vcns', short_help='list vcns for an environment')
@click.pass_context
def list_vcns_cmd(ctx: click.Context):
    '''list vcns'''
    if ctx.obj['DEBUG']:
        click.echo(f"## VCNs for environment {ctx.obj['ENVIRONMENT']}")

    list_vcns(ctx)

@cli.command('list_subnets', short_help='list vcns for an environment')
@click.option('--subnet_filter', envvar=['SUBNET_FILTER'], help='subnets that match this filter will get the security lists')
@click.pass_context
def list_vcns_cmd(ctx: click.Context, subnet_filter: str):
    '''list subnets which can be filtered by --subnet-filter'''
    if ctx.obj['DEBUG']:
        click.echo(f"## subnets for environment {ctx.obj['ENVIRONMENT']}")

    ctx.obj['SUBNET_FILTER'] = subnet_filter      # e.g., "Public1"
    load_subnets(ctx)  # subnet_filter is applied when this loads
    list_subnets(ctx)

@cli.command('update_subnet_seclists', short_help='add security lists matching a suffix to all subnets matching a a suffix for all vcns in an environment')
@click.option('--seclist_filter', envvar=['SECLIST_FILTER'], required=True, help='security lists that match this filter will be applied to the subets')
@click.option('--subnet_filter', envvar=['SUBNET_FILTER'], required=True, help='subnets that match this filter will get the security lists')
@click.option('--add', is_flag=True, default=False, help='add security lists')
@click.option('--remove', is_flag=True, default=False, help='remove security lists')
@click.pass_context
def update_subnet_seclists_cmd(ctx: click.Context, seclist_filter: str, subnet_filter: str, add: bool, remove: bool):
    click.echo("# starting update_subnet_seclists")

    if (add and remove) or (not add and not remove):
        click.echo("## ERROR: set one of either --add or --remove")
        sys.exit(1)

    ctx.obj['SUBNET_FILTER'] = subnet_filter      # e.g., "PublicSubnet1"
    ctx.obj['SECLIST_FILTER'] = seclist_filter    # e.g., "PrivateSecurityList"

    found_subnets = load_subnets(ctx)               # subnet_filter is applied when this loads
    if not found_subnets:
        click.echo(f"## exiting, no subnets found that match {subnet_filter}")
        sys.exit(0)

    found_seclists = load_security_lists(ctx)        # seclist_filter is applied when this loads
    if not found_seclists:
        click.echo("## exiting, no security lists found that match {seclist_filter}")
        sys.exit(0)

    if add:
        add_seclists_to_subnets(ctx)
    else:
        remove_seclists_from_subnets(ctx)

@cli.command('list_security_groups', short_help='list network security groups')
@click.option('--nsg_filter', envvar=['NSG_FILTER'], default=None, help='string to filter network security group names against')
@click.option('--rules', is_flag=True, default=False, help='also show the rules in each group')
@click.option('--audit_ssh', is_flag=True, default=False, help='audit ssh ingress')
@click.pass_context
def list_seclist_cmd(ctx: click.Context, nsg_filter: str, rules: bool, audit_ssh: bool):
    '''list security lists'''
    if ctx.obj['DEBUG']:
        click.echo("## DEBUG: loading network security groups")
    ctx.obj['NETWORK_SECURITY_GROUP_FILTER'] = nsg_filter
    ctx.obj['NETWORK_SECURITY_GROUP_RULES_FLAG'] = rules
    if rules:
        ctx.obj['NETWORK_SECURITY_GROUP_RULES'] = {}
    ctx.obj['NETWORK_SECURITY_GROUP_SSH_FLAG'] = audit_ssh

    load_network_security_groups(ctx)
    print_network_security_groups(ctx)

if __name__ == '__main__':
    cli()
