#!/usr/bin/env bats

load '../../test/test_helper/bats-assert/load'
load '../../test/test_helper/bats-support/load'
source 'test/common.bash'

setup() {
    setup_ensure_clean_environment
}

teardown() {
    teardown_set_skip
}

@test "handle_clean when state is clean" {

    output="$(./deploy.sh clean)"

    # Assertions
    assert_equal "$output" "Current state is clean, nothing to do!"
}