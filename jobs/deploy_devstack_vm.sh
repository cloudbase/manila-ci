#!/bin/bash

function emit_error(){
    echo "$1"
    exit 1
}

basedir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
# Loading OpenStack credentials
source /home/jenkins-slave/tools/keystonerc_admin

# Loading functions
source $basedir/utils.sh

set -e

NAME="mnl-dvs-$ZUUL_CHANGE-$ZUUL_PATCHSET"

case "$JOB_TYPE" in
         handled_share_servers)
            NAME="$NAME-hs"
            ;;
        user_share_servers)
            NAME="$NAME-us"
            ;;
esac

if [[ ! -z $IS_DEBUG_JOB ]] && [[ $IS_DEBUG_JOB = "yes" ]]; then
        NAME="$NAME-dbg"
fi
export NAME=$NAME

echo NAME=$NAME > /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.manila.txt

echo JOB_TYPE=$JOB_TYPE >> /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.manila.txt

echo DEVSTACK_SSH_KEY=$DEVSTACK_SSH_KEY >> /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.manila.txt

NET_ID=$(nova net-list | grep 'private' | awk '{print $2}')
echo NET_ID=$NET_ID >> /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.manila.txt

echo NAME=$NAME
echo NET_ID=$NET_ID

if [[ $(nova list | grep $NAME) ]]
then
    echo "WARNING: Devstack VM $NAME already exists."
    set +e
    nova show "$NAME"
    set -e
fi

devstack_image="devstack-82v1"
echo "Image used is: $devstack_image"

echo "Deploying devstack $NAME"
date

MANILA_FLAVOR_ID="cfc20ce6-72ca-4d4b-8d36-aadf0d5fc30b"

#19July/nherciu: temporarily setting availability zone to hyper-v until we have more manila compute nodes available
export VM_ID=$(nova boot --config-drive true \
                         --availability-zone nova \
                         --flavor devstack.xxl\
                         --image $devstack_image \
                         --key-name default \
                         --security-groups devstack \
                         --nic net-id="$NET_ID" \
                         --nic net-id="$NET_ID" "$NAME" --poll | \
               grep -w id | awk '{print $4}')

if [[ -z $VM_ID ]]
then
    echo "Failed to create devstack VM: $NAME"
    nova show "$NAME"
    exit 1
fi

nova show $VM_ID

# We may remove the "VMID" export after we make sure it's not used in the Jenkins job scripts.
export VMID=$VM_ID
echo VM_ID=$VM_ID >> /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.manila.txt
echo VM_ID=$VM_ID

echo "Fetching devstack VM fixed IP address"
export FIXED_IP=$(nova show "$VM_ID" | grep "private network" | awk '{print $5}' | cut -d"," -f1)

COUNT=0
while [ -z "$FIXED_IP" ]
do
    if [ $COUNT -ge 10 ]
    then
        echo "Failed to get fixed IP"
        echo "nova show output:"
        nova show $VM_ID
        echo "nova console-log output:"
        nova console-log $VM_ID
        echo "neutron port-list output:"
        neutron port-list -D -c device_id -c fixed_ips | grep $VM_ID
        exit 1
    fi
    sleep 15
    export FIXED_IP=$(nova show "$VM_ID" | grep "private network" | awk '{print $5}' | cut -d"," -f1)
    COUNT=$(($COUNT + 1))
done

echo FIXED_IP=$FIXED_IP >> /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.manila.txt

nova show "$VM_ID"

echo "Wait for answer on port 22 on devstack"
wait_for_listening_port $FIXED_IP 22 30 || { nova console-log "$VM_ID" ; exit 1; }
sleep 5

echo "Copy scripts to devstack VM"
scp -v -r -o "StrictHostKeyChecking no" -o "UserKnownHostsFile /dev/null" -i $DEVSTACK_SSH_KEY $basedir/../devstack_vm/* ubuntu@$FIXED_IP:/home/ubuntu/

#disable n-crt on master branch
if [ "$ZUUL_BRANCH" == "master" ]; then
    run_ssh_cmd_with_retry ubuntu@$FIXED_IP $DEVSTACK_SSH_KEY "sed -i 's/^enable_service n-crt/disable_service n-crt/' /home/ubuntu/devstack/local.conf" 1
fi

VLAN_RANGE=`exec_with_retry2 5 5 nonverbose $basedir/../vlan_allocation.py -a $VM_ID`
if [ ! -z "$VLAN_RANGE" ]; then
    run_ssh_cmd_with_retry ubuntu@$FIXED_IP $DEVSTACK_SSH_KEY "sed -i 's/TENANT_VLAN_RANGE.*/TENANT_VLAN_RANGE='$VLAN_RANGE'/g' /home/ubuntu/devstack/local.conf" 3
