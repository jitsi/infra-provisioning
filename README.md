# infra-provisioning
Scripts for provisioning cloud resources for jitsi services

# requirements
terraform 1.2.7
jq
yq 4

# ops-agent
The docker container aaronkvanmeerten/ops-agent is used by jenkins to run all jenkins jobs.
To run it locally, you can run:

`scripts/local-ops-agent.sh`

This assumes that local codebase exists in ~/dev and mounts it in /home/jenkins, but this can be customized via `LOCAL_DEV_DIR`.
