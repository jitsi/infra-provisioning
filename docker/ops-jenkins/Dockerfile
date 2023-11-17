FROM  --platform=$TARGETPLATFORM mikefarah/yq:latest
ARG TARGETPLATFORM
ARG BUILDPLATFORM


FROM  --platform=$TARGETPLATFORM jenkins/jenkins:lts-jdk17
ARG TARGETPLATFORM
ARG BUILDPLATFORM
COPY --from=0 /usr/bin/yq /usr/bin/yq
COPY ./requirements.txt /home/jenkins/requirements.txt

USER root
RUN apt-get update && apt-get -y install procps dnsutils jq python3-pip wget curl gpg unzip zip git python-is-python3 maven xvfb imagemagick sudo && pip install --break-system-packages -r /home/jenkins/requirements.txt && pip install --break-system-packages jenkins-job-builder
RUN echo "%jenkins ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/jenkins

RUN wget -O-  https://download.docker.com/linux/debian/gpg | \
    gpg --dearmor | \
    tee /usr/share/keyrings/docker-archive-keyring.gpg
RUN if [ "$TARGETPLATFORM" = "linux/amd64" ]; then ARCHITECTURE="amd64"; elif [ "$TARGETPLATFORM" = "linux/arm64" ]; then ARCHITECTURE="arm64"; else ARCHITECTURE="amd64"; fi \
    && echo $ARCHITECTURE && echo "deb [signed-by=/usr/share/keyrings/docker-archive-keyring.gpg arch=$ARCHITECTURE] https://download.docker.com/linux/debian bullseye stable" | \
    tee /etc/apt/sources.list.d/docker.list && apt-get update
RUN apt-get -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
RUN usermod -a -G docker jenkins && usermod -a -G shadow jenkins
RUN adduser -q --disabled-password --gecos "" ubuntu && mkdir /home/ubuntu/.ssh && chown ubuntu /home/ubuntu/.ssh
RUN mkdir -p /home/jenkins/triggers && touch /home/jenkins/triggers/reconfigure-users-jenkins && chown -R jenkins:jenkins /home/jenkins/triggers
USER jenkins
RUN jenkins-plugin-cli --plugins "ansicolor ant docker-plugin git-parameter aws-credentials next-build-number build-timestamp fstrigger github junit lockable-resources maven-plugin nomad parameterized-trigger plain-credentials slack ssh-agent ssh-credentials timestamper ws-cleanup script-security blueocean docker-workflow"
