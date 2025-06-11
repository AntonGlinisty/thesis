"""A Python Pulumi program"""

import pulumi
import pulumi_yandex as yc

zone = "ru-central1-a"
platform_id = "standard-v2"
vm_image_id = "fd85u0rct32prepgjlv0"
port = 8080

# vpc
my_vpc = yc.VpcNetwork("my-vpc", name="my-vpc")

# frontend subnet
my_frontend_subnet = yc.VpcSubnet(
    "my-frontend-subnet",
    name="my-frontend-subnet",
    zone=zone,
    network_id=my_vpc.id,
    v4_cidr_blocks=["10.10.1.0/24"],
)

# backend subnet
my_backend_subnet = yc.VpcSubnet(
    "my-backend-subnet",
    name="my-backend-subnet",
    zone=zone,
    network_id=my_vpc.id,
    v4_cidr_blocks=["10.10.2.0/24"],
)

# frontend vm
my_frontend_vm = yc.ComputeInstance(
    "my-frontend-vm",
    name="my-frontend-vm",
    zone=zone,

    resources=yc.ComputeInstanceResourcesArgs(
        cores=2,
        memory=2,
    ),

    boot_disk=yc.ComputeInstanceBootDiskArgs(
        initialize_params=yc.ComputeInstanceBootDiskInitializeParamsArgs(
            image_id=vm_image_id,
        ),
    ),

    network_interfaces=[
        yc.ComputeInstanceNetworkInterfaceArgs(
            subnet_id=my_frontend_subnet.id,
            nat=True,
        ),
    ]
)

# backend vms
backend_vms = []
for i in range(3):
    vm = yc.ComputeInstance(
        f"my-backend-vm-{i}",
        name=f"my-backend-vm-{i}",
        zone=zone,

        resources=yc.ComputeInstanceResourcesArgs(
            cores=2,
            memory=2,
        ),

        boot_disk=yc.ComputeInstanceBootDiskArgs(
            initialize_params=yc.ComputeInstanceBootDiskInitializeParamsArgs(
                image_id=vm_image_id,
            ),
        ),

        network_interfaces=[
            yc.ComputeInstanceNetworkInterfaceArgs(
                subnet_id=my_backend_subnet.id,
                nat=False,
            )
        ],
    )
    backend_vms.append(vm)

# db vm
my_frontend_vm = yc.ComputeInstance(
    "my-db-vm",
    name="my-db-vm",
    zone=zone,

    resources=yc.ComputeInstanceResourcesArgs(
        cores=2,
        memory=2,
    ),

    boot_disk=yc.ComputeInstanceBootDiskArgs(
        initialize_params=yc.ComputeInstanceBootDiskInitializeParamsArgs(
            image_id=vm_image_id,
        ),
    ),

    network_interfaces=[
        yc.ComputeInstanceNetworkInterfaceArgs(
            subnet_id=my_backend_subnet.id,
            nat=False,
        ),
    ]
)

# target group
my_target_group = yc.AlbTargetGroup(
    "my-target-group",
    name="my-target-group",
    targets=[
        yc.AlbTargetGroupTargetArgs(
            subnet_id=my_backend_subnet.id,
            ip_address=vm.network_interfaces[0].ip_address
        ) for vm in backend_vms
    ]
)

# backend group
my_backend_group = yc.AlbBackendGroup(
    "my-backend-group",
    name="my-backend-group",
    http_backends=[
        yc.AlbBackendGroupHttpBackendArgs(
            name="my-http-backend",
            port=port,
            target_group_ids=[my_target_group.id],

            healthcheck=yc.AlbBackendGroupHttpBackendHealthcheckArgs(
                timeout="1s",
                interval="1s",
                healthy_threshold=1,
                unhealthy_threshold=3,
                http_healthcheck=yc.AlbBackendGroupHttpBackendHealthcheckHttpHealthcheckArgs(
                    path="/ping"
                )
            )
        )
    ]
)

# http router
my_http_router = yc.AlbHttpRouter("my-http-router", name="my-http-router")

# virtual host
my_virtual_host = yc.AlbVirtualHost(
    "my-virtual-host",
    name="my-virtual-host",
    http_router_id=my_http_router.id,

    routes=[
        yc.AlbVirtualHostRouteArgs(
            name="my-route",
            http_route=yc.AlbVirtualHostRouteHttpRouteArgs(
                http_route_action=yc.AlbVirtualHostRouteHttpRouteHttpRouteActionArgs(
                    backend_group_id=my_backend_group.id
                )
            )
        )
    ]
)

# load balancer
my_load_balancer = yc.AlbLoadBalancer(
    "my-load-balancer",
    name="my-load-balancer",
    network_id=my_vpc.id,

    allocation_policy=yc.AlbLoadBalancerAllocationPolicyArgs(
        locations=[
            yc.AlbLoadBalancerAllocationPolicyLocationArgs(
                zone_id=zone,
                subnet_id=my_backend_subnet.id,
            )
        ]
    ),

    listeners=[
        yc.AlbLoadBalancerListenerArgs(
            name="my-listener",
            endpoints=[
                yc.AlbLoadBalancerListenerEndpointArgs(
                    addresses=[
                        yc.AlbLoadBalancerListenerEndpointAddressArgs(
                            external_ipv4_address={}
                        )
                    ],
                    ports=[port]
                )
            ],
            http=yc.AlbLoadBalancerListenerHttpArgs(
                handler=yc.AlbLoadBalancerListenerHttpHandlerArgs(
                    http_router_id=my_http_router.id
                )
            )
        )
    ]
)

