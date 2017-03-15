#!/bin/bash
#
hyperv_node=$1
basedir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
# Loading all the needed functions
source $basedir/utils.sh

# Loading parameters
source /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.manila.txt

export LOG_DIR='C:\Openstack\logs\'

# building HyperV node
echo $hyperv_node
join_hyperv $WIN_USER $WIN_PASS $hyperv_node 
