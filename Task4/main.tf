terraform {
  required_version = ">= 1.5.0"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.220"
    }
  }
}

provider "yandex" {
  token     = var.yc_token
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
  zone      = var.zone
}

data "yandex_compute_image" "ubuntu" {
  family = var.image_family
}

locals {
  security_group_ids = {
    portal  = yandex_vpc_security_group.portal.id
    backend = yandex_vpc_security_group.backend.id
    data    = yandex_vpc_security_group.data.id
  }
}

resource "yandex_vpc_network" "platform" {
  name        = "${var.project_name}-network"
  description = "Network for the Data & Analytics Platform"
}

resource "yandex_vpc_subnet" "public" {
  name           = "${var.project_name}-public"
  zone           = var.zone
  network_id     = yandex_vpc_network.platform.id
  v4_cidr_blocks = [var.public_subnet_cidr]
}

resource "yandex_vpc_subnet" "private" {
  name           = "${var.project_name}-private"
  zone           = var.zone
  network_id     = yandex_vpc_network.platform.id
  v4_cidr_blocks = [var.private_subnet_cidr]
}

resource "yandex_vpc_security_group" "bastion" {
  name       = "${var.project_name}-bastion-sg"
  network_id = yandex_vpc_network.platform.id

  ingress {
    description    = "SSH from administrators"
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = var.admin_cidrs
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "portal" {
  name       = "${var.project_name}-portal-sg"
  network_id = yandex_vpc_network.platform.id

  ingress {
    description    = "Public traffic through the Network Load Balancer"
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description       = "SSH from the bastion"
    protocol          = "TCP"
    port              = 22
    security_group_id = yandex_vpc_security_group.bastion.id
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "backend" {
  name       = "${var.project_name}-backend-sg"
  network_id = yandex_vpc_network.platform.id

  ingress {
    description       = "Portal UI to Backend API"
    protocol          = "TCP"
    port              = var.backend_port
    security_group_id = yandex_vpc_security_group.portal.id
  }

  ingress {
    description       = "SSH from the bastion"
    protocol          = "TCP"
    port              = 22
    security_group_id = yandex_vpc_security_group.bastion.id
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "data" {
  name       = "${var.project_name}-data-sg"
  network_id = yandex_vpc_network.platform.id

  ingress {
    description       = "Backend to Dremio"
    protocol          = "TCP"
    port              = var.dremio_port
    security_group_id = yandex_vpc_security_group.backend.id
  }

  ingress {
    description    = "Private data-platform traffic"
    protocol       = "ANY"
    v4_cidr_blocks = [var.private_subnet_cidr]
  }

  ingress {
    description       = "SSH from the bastion"
    protocol          = "TCP"
    port              = 22
    security_group_id = yandex_vpc_security_group.bastion.id
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "database" {
  name       = "${var.project_name}-database-sg"
  network_id = yandex_vpc_network.platform.id

  ingress {
    description       = "Backend to PostgreSQL"
    protocol          = "TCP"
    port              = 6432
    security_group_id = yandex_vpc_security_group.backend.id
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_iam_service_account" "platform" {
  name        = "${var.project_name}-sa"
  description = "Identity used by Data & Analytics Platform VMs"
}

resource "yandex_resourcemanager_folder_iam_member" "platform_storage_editor" {
  folder_id = var.folder_id
  role      = "storage.admin"
  member    = "serviceAccount:${yandex_iam_service_account.platform.id}"
}

resource "yandex_iam_service_account_static_access_key" "platform_storage" {
  service_account_id = yandex_iam_service_account.platform.id
  description        = "S3 key for the Terraform-managed Lakehouse bucket"
}

resource "yandex_storage_bucket" "lakehouse" {
  bucket     = var.lakehouse_bucket_name
  access_key = yandex_iam_service_account_static_access_key.platform_storage.access_key
  secret_key = yandex_iam_service_account_static_access_key.platform_storage.secret_key

  anonymous_access_flags {
    read        = false
    list        = false
    config_read = false
  }

  versioning {
    enabled = true
  }
}

resource "yandex_lockbox_secret" "platform" {
  name        = "${var.project_name}-runtime-secrets"
  description = "Container for application secrets; CI/CD adds secret versions"
}

resource "yandex_compute_instance" "bastion" {
  name        = "${var.project_name}-bastion"
  hostname    = "${var.project_name}-bastion"
  platform_id = var.platform_id
  zone        = var.zone

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      type     = var.disk_type
      size     = var.bastion_boot_disk_gb
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.public.id
    security_group_ids = [yandex_vpc_security_group.bastion.id]
    nat                = true
  }

  metadata = { ssh-keys = "${var.ssh_user}:${var.ssh_public_key}" }
}

resource "yandex_compute_instance" "platform" {
  for_each = var.platform_nodes

  name        = "${var.project_name}-${each.key}"
  hostname    = "${var.project_name}-${each.key}"
  platform_id = var.platform_id
  zone        = var.zone

  resources {
    cores         = each.value.cores
    memory        = each.value.memory_gb
    core_fraction = 100
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      type     = var.disk_type
      size     = each.value.boot_disk_gb
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.private.id
    security_group_ids = [local.security_group_ids[each.value.security_zone]]
  }

  service_account_id = yandex_iam_service_account.platform.id
  metadata           = { ssh-keys = "${var.ssh_user}:${var.ssh_public_key}" }

  depends_on = [yandex_resourcemanager_folder_iam_member.platform_storage_editor]
}

resource "yandex_compute_instance" "dremio_executor" {
  count = var.dremio_executor_count

  name        = "${var.project_name}-dremio-executor-${count.index + 1}"
  hostname    = "${var.project_name}-dremio-executor-${count.index + 1}"
  platform_id = var.platform_id
  zone        = var.zone

  resources {
    cores         = 4
    memory        = 16
    core_fraction = 100
  }
  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      type     = var.disk_type
      size     = var.dremio_executor_boot_disk_gb
    }
  }
  network_interface {
    subnet_id          = yandex_vpc_subnet.private.id
    security_group_ids = [yandex_vpc_security_group.data.id]
  }
  service_account_id = yandex_iam_service_account.platform.id
  metadata           = { ssh-keys = "${var.ssh_user}:${var.ssh_public_key}" }
}

resource "yandex_compute_instance" "spark_worker" {
  count = var.spark_worker_count

  name        = "${var.project_name}-spark-worker-${count.index + 1}"
  hostname    = "${var.project_name}-spark-worker-${count.index + 1}"
  platform_id = var.platform_id
  zone        = var.zone

  resources {
    cores         = 4
    memory        = 16
    core_fraction = 100
  }
  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      type     = var.disk_type
      size     = var.spark_worker_boot_disk_gb
    }
  }
  network_interface {
    subnet_id          = yandex_vpc_subnet.private.id
    security_group_ids = [yandex_vpc_security_group.data.id]
  }
  service_account_id = yandex_iam_service_account.platform.id
  metadata           = { ssh-keys = "${var.ssh_user}:${var.ssh_public_key}" }
}

resource "yandex_lb_target_group" "portal" {
  name = "${var.project_name}-portal-targets"

  target {
    subnet_id = yandex_vpc_subnet.private.id
    address   = yandex_compute_instance.platform["portal-ui"].network_interface[0].ip_address
  }
}

resource "yandex_lb_network_load_balancer" "portal" {
  name = "${var.project_name}-public-nlb"

  listener {
    name = "http"
    port = 80
    external_address_spec { ip_version = "ipv4" }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.portal.id
    healthcheck {
      name = "portal-http"
      http_options {
        port = 80
        path = "/health"
      }
    }
  }
}

resource "yandex_mdb_postgresql_cluster" "metadata" {
  name               = "${var.project_name}-metadata"
  environment        = "PRESTABLE"
  network_id         = yandex_vpc_network.platform.id
  security_group_ids = [yandex_vpc_security_group.database.id]

  config {
    version = 17
    resources {
      resource_preset_id = var.postgresql_resource_preset
      disk_type_id       = var.disk_type
      disk_size          = var.postgresql_disk_gb
    }
  }

  host {
    zone      = var.zone
    name      = "${var.project_name}-metadata-a"
    subnet_id = yandex_vpc_subnet.private.id
  }
}
