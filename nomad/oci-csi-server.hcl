job "plugin-oci-bs-controller" {
  datacenters = ["dc1"]

  group "controller" {
    task "csi-volume-provisioner" {
      driver = "docker"

      config {
        image = "registry.k8s.io/sig-storage/csi-provisioner:v3.5.0"
        args = [
          "--csi-address=/alloc/tmp/csi.sock",
          "--volume-name-prefix=csi",
          "--feature-gates=Topology=true",
          "--timeout=120s",
          "--enable-leader-election=false",
        //   "--leader-election-type=leases",
        //   "--leader-election-namespace=kube-system",
        ]
      }

    }
    task "fss-volume-provisioner" {
      driver = "docker"

      config {
        image = "registry.k8s.io/sig-storage/csi-provisioner:v3.5.0"
        args = [
          "--csi-address=/alloc/tmp/csi-fss.sock",
          "--volume-name-prefix=csi-fss",
          "--feature-gates=Topology=true",
          "--timeout=120s",
          "--enable-leader-election=false",
        //   "--leader-election-type=leases",
        //   "--leader-election-namespace=kube-system",
        ]
      }

    }

    task "csi-resizer" {
      driver = "docker"

      config {
        image = "k8s.gcr.io/sig-storage/csi-resizer:v1.7.0"
        args = [
          "--csi-address=/alloc/tmp/csi.sock",
          "--enable-leader-election=false",
        //   "--leader-election-type=leases",
        //   "--leader-election-namespace=kube-system",
        ]
      }

    }

    task "snapshot-controller" {
      driver = "docker"

      config {
        image = "registry.k8s.io/sig-storage/snapshot-controller:v6.2.0"
        args = [
          "--csi-address=/alloc/tmp/csi.sock",
          "--enable-leader-election=false",
        //   "--leader-election-type=leases",
        //   "--leader-election-namespace=kube-system",
        ]
      }      
    }


    task "csi-snapshotter" {
      driver = "docker"

      config {
        image = "registry.k8s.io/sig-storage/csi-snapshotter:v6.2.0"
        args = [
          "--csi-address=/alloc/tmp/csi.sock",
          "--enable-leader-election=false",
        //   "--leader-election-type=leases",
        //   "--leader-election-namespace=kube-system",
        ]
      }
    }

    task "csi-attacher" {
      driver = "docker"

      config {
        image = "k8s.gcr.io/sig-storage/csi-attacher:v4.2.0"
        args = [
          "--csi-address=/alloc/tmp/csi.sock",
          "--volume-name-prefix=csi-fss",
          "--feature-gates=Topology=true",
          "--timeout=120s",
          "--enable-leader-election=false",
        //   "--leader-election-type=leases",
        //   "--leader-election-namespace=kube-system",
        ]
      }

    }

    task "csi-provisioner" {
      driver = "docker"

      config {
        image = "quay.io/k8scsi/csi-provisioner:v1.6.0"
        args = [
          "--csi-address=/alloc/tmp/csi.sock",
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
          "--endpoint=unix://alloc/tmp/csi.sock",
          "--fss-csi-endpoint=unix://alloc/tmp/csi-fss.sock"
        ]
      }

      csi_plugin {
        id        = "oci-bs0"
        type      = "controller"
        mount_dir = "/alloc/tmp"
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}