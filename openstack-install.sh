
#!/bin/bash

# Possible parameters
WORKING_FOLDER="$HOME/.openstack-install"
[ ! -d "$WORKING_FOLDER" ] && mkdir -p "$WORKING_FOLDER"
STEP=0
MANAGEMENT_NETWORK= #192.168.10.0/24
MANAGEMENT_IP= #192.168.10.100
PASSWD_FILE="$WORKING_FOLDER/passwd.txt"
QUIET=false
QUIET_APT=true
NETWORK_SELFSERVICE=true
PROVIDER_INTERFACE_NAME=eno3
DNS_SERVERS=
SIMPLE_PASSWDS=true

##################################################################
# START

function p_info() {
	echo "$@" >&1
}

# An array of undo commands
_UNDO=()
function undo() {
	_UNDO=( "$*" "${_UNDO[@]}" )
}

# A wrapper to create a file with some content, and include the undo line. It enables to automate the
# inclusion of the comments for the automated install
function genfile() {
	local fname="$1"
	shift
	backupfile "$fname"
	if [ "$1" == "-a" ]; then
		shift
		cat >> "$fname" <<<"${GENERATED_COMMENT}
$*"
	else
		cat > "$fname" <<<"${GENERATED_COMMENT}
$*"
	fi
}
# A wrapper for mysql, to be able to include mysql options
function _mysql() {
	mysql -u root <<< "$1"
}

if ((STEP<=0)); then
p_info "installing and configuring dependencies"
apt update
apt -y dist-upgrade
apt install software-properties-common
add-apt-repository -y cloud-archive:yoga > /dev/null 2> /dev/null
apt install chrony mariadb-server python3-pymysql python3-openstackclient rabbitmq-server memcached python3-memcache etcd
undo add-apt-repository -y -r cloud-archive:yoga

p_info "configuring ntp"
genfile /etc/chrony/chrony.conf -a "allow ${MANAGEMENT_NETWORK}"
service chrony restart

p_info "configuring mysql"
genfile /etc/mysql/mariadb.conf.d/99-openstack.cnf "\
[mysqld]
bind-address = ${MANAGEMENT_IP}
default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8"
service mysql restart

p_info "configuring rabbitmq"
rabbitmqctl add_user openstack "$RABBIT_PASS"
rabbitmqctl set_permissions openstack ".*" ".*" ".*"

sed -i 's/^[ \t]*\(-l .*\)$/# commented by OS Yoga automated install \n# \1/g' /etc/memcached.conf
genfile /etc/memcached.conf -a "-l $MANAGEMENT_IP"
service memcached restart

genfile /etc/default/etcd -a '\
ETCD_NAME="controller"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-01"
ETCD_INITIAL_CLUSTER="controller=http://${MANAGEMENT_IP}:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://${MANAGEMENT_IP}:2380"
ETCD_ADVERTISE_CLIENT_URLS="http://${MANAGEMENT_IP}:2379"
ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380"
ETCD_LISTEN_CLIENT_URLS="http://${MANAGEMENT_IP}:2379"'
systemctl enable etcd
systemctl start etcd
fi 

if ((STEP<=1)); then
	_mysql "\
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$KEYSTONE_DBPASS';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$KEYSTONE_DBPASS';"
	undo 'mysql -u root <<< "DROP DATABASE keystone;
DROP USER '"'"'keystone'"'"'@'"'"'localhost'"'"';
DROP USER '"'"'keystone'"'"'@'"'"'%'"'"';"'
fi

if ((STEP<=2)); then
apt install keystone apache2 libapache2-mod-wsgi

genfile /etc/keystone/keystone.conf "\
[DEFAULT]
log_dir = /var/log/keystone
[database]
connection = mysql+pymysql://keystone:${KEYSTONE_DBPASS}@controller/keystone
[extra_headers]
Distribution = Ubuntu
[token]
provider = fernet"
fi

if ((STEP<=3)); then
p_info "populating de identity service database"
# Populate the Identity service database
su -s /bin/sh -c "keystone-manage db_sync" keystone

