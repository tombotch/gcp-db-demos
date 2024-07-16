#!/usr/bin/env bats

load '../../test/test_helper/bats-assert/load'
load '../../test/test_helper/bats-support/load'
source 'test/common.bash'
source 'test/deploy_common.bash'
source 'deploy.sh'


setup_file() {
    # Check if NO_TEARDOWN is not set or is false
    if [[ -z "$NO_TEARDOWN" ]] || [[ "$NO_TEARDOWN" == false ]]; then
        echo "Teardown WILL RUN at the end of the test." >&3  # Print to stderr
    fi
    setup_ensure_clean_environment
}


teardown_file() {
    if [[ -z "$NO_TEARDOWN" ]]; then
        #this should unblock removing the trial cluster
        perl  -i -0777 -pe 's/provisioner\s+"local-exec"\s*\{[^}]*?when\s*=\s*destroy[^}]*\}//g' ./tf/alloydb-base-2a-cluster-trial.tf
        teardown_deployment 
    else
        echo "teardown disabled" >&3  # Print to stderr for visibility in test output
    fi
}

@test "alloydb-trial deployment when state is clean" {
    test_deploy_alloydb "alloydb-trial"
}

@test "cymbal-air on top of alloydb-trial " {
    test_deploy_cymbal_air_on_alloy
}