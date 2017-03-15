#!/bin/bash
#

basedir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
# Loading all the needed functions
source $basedir/utils.sh

# Loading parameters
source /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.manila.txt

# run devstack
run_ssh_cmd_with_retry ubuntu@$FIXED_IP $DEVSTACK_SSH_KEY "source /home/ubuntu/keystonerc && /home/ubuntu/bin/run_devstack.sh" 5
if [ $? -ne 0 ]
    then
    echo "Failed to install devstack on cinder vm!"
    exit 1
fi

# run post_stack
run_ssh_cmd_with_retry ubuntu@$FIXED_IP $DEVSTACK_SSH_KEY "source /home/ubuntu/keystonerc && /home/ubuntu/bin/post_stack.sh" 5
if [ $? -ne 0 ]
then
    echo "Failed post_stack!"
    exit 1
fi