p_info "initialize kernet key repository"
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

p_info "bootstrap the identity service"
keystone-manage bootstrap --bootstrap-password "${ADMIN_PASS}" --bootstrap-admin-url http://controller:5000/v3/ --bootstrap-internal-url http://controller:5000/v3/ --bootstrap-public-url http://controller:5000/v3/ --bootstrap-region-id RegionOne
fi

if ((STEP<=4)); then
p_info "configure apache"
genfile /etc/apache2/apache2.conf -a "ServerName controller"
service apache2 restart

p_info "creating the admin credentials file admin-openrc"
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD="${ADMIN_PASS}"
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2

genfile admin-openrc "\
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD="${ADMIN_PASS}"
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2"

p_info "creating the service project"
openstack project create --domain default --description "Service Project" service

if check INSTALL_DEMOPROJECT; then
	p_info "creating the demo credentials file demo-openrc"
	genfile demo-openrc "\
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=myproject
export OS_USERNAME=myuser
export OS_PASSWORD="${MYUSER_PASS}"
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2"

	p_info "creating the demo project, user and role"
	openstack domain create --description "An Example Domain" example
	openstack project create --domain default --description "Demo Project" myproject
	openstack user create --domain default --password "${MYUSER_PASS}"
	openstack role create myrole
	openstack role add --project myproject --user myuser myrole
fi # INSTALL_DEMOPROJECT

fi # INSTALL_KEYSTONE


## CONFIG GLANCE
if ((STEP<=5)); then
	source admin-openrc
	p_info "creating database for glance"
	_mysql "CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$GLANCE_DBPASS';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$GLANCE_DBPASS';"
	undo 'mysql -u root <<< "DROP DATABASE glance;
DROP USER '"'"'glance'"'"'@'"'"'localhost'"'"';
DROP USER '"'"'glance'"'"'@'"'"'%'"'"'"'

	p_info "creating glance user"
	openstack user create --domain default --password "$GLANCE_PASS" glance
	openstack role add --project service --user glance admin
	openstack service create --name glance --description "OpenStack Image" image

	p_info "creating endpoints"
	openstack endpoint create --region RegionOne image public http://controller:9292
	openstack endpoint create --region RegionOne image internal http://controller:9292
	openstack endpoint create --region RegionOne image admin http://controller:9292
	undo "# REMOVE GLANCE ENDPOINTS IN KEYSTONE"
fi

## INSTALL GLANCE
if ((STEP<=6)); then
	p_info "installing glance"
	apt install glance

	genfile /etc/glance/glance-api.conf "\
[database]
connection = mysql+pymysql://glance:$GLANCE_DBPASS@controller/glance

[image_format]
disk_formats = ami,ari,aki,vhd,vhdx,vmdk,raw,qcow2,vdi,iso,ploop.root-tar
[keystone_authtoken]
www_authenticate_uri = http://controller:5000
auth_url = http://controller:5000
memcached_servers = controller:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = glance
password = $GLANCE_PASS
[paste_deploy]
flavor = keystone
[oslo_limit]
auth_url = http://controller:5000
auth_type = password
user_domain_id = default
username = MY_SERVICE
system_scope = all
password = MY_PASSWORD
endpoint_id = ENDPOINT_ID
region_name = RegionOne
[glance_store]
stores = file,http
default_store = file
filesystem_store_datadir = /var/lib/glance/images/"

	# MY_SERVICE account has reader access to system-scope resources
	openstack role add --user MY_SERVICE --user-domain Default --system all reader

	su -s /bin/sh -c "glance-manage db_sync" glance
	service glance-registry restart
	service glance-api restart
fi

if ((STEP<=7)); then
	p_info "creating cirros image"
	wget -q http://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img -O /tmp/cirros-0.4.0-x86_64-disk.img
	openstack image create "cirros" --file /tmp/cirros-0.4.0-x86_64-disk.img --disk-format qcow2 --container-format bare --public
	undo openstack image delete "cirros"
fi

if ((STEP<=8)); then
	source admin-openrc
	p_info "creating database for nova"
	_mysql "CREATE DATABASE nova_api;
