IP=${1}

if [ "$IP" == "" ]; then
	echo "must enter an IP ending (eg. 247 para 192.168.10.247)"
	exit 1

cat >> /etc/default/grub << EOT
GRUB_CMDLINE_LINUX_DEFAULT="ipv6.disable=1"
GRUB_CMDLINE_LINUX="ipv6.disable=1"
EOT
update-grub


apt install -y chrony
sed -i 's/^pool/#pool/g' /etc/chrony/chrony.conf
echo "server controller iburst" >> /etc/chrony/chrony.conf
service chrony restart


apt install software-properties-common
add-apt-repository cloud-archive:yoga
apt update && apt -y dist-upgrade
apt install -y python3-openstackclient nova-compute

cat > /etc/nova/nova.conf << EOT
[DEFAULT]
# ...
transport_url = rabbit://openstack:RABBIT_PASS@controller
my_ip = MANAGEMENT_INTERFACE_IP_ADDRESS
[api]
# ...
auth_strategy = keystone

[keystone_authtoken]
# ...
www_authenticate_uri = http://controller:5000/
auth_url = http://controller:5000/
memcached_servers = controller:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = nova
password = NOVA_PASS
[vnc]
# ...
enabled = true
server_listen = 0.0.0.0
server_proxyclient_address = $my_ip
novncproxy_base_url = http://controller:6080/vnc_auto.html
[glance]
# ...
api_servers = http://controller:9292
[oslo_concurrency]
# ...
lock_path = /var/lib/nova/tmp
[placement]
# ...
region_name = RegionOne
project_domain_name = Default
project_name = service
auth_type = password
user_domain_name = Default
auth_url = http://controller:5000/v3
username = placement
password = PLACEMENT_PASS
[libvirt]
# ...
virt_type = qemu
[scheduler]
discover_hosts_in_cells_interval = 300
EOT

service nova-compute restart


