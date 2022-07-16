rabbitmqctl delete_user openstack

mysql -u root <<< "DROP DATABASE keystone;"

mysql -u root <<< "DROP DATABASE glance;"

mysql -u root <<< "DROP DATABASE placement;"

mysql -u root <<< "DROP DATABASE nova_api;"

mysql -u root <<< "DROP DATABASE nova_cell0;"

mysql -u root <<< "DROP DATABASE neutron;"
