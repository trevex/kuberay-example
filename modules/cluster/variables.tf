variable "name" {
  type = string
}

variable "project" {
  type = string
}

variable "region" {
  type = string
}

variable "network_id" {
  type = string
}

variable "subnetwork_id" {
  type = string
}

variable "cluster_secondary_range_name" {
  type    = string
  default = "pods"
}

variable "services_secondary_range_name" {
  type    = string
  default = "services"
}

variable "master_ipv4_cidr_block" {
  type = string
}

variable "release_channel" {
  type    = string
  default = "REGULAR"
}

variable "node_pools" {
  type = map(object({
    machine_type    = string
    image_type      = optional(string, "COS_CONTAINERD")
    node_locations  = optional(set(string))
    min_node_count  = optional(number, 0)
    max_node_count  = number
    max_surge       = optional(number, 1)
    max_unavailable = optional(number, 0)
    preemptible     = optional(bool, false)
    guest_accelerator = optional(object({
      type                       = string
      count                      = number
      gpu_sharing_strategy       = optional(string)
      max_shared_clients_per_gpu = optional(number)
      gpu_driver_version         = optional(string, "DEFAULT")
    }))
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
}
