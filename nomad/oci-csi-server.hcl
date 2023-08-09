job "plugin-oci-bs-controller" {
  datacenters = ["dc1"]

  group "controller" {
    task "provisioner" {
      driver = "docker"

      config {
        image = "quay.io/k8scsi/csi-provisioner:v1.6.0"
        args = [
          "--csi-address=/var/run/shared-tmpfs/csi.sock",
          "--volume-name-prefix=csi",
          "--feature-gates=Topology=true",
          "--timeout=120s",
          "--enable-leader-election=false",
        //   "--leader-election-type=leases",
        //   "--leader-election-namespace=kube-system",
        ]
      }

    }
    task "plugin" {
      driver = "docker"

      config {
        image = "iad.ocir.io/oracle/cloud-provider-oci:0.12.0"
        command = "/usr/local/bin/oci-csi-controller-driver"
        args = [
          "--v=2",
          "--endpoint=unix://var/run/shared-tmpfs/csi.sock",
        ]
      }

      csi_plugin {
        id        = "oci-bs0"
        type      = "controller"
        mount_dir = "/var/run/shared-tmpfs/"
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}