{{ $BROWSER_MAX_SESSIONS := .Env.BROWSER_MAX_SESSIONS | default "1" -}}
{{ $BROWSER_OPTIONS := .Env.BROWSER_OPTIONS | default "\"goog:chromeOptions\": {\"binary\": \"/usr/bin/chromium\"}" -}}
{{ $BROWSER_NAME := .Env.BROWSER_NAME | default "chrome" -}}
{{ $BROWSER_VERSION := .Env.BROWSER_VERSION | default "latest" -}}
{{ $BROWSER_DISPLAY_NAME := .Env.BROWSER_DISPLAY_NAME | default "Chrome" -}}
[[node.driver-configuration]]
display-name = "{{ .Env.BROWSER_DISPLAY_NAME }}"
stereotype = '{"browserName": "{{ $BROWSER_NAME }}", "browserVersion": "{{ $BROWSER_VERSION }}", "platformName": "Linux", {{ $BROWSER_OPTIONS }}, "se:containerName": ""}'
max-sessions = {{ $BROWSER_MAX_SESSIONS}}
