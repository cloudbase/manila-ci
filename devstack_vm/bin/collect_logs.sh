#!/bin/bash

TAR=$(which tar)
GZIP=$(which gzip)
DEVSTACK_LOG_DIR="/opt/stack/logs"
DEVSTACK_LOGS="/opt/stack/logs/screen"
DEVSTACK_BUILD_LOG="/opt/stack/logs/stack.sh.txt"
TEMPEST_LOGS="/home/ubuntu/tempest"
HYPERV_CONFIGS="/openstack/config"
HYPERV_LOGS="/openstack/logs"

LOG_DST="/home/ubuntu/aggregate"
LOG_DST_DEVSTACK="$LOG_DST/devstack_logs"
LOG_DST_HV="$LOG_DST/Hyper-V_logs"
LOG_DST_TEMPEST="$LOG_DST/tempest"
CONFIG_DST_DEVSTACK="$LOG_DST/devstack_config"
CONFIG_DST_HV="$LOG_DST/Hyper-V_config"

hyperv_node=$1
win_user=$2
win_pass=$3
is_debug=$4


function emit_error() {
    echo "ERROR: $1"
    exit 1
}

function emit_warning() {
    echo "WARNING: $1"
    return 0
}

function archive_devstack() {
    if [ ! -d "$LOG_DST_DEVSTACK" ]
    then
        mkdir -p "$LOG_DST_DEVSTACK" || emit_error "L30: Failed to create $LOG_DST_DEVSTACK"
    fi

    if [ ! -d "$LOG_DST_TEMPEST" ]
    then
        mkdir -p "$LOG_DST_TEMPEST" || emit_error "L30: Failed to create $LOG_DST_TEMPEST"
    fi

    for i in `ls -A $DEVSTACK_LOGS`
    do
        if [ -h "$DEVSTACK_LOGS/$i" ]
        then
                REAL=$(readlink "$DEVSTACK_LOGS/$i")
                if [ -f "$REAL" ]; then
                    $GZIP -c "$REAL" > "$LOG_DST_DEVSTACK/$i.gz" || emit_warning "Failed to archive devstack logs"
                fi
        fi
    done
    
    for screen_log in `ls -A $DEVSTACK_LOG_DIR | grep screen-.*.txt`; do
        $GZIP -c "$DEVSTACK_LOG_DIR/$screen_log" > "$LOG_DST_DEVSTACK/$screen_log.gz" || emit_warning "L58: Failed to archive devstack logs"
    done
    
    for stack_log in `ls -A $DEVSTACK_LOG_DIR | grep "stack.sh.txt" | grep -v "gz"`
    do
        $GZIP -c "$DEVSTACK_LOG_DIR/$stack_log" > "$LOG_DST_DEVSTACK/$stack_log.gz" || emit_warning "Failed to archive devstack log"
    done

    for i in manila cinder glance keystone neutron nova openvswitch openvswitch-switch
    do
        mkdir -p $CONFIG_DST_DEVSTACK/$i
        for j in `ls -A /etc/$i`
        do
            if [ -d /etc/$i/$j ]
            then
                $TAR cvzf "$CONFIG_DST_DEVSTACK/$i/$j.tar.gz" "/etc/$i/$j"
            else
                $GZIP -c "/etc/$i/$j" > "$CONFIG_DST_DEVSTACK/$i/$j.gz"
            fi
        done
    done
    #$GZIP -c /home/ubuntu/devstack/localrc > "$CONFIG_DST_DEVSTACK/localrc.txt.gz"
    $GZIP -c /home/ubuntu/devstack/local.conf > "$CONFIG_DST_DEVSTACK/local.conf.gz"
    $GZIP -c /opt/stack/tempest/etc/tempest.conf > "$CONFIG_DST_DEVSTACK/tempest.conf.gz"
    $GZIP -c /opt/stack/tempest/tempest.log > "$LOG_DST_TEMPEST/tempest.log.gz"
    df -h > "$CONFIG_DST_DEVSTACK/df.txt" 2>&1 && $GZIP "$CONFIG_DST_DEVSTACK/df.txt"
    iptables-save > "$CONFIG_DST_DEVSTACK/iptables.txt" 2>&1 && $GZIP "$CONFIG_DST_DEVSTACK/iptables.txt"
    dpkg-query -l > "$CONFIG_DST_DEVSTACK/dpkg-l.txt" 2>&1 && $GZIP "$CONFIG_DST_DEVSTACK/dpkg-l.txt"
    pip freeze > "$CONFIG_DST_DEVSTACK/pip-freeze.txt" 2>&1 && $GZIP "$CONFIG_DST_DEVSTACK/pip-freeze.txt"
    ps axwu > "$CONFIG_DST_DEVSTACK/pidstat.txt" 2>&1 && $GZIP "$CONFIG_DST_DEVSTACK/pidstat.txt"
    #/var/log/kern.log
    #/var/log/rabbitmq/
    #/var/log/syslog
}

function archive_tempest_files() {
    for i in `ls -A $TEMPEST_LOGS`
    do
        $GZIP "$TEMPEST_LOGS/$i" -c > "$LOG_DST_TEMPEST/$i.gz" || emit_error "Failed to archive tempest logs"
    done
}

