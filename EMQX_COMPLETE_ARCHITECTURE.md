# EMQX Complete Architecture - Nomad + OCI Load Balancer

Complete architecture for EMQX MQTT broker cluster with HAProxy load balancing and OCI Load Balancer front-end.

## Architecture Overview

```
Internet
    |
    v
[OCI Load Balancer] (TCP: 1883, 8883, 8083, 8084)
    |
    v
[HAProxy x3] (Nomad jobs on EMQX pool, fixed ports)
    |
    v
[EMQX Cluster x3] (Nomad jobs on EMQX pool, Consul DNS discovery)
    |
    v
[Persistent Volumes x3] (150GB block storage per node)
```

## Components

### 1. Infrastructure Layer (Terraform)

#### A. **EMQX Instance Pool** (`terraform/emqx-instance-pool/`)
- **N instance pools of size 1** (default: 3)
- Each instance tagged with unique `group-index` (0, 1, 2)
- Pool type: `emqx`
- Role: `emqx`
- Distributed across availability domains

#### B. **Block Volumes** (`terraform/volumes-emqx/`)
- 3x 150GB high-performance volumes
- Tagged with `volume-role=emqx`, `volume-index={0,1,2}`
- Auto-attach via `group-index` matching
- Mounted to `/mnt/bv/emqx-{N}` → `/opt/nomad/data/emqx-{N}`

#### C. **Load Balancer Security Group** (`terraform/emqx-load-balancer-security-group/`)
- Ingress: 1883 (MQTT), 8883 (MQTTS), 8083 (WS), 8084 (WSS)
- Egress: All allowed

#### D. **OCI Load Balancer** (`terraform/emqx-network-load-balancer/`)
- Public-facing Layer 4 load balancer
- TCP protocol for all ports
- 4 backend sets (one per protocol/port)
- Backends point to HAProxy instances (via EMQX node IPs)
- Health checks on TCP ports
- DNS A record for public access

### 2. Application Layer (Nomad)

#### A. **EMQX Cluster** (`nomad/emqx.hcl`)
- 3 dynamic groups (one per node)
- Constraints:
  - `pool_type = emqx`
  - `group-index = {0,1,2}` (pinned to specific nodes)
- Ports: 1883, 8883, 8083, 8084, 18083, 4370, 5370
- Volume mounts: `/opt/emqx/data` → host volume `emqx-{N}`
- Clustering: DNS-based via Consul (`emqx.service.consul`)
- Services registered:
  - `emqx` (MQTT)
  - `emqx-tls` (MQTTS)
  - `emqx-ws` (WebSocket)
  - `emqx-dashboard`
  - `emqx-metrics` (Prometheus)

#### B. **HAProxy Load Balancer** (`nomad/emqx-haproxy.hcl`)
- 3 instances (one per EMQX node)
- Constraint: `pool_type = emqx`, `distinct_hosts = true`
- Fixed ports: 1883, 8883, 8083, 8084, 8080 (admin)
- Backends: Consul DNS (`{env}.emqx.service.consul`)
- Load balancing: `leastconn` for MQTT protocols
- Health check endpoint: `:8080/haproxy_health`
- Service: `emqx-haproxy`

### 3. Deployment Scripts

#### A. **EMQX Cluster** (`scripts/deploy-nomad-emqx.sh`)
```bash
export ENVIRONMENT="prod"
export ORACLE_REGION="us-ashburn-1"
export EMQX_COUNT=3
./scripts/deploy-nomad-emqx.sh
```

#### B. **HAProxy** (`scripts/deploy-nomad-emqx-haproxy.sh`)
```bash
export ENVIRONMENT="prod"
export ORACLE_REGION="us-ashburn-1"
./scripts/deploy-nomad-emqx-haproxy.sh
```

---

## Traffic Flow

### MQTT Connection Example

1. **Client** → `mqtt.example.com:1883` (DNS A record)
2. **OCI Load Balancer** → Receives on `:1883`, selects backend
3. **HAProxy (on EMQX node)** → Receives on `:1883`, load balances to EMQX
4. **EMQX Node** → Processes MQTT connection on `:1883`
5. **Persistent Session** → Stored in `/opt/emqx/data` (block volume)

### Cluster Communication

1. **EMQX Node starts** → Registers with Consul as `emqx.service.consul`
2. **Cluster Discovery** → Queries `emqx.service.consul` via DNS
3. **Erlang Distribution** → Connects on port 4370
4. **Cluster Formation** → All nodes join cluster
5. **Data Replication** → Sessions and messages replicated

---

## Deployment Order

### Phase 1: Infrastructure (Terraform)

