# Openstack Minimal Deployment

This project includes automation scripts for a minimal deployment for OpenStack (Yoga release)

  => You can see the full installation in this demo: https://www.youtube.com/watch?v=bKgNCKeTBiQ&t=26s
  
## Introduction
OpenStack consists of several independent parts, named the OpenStack services, all those services should be installed in the order specified below:
- Identity service
- Image service
- Placement service
- Nova Compute service
- Neutron Networking service
- Horizon Dashboard service

The example architecture requires at least two nodes (hosts), the following minimum requirements should support a proof-of-concept environment with core services and several CirrOS instances:

    - Controller Node: 1 processor, 4 GB memory, and 5 GB storage

    - Compute Node: 1 processor, 2 GB memory, and 10 GB storage
(Note: for first-time installation and testing purposes, many users select to build each host as a virtual machine (VM). The primary benefit of VMs is using One physical server that can support multiple nodes, each with almost any number of network interfaces.)

I- At Controller Node we install:

- host environment (DNS, NTP, DB, etc.) setup
- keystone
- glance
- nova
- neutron

II- At Compute Node we install:

- host environment (DNS, NTP, DB, etc.) setup
- nova-compute
- neutron


## Installation

Controller Node
```sh
$ chmod 733 openstack-install.sh
$ ./openstack-install.sh
```

Compute Node
```sh
$ chmod 733 compute-install.sh
$ ./compute-install.sh compute_ip controller_ip
```
