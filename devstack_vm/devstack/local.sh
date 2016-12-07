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

TEMPEST_CONFIG=/opt/stack/tempest/etc/tempest.conf

echo "Updating tempest settings"
iniset $TEMPEST_CONFIG identity username demo
iniset $TEMPEST_CONFIG identity password Passw0rd
iniset $TEMPEST_CONFIG identity tenant_name demo
iniset $TEMPEST_CONFIG identity alt_username alt_demo
iniset $TEMPEST_CONFIG identity alt_password Passw0rd
iniset $TEMPEST_CONFIG identity admin_username admin
iniset $TEMPEST_CONFIG identity admin_password Passw0rd
iniset $TEMPEST_CONFIG identity admin_tenant_name admin

iniset $TEMPEST_CONFIG share enable_protocols cifs
iniset $TEMPEST_CONFIG share enable_ip_rules_for_protocols ""
iniset $TEMPEST_CONFIG share enable_user_rules_for_protocols cifs
iniset $TEMPEST_CONFIG share enable_ro_access_level_for_protocols cifs
iniset $TEMPEST_CONFIG share storage_protocol CIFS
iniset $TEMPEST_CONFIG share image_with_share_tools ws2012r2
iniset $TEMPEST_CONFIG share image_username Admin
iniset $TEMPEST_CONFIG share client_vm_flavor_ref 100
iniset $TEMPEST_CONFIG share build_timeout 2400

public_id=`neutron net-list | grep public | awk '{print $2}'`
iniset $TEMPEST_CONFIG network public_network_id $public_id

# router_id=`neutron router-list | grep router | awk '{print $2}'
# iniset $TEMPEST_CONFIG network public_router_id $router_id

MANILA_IMAGE_ID=$(glance image-list | grep "ws2012r2" | awk '{print $2}')
glance image-update $MANILA_IMAGE_ID --visibility public --protected False
