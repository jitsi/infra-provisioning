def replicateImageOracle() {
    sh(
        script: """#!/bin/bash
        export FORCE_BUILD_IMAGE=true
        # copy new image to root tenancy
        export DEST_COMPARTMENT_USE_TENANCY="true"
        scripts/replicate-image-oracle.sh
        exit \$?"""
    )
}
def setupOCI() {
    sh 'rm -rf ~/.oci'
    sh 'mkdir -p ~/.oci'
    sh 'cp "$OCI_CLI_CONFIG_FILE" ~/.oci/config'
    sh 'cp "$OCI_CLI_KEY_FILE" ~/.oci/private-key.pem'
}
def setupAnsible() {
    sh 'echo "$ANSIBLE_VAULT_PASSWORD_PATH" > ./.vault-password.txt'
}

return this