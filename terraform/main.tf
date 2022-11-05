provider "kind" {}

resource "kind_cluster" "default" {
  name            = var.kind_cluster_name
  node_image      = "kindest/node:v1.25.3"
  kubeconfig_path = pathexpand(var.kind_cluster_config_path)
  wait_for_ready  = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"
      kubeadm_config_patches = [
        "kind: InitConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    node-labels: \"ingress-ready=true\"\n"
      ]
      extra_port_mappings {
        container_port = 80
        host_port      = 80
        listen_address = "0.0.0.0"
      }
      extra_port_mappings {
        container_port = 443
        host_port      = 443
        listen_address = "0.0.0.0"
      }
    }
    node {
      role = "worker"
    }
  }
}

resource "null_resource" "aws_ecr" {
  triggers = {
    key = uuid()
  }

  #  provisioner "local-exec" {
  #    command = <<EOF
  #    sleep 30
  #    kind load docker-image --name ortelius-in-a-box --nodes ortelius-in-a-box-control-plane,ortelius-in-a-box-worker 239907433624.dkr.ecr.eu-central-1.amazonaws.com/argocd:2.0.5.803-165841
  #    kind load docker-image --name ortelius-in-a-box --nodes ortelius-in-a-box-control-plane,ortelius-in-a-box-worker 239907433624.dkr.ecr.eu-central-1.amazonaws.com/redis:6.2.4-alpine
  #    kind load docker-image --name ortelius-in-a-box --nodes ortelius-in-a-box-control-plane,ortelius-in-a-box-worker 239907433624.dkr.ecr.eu-central-1.amazonaws.com/dex:v2.27.0
  #    EOF
  #  }
  #  depends_on = [kind_cluster.default]
}


provider "kubectl" {
  host                   = kind_cluster.default.endpoint
  cluster_ca_certificate = kind_cluster.default.cluster_ca_certificate
  client_certificate     = kind_cluster.default.client_certificate
  client_key             = kind_cluster.default.client_key
}

provider "helm" {
  debug = true
  kubernetes {
    host                   = kind_cluster.default.endpoint
    cluster_ca_certificate = kind_cluster.default.cluster_ca_certificate
    client_certificate     = kind_cluster.default.client_certificate
    client_key             = kind_cluster.default.client_key

  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  version          = "5.6.2"
  create_namespace = true
  depends_on = [kind_cluster.default]
}

#resource "null_resource" "helm_install" {
#  triggers = {
#    key = uuid()
#  }
#
#    provisioner "local-exec" {
#      command = <<EOF
#      #!/bin/bash
#      set -euo pipefail
#      echo "Adding & installing Keptn Ortelius Service & Ortelius"
#      helm repo add keptn-ortelius-service https://ortelius.github.io/keptn-ortelius-service
#      helm repo add ortelius https://ortelius.github.io/ortelius-charts/
#      helm install my-ms-dep-pkg-cud ortelius/ms-dep-pkg-cud --version 10.0.0-build.66
#      helm install my-ms-compitem-crud ortelius/ms-compitem-crud --version 10.0.0-build.78
#      helm install my-ms-dep-pkg-r ortelius/ms-dep-pkg-r --version 10.0.0-build.53
#      helm install my-ms-validate-user ortelius/ms-validate-user --version 10.0.0-build.48
#      helm install my-keptn-ortelius-service keptn-ortelius-service/keptn-ortelius-service --version 0.0.1
#      echo "Done"
#      EOF
#    }
#    depends_on = [kind_cluster.default]
#}

resource "helm_release" "keptn" {
  name = "keptn"

  repository       = "https://charts.keptn.sh"
  chart            = "keptn"
  namespace        = "keptn"
  version          = "0.19.1"
  create_namespace = true
  timeout          = "300"
  depends_on = [kind_cluster.default]
}
