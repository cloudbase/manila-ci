#!/bin/bash

set -x

nova quota-class-update --instances 50 --cores 100 --ram $((51200*4)) --floating-ips 50 --security-groups 50 --security-group-rules 100 default
neutron quota-update --subnet 100 --network 100 default
# manila quota-class-update --shares 50 --share-networks 10 --gigabytes 2000 default
# ERROR: 'Namespace' object has no attribute 'class_name'
# Manila quota cannot be modified using API

#NAT
sudo /sbin/iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo /sbin/iptables -A FORWARD -i eth0 -o br-eth1 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo /sbin/iptables -A FORWARD -i br-eth1 -o eth0 -j ACCEPT

#copy policy.json to share
cp /opt/stack/nova/etc/nova/policy.json /openstack/policy.json