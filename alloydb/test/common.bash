# Pass IS_DRY_RUN from the environment to the sourced script
export IS_DRY_RUN="${IS_DRY_RUN:-false}" # Default to false if not set

declare -g BILLING_ID=$(cat "test/secrets/billing_id.secret")
declare -g VAR_REGION="europe-west4"
declare -g VAR_PASSWORD=$(cat "test/secrets/password.secret")
declare -g CURRENT_STATE=$(cat ".current_state" 2>/dev/null || echo "clean")

#simulates user input 
function sui() {
    local result=""
    for str in "$@"; do
        result+="$str\n"
    done
    # Remove the trailing newline
    #result=${result%$'\n'}
    echo "$result"
}

#similar to sui, but appends yes by default
function suy() {
    local result=$(sui "$@")
    result+="yes\n"
    echo "$result"
}

setup_ensure_clean_environment() {
    [ ! -f ${BATS_PARENT_TMPNAME}.skip ] || skip "skip remaining tests"

    declare -g CURRENT_STATE=$(cat ".current_state" 2>/dev/null || echo "clean")
    if [[ "$CURRENT_STATE" != "clean" ]]; then
        echo "Error: Current state is not clean. Expected 'clean', found '$CURRENT_STATE'." >&2
        exit 1  # Exit with an error code
    fi
    ./deploy.sh power-wash <<< "yes"
}

teardown_set_skip() {
    echo "Test completed: $BATS_TEST_COMPLETED" >&3
    if [[ "$BATS_TEST_COMPLETED" != 1 ]]; then 
        echo "Touching skip file!" >&3
        touch "${BATS_PARENT_TMPNAME}.skip"
    fi
}

#similar to cleanup_deployment, but can be used in teardown
teardown_deployment() {
    cleanup_deployment
    teardown_set_skip
}


cleanup_deployment() {
    echo "Cleaning up deployment in $(pwd)" >&3

    output=$(./deploy.sh clean <<EOF
yes
EOF
)
    echo "$output" >&3
    CURRENT_STATE=$(cat ".current_state" 2>/dev/null || echo "clean")
    if [[ "$CURRENT_STATE" == "clean" ]]; then 
        rm -f tf/terraform.tfvars
    else
        echo "Current state after cleanup is not clean. Expected 'clean', found '$CURRENT_STATE'." >&2
        exit 1  # Exit with an error code
    fi
}

function assert_state {
    local demo_name="$1"

    CURRENT_STATE=$(cat ".current_state" 2>/dev/null || echo "clean")
    assert_equal "$CURRENT_STATE" "$demo_name"
}

function deploy_and_assert_state {
    local demo_name="$1"
    local usr_input="$2"
    local state_name="$3"  # Optional state_name argument

    echo "Deploying $demo_name" >&3
    echo "usr_input: $usr_input" >&3

     # Use a temporary file to preserve newlines
    local temp_input_file=$(mktemp)
    echo -e "$usr_input" > "$temp_input_file"
    
    output=$(./deploy.sh "$demo_name" < "$temp_input_file")
    
    # Check the exit status of deploy.sh
    if [[ $? -ne 0 ]]; then
        echo "Error: deploy.sh failed with exit code $?. Output: $output" >&2
        echo "$output" >&2 
        fail "Deployment of $demo_name failed"
    fi

    # Assert the state using state_name if provided, otherwise use demo_name
    local state_to_assert="${state_name:-$demo_name}"  # Use state_name if defined, else demo_name
    assert_state "$state_to_assert"

    # Clean up the temporary file
    rm "$temp_input_file"
}

function assert_past_states {
    local expected_states="$1"

    past_states=$(list_previous_states)
    echo "Past states: $past_states" >&3
    assert_equal "$past_states" "$expected_states"
}

function assert_snapshot_state {
    local expected_state="$1"
    local snapshot_number=$(get_latest_snapshot_dir)
    echo "snap path: .snapshots/$snapshot_number/.current_state" >&3
    

    snap_state=$(cat .snapshots/$snapshot_number/.current_state 2>/dev/null || echo "null")
    echo "Snap state: $snap_state" >&3    
    assert_equal "$snap_state" "$expected_state"
}

function deploy_and_assert_snapshot {
    local demo_name="$1"
    local usr_input="$2"
    local expected_states="$3"
    local expected_snapshot_state="$4"

    deploy_and_assert_state $demo_name $usr_input 
    assert_past_states "$expected_states"
    assert_snapshot_state $expected_snapshot_state
}

#creates tfvars based on value pairs
#the first param is project_id, as it's always required
create_tfvars() {
    local project_id="$1"
    shift  # Shift the arguments to process the remaining key-value pairs

    # Ensure TF_DIR exists
    mkdir -p "$TF_DIR"

    # Create the .tfvars file
    {
        echo "demo_project_id = \"$project_id\""  # Always include the project_id

        # Process the remaining key-value pairs
        while [[ $# -gt 0 ]]; do
            key="$1"
            value="$2"
            echo "$key = \"$value\""
            shift 2  # Shift two arguments at a time
        done
    } > "$TF_DIR/terraform.tfvars"
}

append_tfvars() {
    # Ensure TF_DIR exists
    mkdir -p "$TF_DIR"

    # Create the .tfvars file
    {
        # Process the remaining key-value pairs
        while [[ $# -gt 0 ]]; do
            key="$1"
            value="$2"
            echo "$key = \"$value\""
            shift 2  # Shift two arguments at a time
        done
    } >> "$TF_DIR/terraform.tfvars"
}