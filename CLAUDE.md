# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is the infrastructure provisioning repository for Jitsi Meet video conferencing services. It manages the complete lifecycle of Jitsi infrastructure including provisioning, deployment, monitoring, and teardown across multiple cloud providers (primarily Oracle Cloud Infrastructure).

## Key Commands

### Development Environment Setup
```bash
# Run local ops-agent container (used by Jenkins)
scripts/local-ops-agent.sh

# Set up local development environment
scripts/localdev.sh
```

### Build and Deployment
```bash
# Build various Oracle Cloud images
scripts/build-*-oracle.sh

# Deploy Nomad services
scripts/deploy-nomad-*.sh

# Create and manage shards (complete service deployments)
scripts/create-shard-*.sh
scripts/delete-shard-*.sh
```

### Common Operations
```bash
# Check shard health and status
scripts/validate-shard.sh
scripts/wait-healthy-shards.sh

# Manage HAProxy and load balancing
scripts/haproxy-status.sh
scripts/set-haproxy-*.sh

# Release management
scripts/set-release-ga.sh
scripts/expand-release.sh
```

### Terraform Operations
```bash
# Initialize and apply Terraform configurations
cd terraform/<component>
terraform init
terraform plan
terraform apply

# Key Terraform projects
terraform/vcn/                    # Virtual Cloud Network foundation
terraform/shard-core/             # Core Jitsi Meet servers
terraform/haproxy-shards/         # Load balancers
terraform/create-jvb-instance-configuration/  # Video bridge servers
terraform/consul-server/          # Service discovery
terraform/nomad-server/           # Container orchestration
```

### Nomad Operations
```bash
# Deploy Nomad jobs
scripts/deploy-nomad-<service>.sh

# Use Nomad packs for templated deployments
scripts/nomad-pack.sh

# Key Nomad services
nomad/jibri.hcl                   # Meeting recording
nomad/coturn.hcl                  # NAT traversal
nomad/prometheus.hcl              # Metrics collection
nomad/loki.hcl                    # Log aggregation
```

#### Using logcli for Log Queries

**Loki Endpoint Pattern:**
```
https://<environment>-<region>-loki.jitsi.net
```

**Basic logcli Usage:**
```bash
# Query error logs from specific service/task
logcli query --addr=https://<environment>-<region>-loki.jitsi.net '{task="<service>"} |~ "(?i)error"' --limit=20 --since=1h

# Examples for beta-meet-jit-si environment:
logcli query --addr=https://beta-meet-jit-si-us-ashburn-1-loki.jitsi.net '{task="prosody"} |~ "(?i)error"' --limit=20 --since=1h
logcli query --addr=https://beta-meet-jit-si-uk-london-1-loki.jitsi.net '{job=~".+"} |~ "(?i)error"' --limit=50 --since=2h
```

**Common Query Patterns:**
- `{task="prosody"}` - Filter by specific Nomad task name
- `{job="autoscaler-us-ashburn-1"}` - Filter by specific Nomad job
- `{alloc="<allocation-id>"}` - Filter by specific allocation ID
- `{component="mod_muc_events"}` - Filter by application component
- `|~ "(?i)error"` - Case-insensitive regex for "error"
- `|~ "404|500|failed"` - Multiple error patterns
- `|~ "URL Callback non successful"` - Specific error patterns

**Environment Discovery:**
Find available regions for any environment:
```bash
# Check NOMAD_REGIONS variable in environment config
cat sites/<environment>/stack-env.sh | grep NOMAD_REGIONS
# Example: sites/beta-meet-jit-si/stack-env.sh shows "us-ashburn-1 us-phoenix-1 uk-london-1"
```

#### Using Nomad and Consul APIs

**Nomad API Endpoint Pattern:**
```
https://<environment>-<region>-nomad.jitsi.net
```

**Consul API Endpoint Pattern:**
```
https://<environment>-<region>-consul.jitsi.net
```

**Nomad API Usage:**
```bash
# Use the OCI_LOCAL_REGION variable from sites/<environment>/stack-env.sh to determine the region to query per environment
# Consul has a global mesh so the local region may be addressed with a ?dc=<datacenter> parameter to query other regions
# Consul uses the 'signal' service name for jitsi shard discovery
# Use scripts/nomad.sh for environment-aware Nomad CLI access
ENVIRONMENT=<environment> LOCAL_REGION=<region> scripts/nomad.sh status
ENVIRONMENT=<environment> LOCAL_REGION=<region> scripts/nomad.sh job status <job-name>
ENVIRONMENT=<environment> LOCAL_REGION=<region> scripts/nomad.sh alloc status <allocation-id>

# Direct API calls (authentication handled automatically)
curl https://<environment>-<region>-nomad.jitsi.net/v1/jobs
curl https://<environment>-<region>-nomad.jitsi.net/v1/job/<job-name>
curl https://<environment>-<region>-nomad.jitsi.net/v1/allocations
```

