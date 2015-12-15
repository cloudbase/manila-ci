#!/bin/bash

rotate_log () {
    local file="$1"
    local limit=$2
    if [ -f $file ] ; then
        if [ -f ${file}.${limit} ] ; then
            rm ${file}.${limit}
        fi

        for (( CNT=$limit; CNT > 1; CNT-- )) ; do
            if [ -f ${file}.$(($CNT-1)) ]; then
                mv ${file}.$(($CNT-1)) ${file}.${CNT} || echo "Failed to run: mv ${file}.$(($CNT-1)) ${file}.${CNT}"
            fi
        done

        # Renames current log to .1
        mv $file ${file}.1
        touch $file
    fi
}

function cherry_pick {
    commit=$1
    set +e
    git cherry-pick $commit

    if [ $? -ne 0 ]
    then
        echo "Ignoring failed git cherry-pick $commit"
        git checkout --force
    fi

    set -e
}

sudo sh -c "echo '* * * * * root echo 3 > /proc/sys/vm/drop_caches' >> /etc/crontab"

set -x
set -e
sudo ifconfig eth1 promisc up

HOSTNAME=$(hostname)

sudo sed -i '2i127.0.0.1  '$HOSTNAME'' /etc/hosts

# Add pip cache for devstack
mkdir -p $HOME/.pip
echo "[global]" > $HOME/.pip/pip.conf
echo "trusted-host = dl.openstack.tld" >> $HOME/.pip/pip.conf
echo "index-url = http://dl.openstack.tld:8080/cloudbase/CI/+simple/" >> $HOME/.pip/pip.conf
echo "[install]" >> $HOME/.pip/pip.conf
echo "trusted-host = dl.openstack.tld" >> $HOME/.pip/pip.conf

sudo mkdir -p /root/.pip
sudo cp $HOME/.pip/pip.conf /root/.pip/
sudo chown -R root:root /root/.pip

# Update pip
sudo easy_install -U pip

# Update six to latest version
sudo pip install -U six
sudo pip install -U kombu
sudo pip install -U pbr
#sudo pip install -U networking-hyperv
sudo pip install -U /opt/stack/networking-hyperv

# Install PyWinrm for manila
sudo pip install -U git+https://github.com/petrutlucian94/pywinrm

# Running an extra apt-get update
sudo apt-get update --assume-yes

set -e

DEVSTACK_LOGS="/opt/stack/logs/screen"
LOCALRC="/home/ubuntu/devstack/localrc"
LOCALCONF="/home/ubuntu/devstack/local.conf"
PBR_LOC="/opt/stack/pbr"
# Clean devstack logs
sudo rm -f "$DEVSTACK_LOGS/*"
sudo rm -rf "$PBR_LOC"

MYIP=$(/sbin/ifconfig eth0 2>/dev/null| grep "inet addr:" 2>/dev/null| sed 's/.*inet addr://g;s/ .*//g' 2>/dev/null)

if [ -e "$LOCALCONF" ]
then
        [ -z "$MYIP" ] && exit 1
        sed -i 's/^HOST_IP=.*/HOST_IP='$MYIP'/g' "$LOCALCONF"
fi

if [ -e "$LOCALRC" ]
then
        [ -z "$MYIP" ] && exit 1
        sed -i 's/^HOST_IP=.*/HOST_IP='$MYIP'/g' "$LOCALRC"
fi

cd /home/ubuntu/devstack
git pull

cd /opt/stack/manila
git config --global user.email "microsoft_manila_ci@microsoft.com"
git config --global user.name "Microsoft Manila CI"


cd /home/ubuntu/devstack

./unstack.sh

# Workaround for the Nova API versions mismatch issue.
# git revert 8349aff5abd26c63470b96e99ade0e8292a87e7a --no-edit

# stack.sh output log
STACK_LOG="/opt/stack/logs/stack.sh.txt"
# keep this many rotated stack.sh logs
STACK_ROTATE_LIMIT=6
rotate_log $STACK_LOG $STACK_ROTATE_LIMIT

sed -i "s#PIP_GET_PIP_URL=https://bootstrap.pypa.io/get-pip.py#PIP_GET_PIP_URL=http://dl.openstack.tld/get-pip.py#g" /home/ubuntu/devstack/tools/install_pip.sh

# temporary fix for https://bugs.launchpad.net/devstack/+bug/1525187
sudo pip install tox==2.2.1

set -o pipefail
./stack.sh 2>&1 | tee $STACK_LOG

source /home/ubuntu/keystonerc

MANILA_SERVICE_SECGROUP="manila-service"
echo "Checking / creating $MANILA_SERVICE_SECGROUP security group"

nova secgroup-list-rules $MANILA_SERVICE_SECGROUP || nova secgroup-create $MANILA_SERVICE_SECGROUP $MANILA_SERVICE_SECGROUP

echo "Adding security rules to the $MANILA_SERVICE_SECGROUP security group"
nova secgroup-add-rule $MANILA_SERVICE_SECGROUP tcp 1 65535 0.0.0.0/0
nova secgroup-add-rule $MANILA_SERVICE_SECGROUP udp 1 65535 0.0.0.0/0
set +e
nova secgroup-add-rule $MANILA_SERVICE_SECGROUP icmp -1 -1 0.0.0.0/0
set -e
