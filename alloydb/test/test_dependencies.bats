#!/usr/bin/env bats

load '../../test/test_helper/bats-assert/load'
load '../../test/test_helper/bats-support/load'
source 'test/common.bash'
source 'deploy.sh'

setup() {
    setup_ensure_clean_environment

    #we can't send user input to nested calls, so here we use tfvars
    create_tfvars   "test-dependency" \
                    "billing_account_id" "$BILLING_ID" \
                    "region" "$VAR_REGION" \
                    "alloydb_password" "$VAR_PASSWORD"
}

teardown() {
    teardown_deployment
    #echo "foo"
}



@test "test find_targets_dependency" {
    load_definitions
    output=$(find_targets_dependency "cymbal-air")
    assert_equal "$output" "alloydb-base"

    output=$(find_targets_dependency "alloydb-base")
    assert_equal "$output" "landing-zone"
    
    output=$(find_targets_dependency "landing-zone")
    assert_equal "$output" ""
}

#what if one of the dependent snapshots is already deployed?
@test "test find_targets_dependency at snapshot" {
    export TF_AUTO_APPROVE=true
    deploy_and_assert_state "test-min" ""


    load_definitions
    output=$(find_targets_dependency "test-vm")
    assert_equal "$output" "test-net"

    output=$(find_targets_dependency "test-net")
    assert_equal "$output" ""
    
    output=$(find_targets_dependency "test-min")
    assert_equal "$output" ""
}

@test "test dependency deployment" {
    #use auto approve due to nested calls
    export TF_AUTO_APPROVE=true
    deploy_and_assert_state "test-vm" ""

    #Behind the scenes, there should be snapshot(s) created
    assert_snapshot_state "test-net"
}