**Consul API Usage:**
```bash
# Query service catalog for signal service
curl https://<environment>-<region>-consul.jitsi.net/v1/catalog/service/signal

# Other catalog operations
curl https://<environment>-<region>-consul.jitsi.net/v1/catalog/services
curl https://<environment>-<region>-consul.jitsi.net/v1/health/service/<service-name>
curl https://<environment>-<region>-consul.jitsi.net/v1/kv/<key-path>
```

**Common API Operations:**
- **Job Management**: List jobs, inspect job status, view allocations
- **Service Discovery**: Query registered services, health status, service nodes
- **Key-Value Store**: Configuration management, feature flags, operational data
- **Health Monitoring**: Service health checks, node status, cluster health

**Examples:**
```bash
# Check Nomad job status in stage-8x8 environment
ENVIRONMENT=stage-8x8 LOCAL_REGION=eu-frankfurt-1 scripts/nomad.sh job status shard-stage-8x8-eu-frankfurt-1-s2

# Query Consul catalog for signal service in stage-8x8
curl https://stage-8x8-eu-frankfurt-1-consul.jitsi.net/v1/catalog/service/signal
```

## High-Level Architecture

### Core Components
- **Jitsi Meet Infrastructure**: Signal nodes, JVB (Jitsi Video Bridge) pools, Jicofo, Prosody XMPP
- **Supporting Services**: HAProxy (load balancing), Consul (service discovery), CoTURN (TURN server), Jigasi (SIP gateway)
- **Monitoring Stack**: Prometheus, Loki, Grafana, Alertmanager, Wavefront
- **Compute Infrastructure**: Nomad clusters, autoscaler groups
- **Network Infrastructure**: Load balancers, VPNs, DNS management

### Infrastructure Patterns
- **Multi-Cloud Deployment**: Automatic distribution across multiple cloud regions
- **Sharding**: Complete service deployments as independent shards
- **Image-based Deployment**: Custom-built images for all components
- **Infrastructure as Code**: Terraform for provisioning, Ansible for configuration

### Key Directories
- **`scripts/`**: Shell and Python scripts for all operations
- **`terraform/`**: Terraform configurations for infrastructure components
- **`nomad/`**: Nomad job definitions and packs
- **`jenkins/`**: Jenkins job definitions and Groovy utilities
- **`ansible/`**: Ansible playbooks and configurations
- **`templates/`**: CloudFormation and other infrastructure templates

## Terraform Project Structure

### Infrastructure Foundation
- **`terraform/vcn/`**: Virtual Cloud Network (VCN) foundation with subnets, gateways, routing
- **`terraform/compartment/`**: OCI compartment management and resource organization
- **`terraform/vcn-security-lists/`**: Network security groups and access control
- **`terraform/create-initial-policies/`**: IAM policies and service authentication

### Core Jitsi Services
- **`terraform/shard-core/`**: Main Jitsi Meet application servers (signal, web, Prosody)
- **`terraform/create-jvb-instance-configuration/`**: Jitsi Video Bridge server configurations
- **`terraform/haproxy-shards/`**: HAProxy load balancers with SSL termination
- **`terraform/create-coturn-stack/`**: TURN/STUN servers for NAT traversal
- **`terraform/jibri-instance-configuration/`**: Meeting recording infrastructure
- **`terraform/jigasi-proxy/`**: SIP gateway for telephony integration

### Orchestration and Service Discovery
- **`terraform/consul-server/`**: Consul clusters for service discovery
- **`terraform/nomad-server/`**: Nomad clusters for container orchestration
- **`terraform/nomad-pool/`**: Compute pools for different workload types
- **`terraform/nomad-instance-pool/`**: Specialized compute pools (x86, ARM, GPU)

### Monitoring and Operations
- **`terraform/wavefront-proxy/`**: Metrics collection and forwarding
- **`terraform/ops-repo/`**: Internal package repositories
- **`terraform/jenkins-server/`**: CI/CD infrastructure
- **`terraform/selenium-grid/`**: Automated testing infrastructure

### Network and Security
- **`terraform/ingress-firewall/`**: Web Application Firewall policies
- **`terraform/create-vpn-oracle-ipsec-tunnel/`**: VPN connectivity
- **`terraform/dns-geo-zone/`**: DNS management and geographic routing
- **`terraform/jumpbox-oracle/`**: Secure access bastion hosts

## Nomad Job Definitions

### Core Jitsi Services
- **`nomad/jibri.hcl`**: Meeting recording service with autoscaler integration
- **`nomad/coturn.hcl`**: TURN/STUN server for WebRTC NAT traversal
- **`nomad/colibri-proxy.hcl`**: WebSocket proxy for JVB communication
- **`nomad/jigasi-haproxy.hcl`**: SIP gateway load balancer
- **`nomad/prosody-egress.hcl`**: XMPP egress proxy
- **`nomad/multitrack-recorder.hcl`**: Advanced multi-track recording service

