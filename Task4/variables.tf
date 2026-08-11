variable "yc_token" {
  type      = string
  sensitive = true
  default   = null
}
variable "cloud_id" { type = string }
variable "folder_id" { type = string }
variable "zone" {
  type    = string
  default = "ru-central1-a"
}
variable "project_name" {
  type    = string
  default = "data-platform"
}
variable "public_subnet_cidr" {
  type    = string
  default = "10.10.0.0/24"
}
variable "private_subnet_cidr" {
  type    = string
  default = "10.10.1.0/24"
}
variable "admin_cidrs" { type = list(string) }
variable "ssh_user" {
  type    = string
  default = "ubuntu"
}
variable "ssh_public_key" {
  type      = string
  sensitive = true
}
variable "image_family" {
  type    = string
  default = "ubuntu-2204-lts"
}
variable "platform_id" {
  type    = string
  default = "standard-v3"
}
variable "disk_type" {
  type    = string
  default = "network-ssd"
}
variable "bastion_boot_disk_gb" {
  type    = number
  default = 10
}
variable "dremio_executor_boot_disk_gb" {
  type    = number
  default = 30
}
variable "spark_worker_boot_disk_gb" {
  type    = number
  default = 25
}
variable "lakehouse_bucket_name" { type = string }
variable "backend_port" {
  type    = number
  default = 8080
}
variable "dremio_port" {
  type    = number
  default = 9047
}
variable "dremio_executor_count" {
  type    = number
  default = 1
}
variable "spark_worker_count" {
  type    = number
  default = 1
}
variable "postgresql_resource_preset" {
  type    = string
  default = "s2.micro"
}
variable "postgresql_disk_gb" {
  type    = number
  default = 20
}

variable "platform_nodes" {
  description = "Private VMs; security_zone must be portal, backend, or data."
  type = map(object({
    cores         = number
    memory_gb     = number
    boot_disk_gb  = number
    security_zone = string
  }))
}
