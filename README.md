This project includes automation scripts for a minimal deployment for openstack (Yoga)
on Ubuntu 20.04 LTS servers.
Following Openstack online guide:
https://docs.openstack.org/install-guide/openstack-services.html#minimal-deployment-for-yoga



OpenStack consists of several independent parts, named the OpenStack services, all those services should be installed in the order specified below:
-Identity service:
-Image service:
-Placement service:
-Compute service:
-Networking service:
-Dashboard service:

The example architecture requires at least two nodes (hosts) to launch a basic virtual machine or instance:

1-Controller Node:

host environment (DNS, NTP, DB, etc.) setup
keystone
glance
nova
neutron

2-Compute Node:

host environment (DNS, NTP, DB, etc.) setup
nova-compute
neutron
