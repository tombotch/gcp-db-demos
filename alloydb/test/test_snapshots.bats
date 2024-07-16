#!/usr/bin/env bats

load '../../test/test_helper/bats-assert/load'
load '../../test/test_helper/bats-support/load'
source 'test/common.bash'
source 'deploy.sh'

setup() {
    setup_ensure_clean_environment
}

teardown() {
    teardown_deployment
    #echo "foo"
}

test_snapshots(){
    #deploy test-net
    deploy_and_assert_snapshot "test-net" "$(suy)" '["test-min"]="1"' "test-min"

    #deploy test-vm
    deploy_and_assert_snapshot "test-vm" "$(suy)" '["test-min"]="1" ["test-net"]="2"' "test-net"
    
    #return down 1 level to test-net
    #this tests handle_back
    deploy_and_assert_snapshot "test-net" "$(suy)" '["test-min"]="1"' "test-min"

    #deploy test-vm again
    deploy_and_assert_snapshot "test-vm" "$(suy)" '["test-min"]="1" ["test-net"]="2"' "test-net"
    
    #return down 2 levels to test-min
    #this tests handle_back
    deploy_and_assert_snapshot "test-min" "$(suy)" "" "null"
}

@test "test snapshots deployment" {
    #here we are going to create a graph/stack of states and traverse it
    deploy_and_assert_state "test-min" \
        "$(suy "test-snapshots" $BILLING_ID $VAR_REGION)"

    test_snapshots
    
}

@test "test detached snapshots deployment" {
    #here we are going to create a graph/stack of states and traverse it
    deploy_and_assert_state "test-min" \
        "$(suy "test-snapshots" $BILLING_ID $VAR_REGION)"

    project_id=$(get_project_id)
    echo "project_id: $project_id" >&3

    echo "Detaching..." >&3
    output="$(./deploy.sh detach)"
    echo "Detaching complete... testing" >&3

    #after detach, the current folder should have a clean state
    assert_state "clean"

    #switch to detached dir
    detached_dir="deployments/$project_id"
    cd "$detached_dir" || {
        echo "Error: Failed to change directory to '$detached_dir'" >&2
        exit 1
    }

    test_snapshots

    #clean detached deployment
    cleanup_deployment

    #go back to main folder
    cd ../../

    #delete detached folder
    rm -rf "$detached_dir"
}