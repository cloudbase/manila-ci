#!/bin/bash

basedir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
echo "Collecting logs"

source $basedir/utils.sh

set -x

source /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.manila.txt

#!/bin/bash
jen_date=$(date +%d/%m/%Y-%H:%M)
set +e

ssh -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i /home/jenkins-slave/tools/admin-msft.pem ubuntu@$FIXED_IP "mkdir -p /openstack/logs/$hyperv_node"
ssh -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i /home/jenkins-slave/tools/admin-msft.pem ubuntu@$FIXED_IP "sudo chown -R nobody:nogroup /openstack/logs"
ssh -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i /home/jenkins-slave/tools/admin-msft.pem ubuntu@$FIXED_IP "sudo chmod -R 777 /openstack/logs"
python /home/jenkins-slave/tools/wsman.py -U https://$hyperv_node:5986/wsman -u $WIN_USER -p $WIN_PASS 'powershell -ExecutionPolicy RemoteSigned C:\OpenStack\manila-ci\HyperV\scripts\export-eventlog.ps1'

if [ -z '$ZUUL_CHANGE' ] || [ -z '$ZUUL_PATCHSET' ]; then
    echo 'Missing parameters!'
    echo "ZUUL_CHANGE=$ZUUL_CHANGE"
    echo "ZUUL_PATCHSET=$ZUUL_PATCHSET"
    exit 1
fi

if [ "$IS_DEBUG_JOB" != "yes" ];then
    LOG_ARCHIVE_DIR="/srv/logs/manila/$ZUUL_CHANGE/$ZUUL_PATCHSET/$JOB_TYPE"
else
    TIMESTAMP=$(date +%d-%m-%Y_%H-%M)
    LOG_ARCHIVE_DIR="/srv/logs/debug/manila/$ZUUL_CHANGE/$ZUUL_PATCHSET/$JOB_TYPE/$TIMESTAMP"
fi

function ssh_cmd_logs_sv {
    local CMD=$1
    ssh -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $LOGS_SSH_KEY logs@logs.openstack.tld $CMD
}

function log_unsupported_branch {
    echo "The Windows SMB Manila driver is supported only on OpenStack Liberty or later." > /tmp/results.txt
    echo ZUUL_BRANCH=$ZUUL_BRANCH >> /tmp/results.txt
    scp -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $LOGS_SSH_KEY /tmp/results.txt logs@logs.openstack.tld:$LOG_ARCHIVE_DIR/results.txt
    rm /tmp/results.txt
}

ensure_branch_supported || (log_unsupported_branch && exit 0)

ssh -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $DEVSTACK_SSH_KEY ubuntu@$FIXED_IP "/home/ubuntu/bin/collect_logs.sh $hyperv_node $WIN_USER $WIN_PASS $IS_DEBUG_JOB"

echo "Creating logs destination folder"
ssh_cmd_logs_sv "if [ ! -d $LOG_ARCHIVE_DIR ]; then mkdir -p $LOG_ARCHIVE_DIR; else rm -rf $LOG_ARCHIVE_DIR/*; fi"

echo "Downloading logs"
scp -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $DEVSTACK_SSH_KEY ubuntu@$FIXED_IP:/home/ubuntu/aggregate.tar.gz "aggregate-$NAME.tar.gz"

echo "GZIP:"
gzip -v9 $CONSOLE_LOG
gzip -v9 /home/jenkins-slave/logs/hyperv-build-log-$ZUUL_UUID.log
gzip -v9 /home/jenkins-slave/logs/devstack-build-log-$ZUUL_UUID.log

echo "Uploading logs"
scp -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $LOGS_SSH_KEY "aggregate-$NAME.tar.gz" logs@logs.openstack.tld:$LOG_ARCHIVE_DIR/aggregate-logs.tar.gz
scp -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $LOGS_SSH_KEY $CONSOLE_LOG.gz logs@logs.openstack.tld:$LOG_ARCHIVE_DIR/console.log.gz && rm -f $CONSOLE_LOG*
scp -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $LOGS_SSH_KEY /home/jenkins-slave/logs/devstack-build-log-$ZUUL_UUID.log.gz \
    logs@logs.openstack.tld:$LOG_ARCHIVE_DIR/devstack-build-log.log.gz
scp -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $LOGS_SSH_KEY /home/jenkins-slave/logs/hyperv-build-log-$ZUUL_UUID.log.gz \
    logs@logs.openstack.tld:$LOG_ARCHIVE_DIR/hyperv-build-log.log.gz

rm /home/jenkins-slave/logs/hyperv-build-log-$ZUUL_UUID.log.gz
rm /home/jenkins-slave/logs/devstack-build-log-$ZUUL_UUID.log.gz

echo "Extracting logs"
ssh_cmd_logs_sv "tar -xzf $LOG_ARCHIVE_DIR/aggregate-logs.tar.gz -C $LOG_ARCHIVE_DIR"

echo "Fixing permissions on all log files"
ssh_cmd_logs_sv "chmod a+rx -R $LOG_ARCHIVE_DIR"

if [ "$IS_DEBUG_JOB" != "yes" ] || [ -z '$IS_DEBUG_JOB' ]; then
	echo "Detaching and cleaning Hyper-V node"
	python /home/jenkins-slave/tools/wsman.py -U https://$hyperv_node:5986/wsman -u administrator -p H@rd24G3t "powershell -ExecutionPolicy RemoteSigned C:\OpenStack\manila-ci\HyperV\scripts\teardown.ps1"
fi

echo `date -u +%H:%M:%S`
set +x
