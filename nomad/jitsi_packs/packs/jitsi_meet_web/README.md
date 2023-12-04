# jitsi_meet_web

<!-- Include a brief description of your pack -->

This pack deploys jitsi-meet-web tagged with a release, to be paired with shard backends.

## Pack Usage

<!-- Include information about how to use your pack -->

### Changing the Message

To change the message this server responds with, change the "message" variable
when running the pack.

```
nomad-pack run jitsi_meet_web --var message="Hola Mundo!"
```

This tells Nomad Pack to tweak the `MESSAGE` environment variable that the
service reads from.

## Variables

<!-- Include information on the variables from your pack -->

- `job_name` (string) - The name to use as the job name which overrides using
  the pack name

[pack-registry]: https://github.com/jitsi/infra-provisioning/nomad-packs
