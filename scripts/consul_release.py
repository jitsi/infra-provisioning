"""
manipulate live releases and tenant pins in consul
applies changes across all datacenters in a federation
entry: python consul_release.py --help
"""

import sys
import base64
import requests
import click

def read_consul_kv_response(ctx: dict, response, key) -> str:
    '''decodes a get from the consul kv store'''
    if response.text == '':
        if ctx.obj['DEBUG']:
            click.echo("# no result found")
        return None
    try:
        response_json = response.json()
    except requests.exceptions.JSONDecodeError:
        if ctx.obj['DEBUG']:
            click.echo(f"# empty or invalid JSON from {response.url}: {response.text}")
        return None
    if response_json[0]['Key'] == key:
        return base64.b64decode(response_json[0]["Value"]).decode('ascii')
    if ctx.obj['DEBUG']:
        click.echo(f"# ERROR: unexpected response: {response_json}")
    return None

def fetch_datacenters(ctx: dict) -> list:
    '''
    fetch a list of datacenters from consul
    returns a list of strings or [""]
    '''
    dc_url = f"{ctx.obj['CONSUL_URL']}/v1/catalog/datacenters"
    response = requests.get(dc_url)
    try:
        response_json = response.json()
    except requests.exceptions.JSONDecodeError:
        click.echo("# WARNING: failed to get datacenters")
        return [""]
    if ctx.obj['DEBUG']:
        click.echo(f"## DEBUG: datacenters from consul: {list(response_json)}")
    return list(response_json)

def fetch_live_release(ctx: dict) -> str:
    '''
    read live release from local datacenter
    returns name of live release or None
    '''
    live_key = f"releases/{ctx.obj['ENVIRONMENT']}/live"
    live_url = f"{ctx.obj['CONSUL_URL']}/v1/kv/{live_key}"
    response = requests.get(live_url)
    return read_consul_kv_response(ctx, response, live_key)

def set_live_release(ctx: dict, release: str) -> bool:
    '''
    set live release in all datacenters
    returns True if set, False if not set
    '''
    live_url = f"{ctx.obj['CONSUL_URL']}/v1/kv/releases/{ctx.obj['ENVIRONMENT']}/live"
    datacenters = fetch_datacenters(ctx)
    success = True
    for datacenter in datacenters:
        response = requests.put(live_url, data=release, params={'dc': datacenter})
        if response.text != 'true':
            click.echo(f"# failed to set GA/live release {release} for {datacenter} datacenter")
            success = False
    return success

def fetch_tenant_release(ctx: dict, tenant: str) -> str:
    '''
    read tenant pin from local datacenter
    returns tenant pin release or None
    '''
    tenant_key = f"releases/{ctx.obj['ENVIRONMENT']}/tenant/{tenant}"
    tenant_url = f"{ctx.obj['CONSUL_URL']}/v1/kv/{tenant_key}"
    response = requests.get(tenant_url)
    return read_consul_kv_response(ctx, response, tenant_key)

def set_tenant_release(ctx: dict, tenant: str, release: str) -> bool:
    '''
    write tenant pin to all datacenters
    returns True if set, False if not
    '''
    tenant_url = f"{ctx.obj['CONSUL_URL']}/v1/kv/releases/{ctx.obj['ENVIRONMENT']}/tenant/{tenant}"
    datacenters = fetch_datacenters(ctx)
    success = True
    for datacenter in datacenters:
        response = requests.put(tenant_url, data=release, params={'dc': datacenter})
        if response.text != 'true':
            click.echo(f"# failed to set pin {tenant}: {release} for {datacenter} datacenter")
            success = False
    return success

def delete_tenant_pin(ctx: dict, tenant: str) -> bool:
    '''
    delete tenant pin from all datacenters
    returns True if successful, False if not
    '''
    tenant_url = f"{ctx.obj['CONSUL_URL']}/v1/kv/releases/{ctx.obj['ENVIRONMENT']}/tenant/{tenant}"
    datacenters = fetch_datacenters(ctx)
    success = True
    for datacenter in datacenters:
        response = requests.delete(tenant_url, params={'dc': datacenter})
        if ctx.obj['DEBUG']:
            click.echo(f"# DEBUG: attempted delete via {response.url} resulted in {response.text}")
        if response.text != 'true':
            click.echo(f"# failed to delete pin {tenant} in {datacenter} datacenter")
            success = False
    return success

def fetch_all_tenant_releases(ctx: dict) -> list:
    '''
    get a list of all tenant releases from local datacenter.
    returns linefeed delimited list of tenant to release pins, formatted for use
    in a haproxy map file
    '''
    pin_key = f"releases/{ctx.obj['ENVIRONMENT']}/tenant"
    pin_url = f"{ctx.obj['CONSUL_URL']}/v1/kv/{pin_key}?recurse=true"
    response = requests.get(pin_url)
    if response.text == '':
        if ctx.obj['DEBUG']:
            click.echo(f"# empty response from {pin_url}")
        return []
    try:
        response_json = response.json()
    except requests.exceptions.JSONDecodeError:
        if ctx.obj['DEBUG']:
            click.echo(f"# invalid JSON from {pin_url}: {response.text}")
        return []
    result = []
    for release in response_json:
        tenant = release['Key'].split('/')[-1]
        result.append(f"{tenant} {base64.b64decode(release['Value']).decode('ascii')}")
    return result

