#!/bin/bash

source /home/ubuntu/devstack/functions
TEMPEST_CONFIG=/opt/stack/tempest/etc/tempest.conf

echo "Updating tempest settings"
iniset $TEMPEST_CONFIG identity username demo
iniset $TEMPEST_CONFIG identity password Passw0rd
iniset $TEMPEST_CONFIG identity tenant_name demo
iniset $TEMPEST_CONFIG identity alt_username alt_demo
iniset $TEMPEST_CONFIG identity alt_password Passw0rd
iniset $TEMPEST_CONFIG identity admin_username admin
iniset $TEMPEST_CONFIG identity admin_password Passw0rd
iniset $TEMPEST_CONFIG identity admin_tenant_name admin

iniset $TEMPEST_CONFIG share enable_protocols cifs
iniset $TEMPEST_CONFIG share enable_ip_rules_for_protocols ""
iniset $TEMPEST_CONFIG share enable_user_rules_for_protocols cifs
iniset $TEMPEST_CONFIG share enable_ro_access_level_for_protocols cifs
iniset $TEMPEST_CONFIG share storage_protocol CIFS
iniset $TEMPEST_CONFIG share image_with_share_tools ws2012r2
iniset $TEMPEST_CONFIG share image_username Admin
iniset $TEMPEST_CONFIG share client_vm_flavor_ref 100
iniset $TEMPEST_CONFIG share build_timeout 2400

public_id=`neutron net-list | grep public | awk '{print $2}'`
iniset $TEMPEST_CONFIG network public_network_id $public_id

TEMPEST_BASE="/opt/stack/tempest"

cd $TEMPEST_BASE

testr init

TEMPEST_DIR="/home/ubuntu/tempest"
EXCLUDED_TESTS="$TEMPEST_DIR/excluded_tests.txt"
RUN_TESTS_LIST="$TEMPEST_DIR/test_list.txt"
log_file="/home/ubuntu/tempest/subunit-output.log"
results_html_file="/home/ubuntu/tempest/results.html"
tempest_output_file="/home/ubuntu/tempest/tempest-output.log"
subunit_stats_file="/home/ubuntu/tempest/subunit_stats.log"
basedir="/home/ubuntu/bin"

mkdir -p "$TEMPEST_DIR"

# Checkout stable commit for tempest to avoid possible
# incompatibilities for plugin stored in Manila repo.
#automatically get the latest commit

wget --quiet https://raw.githubusercontent.com/openstack/manila/master/contrib/ci/common.sh -O /tmp/manilacommon.sh
exportcmd=$(grep MANILA_TEMPEST_COMMIT /tmp/manilacommon.sh)
eval $exportcmd
rm -f /tmp/manilacommon.sh

git checkout $MANILA_TEMPEST_COMMIT

export OS_TEST_TIMEOUT=2400

# TODO: run consistency group tests after we adapt our driver to support this feature (should be minimal changes)
testr list-tests | grep "manila_tempest_tests.tests.api" | grep -v consistency_group | grep -v security_services | grep -v test_mtu_with_neutron | grep -v test_gateway_with_neutron > "$RUN_TESTS_LIST"
res=$?
if [ $res -ne 0 ]; then
    echo "failed to generate list of tests"
    exit $res
fi

testr run --subunit --parallel --load-list=$RUN_TESTS_LIST  > $log_file 2>&1

cat $log_file | subunit-trace -n -f > $tempest_output_file 2>&1 || true

cd /home/ubuntu/tempest/

echo "Generating HTML report..."
subunit2html $log_file $results_html_file

subunit-stats $log_file > $subunit_stats_file
