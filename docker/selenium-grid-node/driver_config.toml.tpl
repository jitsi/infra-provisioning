{{ $BROWSER_MAX_SESSIONS := .Env.BROWSER_MAX_SESSIONS | default "1" -}}
{{ $BROWSER_NAME := .Env.BROWSER_NAME | default "chrome" -}}
{{ $BROWSER_VERSION := .Env.BROWSER_VERSION | default "latest" -}}
{{ $BROWSER_DISPLAY_NAME := .Env.BROWSER_DISPLAY_NAME | default "Chrome" -}}
{{ $BROWSER_BINARY_CHROME := .Env.BROWSER_BINARY_CHROME | default "/usr/bin/google-chrome" -}}
{{ $BROWSER_BINARY_FIREFOX := .Env.BROWSER_BINARY_FIREFOX | default "/usr/bin/firefox" -}}
[[node.driver-configuration]]
display-name = "{{ $BROWSER_DISPLAY_NAME }}"
stereotype = '{"browserName": "{{ $BROWSER_NAME }}", "browserVersion": "{{ $BROWSER_VERSION }}", "platformName": "Linux",
{{- if eq $BROWSER_NAME "firefox" -}}
"moz:firefoxOptions":{"binary":"{{ $BROWSER_BINARY_FIREFOX }}"}
{{- else -}}
"goog:chromeOptions":{"binary":"{{ $BROWSER_BINARY_CHROME }}"}
{{- end -}}
, "se:containerName": ""}'
max-sessions = {{ $BROWSER_MAX_SESSIONS }}
