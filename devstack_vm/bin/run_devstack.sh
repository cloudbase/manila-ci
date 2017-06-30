#!/bin/bash

rotate_log () {
    local file="$1"
    local limit="$2"
    #We set $new_file as $file without extension 
    local new_file="${file//.txt/}"
    if [ -f $file ] ; then
        if [[ -f ${new_file}.${limit}.txt ]] ; then
            rm ${new_file}.${limit}.txt
        fi

        for (( CNT=$limit; CNT > 1; CNT-- )) ; do
            if [[ -f ${new_file}.$(($CNT-1)).txt ]]; then
                echo ${new_file}.$(($CNT-1)).txt
                mv ${new_file}.$(($CNT-1)).txt ${new_file}.${CNT}.txt || echo "Failed to run: mv ${new_file}.$(($CNT-1)).txt ${new_file}.${CNT}.txt"
            fi
        done

        # Renames current log to .1.txt
        mv $file ${new_file}.1.txt
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

HOSTNAME=$(hostname)

sudo sed -i '2i127.0.0.1  '$HOSTNAME'' /etc/hosts

# Add pip cache for devstack
mkdir -p $HOME/.pip
echo "[global]" > $HOME/.pip/pip.conf
echo "trusted-host = 10.20.1.8" >> $HOME/.pip/pip.conf
echo "index-url = http://10.20.1.8:8080/cloudbase/CI/+simple/" >> $HOME/.pip/pip.conf
echo "[install]" >> $HOME/.pip/pip.conf
echo "trusted-host = 10.20.1.8" >> $HOME/.pip/pip.conf

sudo mkdir -p /root/.pip
sudo cp $HOME/.pip/pip.conf /root/.pip/
sudo chown -R root:root /root/.pip

# Update packages to latest version
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

# force older python-novaclient because version 8.0.0 does not work with manila
# http://logs.openstack.org/01/443101/11/check/gate-manila-tempest-dsvm-mysql-generic-ubuntu-xenial-nv/fe0ca1b/logs/screen-m-shr.txt.gz
sed -i "s/python-novaclient===8.0.0/python-novaclient===7.1.0/g" /opt/stack/requirements/upper-constraints.txt

cd /home/ubuntu/devstack
git pull

git config --global user.email "microsoft_manila_ci@microsoft.com"
git config --global user.name "Microsoft Manila CI"

cd /opt/stack/manila
# This will log the console output of unavailable share instances.
git fetch git://git.openstack.org/openstack/manila refs/changes/74/352474/1
cherry_pick FETCH_HEAD

cd /home/ubuntu/devstack

./unstack.sh

#Fix for unproper ./unstack.sh
screen_pid=$(ps auxw | grep -i screen | grep -v grep | awk '{print $2}')
if [[ -n $screen_pid ]] 
then
    kill -9 $screen_pid
    #In case there are "DEAD ????" screens, we remove them
    screen -wipe
fi

# Workaround for the Nova API versions mismatch issue.
# git revert 8349aff5abd26c63470b96e99ade0e8292a87e7a --no-edit

# stack.sh output log
STACK_LOG="/opt/stack/logs/stack.sh.txt"
# keep this many rotated stack.sh logs
STACK_ROTATE_LIMIT=6
rotate_log $STACK_LOG $STACK_ROTATE_LIMIT

set -o pipefail
./stack.sh 2>&1 | tee $STACK_LOG

