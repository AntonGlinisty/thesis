locals {
  flavor_id = "25ae869c-be29-4840-8e12-99e046d2dbd4"
  image_id  = "c1703b98-c903-436c-9de3-370af53a306f"
}

resource "vkcs_networking_network" "vpc" {
  name = "my-vpc"
}

resource "vkcs_networking_subnet" "frontend_subnet" {
  name        = "my-frontend-subnet"
  network_id  = vkcs_networking_network.vpc.id
  cidr        = "10.10.1.0/24"
  enable_dhcp = true
}

resource "vkcs_networking_subnet" "backend_subnet" {
  name        = "my-backend-subnet"
  network_id  = vkcs_networking_network.vpc.id
  cidr        = "10.10.2.0/24"
}

data "vkcs_networking_network" "external_network" {
  name = "internet"
}

resource "vkcs_networking_router" "router" {
  name                = "my-router"
  external_network_id = data.vkcs_networking_network.external_network.id
}

resource "vkcs_networking_router_interface" "frontend_router_if" {
  router_id = vkcs_networking_router.router.id
  subnet_id = vkcs_networking_subnet.frontend_subnet.id
}

resource "vkcs_networking_router_interface" "backend_router_if" {
  router_id = vkcs_networking_router.router.id
  subnet_id = vkcs_networking_subnet.backend_subnet.id
}

resource "vkcs_networking_secgroup" "frontend_sg" {
  name  = "my-frontend-sg"
}

resource "vkcs_networking_secgroup_rule" "frontend_http_rule" {
  direction         = "ingress"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = vkcs_networking_secgroup.frontend_sg.id
}

resource "vkcs_networking_secgroup_rule" "frontend_https_rule" {
  direction         = "ingress"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = vkcs_networking_secgroup.frontend_sg.id
}

resource "vkcs_networking_secgroup_rule" "frontend_ssh_rule" {
  direction         = "ingress"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = vkcs_networking_secgroup.frontend_sg.id
}

resource "vkcs_networking_secgroup" "backend_sg" {
  name  = "my-backend-sg"
}

resource "vkcs_networking_secgroup_rule" "backend_ingress_lb_frontend_rule" {
  direction         = "ingress"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "10.10.1.0/24"
  security_group_id = vkcs_networking_secgroup.backend_sg.id
}

resource "vkcs_networking_secgroup_rule" "backend_ssh_rule" {
  direction         = "ingress"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = vkcs_networking_secgroup.backend_sg.id
}

resource "vkcs_compute_instance" "frontend_vm" {
  name            = "my-frontend-vm"
  flavor_id       = local.flavor_id
  image_id        = local.image_id
  security_group_ids = [vkcs_networking_secgroup.frontend_sg.id]

  network {
    uuid = vkcs_networking_subnet.frontend_subnet.network_id
  }
}

resource "vkcs_networking_floatingip" "frontend_fip" {
  pool = data.vkcs_networking_network.external_network.name
}

resource "vkcs_compute_floatingip_associate" "frontend_ip_assoc" {
  floating_ip = vkcs_networking_floatingip.frontend_fip.address
  instance_id = vkcs_compute_instance.frontend_vm.id
}

resource "vkcs_compute_instance" "backend_vms" {
  count             = 3
  name              = "my-backend-vm-${count.index}"
  flavor_id         = local.flavor_id
  image_id          = local.image_id
  security_group_ids = [vkcs_networking_secgroup.backend_sg.id]

  network {
    uuid = vkcs_networking_subnet.backend_subnet.network_id
  }
}

resource "vkcs_compute_instance" "db_vm" {
  name              = "my-db-vm"
  flavor_id         = local.flavor_id
  image_id          = local.image_id
  security_group_ids = [vkcs_networking_secgroup.backend_sg.id]
  
  network {
    uuid = vkcs_networking_subnet.backend_subnet.network_id
  }
}

resource "vkcs_lb_loadbalancer" "loadbalancer" {
  name          = "my-loadbalancer"
  vip_subnet_id = vkcs_networking_subnet.backend_subnet.id
}

resource "vkcs_lb_listener" "lb_listener" {
  name            = "my-lb-listener"
  loadbalancer_id = vkcs_lb_loadbalancer.loadbalancer.id
  protocol        = "HTTP"
  protocol_port   = 80
}

resource "vkcs_lb_pool" "lb_pool" {
  name        = "my-lb-pool"
  listener_id = vkcs_lb_listener.lb_listener.id
  protocol    = "HTTP"
  lb_method   = "ROUND_ROBIN"
}

resource "vkcs_lb_member" "backend_lb_members" {
  count         = 3
  pool_id       = vkcs_lb_pool.lb_pool.id
  address       = vkcs_compute_instance.backend_vms[count.index].network[0].fixed_ip_v4
  protocol_port = 80
  subnet_id     = vkcs_networking_subnet.backend_subnet.id
}
