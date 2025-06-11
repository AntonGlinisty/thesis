locals {
  availability_zone = "MS1"
  flavor_id         = "25ae869c-be29-4840-8e12-99e046d2dbd4"
  image_id          = "c1703b98-c903-436c-9de3-370af53a306f"
  port              = 8080
}

# vpc
resource "vkcs_networking_network" "my_vpc" {
  name = "my-vpc"
}

# frontend subnet
resource "vkcs_networking_subnet" "my_frontend_subnet" {
  name        = "my-frontend-subnet"
  network_id  = vkcs_networking_network.my_vpc.id
  cidr        = "10.10.1.0/24"
}

# backend subnet
resource "vkcs_networking_subnet" "my_backend_subnet" {
  name        = "my-backend-subnet"
  network_id  = vkcs_networking_network.my_vpc.id
  cidr        = "10.10.2.0/24"
}

# frontend port
resource "vkcs_networking_port" "my_frontend_port" {
  name       = "my-frontend-port"
  network_id = vkcs_networking_network.my_vpc.id
  fixed_ip {
    subnet_id = vkcs_networking_subnet.my_frontend_subnet.id
  }
}

# frontend vm
resource "vkcs_compute_instance" "my_frontend_vm" {
  name              = "my-frontend-vm"
  flavor_id         = local.flavor_id
  image_id          = local.image_id
  availability_zone = local.availability_zone
  
  network {
    port = vkcs_networking_port.my_frontend_port.id
  }
}

# backend ports
resource "vkcs_networking_port" "my_backend_ports" {
  count      = 3
  name       = "my-backend-ports-${count.index}"
  network_id = vkcs_networking_network.my_vpc.id
  fixed_ip {
    subnet_id = vkcs_networking_subnet.my_backend_subnet.id
  }
}

# backend vms
resource "vkcs_compute_instance" "my_backend_vms" {
  count             = 3
  name              = "my-backend-vms-${count.index}"
  flavor_id         = local.flavor_id
  image_id          = local.image_id
  availability_zone = local.availability_zone
  
  network {
    port = vkcs_networking_port.my_backend_ports[count.index].id
  }
}

# db port
resource "vkcs_networking_port" "my_db_port" {
  name        = "my-db-port"
  network_id  = vkcs_networking_network.my_vpc.id

  fixed_ip {
    subnet_id  = vkcs_networking_subnet.my_backend_subnet.id
  }
}

# db vm
resource "vkcs_compute_instance" "my_db_vm" {
  name              = "my-db-vm"
  flavor_id         = local.flavor_id
  image_id          = local.image_id
  availability_zone = local.availability_zone
  
  network {
    port = vkcs_networking_port.my_db_port.id
  }
}

# lb
resource "vkcs_lb_loadbalancer" "my_lb" {
  name          = "my-lb"
  vip_subnet_id = vkcs_networking_subnet.my_backend_subnet.id
}

# lb listener
resource "vkcs_lb_listener" "my_lb_listener" {
  name            = "my-lb-listener"
  loadbalancer_id = vkcs_lb_loadbalancer.my_lb.id
  protocol        = "HTTP"
  protocol_port   = local.port
}

# lb pool
resource "vkcs_lb_pool" "my_lb_pool" {
  name        = "my-lb-pool"
  listener_id = vkcs_lb_listener.my_lb_listener.id
  protocol    = "HTTP"
  lb_method   = "ROUND_ROBIN"
}

# backend lb members
resource "vkcs_lb_member" "my_backend_lb_members" {
  count         = 3
  pool_id       = vkcs_lb_pool.my_lb_pool.id
  address       = vkcs_compute_instance.my_backend_vms[count.index].network[0].fixed_ip_v4
  protocol_port = local.port
  subnet_id     = vkcs_networking_subnet.my_backend_subnet.id
}

