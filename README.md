# Openstack Minimal Deployment

This project includes automation scripts for a minimal deployment for openstack (Yoga release)

## Introduction
OpenStack consists of several independent parts, named the OpenStack services, all those services should be installed in the order specified below:
- Identity service:
- Image service:
- Placement service:
- Compute service:
- Networking service:
- Dashboard service:

The example architecture requires at least two nodes (hosts) to launch a basic virtual machine or instance:

I- Controller Node:

- host environment (DNS, NTP, DB, etc.) setup
- keystone
- glance
- nova
- neutron

II- Compute Node:

- host environment (DNS, NTP, DB, etc.) setup
- nova-compute
- neutron


## Installation

Controller Node
```sh
chmod 766 openstack-install.sh
./openstack-install.sh
```

Compute Node
```sh
chmod 766 compute-install.sh
./compute-install.sh
```