else
    echo "Could not retrieve a VLAN Range for VM $VM_ID"
fi

# Disable offloating on eth0
echo "Disabling offloading on eth0"
set +e
run_ssh_cmd_with_retry ubuntu@$FIXED_IP $DEVSTACK_SSH_KEY "sudo ip -f inet r replace default via 10.250.0.1 dev eth0" 3
run_ssh_cmd_with_retry ubuntu@$FIXED_IP $DEVSTACK_SSH_KEY "sudo ethtool --offload eth0 rx off tx off" 3
run_ssh_cmd_with_retry ubuntu@$FIXED_IP $DEVSTACK_SSH_KEY "sudo ethtool -K eth0 gso off" 3
run_ssh_cmd_with_retry ubuntu@$FIXED_IP $DEVSTACK_SSH_KEY "sudo ethtool -K eth0 gro off" 3
set -e

run_ssh_cmd_with_retry ubuntu@$FIXED_IP $DEVSTACK_SSH_KEY "sed -i 's/export OS_AUTH_URL.*/export OS_AUTH_URL=http:\/\/127.0.0.1\/identity/g' /home/ubuntu/keystonerc" 3

# Repository section
echo "setup apt-cacher-ng:"
run_ssh_cmd_with_retry ubuntu@$FIXED_IP $DEVSTACK_SSH_KEY 'echo "Acquire::http { Proxy \"http://10.20.1.36:8000\" };" | sudo tee --append /etc/apt/apt.conf.d/90-apt-proxy.conf' 3
echo "clean any apt files:"
run_ssh_cmd_with_retry ubuntu@$FIXED_IP $DEVSTACK_SSH_KEY "sudo rm -rfv /var/lib/apt/lists/*" 3
echo "apt-get update:"
run_ssh_cmd_with_retry ubuntu@$FIXED_IP $DEVSTACK_SSH_KEY "sudo apt-get update -y" 3
sleep 15
echo "apt-get update - 2nd independent run:"
run_ssh_cmd_with_retry ubuntu@$FIXED_IP $DEVSTACK_SSH_KEY "sudo apt-get update --assume-yes" 3
echo "apt-get upgrade:"
run_ssh_cmd_with_retry ubuntu@$FIXED_IP $DEVSTACK_SSH_KEY 'sudo DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt-get -q -y -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold" upgrade' 3
echo "apt-get cleanup:"
run_ssh_cmd_with_retry ubuntu@$FIXED_IP $DEVSTACK_SSH_KEY "sudo apt-get autoremove -y" 3

#set timezone to UTC
echo "Set local time to UTC on devstack"
run_ssh_cmd_with_retry ubuntu@$FIXED_IP $DEVSTACK_SSH_KEY "sudo ln -fs /usr/share/zoneinfo/UTC /etc/localtime" 3

echo "Update git repos to latest"
run_ssh_cmd_with_retry ubuntu@$FIXED_IP $DEVSTACK_SSH_KEY "/home/ubuntu/bin/update_devstack_repos.sh --branch $ZUUL_BRANCH --build-for $ZUUL_PROJECT" 1

# Preparing share for HyperV logs
run_ssh_cmd_with_retry ubuntu@$FIXED_IP $DEVSTACK_SSH_KEY 'mkdir -p /openstack/logs; chmod 777 /openstack/logs; sudo chown nobody:nogroup /openstack/logs'

ZUUL_SITE=`echo "$ZUUL_URL" |sed 's/.\{2\}$//'`
echo ZUUL_SITE=$ZUUL_SITE >> /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.manila.txt

# creating manila folder and cloning master
# this step is not needed since it`s done in update_devstack_repos.sh
#run_ssh_cmd_with_retry ubuntu@$FIXED_IP $DEVSTACK_SSH_KEY "git clone git://git.openstack.org/openstack/manila.git /opt/stack/manila"

echo "Run gerrit-git-prep on devstack"
run_ssh_cmd_with_retry ubuntu@$FIXED_IP $DEVSTACK_SSH_KEY  "/home/ubuntu/bin/gerrit-git-prep.sh --zuul-site $ZUUL_SITE --gerrit-site $ZUUL_SITE --zuul-ref $ZUUL_REF --zuul-change $ZUUL_CHANGE --zuul-project $ZUUL_PROJECT" 1
