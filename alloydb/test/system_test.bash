#! /bin/bash
#Tests internal workings of the deployment script, but not the deployments itself

echo "$(pwd)"

bats $(find test -name "*.bats" | grep -v '_deploy_')