def test_active_releases(ctx: dict, domain: str) -> bool:
    '''
    derive a list of active releases based on what's live and pinned in consul.
    curl to each of these and return True only if all of them return correct
    backends.
    '''
    live_release = fetch_live_release(ctx)
    pinned_releases = fetch_all_tenant_releases(ctx)

    if ctx.obj['DEBUG']:
        click.echo(f"## DEBUG: live_release: {live_release}")
        click.echo("## DEBUG: pinned_releases:\n##   {}".format("\n##   ".join(pinned_releases)))

    release_dict = { live_release: "GA" }

    for pin in pinned_releases:
        if pin.split()[1] not in release_dict:
            release_dict[pin.split()[1]] = pin.split()[0]

    ## TODO: consider testing all tenants vs. just one per release

    success = True
    for release, tenant in release_dict.items():
        if tenant == "GA":
            url = 'https://' + domain + '/_unlock'
        else:
            url = 'https://' + domain + '/' + tenant + '/_unlock)'

        try:
            resp = requests.get(url)
        except requests.exceptions.RequestException as exception:
            click.echo(f"## ERROR: requests get to {url} threw exception: {exception}")
            success = False

        if resp.status_code != 200:
            click.echo(f"## FAIL: received non-200 response of {resp.status_code} for {resp.url}")
            success = False
        elif not resp.headers and 'x-jitsi-release' not in resp.headers:
            click.echo(f"## FAIL: no 'X-Jitsi-Release' in response headers for {resp.url}")
            success = False
        elif release != 'release-' + resp.headers['x-jitsi-release']:
            click.echo(f"## FAIL: got release-{resp.headers['x-jitsi-release']} for {resp.url}, but expected {release}")
            success = False
        else:
            click.echo(f"## SUCCESS: got release-{resp.headers['x-jitsi-release']} for {resp.url}")

    return success

@click.group(invoke_without_command=False, context_settings=dict(max_content_width=120))
@click.option('--consul_url', default='http://localhost:8500', show_default=True, envvar='CONSUL_URL', help='url of consul server')
@click.option('--environment', required=True, envvar=['ENVIRONMENT', 'HCV_ENVIRONMENT'], help='jitsi environment')
@click.option('--debug', is_flag=True, envvar=['DEBUG'], help='debug mode on')
@click.pass_context
def cli(ctx, consul_url, environment, debug):
    '''interact with live and tenant pins in consul'''
    ctx.ensure_object(dict)
    ctx.obj['CONSUL_URL'] = consul_url
    ctx.obj['ENVIRONMENT'] = environment
    ctx.obj['DEBUG'] = debug
    if ctx.obj['DEBUG']:
        click.echo(f"# DEBUG: consul_release.py release cli params: consul_url: {consul_url}, environment: {environment}")

@cli.command('live', short_help='get or set a live(GA) release')
@click.option('--set', '-s', 'set_', default=None, help='release to set live')
@click.pass_context
def live_cmd(ctx, set_):
    '''
    get or set a live (GA) release

    \b
    > python consul_release.py live
    > python consul_release.py live --set [release]
    '''
    if not set_:
        live_release = fetch_live_release(ctx)
        if live_release:
            click.echo(live_release)
        else:
            click.echo("# failed to fetch live release")
            sys.exit(1)
    else:
        success = set_live_release(ctx, set_)
        if success:
            click.echo(f"live {set_}")
        else:
            click.echo("# failed to set live release")
            sys.exit(1)

@cli.command('pin', short_help='get / list / delete / test pins')
@click.option('--get', '-g', 'get', help='get [tenant] release')
@click.option('--set', '-s', 'set_', nargs=2, help='pin [tenant] to [release]')
@click.option('--list', '-l', 'list_', is_flag=True, help='list all tenant pins')
@click.option('--delete', 'delete', help='delete [tenant] pin')
@click.pass_context
def pin_cmd(ctx, get, set_, list_, delete):
    '''
    interact with tenant pins

    \b
    > python consul_release.py pin --get [tenant]
    > python consul_release.py pin --set [tenant] [release]
    > python consul_release.py pin --list
    > python consul_release.py pin --delete [tenant]
    '''
    if get:
        release = fetch_tenant_release(ctx, get)
        if release:
            click.echo(f"{get} {release}")
        else:
            click.echo(f"{get} UNPINNED")
    elif set_:
        tenant, release = set_[0], set_[1]
        success = set_tenant_release(ctx, tenant, release)
        if success:
            click.echo(f"{tenant} {release}")
        else:
            click.echo("# failed to set live release")
            sys.exit(1)
    elif list_:
        release_pins = fetch_all_tenant_releases(ctx)
        for tenant_pin in release_pins:
            click.echo(tenant_pin)
    elif delete:
        success = delete_tenant_pin(ctx, delete)
        if success:
            click.echo(f"{delete} UNPINNED")
        else:
            click.echo(f"# failed to delete {delete} pin in one or more datacenters")
            sys.exit(1)
    else:
        click.echo("# called consul_release pin without --get, --set, --list, or --delete")
        sys.exit(1)

@cli.command('release_test', short_help='test release backends')
@click.option('--domain', 'domain', help='domain to test against')
@click.pass_context
def releasetest_cmd(ctx, domain):
    '''
    test that all release backends have live shards responding

    > python consul_release.py release_test --domain [domain, e.g., stage.8x8.vc]
    '''
    success = test_active_releases(ctx, domain)
    if not success:
        click.echo("## consul_release failed to reach one or more active release backends")
        sys.exit(1)
    click.echo("## all active releases appear to be working")

if __name__ == '__main__':
    cli()
