variable "environment" {}
variable "domain" {}
variable "shard" {}
variable "cloud_name" {}
variable "release_number" {}
variable "name" {}
variable "oracle_region" {}
variable "shape" {}
variable "availability_domains" {
  type = list(string)
}
variable "role" {}
variable "git_branch" {}
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "vcn_name" {}
variable "resource_name_root" {}
variable "subnet_ocid" {}
variable "image_ocid" {}
variable "dns_name" {}
variable "internal_dns_name" {}
variable "dns_zone_name" {}
variable "dns_compartment_ocid" {}
variable "environment_type" {}
variable "tag_namespace" {}
variable "user" {}
variable "user_private_key_path" {}
variable "user_public_key_path" {}
variable "bastion_host" {}
variable "ingress_nsg_cidr" {}
variable "instance_display_name" {}
variable "instance_shape_config_memory_in_gbs" {}
variable "instance_shape_config_ocpus" {}
variable "postinstall_status_file" {}
variable "disk_in_gbs" {}
variable "user_data_file" {
  default = "terraform/shard-core/user-data/postinstall-runner-oracle.sh"
}
variable "user_data_lib_path" {
  default = "terraform/lib"
}
variable "http_monitor_interval_in_seconds" {
  default = "30"
}
variable "http_monitor_timeout_in_seconds" {
  default = "10"
}
variable "http_monitor_is_enabled" {
  default = "true'"
}
variable "http_monitor_vantage_point_names" {
  default = [ "aws-pdx","aws-iad", "aws-gru","aws-fra","aws-tyo" ]
}

# leave alarm off until shard has JVBs or else alarms will ring on new shard creation
variable "alarm_is_enabled" {
  default = "false"
}
variable "alarm_body" {
  default = "FAILURE: Shard health check failed from all external perspectives and is in a failed state.\nCheck the on call cheat sheet for more details:\n https://docs.google.com/document/d/1hFMNI6tbahZhXDWqimJQ9cJO4Ofa3P02lKCAOUegdNM/edit"
}
variable "alarm_any_body" {
  default = "WARNING: Shard health check failed from at least one external perspective twice in a row.\nCheck the on call cheat sheet for more details:\n https://docs.google.com/document/d/1hFMNI6tbahZhXDWqimJQ9cJO4Ofa3P02lKCAOUegdNM/edit"
}

variable "alarm_repeat_notification_duration" {
  default = ""
}

variable "alarm_severity" {
  default = "CRITICAL"
}
variable "alarm_any_severity" {
  default = "WARNING"
}

variable "alarm_pagerduty_is_enabled" {
  default = "false"
}
variable "alarm_pagerduty_topic_name" {}
variable "alarm_email_topic_name" {}
variable "infra_configuration_repo" {}
variable "infra_customizations_repo" {}

locals {
  common_tags = {
    "${var.tag_namespace}.environment" = var.environment
    "${var.tag_namespace}.domain" = var.domain
    "${var.tag_namespace}.shard" = var.shard
    "${var.tag_namespace}.cloud_name" = var.cloud_name
    "${var.tag_namespace}.environment_type" = var.environment_type
    "${var.tag_namespace}.release_number" = var.release_number
    "${var.tag_namespace}.git_branch" = var.git_branch
    "${var.tag_namespace}.role" = var.role
    "${var.tag_namespace}.shard-role" = var.role
    "${var.tag_namespace}.Name" = var.name
  }
}

provider "oci" {
  region = var.oracle_region
  tenancy_ocid = var.tenancy_ocid
}

terraform {
  backend "s3" {
    skip_region_validation = true
    skip_credentials_validation = true
    skip_metadata_api_check = true
    force_path_style = true
  }
  required_providers {
      oci = {
          source  = "oracle/oci"
      }
      null = {
          source = "hashicorp/null"
      }      
  }
}

data "oci_core_vcns" "vcns" {
  compartment_id = var.compartment_ocid
  display_name = var.vcn_name
}


data "oci_ons_notification_topics" "email_notification_topics" {
    #Required
    compartment_id = var.compartment_ocid

    #Optional
 #   id = var.notification_topic_id
    name = var.alarm_email_topic_name
}

data "oci_ons_notification_topics" "pagerduty_notification_topics" {
    #Required
    compartment_id = var.compartment_ocid

    #Optional
 #   id = var.notification_topic_id
    name = var.alarm_pagerduty_topic_name
}

locals {
  overall_alarm_targets = var.alarm_pagerduty_is_enabled == "true" ? [data.oci_ons_notification_topics.pagerduty_notification_topics.notification_topics[0].topic_id] : [data.oci_ons_notification_topics.email_notification_topics.notification_topics[0].topic_id]
  email_only_alarm_targets = [data.oci_ons_notification_topics.email_notification_topics.notification_topics[0].topic_id]
}

