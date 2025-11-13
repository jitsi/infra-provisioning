# EMQX Deployment Guide

Complete guide for deploying EMQX MQTT broker cluster on Oracle Cloud Infrastructure with Nomad orchestration.

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Phase 1: Infrastructure Deployment](#phase-1-infrastructure-deployment)
4. [Phase 2: Nomad Job Deployment](#phase-2-nomad-job-deployment)
5. [Phase 3: Verification & Testing](#phase-3-verification--testing)
6. [Configuration](#configuration)
7. [Scaling](#scaling)
8. [Monitoring](#monitoring)
9. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

### Components
- **N Instance Pools** of size 1 each (default: 3)
- **N Block Volumes** (150GB each, default: 3)
- **EMQX Cluster** with DNS-based discovery via Consul
- **Nomad Orchestration** with host volume mounts
- **Consul Service Discovery** for cluster formation

### Data Flow
1. Instances launch with `group-index` tags (0, 1, 2)
2. Volumes auto-attach by matching `group-index` to `volume-index`
3. Volumes mount to `/mnt/bv/emqx-{N}` and symlink to `/opt/nomad/data/emqx-{N}`
4. Nomad jobs use host volumes for persistent storage
5. EMQX nodes discover each other via Consul DNS (`emqx.service.consul`)
6. Cluster forms automatically using Erlang distribution

---

## Prerequisites

### Required
- Terraform >= 1.0
- Nomad CLI
- OCI CLI configured with appropriate credentials
- SSH access to OCI instances
- Network security group with EMQX ports open

### Network Requirements
Ensure security group allows:
- **1883**: MQTT (TCP, from clients)
- **8883**: MQTTS (TCP, from clients)
- **8083**: WebSocket (TCP, from clients)
- **8084**: WebSocket Secure (TCP, from clients)
- **18083**: Dashboard (TCP, internal only)
- **4370**: Erlang distribution (TCP, between EMQX nodes)
- **5370**: Cluster RPC (TCP, between EMQX nodes)

---

## Phase 1: Infrastructure Deployment

### Step 1: Create EMQX Volumes

Navigate to your environment directory (e.g., `terraform/prod-us-ashburn-1/`):

```bash
cd terraform/prod-us-ashburn-1/

# Create volumes configuration
cat > emqx-volumes.tf <<'EOF'
module "emqx_volumes" {
  source = "../volumes-emqx"

  tenancy_ocid     = var.tenancy_ocid
  compartment_ocid = var.compartment_ocid
  oracle_region    = var.oracle_region
  environment      = var.environment
  tag_namespace    = var.tag_namespace

  volume_count      = 3
  volume_size_in_gbs = 150
}
EOF

# Initialize and apply
terraform init
terraform plan -target=module.emqx_volumes
terraform apply -target=module.emqx_volumes
```

**Verify volumes created:**
```bash
oci bv volume list --compartment-id $COMPARTMENT_OCID \
  --display-name "emqx-volume-*" \
  --query 'data[*].{Name:"display-name", Size:"size-in-gbs", State:"lifecycle-state"}'
```

### Step 2: Create EMQX Instance Pool

```bash
# Create instance pool configuration
cat > emqx-instance-pool.tf <<'EOF'
module "emqx_instance_pool" {
  source = "../emqx-instance-pool"

  environment        = var.environment
  name              = "${var.environment}-${var.oracle_region}-emqx"
  oracle_region     = var.oracle_region
  availability_domains = var.availability_domains

  instance_pool_size   = 3
  instance_pool_name   = "${var.environment}-${var.oracle_region}-emqx-pool"
  instance_config_name = "${var.environment}-${var.oracle_region}-emqx-config"

  shape          = "VM.Standard.E4.Flex"
  ocpus         = 4
  memory_in_gbs = 16
  disk_in_gbs   = 50

  pool_subnet_ocid  = var.nat_subnet_ocid
  security_group_id = var.emqx_security_group_id
  image_ocid       = var.oracle_image_ocid

  user_public_key_path  = var.user_public_key_path
  user                 = "opc"
  user_private_key_path = var.user_private_key_path

  tenancy_ocid      = var.tenancy_ocid
  compartment_ocid  = var.compartment_ocid
  git_branch       = var.git_branch

  infra_configuration_repo  = var.infra_configuration_repo
  infra_customizations_repo = var.infra_customizations_repo

  resource_name_root       = "${var.environment}-${var.oracle_region}-emqx"
  vcn_name                = var.vcn_name
  postinstall_status_file = "/tmp/emqx-postinstall-${var.environment}.log"

  environment_type = var.environment_type
  tag_namespace   = var.tag_namespace

  volumes_enabled = true
}
EOF

# Apply infrastructure
terraform plan -target=module.emqx_instance_pool
terraform apply -target=module.emqx_instance_pool
```

**Verify instances created:**
```bash
# Check private IPs
terraform output -json | jq -r '.emqx_instance_pool.value.private_ips[]'

# SSH to verify volume mounting
ssh opc@<instance-ip>
ls -la /mnt/bv/emqx-*
ls -la /opt/nomad/data/emqx-*
```

### Step 3: Verify Nomad Registration

```bash
# Set Nomad address
export NOMAD_ADDR="https://$ENVIRONMENT-$ORACLE_REGION-nomad.example.com"

# Check nodes
nomad node status -filter 'Meta["pool_type"]=="emqx"'

# Verify node metadata
nomad node status <node-id> | grep -A 20 "Attributes"
```

Expected output should show:
- `meta.pool_type = emqx`
- `meta.group-index = 0` (or 1, 2)

---

## Phase 2: Nomad Job Deployment

### Option A: Using Deployment Script (Recommended)

```bash
cd scripts/

# Set environment
export ENVIRONMENT="prod"
export ORACLE_REGION="us-ashburn-1"

# Optional: Override defaults
export EMQX_VERSION="5.8.3"
export EMQX_COUNT="3"
export EMQX_CLUSTER_COOKIE="your-secure-random-cookie"

# Deploy
./deploy-nomad-emqx.sh
```

### Option B: Manual Deployment

```bash
export NOMAD_ADDR="https://prod-us-ashburn-1-nomad.example.com"

# Deploy job
sed -e "s/\[JOB_NAME\]/emqx-us-ashburn-1/" nomad/emqx.hcl | \
  nomad job run \
    -var="dc=prod-us-ashburn-1" \
    -var="emqx_version=5.8.3" \
    -var="emqx_count=3" \
    -var="emqx_cluster_cookie=your-secret-cookie" \
    -var="domain=example.com" \
    -
```

---

## Phase 3: Verification & Testing

### Step 1: Check Job Status

```bash
# Job status
nomad job status emqx-us-ashburn-1

# Check allocations
nomad job allocs emqx-us-ashburn-1

# View specific allocation
nomad alloc status <allocation-id>
```

### Step 2: Verify Cluster Formation

```bash
# Get allocation ID for node 0
ALLOC_ID=$(nomad job allocs emqx-us-ashburn-1 -json | jq -r '.[0].ID')

# Check cluster status
nomad alloc exec $ALLOC_ID emqx ctl cluster status

# Expected output:
# Cluster status: #{running_nodes => ['emqx@10.0.1.10','emqx@10.0.1.11','emqx@10.0.1.12'],
#                   stopped_nodes => []}
```

### Step 3: Check Consul Services

```bash
# Query Consul
dig +short emqx.service.consul

# Should return 3 IP addresses (one per node)
```

### Step 4: Test MQTT Connectivity

```bash
# Install MQTT client
pip install paho-mqtt

# Test connection
python3 <<EOF
import paho.mqtt.client as mqtt

def on_connect(client, userdata, flags, rc):
    print(f"Connected with result code {rc}")
    client.subscribe("test/topic")

def on_message(client, userdata, msg):
    print(f"{msg.topic}: {msg.payload.decode()}")

client = mqtt.Client()
client.on_connect = on_connect
client.on_message = on_message

# Connect to any EMQX node
client.connect("10.0.1.10", 1883, 60)
client.publish("test/topic", "Hello EMQX!")
client.loop_start()

import time
time.sleep(2)
client.loop_stop()
EOF
```

### Step 5: Access Dashboard

```bash
# Dashboard URL
echo "https://prod-us-ashburn-1-emqx.example.com/"

# Default credentials:
# Username: admin
# Password: public
# *** CHANGE IMMEDIATELY ***
```

Dashboard provides:
- Cluster overview
- Connected clients
- Message rates
- Topic statistics
- Configuration management

---

## Configuration

### EMQX Configuration via Environment Variables

The Nomad job accepts these variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `emqx_version` | `5.8.3` | EMQX Docker image version |
| `emqx_count` | `3` | Number of cluster nodes |
| `emqx_cluster_cookie` | random | Erlang cluster authentication cookie |
| `domain` | - | Domain for dashboard access |
| `dc` | - | Datacenter name |

### Host Volume Configuration

Each Nomad client must have host volumes configured:

```hcl
# /etc/nomad.d/client.hcl
client {
  enabled = true

  host_volume "emqx-0" {
    path      = "/opt/nomad/data/emqx-0"
    read_only = false
  }
  host_volume "emqx-1" {
    path      = "/opt/nomad/data/emqx-1"
    read_only = false
  }
  host_volume "emqx-2" {
    path      = "/opt/nomad/data/emqx-2"
    read_only = false
  }
}
```

**Note:** This is auto-configured by the instance pool's cloud-init.

---

## Scaling

### Scaling Up (Add Nodes)

1. **Update volume count:**
   ```bash
   cd terraform/prod-us-ashburn-1/

   # Edit emqx-volumes.tf
   # Change: volume_count = 5

   terraform apply -target=module.emqx_volumes
   ```

2. **Update instance pool size:**
   ```bash
   # Edit emqx-instance-pool.tf
   # Change: instance_pool_size = 5

   terraform apply -target=module.emqx_instance_pool
   ```

3. **Update Nomad job:**
   ```bash
   export EMQX_COUNT=5
   ./scripts/deploy-nomad-emqx.sh
   ```

4. **Verify new nodes joined:**
   ```bash
   nomad alloc exec <alloc-id> emqx ctl cluster status
   ```

### Scaling Down (Remove Nodes)

1. **Decrease Nomad job count first:**
   ```bash
   export EMQX_COUNT=3
   ./scripts/deploy-nomad-emqx.sh
   ```

2. **Wait for allocations to stop:**
   ```bash
   nomad job status emqx-us-ashburn-1
   ```

3. **Update infrastructure:**
   ```bash
   # Update both modules to new size
   terraform apply
   ```

---

## Monitoring

### Prometheus Metrics

EMQX exposes Prometheus metrics via the `emqx-metrics` service:

```bash
# Check metrics endpoint
curl http://<emqx-node-ip>:18083/api/v5/prometheus/stats
```

Add to Prometheus scrape config:
```yaml
scrape_configs:
  - job_name: 'emqx'
    consul_sd_configs:
      - server: 'localhost:8500'
        services: ['emqx-metrics']
    relabel_configs:
      - source_labels: [__meta_consul_service_metadata_node_index]
        target_label: emqx_node
```

### Key Metrics
- `emqx_client_connected`: Number of connected clients
- `emqx_messages_received`: Messages received rate
- `emqx_messages_sent`: Messages sent rate
- `emqx_messages_dropped`: Dropped messages
- `emqx_bytes_received`: Network traffic in
- `emqx_bytes_sent`: Network traffic out

### Health Checks

Consul automatically monitors:
- **MQTT Port**: TCP check on 1883
- **Dashboard**: HTTP check on `/api/v5/status`
- **Metrics**: HTTP check on `/api/v5/prometheus/stats`

---

## Troubleshooting

### Issue: Volumes Not Mounting

**Symptoms:**
- Instance starts but volume not at `/mnt/bv/emqx-N`
- EMQX fails to start with "permission denied" on `/opt/emqx/data`

**Debug:**
```bash
ssh opc@<instance-ip>

# Check cloud-init logs
sudo cat /var/log/cloud-init-output.log | grep -A 20 "mount_volume"

# Check for volume
sudo lsblk
sudo ls -la /mnt/bv/

# Check instance metadata
curl -s http://169.254.169.254/opc/v1/instance/ | jq '.freeformTags."group-index"'

# List available volumes
oci bv volume list --compartment-id $COMPARTMENT_OCID \
  --lifecycle-state AVAILABLE \
  | jq '.data[] | select(.["freeform-tags"]["volume-role"] == "emqx")'
```

**Solution:**
- Verify `volume-role=emqx` and `volume-index` tags match
- Check volume is in AVAILABLE state
- Ensure instance has correct `group-index` tag

### Issue: EMQX Nodes Not Clustering

**Symptoms:**
- Nodes start but remain isolated
- Dashboard shows single-node cluster

**Debug:**
```bash
# Check DNS resolution
dig +short emqx.service.consul

# Check from container
nomad alloc exec <alloc-id> nslookup emqx.service.consul

# View EMQX logs
nomad alloc logs <alloc-id> emqx | grep -i cluster

# Check Erlang distribution
nomad alloc exec <alloc-id> emqx ctl cluster status
```

**Solution:**
- Verify Consul service registration: `consul catalog services | grep emqx`
- Check network connectivity between nodes on port 4370
- Verify Erlang cookie matches across all nodes
- Check security group allows inter-node traffic

### Issue: High Memory Usage

**Symptoms:**
- EMQX pod OOMKilled
- Nomad shows memory above limit

**Debug:**
```bash
# Check resource usage
nomad alloc status <alloc-id>

# View EMQX memory stats
nomad alloc exec <alloc-id> emqx ctl status | grep memory
```

**Solution:**
```bash
# Increase memory in Nomad job
# Edit nomad/emqx.hcl, increase resources.memory

# Or scale horizontally (add nodes)
export EMQX_COUNT=5
./scripts/deploy-nomad-emqx.sh
```

### Issue: Cannot Access Dashboard

**Symptoms:**
- Dashboard URL returns 502/504
- Cannot connect to port 18083

**Debug:**
```bash
# Check service registration
consul catalog service emqx-dashboard

# Check Nomad allocation
nomad job status emqx-us-ashburn-1

# Test direct connection
curl http://<emqx-node-ip>:18083/api/v5/status

# Check Fabio routes (if using Fabio)
curl http://<fabio-ip>:9998/routes | grep emqx
```

**Solution:**
- Verify `int-urlprefix` tag in Consul service
- Check Fabio/load balancer configuration
- Ensure CNAME record created correctly

---

## Security Best Practices

1. **Change Default Credentials Immediately**
   - Dashboard default: `admin/public`
   - Change via dashboard or API

2. **Enable TLS for MQTT**
   - Configure certificates in EMQX
   - Use port 8883 for MQTTS

3. **Restrict Dashboard Access**
   - Limit security group to VPN/internal IPs only
   - Use authentication tokens for API access

4. **Rotate Erlang Cookie**
   - Use strong random value for `emqx_cluster_cookie`
   - Store securely (Vault, parameter store)

5. **Configure Authentication**
   - Enable built-in database or JWT auth
   - Set up ACLs for topic access control

---

## Files Created

### Terraform Modules
- `terraform/volumes-emqx/volumes-emqx.tf` - Block volume creation
- `terraform/emqx-instance-pool/emqx-instance-pool-stack.tf` - Instance pool
- `terraform/emqx-instance-pool/user-data/postinstall-runner-oracle.sh` - Cloud-init script
- `terraform/emqx-instance-pool/README.md` - Module documentation

### Nomad Jobs
- `nomad/emqx.hcl` - EMQX cluster job definition

### Scripts
- `scripts/deploy-nomad-emqx.sh` - Deployment automation

### Documentation
- `EMQX_DEPLOYMENT_GUIDE.md` - This file

---

## Additional Resources

- [EMQX Documentation](https://www.emqx.io/docs/en/latest/)
- [EMQX Clustering](https://www.emqx.io/docs/en/latest/deploy/cluster/intro.html)
- [MQTT 5.0 Specification](https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html)
- [Nomad Job Specification](https://www.nomadproject.io/docs/job-specification)
- [Consul Service Discovery](https://www.consul.io/docs/discovery/services)

---

## Support

For issues or questions:
1. Check Nomad allocation logs: `nomad alloc logs -job emqx-<region>`
2. Review EMQX logs via dashboard
3. Consult EMQX documentation
4. Check infrastructure repository issues
