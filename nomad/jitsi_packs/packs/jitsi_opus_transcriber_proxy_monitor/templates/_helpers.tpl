[[/* Template helpers used by jitsi_opus_transcriber_proxy_monitor.nomad.tpl. */]]

[[/* job_name: the job_name var, falling back to the pack name. */]]
[[- define "job_name" -]]
[[ coalesce (var "job_name" .) (meta "pack.name" .) | quote ]]
[[- end -]]

[[/* region: emit a region line only when the region var is set. */]]
[[ define "region" -]]
[[- if var "region" . -]]
  region = "[[ var "region" . ]]"
[[- end -]]
[[- end -]]
