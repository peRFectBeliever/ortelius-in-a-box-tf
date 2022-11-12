provider "kind" {}

resource "kind_cluster" "ortelius" {
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

resource "null_resource" "kubectl" {
  depends_on = [kind_cluster.ortelius]
  triggers = {
    key = uuid()
  }

  provisioner "local-exec" {
    command = <<EOF
      kubectl create secret generic pgcred --from-literal=DBUserName=postgres --from-literal=DBPassword=postgres --from-literal=DBHost=localhost --from-literal=DBPort=5432 --from-literal=DBName=postgres -n ortelius
      sleep 45
      kubectl patch deployment keptn-keptn-ortelius-service --patch-file patch-keptn-image.yaml -n keptn
      kubectl patch deployment ms-validate-user --patch-file patch-ms-validate-user.yaml -n ortelius
    EOF
  }
}

resource "time_sleep" "wait_40_seconds" {
  create_duration = "40s"
}

resource "null_resource" "kind_copy_container_images" {
  depends_on = [time_sleep.wait_40_seconds]
  triggers = {
    key = uuid()
  }

  provisioner "local-exec" {
    command = <<EOF
      kind load docker-image --name ortelius-in-a-box --nodes ortelius-in-a-box-control-plane,ortelius-in-a-box-worker quay.io/ortelius/ortelius
      kind load docker-image --name ortelius-in-a-box --nodes ortelius-in-a-box-control-plane,ortelius-in-a-box-worker ghcr.io/ortelius/keptn-ortelius-service:0.0.2-dev
      kind load docker-image --name ortelius-in-a-box --nodes ortelius-in-a-box-control-plane,ortelius-in-a-box-worker docker.io/istio/base:1.16-2022-11-02T13-31-52
    EOF
  }
}

provider "kubectl" {
  host                   = kind_cluster.ortelius.endpoint
  cluster_ca_certificate = kind_cluster.ortelius.cluster_ca_certificate
  client_certificate     = kind_cluster.ortelius.client_certificate
  client_key             = kind_cluster.ortelius.client_key
  load_config_file       = false
}

provider "helm" {
  #debug = true
  kubernetes {
    host                   = kind_cluster.ortelius.endpoint
    cluster_ca_certificate = kind_cluster.ortelius.cluster_ca_certificate
    client_certificate     = kind_cluster.ortelius.client_certificate
    client_key             = kind_cluster.ortelius.client_key
    config_path            = "~/.kube/config"
  }
}

resource "helm_release" "argocd" {
  name = "argocd"
  #repository       = "https://argoproj.github.io/argo-helm"
  chart = "argo-cd"
  #version          = "5.6.2"
  namespace        = "argocd"
  create_namespace = true
  depends_on       = [kind_cluster.ortelius]

  values = [
    file("argo-cd/values.yaml"),
  ]
}

resource "helm_release" "ortelius" {
  name = "ortelius"
  #  repository       = "https://ortelius.github.io/ortelius-charts/"
  chart            = "ortelius"
  namespace        = "ortelius"
  create_namespace = true
  #  force_update     = true
  depends_on = [kind_cluster.ortelius]
  timeout    = 900

  values = [
    file("ortelius/values.yaml"),
  ]
}

resource "helm_release" "keptn" {
  name             = "keptn"
  repository       = "https://ortelius.github.io/keptn-ortelius-service"
  chart            = "keptn-ortelius-service"
  namespace        = "keptn"
  create_namespace = true
  depends_on       = [kind_cluster.ortelius]
}

resource "helm_release" "istio_banzaicloud" {
  name             = "banzaicloud"
  chart            = "istio-operator"
  namespace        = "istio-system"
  create_namespace = true
  depends_on       = [kind_cluster.ortelius]
  timeout          = 900

  values = [
    file("istio-operator/values.yaml"),
  ]
}
