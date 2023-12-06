# jitsi_autoscaler

<!-- Include a brief description of your pack -->

This pack is a simple Nomad job that runs as a service and can be accessed via
HTTP.

## Pack Usage

<!-- Include information about how to use your pack -->

Override variables when running for best effect

## Variables

<!-- Include information on the variables from your pack -->

- `count` (number:2) - The number of app instances to deploy
- `job_name` (string) - The name to use as the job name which overrides using
  the pack name
- `datacenters` (list of strings:["*"]) - A list of datacenters in the region which
  are eligible for task placement
- `region` (string) - The region where jobs will be deployed
- `register_service` (bool: true) - If you want to register a Nomad service
  for the job

[pack-registry]: https://github.com/jitsi/infra-provisioning.git//nomad/jitsi_packs
