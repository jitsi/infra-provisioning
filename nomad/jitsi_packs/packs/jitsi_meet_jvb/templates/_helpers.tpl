[[- /*

# Template Helpers

This file contains Nomad pack template helpers. Any information outside of a
`define` template action is informational and is not rendered, allowing you
to write comments and implementation details about your helper functions here.
Some helper functions are included to get you started.

*/ -]]

[[- /*

## `job_name` helper

This helper demonstrates how to use a variable value or fall back to the pack's
metadata when that value is set to a default of "".

*/ -]]

[[- define "job_name" -]]
[[ coalesce ( var "job_name" .) (meta "pack.name" .) | quote ]]
[[- end -]]

[[- /*

## `region` helper

This helper demonstrates conditional element rendering. If your pack specifies
a variable named "region" and it's set, the region line will render otherwise
it won't.

*/ -]]

[[ define "region" -]]
[[- if var "region" . -]]
  region = "[[ var "region" . ]]"
[[- end -]]
[[- end -]]

[[- /*

## `constraints` helper

This helper creates Nomad constraint blocks from a value of type
  `list(object(attribute string, operator string, value string))`

*/ -]]

[[ define "constraints" -]]
[[ range $idx, $constraint := . ]]
  constraint {
    attribute = [[ $constraint.attribute | quote ]]
    [[ if $constraint.operator -]]
    operator  = [[ $constraint.operator | quote ]]
    [[ end -]]
    value     = [[ $constraint.value | quote ]]
  }
[[ end -]]
[[- end -]]

[[- /*

## `service` helper

This helper creates Nomad constraint blocks from a value of type

```
  list(
    object(
      service_name string, service_port_label string, service_provider string, service_tags list(string),
      upstreams list(object(name string, port number))
      check_type string, check_path string, check_interval string, check_timeout string
    )
  )
```

The template context should be set to the value of the object when calling the
template.

*/ -]]

[[ define "service" -]]
[[ $service := . ]]
      service {
        name = [[ $service.service_name | quote ]]
        port = [[ $service.service_port_label | quote ]]
        tags = [[ $service.service_tags | toStringList ]]
        provider = [[ $service.service_provider | quote ]]
        [[- if $service.upstreams ]]
        connect {
          sidecar_service {
            proxy {
              [[- range $upstream := $service.upstreams ]]
              upstreams {
                destination_name = [[ $upstream.name | quote ]]
                local_bind_port  = [[ $upstream.port ]]
              }
              [[- end ]]
            }
          }
        }
        [[- end ]]
        check {
          type     = [[ $service.check_type | quote ]]
          [[- if $service.check_path]]
          path     = [[ $service.check_path | quote ]]
          [[- end ]]
          interval = [[ $service.check_interval | quote ]]
          timeout  = [[ $service.check_timeout | quote ]]
        }
      }
[[- end ]]

[[- /*

## `env_vars` helper

This helper formats maps as key and quoted value pairs.

*/ -]]

[[ define "env_vars" -]]
        [[- range $idx, $var := . ]]
        [[ $var.key ]] = [[ $var.value | quote ]]
        [[- end ]]
[[- end ]]

[[- /*

## `resources` helper

This helper formats values of object(cpu number, memory number) as a `resources`
block

*/ -]]

[[ define "resources" -]]
[[- $resources := . ]]
      resources {
        cpu    = [[ $resources.cpu ]]
        memory = [[ $resources.memory ]]
      }
[[- end ]]

[[ define "shard-lookup" -]]
[[ $pool_mode := or (env "CONFIG_jvb_pool_mode") "shard" -]]
[[ $shard_brewery_enabled := (or (env "CONFIG_jvb_shard_brewery_enabled") "true") "true" ]]

[[ if eq $pool_mode "remote" "global" -]]
{{ range $dcidx, $dc := datacenters -}}
  [[ if eq $pool_mode "remote" -]]
  {{ if ne $dc "[[ var "datacenter" . ]]" -}}
  [[ end -]]
[[ if eq $shard_brewery_enabled "false" -]]
  {{ $service := print "prosody-brewery@" $dc -}}
[[- else ]]
  {{ $service := print "release-" (envOrDefault "RELEASE_NUMBER" "0") ".signal@" $dc -}}
[[- end ]]
  {{range $index, $item := service $service -}}
    {{ scratch.MapSetX "shards" .ServiceMeta.shard $item  -}}
  {{ end -}}
  [[ if eq $pool_mode "remote" -]]
  {{ end -}}
  [[ end -]]
{{ end -}}
[[ else -]]

[[ if eq $shard_brewery_enabled "false" -]]
{{ $service := print "prosody-brewery" -}}
[[ else -]]
  [[ if eq $pool_mode "local" -]]
{{ $service := print "release-" (envOrDefault "RELEASE_NUMBER" "0") ".signal" -}}
  [[ else -]]
{{ $service := print "shard-" (env "SHARD") ".signal" -}}
  [[ end -]]
[[ end -]]
{{range $index, $item := service $service -}}
  {{ scratch.MapSetX "shards" .ServiceMeta.shard $item  -}}
{{ end -}}
[[ end -]]
[[- end ]]

[[ define "reload-shards" ]]
#!/usr/bin/with-contenv bash

SHARD_FILE=/config/shards.json
UPLOAD_FILE=/config/upload.json
DRAIN_URL="http://localhost:8080/colibri/drain"
LIST_URL="http://localhost:8080/colibri/muc-client/list"
ADD_URL="http://localhost:8080/colibri/muc-client/add"
REMOVE_URL="http://localhost:8080/colibri/muc-client/remove"

