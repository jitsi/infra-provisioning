FROM --platform=$TARGETPLATFORM jitsi/base:unstable
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG GIT_UID=1046
ARG GIT_GID=1049

RUN apt-get update && apt-get -y install openssh-server openssh-client git cron sudo

RUN mkdir /run/sshd

RUN addgroup --gid $GIT_GID git && \
    adduser --quiet --disabled-password --uid $GIT_UID --gid $GIT_GID git

RUN mkdir /home/git/.ssh && \
    chmod 700 /home/git/.ssh

COPY rootfs /

USER root

VOLUME /home/git

EXPOSE 22

ENTRYPOINT [ "/init" ]
