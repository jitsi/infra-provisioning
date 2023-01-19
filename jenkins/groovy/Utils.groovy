def ReplicateImageOracle(image_type) {
    sh(
        script: """#!/bin/bash
        export FORCE_BUILD_IMAGE=true
        export IMAGE_TYPE="${image_type}"
        # copy new image to root tenancy
        export DEST_COMPARTMENT_USE_TENANCY="true"
        scripts/replicate-image-oracle.sh
        exit \$?"""
    )
}
def SetupOCI() {
    withCredentials([
        file(credentialsId: 'oci-jenkins-config', variable: 'OCI_CLI_CONFIG_FILE'),
        file(credentialsId: 'oci-jenkins-pem', variable: 'OCI_CLI_KEY_FILE')
    ]) {
        sh 'rm -rf ~/.oci'
        sh 'mkdir -p ~/.oci'
        sh 'cp "$OCI_CLI_CONFIG_FILE" ~/.oci/config'
        sh 'cp "$OCI_CLI_KEY_FILE" ~/.oci/private-key.pem'
    }
}
def SetupAnsible() {
    withCredentials([
        string(credentialsId: 'ansible-vault-password', variable: 'ANSIBLE_VAULT_PASSWORD_PATH'),
    ]) {
        sh 'echo "$ANSIBLE_VAULT_PASSWORD_PATH" > ./.vault-password.txt'
    }
}
def CheckSkipBuild(image_type, environment) {
    echo "checking for existing images before building, FORCE_BUILD_IMAGE is ${env.FORCE_BUILD_IMAGE}"
    def checkOutput = sh(
        returnStdout: true,
        script: """#!/bin/bash
        export IMAGE_TYPE="${image_type}"
        export CLOUDS=\$(scripts/release_clouds.sh ${environment})
        SKIP_BUILD=false
        if [[ "\$FORCE_BUILD_IMAGE" != "true" ]]; then
            scripts/check-build-oracle-image-for-clouds.sh 1>&2 && SKIP_BUILD=true
        fi
        if \$SKIP_BUILD; then
            echo 'skip'
        fi"""
    ).trim()
    // echo checkOutput;
    return (checkOutput == 'skip');
}

def SetupRepos() {
  sshagent (credentials: ['video-infra']) {
      def scmUrl = scm.getUserRemoteConfigs()[0].getUrl()
      dir('infra-provisioning') {
          git branch: env.VIDEO_INFRA_BRANCH, url: scmUrl, credentialsId: 'video-infra'
      }
      dir('infra-configuration') {
          checkout([$class: 'GitSCM', branches: [[name: "origin/${VIDEO_INFRA_BRANCH}"]], extensions: [[$class: 'SubmoduleOption', disableSubmodules: false, parentCredentials: false, recursiveSubmodules: true, reference: '', trackingSubmodules: false]], userRemoteConfigs: [[credentialsId: 'video-infra', url: env.INFRA_CONFIGURATION_REPO]]])
          SetupAnsible()
      }
      dir('infra-customization') {
          git branch: env.VIDEO_INFRA_BRANCH, url: env.INFRA_CUSTOMIZATIONS_REPO, credentialsId: 'video-infra'
      }
      sh 'cp -a infra-customization/* infra-configuration'
      sh 'cp -a infra-customization/* infra-provisioning'
  }
}


return this