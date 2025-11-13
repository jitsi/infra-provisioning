# EMQX Instance Pool Module

This Terraform module creates an EMQX cluster on Oracle Cloud Infrastructure (OCI) for use with Nomad orchestration.

## Architecture

### Overview
- Creates **N instance pools of size 1** (not 1 pool of size N)
- Each instance gets a unique `group-index` freeform tag (0, 1, 2, ...)
- Instances are distributed across availability domains for high availability
- Each instance has a dedicated high-I/O block volume attached
- Uses Consul for service discovery and DNS-based clustering
- Runs as Nomad clients with pool_type `emqx`

### Components

1. **Instance Configuration**: One per pool member with unique `group-index`
2. **Instance Pools**: N pools of size 1 each
3. **Volume Matching**: Instance `group-index` matches volume `volume-index` for automatic attachment
4. **Nomad Integration**: Runs standard `nomad-client.yml` playbook with volume support

## Volume Mounting

The module leverages the existing `mount_volumes()` function from `terraform/lib/postinstall-lib.sh`:

1. **Cloud-init runs** on instance launch
2. **Volume Discovery**: Finds volumes with matching `volume-role=emqx` and `volume-index={group-index}`
3. **Attachment**: OCI API attaches block volume to instance
4. **Filesystem**: Creates ext4 filesystem on first boot
5. **Mount**: Mounts to `/mnt/bv/emqx-{N}`
6. **Nomad Symlink**: Creates `/opt/nomad/data/emqx-{N}` → `/mnt/bv/emqx-{N}`

## Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `environment` | string | - | Environment name (e.g., prod, dev) |
| `name` | string | - | Resource name |
| `oracle_region` | string | - | OCI region |
| `availability_domains` | list(string) | - | List of ADs to distribute across |
| `role` | string | `"emqx"` | Instance role tag |
| `pool_type` | string | `"emqx"` | Nomad pool type |
| `git_branch` | string | - | Git branch for config repo |
| `tenancy_ocid` | string | - | OCI tenancy OCID |
| `compartment_ocid` | string | - | OCI compartment OCID |
| `resource_name_root` | string | - | Root name for resources |
| `instance_config_name` | string | - | Instance configuration display name |
| `image_ocid` | string | - | OCI image OCID |
| `user_public_key_path` | string | - | Path to SSH public key |
| `security_group_id` | string | - | Network security group OCID |
| `shape` | string | - | Instance shape (e.g., VM.Standard.E4.Flex) |
| `memory_in_gbs` | number | - | Memory per instance |
| `ocpus` | number | - | OCPUs per instance |
| `pool_subnet_ocid` | string | - | Subnet OCID |
| `instance_pool_size` | number | - | Number of EMQX nodes (1, 3, 5, etc.) |
| `instance_pool_name` | string | - | Instance pool display name |
| `disk_in_gbs` | number | - | Boot disk size |
| `volumes_enabled` | bool | `true` | Enable volume mounting |
| `infra_configuration_repo` | string | - | Infrastructure config repo URL |
| `infra_customizations_repo` | string | - | Customizations repo URL |

## Outputs

| Output | Description |
|--------|-------------|
| `private_ips` | List of private IPs for all instances |
| `instance_pool_ids` | List of instance pool OCIDs |

## Usage Example

```hcl
module "emqx_pool" {
  source = "../emqx-instance-pool"

  environment        = "prod"
  name              = "emqx-cluster"
  oracle_region     = "us-ashburn-1"
  availability_domains = ["AD-1", "AD-2", "AD-3"]

  instance_pool_size = 3
  instance_pool_name = "prod-emqx-pool"
  instance_config_name = "prod-emqx-config"

  shape          = "VM.Standard.E4.Flex"
  ocpus         = 4
  memory_in_gbs = 16
  disk_in_gbs   = 50

  pool_subnet_ocid   = var.private_subnet_ocid
  security_group_id  = var.emqx_security_group_id
  image_ocid        = var.oracle_linux_image_ocid

  user_public_key_path = "~/.ssh/id_rsa.pub"
  user                = "opc"
  user_private_key_path = "~/.ssh/id_rsa"

  tenancy_ocid      = var.tenancy_ocid
  compartment_ocid  = var.compartment_ocid
  git_branch       = "main"

  infra_configuration_repo = "https://github.com/org/infra-configuration"
  infra_customizations_repo = "https://github.com/org/infra-customizations"

  resource_name_root   = "prod-emqx"
  vcn_name            = "prod-vcn"
  postinstall_status_file = "/tmp/emqx-postinstall.log"
}
```

## Scaling

### Scale Up
1. Increase `instance_pool_size` variable
2. Apply Terraform: `terraform apply`
3. New instances will auto-join EMQX cluster via Consul DNS
4. Update corresponding Nomad job's `emqx_count` variable

### Scale Down
1. Decrease `instance_pool_size` variable
2. Apply Terraform: `terraform apply`
3. Remove corresponding Nomad allocations first if needed

## Network Security Requirements

The security group must allow:

### Inbound Rules
- **TCP 1883**: MQTT (from client networks)
- **TCP 8883**: MQTTS/TLS (from client networks)
- **TCP 8083**: WebSocket (from client networks)
- **TCP 8084**: WebSocket Secure (from client networks)
- **TCP 18083**: Dashboard (internal/VPN only)
- **TCP 4370**: Erlang distribution (from emqx pool only)
- **TCP 5370**: Cluster RPC (from emqx pool only)

### Outbound Rules
- All allowed

## Dependencies

### Required Terraform Modules
- `terraform/volumes-emqx`: Creates block volumes

### Required Ansible Playbooks
- `nomad-client.yml`: Standard Nomad client setup

### Required Scripts
- `terraform/lib/postinstall-lib.sh`: Volume mounting functions
- `terraform/lib/postinstall-header.sh`: Initialization
- `terraform/lib/postinstall-footer.sh`: Finalization

## Integration with Nomad

After deploying this infrastructure:

1. Verify instances are running:
   ```bash
   terraform output private_ips
   ```

2. Check Nomad registration:
   ```bash
   nomad node status -filter 'Meta["pool_type"]=="emqx"'
   ```

3. Deploy EMQX Nomad job:
   ```bash
   nomad job run -var="emqx_count=3" nomad/emqx.hcl
   ```

4. Verify cluster formation:
   ```bash
   nomad alloc status <allocation-id>
   nomad alloc logs <allocation-id> emqx
   ```

5. Access dashboard:
   - URL: `http://emqx.{domain}/`
   - Default credentials: admin / public (change immediately)

## Monitoring

The EMQX instances will:
- Register with Consul service discovery
- Expose Prometheus metrics at `/api/v5/prometheus/stats`
- Report health via dashboard API `/api/v5/status`
- Send telemetry via Telegraf (if configured)

## Troubleshooting

### Volume Not Mounting
```bash
ssh opc@<instance-ip>
sudo cat /var/log/cloud-init-output.log
sudo ls -la /mnt/bv/
```

### EMQX Not Clustering
```bash
# Check Consul DNS
dig emqx.service.consul

# Check from EMQX container
nomad alloc exec <alloc-id> emqx emqx ctl cluster status
```

### Instance Not Joining Nomad
```bash
ssh opc@<instance-ip>
sudo systemctl status nomad
sudo journalctl -u nomad -f
```

## References

- [EMQX Documentation](https://www.emqx.io/docs/en/latest/)
- [EMQX Clustering Guide](https://www.emqx.io/docs/en/latest/deploy/cluster/intro.html)
- [Nomad Job Specification](https://www.nomadproject.io/docs/job-specification)
