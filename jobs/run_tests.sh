#!/bin/bash
basedir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.manila.txt
source $basedir/utils.sh
ensure_branch_supported || exit 0

export FAILURE=0
echo "Running tests"
ssh -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $DEVSTACK_SSH_KEY ubuntu@$FIXED_IP "source /home/ubuntu/keystonerc && /home/ubuntu/bin/run_tests.sh" 