CREATE DATABASE nova;
CREATE DATABASE nova_cell0;
CREATE DATABASE placement;
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';
GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY '$PLACEMENT_DBPASS';
GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY '$PLACEMENT_DBPASS';"
	undo 'mysql -u root <<< "DROP DATABASE nova_api;
DROP DATABASE nova;
DROP DATABASE nova_cell0;
DROP DATABASE placement;
DROP USER '"'"'nova'"'"'@'"'"'localhost'"'"';
DROP USER '"'"'nova'"'"'@'"'"'%'"'"';
DROP USER '"'"'placement'"'"'@'"'"'localhost'"'"';
DROP USER '"'"'placement'"'"'@'"'"'%'"'"'"'

	p_info "creating nova user and service"
	openstack user create --domain default --password "$NOVA_PASS" nova
	openstack role add --project service --user nova admin
	openstack service create --name nova --description "OpenStack Compute" compute
	undo openstack user delete nova
	undo openstack service delete nova

	p_info "creating nova endpoints"
	openstack endpoint create --region RegionOne compute public http://controller:8774/v2.1
	openstack endpoint create --region RegionOne compute internal http://controller:8774/v2.1
	openstack endpoint create --region RegionOne compute admin http://controller:8774/v2.1
	undo "# REMOVE NOVA ENDPOINTS"

	p_info "creating placement user and service"
	openstack user create --domain default --password "$PLACEMENT_PASS" placement	
	openstack role add --project service --user placement admin
	openstack service create --name placement --description "Placement API" placement
	undo openstack user delete placement
	undo openstack service delete placement

	p_info "creating placement endpoints"
	openstack endpoint create --region RegionOne placement public http://controller:8778
	openstack endpoint create --region RegionOne placement internal http://controller:8778
	openstack endpoint create --region RegionOne placement admin http://controller:8778
	undo "# REMOVE PLACEMENT ENDPOINTS"
fi

if ((STEP<=9)); then
	source admin-openrc
	_aptinstall nova-api nova-conductor nova-consoleauth nova-novncproxy nova-scheduler nova-placement-api
	
	genfile /etc/nova/nova.conf "\
[DEFAULT]
lock_path = /var/lock/nova
state_path = /var/lib/nova
transport_url = rabbit://openstack:$RABBIT_PASS@controller
my_ip = $MANAGEMENT_IP
use_neutron = true
firewall_driver = nova.virt.firewall.NoopFirewallDriver
[api]
auth_strategy = keystone
[api_database]
connection = mysql+pymysql://nova:$NOVA_DBPASS@controller/nova_api
[cells]
enable = False
[database]
connection = mysql+pymysql://nova:$NOVA_DBPASS@controller/nova
[glance]
api_servers = http://controller:9292
[keystone_authtoken]
auth_url = http://controller:5000/v3
memcached_servers = controller:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = nova
password = $NOVA_PASS
[neutron]
url = http://controller:9696
auth_url = http://controller:5000
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = RegionOne
project_name = service
username = neutron
password = $NEUTRON_PASS
service_metadata_proxy = true
metadata_proxy_shared_secret = $METADATA_SECRET
[oslo_concurrency]
lock_path = /var/lib/nova/tmp
[placement]
os_region_name = openstack
region_name = RegionOne
project_domain_name = Default
project_name = service
auth_type = password
user_domain_name = Default
auth_url = http://controller:5000/v3
username = placement
password = $PLACEMENT_PASS
[placement_database]
connection = mysql+pymysql://placement:$PLACEMENT_DBPASS@controller/placement
[scheduler]
discover_hosts_in_cells_interval = 300
[vnc]
enabled = true
server_listen = \$my_ip
server_proxyclient_address = \$my_ip"

	p_info "populating nova-api and placement databases"
	su -s /bin/sh -c "nova-manage api_db sync" nova

	p_info "registering cells"
	su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
	su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova

	p_info "populating nova database"
	su -s /bin/sh -c "nova-manage db sync" nova

	p_info "restarting services"	
	service nova-api restart
	service nova-consoleauth restart
	service nova-scheduler restart
	service nova-conductor restart
	service nova-novncproxy restart
