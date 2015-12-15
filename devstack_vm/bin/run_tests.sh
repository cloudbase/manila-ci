#!/bin/bash

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

testr run --subunit --parallel --load-list=$RUN_TESTS_LIST  > $log_file 2>&1

cat $log_file | subunit-trace -n -f > $tempest_output_file 2>&1 || true

cd /home/ubuntu/tempest/

echo "Generating HTML report..."
python $basedir/subunit2html.py $log_file $results_html_file

subunit-stats $log_file > $subunit_stats_file
