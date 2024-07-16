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
}

@test "test detaching test-min" {
    deploy_and_assert_state "test-min" \
        $(suy "test-detach" $BILLING_ID $VAR_REGION)

    project_id=$(get_project_id)
    echo "project_id: $project_id" >&3

    echo "Detaching..." >&3
    output="$(./deploy.sh detach)"
    echo "Detaching complete... testing" >&3
    
    #after detach, the current folder should have a clean state
    assert_state "clean"

    #check that tf folder doesn't exist
    if [[ -d "$TF_DIR" ]]; then
        echo "tf folder should not exist, but it does" >&3
        exit 1
    fi

    #check that snapshots folder doesn't exist
    if [[ -d "$SNAPSHOTS_DIR" ]]; then
        echo ".snapshots folder should not exist, but it does" >&3
        exit 1
    fi

    #not sure about backups... we could leave them in place?

    #switch to detached dir
    detached_dir="deployments/$project_id"
    cd "$detached_dir" || {
        echo "Error: Failed to change directory to '$detached_dir'" >&2
        exit 1
    }

    #the detached folder should have test-min state
    assert_state "test-min"

    #check that tf folder is there
    if [[ ! -d "$TF_DIR" ]]; then
        echo "tf folder should exist, but it does not" >&3
        exit 1
    fi

    #deploy test-net in detached state
    deploy_and_assert_state "test-net" "$(suy)"

    #go back to main folder
    cd ../../

    #assert it's still clean
    assert_state "clean"

    #go back to detached folder
    cd "$detached_dir" || {
        echo "Error: Failed to change directory to '$detached_dir'" >&2
        exit 1
    }

    #clean
    echo "Cleaning detached deployment" >&3
    cleanup_deployment

    #go back to main folder
    echo "Going back to previous folder" >&3
    cd ../../
    echo "pwd :$(pwd)" >&3

    #delete detached folder
    echo "Removing detached dir" >&3
    rm -rf "$detached_dir" || echo "Warning: Failed to remove detached directory '$detached_dir'" >&2
}

@test "detach when state is clean" {

    output="$(./deploy.sh detach)"

    # Assertions
    assert_equal "$output" "Current state is clean, nothing to detach!"
}