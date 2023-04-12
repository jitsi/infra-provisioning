FROM  --platform=$TARGETPLATFORM mikefarah/yq:latest
ARG TARGETPLATFORM
ARG BUILDPLATFORM


FROM  --platform=$TARGETPLATFORM jenkins/agent:latest-jdk11
ARG TARGETPLATFORM
ARG BUILDPLATFORM
COPY --from=0 /usr/bin/yq /usr/bin/yq
COPY ./requirements.txt /home/jenkins/requirements.txt
COPY ./s3cfg /home/jenkins/.s3cfg

USER root
RUN apt-get update && apt-get -y install procps dnsutils jq python3-pip wget curl gpg unzip zip git python-is-python3 maven xvfb imagemagick s3cmd s3fs mini-dinstall sudo devscripts dpkg-dev && pip install -r /home/jenkins/requirements.txt && pip install jenkins-job-builder
RUN echo "%jenkins ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/jenkins
RUN wget -O- https://apt.releases.hashicorp.com/gpg | \
    gpg --dearmor | \
    tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
RUN echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com bullseye main" | \
    tee /etc/apt/sources.list.d/hashicorp.list
RUN apt-get update && apt-get -y install packer nomad && rm /etc/apt/sources.list.d/hashicorp.list
RUN if [ "$TARGETPLATFORM" = "linux/amd64" ]; then ARCHITECTURE="amd64"; elif [ "$TARGETPLATFORM" = "linux/arm64" ]; then ARCHITECTURE="arm64"; else ARCHITECTURE="amd64"; fi \
    && echo $ARCHITECTURE && \
    wget https://releases.hashicorp.com/terraform/1.3.6/terraform_1.3.6_linux_${ARCHITECTURE}.zip && unzip ./terraform*.zip && mv terraform /usr/bin/terraform
RUN wget -O- https://deb.nodesource.com/gpgkey/nodesource.gpg.key | \
    gpg --dearmor | \
    tee /usr/share/keyrings/nodesource-archive-keyring.gpg
RUN echo "deb [signed-by=/usr/share/keyrings/nodesource-archive-keyring.gpg] https://deb.nodesource.com/node_16.x bullseye main" | \
    tee /etc/apt/sources.list.d/nodesource.list
RUN apt-get update && apt-get -y install nodejs && rm /etc/apt/sources.list.d/nodesource.list
RUN mkdir -p /opt/jitsi && git clone https://github.com/jitsi/jitsi-autoscaler-sidecar.git /opt/jitsi/jitsi-autoscaler-sidecar \
    && cd /opt/jitsi/jitsi-autoscaler-sidecar && npm install && npm run build
RUN mkdir -p /opt/jitsi && git clone https://github.com/jitsi/token-generator.git /opt/jitsi/token-generator \
    && cd /opt/jitsi/token-generator && npm install && npm run build

USER jenkins
RUN mkdir -p /home/jenkins/.ansible/cp
#ENTRYPOINT ["/usr/local/bin/jenkins-agent"]
