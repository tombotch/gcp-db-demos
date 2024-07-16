#! /bin/bash

echo "$(pwd)"

IS_DRY_RUN=true bats $(find test -name "*.bats" | grep -v '_deploy_')