DRAIN_MODE=$(cat $SHARD_FILE | jq -r ".drain_mode")
DOMAIN=$(cat $SHARD_FILE | jq -r ".domain")
USERNAME=$(cat $SHARD_FILE | jq -r ".username")
PASSWORD=$(cat $SHARD_FILE | jq -r ".password")
MUC_JIDS=$(cat $SHARD_FILE | jq -r ".muc_jids")
MUC_NICKNAME=$(cat $SHARD_FILE | jq -r ".muc_nickname")
IQ_HANDLER_MODE=$(cat $SHARD_FILE | jq -r ".iq_handler_mode")
DISABLE_CERT_VERIFY="true"
XMPP_PORT=$(cat $SHARD_FILE | jq -r ".port")

SHARDS=$(cat $SHARD_FILE | jq -r ".shards|keys|.[]")
for SHARD in $SHARDS; do
    echo "Adding shard $SHARD"
    SHARD_IP=$(cat $SHARD_FILE | jq -r ".shards.\"$SHARD\".xmpp_host_private_ip_address")
    SHARD_PORT=$(cat $SHARD_FILE | jq -r ".shards.\"$SHARD\".host_port")
    if [[ "[[" ]] "$SHARD_PORT" == "null" ]]; then
        SHARD_PORT=$XMPP_PORT
    fi
    T="
{
    \"id\":\"$SHARD\",
    \"domain\":\"$DOMAIN\",
    \"hostname\":\"$SHARD_IP\",
    \"port\":\"$SHARD_PORT\",
    \"username\":\"$USERNAME\",
    \"password\":\"$PASSWORD\",
    \"muc_jids\":\"$MUC_JIDS\",
    \"muc_nickname\":\"$MUC_NICKNAME\",
    \"iq_handler_mode\":\"$IQ_HANDLER_MODE\",
    \"disable_certificate_verification\":\"$DISABLE_CERT_VERIFY\"
}"

    #configure JVB to know about shard via POST
    echo $T > $UPLOAD_FILE
    curl --data-binary "@$UPLOAD_FILE" -H "Content-Type: application/json" $ADD_URL
    rm $UPLOAD_FILE
done

LIVE_DRAIN_MODE="$(curl $DRAIN_URL | jq '.drain')"
if [[ "[[" ]] "$DRAIN_MODE" == "true" ]]; then
    if [[ "[[" ]] "$LIVE_DRAIN_MODE" == "false" ]]; then
        echo "Drain mode is requested, draining JVB"
        curl -d "" "$DRAIN_URL/enable"
    fi
fi
if [[ "[[" ]] "$DRAIN_MODE" == "false" ]]; then
    if [[ "[[" ]] "$LIVE_DRAIN_MODE" == "true" ]]; then
        echo "Drain mode is disabled, setting JVB to ready"
        curl -d "" "$DRAIN_URL/disable"
    fi
fi

LIVE_SHARD_ARR="$(curl $LIST_URL)"
FILE_SHARD_ARR="$(cat $SHARD_FILE | jq ".shards|keys")"
REMOVE_SHARDS=$(jq -r -n --argjson FILE_SHARD_ARR "$FILE_SHARD_ARR" --argjson LIVE_SHARD_ARR "$LIVE_SHARD_ARR" '{"live": $LIVE_SHARD_ARR,"file":$FILE_SHARD_ARR} | .live-.file | .[]')

for SHARD in $REMOVE_SHARDS; do
    echo "Removing shard $SHARD"
    curl -H "Content-Type: application/json" -X POST -d "{\"id\":\"$SHARD\"}" $REMOVE_URL 
done

[[- end ]]

[[ define "shards-json" ]]
[[ template "shard-lookup" . ]]
[[ $shard_brewery_enabled := (or (env "CONFIG_jvb_shard_brewery_enabled") "true") "true" ]]

{
  "shards": {
{{ range $sindex, $item := scratch.MapValues "shards" -}}
  {{ scratch.SetX "domain" .ServiceMeta.domain -}}
  {{ if ne $sindex 0}},{{ end }}
    "{{.ServiceMeta.shard}}": {
      "shard":"{{.ServiceMeta.shard}}",
      "domain":"{{ .ServiceMeta.domain }}",
      "address":"{{.Address}}",
      "xmpp_host_private_ip_address":"{{.Address}}",
      "host_port":"{{ with .ServiceMeta.prosody_jvb_client_port}}{{.}}{{ else }}6222{{ end }}"
    }
{{ end -}}
  },
  "drain_mode":"false",
  "port": 6222,
  "domain":"auth.jvb.{{ scratch.Get "domain" }}",
[[ if eq $shard_brewery_enabled "false" -]]
  "muc_jids":"release-[[ or (env "CONFIG_release_number") "0" ]]@muc.jvb.{{ scratch.Get "domain" }}",
[[- else ]]
  "muc_jids":"jvbbrewery@muc.jvb.{{ scratch.Get "domain" }}",
[[- end ]]
  "username":"[[ or (env "CONFIG_jvb_auth_username") "jvb" ]]",
  "password":"[[ env "CONFIG_jvb_auth_password" ]]",
  "muc_nickname":"jvb-{{ env "NOMAD_ALLOC_ID" }}",
  "iq_handler_mode":"[[ or (env "CONFIG_jvb_iq_handler_mode") "sync" ]]"
}
[[- end ]]
