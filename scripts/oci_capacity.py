#!/usr/bin/env python3
''' helper tool to interact with oracle compute client'''

import json
import pprint
import sys
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

def fault_domains_for_ad(ctx: click.Context, region: str, availability_domain: str):
    '''sorted fault domain names for an availability domain'''
    id_client = ctx.obj['OCI_ID_CLIENT'][region]
    return sorted([fd.name for fd in id_client.list_fault_domains(
        compartment_id=ctx.obj['COMPARTMENT'].id,
        availability_domain=availability_domain,
        retry_strategy=ctx.obj['RETRY_STRATEGY']).data])

def shape_config(ocpus, memory_in_gbs):
    '''build a shape config, or None for a fixed (non-flex) shape'''
    if ocpus is None and memory_in_gbs is None:
        return None
    return oci.core.models.CapacityReportInstanceShapeConfig(ocpus=ocpus, memory_in_gbs=memory_in_gbs)

def capacity_by_fault_domain(ctx: click.Context, region: str, availability_domain: str,
                             shape: str, ocpus, memory_in_gbs):
    '''
    per-fault-domain capacity for a shape in one availability domain

    returns a dict of fault domain name -> {'status': str, 'available_count': int}
    status is one of AVAILABLE, OUT_OF_HOST_CAPACITY, HARDWARE_NOT_SUPPORTED
    '''
    fds = fault_domains_for_ad(ctx, region, availability_domain)
    config = shape_config(ocpus, memory_in_gbs)
    details = oci.core.models.CreateComputeCapacityReportDetails(
        availability_domain=availability_domain,
        compartment_id=ctx.obj['COMPARTMENT'].id,
        shape_availabilities=[
            oci.core.models.CreateCapacityReportShapeAvailabilityDetails(
                instance_shape=shape, instance_shape_config=config, fault_domain=fd)
            for fd in fds])
    report = ctx.obj['OCI_CC_CLIENT'][region].create_compute_capacity_report(
        create_compute_capacity_report_details=details,
        retry_strategy=ctx.obj['RETRY_STRATEGY']).data
    return {sa.fault_domain: {'status': sa.availability_status,
                              'available_count': sa.available_count}
            for sa in report.shape_availabilities}

def assign_fault_domains(capacity, placement_ads, current=None):
    '''
    pick one fault domain per placement so that no two placements sharing an
    availability domain share a fault domain.

    capacity        dict of AD -> (dict of FD -> {'status', 'available_count'})
    placement_ads   list of AD names, one per placement, in placement order
    current         optional list of the fault domain each placement uses today

    Fault domains are only meaningful within an availability domain, so two
    placements in different ADs may hold the same fault domain name. Within an
    AD the assignment prefers the placement's current fault domain when it is
    still available, then the emptiest remaining one. Raises ValueError when an
    AD has fewer available fault domains than placements that need them.
    '''
    assignment = [None] * len(placement_ads)
    by_ad = {}
    for idx, ad in enumerate(placement_ads):
        by_ad.setdefault(ad, []).append(idx)

    for ad, indexes in by_ad.items():
        fds = capacity.get(ad, {})
        usable = [fd for fd, info in fds.items() if info['status'] == 'AVAILABLE']
        if len(usable) < len(indexes):
            raise ValueError(
                "%s has %d fault domain(s) with capacity but %d placement(s) need one: %s"
                % (ad, len(usable), len(indexes),
                   json.dumps({fd: info['status'] for fd, info in sorted(fds.items())})))

        taken = set()
        # keep an existing placement where it is, so a re-run does not shuffle
        # instances between fault domains for no reason
        if current:
            for idx in indexes:
                existing = current[idx] if idx < len(current) else None
                if existing in usable and existing not in taken:
                    assignment[idx] = existing
                    taken.add(existing)
        # fill the rest from the emptiest fault domain down
        remaining = sorted([fd for fd in usable if fd not in taken],
                           key=lambda fd: (-fds[fd]['available_count'], fd))
        for idx in indexes:
            if assignment[idx] is None:
                assignment[idx] = remaining.pop(0)
                taken.add(assignment[idx])

    return assignment

@click.group(invoke_without_command=False, context_settings=dict(max_content_width=120))
@click.option('--environment', required=True, envvar=['ENVIRONMENT', 'HCV_ENVIRONMENT'], help='jitsi environment')
@click.option('--debug', '-d', envvar=['DEBUG'], is_flag=True, default=False, help='debug mode')
@click.pass_context
def cli(ctx: click.Context, environment: str, debug: bool):
    '''helper tool to interact with oci compute client'''
    if debug:
        click.echo("# starting oci_capacity.py")
        click.echo("## DEBUG: init context")
    init_click_context(ctx, environment, debug)

