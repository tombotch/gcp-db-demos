#!/usr/bin/env bats

load '../../test/test_helper/bats-assert/load'
load '../../test/test_helper/bats-support/load'
source 'test/common.bash'
source 'deploy.sh'


@test "Available targets in clean state" {
    load_definitions
    # Capture the output in an array
    read -ra actual_targets <<< "$(get_valid_targets "clean")"

    # Define the expected targets as an array
    expected_targets=("alloydb-base" "alloydb-trial" "cymbal-air")

    # Assert that both arrays contain the same elements (regardless of order)
    assert_equal "$(printf '%s\n' "${actual_targets[@]}" | sort)" "$(printf '%s\n' "${expected_targets[@]}" | sort)"
}

@test "Available targets in alloydb-trial state" {
    load_definitions
    # Capture the output in an array
    read -ra actual_targets <<< "$(get_valid_targets "alloydb-trial")"

    # Define the expected targets as an array
    expected_targets=("cymbal-air" "clean")

    # Assert that both arrays contain the same elements (regardless of order)
    assert_equal "$(printf '%s\n' "${actual_targets[@]}" | sort)" "$(printf '%s\n' "${expected_targets[@]}" | sort)"
}

@test "Available targets in alloydb-base state" {
    load_definitions
    # Capture the output in an array
    read -ra actual_targets <<< "$(get_valid_targets "alloydb-trial")"

    # Define the expected targets as an array
    expected_targets=("cymbal-air" "clean")

    # Assert that both arrays contain the same elements (regardless of order)
    assert_equal "$(printf '%s\n' "${actual_targets[@]}" | sort)" "$(printf '%s\n' "${expected_targets[@]}" | sort)"
}

#TODO: test in combination with snapshots