terraform {
  required_version = ">= 1.0"
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.90"
    }
  }
}

provider "yandex" {
  token     = var.yc_token
  cloud_id  = var.yc_cloud_id
  folder_id = var.yc_folder_id
  zone      = var.default_zone
}

# Создание сервисного аккаунта для Terraform
resource "yandex_iam_service_account" "tf_sa" {
  name        = "terraform-sa"
  description = "Service account for Terraform operations"
}

# Назначение роли editor (минимально необходимые права)
resource "yandex_resourcemanager_folder_iam_member" "tf_sa_editor" {
  folder_id = var.yc_folder_id
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.tf_sa.id}"
}

# Создание статического ключа для сервисного аккаунта (для бекенда)
resource "yandex_iam_service_account_static_access_key" "tf_sa_key" {
  service_account_id = yandex_iam_service_account.tf_sa.id
  description        = "Static access key for Terraform S3 backend"
}

# Создание бакета для хранения state файла
resource "yandex_storage_bucket" "tf_state" {
  bucket     = "tf-state-lebedev-vv-diplom"
  acl        = "private"
  folder_id  = var.yc_folder_id

  versioning {
    enabled = true
  }

  lifecycle_rule {
    id      = "cleanup-old-versions"
    enabled = true
    
    noncurrent_version_expiration {
      days = 30
    }
  }

  tags = {
    Environment = "terraform"
    Project     = "diplom"
    Student     = "lebedev-vv"
  }
}

# Выводы для использования в основной конфигурации
output "sa_key_id" {
  value     = yandex_iam_service_account_static_access_key.tf_sa_key.id
  sensitive = true
}

output "sa_secret_key" {
  value     = yandex_iam_service_account_static_access_key.tf_sa_key.secret_key
  sensitive = true
}

output "tf_state_bucket" {
  value = yandex_storage_bucket.tf_state.bucket
}

output "service_account_id" {
  value = yandex_iam_service_account.tf_sa.id
}
