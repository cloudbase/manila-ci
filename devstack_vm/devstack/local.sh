#!/bin/bash

set -e

source /home/ubuntu/devstack/functions
source /home/ubuntu/devstack/functions-common

echo "Updating flavors"
nova flavor-delete 100
nova flavor-create manila-service-flavor 100 4096 25 2

# Add DNS config to the private network
echo "Add DNS config to the private network"
subnet_id=`neutron net-show private | grep subnets | awk '{print $4}'`
neutron subnet-update $subnet_id --dns_nameservers list=true 8.8.8.8 8.8.4.4

# Add a route for the private network
router_ip=`neutron router-list | grep router1 | grep -oP '(?<=ip_address": ").*(?=")'`
sudo ip route replace 172.20.1.0/24 via $router_ip

MANILA_IMAGE_ID=$(glance image-list | grep "ws2012r2" | awk '{print $2}')
glance image-update $MANILA_IMAGE_ID --visibility public --protected False

SHARE_TYPE_EXTRA_SPECS="snapshot_support=True create_share_from_snapshot_support=True"
manila type-key default set $SHARE_TYPE_EXTRA_SPECS
# Disable share groups APIs by default as of Ocata because feature has not been completed.
# Revert this change back in Pike.
# https://review.openstack.org/#/c/428840/
#manila share-group-type-key default set $SHARE_TYPE_EXTRA_SPECS

MANILA_SERVICE_SECGROUP="manila-service"
echo "Checking / creating $MANILA_SERVICE_SECGROUP security group"
openstack security group rule list $MANILA_SERVICE_SECGROUP || openstack security group create $MANILA_SERVICE_SECGROUP

set +e
echo "Adding security rules to the $MANILA_SERVICE_SECGROUP security group"
openstack security group rule create --protocol tcp --dst-port 1:65535 --remote-ip 0.0.0.0/0 $MANILA_SERVICE_SECGROUP
openstack security group rule create --protocol udp --dst-port 1:65535 --remote-ip 0.0.0.0/0 $MANILA_SERVICE_SECGROUP
openstack security group rule create --protocol icmp manila-service
set -e
