#!/bin/bash

source $KEYSTONERC
basedir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

# Loading OpenStack credentials
source /home/jenkins-slave/tools/keystonerc_admin
source /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.manila.txt

# Loading functions
source $basedir/utils.sh
ensure_branch_supported || exit 0

set +e

if [ "$IS_DEBUG_JOB" != "yes" ]
  then
    jen_date=$(date +%d/%m/%Y-%H:%M:%S)
    echo "Detaching the hyper-v node"
    teardown_hyperv $WIN_USER $WIN_PASS $hyperv_node
    echo "$jen_date;$ZUUL_PROJECT;$ZUUL_BRANCH;$ZUUL_CHANGE;$ZUUL_PATCHSET;$hyperv_node;FREE" >> /home/jenkins-slave/hypervnodes.log
    echo "Removing devstack VM"
    exec_with_retry 5 5 $basedir/../vlan_allocation.py -r $VM_ID
    if [ $? -ne 0 ]; then
        echo "Could not remove VLAN range for VM $VM_ID" 
    fi
    nova delete $VM_ID
  else
    echo "Not deleting the VMs, cleanup will be done by hand after debug"
fi

set -e
