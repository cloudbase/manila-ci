#!/bin/bash

basedir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
# Loading OpenStack credentials
source /home/jenkins-slave/tools/keystonerc_admin

# Loading functions
source $basedir/utils.sh
source /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.manila.txt

# Building devstack as a threaded job
echo `date -u +%H:%M:%S` "Started to build devstack as a threaded job"
nohup $basedir/build_devstack.sh > /home/jenkins-slave/logs/devstack-build-log-$ZUUL_UUID.log 2>&1 &
pid_devstack=$!

# Building and joining HyperV nodes
echo `date -u +%H:%M:%S` "Started building & joining Hyper-V node: $hyperv_node"
nohup $basedir/build_hyperv.sh $hyperv_node > /home/jenkins-slave/logs/hyperv-build-log-$ZUUL_UUID.log 2>&1 &
pid_hv=$!

TIME_COUNT=0
PROC_COUNT=2

echo `date -u +%H:%M:%S` "Start waiting for parallel init jobs."

finished_devstack=0;
finished_hv=0;
while [[ $TIME_COUNT -lt 60 ]] && [[ $PROC_COUNT -gt 0 ]]; do
    if [[ $finished_devstack -eq 0 ]]; then
        ps -p $pid_devstack > /dev/null 2>&1 || finished_devstack=$?
        [[ $finished_devstack -ne 0 ]] && PROC_COUNT=$(( $PROC_COUNT - 1 )) && echo `date -u +%H:%M:%S` "Finished building devstack"
    fi
    if [[ $finished_hv -eq 0 ]]; then
        ps -p $pid_hv > /dev/null 2>&1 || finished_hv=$?
        [[ $finished_hv -ne 0 ]] && PROC_COUNT=$(( $PROC_COUNT - 1 )) && echo `date -u +%H:%M:%S` "Finished building $hyperv_node"
    fi
    if [[ $PROC_COUNT -gt 0 ]]; then
        sleep 1m
        TIME_COUNT=$(( $TIME_COUNT +1 ))
    fi
done

echo `date -u +%H:%M:%S` "Finished waiting for the parallel init jobs."
echo `date -u +%H:%M:%S` "We looped $TIME_COUNT times, and when finishing we have $PROC_COUNT threads still active"

OSTACK_PROJECT=`echo "$ZUUL_PROJECT" | cut -d/ -f2`

if [[ ! -z $IS_DEBUG_JOB ]] && [[ $IS_DEBUG_JOB == "yes" ]]
    then
        echo "All build logs can be found in http://64.119.130.115/debug/$OSTACK_PROJECT/$ZUUL_CHANGE/$ZUUL_PATCHSET/$JOB_TYPE/"
    else
        echo "All build logs can be found in http://64.119.130.115/$OSTACK_PROJECT/$ZUUL_CHANGE/$ZUUL_PATCHSET/$JOB_TYPE/"
fi

if [[ $PROC_COUNT -gt 0 ]]; then
    kill -9 $pid_devstack > /dev/null 2>&1
    kill -9 $pid_hv > /dev/null 2>&1
    echo "Not all build threads finished in time, initialization process failed."
    exit 1
fi

WIN_IMG_ID=$(run_ssh_cmd_with_retry ubuntu@$FIXED_IP $DEVSTACK_SSH_KEY "source /home/ubuntu/keystonerc && glance image-list | grep ws2012r2" | awk '{print $2}')
echo WIN_IMG_ID=$WIN_IMG_ID
if [[ -z $WIN_IMG_ID ]]; then
    echo "Could not get Windows image id."
    exit 1
fi

post_build_hyperv $WIN_USER $WIN_PASS $hyperv_node $WIN_IMG_ID
