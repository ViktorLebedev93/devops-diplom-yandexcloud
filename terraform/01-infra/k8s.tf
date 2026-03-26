# KMS ключ для шифрования данных в кластере
resource "yandex_kms_symmetric_key" "k8s_key" {
  name              = "k8s-encryption-key"
  description       = "Key for Kubernetes cluster encryption"
  default_algorithm = "AES_128"
  rotation_period   = "8760h"
}

# Сервисный аккаунт для кластера
resource "yandex_iam_service_account" "k8s_cluster_sa" {
  name        = "k8s-cluster-sa"
  description = "Service account for Kubernetes cluster"
}

resource "yandex_iam_service_account" "k8s_node_sa" {
  name        = "k8s-node-sa"
  description = "Service account for Kubernetes nodes"
}

resource "yandex_resourcemanager_folder_iam_member" "k8s_cluster_sa_editor" {
  folder_id = var.yc_folder_id
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.k8s_cluster_sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "k8s_node_sa_editor" {
  folder_id = var.yc_folder_id
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.k8s_node_sa.id}"
}

# Региональный мастер Kubernetes
resource "yandex_kubernetes_cluster" "diplom_cluster" {
  name        = var.cluster_name
  description = "Kubernetes cluster for diploma project"
  network_id  = yandex_vpc_network.diplom_network.id

  master {
    version = "1.31"
    regional {
      region = "ru-central1"
      location {
        zone      = "ru-central1-a"
        subnet_id = yandex_vpc_subnet.public_subnets[0].id
      }
      location {
        zone      = "ru-central1-b"
        subnet_id = yandex_vpc_subnet.public_subnets[1].id
      }
      location {
        zone      = "ru-central1-d"
        subnet_id = yandex_vpc_subnet.public_subnets[2].id
      }
    }
    public_ip = true
  }

  service_account_id      = yandex_iam_service_account.k8s_cluster_sa.id
  node_service_account_id = yandex_iam_service_account.k8s_node_sa.id

  kms_provider {
    key_id = yandex_kms_symmetric_key.k8s_key.id
  }

  depends_on = [
    yandex_resourcemanager_folder_iam_member.k8s_cluster_sa_editor,
    yandex_resourcemanager_folder_iam_member.k8s_node_sa_editor
  ]
}

# Группа worker nodes (прерываемые ВМ)
resource "yandex_kubernetes_node_group" "worker_group" {
  cluster_id = yandex_kubernetes_cluster.diplom_cluster.id
  name       = "worker-group"
  version    = "1.31"

  instance_template {
    platform_id = "standard-v3"
    
    resources {
      cores  = var.node_cores
      memory = var.node_memory
    }

    boot_disk {
      type = "network-ssd"
      size = 50
    }

    network_interface {
      subnet_ids = [
        yandex_vpc_subnet.private_subnets[0].id,
        yandex_vpc_subnet.private_subnets[1].id,
        yandex_vpc_subnet.private_subnets[2].id
      ]
      nat = false
    }

    metadata = {
      ssh-keys = "ubuntu:${file(var.public_key_path)}"
    }
  }

  scale_policy {
    fixed_scale {
      size = var.node_group_size
    }
  }

  allocation_policy {
    location {
      zone = "ru-central1-a"
    }
    location {
      zone = "ru-central1-b"
    }
    location {
      zone = "ru-central1-d"
    }
  }

  node_labels = {
    "node-type"   = "worker"
    "preemptible" = "true"
  }

  node_taints = ["preemptible=true:NoSchedule"]
}

# Container Registry для хранения Docker образов
resource "yandex_container_registry" "diplom_registry" {
  name      = "diplom-registry"
  folder_id = var.yc_folder_id
}

# Назначение прав на Registry
resource "yandex_resourcemanager_folder_iam_member" "registry_pusher" {
  folder_id = var.yc_folder_id
  role      = "container-registry.images.pusher"
  member    = "serviceAccount:${yandex_iam_service_account.k8s_cluster_sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "registry_puller" {
  folder_id = var.yc_folder_id
  role      = "container-registry.images.puller"
  member    = "serviceAccount:${yandex_iam_service_account.k8s_node_sa.id}"
}

# Выводы
output "cluster_endpoint" {
  value = yandex_kubernetes_cluster.diplom_cluster.master[0].external_v4_endpoint
}

output "cluster_ca_certificate" {
  value     = yandex_kubernetes_cluster.diplom_cluster.master[0].cluster_ca_certificate
  sensitive = true
}

output "container_registry_id" {
  value = yandex_container_registry.diplom_registry.id
}
