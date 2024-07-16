create_alloydb_tfvars(){
    #we can't send user input to nested calls, so here we use tfvars
    create_tfvars   "test-$demo_name" \
                    "billing_account_id" "$BILLING_ID" \
                    "region" "$VAR_REGION" \
                    "alloydb_password" "$VAR_PASSWORD" \
                    "test_mode" "true" #this is important so we don't create real trial cluster
}

test_deploy_alloydb(){
    demo_name="$1"

    create_alloydb_tfvars
    
    #use auto approve due to nested calls
    export TF_AUTO_APPROVE=true
    
    deploy_and_assert_state "$demo_name" ""

    #Behind the scenes, there should be landing-zone snapshot created
    assert_snapshot_state "landing-zone"

    #make sure db is accessible
    if [[ "$IS_DRY_RUN" != true ]]; then
        output=$(gcloud compute ssh alloydb-client --zone "$VAR_REGION-a" \
                --tunnel-through-iap --project $(get_project_id) \
                --command="export PGPASSWORD='$VAR_PASSWORD'; source ~/.profile; psql -c 'SELECT current_database(), version();'")

        echo $output >&3
        expected_pattern='PostgreSQL [0-9.]+'

        # Assert that the output matches the expected pattern
        if [[ "$output" =~ $expected_pattern ]]; then
            echo "pass"
        else
            fail "Output doesn't match expected pattern. Actual output: $output"  # Indicate failure with a message
        fi
    fi
}

#this will deploy cymbal air on top of existing alloydb - trial or base
test_deploy_cymbal_air_on_alloy() {
    #append required vars
    append_tfvars   "demo_app_support_email" "$(cat 'test/secrets/support_email.secret')"
    
    #use auto approve due to nested calls
    export TF_AUTO_APPROVE=true
    
    deploy_and_assert_state "cymbal-air" "" "cymbal-air-base"

    #Prompt the user to create Client Secret
    while true; do
        echo "" >&3
        echo "MANUAL STEP REQUIRED" >&3
        echo "" >&3
        echo "You now need to do the manual step and then provide Oauth Client ID" >&3
        echo "https://console.cloud.google.com/apis/credentials?project=$(get_project_id)" >&3
        echo "Enter y when you are done with the manual step" >&3
        read -p "" yn
        case $yn in
            [Yy]* ) break;;
            [Nn]* ) exit;;
            * ) echo "Please answer yes or no.";;
        esac
        echo "end";
    done

    #Prompt the user to enter client id and add it to the config
    echo "Now enter the Client ID" >&3
    read -p "" client_id
    append_tfvars   "cymbail_air_web_app_client_id" "$client_id"
    
    #deploy 2nd phase
    deploy_and_assert_state "cymbal-air" ""

    #start cymbal air
    ./cymbal-air-start.sh &
    pid=$!
    echo "Starting cymbal-air server" >&3
    #wait for the server to come up
    sleep 30
    #fetch the page
    echo "Fetching..." >&3
    output=$(wget -O - http://localhost:8081)
    #test output
    expected_pattern='<!doctype html>.*<title>Assistant</title>.*<div class="chat-wrapper">.*Welcome to Cymbal Air.*</div>.*<input type="text".*placeholder="type your question here'
    # Assert that the output matches the expected pattern
    if [[ "$output" =~ $expected_pattern ]]; then
        echo "Cymbal air up and running!" >&3
    else
        echo "Cymbal air doesn't seem to be up!" >&3
        fail "Output doesn't match expected pattern. Actual output: $output"
    fi
    #echo "Killing server" >&3
    #kill -9 "$pid"
}