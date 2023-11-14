terraform {
  backend "gcs" {
    bucket = "nvoss-kuberay-demo-tf-state"
    prefix = "terraform/1-operator"
  }
}

provider "google" {
  project = var.project
  region  = var.region
}

provider "google-beta" {
  project = var.project
  region  = var.region
}


data "google_client_config" "cluster" {}


data "google_container_cluster" "cluster" {
  project  = var.project
  location = var.region
  name     = "demo-cluster" # hardcoded!
}

provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.cluster.endpoint}"
  token                  = data.google_client_config.cluster.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.cluster.master_auth[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = "https://${data.google_container_cluster.cluster.endpoint}"
    token                  = data.google_client_config.cluster.access_token
    cluster_ca_certificate = base64decode(data.google_container_cluster.cluster.master_auth[0].cluster_ca_certificate)
  }
}

resource "helm_release" "kuberay-operator" {
  name       = "kuberay-operator"
  repository = "https://ray-project.github.io/kuberay-helm/"
  chart      = "kuberay-operator"
  version    = var.operator_version

  values = [<<EOF
env:
- name: CLUSTER_DOMAIN
  value: "demo-cluster"
EOF
  ]
}

resource "kubernetes_config_map" "fluent-bit" {
  metadata {
    name = "fluentbit-config"
  }

  data = {
    "fluent-bit.conf" = "${file("${path.module}/fluent-bit.conf")}"
    "parsers.conf"    = "${file("${path.module}/parsers.conf")}"
  }
}

resource "helm_release" "kuberay-l4-cluster" {
  name       = "l4-cluster"
  repository = "https://ray-project.github.io/kuberay-helm/"
  chart      = "ray-cluster"
  version    = var.operator_version

  values = [file("${path.module}/cluster-base.yaml")]

  depends_on = [
    helm_release.kuberay-operator,
    kubernetes_config_map.fluent-bit
  ]
}

# TODO: google_workbench_instance not yet supported :/

