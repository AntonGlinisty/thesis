locals {
  zone        = "ru-central1-a"
  platform_id = "standard-v2"
  vm_image_id = "fd85u0rct32prepgjlv0"  # ubuntu 22.04
  port        = 8080
}

# vpc
resource "yandex_vpc_network" "my_vpc" {
  name = "my-vpc"
}

# frontend subnet
resource "yandex_vpc_subnet" "my_frontend_subnet" {
  name           = "my-frontend-subnet"
  zone           = local.zone
  network_id     = yandex_vpc_network.my_vpc.id
  v4_cidr_blocks = ["10.10.1.0/24"]
}

# backend subnet
resource "yandex_vpc_subnet" "my_backend_subnet" {
  name           = "my-backend-subnet"
  zone           = local.zone
  network_id     = yandex_vpc_network.my_vpc.id
  v4_cidr_blocks = ["10.10.2.0/24"]
}

# frontend vm
resource "yandex_compute_instance" "my_frontend_vm" {
  name        = "my-frontend-vm"
  platform_id = local.platform_id
  zone        = local.zone
  resources {
    cores  = 2
    memory = 2
  }
  boot_disk {
    initialize_params {
      image_id = local.vm_image_id
    }
  }
  network_interface {
    subnet_id = yandex_vpc_subnet.my_frontend_subnet.id
    nat       = true
  }
}

# backend vms
resource "yandex_compute_instance" "my_backend_vms" {
  count       = 3
  name        = "my-backend-vm-${count.index}"
  platform_id = local.platform_id
  zone        = local.zone
  resources {
    cores  = 2
    memory = 2
  }
  boot_disk {
    initialize_params {
      image_id = local.vm_image_id
    }
  }
  network_interface {
    subnet_id = yandex_vpc_subnet.my_backend_subnet.id
  }
}

# db vm
resource "yandex_compute_instance" "my_db_vm" {
  name        = "my-db-vm"
  platform_id = local.platform_id
  zone        = local.zone
  resources {
    cores  = 2
    memory = 2
  }
  boot_disk {
    initialize_params {
      image_id = local.vm_image_id
    }
  }
  network_interface {
    subnet_id = yandex_vpc_subnet.my_backend_subnet.id
  }
}

# target group
resource "yandex_alb_target_group" "my_target_group" {
  name = "my-target-group"
  dynamic "target" {
    for_each = yandex_compute_instance.my_backend_vms[*]
    content {
      subnet_id  = yandex_vpc_subnet.my_backend_subnet.id
      ip_address = target.value.network_interface[0].ip_address
    }
  }
}

# backend group
resource "yandex_alb_backend_group" "my_backend_group" {
  name = "my-backend-group"
  http_backend {
    name             = "my-http-backend"
    port             = local.port
    target_group_ids = [yandex_alb_target_group.my_target_group.id]
    healthcheck {
      timeout             = "1s"
      interval            = "1s"
      healthy_threshold   = 1
      unhealthy_threshold = 3
      http_healthcheck {
        path = "/ping"
      }
    }
  }
}

# http router
resource "yandex_alb_http_router" "my_http_router" {
  name = "my-http-router"
}

# virtual host
resource "yandex_alb_virtual_host" "my_virtual_host" {
  name           = "my-virtual-host"
  http_router_id = yandex_alb_http_router.my_http_router.id
  route {
    name = "my-route"
    http_route {
      http_route_action {
        backend_group_id = yandex_alb_backend_group.my_backend_group.id
      }
    }
  }
}

# load balancer
resource "yandex_alb_load_balancer" "my_load_balancer" {
  name       = "my-load-balancer"
  network_id = yandex_vpc_network.my_vpc.id
  allocation_policy {
    location {
      zone_id   = local.zone
      subnet_id = yandex_vpc_subnet.my_backend_subnet.id
    }
  }
  listener {
    name = "my-listener"
    endpoint {
      address {
        external_ipv4_address {}
      }
      ports = [local.port]
    }
    http {
      handler {
        http_router_id = yandex_alb_http_router.my_http_router.id
      }
    }
  }
}
