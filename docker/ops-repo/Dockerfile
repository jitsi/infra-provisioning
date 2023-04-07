FROM docker.io/library/ubuntu:jammy
ARG TARGETPLATFORM

RUN apt-get update && \
    apt-get install -y apt-transport-https apt-utils ca-certificates gnupg wget s3fs software-properties-common && \
    add-apt-repository ppa:hadret/nginx && \
    apt-get update && apt-get install -y nginx-core libnginx-mod-http-fancyindex && \
    rm /etc/nginx/modules-enabled/70-mod-stream-geoip.conf && \
    mkdir /docker-entrypoint.d && \
# forward request and error logs to docker log collector
    ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log && \
    mkdir -p /mnt/ops-repo/repo && \
    echo 'REPLACE WITH VOLUME MOUNT' > /mnt/ops-repo/repo/mount.txt


COPY docker-entrypoint.sh /

COPY nginx.conf /etc/nginx/nginx.conf
COPY default.conf /etc/nginx/sites-available/default
COPY htpasswd.repo /etc/nginx/htpasswd.repo

ENTRYPOINT ["/docker-entrypoint.sh"]

EXPOSE 80

STOPSIGNAL SIGQUIT

CMD ["nginx", "-g", "daemon off;"]
