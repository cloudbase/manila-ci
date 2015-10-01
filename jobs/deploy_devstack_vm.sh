#!/bin/bash

function emit_error(){
    echo "$1"
    exit 1
}

run_devstack (){
    # run devstack
    echo "Checking nova console-log for errors before installing devstack"
    nova console-log "$NAME"
    echo ""
    echo "Run stack.sh on devstack"
    run_ssh_cmd_with_retry ubuntu@$DEVSTACK_FLOATING_IP $DEVSTACK_SSH_KEY "source /home/ubuntu/keystonerc; /home/ubuntu/bin/run_devstack.sh" 5

    # run post_stack
    echo "Run post_stack scripts on devstack"
    run_ssh_cmd_with_retry ubuntu@$DEVSTACK_FLOATING_IP $DEVSTACK_SSH_KEY "source /home/ubuntu/keystonerc && /home/ubuntu/bin/post_stack.sh" 5
}

# Loading OpenStack credentials
source /home/jenkins-slave/tools/keystonerc_admin

# Loading functions
source /usr/local/src/manila-ci/jobs/utils.sh

set -e

export NAME="manila-devstack-$ZUUL_UUID-$JOB_TYPE"
echo NAME=$NAME > /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.manila.txt

echo JOB_TYPE=$JOB_TYPE >> /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.manila.txt

echo DEVSTACK_SSH_KEY=$DEVSTACK_SSH_KEY >> /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.manila.txt

NET_ID=$(nova net-list | grep 'private' | awk '{print $2}')
echo NET_ID=$NET_ID >> /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.manila.txt

echo DEVSTACK_FLOATING_IP=$DEVSTACK_FLOATING_IP
echo NAME=$NAME
echo NET_ID=$NET_ID

echo "Deploying devstack $NAME"
nova boot --availability-zone manila --flavor manila.stack --image devstack-62v3 --key-name default --security-groups devstack --nic net-id="$NET_ID" "$NAME" --poll

if [ $? -ne 0 ]
then
    echo "Failed to create devstack VM: $NAME"
    nova show "$NAME"
    exit 1
fi

echo "Fetching devstack VM fixed IP address"
export FIXED_IP=$(nova show "$NAME" | grep "private network" | awk '{print $5}')

COUNT=0
while [ -z "$FIXED_IP" ]
do
    if [ $COUNT -ge 10 ]
    then
        echo "Failed to get fixed IP"
        echo "nova show output:"
        nova show "$NAME"
        echo "nova console-log output:"
        nova console-log "$NAME"
        echo "neutron port-list output:"
        neutron port-list -D -c device_id -c fixed_ips | grep $VM_ID
        exit 1
    fi
    sleep 15
    export FIXED_IP=$(nova show "$NAME" | grep "private network" | awk '{print $5}')
    COUNT=$(($COUNT + 1))
done

echo FIXED_IP=$FIXED_IP >> /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.manila.txt

export DEVSTACK_FLOATING_IP=$(nova floating-ip-create public | awk '{print $2}' | sed '/^$/d' | tail -n 1 ) || echo "Failed to allocate floating IP"
if [ -z "$DEVSTACK_FLOATING_IP" ]
then
    exit 1
fi
echo DEVSTACK_FLOATING_IP=$DEVSTACK_FLOATING_IP >> /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.manila.txt

export VMID=`nova show $NAME | grep -w id | awk '{print $4}'`

echo VM_ID=$VMID >> /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.manila.txt
echo VM_ID=$VMID

exec_with_retry 15 5 "nova floating-ip-associate $NAME $DEVSTACK_FLOATING_IP"

nova show "$NAME"

echo "Wait for answer on port 22 on devstack"
wait_for_listening_port $DEVSTACK_FLOATING_IP 22 30 || { nova console-log "$NAME" ; exit 1; }
sleep 5

# Add 1 more interface after successful SSH
echo "Adding two more network interfaces to devstack VM"
nova interface-attach --net-id "$NET_ID" "$NAME" || emit_error "Failed to attach interface"