fi

if ((STEP<=10)); then
        source admin-openrc
        p_info "creating database for neutron"
        _mysql "CREATE DATABASE neutron;
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$NEUTRON_DBPASS';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$NEUTRON_DBPASS';"
        undo 'mysql -u root <<< "DROP DATABASE neutron;
DROP USER '"'"'neutron'"'"'@'"'"'localhost'"'"';
DROP USER '"'"'neutron'"'"'@'"'"'%'"'"'"'

        p_info "creating neutron user and service"
        openstack user create --domain default --password "$NEUTRON_PASS" neutron
        openstack role add --project service --user neutron admin
	openstack service create --name neutron --description "OpenStack Networking" network

        undo openstack user delete neutron
        undo openstack service delete neutron

        p_info "creating neutron endpoints"
	openstack endpoint create --region RegionOne network public http://controller:9696
	openstack endpoint create --region RegionOne network internal http://controller:9696
	openstack endpoint create --region RegionOne network admin http://controller:9696
fi

if ((STEP<=11)); then
	if check NETWORK_SELFSERVICE; then
		_aptinstall neutron-server neutron-plugin-ml2 neutron-linuxbridge-agent neutron-l3-agent neutron-dhcp-agent neutron-metadata-agent
		genfile /etc/neutron/neutron.conf "\
[DEFAULT]
core_plugin = ml2
core_plugin = ml2
service_plugins = router
allow_overlapping_ips = true
transport_url = rabbit://openstack:$RABBIT_PASS@controller
auth_strategy = keystone
notify_nova_on_port_status_changes = true
notify_nova_on_port_data_changes = true
[agent]
root_helper = "sudo /usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf"
[database]
connection = mysql+pymysql://neutron:$NEUTRON_DBPASS@controller/neutron
[keystone_authtoken]
www_authenticate_uri = http://controller:5000
auth_url = http://controller:5000
memcached_servers = controller:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = neutron
password = $NEUTRON_PASS
[nova]
auth_url = http://controller:5000
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = RegionOne
project_name = service
username = nova
password = $NOVA_PASS
[oslo_concurrency]
lock_path = /var/lock/neutron"

		genfile /etc/neutron/plugins/ml2/ml2_conf.ini "\
[ml2]
type_drivers = flat,vlan,vxlan
tenant_network_types = vxlan
mechanism_drivers = linuxbridge,l2population
extension_drivers = port_security
[ml2_type_flat]
flat_networks = provider
[ml2_type_vxlan]
vni_ranges = 1:1000
[securitygroup]
enable_ipset = true"

		genfile /etc/neutron/plugins/ml2/linuxbridge_agent.ini "\
[linux_bridge]
physical_interface_mappings = provider:$PROVIDER_INTERFACE_NAME
[securitygroup]
firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver
enable_security_group = true
[vxlan]
enable_vxlan = true
local_ip = $MANAGEMENT_IP
l2_population = true"

		genfile /etc/neutron/l3_agent.ini "\
[DEFAULT]
interface_driver = linuxbridge"

		genfile /etc/neutron/dhcp_agent.ini "\
[DEFAULT]
interface_driver = linuxbridge
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq
enable_isolated_metadata = true
dnsmasq_dns_servers = 8.8.8.8 $DNS_SERVERS"
	fi
	genfile /etc/neutron/metadata_agent.ini "\
[DEFAULT]
nova_metadata_host = controller
metadata_proxy_shared_secret = $METADATA_SECRET"
	p_info "populating database"
	su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron

	p_info "restarting services"
	service nova-api restart
	service neutron-server restart
	service neutron-linuxbridge-agent restart
	service neutron-dhcp-agent restart
	service neutron-metadata-agent restart
	service neutron-l3-agent restart
fi
echo $CINDER_PASS
if ((STEP<=12)); then
        _mysql "\
CREATE DATABASE cinder;
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY '$CINDER_DBPASS';
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY '$CINDER_DBPASS';"
        undo 'mysql -u root <<< "DROP DATABASE cinder;
