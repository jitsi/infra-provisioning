def ReplicateImageOracle() {
    sh(
        script: """#!/bin/bash
        export FORCE_BUILD_IMAGE=true
        # copy new image to root tenancy
        export DEST_COMPARTMENT_USE_TENANCY="true"
        scripts/replicate-image-oracle.sh
        exit \$?"""
    )
}
def SetupOCI() {
    sh 'rm -rf ~/.oci'
    sh 'mkdir -p ~/.oci'
    sh 'cp "$OCI_CLI_CONFIG_FILE" ~/.oci/config'
    sh 'cp "$OCI_CLI_KEY_FILE" ~/.oci/private-key.pem'
}
def SetupAnsible() {
    sh 'echo "$ANSIBLE_VAULT_PASSWORD_PATH" > ./.vault-password.txt'
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
    echo checkOutput;
    return (checkOutput == 'skip');
}
return this