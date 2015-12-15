#!/bin/bash

# Loading OpenStack credentials
source /home/jenkins-slave/tools/keystonerc_admin

# Loading functions
source /usr/local/src/manila-ci/jobs/utils.sh


# Run devstack
echo "Run stack.sh on devstack"
run_ssh_cmd_with_retry ubuntu@$DEVSTACK_FLOATING_IP $DEVSTACK_SSH_KEY "source /home/ubuntu/keystonerc && /home/ubuntu/bin/run_devstack.sh" 6
if [ $? -ne 0 ]
    then
    echo "Failed to install devstack on cinder vm!"
    exit 1
fi
# Run post_stack
echo "Run post_stack scripts on devstack"
run_ssh_cmd_with_retry ubuntu@$DEVSTACK_FLOATING_IP $DEVSTACK_SSH_KEY "source /home/ubuntu/keystonerc && /home/ubuntu/bin/post_stack.sh" 6
if [ $? -ne 0 ]
then
    echo "Failed post_stack!"
    exit 1
fi

echo "Joining Hyper-V node $hyperv_node"

join_hyperv $WIN_USER $WIN_PASS $hyperv_node
