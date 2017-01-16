#!/bin/bash

set -e

source /home/ubuntu/devstack/functions
source /home/ubuntu/devstack/functions-common

echo "Updating flavors"

if [ "$branch" == "stable/newton" ] || [ "$branch" == "stable/liberty" ] || [ "$branch" == "stable/mitaka" ]; then
    nova flavor-delete 100
fi

nova flavor-create manila-service-flavor 100 1536 25 2

# Add DNS config to the private network
echo "Add DNS config to the private network"
subnet_id=`neutron net-show private | grep subnets | awk '{print $4}'`
neutron subnet-update $subnet_id --dns_nameservers list=true 8.8.8.8 8.8.4.4

# Add a route for the private network
router_ip=`neutron router-list | grep router1 | grep -oP '(?<=ip_address": ").*(?=")'`
sudo ip route replace 172.20.1.0/24 via $router_ip

MANILA_IMAGE_ID=$(glance image-list | grep "ws2012r2" | awk '{print $2}')
glance image-update $MANILA_IMAGE_ID --visibility public --protected False
