[[ define "nginx.conf" -]]
user www-data;
worker_processes 4;
pid /run/nginx.pid;
#include /etc/nginx/modules-enabled/*.conf;

events {
	worker_connections 1024;
	# multi_accept on;
}

http {

	##
	# Basic Settings
	##

	sendfile on;
	tcp_nopush on;
	tcp_nodelay on;
	keepalive_timeout 65;
	types_hash_max_size 2048;
	server_tokens off;

	# server_names_hash_bucket_size 64;
	# server_name_in_redirect off;

	client_max_body_size 0;


 	include /etc/nginx/mime.types;
	types {
		# add support for wasm MIME type, that is required by specification and it is not part of default mime.types file
		application/wasm wasm;
		# add support for the wav MIME type that is requried to playback wav files in Firefox.
		audio/wav        wav;
	}
	default_type application/octet-stream;

map $remote_addr $remote_addr_anon {
    ~(?P<ip>\d+\.\d+)\.         $ip.X.X;
    ~(?P<ip>[^:]+:[^:]+):       $ip::X;
    127.0.0.1                   $remote_addr;
    ::1                         $remote_addr;
    default                     0.0.0.0;
}
map $request $request_anon {
    "~(?P<method>.+) (?P<url>\/.+\?)(?P<room>room=[^\&]+\&?)?.* (?P<protocol>.+)"     "$method $url$room $protocol";
    default                    $request;
}
map $http_referer $http_referer_anon {
    "~(?P<url>\/.+\?)(?P<room>room=[^\&]+\&?)?.*"     "$url$room";
    default                    $http_referer;
}
map $http_x_real_ip $http_x_real_ip_anon {
    ~(?P<ip>\d+\.\d+)\.         $ip.X.X;
    ~(?P<ip>[^:]+:[^:]+):       $ip::X;
    127.0.0.1                   $remote_addr;
    ::1                         $remote_addr;
    default                     0.0.0.0;
}

log_format anon '$remote_addr_anon - $remote_user [$time_local] "$request_anon" '
    '$status $body_bytes_sent "$http_referer_anon" '
    '"$http_user_agent" "$http_x_real_ip_anon" $request_time';

	##
	# Logging Settings
	##

	access_log /dev/stdout anon;
	error_log /dev/stderr;

	##
	# Gzip Settings
	##

	gzip on;
	gzip_types text/plain text/css application/javascript application/json;
	gzip_vary on;
	gzip_min_length 860;

	##
	# Connection header for WebSocket reverse proxy
	##
	map $http_upgrade $connection_upgrade {
		default upgrade;
		''      close;
	}

  map $http_x_proxy_region $user_region {
      default '';
      us-west-2 us-west-2;
      us-east-1 us-east-1;
      us-east-2 us-east-2;
      us-west-1 us-west-1;
      ca-central-1 ca-central-1;
      eu-central-1 eu-central-1;
      eu-west-1 eu-west-1;
      eu-west-2 eu-west-2;
      eu-west-3 eu-west-3;
      eu-north-1 eu-north-1;
      me-south-1 me-south-1;
      ap-east-1 ap-east-1;
      ap-south-1 ap-south-1;
      ap-northeast-2 ap-northeast-2;
      ap-northeast-1 ap-northeast-1;
      ap-southeast-1 ap-southeast-1;
      ap-southeast-2 ap-southeast-2;
      sa-east-1 sa-east-1;
  }

	##
	# Virtual Host Configs
	##
	include /etc/nginx/conf.d/*.conf;
}

stream {
    include /etc/nginx/conf.stream/*.conf;
}

#daemon off;
[[ end -]]

[[ define "nginx-status.conf" -]]
server {
    listen 888 default_server;
    server_name  localhost;
    location /nginx_status {
        stub_status on;
        access_log off;
    }
}
[[ end -]]

[[ define "nginx-streams.conf" -]]
# upstream main prosody
upstream prosodylimitedupstream {
    server {{ env "NOMAD_IP_prosody_http" }}:{{ env "NOMAD_HOST_PORT_prosody_http" }};
}
# local rate-limited proxy for main prosody
server {
    listen    15280;
    proxy_upload_rate 10k;
    proxy_pass prosodylimitedupstream;
}

[[ range $index, $i := split " "  (seq 0 ((sub (var "visitors_count" .) 1)|int)) -]]
# upstream visitor prosody [[ $i ]]
upstream prosodylimitedupstream[[ $i ]] {
    server {{ env "NOMAD_IP_prosody_vnode_[[ $i ]]_http" }}:{{ env "NOMAD_HOST_PORT_prosody_vnode_[[ $i ]]_http" }};
}
# local rate-limited proxy for visitor prosody [[ $i ]]
server {
{{ $port := add 25280 [[ $i ]] -}}
    listen    {{ $port }};
    proxy_upload_rate 10k;
    proxy_pass prosodylimitedupstream[[ $i ]];
}
[[ end -]]
[[ end -]]

[[ define "nginx-site.conf" -]]

{{ range service "release-[[ env "CONFIG_release_number" ]].jitsi-meet-web" -}}
    {{ scratch.SetX "web" .  -}}
{{ end -}}

upstream prosody {
    zone upstreams 64K;
    server {{ env "NOMAD_IP_prosody_http" }}:{{ env "NOMAD_HOST_PORT_prosody_http" }};
    keepalive 2;
}

# local upstream for main prosody used in final proxy_pass directive
upstream prosodylimited {
    zone upstreams 64K;
    server 127.0.0.1:15280;
    keepalive 2;
}

# local upstream for web content used in final proxy_pass directive
upstream web {
    zone upstreams 64K;
{{ with scratch.Get "web" -}}
    server {{ .Address }}:{{ .Port }};
{{ else -}}
    server 127.0.0.1:15280;
{{ end -}}
    keepalive 2;
}

# local upstream for jicofo connection
upstream jicofo {
    zone upstreams 64K;
    server {{ env "NOMAD_IP_jicofo_http" }}:{{ env "NOMAD_HOST_PORT_jicofo_http" }};
    keepalive 2;
}

[[ range $index, $i := split " "  (seq 0 ((sub (var "visitors_count" .) 1)|int)) -]]

# local upstream for visitor prosody [[ $i ]] used in final proxy_pass directive
upstream prosodylimited[[ $i ]] {
    zone upstreams 64K;
{{ $port := add 25280 [[ $i ]] -}}
    server 127.0.0.1:{{ $port }};
    keepalive 2;
}
[[ end -]]


[[ range $index, $i := split " "  (seq 0 ((sub (var "visitors_count" .) 1)|int)) -]]
# upstream visitor prosody [[ $i ]]
upstream v[[ $i ]] {
    server {{ env "NOMAD_IP_prosody_vnode_[[ $i ]]_http" }}:{{ env "NOMAD_HOST_PORT_prosody_vnode_[[ $i ]]_http" }};
}
[[ end -]]

map $arg_vnode $prosody_node {
    default prosody;
[[ range $index, $i := split " "  (seq 0 ((sub (var "visitors_count" .) 1)|int)) -]]
    v[[ $i ]] v[[ $i ]];
[[ end -]]
}

# map to determine which prosody to proxy based on query param 'vnode'
map $arg_vnode $prosody_bosh_node {
    default prosodylimited;
[[ range $index, $i := split " "  (seq 0 ((sub (var "visitors_count" .) 1)|int)) -]]
    v[[ $i ]] prosodylimited[[ $i ]];
[[ end -]]
}

limit_req_zone $remote_addr zone=conference-request:10m rate=5r/s;

# Set $remote_addr by scanning X-Forwarded-For, while only trusting the defined list of trusted proxies.
# public ips below are ranges of Cloudflare IPs
set_real_ip_from 127.0.0.1;
set_real_ip_from 172.17.0.0/16;
set_real_ip_from ::1;
set_real_ip_from 10.0.0.0/8;
set_real_ip_from 103.21.244.0/22;
set_real_ip_from 103.22.200.0/22;
set_real_ip_from 103.31.4.0/22;
set_real_ip_from 104.16.0.0/13;
set_real_ip_from 104.24.0.0/14;
set_real_ip_from 108.162.192.0/18;
set_real_ip_from 131.0.72.0/22;
set_real_ip_from 141.101.64.0/18;
set_real_ip_from 162.158.0.0/15;
set_real_ip_from 172.64.0.0/13;
set_real_ip_from 173.245.48.0/20;
set_real_ip_from 188.114.96.0/20;
set_real_ip_from 190.93.240.0/20;
set_real_ip_from 197.234.240.0/22;
set_real_ip_from 198.41.128.0/17;
set_real_ip_from 2400:cb00::/32;
set_real_ip_from 2405:8100::/32;
set_real_ip_from 2405:b500::/32;
set_real_ip_from 2606:4700::/32;
set_real_ip_from 2803:f800::/32;
set_real_ip_from 2a06:98c0::/29;
set_real_ip_from 2c0f:f248::/32;
real_ip_header X-Forwarded-For;
real_ip_recursive on;

server {
    proxy_connect_timeout       90s;
    proxy_send_timeout          90s;
    proxy_read_timeout          90s;
    send_timeout                90s;

    listen 80;

    server_name [[ env "CONFIG_signal_api_hostname" ]];

    set $prefix "";

    location = /kick-participant {
        proxy_pass http://prosodylimited/kick-participant?prefix=$prefix&$args;
        proxy_http_version 1.1;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header Host '[[ env "CONFIG_domain" ]]';
    }

    location ~ ^/([^/?&:'"]+)/kick-participant {
        set $subdomain "$1.";
        set $subdir "$1/";
        set $prefix "$1";

        rewrite ^/(.*)$ /kick-participant;
    }

    location ~ ^/room-password(/?)(.*)$ {
        proxy_pass http://prosodylimited/room-password$2$is_args$args;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host [[ env "CONFIG_domain" ]];

        proxy_buffering off;
        tcp_nodelay on;
    }

    location = /end-meeting {
        proxy_pass http://prosodylimited/end-meeting$is_args$args;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host [[ env "CONFIG_domain" ]];

        proxy_buffering off;
        tcp_nodelay on;
    }

    location = /invite-jigasi{
            proxy_pass http://prosodylimited/invite-jigasi$is_args$args;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Host [[ env "CONFIG_domain" ]];

            proxy_buffering off;
            tcp_nodelay on;
    }

    location ~ ^/([^/?&:'"]+)/room-password$ {
        set $subdomain "$1.";
        set $subdir "$1/";
        set $prefix "$1";

        rewrite ^/(.*)$ /room-password;
    }

    location ~ ^/([^/?&:'"]+)/end-meeting$ {
        set $subdomain "$1.";
        set $subdir "$1/";
        set $prefix "$1";

        rewrite ^/(.*)$ /end-meeting;
    }

    location ~ ^/([^/?&:'"]+)/invite-jigasi$ {
        set $subdomain "$1.";
        set $subdir "$1/";
        set $prefix "$1";

        rewrite ^/(.*)$ /invite-jigasi;
    }
}


# main server doing the routing
server {
    proxy_connect_timeout       90s;
    proxy_send_timeout          90s;
    proxy_read_timeout          90s;
    send_timeout                90s;

    listen       80 default_server;
    server_name  [[ env "CONFIG_domain" ]];

    add_header X-Content-Type-Options nosniff;
[[ template "nginx-headers" . ]]

    set $prefix "";

    # BOSH
    location = /http-bind {
[[ template "nginx-headers" . ]]
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header Host [[ env "CONFIG_domain" ]];

        proxy_pass http://$prosody_bosh_node/http-bind?prefix=$prefix&$args;
    }

    # xmpp websockets
    location = /xmpp-websocket {
        tcp_nodelay on;

[[ template "nginx-headers" . ]]
        proxy_http_version 1.1;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Host [[ env "CONFIG_domain" ]];
        proxy_set_header X-Forwarded-For $remote_addr;

        proxy_pass http://$prosody_node/xmpp-websocket?prefix=$prefix&$args;
    }

    location ~ ^/conference-request/v1(\/.*)?$ {
        proxy_pass http://jicofo/conference-request/v1$1;
        limit_req zone=conference-request burst=5;
[[ template "nginx-headers" . ]]

    }
    location ~ ^/([^/?&:'"]+)/conference-request/v1(\/.*)?$ {
            rewrite ^/([^/?&:'"]+)/conference-request/v1(\/.*)?$ /conference-request/v1$2;
    }


    # BOSH for subdomains
    location ~ ^/([^/?&:'"]+)/http-bind {
        set $subdomain "$1.";
        set $subdir "$1/";
        set $prefix "$1";

        rewrite ^/(.*)$ /http-bind;
    }

    # websockets for subdomains
    location ~ ^/([^/?&:'"]+)/xmpp-websocket {
        set $subdomain "$1.";
        set $subdir "$1/";
        set $prefix "$1";

        rewrite ^/(.*)$ /xmpp-websocket;
    }

    # shard health check
    location = /about/health {
        proxy_pass      http://{{ env "NOMAD_IP_signal_sidecar_http" }}:{{ env "NOMAD_HOST_PORT_signal_sidecar_http" }}/signal/health;
        access_log   off;
        # do not cache anything from prebind
        add_header "Cache-Control" "no-cache, no-store";
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $http_host;
[[ template "nginx-headers" . ]]
    }

    location = /_unlock {
[[ template "nginx-headers" . ]]
        alias /usr/share/nginx/html/_unlock;
    }

    # unlock for subdomains
    location ~ ^/([^/?&:'"]+)/_unlock {
        set $subdomain "$1.";
        set $subdir "$1/";
        set $prefix "$1";

        rewrite ^/(.*)$ /_unlock;
    }

[[ if ne (or (env "CONFIG_jitsi_meet_close_page_redirect_url") "false") "false" -]]
    rewrite ^.*/static/close.html$ [[ env "CONFIG_jitsi_meet_close_page_redirect_url" ]] redirect;
    rewrite ^.*/static/close2.html$ [[ env "CONFIG_jitsi_meet_close_page_redirect_url" ]] redirect;
[[ end -]]

    location / {
        add_header Strict-Transport-Security 'max-age=63072000; includeSubDomains';
        proxy_set_header X-Jitsi-Shard '[[ env "CONFIG_shard" ]]';
        proxy_hide_header 'X-Jitsi-Shard';
        proxy_set_header Host $http_host;

        proxy_pass http://web;
    }

    #error_page  404              /404.html;

    # redirect server error pages to the static page /50x.html
    #
    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/share/nginx/html;
    }

}
[[ end -]]

[[ define "nginx-headers" -]]
        add_header Strict-Transport-Security 'max-age=63072000; includeSubDomains';
        add_header 'Access-Control-Allow-Origin' '*';
        add_header 'Access-Control-Expose-Headers' "Content-Type, X-Jitsi-Region, X-Jitsi-Shard, X-Proxy-Region, X-Jitsi-Release";
        add_header 'X-Jitsi-Shard' '[[ env "CONFIG_shard" ]]';
        add_header 'X-Jitsi-Region' '[[ env "CONFIG_octo_region" ]]';
        add_header 'X-Jitsi-Release' '[[ env "CONFIG_release_number" ]]';
        add_header "Cache-Control" "no-cache, no-store";
[[ end -]]
[[ define "nginx-reload" -]]
        change_mode = "script"
        change_script {
          command = "/usr/sbin/nginx"
          args = ["-s", "reload"]
          timeout = "30s"
          fail_on_error = true
        }
[[ end -]]