### Jitsi Packs (Template-Based)
- **`nomad/jitsi_packs/jitsi_meet_web/`**: Frontend web interface
- **`nomad/jitsi_packs/jitsi_meet_jvb/`**: Video bridge deployment
- **`nomad/jitsi_packs/jitsi_meet_backend/`**: Backend services (Jicofo, Prosody)
- **`nomad/jitsi_packs/jitsi_autoscaler/`**: JVB autoscaling service
- **`nomad/jitsi_packs/jitsi_cloudprober/`**: Health monitoring service

### Monitoring and Observability
- **`nomad/prometheus.hcl`**: Metrics collection and storage
- **`nomad/grafana.hcl`**: Visualization dashboards
- **`nomad/alertmanager.hcl`**: Alert routing and notifications
- **`nomad/loki.hcl`**: Log aggregation and storage
- **`nomad/telegraf.hcl`**: System metrics collection (system job)
- **`nomad/alert-emailer.hcl`**: Email notification service

### Infrastructure Services
- **`nomad/fabio.hcl`**: HTTP load balancer and reverse proxy
- **`nomad/registry.hcl`**: Docker registry for container images
- **`nomad/wavefront-proxy.hcl`**: Metrics proxy for Wavefront
- **`nomad/selenium-grid-hub.hcl`**: Testing infrastructure

## Scripts Organization

### Python Helper Libraries
- **`scripts/hcvlib.py`**: Core library for cloud operations and utilities
- **`scripts/shard.py`**: Shard management and operations
- **`scripts/cloud.py`**: Cloud provider abstractions
- **`scripts/pool.py`**: Resource pool management

### Common Script Patterns
- Most scripts accept `--environment` parameter for environment-specific operations
- Scripts use consistent naming: `<action>-<component>-<cloud>.sh`
- Oracle Cloud scripts typically end with `-oracle.sh`
- Batch mode operations support `--batch` flag for automation

## Jenkins CI/CD

The Jenkins configuration manages the complete infrastructure lifecycle:

### Key Job Categories
- **`release-*`**: Release management and promotion
- **`provision-*`**: Infrastructure provisioning
- **`destroy-*`**: Cleanup and teardown
- **`reconfigure-*`**: Runtime configuration changes
- **`monitor-*`**: Health checking and monitoring

### Common Jenkins Patterns
- **Multi-Cloud Orchestration**: Parallel execution across cloud regions
- **State Management**: Consul integration for service discovery
- **Image Lifecycle**: Automated building and replication
- **Environment-Specific**: Heavy use of environment variables and site configs

## Environment Configuration

### Site-Specific Configuration
- Environment-specific settings in `sites/*/stack-env.sh`
- Inventory files for different deployment targets (e.g., `meet-shards.inventory`)
- Cloud-specific configurations in `clouds/` directory

### Required Tools
- terraform 1.2.7
- jq (JSON processor)
- yq 4 (YAML processor)
- ansible-vault
- xmlstarlet
- Oracle Cloud CLI (oci)
- AWS CLI

## Common Development Workflows

### Creating New Infrastructure
1. Define Terraform configuration in appropriate `terraform/` subdirectory
2. Create corresponding shell script in `scripts/`
3. Add Jenkins job definition in `jenkins/jobs/` and `jenkins/groovy/`
4. Test with local ops-agent container

### Updating Existing Services
1. Modify Nomad job definitions in `nomad/`
2. Update deployment scripts in `scripts/deploy-nomad-*.sh`
3. Use reconfigure Jenkins jobs for runtime changes

### Debugging and Monitoring
1. Use validation scripts to check shard health
2. Check HAProxy status and load balancing
3. Monitor through Prometheus/Grafana dashboards
4. Use synthetic testing jobs for end-to-end validation

## Infrastructure Dependencies

### Core Meeting Flow
```
User → HAProxy → Jitsi Meet Web → Jitsi Meet Backend → JVB
                                        ↓
                                 Prosody XMPP
                                        ↓
                         Jibri (Recording) → Object Storage
                                        ↓
                         Coturn (NAT Traversal)
```

### Terraform Dependencies
```
VCN → Security Groups → Compute Resources → Load Balancers → DNS
     ↓
   Consul → Nomad → Application Services
```

### Nomad Service Dependencies
```
telegraf → prometheus → grafana (Monitoring)
loki → vector → Log aggregation
alertmanager → alert-emailer → Notifications
fabio → HTTP load balancing for services
```

## Security Considerations

- All cloud credentials managed through Jenkins credential store
- SSH keys and certificates handled securely
- Network segmentation through VPCs and security groups
- Regular rotation of service credentials and certificates
- Vault integration for secrets management in Nomad jobs
- ASAP (Atlassian Service Authentication Protocol) for service authentication