DROP USER '"'"'cinder'"'"'@'"'"'localhost'"'"';
DROP USER '"'"'cinder'"'"'@'"'"'%'"'"';"'

	source admin-openrc
	p_info "creating cinder user"
	openstack user create --domain default --password "$CINDER_PASS" cinder
	openstack role add --project service --user cinder admin
	openstack service create --name cinderv2 --description "OpenStack Block Storage" volumev2
	openstack service create --name cinderv3 --description "OpenStack Block Storage" volumev3

	p_info "creating endpoints"
	openstack endpoint create --region RegionOne volumev2 public http://controller:8776/v2/%\(project_id\)s
	openstack endpoint create --region RegionOne volumev2 internal http://controller:8776/v2/%\(project_id\)s
	openstack endpoint create --region RegionOne volumev2 admin http://controller:8776/v2/%\(project_id\)s
	openstack endpoint create --region RegionOne volumev3 public http://controller:8776/v3/%\(project_id\)s
	openstack endpoint create --region RegionOne volumev3 internal http://controller:8776/v3/%\(project_id\)s
	openstack endpoint create --region RegionOne volumev3 admin http://controller:8776/v3/%\(project_id\)s
	undo "# REMOVE CINDER ENDPOINTS IN KEYSTONE"

	_aptinstall cinder-api cinder-scheduler
fi

if ((STEP<=13)); then
	genfile /etc/cinder/cinder.conf "\
[DEFAULT]
rootwrap_config = /etc/cinder/rootwrap.conf
api_paste_confg = /etc/cinder/api-paste.ini
iscsi_helper = tgtadm
volume_name_template = volume-%s
volume_group = cinder-volumes
verbose = True
auth_strategy = keystone
state_path = /var/lib/cinder
lock_path = /var/lock/cinder
volumes_dir = /var/lib/cinder/volumes
enabled_backends = lvm
transport_url = rabbit://openstack:$RABBIT_PASS@controller
my_ip=$MANAGEMENT_IP
[database]
connection = mysql+pymysql://cinder:$CINDER_DBPASS@controller/cinder
[keystone_authtoken]
www_authenticate_uri = http://controller:5000
auth_url = http://controller:5000
memcached_servers = controller:11211
auth_type = password
project_domain_id = default
user_domain_id = default
project_name = service
username = cinder
password = $CINDER_PASS
[oslo_concurrency]
lock_path = /var/lib/cinder/tmp"

	su -s /bin/sh -c "cinder-manage db sync" cinder

	crudini --set /etc/nova/nova.conf cinder os_region_name RegionOne	

	service nova-api restart
	service cinder-scheduler restart
	service apache2 restart
fi

if ((STEP<=14)); then
	if [ "$CINDER_DEV" != "" ]; then
		_aptinstall lvm2 thin-provisioning-tools
		pvcreate $CINDER_DEV
		undo pvremove $CINDER_DEV
		vgcreate cinder-volumes $CINDER_DEV
		undo vgremove cinder-volumes

		p_info "you are advised to remove any lvm volume from lvm.conf in the storage node
i.e. add the following filter to /lvm/lvm.conf, section devices; it makes lvscan to ignore any device but vdb
	filter = [ \"a/vdb/*\", \"r/.*/\" ]"

		_aptinstall cinder-volume

		crudini --set /etc/cinder/cinder.conf lvm volume_driver cinder.volume.drivers.lvm.LVMVolumeDriver
		crudini --set /etc/cinder/cinder.conf lvm volume_group cinder-volumes
		crudini --set /etc/cinder/cinder.conf lvm iscsi_protocol iscsi
		crudini --set /etc/cinder/cinder.conf lvm iscsi_helper tgtadm
		crudini --set /etc/cinder/cinder.conf DEFAULT glance_api_servers "http://controller:9292"

		service tgt restart
		service cinder-volume restart
	else
		p_info "skipping lvm configuration because no device was configured"
	fi
fi
