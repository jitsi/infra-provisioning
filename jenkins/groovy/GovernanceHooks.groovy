// GovernanceHooks.groovy — no-op governance hook stubs.
// Override in infra-customizations to integrate with a governance provider.
// Overlaid via cp -a during SetupRepos().

def init(Map opts) {
    echo "GovernanceHooks: no governance provider configured (init)"
    return [:]
}

def preRelease(Map artConfig) {
    echo "GovernanceHooks: no governance provider configured (preRelease)"
}

def preDeploy(Map artConfig) {
    echo "GovernanceHooks: no governance provider configured (preDeploy)"
}

def postHooks(Map artConfig, boolean success) {
    echo "GovernanceHooks: no governance provider configured (postHooks)"
}

// Deploy-only gates, for jobs that redeploy or replace running infrastructure
// without cutting a new release (e.g. the rotate-* jobs). Paired with
// postDeployOnly; skips the release gates entirely.
def preDeployOnly(Map artConfig) {
    echo "GovernanceHooks: no governance provider configured (preDeployOnly)"
}

def postDeployOnly(Map artConfig, boolean success) {
    echo "GovernanceHooks: no governance provider configured (postDeployOnly)"
}

def loadLibrary() {
    echo "GovernanceHooks: no governance provider configured (loadLibrary)"
}

def loadCredentials(credentialId = '') {
    echo "GovernanceHooks: no governance provider configured (loadCredentials)"
}

def getRpTicket() {
    return env.RP_TICKET ?: ''
}

return this
