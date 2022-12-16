FROM  --platform=$TARGETPLATFORM mikefarah/yq:latest
ARG TARGETPLATFORM
ARG BUILDPLATFORM


FROM  --platform=$TARGETPLATFORM jenkins/agent:latest-jdk11
ARG TARGETPLATFORM
ARG BUILDPLATFORM
COPY --from=0 /usr/bin/yq /usr/bin/yq
COPY ./requirements.txt /home/jenkins/requirements.txt

USER root
RUN apt-get update && apt-get -y install jq python3-pip wget gpg unzip git && pip install -r /home/jenkins/requirements.txt && pip install jenkins-job-builder
RUN wget -O- https://apt.releases.hashicorp.com/gpg | \
    gpg --dearmor | \
    tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
RUN echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com bullseye main" | \
    tee /etc/apt/sources.list.d/hashicorp.list
RUN apt-get update && apt-get -y install packer
RUN if [ "$TARGETPLATFORM" = "linux/amd64" ]; then ARCHITECTURE="amd64"; elif [ "$TARGETPLATFORM" = "linux/arm64" ]; then ARCHITECTURE="arm64"; else ARCHITECTURE="amd64"; fi \
    && echo $ARCHITECTURE && \
    wget https://releases.hashicorp.com/terraform/1.3.6/terraform_1.3.6_linux_${ARCHITECTURE}.zip && unzip ./terraform*.zip && mv terraform /usr/bin/terraform

USER jenkins
#ENTRYPOINT ["/usr/local/bin/jenkins-agent"]