echo "Copy scripts to devstack VM"
scp -v -r -o "StrictHostKeyChecking no" -o "UserKnownHostsFile /dev/null" -i $DEVSTACK_SSH_KEY /usr/local/src/manila-ci/devstack_vm/* ubuntu@$DEVSTACK_FLOATING_IP:/home/ubuntu/

# Disable offloating on eth0
echo "Disabling offloading on eth0"
set +e
run_ssh_cmd_with_retry ubuntu@$DEVSTACK_FLOATING_IP $DEVSTACK_SSH_KEY "sudo ethtool --offload eth0 rx off tx off" 3
run_ssh_cmd_with_retry ubuntu@$DEVSTACK_FLOATING_IP $DEVSTACK_SSH_KEY "sudo ethtool -K eth0 gso off" 3
run_ssh_cmd_with_retry ubuntu@$DEVSTACK_FLOATING_IP $DEVSTACK_SSH_KEY "sudo ethtool -K eth0 gro off" 3
set -e

# Repository section
echo "setup apt-cacher-ng:"
run_ssh_cmd_with_retry ubuntu@$DEVSTACK_FLOATING_IP $DEVSTACK_SSH_KEY 'echo "Acquire::http { Proxy \"http://10.21.7.214:3142\" };" | sudo tee --append /etc/apt/apt.conf.d/90-apt-proxy.conf' 3
echo "clean any apt files:"
run_ssh_cmd_with_retry ubuntu@$DEVSTACK_FLOATING_IP $DEVSTACK_SSH_KEY "sudo rm -rfv /var/lib/apt/lists/*" 3
echo "apt-get update:"
run_ssh_cmd_with_retry ubuntu@$DEVSTACK_FLOATING_IP $DEVSTACK_SSH_KEY "sudo apt-get update -y" 3
sleep 15
echo "apt-get update - 2nd independent run:"
run_ssh_cmd_with_retry ubuntu@$DEVSTACK_FLOATING_IP $DEVSTACK_SSH_KEY "sudo apt-get update --assume-yes" 3
echo "apt-get upgrade:"
run_ssh_cmd_with_retry ubuntu@$DEVSTACK_FLOATING_IP $DEVSTACK_SSH_KEY 'sudo DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt-get -q -y -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold" upgrade' 3
echo "apt-get cleanup:"
run_ssh_cmd_with_retry ubuntu@$DEVSTACK_FLOATING_IP $DEVSTACK_SSH_KEY "sudo apt-get autoremove -y" 3

#set timezone to UTC
echo "Set local time to UTC on devstack"
run_ssh_cmd_with_retry ubuntu@$DEVSTACK_FLOATING_IP $DEVSTACK_SSH_KEY "sudo ln -fs /usr/share/zoneinfo/UTC /etc/localtime" 3

echo "Update git repos to latest"
run_ssh_cmd_with_retry ubuntu@$DEVSTACK_FLOATING_IP $DEVSTACK_SSH_KEY "/home/ubuntu/bin/update_devstack_repos.sh --branch $ZUUL_BRANCH --build-for $ZUUL_PROJECT" 1

echo "Ensure configs are copied over"
scp -v -r -o "StrictHostKeyChecking no" -o "UserKnownHostsFile /dev/null" -i $DEVSTACK_SSH_KEY /usr/local/src/manila-ci/devstack_vm/devstack/* ubuntu@$DEVSTACK_FLOATING_IP:/home/ubuntu/devstack

ZUUL_SITE=`echo "$ZUUL_URL" |sed 's/.\{2\}$//'`
echo ZUUL_SITE=$ZUUL_SITE >> /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.manila.txt

# Set ZUUL IP in hosts file
ZUUL_MANILA="10.21.7.43"
if ! grep -qi zuul /etc/hosts ; then
    run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY "echo '$ZUUL_MANILA zuul-manila.openstack.tld' | sudo tee -a /etc/hosts"
fi

# get locally the qcow2 windows image used by tempest (image is created with local.sh)
echo "Downloading the images for devstack"
run_ssh_cmd_with_retry ubuntu@$DEVSTACK_FLOATING_IP $DEVSTACK_SSH_KEY "mkdir -p /home/ubuntu/devstack/files/images/"
run_ssh_cmd_with_retry ubuntu@$DEVSTACK_FLOATING_IP $DEVSTACK_SSH_KEY "wget http://dl.openstack.tld/ws2012_r2_kvm_eval.qcow2.gz -O /home/ubuntu/devstack/files/images/ws2012_r2_kvm_eval.qcow2.gz"

# creating manila folder and cloning master
run_ssh_cmd_with_retry ubuntu@$DEVSTACK_FLOATING_IP $DEVSTACK_SSH_KEY "git clone git://git.openstack.org/openstack/manila.git /opt/stack/manila"

echo "Run gerrit-git-prep on devstack"
run_ssh_cmd_with_retry ubuntu@$DEVSTACK_FLOATING_IP $DEVSTACK_SSH_KEY  "/home/ubuntu/bin/gerrit-git-prep.sh --zuul-site $ZUUL_SITE --gerrit-site $ZUUL_SITE --zuul-ref $ZUUL_REF --zuul-change $ZUUL_CHANGE --zuul-project $ZUUL_PROJECT" 1
