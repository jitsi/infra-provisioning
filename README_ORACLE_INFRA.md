# Oracle Infra Cookbooks
Steps to Configure a new Compartment in Oracle, together with one or several
Regions. This is provided as rough guidance and changes may be required for your
own configuration purposes.

## Pre-Requisites
Resources such as users, tags, either don't need a compartment, or use the root
compartment. They should already exist in the tenancy, but in case they don't,
this is how to create them:

* Create tf-state-all bucket in root compartment, if it doesn't already exist
  * Eg. `oci os bucket create --region eu-frankfurt-1 --name tf-state-all -c $COMPARTMENT_OCID -ns $OCI_NAMESPACE --object-events-enabled false --versioning Enabled`
* Create jitsi tag namespace with the `create-defined-tags-for-a-new-compartment-oracle` Jenkins job.

## How To Configure A New Compartment
#### Create a new Compartment and associated Dynamic Groups, including Jibri and Recovery Agent Dynamic Group
* Run the `provision-compartment-oracle` Jenkins job then wait for it ~10m to come up in the UI

#### Create general Policies
* Run the `create-main-policies-for-a-new-compartment-oracle` job.

#### Create Bucket to store Terraform states
* Needed for all terraform scripts which store the state, including `create-defined-tags.sh`
* run `oci os bucket create --region eu-frankfurt-1 --name tf-state-$COMPARTMENT_NAME -c $COMPARTMENT_OCID -ns $OCI_NAMESPACE--object-events-enabled false --versioning Enabled`

## How To Configure A New Region Inside Compartment meet-jit-si

#### Enable the Lifecycle policies creation on Object Storage
* To execute object lifecycle policies, you must authorize the service to archive and delete objects on your behalf.
* Add in Policies, in {COMPARTMENT_NAME}-policy
    * `Allow service objectstorage-${REGION} to manage object-family in compartment ${COMPARTMENT_NAME}`

#### create tf state bucket
Create a bucket called `tf-state-<compartment-name>` at the top level for compartment terraform state

#### Create Notifications in Application Integration
* Notifications:
    * Create email topic: `terraform/topic-email/create-topic-email.sh`
    * Create pagerduty topic: `terraform/topic-pagerduty/create-topic-pagerduty.sh`
    * Confirm the email subscriptions sent to meetings-ops
    
#### Create Object Storage Buckets and Lifecycle Policies
* run `scripts/create-buckets-oracle.sh`
* upload ssh key and vault password to `jvb-bucket-<compartment_name>`

#### Create a jitsi-video-infrastructure Branch With The New Region Configs. 
Add the following:
* `<customization_repo>/clouds/<oracle_region>-<compartment_name>` - add the `COMPARTMENT_ID`

#### Networking
* Create VCN with a new CIRD block with the provision-vcn-oracle job
* Add new regions to `stack-env.sh` in `DRG_PEER_REGIONS`, `RELEASE_CLOUDS`, and `CS_HISTORY_ORACLE_REGIONS`
* Add new regions to `vars.yml` in `consul_wan_regions_oracle`

#### Add jitsi-video-infrastructure Branch Configs For The New Oracle Region
* Region: `<customization_repo>/regions/<oracle_region>-oracle.sh` and `<customization_repo>/regions/<aws-region>`
    * Add `ORACLE_REGION` variable
    * Identify the BARE image (e.g., Ubuntu 22.04) and update `DEFAULT_BARE_IMAGE_ID` for the new region to point to it (create a new instance and copy image ocid)
* Clouds: `<customization_repo>/clouds/<oracle_region>-<compartment_name>`
* Network: `<customization_repo>/cloud-vpcs/<oracle_region>-<compartment_name>`
* Maps: `<customization_repo>/config/vars.yml`
    * Configure the `oracle_to_aws_region_map` to contain the mapping for the new region
    * Configure the `oracle_to_recording_agent_region_map` to contain the mapping for the new region

#### Create A New Base Image From Branch
* Run the `build-image-oracle` job

#### create the vault password and id RSA for the VCN
* Upload your RSA key `id_rsa_jitsi_deployment` and your `vault-password` to `jvb-bucket-<compartment_name>`

#### Create A Jumpbox From Branch
* Run the `provision-jumpbox` job. Alternately, you will be using a VPN for access.

#### Configure jitsi-video-infrastructure Branch to Use The Jumpbox
* Add the DNS entry for the jumpbox in Route53 (use the jumpbox hostname)
* Update `ssh.config` to include the new cidr and jumpbox hostname `"${ORACLE_CLOUD_NAME}-ssh.oracle.${INFRA_DOMAIN}"`
* From jenkins machine, do a ssh to the jumpbox, to add its host to known hosts

#### Merge the Branch in master

#### Create Wavefront Proxy From Branch
* Run the `provision-wavefront-proxy-oracle` job.
* Add the new proxy to the `wavefront_proxy_host_by_cloud` map

#### Test The Branch By Creating A New JVB Image From Branch And A JVB Instance pool
* Test JVB deployment with `provision-jvb-pool`
* Destroy the JVB after test with `destroy-jvb-pool`

#### Create/Update Jibri and Recovery agent Policies To Include new Region/Bucket
!!!!! Please note that this should probably be run only for new compartments, as the old compartments don't have the state saved. !!!!!
For existing compartments, the policies should be manually added
* Run the `provision-component-policies-oracle` job

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

#### create haproxies to support shards

Before haproxies can be deployed, make sure that the new consul kv store has
been updated with the current live / GA release by running `set-live-release`
with the current release.

see README_HAPROXY.md for information about how to set up and manage haproxies. 

#### set up geo steering
`terraform/dns-steering-policy/dns-steering-policy.sh ubuntu`

Make sure `FALLBACK_REGION` is set to a region that exists in this environment;
it defaults to us-ashburn-1.
