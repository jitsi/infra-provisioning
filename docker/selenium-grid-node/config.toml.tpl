{{ $GRID_HUB_HOST := .Env.SE_HUB_HOST | default "localhost" -}}
{{ $GRID_PUBLISH_PORT :=.Env.SE_EVENT_BUS_PUBLISH_PORT | default "5556" -}}
{{ $GRID_SUBSCRIBE_PORT :=.Env.SE_EVENT_BUS_SUBSCRIBE_PORT | default "5557" -}}
{{ $NODE_HOST := .Env.SE_NODE_HOST | default "localhost" -}}
{{ $NODE_PORT := .Env.SE_NODE_PORT | default "5555" -}}
{{ $GRID_MAX_SESSIONS := .Env.GRID_MAX_SESSIONS | default "1" -}}
[node]
detect-drivers = false
max-sessions = {{ $GRID_MAX_SESSIONS }}

[events]
publish = "tcp://{{ $GRID_HUB_HOST }}:{{ $GRID_PUBLISH_PORT }}"
subscribe = "tcp://{{ $GRID_HUB_HOST }}:{{ $GRID_SUBSCRIBE_PORT }}"

# Uncomment the following section if you are running the node on a separate VM
# Fill out the placeholders with appropriate values
[server]
host = "{{ $NODE_HOST }}"
port = {{ $NODE_PORT }}

# below is intended to be blank, and filled in at startup time