resource "oci_core_network_security_group" "instance_security_group" {
  compartment_id = var.compartment_ocid
  vcn_id = data.oci_core_vcns.vcns.virtual_networks[0].id
  display_name = "${var.resource_name_root}-SecurityGroup"
}

resource "oci_core_network_security_group_security_rule" "instance_nsg_rule_egress" {
  network_security_group_id = oci_core_network_security_group.instance_security_group.id
  direction = "EGRESS"
  destination = "0.0.0.0/0"
  protocol = "all"
}

resource "oci_core_network_security_group_security_rule" "instance_nsg_rule_ingress_ssh" {
  network_security_group_id = oci_core_network_security_group.instance_security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = data.oci_core_vcns.vcns.virtual_networks[0].cidr_block
  stateless = false

  tcp_options {
    destination_port_range {
      max = 22
      min = 22
    }
  }
}

# TCP Ingress for iperf server
resource "oci_core_network_security_group_security_rule" "instance_nsg_rule_ingress_tcp" {
  network_security_group_id = oci_core_network_security_group.instance_security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = var.ingress_nsg_cidr
  stateless = false

  tcp_options {
    destination_port_range {
      max = 443
      min = 443
    }
  }
}

# TCP Ingress for xmpp server
resource "oci_core_network_security_group_security_rule" "instance_nsg_rule_ingress_tcp_xmpp" {
  network_security_group_id = oci_core_network_security_group.instance_security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = "10.0.0.0/8"
  stateless = false

  tcp_options {
    destination_port_range {
      max = 5222
      min = 5222
    }
  }
}

# TCP Ingress for prosody-jvb server
resource "oci_core_network_security_group_security_rule" "instance_nsg_rule_ingress_tcp_xmppjvb" {
  network_security_group_id = oci_core_network_security_group.instance_security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = "10.0.0.0/8"
  stateless = false

  tcp_options {
    destination_port_range {
      max = 6222
      min = 6222
    }
  }
}

# TCP Ingress for signal-sidecar http server
resource "oci_core_network_security_group_security_rule" "instance_nsg_rule_ingress_tcp_sidecarhttp" {
  network_security_group_id = oci_core_network_security_group.instance_security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = "10.0.0.0/8"
  stateless = false

  tcp_options {
    destination_port_range {
      max = 6000
      min = 6000
    }
  }
}

# TCP Ingress for signal-sidecar haproxy agent server
resource "oci_core_network_security_group_security_rule" "instance_nsg_rule_ingress_tcp_sidecaragent" {
  network_security_group_id = oci_core_network_security_group.instance_security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = "10.0.0.0/8"
  stateless = false

  tcp_options {
    destination_port_range {
      max = 6060
      min = 6060
    }
  }
}

# ingress for serf / consul
resource "oci_core_network_security_group_security_rule" "instance_nsg_rule_ingress_tcp_serf" {
  network_security_group_id = oci_core_network_security_group.instance_security_group.id
  direction = "INGRESS"
  protocol = "6"
  source = "10.0.0.0/8"
  stateless = false

  tcp_options {
    destination_port_range {
      max = 8301
      min = 8301
    }
  }
}

resource "oci_core_instance" "instance" {
    #Required
    availability_domain = var.availability_domains[0]
    compartment_id = var.compartment_ocid
    shape = var.shape

    create_vnic_details {
        subnet_id = var.subnet_ocid
        nsg_ids = [oci_core_network_security_group.instance_security_group.id]
    }

    source_details {
        source_type = "image"
        source_id = var.image_ocid
        # Apply this to set the size of the boot volume that's created for this instance.
        # Otherwise, the default boot volume size of the image is used.
        # This should only be specified when source_type is set to "image".
        boot_volume_size_in_gbs = var.disk_in_gbs
    }

    metadata = {
        user_data = base64encode(join("",[
          file("${path.cwd}/${var.user_data_lib_path}/postinstall-header.sh"), # load the header
          file("${path.cwd}/${var.user_data_lib_path}/postinstall-lib.sh"), # load the lib
          "\nexport INFRA_CONFIGURATION_REPO=${var.infra_configuration_repo}\nexport INFRA_CUSTOMIZATIONS_REPO=${var.infra_customizations_repo}\n", #repo variables
          file("${path.cwd}/${var.user_data_file}"), # load our customizations
          file("${path.cwd}/${var.user_data_lib_path}/postinstall-footer.sh") # load the footer
        ]))
        ssh_authorized_keys = file(var.user_public_key_path)
    }

    defined_tags = local.common_tags

    display_name = var.instance_display_name

    shape_config {
        #Optional
        memory_in_gbs = var.instance_shape_config_memory_in_gbs
        ocpus = var.instance_shape_config_ocpus
    }

    preserve_boot_volume = false
}


