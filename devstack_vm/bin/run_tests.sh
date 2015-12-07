#!/bin/bash

TEMPEST_BASE="/opt/stack/tempest"

cd $TEMPEST_BASE

testr init

TEMPEST_DIR="/home/ubuntu/tempest"
EXCLUDED_TESTS="$TEMPEST_DIR/excluded_tests.txt"
RUN_TESTS_LIST="$TEMPEST_DIR/test_list.txt"
mkdir -p "$TEMPEST_DIR"

# Checkout stable commit for tempest to avoid possible
# incompatibilities for plugin stored in Manila repo.
TEMPEST_COMMIT=${TEMPEST_COMMIT:-"d160c29b"}  # 01 Dec, 2015
git checkout $TEMPEST_COMMIT

export OS_TEST_TIMEOUT=2400

# TODO: run consistency group tests after we adapt our driver to support this feature (should be minimal changes)
testr list-tests | grep "manila_tempest_tests.tests.api" | grep -v consistency_group | grep -v security_services > "$RUN_TESTS_LIST"
res=$?
if [ $res -ne 0 ]; then
    echo "failed to generate list of tests"
    exit $res
fi

testr run --subunit --parallel --load-list=$RUN_TESTS_LIST | subunit-trace -n -f > /home/ubuntu/tempest/tempest-output.log 2>&1

RET=$?
cd /home/ubuntu/tempest/
/usr/local/bin/subunit2html /home/ubuntu/tempest/subunit-output.log
exit $RET
