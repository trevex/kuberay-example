terraform {
  backend "gcs" {
    bucket = "nvoss-kuberay-demo-tf-state"
    prefix = "terraform/0-cluster"
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


# Enable required APIs

resource "google_project_service" "services" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "artifactregistry.googleapis.com",
    "notebooks.googleapis.com",
  ])
  project = var.project
  service = each.value
}


# Let's create our artifact registry for our container-images

resource "google_artifact_registry_repository" "images" {
  #checkov:skip=CKV_GCP_84:We do not want to use CSEK
  location      = var.region
  repository_id = "images"
  description   = "Primary container-image registry"
  format        = "DOCKER"

  depends_on = [google_project_service.services]
}


# The underlying network mainly for the cluster

module "network" {
  source = "../modules//network"

  name = "demo-network"
  subnetworks = [{
    name_affix    = "main" # full name will be `${name}-${name_affix}-${region}`
    ip_cidr_range = "10.10.0.0/20"
    region        = var.region
    secondary_ip_range = [{ # Use larger ranges in production!
      range_name    = "pods"
      ip_cidr_range = "10.10.32.0/19"
      }, {
      range_name    = "services"
      ip_cidr_range = "10.10.16.0/20"
    }]
  }]

  depends_on = [google_project_service.services]
}

# Create GKE Standard cluster with two node-pools: one for general workloads and another zonal pool for gpu-sharing

module "cluster" {
  source = "../modules//cluster"

  name                   = "demo-cluster"
  project                = var.project
  region                 = var.region
  network_id             = module.network.id
  subnetwork_id          = module.network.subnetworks["demo-network-main-${var.region}"].id
  master_ipv4_cidr_block = "172.16.0.0/28"
  dns_scope              = "VPC_SCOPE"

  node_pools = {
    default = {
      machine_type   = "n1-standard-8"
      max_node_count = 8
    }
    gpu-sharing = {
      # NOTE: I had issues running ray on COS leveraging GPUs and did not dig deeper,
      #       but native CUDA worked but the Ray images had issues detecting the GPU...
      #       => using Ubuntu instead...
      # image_type     = "UBUNTU_CONTAINERD"
      machine_type   = "n1-standard-16"
      node_locations = ["${var.region}-b"]
      min_node_count = 0
      max_node_count = 1 # let's limit costs of this example
      guest_accelerator = {
        type                       = "nvidia-tesla-t4"
        count                      = 1
        gpu_sharing_strategy       = "TIME_SHARING"
        max_shared_clients_per_gpu = 8
      }
    }
    gpu-l4 = {
      machine_type   = "g2-standard-16"
      disk_type      = "pd-ssd"
      node_locations = ["${var.region}-a"]
      min_node_count = 1
      max_node_count = 2
      guest_accelerator = {
        type               = "nvidia-l4"
        count              = 1
        gpu_driver_version = "LATEST"
      }
    }
  }

  depends_on = [module.network]
}

resource "google_artifact_registry_repository_iam_member" "cluster_ar_reader" {
  project    = google_artifact_registry_repository.images.project
  location   = google_artifact_registry_repository.images.location
  repository = google_artifact_registry_repository.images.name

  role   = "roles/artifactregistry.reader"
  member = "serviceAccount:${module.cluster.cluster_sa_email}"
}

