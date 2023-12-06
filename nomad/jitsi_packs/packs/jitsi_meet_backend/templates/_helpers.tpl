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

[[ define "prosody_artifacts" -]]
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/[[ var "prosody_modules_commit_id" . ]]/mod_measure_stanza_counts/mod_measure_stanza_counts.lua"
        destination = "local/prosody-plugins-custom"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/[[ var "prosody_modules_commit_id" . ]]/mod_debug_traceback/mod_debug_traceback.lua"
        destination = "local/prosody-plugins-custom"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/[[ var "prosody_modules_commit_id" . ]]/mod_secure_interfaces/mod_secure_interfaces.lua"
        destination = "local/prosody-plugins-custom"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/[[ var "prosody_modules_commit_id" . ]]/mod_firewall/mod_firewall.lua"
        destination = "local/prosody-plugins-custom/mod_firewall"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/[[ var "prosody_modules_commit_id" . ]]/mod_firewall/definitions.lib.lua"
        destination = "local/prosody-plugins-custom/mod_firewall"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/[[ var "prosody_modules_commit_id" . ]]/mod_firewall/actions.lib.lua"
        destination = "local/prosody-plugins-custom/mod_firewall"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/[[ var "prosody_modules_commit_id" . ]]/mod_firewall/marks.lib.lua"
        destination = "local/prosody-plugins-custom/mod_firewall"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/[[ var "prosody_modules_commit_id" . ]]/mod_firewall/conditions.lib.lua"
        destination = "local/prosody-plugins-custom/mod_firewall"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/[[ var "prosody_modules_commit_id" . ]]/mod_firewall/test.lib.lua"
        destination = "local/prosody-plugins-custom/mod_firewall"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/[[ var "prosody_modules_commit_id" . ]]/mod_log_ringbuffer/mod_log_ringbuffer.lua"
        destination = "local/prosody-plugins-custom"
      }
      artifact {
        source      = "https://raw.githubusercontent.com/jitsi/infra-configuration/main/ansible/roles/prosody/files/mod_muc_webhooks.lua"
        destination = "local/prosody-plugins-custom"
      }
      artifact {
        source      = "https://raw.githubusercontent.com/jitsi/infra-configuration/main/ansible/roles/prosody/files/mod_muc_moderators.lua"
        destination = "local/prosody-plugins-custom"
      }
      artifact {
        source      = "https://raw.githubusercontent.com/jitsi/infra-configuration/main/ansible/roles/prosody/files/mod_muc_events.lua"
        destination = "local/prosody-plugins-custom"
      }
      artifact {
        source      = "https://raw.githubusercontent.com/jitsi/infra-configuration/main/ansible/roles/prosody/files/mod_muc_auth_vpaas.lua"
        destination = "local/prosody-plugins-custom"
      }
      artifact {
        source      = "https://raw.githubusercontent.com/jitsi/infra-configuration/main/ansible/roles/prosody/files/mod_muc_permissions_vpaas.lua"
        destination = "local/prosody-plugins-custom"
      }
      artifact {
        source      = "https://raw.githubusercontent.com/jitsi/infra-configuration/main/ansible/roles/prosody/files/mod_muc_password_preset.lua"
        destination = "local/prosody-plugins-custom"
      }
      artifact {
        source      = "https://raw.githubusercontent.com/jitsi/infra-configuration/main/ansible/roles/prosody/files/util.internal.lib.lua"
        destination = "local/prosody-plugins-custom"
      }
[[ end -]]

[[ define "common-env" -]]
        ENABLE_JVB_XMPP_SERVER = "1"
        ENABLE_RECORDING = "1"
        ENABLE_OCTO = "1"
        ENABLE_LETSENCRYPT = "0"
        ENABLE_XMPP_WEBSOCKET = "1"
        DISABLE_HTTPS = "1"
        ENABLE_SCTP = "[[ env "CONFIG_jicofo_enable_sctp" ]]"
        ENABLE_SCTP_RELAY = "[[ env "CONFIG_jicofo_enable_sctp_relay" ]]"
        PROSODY_VISITORS_MUC_PREFIX = "conference"
        AUTH_TYPE = "jwt"
        XMPP_DOMAIN = "[[ env "CONFIG_domain" ]]"
        JICOFO_AUTH_PASSWORD = "[[ env "CONFIG_jicofo_auth_password" ]]"
        JVB_AUTH_PASSWORD = "[[ env "CONFIG_jvb_auth_password" ]]"
        JIGASI_XMPP_PASSWORD = "[[ env "CONFIG_jigasi_xmpp_password" ]]"
        JIBRI_RECORDER_PASSWORD = "[[ env "CONFIG_jibri_recorder_password" ]]"
        JIBRI_XMPP_PASSWORD = "[[ env "CONFIG_jibri_xmpp_password" ]]"
        PUBLIC_URL = "https://[[ env "CONFIG_domain" ]]/"
        TURN_CREDENTIALS = "[[ env "CONFIG_turnrelay_password" ]]"
        TURNS_HOST = "[[ env "CONFIG_turnrelay_host" ]]"
        TURN_HOST = "[[ env "CONFIG_turnrelay_host" ]]"
        STUN_HOST = "[[ env "CONFIG_turnrelay_host" ]]"
        SHARD = "[[ env "CONFIG_shard" ]]"
        RELEASE_NUMBER = "[[ env "CONFIG_release_number" ]]"
        # Internal XMPP domain for authenticated services
        XMPP_AUTH_DOMAIN = "auth.[[ env "CONFIG_domain" ]]"
        JVB_BREWERY_MUC = "jvbbrewery"
        JVB_STUN_SERVERS = "meet-jit-si-turnrelay.jitsi.net:443"
        JVB_AUTH_USER = "jvb"

        JVB_XMPP_AUTH_DOMAIN = "auth.jvb.[[ env "CONFIG_domain" ]]"
        # XMPP domain for the MUC
        XMPP_MUC_DOMAIN = "conference.[[ env "CONFIG_domain" ]]"
        # XMPP domain for the internal MUC used for jibri, jigasi and jvb pools
        XMPP_INTERNAL_MUC_DOMAIN = "internal.auth.[[ env "CONFIG_domain" ]]"
        JVB_XMPP_INTERNAL_MUC_DOMAIN = "muc.jvb.[[ env "CONFIG_domain" ]]"
        # XMPP domain for unauthenticated users
        XMPP_GUEST_DOMAIN = "guest.[[ env "CONFIG_domain" ]]"
        # XMPP domain for the jibri recorder
        XMPP_RECORDER_DOMAIN = "recorder.[[ env "CONFIG_domain" ]]"
        JICOFO_OCTO_REGION = "[[ env "CONFIG_octo_region" ]]"
[[ end -]]