@cli.command('list_availability_domains', short_help='list availability domains')
@click.pass_context
def list_ads_cmd(ctx: click.Context):
    '''list availability domains'''
    if ctx.obj['DEBUG']:
        click.echo("## DEBUG: loading availability domains")

    load_availability_domains(ctx)
    print_availability_domains(ctx)

@cli.command('list_compute_capacity', short_help='list compute capacity per fault domain')
@click.option('--region', 'regions', multiple=True, envvar='ORACLE_REGION',
              help='oracle region, repeatable; defaults to every region in the environment')
@click.option('--shape', required=True, envvar='SHAPE', help='instance shape')
@click.option('--ocpus', type=float, envvar='OCPUS', help='ocpus, for flex shapes')
@click.option('--memory-in-gbs', type=float, envvar='MEMORY_IN_GBS', help='memory in GB, for flex shapes')
@click.option('--json', 'as_json', is_flag=True, default=False, help='emit json instead of a table')
@click.pass_context
def list_compute_capacity_cmd(ctx: click.Context, regions, shape, ocpus, memory_in_gbs, as_json):
    '''list compute capacity for a shape, broken out by availability and fault domain'''
    load_availability_domains(ctx)

    selected = list(regions) if regions else list(ctx.obj['OCI_ADS'].keys())
    out = {}
    for region in selected:
        out[region] = {}
        for ad in ctx.obj['OCI_ADS'].get(region, []):
            out[region][ad.name] = capacity_by_fault_domain(
                ctx, region, ad.name, shape, ocpus, memory_in_gbs)

    if as_json:
        click.echo(json.dumps(out, indent=2, sort_keys=True))
        return
    for region in sorted(out):
        click.echo("== %s %s" % (region, shape))
        for ad in sorted(out[region]):
            for fd in sorted(out[region][ad]):
                info = out[region][ad][fd]
                click.echo("  %-30s %-16s %-22s available_count=%s"
                           % (ad, fd, info['status'], info['available_count']))

@cli.command('assign_fault_domains', short_help='pick a distinct fault domain per placement')
@click.option('--region', required=True, envvar='ORACLE_REGION', help='oracle region')
@click.option('--shape', required=True, envvar='SHAPE', help='instance shape')
@click.option('--ocpus', type=float, envvar='OCPUS', help='ocpus, for flex shapes')
@click.option('--memory-in-gbs', type=float, envvar='MEMORY_IN_GBS', help='memory in GB, for flex shapes')
@click.option('--count', type=int, default=3, show_default=True, help='number of placements to assign')
@click.option('--availability-domains', help='json list of ADs; defaults to every AD in the region')
@click.option('--current', help='json list of the fault domain each placement uses today, to hold placements steady')
@click.pass_context
def assign_fault_domains_cmd(ctx: click.Context, region, shape, ocpus, memory_in_gbs,
                             count, availability_domains, current):
    '''
    emit a json list of fault domains, one per placement, such that placements
    sharing an availability domain never share a fault domain

    intended to be captured by a provisioning script and handed to terraform,
    e.g. CONSUL_FAULT_DOMAINS for the consul-server stack
    '''
    load_availability_domains(ctx)

    if availability_domains:
        ads = json.loads(availability_domains)
    else:
        ads = [ad.name for ad in ctx.obj['OCI_ADS'].get(region, [])]
    if not ads:
        click.echo("no availability domains found for %s" % region, err=True)
        sys.exit(1)

    # placement i targets ads[i % len(ads)], matching how the consul-server
    # stack maps pool a/b/c onto availability_domains[0/1/2]
    placement_ads = [ads[i % len(ads)] for i in range(count)]

    capacity = {}
    for ad in set(placement_ads):
        capacity[ad] = capacity_by_fault_domain(ctx, region, ad, shape, ocpus, memory_in_gbs)

    try:
        assignment = assign_fault_domains(
            capacity, placement_ads, json.loads(current) if current else None)
    except ValueError as err:
        click.echo("## ERROR: %s" % err, err=True)
        sys.exit(2)

    if ctx.obj['DEBUG']:
        for idx, ad in enumerate(placement_ads):
            click.echo("## DEBUG: placement %d %s %s available_count=%s"
                       % (idx, ad, assignment[idx],
                          capacity[ad][assignment[idx]]['available_count']), err=True)

    click.echo(json.dumps(assignment))

if __name__ == '__main__':
    cli()
