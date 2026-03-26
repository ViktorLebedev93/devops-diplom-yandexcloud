# VPC сеть
resource "yandex_vpc_network" "diplom_network" {
  name = "diplom-network"
}

# Публичные подсети в трёх зонах доступности
resource "yandex_vpc_subnet" "public_subnets" {
  count = 3

  name           = "public-subnet-${count.index + 1}"
  zone           = element(["ru-central1-a", "ru-central1-b", "ru-central1-d"], count.index)
  network_id     = yandex_vpc_network.diplom_network.id
  v4_cidr_blocks = ["10.${count.index + 10}.0.0/24"]
}

# NAT-инстанс в публичной подсети
resource "yandex_compute_instance" "nat_instance" {
  name        = "nat-instance"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd80mrhj8fl2oe87o4e1"
      size     = 20
    }
  }

  network_interface {
    subnet_id  = yandex_vpc_subnet.public_subnets[0].id
    ip_address = "10.10.0.254"
    nat        = true
  }

  metadata = {
    ssh-keys = "ubuntu:${file(var.public_key_path)}"
  }
}

# Route tables для приватных подсетей
resource "yandex_vpc_route_table" "private_routes" {
  count = 3

  name       = "private-route-${count.index + 1}"
  network_id = yandex_vpc_network.diplom_network.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    next_hop_address   = yandex_compute_instance.nat_instance.network_interface[0].ip_address
  }
}

# Приватные подсети для worker nodes (с route tables)
resource "yandex_vpc_subnet" "private_subnets" {
  count = 3

  name           = "private-subnet-${count.index + 1}"
  zone           = element(["ru-central1-a", "ru-central1-b", "ru-central1-d"], count.index)
  network_id     = yandex_vpc_network.diplom_network.id
  v4_cidr_blocks = ["192.168.${count.index + 10}.0/24"]
  route_table_id = yandex_vpc_route_table.private_routes[count.index].id
}
