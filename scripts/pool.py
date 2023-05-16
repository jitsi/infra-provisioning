#!/usr/bin/env python3
''' helper tool to interact with jitsi oracle instance pools'''

import sys
from typing import Tuple
import time
import concurrent
from concurrent.futures import ThreadPoolExecutor
import pprint
import click
import oci
import hcvlib

def init_click_context(ctx: click.Context, environment: str, role: str, pool: str, oracle_regions: str, inactive: bool, debug: bool):
    '''
    initialize the context object
    \b
    ctx.obj['OCI_COMP']     OCI Compute client per region (dict)
    ctx.obj['OCI_MGMT']     OCI ComputeManagement clients per region (dict)
    ctx.obj['POOLS']        per region {} containing [{instance_pool/[instance]/role}]
    ctx.obj['ENVIRONMENT']  jitsi environment
    ctx.obj['FILTER']       pool filters
    '''
    ctx.ensure_object(dict)
    ctx.obj['OCI_COMP'] = {}
    ctx.obj['OCI_MGMT'] = {}
    ctx.obj['POOLS'] = {}
    ctx.obj['ENVIRONMENT'] = environment
    ctx.obj['FILTER'] = {}
    ctx.obj['FILTER']['ROLE'] = role
    ctx.obj['FILTER']['POOL'] = pool
    ctx.obj['INACTIVE'] = inactive 
    ctx.obj['DEBUG'] = debug

    if ctx.obj['DEBUG']:
        click.echo("## DEBUG: create an oracle ComputeManagementClient for each region in OCI")
    oci_config = oci.config.from_file()
    if oracle_regions:
        regions = oracle_regions.split(',')
    else:
        regions = hcvlib.oracle_regions()
    for region in regions:
        compute_client = oci.core.ComputeClient(oci_config)
        compute_client.base_client.set_region(region)
        ctx.obj['OCI_COMP'][region] = compute_client
        compute_management_client = oci.core.ComputeManagementClient(oci_config)
        compute_management_client.base_client.set_region(region)
        ctx.obj['OCI_MGMT'][region] = compute_management_client

    if ctx.obj['DEBUG']:
        click.echo("## DEBUG: create a retry strategy for oracle calls to prevent fails during SCALING")
    checker_container=oci.retry.retry_checkers.RetryCheckerContainer(checkers=[oci.retry.retry_checkers.TimeoutConnectionAndServiceErrorRetryChecker()])
    ctx.obj['RETRY_STRATEGY'] = oci.retry.retry.ExponentialBackOffWithDecorrelatedJitterRetryStrategy(
        base_sleep_time_seconds=20,
        exponent_growth_factor=2,
        max_wait_between_calls_seconds=180,
        checker_container=checker_container
    )

def check_pool_state(ctx: click.Context, pool):
    if pool.lifecycle_state not in ('RUNNING', 'SCALING') and not ctx.obj['INACTIVE']:
        if ctx.obj['DEBUG']:
            click.echo(f"## DEBUG: skipped loading an inactive instance pool: {region} {pool.display_name} {pool.lifecycle_state}")
        return False
    if pool.lifecycle_state != 'RUNNING':
        if ctx.obj['DEBUG']:
            click.echo(f"## DEBUG: flagged ALL_POOLS_RUNNING as false")
        ctx.obj['ALL_POOLS_RUNNING'] = False
        return False

    return True

def get_pool_role(pool):
    if 'role' in pool.defined_tags['jitsi']:
        return pool.defined_tags['jitsi']['role']
    elif 'shard-role' in pool.defined_tags['jitsi']:
        return pool.defined_tags['jitsi']['shard-role']
    else:
        return False

