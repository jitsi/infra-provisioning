variable "oracle_region" {}
variable "tenancy_ocid" {}
variable "compartment_ocid" {}
variable "environment" {}
variable "domain" {}
variable "dns_name" {}
variable "dns_zone_name" {}
variable "fallback_host" {}
variable "tag_namespace" {
    default = "jitsi"
}
variable "steering_policy_template" {
    default = "ROUTE_BY_GEO"
}
variable "steering_policy_ttl" {
  default = "30"
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
variable "region_list" {
  type = list(string)
  default = [ "us-ashburn-1", "us-phoenix-1","eu-frankfurt-1","uk-london-1","ap-mumbai-1","ap-tokyo-1","ap-sydney-1","sa-saopaulo-1" ]
}
variable "ip_map" {
  type = map(string)
}
# this takes the list of regions with respect to the specific geo
variable "geocode_region_order" {
  type = map(list(string))
  default = { 
    #UK
    "2635167" = ["uk-london-1","eu-frankfurt-1","us-ashburn-1","ap-mumbai-1","us-phoenix-1","ap-tokyo-1","ap-sydney-1","sa-saopaulo-1"] 

    # US WEST STATES
    #US Arizona
    "5551752" = ["us-phoenix-1","us-ashburn-1","ap-tokyo-1","ap-sydney-1","sa-saopaulo-1","uk-london-1","eu-frankfurt-1","ap-mumbai-1"] 
    #US California
    "5332921" = ["us-phoenix-1","us-ashburn-1","ap-tokyo-1","ap-sydney-1","sa-saopaulo-1","uk-london-1","eu-frankfurt-1","ap-mumbai-1"] 
    #US Colorado
    "5417618" = ["us-phoenix-1","us-ashburn-1","ap-tokyo-1","ap-sydney-1","sa-saopaulo-1","uk-london-1","eu-frankfurt-1","ap-mumbai-1"] 
    #US Idaho
    "5596512" = ["us-phoenix-1","us-ashburn-1","ap-tokyo-1","ap-sydney-1","sa-saopaulo-1","uk-london-1","eu-frankfurt-1","ap-mumbai-1"] 
    #US Kansas
    "4273857" = ["us-phoenix-1","us-ashburn-1","ap-tokyo-1","ap-sydney-1","sa-saopaulo-1","uk-london-1","eu-frankfurt-1","ap-mumbai-1"] 
    #US Montana
    "5667009" = ["us-phoenix-1","us-ashburn-1","ap-tokyo-1","ap-sydney-1","sa-saopaulo-1","uk-london-1","eu-frankfurt-1","ap-mumbai-1"] 
    #US Nevada
    "5509151" = ["us-phoenix-1","us-ashburn-1","ap-tokyo-1","ap-sydney-1","sa-saopaulo-1","uk-london-1","eu-frankfurt-1","ap-mumbai-1"] 
    #US North Dakota
    "5690763" = ["us-phoenix-1","us-ashburn-1","ap-tokyo-1","ap-sydney-1","sa-saopaulo-1","uk-london-1","eu-frankfurt-1","ap-mumbai-1"] 
    #US New Mexico
    "5481136" = ["us-phoenix-1","us-ashburn-1","ap-tokyo-1","ap-sydney-1","sa-saopaulo-1","uk-london-1","eu-frankfurt-1","ap-mumbai-1"] 
    #US Oklahoma
    "4544379" = ["us-phoenix-1","us-ashburn-1","ap-tokyo-1","ap-sydney-1","sa-saopaulo-1","uk-london-1","eu-frankfurt-1","ap-mumbai-1"] 
    #US Oregon
    "5744337" = ["us-phoenix-1","us-ashburn-1","ap-tokyo-1","ap-sydney-1","sa-saopaulo-1","uk-london-1","eu-frankfurt-1","ap-mumbai-1"] 
    #US South Dakota
    "5769223" = ["us-phoenix-1","us-ashburn-1","ap-tokyo-1","ap-sydney-1","sa-saopaulo-1","uk-london-1","eu-frankfurt-1","ap-mumbai-1"] 
    #US Texas
    "4736286" = ["us-phoenix-1","us-ashburn-1","ap-tokyo-1","ap-sydney-1","sa-saopaulo-1","uk-london-1","eu-frankfurt-1","ap-mumbai-1"] 
    #US Utah
    "5549030" = ["us-phoenix-1","us-ashburn-1","ap-tokyo-1","ap-sydney-1","sa-saopaulo-1","uk-london-1","eu-frankfurt-1","ap-mumbai-1"] 
    #US Washington
    "5815135" = ["us-phoenix-1","us-ashburn-1","ap-tokyo-1","ap-sydney-1","sa-saopaulo-1","uk-london-1","eu-frankfurt-1","ap-mumbai-1"] 
    #US Wyoming
    "5843591" = ["us-phoenix-1","us-ashburn-1","ap-tokyo-1","ap-sydney-1","sa-saopaulo-1","uk-london-1","eu-frankfurt-1","ap-mumbai-1"] 

    #US overall (goes to east)
    "6252001" = ["us-ashburn-1","us-phoenix-1","uk-london-1","eu-frankfurt-1","sa-saopaulo-1","ap-mumbai-1","ap-tokyo-1","ap-sydney-1"] 

    # CANADA WESTERN PROVINCES (goes to us west)
    # CA Alberta
    "5883102"  = ["us-phoenix-1","us-ashburn-1","ap-tokyo-1","ap-sydney-1","sa-saopaulo-1","uk-london-1","eu-frankfurt-1","ap-mumbai-1"] 
    # CA British Columbia	
    "5909050" = ["us-phoenix-1","us-ashburn-1","ap-tokyo-1","ap-sydney-1","sa-saopaulo-1","uk-london-1","eu-frankfurt-1","ap-mumbai-1"] 
    # CA Northwest Territories
    "6091069" = ["us-phoenix-1","us-ashburn-1","ap-tokyo-1","ap-sydney-1","sa-saopaulo-1","uk-london-1","eu-frankfurt-1","ap-mumbai-1"] 
    # CA Saskatchewan
    "6141242" = ["us-phoenix-1","us-ashburn-1","ap-tokyo-1","ap-sydney-1","sa-saopaulo-1","uk-london-1","eu-frankfurt-1","ap-mumbai-1"] 
    # CA Yukon
    "6185811" = ["us-phoenix-1","us-ashburn-1","ap-tokyo-1","ap-sydney-1","sa-saopaulo-1","uk-london-1","eu-frankfurt-1","ap-mumbai-1"] 

    #Canada overall (goes to us east)
    "6251999" = ["us-ashburn-1","us-phoenix-1","uk-london-1","eu-frankfurt-1","sa-saopaulo-1","ap-mumbai-1","ap-tokyo-1","ap-sydney-1"] 

    #India
    "1269750" = ["ap-mumbai-1","ap-tokyo-1","eu-frankfurt-1","us-ashburn-1","uk-london-1","ap-sydney-1","us-phoenix-1","sa-saopaulo-1"]
    #Mexico (goes to us east)
    "3996063" = ["us-ashburn-1","us-phoenix-1","uk-london-1","eu-frankfurt-1","sa-saopaulo-1","ap-mumbai-1","ap-tokyo-1","ap-sydney-1"] 
    #Africa (copy of europe)
    "6255146" = ["eu-frankfurt-1","uk-london-1","us-ashburn-1","ap-mumbai-1","us-phoenix-1","ap-tokyo-1","ap-sydney-1","sa-saopaulo-1"]
    #Antarctica
    "6255152" = ["sa-saopaulo-1","ap-sydney-1","ap-mumbai-1","us-ashburn-1","us-phoenix-1","uk-london-1","eu-frankfurt-1","ap-tokyo-1"]
    #Asia
    "6255147" = ["ap-tokyo-1","ap-mumbai-1","eu-frankfurt-1","us-phoenix-1","ap-sydney-1","uk-london-1","sa-saopaulo-1","us-ashburn-1"]
    #Europe
    "6255148" = ["eu-frankfurt-1","uk-london-1","us-ashburn-1","ap-mumbai-1","us-phoenix-1","ap-tokyo-1","ap-sydney-1","sa-saopaulo-1"] 
    #North America
    "6255149" = ["us-ashburn-1","us-phoenix-1","uk-london-1","eu-frankfurt-1","sa-saopaulo-1","ap-mumbai-1","ap-tokyo-1","ap-sydney-1"] 
    #Oceana
    "6255151" = ["ap-sydney-1","ap-tokyo-1","us-phoenix-1","ap-mumbai-1","us-ashburn-1","sa-saopaulo-1","uk-london-1","eu-frankfurt-1"] 
    #South America
    "6255150" = ["sa-saopaulo-1","us-ashburn-1","us-phoenix-1","ap-sydney-1","ap-mumbai-1","uk-london-1","eu-frankfurt-1","ap-tokyo-1"]
  }
}

locals {
  steering_policy_display_name = "${var.environment}-geo"
  common_tags = {
    "${var.tag_namespace}.environment" = var.environment
    "${var.tag_namespace}.domain" = var.domain
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
  }
}

data "oci_dns_zones" "dns_zones" {
    compartment_id = var.tenancy_ocid
    name = var.dns_zone_name
}

resource "oci_health_checks_http_monitor" "lb_http_health" {
    #Required
    compartment_id = var.tenancy_ocid
    display_name = "${var.environment}-LBHealthCheck"
    interval_in_seconds = var.http_monitor_interval_in_seconds
    protocol = "HTTPS"
    targets = [ for r in var.region_list : var.ip_map[r] ]

    #Optional
    defined_tags = local.common_tags
    is_enabled = "true"
    headers = {"Host": var.domain}
    method = "HEAD"
    path = "/"
    port = 443
    timeout_in_seconds = var.http_monitor_timeout_in_seconds
    vantage_point_names = var.http_monitor_vantage_point_names
}

resource "oci_dns_steering_policy" "geo_steering_policy" {
    #Required
    compartment_id = var.tenancy_ocid
    display_name = local.steering_policy_display_name
    template = var.steering_policy_template

    #Optional
    dynamic "answers" {
      for_each = var.region_list
      content {
        name = "${var.environment}-${answers.value}"
        rdata = var.ip_map[answers.value]
        rtype = "A"
        is_disabled = false
        pool = answers.value
      }
    }

    defined_tags = local.common_tags
    # freeform_tags = var.steering_policy_freeform_tags
    health_check_monitor_id = oci_health_checks_http_monitor.lb_http_health.id
    # required rules for this template type are defined here: https://docs.oracle.com/en-us/iaas/Content/TrafficManagement/Concepts/trafficmanagementapi.htm
    rules {
      rule_type = "FILTER"
      default_answer_data {

          #Optional
          answer_condition = "answer.isDisabled != true"
          should_keep = true
      }
    }
    rules {
      rule_type = "HEALTH"
    }
    # geokeys are defined here: https://docs.oracle.com/en-us/iaas/Content/TrafficManagement/Reference/trafficmanagementgeo.htm
    rules {
        rule_type = "PRIORITY"
        description = "Geo DNS for ${var.domain}"

        # geo processing rules from specific to more general
        dynamic "cases" {
          for_each = var.geocode_region_order
          content {
            case_condition = "query.client.geoKey in (geoKey '${cases.key}')"
            dynamic "answer_data" {
              for_each = [ for v in cases.value : v if contains(var.region_list,v) ]              
              content {
                answer_condition = "answer.pool == '${answer_data.value}'"
                should_keep = true
                value = answer_data.key+1
              }
            }

          }
        }
        # fallback with no case_condition, uses incoming region list for priority
        cases {
            dynamic "answer_data" {
              for_each = var.region_list
              content {
                answer_condition = "answer.pool == '${answer_data.value}'"
                should_keep = false
                value = answer_data.key+1
              }
            }
        }
    }
    rules {
      rule_type = "LIMIT"
      default_count = 1
    }
    ttl = var.steering_policy_ttl
}

resource "oci_dns_rrset" "geo_fallback_dns_record" {
  zone_name_or_id = var.dns_zone_name
  domain = var.dns_name
  rtype = "A"
  compartment_id = var.tenancy_ocid
  items {
    domain = var.dns_name
    rtype = "A"
    ttl = "60"
    rdata = var.fallback_host
   }
}

resource "oci_dns_steering_policy_attachment" "geo_steering_policy_attachment" {
    #Required
    domain_name = var.dns_name
    steering_policy_id = oci_dns_steering_policy.geo_steering_policy.id
    zone_id = data.oci_dns_zones.dns_zones.zones[0].id

    #Optional
    display_name = var.dns_name
}