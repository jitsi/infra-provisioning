// CI/CD governance hooks — no-op stub.
// The real implementation lives in infra-customizations and is
// overlaid via `cp -a` during SetupRepos().

def PreDeployHook(Map config) {
    echo "GovernanceHooks PreDeployHook: no implementation present"
    return null
}

def PostDeployHook(Map config, boolean success) {
    echo "GovernanceHooks PostDeployHook: no implementation present"
    return null
}

def PreReleaseHook(Map config) {
    echo "GovernanceHooks PreReleaseHook: no implementation present"
    return null
}

def PostReleaseHook(Map config, boolean success) {
    echo "GovernanceHooks PostReleaseHook: no implementation present"
    return null
}

@com.cloudbees.groovy.cps.NonCPS
def ExtractRpTicket(String gateResultJson) {
    return null
}

return this