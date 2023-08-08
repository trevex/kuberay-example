output "cluster_id" {
  value = module.cluster.id
}

output "artifact_repository_id" {
  value = google_artifact_registry_repository.images.id
}

output "artifact_repository_docker_url" {
  value = "${google_artifact_registry_repository.images.location}-docker.pkg.dev/${var.project}/${google_artifact_registry_repository.images.repository_id}"
}