locals {
  private_ip = oci_core_instance.instance.private_ip
  public_ip = oci_core_instance.instance.public_ip
}

resource "oci_dns_rrset" "instance_dns_record_internal" {
  zone_name_or_id = var.dns_zone_name
  domain = var.internal_dns_name
  rtype = "A"
  compartment_id = var.dns_compartment_ocid
  items {
    domain = var.internal_dns_name
    rtype = "A"
    ttl = "60"
    rdata = oci_core_instance.instance.private_ip
   }
}

resource "oci_dns_rrset" "instance_dns_record" {
  zone_name_or_id = var.dns_zone_name
  domain = var.dns_name
  rtype = "A"
  compartment_id = var.dns_compartment_ocid
  items {
    domain = var.dns_name
    rtype = "A"
    ttl = "60"
    rdata = oci_core_instance.instance.public_ip
   }
}
resource "null_resource" "verify_cloud_init" {
  count = 1
  depends_on = [oci_core_instance.instance]

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait"
    ]
    connection {
      type = "ssh"
      host = local.private_ip
      user = var.user
      private_key = file(var.user_private_key_path)

      bastion_host = var.bastion_host
      bastion_user = var.user
      bastion_private_key = file(var.user_private_key_path)
      script_path = "/home/${var.user}/script_%RAND%.sh"

      timeout = "5m"
    }
  }
  triggers = {
    always_run = "${timestamp()}"
  }
}


resource "oci_health_checks_http_monitor" "shard_http_health" {
    #Required
    compartment_id = var.compartment_ocid
    display_name = "${var.resource_name_root}-HealthCheck"
    interval_in_seconds = var.http_monitor_interval_in_seconds
    protocol = "HTTPS"
    targets = [local.public_ip]

    #Optional
    defined_tags = local.common_tags
    is_enabled = "true"
    headers = {"Host": var.domain}
    method = "GET"
    path = "/about/health"
    port = 443
    timeout_in_seconds = var.http_monitor_timeout_in_seconds
    vantage_point_names = var.http_monitor_vantage_point_names
}

resource "oci_monitoring_alarm" "shard_health_alarm_overall" {
    #Required
    compartment_id = var.compartment_ocid
    destinations = local.overall_alarm_targets
    display_name = "${var.resource_name_root}-HealthAlarm"
    is_enabled = var.alarm_is_enabled
    metric_compartment_id = var.compartment_ocid
    namespace = "oci_healthchecks"
    query = "HTTP.isHealthy[1m]{resourceId = \"${oci_health_checks_http_monitor.shard_http_health.id}\"}.grouping().max() < 1"
    severity = var.alarm_severity
    depends_on = [
      oci_health_checks_http_monitor.shard_http_health
    ]
    #Optional
    body = var.alarm_body
    defined_tags = local.common_tags
    message_format = "ONS_OPTIMIZED"
    pending_duration = "PT1M"
# can be set to repeat emails while a shard is down
    repeat_notification_duration = var.alarm_repeat_notification_duration
#    metric_compartment_id_in_subtree = var.alarm_metric_compartment_id_in_subtree
#    resolution = var.alarm_resolution
#    resource_group = var.alarm_resource_group
}

resource "oci_monitoring_alarm" "shard_health_alarm_any" {
    #Required
    compartment_id = var.compartment_ocid
    destinations = local.email_only_alarm_targets
    display_name = "${var.resource_name_root}-HealthAnyAlarm"
    is_enabled = var.alarm_is_enabled
    metric_compartment_id = var.compartment_ocid
    namespace = "oci_healthchecks"
    query = "HTTP.isHealthy[1m]{resourceId = \"${oci_health_checks_http_monitor.shard_http_health.id}\", errorMessage !~ \"*context deadline exceeded*\"}.min() < 1"
    severity = var.alarm_any_severity
    depends_on = [
      oci_health_checks_http_monitor.shard_http_health
    ]
    #Optional
    body = var.alarm_any_body
    defined_tags = local.common_tags
    message_format = "ONS_OPTIMIZED"
    pending_duration = "PT2M"
#    metric_compartment_id_in_subtree = var.alarm_metric_compartment_id_in_subtree
# can be set to repeat emails while a shard is down
#    repeat_notification_duration = var.alarm_repeat_notification_duration
#    resolution = var.alarm_resolution
#    resource_group = var.alarm_resource_group
}

output "private_ip" {
  value = local.private_ip
}

output "public_ip" {
  value = local.public_ip
}
