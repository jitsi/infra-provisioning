packer {
  required_plugins {
    oracle = {
      version = ">= 1.0.3"
      source  = "github.com/hashicorp/oracle"
    }
    ansible = {
      version = ">= 1.1.1"
      source  = "github.com/hashicorp/ansible"
    }
  }
}    

