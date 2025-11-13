# EMQX Deployment Order - Infrastructure First Approach

## Overview

The EMQX deployment follows a specific order where the **OCI Load Balancer must be created BEFORE the instance pools**. This allows the instance pools to automatically register with the load balancer backend sets during creation.

## Architecture Pattern

This follows the same pattern as `jigasi-proxy`:
1. Create Load Balancer with Backend Sets
2. Create Instance Pools with `load_balancers` block referencing the backend sets
3. Instances automatically register/deregister as pool scales

## Deployment Steps

### Phase 1: Create Load Balancer Infrastructure

```bash
cd terraform/your-environment/

# 1. Create load balancer security group
cat > emqx-lb-security-group.tf <<'EOF'
module "emqx_lb_security_group" {
  source = "../emqx-load-balancer-security-group"

  resource_name_root = "${var.environment}-${var.oracle_region}-emqx"
  vcn_name          = var.vcn_name
  oracle_region     = var.oracle_region
  tenancy_ocid      = var.tenancy_ocid
  compartment_ocid  = var.compartment_ocid
}
EOF

terraform apply -target=module.emqx_lb_security_group

# 2. Create OCI Load Balancer (before instance pools!)
cat > emqx-load-balancer.tf <<'EOF'
module "emqx_load_balancer" {
  source = "../emqx-network-load-balancer"

  environment           = var.environment
  oracle_region         = var.oracle_region
  resource_name_root    = "${var.environment}-${var.oracle_region}-emqx"

  public_subnet_ocid    = var.public_subnet_ocid
  lb_security_group_id  = module.emqx_lb_security_group.security_group_id

  dns_name              = "mqtt.${var.domain}"
  dns_zone_name         = var.domain
  dns_compartment_ocid  = var.compartment_ocid

  tenancy_ocid      = var.tenancy_ocid
  compartment_ocid  = var.compartment_ocid
  environment_type  = var.environment_type
  tag_namespace     = var.tag_namespace
}
EOF

terraform apply -target=module.emqx_load_balancer

# Save outputs for next step
LB_ID=$(terraform output -json | jq -r '.emqx_load_balancer.value.lb_id')
MQTT_BACKEND_SET=$(terraform output -json | jq -r '.emqx_load_balancer.value.mqtt_backend_set_name')
```

### Phase 2: Create Block Volumes

```bash
# 3. Create volumes
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

terraform apply -target=module.emqx_volumes
```

### Phase 3: Create Instance Pools (with LB attachment)

```bash
# 4. Create EMQX instance pools with load balancer attachment
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

  # Load balancer attachment (critical!)
  load_balancer_id      = module.emqx_load_balancer.lb_id
  lb_backend_set_name   = module.emqx_load_balancer.mqtt_backend_set_name
  lb_backend_port       = 8080  # HAProxy health check port
}
EOF

terraform apply -target=module.emqx_instance_pool
```

### Phase 4: Deploy Nomad Jobs

```bash
# 5. Deploy EMQX cluster
export ENVIRONMENT="prod"
export ORACLE_REGION="us-ashburn-1"
export EMQX_COUNT=3
./scripts/deploy-nomad-emqx.sh

# 6. Wait for EMQX cluster to form
nomad job status emqx-us-ashburn-1
nomad alloc exec <alloc-id> emqx ctl cluster status

# 7. Deploy HAProxy on EMQX pool
./scripts/deploy-nomad-emqx-haproxy.sh

# 8. Verify HAProxy is running and healthy
nomad job status emqx-haproxy-us-ashburn-1
curl http://<emqx-node-ip>:8080/haproxy_health
```

### Phase 5: Verify Load Balancer Integration

```bash
# Check backend health in OCI
oci lb backend-health get \
  --load-balancer-id $LB_ID \
  --backend-set-name $MQTT_BACKEND_SET

# Test MQTT connectivity through load balancer
dig mqtt.example.com
mosquitto_pub -h mqtt.example.com -p 1883 -t test/topic -m "Hello EMQX!"
```

---

## Why This Order?

### 1. Load Balancer First
- Backend sets must exist before instance pools can reference them
- The `load_balancers` block in instance pool requires valid LB ID and backend set name
- Terraform will error if you try to create pools without existing backend sets

### 2. Volumes Before Pools
- Not strictly required, but logical
- Volumes can be created independently
- Instances will attach volumes during post-installation

### 3. Instance Pools with LB Attachment
- Each instance pool has a `load_balancers` block
- OCI automatically adds/removes instances as pool scales
- Health checks run on port 8080 (HAProxy admin endpoint)

### 4. Nomad Jobs After Infrastructure
- Infrastructure must be ready
- Instances must be running and registered in Nomad
- HAProxy job targets EMQX pool nodes
- EMQX services register with Consul for internal discovery

---

## Load Balancer Backend Architecture