def filter_pools(ctx: click.Context, region, pool):
    if 'jitsi' not in pool.defined_tags:
        click.echo(f"## WARN: skipped loading a pool missing the jitsi tag namespace: {region} {pool.display_name}")
        return False
    if 'Name' not in pool.defined_tags['jitsi']:
        click.echo(f"## WARN: skipped loading a pool missing the jitsi.Name tag: {region} {pool.display_name}")
        return False
    pool_role = get_pool_role(pool)
    if not pool_role:
        click.echo(f"## WARN: skipped loading a pool missing jitsi.role and jitsi.shard-role tags: {region} {pool.display_name}")
        return False
    if ctx.obj['FILTER']['ROLE'] and ctx.obj['FILTER']['ROLE'] != pool_role:
        return False

    return True

def load_instance_pools(ctx: click.Context):
    '''load instance pools to 'POOLS' in the context in an environment based on filters'''
    env_compartment = hcvlib.get_oracle_compartment_by_environment(ctx.obj['ENVIRONMENT'])
    ctx.obj['ALL_POOLS_RUNNING'] = True

    skip_filter_pools = False
    for region in ctx.obj['OCI_MGMT'].keys():
        filtered_region_instance_pools = []
        compute_management_client = ctx.obj['OCI_MGMT'][region]
        if (ctx.obj['FILTER']['POOL']):
            pool = compute_management_client.get_instance_pool(ctx.obj['FILTER']['POOL']).data
            region_pools = [pool]
            skip_filter_pools = True
        else:
            region_pools = compute_management_client.list_instance_pools(env_compartment.id).data
        for pool in region_pools:
            if ctx.obj['DEBUG']:
                click.echo(f"## DEBUG: {region} loading pool:")
                pprint.pprint(pool)
            if check_pool_state(ctx, pool) and (skip_filter_pools or filter_pools(ctx, region, pool)):
                if ctx.obj['DEBUG']:
                    click.echo(f"## DEBUG: pool {pool.id} passed checks and filters and added to list for region {region}")
                pool_instances = compute_management_client.list_instance_pool_instances(env_compartment.id, instance_pool_id=pool.id).data
                filtered_region_instance_pools.append({
                    'instance_pool': pool,
                    'instances': pool_instances,
                    'pool_role': get_pool_role(pool),
                })
            else:
                continue

        ctx.obj['POOLS'][region] = filtered_region_instance_pools

def list_instance_pools(ctx: click.Context):
    '''pretty print summary info for loaded instance pools'''
    for region in ctx.obj['POOLS'].keys():
        if len(ctx.obj['POOLS'][region]) < 1:
            continue
        for pool in ctx.obj['POOLS'][region]:
            pprint.pprint({
                'name': pool['instance_pool'].defined_tags['jitsi']['Name'],
                'region': region,
                'size': pool['instance_pool'].size,
                'state': pool['instance_pool'].lifecycle_state,
                'ocid': pool['instance_pool'].id,
                'role': pool['pool_role'],
                'instances': [{'ocid': i.id, 'name': i.display_name, 'time_created': i.time_created} for i in pool['instances']]
            })

def wait_for_running_pools(ctx: click.Context):
    '''check instance pools every 10 seconds and only return once they are all in RUNNING state'''
    click.echo("## waiting for all pools to be running...")
    while True:
        load_instance_pools(ctx)
        if ctx.obj['ALL_POOLS_RUNNING'] == True:
            click.echo("## all instance pools are now RUNNING")
            break
        else:
            click.echo("## some active pools are SCALING, checking again in 10 seconds")
        time.sleep(10)

def double_instance_pools(ctx: click.Context):
    '''double the size of all instance pools in the context via automated scaling'''
    for region in ctx.obj['POOLS'].keys():
        for pool in ctx.obj['POOLS'][region]:
            click.echo(f"## doubling size of pool in {region}: {pool['instance_pool'].defined_tags['jitsi']['Name']}")
            instance_pool_details = oci.core.models.UpdateInstancePoolDetails(size=2*pool['instance_pool'].size)
            compute_management_client = ctx.obj['OCI_MGMT'][region]

            updated_pool = compute_management_client.update_instance_pool(
                instance_pool_id=pool['instance_pool'].id,
                update_instance_pool_details=instance_pool_details,
                retry_strategy=ctx.obj['RETRY_STRATEGY'],
            )
            if ctx.obj['DEBUG']:
                click.echo(f"## DEBUG: updated pool info: {updated_pool.data}")
    if ctx.obj['WAIT']:
        wait_for_running_pools(ctx)

