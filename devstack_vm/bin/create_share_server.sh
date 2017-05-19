#!/bin/bash

# TODO(lpetrut): remove hardcoded stuff
MANILA_SERVICE_SECGROUP="manila-service"
NET_ID=$(neutron net-list | grep private | awk '{print $2}')
neutron net-update --shared=True private


openstack --os-username manila \
	--os-tenant-name service \
	--os-password Passw0rd \
	--os-auth-url http://127.0.0.1/identity \
	security group delete $MANILA_SERVICE_SECGROUP

openstack --os-username manila \
        --os-tenant-name service \
        --os-password Passw0rd \
        --os-auth-url http://127.0.0.1/identity \
        security group create $MANILA_SERVICE_SECGROUP

echo "Adding security rules to the $MANILA_SERVICE_SECGROUP security group"

openstack --os-username manila \
        --os-tenant-name service \
        --os-password Passw0rd \
        --os-auth-url http://127.0.0.1/identity \
	security group rule create --protocol tcp --dst-port 1:65535 \
	--remote-ip 0.0.0.0/0 $MANILA_SERVICE_SECGROUP

openstack --os-username manila \
        --os-tenant-name service \
        --os-password Passw0rd \
        --os-auth-url http://127.0.0.1/identity \
	security group rule create --protocol udp --dst-port 1:65535 \
	--remote-ip 0.0.0.0/0 $MANILA_SERVICE_SECGROUP

VM_OK=1
RETRIES=5
while [ $VM_OK -ne 0 ] && [ $RETRIES -ne 0 ]; do
    nova --os-username manila --os-tenant-name service --os-password Passw0rd \
        boot ws2012r2 --image=ws2012r2 \
                      --flavor=100 \
                      --nic net-id=$NET_ID \
                      --user-data=/home/ubuntu/ssl/winrm_client_cert.pem \
                      --security-groups $MANILA_SERVICE_SECGROUP
    VM_OK=$?
    RETRIES=$(( $RETRIES -1 ))
done

