# Oracle Infra Cookbooks
Steps to Configure a new Compartment in Oracle, together with one or several Regions 

## Pre-Requisites
Resources such as users, tags, either don't need a compartment, or use the root compartment. 
They should already exist in the cluster, but in case they don't, this is how to create them:

* Create tf-state-all bucket in root compartment, if it doesn't already exist
  * Eg. `oci os bucket create --region eu-frankfurt-1 --name tf-state-all -c ocid1.tenancy.oc1..aaaaaaaakxqd22zn5pin6sjgluadmjovlxqrd7sakqm2suiy3xkgg2bac3hq -ns fr4eeztjonbe --object-events-enabled false --versioning Enabled`
* Run https://jenkins.jitsi.net/job/provision-service-users-oracle/ to create users that are needed by AWS k8s services
* Create jitsi tag namespace (TBD whether this is the job https://jenkins.jitsi.net/job/create-defined-tags-for-a-new-compartment-oracle/)

## How To Configure A New Compartment

#### Create a new Compartment and associated Dynamic Groups, including Jibri and Recovery Agent Dynamic Group
* https://jenkins.jitsi.net/job/provision-compartment-oracle/
* wait for it ~10m to come up in the UI

#### Create general Policies
* https://jenkins.jitsi.net/job/create-main-policies-for-a-new-compartment-oracle/

#### Create Bucket to store Terraform states
* Needed for all terraform scripts which store the state, including `create-defined-tags.sh`
* run `oci os bucket create --region eu-frankfurt-1 --name tf-state-$COMPARTMENT_NAME -c $COMPARTMENT_OCID -ns fr4eeztjonbe --object-events-enabled false --versioning Enabled`
* Eg. `oci os bucket create --region eu-frankfurt-1 --name tf-state-beta-meet-jit-si -c ocid1.compartment.oc1..aaaaaaaacqopxrmhfagi2vuer2i737q7dvk3qtomrlwkhw3qpxsidjukympq -ns fr4eeztjonbe --object-events-enabled false --versioning Enabled`

## How To Configure A New Region Inside Compartment meet-jit-si

#### Enable the Lifecycle policies creation on Object Storage
* To execute object lifecycle policies, you must authorize the service to archive and delete objects on your behalf.
* Add in Policies, in {COMPARTMENT_NAME}-policy
    * `Allow service objectstorage-${REGION} to manage object-family in compartment ${COMPARTMENT_NAME}`
* Eg. `Allow service objectstorage-eu-frankfurt-1 to manage object-family in compartment beta-meet-jit-si`

#### Add the Policy for Jitsi Tag Editing in Root Tenancy Policies
* allow dynamic-group dev-8x8-dynamic-group to use tag-namespace in tenancy

#### create tf state bucket
Create a bucket called `tf-state-<environment>` at the top level.

#### Create Notifications in Application Integration
* Notifications:
    * Create email topic: `./environments/all/bin/terraform/topic-email/create-topic-email.sh`
    * Create pagerduty topic: `./environments/all/bin/terraform/topic-pagerduty/create-topic-pagerduty.sh`
    * Confirm the email subscriptions sent to meetings-ops
    
#### Create Object Storage Buckets and Lifecycle Policies
* run `create-buckets-oracle.sh`
* upload ssh key and vault password to `jvb-bucket-meet-jit-si`

#### Replace the Custom Secret Key - !! This step can be skipped, but it's worth keeping in case we'll need it again
* From Identity > Users, Go to Oana Ianc user, delete the key `Jenkins-S3 Access Key`
* Create a new key with name `Jenkins-S3 Access Key`
* Add the key id + value to Jenkins machine `/var/lib/jenkins/.aws/credentials`

#### Create a jitsi-video-infrastructure Branch With The New Region Configs. 
Add the following:
* `/environments/all/clouds/<oracle_region>-meet-jit-si-oracle.sh` - add the `COMPARTMENT_ID`

#### Networking
* Create VCN with a new CIRD block: https://jenkins.jitsi.net/job/provision-vcn-oracle/
* Add new regions to `stack-env.sh` in `DRG_PEER_REGIONS`, `RELEASE_CLOUDS`, and `CS_HISTORY_ORACLE_REGIONS`
* Add new regions to `vars.yaml` in `consul_wan_regions_oracle`

#### Add jitsi-video-infrastructure Branch Configs For The New Oracle Region
* Region: `/environments/all/regions/<oracle_region>-oracle.sh` and `./environments/all/regions/<aws-region>`
    * Add `ORACLE_REGION` variable
    * Identify the BARE image (Ubuntu 18.04) and update `DEFAULT_BARE_IMAGE_ID` for the new region to point to it (create a new instance and copy image ocid)
* Clouds: `/environments/all/clouds/<oracle_region>-meet-jit-si-oracle.sh`
* Network: `/environments/all/cloud-vpcs/<oracle_region>-meet-jit-si-oracle.sh`
* Maps: `/environments/all/group_vars/all.yml`
    * Configure the `oracle_to_aws_region_map` to contain the mapping for the new region
    * Configure the `oracle_to_recording_agent_region_map` to contain the mapping for the new region

#### Create A New Base Image From Branch
* https://jenkins.jitsi.net/job/jitsi-base-image-oracle/

#### create the vault password and id RSA for the VCN
* Download these objects: https://cloud.oracle.com/object-storage/buckets/fr4eeztjonbe/jvb-bucket-meet-jit-si/objects?region=eu-frankfurt-1
* Upload to a new `jvb-bucket-<compartment>` in the new region/compartment

#### Create A Jumpbox From Branch
* https://jenkins.jitsi.net/job/jitsi-create-jumpbox-oracle/

#### Configure jitsi-video-infrastructure Branch to Use The Jumpbox
* Add the DNS entry for the jumpbox in Route53 (use the jumpbox hostname)
* Update `ssh.config` to include the new cidr and jumpbox hostname `"${ORACLE_CLOUD_NAME}-ssh.oracle.infra.jitsi.net"`
* Only if the jumpbox was created via manual task (not from jenkins): add the jenkins key as authorized ssh key for user ubuntu
* From jenkins machine, do a ssh to the jumpbox, to add its host to known hosts

#### Merge the Branch in master

#### Create Wavefront Proxy From Branch
* https://jenkins.jitsi.net/job/provision-wavefront-proxy-oracle/
* Add the new proxy to wavefront_proxy_host_by_cloud map

#### Test The Branch By Creating A New JVB Image From Branch And A JVB Instance pool
* https://jenkins.jitsi.net/job/jitsi-videobridge-image-oracle/
    * JVB_VERSION e.g. 2.1-198-gb3d9736e (or 2.1-198-gb3d9736e-1)
    * BUILD_ID - can be standalone for now
* https://jenkins.jitsi.net/job/jitsi-deploy-jvb-oracle/
* https://jenkins.jitsi.net/job/jitsi-destroy-jvb-oracle/

#### Create/Update Jibri and Recovery agent Policies To Include new Region/Bucket
!!!!! Please note that this should probably be run only for new compartments, as the old compartments don't have the state saved. !!!!!
For existing compartments, the policies should be manually added
* https://jenkins.jitsi.net/job/provision-component-policies-oracle/

#### Create/Update Policies for k8s Services To Include New Region/Bucket
Usually only needed for 8x8 specific compartments (e.g. prod-8x8), but please check with the backend team
* https://jenkins.jitsi.net/job/provision-service-users-policies-oracle/

#### Set up network peering for the regions in the compartment
* Create a DRG for each region and add a route, run `ORACLE_REGION=<region> ENVIRONMENT=<compartment> scripts/create-drg-oracle.sh`
* For each region running shards and/or jvbs, run `ORACLE_REGION=<region> ENVIRONMENT=<compartment> scripts/link-drgs-oracle.sh`
* Build the ops network to all regions across the environment: `OPS_ENVIRONMENT=<ops-compartment> ORACLE_REGION=<ops-region> TARGET_ENVIRONMENTS=<target-compartment> scripts/link-ops-drgs-oracle.sh`

#### Create a Consul cluster for the environment/region
Consul is used as a source of truth for service discovery and configuration
information across our system. In OCI, there is a consul cluster per region per
environment. Clusters typically contain 3 servers. Each server is in its own OCI
instance pool in order to spread them across availability domains within the
region. These are not currently needed in coturn-only regions.

Services that consul tracks (as of July 2022):
* consul
* haproxy
* jigasi
* signal

The consul kv store is used to maintain dynamic information about:
* shard readiness state
* the latest signal node status reports
* which release is marked as GA/live for the environment
* which tenants are pinned and to what release

Make sure that `consul_wan_regions_oracle` is properly set in group_vars/all.yml
for the environment so that the inter-datacenter mesh is created. When a region
is added, existing consul clusters will need the new region's servers to be added
to their config via `consul-rotate`.

A consul cluster is provisioned for a new region/compartment using:
* https://jenkins.jitsi.net/job/provision-consul-oracle/

When a consul cluster needs a major update, the consul rotation job can be used
to replace the current instances with fresh ones. This should also be run for
all other consul clusters in the environment when a new region is added in order
to reconfigure them:
* https://jenkins.jitsi.net/job/consul-rotate/

When conducting an upgrade via `consul-rotate`, it is recommended to log into
all three consul servers and keep an eye on `consul members` and
`/var/log/consul.log` and especially to make sure that the cluster always has a
leader.

#### add a device42 instance to the environment/region

These are used for 8x8 inventory. From the environment directory for the new region, run, e.g.:
```ORACLE_REGION=eu-amsterdam-1 ../all/bin/terraform/device42-instance/create-device42-instance-oracle.sh```

#### add a rapid7 instance to the environment/region, if in stage-8x8 or prod-8x8

These are used for 8x8 to scan security. From the environment directory for the
new region, run, e.g.,
```ORACLE_REGION=eu-amsterdam-1 ../all/bin/terraform/rapid7-oracle/create-rapid7-stack-oracle.sh```

#### create haproxies to support shards

Before haproxies can be deployed, make sure that the new consul kv store has
been updated with the current live / GA release by running `set-live-release`
with the current release.

see README_HAPROXY.md for information about how to set up and manage haproxies. 

#### set up geo steering

`../all/bin/terraform/dns-steering-policy/dns-steering-policy.sh ubuntu`

Make sure `FALLBACK_REGION` is set to a region that exists in this environment;
it defaults to us-ashburn-1.