def halve_pool_instances_in_region(ctx: click.Context, region: str) -> Tuple[str, bool]:
    '''halve the size of instance pools in a region'''
    if len(ctx.obj['POOLS'][region]) < 1:
        if ctx.obj['DEBUG'] and not ctx.obj['IP_ONLY']:
            click.echo(f"## DEBUG: skipping scale down in {region} (no instance pools)")
    compute_management_client = ctx.obj['OCI_MGMT'][region]
    for pool in ctx.obj['POOLS'][region]:
        pool_name = pool['instance_pool'].defined_tags['jitsi']['Name']
        running_instances = [{'ocid': i.id, 'time_created': i.time_created, } for i in pool['instances'] if i.state == 'Running']
        if len(running_instances) <= int(ctx.obj['MINIMUM_POOL_SIZE']):
            if not ctx.obj['IP_ONLY'] or ctx.obj['DEBUG']:
                click.echo(f"## skipped halving pool in {region}: {pool_name} (pool has {len(running_instances)} " +
                           f"running instances and minimum size is {int(ctx.obj['MINIMUM_POOL_SIZE'])})")
            continue
        floor_half_running = len(running_instances)//2 
        max_detachable = len(running_instances) - int(ctx.obj['MINIMUM_POOL_SIZE'])
        detach_int = min(floor_half_running, max_detachable) 
        if not ctx.obj['IP_ONLY']:
            click.echo(f"## detaching {detach_int} of {len(running_instances)} instances from pool {pool_name}...")
        ordered_instances = sorted(pool['instances'], key=lambda x: x.time_created)
        for i in range(detach_int):
            instance_details = oci.core.models.DetachInstancePoolInstanceDetails(
                instance_id=ordered_instances[i].id,
                is_auto_terminate=True,
                is_decrement_size=True,
            )
            if ctx.obj['IP_ONLY']:
                instance = ctx.obj['OCI_COMP'][region].get_instance(instance_id=ordered_instances[i].id)
                ctx.obj['IP_HITLIST'].append(instance.data.freeform_tags['private_ip'])
            if not ctx.obj['IP_ONLY']:
                click.echo(f"## {pool_name} [{i+1}/{detach_int}]: detaching {ordered_instances[i].id}")
                try:
                    compute_management_client.detach_instance_pool_instance(
                        instance_pool_id=pool['instance_pool'].id,
                        detach_instance_pool_instance_details=instance_details,
                        retry_strategy=ctx.obj['RETRY_STRATEGY'],
                    )
                except oci.exceptions.TransientServiceError as transient_error:
                    click.echo(f"## {pool_name} [{i+1}/{detach_int}]: FAILED detach instance: {ordered_instances[i].id}:\n{transient_error}")
                    return(region, False)
                click.echo(f"## {pool_name} [{i+1}/{detach_int}]: successfully detached instance")
    return (region, True)

def halve_instance_pools(ctx: click.Context):
    '''halve the size of all instance pools in the context by detaching/deleting the oldest instances'''
    if not ctx.obj['IP_ONLY'] or ctx.obj['DEBUG']:
        click.echo(f"## pool.py: halving instance pools for role {ctx.obj['FILTER']['ROLE']} in {ctx.obj['ENVIRONMENT']}")
    regions = ctx.obj['POOLS'].keys()
    with ThreadPoolExecutor(max_workers=len(regions)) as executor:
        future_results = { executor.submit(halve_pool_instances_in_region, ctx, region) for region in regions }
        for future in concurrent.futures.as_completed(future_results):
            data = future.result()
            if ctx.obj['DEBUG']:
                click.echo(f"## DEBUG: half_pool_instances_in_region result: {data}")
            if not data[1]:
                if not ctx.obj['IP_ONLY'] or ctx.obj['DEBUG']:
                    click.echo(f"## failed halve_instance_pools for at least one pool in region: {data[0]}")
    if ctx.obj['WAIT']:
        wait_for_running_pools(ctx)
    if ctx.obj['IP_ONLY']:
        click.echo(f"{' '.join(ctx.obj['IP_HITLIST'])}")

