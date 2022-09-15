. admin-openrc
#Create the network:
openstack network create  --share --external \
  --provider-physical-network provider \
  --provider-network-type flat provider

#Create a subnet on the network:
openstack subnet create --network provider \
  --allocation-pool start=203.0.113.101,end=203.0.113.250 \
  --dns-nameserver 8.8.8.8 --gateway 203.0.113.1 \
  --subnet-range 203.0.113.0/24 provider
#Create m1.nano flavor
openstack flavor create --id 0 --vcpus 1 --ram 64 --disk 1 m1.nano

#ssh-keygen -q -N ""
#openstack keypair create --public-key ~/.ssh/id_rsa.pub mykey
#openstack keypair list

## create self service network
openstack network create selfservice
## create a subnet on network
openstack subnet create --network selfservice \
  --dns-nameserver 8.8.4.4 --gateway 172.16.1.1 \
  --subnet-range 172.16.1.0/24 selfservice
#create router
openstack router create router
#Add the self-service network subnet as an interface on the router:
openstack router add subnet router selfservice
#Set a gateway on the provider network on the router
openstack router set router --external-gateway provider

openstack security group rule create --proto icmp default
openstack security group rule create --proto tcp --dst-port 22 default

## add flavors
echo "adding flavors.."
        openstack flavor create --id 1 --ram 512 --disk 1 --vcpus 1 m1.tiny
        openstack flavor create --id 2 --ram 2048 --disk 20 --vcpus 1 m1.small
        openstack flavor create --id 3 --ram 4096 --disk 40 --vcpus 2 m1.medium
        openstack flavor create --id 4 --ram 8192 --disk 80 --vcpus 4 m1.large
        openstack flavor create --id 5 --ram 16384 --disk 160 --vcpus 8 m1.xlarge
 
        openstack flavor create --id c1 --ram 256 --disk 0 --vcpus 1 cirros256
        openstack flavor create --id d1 --ram 512 --disk 5 --vcpus 1 ds512M
        openstack flavor create --id d2 --ram 1024 --disk 10 --vcpus 1 ds1G
        openstack flavor create --id d3 --ram 2048 --disk 10 --vcpus 2 ds2G
        openstack flavor create --id d4 --ram 4096 --disk 20 --vcpus 4 ds4G

## download image xenial ubuntu
echo "download xenial ubuntu iamge.."
wget https://cloud-images.ubuntu.com/xenial/current/xenial-server-cloudimg-amd64-disk1.img
openstack --insecure image create --disk-format qcow2 --min-disk 8 --min-ram 512 --file xenial-server-cloudimg-amd64-disk1.img --public 16.04

#Launch the instance
#openstack server create --flavor m1.nano --image cirros \
#  --nic net-id=PROVIDER_NET_ID --security-group default \
#  --key-name mykey provider-instance
echo "finished!!"
