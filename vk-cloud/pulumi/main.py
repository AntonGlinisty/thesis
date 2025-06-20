import pulumi_openstack as openstack

flavor_id = "25ae869c-be29-4840-8e12-99e046d2dbd4"
image_id = "c1703b98-c903-436c-9de3-370af53a306f"

network = openstack.networking.Network("my-vpc", name="my-vpc")

frontend_subnet = openstack.networking.Subnet(
    "my-frontend-subnet",
    name="my-frontend-subnet",
    network_id=network.id,
    cidr="10.10.1.0/24",
    enable_dhcp=True,
)

backend_subnet = openstack.networking.Subnet(
    "my-backend-subnet",
    name="my-backend-subnet",
    network_id=network.id,
    cidr="10.10.2.0/24",
)

external_network = openstack.networking.get_network(name="internet")

router = openstack.networking.Router(
    "my-router",
    name="main-router",
    external_network_id=external_network.id,
)

frontend_router_if = openstack.networking.RouterInterface(
    "frontend-router-if",
    router_id=router.id,
    subnet_id=frontend_subnet.id,
)

backend_router_if = openstack.networking.RouterInterface(
    "backend-router-if",
    router_id=router.id,
    subnet_id=backend_subnet.id,
)

frontend_sg = openstack.networking.SecGroup(
    "my-frontend-sg",
    name="my-frontend-sg",
)

frontend_http_rule = openstack.networking.SecGroupRule(
    "frontend-ingress-http",
    direction="ingress",
    ethertype="IPv4",
    protocol="tcp",
    port_range_min=80,
    port_range_max=80,
    remote_ip_prefix="0.0.0.0/0",
    security_group_id=frontend_sg.id,
)

frontend_https_rule = openstack.networking.SecGroupRule(
    "frontend-ingress-https",
    direction="ingress",
    ethertype="IPv4",
    protocol="tcp",
    port_range_min=443,
    port_range_max=443,
    remote_ip_prefix="0.0.0.0/0",
    security_group_id=frontend_sg.id,
)

frontend_ssh_rule = openstack.networking.SecGroupRule(
    "frontend-ingress-ssh",
    direction="ingress",
    ethertype="IPv4",
    protocol="tcp",
    port_range_min=22,
    port_range_max=22,
    remote_ip_prefix="0.0.0.0/0",
    security_group_id=frontend_sg.id,
)

backend_sg = openstack.networking.SecGroup(
    "my-backend-sg",
    name="my-backend-sg",
)

backend_ingress_lb_frontend_rule = openstack.networking.SecGroupRule(
    "backend-ingress-lb-frontend",
    direction="ingress",
    ethertype="IPv4",
    protocol="tcp",
    port_range_min=80,
    port_range_max=80,
    remote_ip_prefix="10.10.1.0/24",
    security_group_id=backend_sg.id,
)

backend_ssh_rule = openstack.networking.SecGroupRule(
    "backend-ingress-ssh",
    direction="ingress",
    ethertype="IPv4",
    protocol="tcp",
    port_range_min=22,
    port_range_max=22,
    remote_ip_prefix="0.0.0.0/0",
    security_group_id=backend_sg.id,
)

frontend_vm = openstack.compute.Instance(
    "my-frontend-vm",
    name="my-frontend-vm",
    flavor_id=flavor_id,
    image_id=image_id,
    security_groups=[frontend_sg.name],

    networks=[{
        "uuid": frontend_subnet.network_id,
    }],
)

frontend_fip = openstack.networking.FloatingIp(
    "frontend-fip",
    pool=external_network.name,
)

frontend_ip_assoc = openstack.compute.FloatingIpAssociate(
    "frontend-ip-assoc",
    floating_ip=frontend_fip.address,
    instance_id=frontend_vm.id,
)

backend_vms = []
for i in range(3):
    vm = openstack.compute.Instance(
        f"my-backend-vm-{i}",
        name=f"my-backend-vm-{i}",
        flavor_id=flavor_id,
        image_id=image_id,
        security_groups=[backend_sg.name],

        networks=[{
            "uuid": backend_subnet.network_id,
        }],
    )
    backend_vms.append(vm)

db_vm = openstack.compute.Instance(
    "my-db-vm",
    name="my-db-vm",
    flavor_id=flavor_id,
    image_id=image_id,
    security_groups=[backend_sg.name],

    networks=[{
        "uuid": backend_subnet.network_id,
    }],
)

loadbalancer = openstack.loadbalancer.LoadBalancer(
    "my-loadbalancer",
    name="my-loadbalancer",
    vip_subnet_id=backend_subnet.id,
)

lb_listener = openstack.loadbalancer.Listener(
    "my-lb-listener",
    name="my-lb-listener",
    loadbalancer_id=loadbalancer.id,
    protocol="HTTP",
    protocol_port=80,
)

lb_pool = openstack.loadbalancer.Pool(
    "my-lb-pool",
    name="my-lb-pool",
    listener_id=lb_listener.id,
    protocol="HTTP",
    lb_method="ROUND_ROBIN",
)

for i, backend_vm in enumerate(backend_vms):
    backend_lb_member = openstack.loadbalancer.Member(
        f"my-backend-lb-member-{i}",
        pool_id=lb_pool.id,
        address=backend_vm.access_ip_v4,
        protocol_port=80,
        subnet_id=backend_subnet.id,
    )