@click.group(invoke_without_command=False, context_settings=dict(max_content_width=120))
@click.option('--environment', required=True, envvar=['ENVIRONMENT', 'HCV_ENVIRONMENT'],
              help='jitsi environment')
@click.option('--role', envvar=['ROLE', 'SHARD_ROLE'], default=None, help='role to filter on')
@click.option('--pool', envvar=['INSTANCE_POOL_ID'], default=None, help='instance pool ID to use')
@click.option('--oracle_regions', envvar=['ORACLE_REGIONS'], default=None, help='list of oracle regions where instance pools reside, comma-separated')
@click.option('--inactive', envvar=['INACTIVE'], is_flag=True, default=False, help='load inactive pools (not ACTIVE or SCALING)')
@click.option('--debug', '-d', envvar=['DEBUG'], is_flag=True, default=False, help='debug mode')
@click.pass_context
def cli(ctx: click.Context, environment: str, role: str, pool: str, oracle_regions: str, inactive: bool, debug: bool):
    '''interact with jitsi oci instance pools'''
    if debug:
        click.echo("# starting pool.py")
        click.echo("## DEBUG: init context")
    init_click_context(ctx, environment, role, pool, oracle_regions, inactive, debug)
    if ctx.obj['DEBUG']:
        click.echo("## DEBUG: loading instance pools")
    load_instance_pools(ctx)

@cli.command('inventory', short_help='list all instance pools')
@click.pass_context
def inventory_cmd(ctx: click.Context):
    '''list all instance pools in json format'''
    list_instance_pools(ctx)

@cli.command('double', short_help='scale up existing instance pools to double')
@click.option('--wait', envvar=['WAIT'], is_flag=True, default=False, help='wait for pools to be in RUNNING state before exit')
@click.pass_context
def double_cmd(ctx: click.Context, wait: bool):
    '''double the size of existing instance pools of a specified role'''
    ctx.obj['WAIT'] = wait
    if not ctx.obj['FILTER']['ROLE'] and not ctx.obj['FILTER']['POOL']:
        click.echo("## must set ROLE or POOL for scaling operations")
        sys.exit(1)
    if ctx.obj['INACTIVE']:
        click.echo("## double can only be carried out against active pools")
        sys.exit(1)
    double_instance_pools(ctx)

@cli.command('halve', short_help='scale down existing instance pools to half')
@click.option('--minimum', envvar=['MINIMUM_POOL_SIZE'], default=1, help='minimum remaining pool size')
@click.option('--onlyip', envvar=['IP_ONLY'], is_flag=True, default=False, help='no-op that only lists IPs that would be scaled down')
@click.option('--wait', envvar=['WAIT'], is_flag=True, default=False, help='wait for pools to be in RUNNING state before exit')
@click.pass_context
def halve_cmd(ctx: click.Context, minimum: int, onlyip: bool, wait: bool):
    '''halve the size of existing instance pools of a specified role'''
    ctx.obj['MINIMUM_POOL_SIZE'] = minimum
    ctx.obj['WAIT'] = wait
    ctx.obj['IP_ONLY'] = onlyip
    ctx.obj['IP_HITLIST'] = []
    if not ctx.obj['FILTER']['ROLE'] and not ctx.obj['FILTER']['POOL']:
        click.echo("## must set ROLE or POOL for scaling operations")
        sys.exit(1)
    if ctx.obj['INACTIVE']:
        click.echo("## halve can only be carried out against active pools")
        sys.exit(1)
    halve_instance_pools(ctx)

if __name__ == '__main__':
    cli()
