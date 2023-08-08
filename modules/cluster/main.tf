resource "google_service_account" "cluster" {
  account_id   = var.name
  display_name = "Service Account used by GKE cluster: '${var.name}'."
}

resource "google_project_iam_member" "cluster_log_writer" {
  project = var.project
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cluster.email}"
}

resource "google_project_iam_member" "cluster_metric_writer" {
  project = var.project
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.cluster.email}"
}

resource "google_project_iam_member" "cluster_monitoring_viewer" {
  project = var.project
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.cluster.email}"
}

resource "google_project_iam_member" "cluster_metadata_writer" {
  project = var.project
  role    = "roles/stackdriver.resourceMetadata.writer"
  member  = "serviceAccount:${google_service_account.cluster.email}"
}

#tfsec:ignore:google-gke-enable-network-policy We keep things simple for this demo
#tfsec:ignore:google-gke-enable-master-networks We keep things simple for this demo
#tfsec:ignore:google-gke-use-service-account False positive, we have a ServiceAccount setup
#tfsec:ignore:google-gke-metadata-endpoints-disabled False positive, ...
#tfsec:ignore:google-gke-enforce-pod-security-policy No PSPs, but no privileged pods allowed either...
resource "google_container_cluster" "cluster" {

  provider = google-beta

  name     = var.name
  location = var.region

  network           = var.network_id
  subnetwork        = var.subnetwork_id
  datapath_provider = "ADVANCED_DATAPATH" # We use Dataplane V2

  resource_labels = {
    "managed-by" = "tf"
  }

  remove_default_node_pool = true
  initial_node_count       = 1

  release_channel {
    channel = var.release_channel
  }

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = var.cluster_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
    master_global_access_config {
      enabled = true
    }
  }

  workload_identity_config {
    workload_pool = "${var.project}.svc.id.goog"
  }

  node_config {
    # Argolis specific to avoid issue with org-policy
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  lifecycle {
    ignore_changes = [
      node_config # required due to Argolis workaround
    ]
  }

  timeouts {
    create = "45m"
    update = "45m"
    delete = "45m"
  }
}


resource "google_compute_firewall" "cluster_admission_controller_access" {
  project     = var.project
  name        = "allow-gke-cp-access-admission-controller"
  network     = var.network_id
  description = "Allow ingress on tcp from GKE Control-Plane"

  allow {
    protocol = "tcp"
  }

  source_ranges = [google_container_cluster.cluster.private_cluster_config[0].master_ipv4_cidr_block]
  target_tags   = [var.name]
}


resource "google_container_node_pool" "default" {
  provider = google-beta

  for_each = var.node_pools

  name     = each.key
  project  = var.project
  location = var.region
  cluster  = google_container_cluster.cluster.name

  node_locations     = each.value.node_locations
  initial_node_count = each.value.min_node_count

  autoscaling {
    min_node_count = each.value.min_node_count
    max_node_count = each.value.max_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = each.value.max_surge
    max_unavailable = each.value.max_unavailable
  }

  node_config {
    image_type      = each.value.image_type
    machine_type    = each.value.machine_type
    preemptible     = each.value.preemptible
    local_ssd_count = 0
    disk_size_gb    = 80
    disk_type       = "pd-standard"

    # No access to legacy metadata servers
    metadata = {
      "disable-legacy-endpoints" = true
    }

    # We specify the service account to minimize permissions and not use default compute account
    service_account = google_service_account.cluster.email

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    dynamic "guest_accelerator" {
      for_each = each.value.guest_accelerator != null ? [each.value.guest_accelerator] : []
      content {
        type  = guest_accelerator.value.type
        count = guest_accelerator.value.count
        gpu_sharing_config {
          gpu_sharing_strategy       = guest_accelerator.value.gpu_sharing_strategy
          max_shared_clients_per_gpu = guest_accelerator.value.max_shared_clients_per_gpu
        }
        gpu_driver_installation_config {
          gpu_driver_version = guest_accelerator.value.gpu_driver_version
        }
      }
    }

    # TODO: only relying on NVIDIA taint for now
    #       https://github.com/hashicorp/terraform-provider-google/issues/7928
    # dynamic "taint" {
    #   for_each = each.value.taints
    #   content {
    #     key    = taint.value.key
    #     value  = taint.value.value
    #     effect = taint.value.effect
    #   }
    # }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/monitoring" # required for Managed Prometheus
    ]

    tags = [var.name]
  }

  lifecycle {
    ignore_changes  = [initial_node_count, node_config[0].taint]
    prevent_destroy = false
  }

  timeouts {
    create = "45m"
    update = "45m"
    delete = "45m"
  }
}