```bash
cd terraform/your-environment/

# 1. Create volumes
cat > emqx-volumes.tf <<'EOF'
module "emqx_volumes" {
  source = "../volumes-emqx"

  tenancy_ocid     = var.tenancy_ocid
  compartment_ocid = var.compartment_ocid
  oracle_region    = var.oracle_region
  environment      = var.environment

  volume_count      = 3
  volume_size_in_gbs = 150
}
EOF

terraform apply -target=module.emqx_volumes

# 2. Create instance pool
cat > emqx-instance-pool.tf <<'EOF'
module "emqx_instance_pool" {
  source = "../emqx-instance-pool"

  environment        = var.environment
  name              = "${var.environment}-${var.oracle_region}-emqx"
  instance_pool_size = 3
  # ... other variables
}
EOF

terraform apply -target=module.emqx_instance_pool

# 3. Create load balancer security group
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

# 4. Get instance pool IDs for load balancer
# The load balancer will need the first instance pool ID to discover backends

# 5. Create OCI load balancer (after EMQX + HAProxy are deployed)
cat > emqx-load-balancer.tf <<'EOF'
module "emqx_load_balancer" {
  source = "../emqx-network-load-balancer"

  environment           = var.environment
  resource_name_root    = "${var.environment}-${var.oracle_region}-emqx"
  public_subnet_ocid    = var.public_subnet_ocid
  lb_security_group_id  = module.emqx_lb_security_group.security_group_id
  emqx_instance_pool_id = module.emqx_instance_pool.instance_pool_ids[0]

  dns_name              = "mqtt.${var.domain}"
  dns_zone_name         = var.domain
  dns_compartment_ocid  = var.compartment_ocid

  # ... other variables
}
EOF

# Deploy load balancer AFTER Nomad jobs are running
# terraform apply -target=module.emqx_load_balancer
```

### Phase 2: Nomad Applications

```bash
# 1. Deploy EMQX cluster
export ENVIRONMENT="prod"
export ORACLE_REGION="us-ashburn-1"
export EMQX_COUNT=3
./scripts/deploy-nomad-emqx.sh

# 2. Wait for cluster to form
nomad job status emqx-us-ashburn-1
nomad alloc exec <alloc-id> emqx ctl cluster status

# 3. Deploy HAProxy
./scripts/deploy-nomad-emqx-haproxy.sh

# 4. Verify HAProxy backends
nomad job status emqx-haproxy-us-ashburn-1
curl http://<emqx-node-ip>:8080/haproxy_stats
```

### Phase 3: Load Balancer

```bash
# Deploy OCI Load Balancer pointing to HAProxy instances
cd terraform/your-environment/
terraform apply -target=module.emqx_load_balancer

# Verify DNS and connectivity
dig mqtt.example.com
mosquitto_pub -h mqtt.example.com -p 1883 -t test/topic -m "Hello"
```

---

## Port Reference

| Port  | Protocol | Component | Purpose |
|-------|----------|-----------|---------|
| 1883  | MQTT     | EMQX/HAProxy/LB | MQTT TCP |
| 8883  | MQTTS    | EMQX/HAProxy/LB | MQTT over TLS |
| 8083  | WS       | EMQX/HAProxy/LB | WebSocket |
| 8084  | WSS      | EMQX/HAProxy/LB | WebSocket Secure |
| 18083 | HTTP     | EMQX | Dashboard (internal) |
| 4370  | TCP      | EMQX | Erlang distribution |
| 5370  | TCP      | EMQX | Cluster RPC |
| 8080  | HTTP     | HAProxy | Admin/stats/health |

---

## High Availability Features

### Node Failure Scenarios

#### EMQX Node Fails
1. Consul health check fails
2. HAProxy marks backend as down
3. New connections routed to healthy nodes
4. Existing sessions: clients reconnect to new node
5. **Data**: Persisted on block volume, survives node restart

#### HAProxy Instance Fails
1. OCI LB health check fails (port 8080 down)
2. OCI LB removes backend from rotation
3. Traffic routed to remaining 2 HAProxy instances
4. **No EMQX impact**: EMQX cluster still healthy

#### Availability Domain Outage
1. All instances in AD become unreachable
2. OCI LB health checks fail for that AD
3. Traffic routed to remaining ADs
4. EMQX cluster continues with reduced capacity
5. **Auto-recovery**: When AD recovers, nodes rejoin cluster

### Load Balancing Algorithms

- **OCI Load Balancer**: 5-tuple hash (source IP, dest IP, source port, dest port, protocol)
- **HAProxy**: Least connections (`leastconn`) - optimal for long-lived MQTT connections
- **EMQX Cluster**: Session distribution via consistent hashing

---

## Scaling Guide

### Vertical Scaling (More Resources)

```bash
# Edit instance pool module
# Change: ocpus = 8, memory_in_gbs = 32
terraform apply -target=module.emqx_instance_pool
```

### Horizontal Scaling (More Nodes)

```bash
# 1. Increase volume count
# Edit: volume_count = 5
terraform apply -target=module.emqx_volumes

# 2. Increase instance pool size
# Edit: instance_pool_size = 5
terraform apply -target=module.emqx_instance_pool

# 3. Update Nomad jobs
export EMQX_COUNT=5
./scripts/deploy-nomad-emqx.sh
./scripts/deploy-nomad-emqx-haproxy.sh

# 4. Verify cluster
nomad alloc exec <alloc-id> emqx ctl cluster status
```

---

## Monitoring & Observability

### Prometheus Metrics

