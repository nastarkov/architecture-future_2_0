# Replace REPLACE_ME values. Keep YC_TOKEN outside this file: export YC_TOKEN="...".
cloud_id  = "REPLACE_ME_CLOUD_ID"
folder_id = "REPLACE_ME_FOLDER_ID"

project_name        = "data-platform"
zone                = "ru-central1-a"
public_subnet_cidr  = "10.10.0.0/24"
private_subnet_cidr = "10.10.1.0/24"
admin_cidrs         = ["203.0.113.10/32"]

ssh_user       = "ubuntu"
ssh_public_key = "ssh-ed25519 REPLACE_ME user@workstation"

# Must be globally unique in Yandex Object Storage.
lakehouse_bucket_name = "REPLACE_ME-unique-lakehouse-bucket"

# Increase these counts to scale the distributed query and processing clusters.
dremio_executor_count        = 1
spark_worker_count           = 1
bastion_boot_disk_gb         = 10
dremio_executor_boot_disk_gb = 30
spark_worker_boot_disk_gb    = 25

platform_nodes = {
  portal-ui          = { cores = 2, memory_gb = 4, boot_disk_gb = 10, security_zone = "portal" }
  portal-backend     = { cores = 2, memory_gb = 4, boot_disk_gb = 10, security_zone = "backend" }
  dremio-coordinator = { cores = 4, memory_gb = 16, boot_disk_gb = 30, security_zone = "data" }
  airflow            = { cores = 2, memory_gb = 8, boot_disk_gb = 15, security_zone = "data" }
  spark-master       = { cores = 4, memory_gb = 16, boot_disk_gb = 25, security_zone = "data" }
}
