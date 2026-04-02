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

def getRpTicket() {
    return env.RP_TICKET ?: ''
}

return this
