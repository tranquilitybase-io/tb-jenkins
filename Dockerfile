FROM openjdk:8-jdk-stretch

# Install git lfs on Debian stretch per https://github.com/git-lfs/git-lfs/wiki/Installation#debian-and-ubuntu
# Avoid JENKINS-59569 - git LFS 2.7.1 fails clone with reference repository
RUN apt-get update && apt-get upgrade -y && apt-get install -y  dos2unix sudo git curl  build-essential && curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | bash && apt-get install -y git-lfs && git lfs install && rm -rf /var/lib/apt/lists/*

RUN echo "deb http://packages.cloud.google.com/apt cloud-sdk-stretch main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list \
    && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - \
    && apt-get update -y && apt-get install google-cloud-sdk -y \
    && PATH=$PATH:/root/google-cloud-sdk/bin

ARG user=jenkins
ARG group=jenkins
ARG uid=1000
ARG gid=1000
ARG http_port=8080
ARG agent_port=50000
ARG JENKINS_HOME=/var/jenkins_home
ARG REF=/usr/share/jenkins/ref 
ARG JENKINS_CONFIG=/var/jenkins_config

ENV JENKINS_HOME $JENKINS_HOME
ENV JENKINS_SLAVE_AGENT_PORT ${agent_port}
ENV REF $REF
ENV ADMIN_USERNAME=admin
ENV ADMIN_PASSWORD=admin
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"
#ENV JENKINS_UC_DOWNLOAD="http://mirrors.jenkins-ci.org"


# Jenkins is run with user `jenkins`, uid = 1000
# If you bind mount a volume from the host or a data container,
# ensure you use the same uid
RUN mkdir -p $JENKINS_HOME \
  && chown -R ${uid}:${gid} $JENKINS_HOME \
  && chmod -R 777  $JENKINS_HOME \
  && groupadd -g ${gid} ${group} \
  && groupadd docker \
  && useradd -d "$JENKINS_HOME" -u ${uid} -g ${gid} -m -s /bin/bash ${user}


# Jenkins home directory is a volume, so configuration and build history
# can be persisted and survive image upgrades
VOLUME $JENKINS_HOME

# $REF (defaults to `/usr/share/jenkins/ref/`) contains all reference configuration we want
# to set on a fresh new installation. Use it to bundle additional plugins
# or config file with your custom jenkins Docker image.
RUN mkdir -p ${REF}/init.groovy.d

# $JENKINS_CONFIG (defaults to `/var/jenkins_config/`) contains the .yaml file the JCASC plugin uses to instantiate Jenkins with
RUN mkdir -p $JENKINS_CONFIG

# Use tini as subreaper in Docker container to adopt zombie processes
ARG TINI_VERSION=v0.16.1
COPY tini_pub.gpg ${JENKINS_HOME}/tini_pub.gpg
RUN curl -fsSL https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-static-$(dpkg --print-architecture) -o /sbin/tini \
  && curl -fsSL https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-static-$(dpkg --print-architecture).asc -o /sbin/tini.asc \
  && gpg --no-tty --import ${JENKINS_HOME}/tini_pub.gpg \
  && gpg --verify /sbin/tini.asc \
  && rm -rf /sbin/tini.asc /root/.gnupg \
  && chmod +x /sbin/tini
  
# Installs Docker Engine  
RUN sudo apt-get -o Acquire::ForceIPv4=true update \
&& sudo apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common \
&& curl -4fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add - \ 
&& sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
&& sudo apt-get -o Acquire::ForceIPv4=true update \
&& sudo apt-get install -y docker-ce-cli  

# jenkins version being bundled in this docker image
ARG JENKINS_VERSION
ENV JENKINS_VERSION ${JENKINS_VERSION:-2.278}

# jenkins.war checksum, download will be validated using it
ARG JENKINS_SHA=c0a477ece3651819346a76ae86382dc32309510ceb3f2f6713a5a4cf4f046957

# Can be used to customize where jenkins.war get downloaded from
ARG JENKINS_URL=https://repo.jenkins-ci.org/public/org/jenkins-ci/main/jenkins-war/${JENKINS_VERSION}/jenkins-war-${JENKINS_VERSION}.war

# could use ADD but this one does not check Last-Modified header neither does it allow to control checksum
# see https://github.com/docker/docker/issues/8331
RUN curl -fsSL ${JENKINS_URL} -o /usr/share/jenkins/jenkins.war \
  && echo "${JENKINS_SHA}  /usr/share/jenkins/jenkins.war" | sha256sum -c -

ENV JENKINS_UC https://updates.jenkins.io
ENV JENKINS_UC_EXPERIMENTAL=https://updates.jenkins.io/experimental
ENV JENKINS_INCREMENTALS_REPO_MIRROR=https://repo.jenkins-ci.org/incrementals
RUN chown -R ${user} "$JENKINS_HOME" "$REF"

# for main web interface:
EXPOSE ${http_port}

# will be used by attached slave agents:
EXPOSE ${agent_port}

ENV COPY_REFERENCE_FILE_LOG $JENKINS_HOME/copy_reference_file.log

USER root

ENV CASC_JENKINS_CONFIG=/var/jenkins_config/jenkins.yaml
COPY jenkins.yaml /var/jenkins_config/jenkins.yaml
COPY init-scripts /usr/share/jenkins/ref/init.groovy.d
COPY disable-script-security.groovy /usr/share/jenkins/ref/init.groovy.d/disable-script-security.groovy
COPY jenkins-support /usr/local/bin/jenkins-support
COPY jenkins.sh /usr/local/bin/jenkins.sh
COPY tini-shim.sh /bin/tini
COPY plugins.sh /usr/local/bin/plugins.sh
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
COPY install-plugins.sh /usr/local/bin/install-plugins.sh
COPY security.groovy /usr/share/jenkins/ref/init.groovy.d/security.groovy

# ensure shell scripts have unix line endings
RUN dos2unix -- /usr/local/bin/*.sh
RUN dos2unix -- /usr/local/bin/jenkins-support

RUN ["chmod", "+x", "/usr/local/bin/jenkins-support"]
RUN ["chmod", "+x", "/usr/local/bin/jenkins.sh"]
RUN ["chmod", "+x", "/usr/local/bin/plugins.sh"]
RUN ["chmod", "+x", "/usr/local/bin/install-plugins.sh"]

USER ${user}

RUN  /usr/local/bin/install-plugins.sh < /usr/share/jenkins/ref/plugins.txt

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/jenkins.sh"]

# from a derived Dockerfile, can use `RUN plugins.sh active.txt` to setup ${REF}/plugins from a support bundle