EMQX exposes metrics via `emqx-metrics` service:

```yaml
scrape_configs:
  - job_name: 'emqx'
    consul_sd_configs:
      - server: 'localhost:8500'
        services: ['emqx-metrics']
    metrics_path: '/api/v5/prometheus/stats'
```

### HAProxy Stats

```bash
# Access stats page
open http://<emqx-node-ip>:8080/haproxy_stats

# Credentials: admin/admin
```

### Key Metrics

- **EMQX**:
  - `emqx_client_connected`: Connected clients
  - `emqx_messages_received`: Message rate
  - `emqx_cluster_nodes_running`: Cluster health

- **HAProxy**:
  - Backend status (up/down)
  - Connection rates
  - Queue depth

- **OCI Load Balancer**:
  - Active connections
  - Health check status
  - Bandwidth usage

---

## Security Considerations

### Network Security

1. **OCI Load Balancer**: Public-facing with NSG restrictions
2. **EMQX Nodes**: Private subnet, no public IPs
3. **Inter-node Communication**: Port 4370/5370 only within EMQX pool
4. **Dashboard**: Port 18083 internal only (access via VPN or Fabio)

### Authentication

```bash
# Enable EMQX authentication
# Via dashboard or config:
# - Built-in database
# - JWT tokens
# - LDAP/AD
# - HTTP auth plugin
```

### TLS/SSL

```bash
# Configure TLS certificates
# Upload to EMQX via dashboard or mount via Nomad volumes
# Enable MQTTS on port 8883
# Enable WSS on port 8084
```

---

## Troubleshooting

### EMQX Not Clustering

```bash
# Check Consul DNS
dig emqx.service.consul

# Check from container
nomad alloc exec <alloc-id> nslookup emqx.service.consul

# Check Erlang cookie
nomad alloc exec <alloc-id> cat /opt/emqx/data/.erlang.cookie

# Check cluster status
nomad alloc exec <alloc-id> emqx ctl cluster status
```

### HAProxy Not Finding Backends

```bash
# Check HAProxy config
nomad alloc exec <alloc-id> cat /usr/local/etc/haproxy/haproxy.cfg

# Check DNS resolution
nomad alloc exec <alloc-id> nslookup prod.emqx.service.consul

# Check backend health
curl http://<emqx-node-ip>:8080/haproxy_stats
```

### Load Balancer Health Checks Failing

```bash
# Check HAProxy health endpoint
curl http://<emqx-node-ip>:8080/haproxy_health

# Check OCI LB backend status
oci lb backend-health get \
  --load-balancer-id <lb-ocid> \
  --backend-set-name emqx-mqtt-backend

# Check security groups
# Ensure LB can reach HAProxy on port 8080
```

---

## Files Created

### Terraform Modules
```
terraform/
├── volumes-emqx/
│   └── volumes-emqx.tf
├── emqx-instance-pool/
│   ├── emqx-instance-pool-stack.tf
│   ├── user-data/postinstall-runner-oracle.sh
│   └── README.md
├── emqx-load-balancer-security-group/
│   └── emqx-lb-security-group.tf
└── emqx-network-load-balancer/
    └── emqx-nlb.tf
```

### Nomad Jobs
```
nomad/
├── emqx.hcl
└── emqx-haproxy.hcl
```

### Scripts
```
scripts/
├── deploy-nomad-emqx.sh
└── deploy-nomad-emqx-haproxy.sh
```

### Documentation
```
├── EMQX_DEPLOYMENT_GUIDE.md
└── EMQX_COMPLETE_ARCHITECTURE.md
```

---

## Quick Start Summary

```bash
# 1. Deploy infrastructure
cd terraform/your-environment/
terraform apply  # volumes, instance pools, security groups

# 2. Deploy EMQX cluster
export ENVIRONMENT="prod" ORACLE_REGION="us-ashburn-1"
./scripts/deploy-nomad-emqx.sh

# 3. Deploy HAProxy
./scripts/deploy-nomad-emqx-haproxy.sh

# 4. Deploy load balancer
terraform apply -target=module.emqx_load_balancer

# 5. Test connectivity
mosquitto_pub -h mqtt.example.com -p 1883 -t test/topic -m "Hello EMQX!"
```

---

## Architecture Benefits

1. **High Availability**: Multi-AZ deployment, automatic failover
2. **Scalability**: Horizontal scaling from 1 to N nodes
3. **Performance**: Layer 4 load balancing, least-connection routing
4. **Persistence**: Block volumes survive node failures
5. **Observability**: Prometheus metrics, HAProxy stats, Consul health checks
6. **Flexibility**: Nomad orchestration allows easy updates and rollbacks
7. **Cost Optimization**: Shared infrastructure (HAProxy on EMQX nodes)

---

## Next Steps

1. Configure TLS certificates for MQTTS/WSS
2. Set up authentication (JWT, database, LDAP)
3. Configure ACLs for topic access control
4. Enable Prometheus scraping
5. Set up alerts for cluster health
6. Configure message persistence and retention policies
7. Implement backup strategy for EMQX data volumes
