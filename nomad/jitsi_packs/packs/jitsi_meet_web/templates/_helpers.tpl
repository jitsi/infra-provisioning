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

[[ define "variables" -]]

variable "count_per_dc" {
  type = number
  default = 2
}

variable "environment" {
    type = string
}

variable "domain" {
    type = string
}

variable "web_tag" {
  type = string
}

variable "signal_version" {
  type = string
}

variable "dc" {
  type = list(string)
}

variable "release_number" {
  type = string
  default = "0"
}

variable "pool_type" {
  type = string
  default = "general"
}

variable web_repo {
  type = string
  default = "jitsi/web"
}

variable branding_name {
  type = string
  default = "jitsi-meet"
}

variable cloud_provider {
    type = string
    default = "oracle"
}

variable token_auth_url {
  type = string
  default = ""
}

variable token_auth_auto_redirect {
  type = string
  default = "false"
}

variable token_logout_url {
  type = string
  default = ""
}

variable token_sso {
  type = string
  default = ""
}

variable jvb_prefer_sctp {
  type = string
  default = "false"
}

variable insecure_room_name_warning {
  type = string
  default = "false"
}

variable amplitude_api_key {
  type = string
  default = ""
}

variable amplitude_include_utm {
  type = string
  default = "false"
}

variable rtcstats_enabled {
  type = string
  default = "false"
}

variable rtcstats_store_logs {
  type = string
  default = "false"
}

variable rtcstats_use_legacy {
  type = string
  default = "false"
}

variable rtcstats_endpoint {
  type = string
  default = ""
}

variable rtcstats_poll_interval {
  type = string
  default = "10000"
}

variable rtcstats_log_sdp {
  type = string
  default = "false"
}

variable analytics_white_listed_events {
  type = string
  default = ""
}

variable video_resolution {
  type = string
  default = ""
}

variable conference_request_http_enabled {
  type = string
  default = "false"
}

variable google_api_app_client_id {
  type = string
  default = ""
}

variable google_analytics_id {
  type = string
  default = ""
}

variable microsoft_api_app_client_id {
  type = string
  default = ""
}

variable dropbox_appkey {
  type = string
  default = ""
}

variable calendar_enabled {
  type = string
  default = "true"
}

variable token_based_roles_enabled {
  type = string
  default = "false"
}

variable invite_service_url {
  type = string
  default = ""
}

variable people_search_url {
  type = string
  default = ""
}

variable confcode_url {
  type = string
  default = ""
}

variable dialin_numbers_url {
  type = string
  default = ""
}

variable dialout_auth_url {
  type = string
  default = ""
}

variable dialout_codes_url {
  type = string
  default = ""
}

variable dialout_region_url {
  type = string
  default = ""
}

variable api_dialin_numbers_url {
  type = string
  default = ""
}

variable api_conference_mapper_url {
  type = string
  default = ""
}

variable api_dialout_auth_url {
  type = string
  default = ""
}

variable api_dialout_codes_url {
  type = string
  default = ""
}

variable api_dialout_region_url {
  type = string
  default = ""
}

variable api_directory_search_url {
  type = string
  default = ""
}

variable api_conference_invite_url {
  type = string
  default = ""
}

variable api_conference_invite_callflows_url {
  type = string
  default = ""
}

variable api_guest_dial_out_url {
  type = string
  default = ""
}

variable api_guest_dial_out_status_url {
  type = string
  default = ""
}

variable api_recoding_sharing_url {
  type = string
  default = ""
}

variable jaas_actuator_url {
  type = string
  default = ""
}

variable api_jaas_token_url {
  type = string
  default = ""
}

variable jitsi_meet_api_jaas_conference_creator_url {
  type = string
  default = ""
}

variable api_jaas_webhook_proxy {
  type = string
  default = ""
}

variable api_billing_counter {
  type = string
  default = ""
}

variable api_branding_data_url {
  type = string
  default = ""
}

variable channel_last_n {
  type = string
  default = "-1"
}

variable ssrc_rewriting_enabled {
  type = string
  default = "false"
}

variable restrict_hd_tile_view_jvb {
  type = string
  default = "false"
}

variable dtx_enabled {
  type = string
  default = "false"
}

variable hidden_from_recorder_feature {
  type = string
  default = "false"
}

variable transcriptions_enabled {
  type = string
  default = "false"
}

variable livestreaming_enabled {
  type = string
  default = "false"
}

variable service_recording_enabled {
  type = string
  default = "false"
}

variable service_recording_sharing_enabled {
  type = string
  default = "false"
}

variable local_recording_disabled {
  type = string
  default = "false"
}

variable require_display_name {
  type = string
  default = "false"
}

variable start_video_muted {
  type = number
  default = 25
}

variable start_audio_muted {
  type = number
  default = 25
}

variable forced_reloads_enabled {
  type = string
  default = "false"
}

variable legal_urls {
  type = string
  default = "{\"helpCentre\": \"https://web-cdn.jitsi.net/faq/meet-faq.html\", \"privacy\": \"https://jitsi.org/meet/privacy\", \"terms\": \"https://jitsi.org/meet/terms\"}"
}

variable whiteboard_enabled {
  type = string
  default = "false"
}

variable whiteboard_server_url {
  type = string
  default = ""
}

variable giphy_enabled {
  type = string
  default = "false"
}

variable giphy_sdk_key {
  type = string
  default = ""
}

variable performance_stats_enabled {
  type = string
  default = "false"
}

variable prejoin_page_enabled {
  type = string
  default = "false"
}

variable moderated_service_url {
  type = string
  default = ""
}

variable webhid_feature_enabled {
  type = string
  default = "true"
}

variable iframe_api_disabled {
  type = string
  default = "false"
}

variable screenshot_capture_enabled {
  type = string
  default = "false"
}

variable screenshot_capture_mode {
  type = string
  default = "recording"
}

variable face_landmarks_centering_enabled {
  type = string
  default = "false"
}

variable face_landmarks_detect_expressions {
  type = string
  default = "false"
}

variable face_landmarks_display_expressions {
  type = string
  default = "false"
}

variable face_landmarks_rtcstats_enabled {
  type = string
  default = "false"
}

variable reactions_moderation_disabled {
  type = string
  default = "false"
}

variable turn_udp_enabled {
  type = string
  default = "false"
}

variable jitsi_meet_jvb_preferred_codecs {
  type = string
  default = ""
}

variable jitsi_meet_p2p_preferred_codecs {
    type = string
    default = ""
}
[[ end -]]
