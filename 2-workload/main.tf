terraform {
  backend "gcs" {
    bucket = "nvoss-kuberay-tf-state"
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
  name     = "cluster-kuberay"
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
  name       = "example-cluster"
  repository = "https://ray-project.github.io/kuberay-helm/"
  chart      = "ray-cluster"
  version    = var.cluster_version
  values = [
    file("${path.module}/cluster-values.yaml")
  ]
}