### Backend Set Configuration

Each protocol has its own backend set:
- `emqx-mqtt-backend` → Port 1883 (MQTT)
- `emqx-mqtts-backend` → Port 8883 (MQTTS)
- `emqx-ws-backend` → Port 8083 (WebSocket)
- `emqx-wss-backend` → Port 8084 (WSS)

All backend sets:
- Health check on port 8080 (HAProxy `/haproxy_health`)
- Policy: `LEAST_CONNECTIONS`
- Protocol: TCP listeners forwarding to HAProxy

### Instance Pool Attachment

Each of the 3 instance pools attaches to **one backend set**:
```hcl
load_balancers {
  load_balancer_id = var.load_balancer_id
  backend_set_name = var.lb_backend_set_name  # e.g., "emqx-mqtt-backend"
  port             = 8080  # HAProxy health check port
  vnic_selection   = "PrimaryVnic"
}
```

**Important**: We only attach to the MQTT backend set because:
1. Health checks run on port 8080 (HAProxy admin)
2. HAProxy listens on all ports (1883, 8883, 8083, 8084)
3. Load balancer has separate listeners for each port
4. All listeners can use the same backend IPs
5. This avoids duplicate backend registrations

---

## Traffic Flow

```
Client → mqtt.example.com:1883
   ↓
OCI Load Balancer (Listener: 1883)
   ↓
Backend Set: emqx-mqtt-backend
   ↓
Instance Pool Backends (3x EMQX nodes)
   ↓
HAProxy on EMQX Node (:1883)
   ↓
EMQX on same node (:1883)
```

---

## Scaling Workflow

When scaling from 3 to 5 nodes:

```bash
# 1. Add volumes
# Edit: volume_count = 5
terraform apply -target=module.emqx_volumes

# 2. Scale instance pool
# Edit: instance_pool_size = 5
terraform apply -target=module.emqx_instance_pool

# 3. OCI automatically:
#    - Creates 2 new instance pools (pool-3, pool-4)
#    - Launches instances in new pools
#    - Registers new instances to LB backend set
#    - Starts health checks on port 8080

# 4. Update Nomad jobs
export EMQX_COUNT=5
./scripts/deploy-nomad-emqx.sh
./scripts/deploy-nomad-emqx-haproxy.sh

# 5. Verify
nomad job status emqx-us-ashburn-1
oci lb backend-health list \
  --load-balancer-id $LB_ID \
  --backend-set-name $MQTT_BACKEND_SET
```

---

## Multi-Backend-Set Alternative (Not Recommended)

If you wanted each instance pool to attach to **all 4 backend sets**, you would need:

```hcl
# Instance pool with multiple LB attachments
resource "oci_core_instance_pool" "oci_instance_pool" {
  # ... other config ...

  load_balancers {
    load_balancer_id = var.load_balancer_id
    backend_set_name = "emqx-mqtt-backend"
    port             = 1883
    vnic_selection   = "PrimaryVnic"
  }

  load_balancers {
    load_balancer_id = var.load_balancer_id
    backend_set_name = "emqx-mqtts-backend"
    port             = 8883
    vnic_selection   = "PrimaryVnic"
  }

  # ... repeat for ws and wss ...
}
```

**Why we don't do this:**
- Requires 4x backend registrations per instance
- More complex health checking
- Same backends serve all ports anyway (via HAProxy)
- No performance benefit
- Creates unnecessary OCI API load

---

## Troubleshooting

### Backends Not Registering

```bash
# Check instance pool has load_balancers block
terraform state show module.emqx_instance_pool.oci_core_instance_pool.oci_instance_pool[0]

# Verify load balancer ID is correct
echo $LB_ID

# Check backend set name
terraform output -json | jq -r '.emqx_load_balancer.value.mqtt_backend_set_name'
```

### Health Checks Failing

```bash
# SSH to EMQX node
ssh opc@<node-ip>

# Check HAProxy is running
nomad job status emqx-haproxy-us-ashburn-1

# Test health endpoint
curl http://localhost:8080/haproxy_health

# Check HAProxy stats
curl http://localhost:8080/haproxy_stats
```

### Wrong Deployment Order

If you created instance pools before load balancer:

```bash
# Destroy instance pools
terraform destroy -target=module.emqx_instance_pool

# Create load balancer
terraform apply -target=module.emqx_load_balancer

# Recreate instance pools with LB attachment
terraform apply -target=module.emqx_instance_pool
```

---

## Summary

**Correct Order:**
1. Load Balancer Security Group
2. **OCI Load Balancer** (creates backend sets)
3. Block Volumes
4. **Instance Pools** (with `load_balancers` block)
5. Nomad EMQX Job
6. Nomad HAProxy Job

**Key Point:** The load balancer must exist with its backend sets defined **before** creating the instance pools, so that the pools can automatically attach to the backend sets during creation.
