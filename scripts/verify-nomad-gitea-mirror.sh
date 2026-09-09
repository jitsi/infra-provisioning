#!/bin/bash
# Verifies a deployed Gitea mirror the way a booting VM would: the credential
# from the environment's boot bucket, against EACH replica directly (replicas
# have independent databases, so the Fabio hostname only ever tests one).
# Usage: ENVIRONMENT=stage-8x8 ORACLE_REGION=us-phoenix-1 scripts/verify-nomad-gitea-mirror.sh
# Exits non-zero if any check fails on any replica. See JIT-16092.
[ -z "$ENVIRONMENT" ] && { echo "No ENVIRONMENT set"; exit 2; }
[ -z "$ORACLE_REGION" ] && { echo "No ORACLE_REGION set"; exit 2; }
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"
[ -z "$NOMAD_ADDR" ] && export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.jitsi.net"
[ -z "$JOB" ] && JOB="gitea-mirror-$ORACLE_REGION"
[ -z "$PRIVATE_REPO" ] && PRIVATE_REPO="infra-customizations-private"
[ -z "$PUBLIC_REPO" ] && PUBLIC_REPO="infra-provisioning"
H=$(mktemp -d); trap 'rm -rf "$H"' EXIT
oci os object get -bn "jvb-bucket-$ENVIRONMENT" --region "$ORACLE_REGION" --name gitea-read-user --file "$H/c.json" >/dev/null 2>&1 \
  || { echo "no gitea-read-user in jvb-bucket-$ENVIRONMENT ($ORACLE_REGION); run publish-gitea-read-user-bucket.sh"; exit 1; }
U=$(jq -r .username "$H/c.json"); P=$(jq -r .password "$H/c.json"); rm -f "$H/c.json"
echo "$ENVIRONMENT $ORACLE_REGION, credential user $U"
RET=0
for a in $(nomad job allocs -json "$JOB" | jq -r '.[] | select(.ClientStatus=="running") | .ID'); do
  addr=$(nomad alloc status -json "$a" | jq -r '.AllocatedResources.Shared.Ports[] | select(.Label=="http") | "\(.HostIP):\(.Value)"')
  health=$(nomad alloc status -json "$a" | jq -r '.AllocatedResources.Shared.Ports[] | select(.Label=="health") | "\(.HostIP):\(.Value)"')
  echo "== ${a:0:8} on $(nomad alloc status -json "$a" | jq -r .NodeName) at $addr"
  printf '  anonymous private API (want 404): %s\n' "$(curl -s -m 10 -o /dev/null -w '%{http_code}' "http://$addr/api/v1/repos/jitsi/$PRIVATE_REPO")"
  rm -rf "$H/anon"; if GIT_TERMINAL_PROMPT=0 git clone -q "http://$addr/jitsi/$PRIVATE_REPO.git" "$H/anon" >/dev/null 2>&1; then echo "  anonymous private clone:          SUCCEEDED (BAD)"; RET=1; else echo "  anonymous private clone:          refused (good)"; fi
  printf 'machine %s login %s password %s\n' "${addr%%:*}" "$U" "$P" > "$H/.netrc"; chmod 600 "$H/.netrc"
  rm -rf "$H/priv"; if HOME="$H" GIT_TERMINAL_PROMPT=0 git clone -q "http://$addr/jitsi/$PRIVATE_REPO.git" "$H/priv" >/dev/null 2>&1; then echo "  netrc private clone:              ok ($(git -C "$H/priv" rev-parse --short HEAD))"; else echo "  netrc private clone:              FAILED"; RET=1; fi
  rm -rf "$H/pub"; if GIT_TERMINAL_PROMPT=0 git clone -q --depth 1 "http://$addr/jitsi/$PUBLIC_REPO.git" "$H/pub" >/dev/null 2>&1; then echo "  anonymous public clone:           ok"; else echo "  anonymous public clone:           FAILED"; RET=1; fi
  if [ -d "$H/priv" ]; then (cd "$H/priv" && git -c user.email=x@y -c user.name=x commit -q --allow-empty -m x >/dev/null 2>&1 && HOME="$H" git push -q origin HEAD:refs/heads/verify-push-test >/dev/null 2>&1) && { echo "  netrc push (want refused):        SUCCEEDED (BAD)"; RET=1; } || echo "  netrc push (want refused):        refused (good)"; fi
  echo "  gate ready=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://$health/ready")  $(curl -s -m 5 "http://$health/metrics" | grep 'read_access{' | tr '\n' ' ')"
done
exit $RET