function archive_hyperv_configs() {
    if [ ! -d "$CONFIG_DST_HV" ]
    then
        mkdir -p "$CONFIG_DST_HV"
    fi
    COUNT=1
    for i in `ls -A "$HYPERV_CONFIGS"`
    do
        if [ -d "$HYPERV_CONFIGS/$i" ]
        then
            NAME=`echo $i | sed 's/^\(hv-compute[0-9]\{2,3\}\)\|^\(c[0-9]-r[0-9]-u[0-9]\{2\}\)/hv-compute'$COUNT'/g'`
            
            mkdir -p "$CONFIG_DST_HV/$NAME"
            COUNT=$(($COUNT + 1))

            for j in `ls -A "$HYPERV_CONFIGS/$i"`
            do
                if [ -d "$HYPERV_CONFIGS/$i/$j" ]
                then
                    mkdir -p "$CONFIG_DST_HV/$NAME/$j"
                    for k in `ls -A "$HYPERV_CONFIGS/$i/$j"`
                    do
                        if [ -d "$HYPERV_CONFIGS/$i/$j/$k" ]
                        then
                            $TAR cvzf "$CONFIG_DST_HV/$NAME/$j/$k.tar.gz" "$HYPERV_CONFIGS/$i/$j/$k"
                        else
                            $GZIP -c "$HYPERV_CONFIGS/$i/$j/$k" > "$CONFIG_DST_HV/$NAME/$j/$k.gz" || emit_warning "Failed to archive $HYPERV_CONFIGS/$i/$j/$k"
                        fi
                    done
                else
                    $GZIP -c "$HYPERV_CONFIGS/$i/$j" > "$CONFIG_DST_HV/$NAME/$j.gz" || emit_warning "Failed to archive $HYPERV_CONFIGS/$i/$j"
                fi
            done
        else
            $GZIP -c "$HYPERV_CONFIGS/$i" > "$CONFIG_DST_HV/$i.gz" || emit_warning "Failed to archive $HYPERV_CONFIGS/$i"
        fi
    done
}

function archive_hyperv_logs() {
    if [ ! -d "$LOG_DST_HV" ]
    then
        mkdir -p "$LOG_DST_HV"
    fi
    COUNT=1
    for i in `ls -A "$HYPERV_LOGS"`
    do
        if [ -d "$HYPERV_LOGS/$i" ]
        then
            NAME=`echo $i | sed 's/^\(hv-compute[0-9]\{2,3\}\)\|^\(c[0-9]-r[0-9]-u[0-9]\{2\}\)/hv-compute'$COUNT'/g'`
            
            mkdir -p "$LOG_DST_HV/$NAME"
            COUNT=$(($COUNT + 1))

            for j in `ls -A "$HYPERV_LOGS/$i"`
            do
                if [ -d "$HYPERV_LOGS/$i/$j" ]
                then
                    mkdir -p "$LOG_DST_HV/$NAME/$j"
                    for k in `ls -A "$HYPERV_LOGS/$i/$j"`
                    do
                        $GZIP -c "$HYPERV_LOGS/$i/$j/$k" > "$LOG_DST_HV/$NAME/$j/$k.gz" || emit_warning "Failed to archive $HYPERV_LOGS/$i/$j/$k"
                    done
                else
                    $GZIP -c "$HYPERV_LOGS/$i/$j" > "$LOG_DST_HV/$NAME/$j.gz" || emit_warning "Failed to archive $HYPERV_LOGS/$i/$j"
                fi
            done
        else
            $GZIP -c "$HYPERV_LOGS/$i" > "$LOG_DST_HV/$i.gz" || emit_warning "Failed to archive $HYPERV_LOGS/$i"
        fi
    done
}

function get_win_files() {
    local host=$1
    local remote_dir=$2
    local local_dir=$3
    if [ ! -d "$local_dir" ];then
        mkdir -p "$local_dir"
    fi
    smbclient "//$host/C\$" -c "prompt OFF; cd $remote_dir" -U "$win_user%$win_pass"
    if [ $? -ne 0 ];then
        echo "Folder $remote_dir does not exists"
        return 0
    fi
    smbclient "//$host/C\$" -c "prompt OFF; recurse ON; lcd $local_dir; cd $remote_dir; mget *" -U "$win_user%$win_pass"
}

[ -d "$LOG_DST" ] && rm -rf "$LOG_DST"
mkdir -p "$LOG_DST"

for u in `sudo systemctl list-unit-files | grep devstack | awk '{print $1}'`; do
    name=$(echo $u | sed 's/devstack@/screen-/' | sed 's/\.service//')
    sudo journalctl -o short-precise --unit $u | sudo tee /opt/stack/logs/$name.txt > /dev/null
done

echo Getting Hyper-V logs
get_win_files $hyperv_node "\OpenStack\logs" "$LOG_DST_HV/$hyperv_node"

echo Getting Hyper-V configs
get_win_files $hyperv_node "\OpenStack\etc" "$CONFIG_DST_HV/$hyperv_node"

archive_devstack
archive_hyperv_configs
archive_hyperv_logs
archive_tempest_files

pushd "$LOG_DST"
$TAR -czf "$LOG_DST.tar.gz" . || emit_error "Failed to archive aggregate logs"
popd

# Clean
if [[ -z $is_debug ]] || [[ $is_debug != "yes" ]]; then
    echo "no debug case. Param is: $is_debug"
    pushd /home/ubuntu/devstack
    ./unstack.sh
    popd
else
    echo "skipped unstack since we activated debug."
fi

exit 0
