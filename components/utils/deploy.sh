#! /bin/bash
#
# Description:
# This script manages the deployment and configuration of various demo environments
# using Terraform. It reads product-specific configuration details from a `config.sh` 
# file, which is used to tailor the script for separate products (alloydb, spanner,..).
# There is one "master" file, which is soft linked to product specific files.
# The config.sh files are unique for each of the products
#
# One aspect of this script is that it is aiming to enable modular demo deployments,
# ie, user can first deploy alloydb-base, and then decide to deploy cymbal-air on top
# and then return to alloydb-base. However, this feature is not guaranteed to work and
# deploying parallel demos is not supported at this time (ie, startin with alloydb-base
# and then branching out to cymbal-air demo and foo-demo in parallel )
#
# Instead, the script supports "detaching" an environment - meaning that the active
# config is moved to /deployments/project_id folder, where it can be managed as a
# separate unit. The downside of this approach is that it means multiple parallel database
# instances, which is not ideal, so we should investigate improving branching out 
# in the future.
#
# Commands:
# - running script with no command: will display the current state and possible states
#   to transition to (meaning - adding or removing demos)
# 
# - demo-name: will deploy the demo, assuming the transition to installing that demo is
#   possible (as per package maintainer)
#
# - clean: will undeploy all deployed resources (tf destroy) and clean up files, but will
#   leave tfvars in place
#
# - power-wash: will force delete all files. User will need to delete the project manually
#
# - detach: the active config is moved to /deployments/project_id folder, 
#  where it can be managed as a separate unit
#
#
# TODO:
# - detach command shoud not be available from a detached script
#
# CONFIG BLOCKS
#
# - DEFINITIONS: Must contain:
#     - VALID_TRANSITIONS
#     - DEMO_FILES
# 
# - TF_STRING_REPLACEMENTS: optional: can contain pairs of strings to be find and replace
#     - TF_REPLACEMENTS
#
# - CUSTOM HELP: any custom echo commands, can be conditional, ie based on current state
#
# - SUBSTITUTE_TARGET_DEMO: if your demo requires intermediate step, inject it here
#   (replace user target demo with the intermediate demo step name)
# 
# - CUSTOM_STATE_TRANSITIONS: optional, can contain logic to process custom states
#   ie, injecting additional state before the final state.
#   That hendler replaces the default and must have its own default option
#   echo $DEMO_NAME > .current_state if no custom state is detected!

#init
declare -g TF_DIR="./tf"
declare -g COMPONENTS_DIR="./components"
declare -g CORE_COMPONENTS_DIR="../$COMPONENTS_DIR"
declare -g CONFIG_FILE="config.sh"
declare -g CURRENT_STATE=$(cat ".current_state" 2>/dev/null || echo "clean")
declare -g DEMO_NAME="$1"
declare -g TF_LOG="./.tf.log"  # Define log file path

mkdir -p $TF_DIR #create the dir if it doesn't exist

read_config_tag() {
    local begin_tag="BEGIN_$1"
    local end_tag="END_$1"
    sed -n "/$begin_tag/,/$end_tag/{
        /$begin_tag/d
        /$end_tag/d
        p
    }" "$CONFIG_FILE"
}


load_definitions() {
     #common definitions - used by all products
    LANDING_ZONE_FILES=(
        "$CORE_COMPONENTS_DIR/00-landing-zone.tf"
        "$CORE_COMPONENTS_DIR/01-landing-zone-network.tf"
        "$CORE_COMPONENTS_DIR/02-landing-zone-apis.tf"
        "$CORE_COMPONENTS_DIR/03-landing-zone-clientvm.tf"
        "$CORE_COMPONENTS_DIR/09-landing-zone-vars.tf"
    )
    #Source product-specific definitions
    source <(read_config_tag DEFINITIONS)
}


clean_up() {
    rm -f ${TF_DIR}/*.tf
    rm -f ${TF_DIR}/terraform.tfstate*
    rm -f ${TF_DIR}/.terraform.*
    rm -rf ${TF_DIR}/.terraform
    rm -f cymbal-air-start.sh
}

print_tf_error() {
    local op=$1
    echo "An error occurred while running terraform!"
    echo "Sometimes the root cause are some timings - waiting a bit and trying again could help"
    echo "To try to resolve issue manually, go to tf subfolder and run"
    echo "terraform $op"
    if [[ $op == "destroy" ]]; then
        echo "You will also need to delete all terraform files: *.tf, terraform.tfstate*"
        echo ".terraform.* and .terraform folder"
        echo ""
    fi
    echo "In case the configuration can't be resolved, it's recommended to:"
    echo "- disable billing on the project"
    echo "- delete the project"
    
}

handle_display_usage() {
    source <(read_config_tag CUSTOM_HELP) 
    
    echo "Usage: $0 <demo_name>"
    echo "Currently supported demos, given current state '$CURRENT_STATE':"
    for transition in "${!VALID_TRANSITIONS[@]}"; do
        # Check if the transition starts from the current state
        # and that target is not test-min
        if [[ "${transition%,*}" == "$CURRENT_STATE" ]] && [[ "${transition#*,}" != "test-min" ]]; then 
            echo "- ${transition#*,}" # Print the target demo of the transition
        fi
    done
    # Clean is always available
    echo "- clean"
}

handle_detach() {
    DEPLOYMENTS_DIR="./deployments"
    mkdir -p $DEPLOYMENTS_DIR
    NEW_DIR="deployments/$(cd $TF_DIR && terraform output -raw project_id)"
    echo "Moving current config to $NEW_DIR!"
    mv ${TF_DIR} ${NEW_DIR} 
    mv cymbal-air-start.sh ${NEW_DIR}/ || true
    mv .current_state ${NEW_DIR}/ || true
    cp deploy.sh ${NEW_DIR}/ || true
    sed -i 's/TF_DIR=".\/tf"/TF_DIR="."/' ${NEW_DIR}/deploy.sh
    sed -i 's/COMPONENTS_DIR=".\/components"/COMPONENTS_DIR="..\/..\/components"/' ${NEW_DIR}/deploy.sh
    cp store-vars.sh ${NEW_DIR}/ || true
    sed -i 's/TF_DIR=".\/tf"/TF_DIR="."/' ${NEW_DIR}/store-vars.sh
    cp config.sh ${NEW_DIR}/ || true
    exit 0
}

handle_clean() {
    TF_AUTO_APPROVE=false  # Flag to track whether to force destroy

    if [ "$CURRENT_STATE" = "clean" ]; then
        echo "Current state is clean, nothing to do!"
        exit 0
    fi

    # There is an issue with serverless ip not being destroyed for quite some time
    # Detect it and retry 
    for i in {1..10}; do  # Attempt up to 10 times

        #if TF_AUTO_APPROVE is set, that indicates that network error has been detected
        if [[ $TF_AUTO_APPROVE == true ]]; then
            echo "Detected a known network dependency issue. Retrying in:"
            for countdown in {600..0}; do
                echo -ne "...$countdown seconds...\r"
                sleep 1
            done
            echo "Retrying now..."
        fi

        (cd "${TF_DIR}" && terraform destroy $([ "$TF_AUTO_APPROVE" == true ] && echo "-auto-approve")) 2> "$TF_LOG"
        if [ $? -eq 0 ]; then
            #Clean up
            clean_up
            echo "clean" > .current_state
            # Success, exit 
            exit 0
        else
            # Error occurred, print the log file contents
            echo "Terraform destroy failed. Error log:"
            cat "$TF_LOG"  # Print the contents of the log file
            
            # Error, check if it's the specific network error
            if grep -q "Error waiting for Deleting Network" "$TF_LOG" && grep -q "serverless-ipv4" "$TF_LOG"; then
                TF_AUTO_APPROVE=true  # Set the flag for subsequent retries
            else
                # Different error, break the loop and print the generic error message
                print_tf_error "destroy"
                echo "dirty" > .current_state
                exit 1
            fi
        fi
    done

    echo "All destroy attempts failed."
    exit 1  # Exit with an error code
}


handle_power_wash() {
    echo "Power-wash will wipe active configuration WITHOUT DESTROYING CLOUD RESOURCES"
    read -p "Are you sure you want to proceed? (y/n) " confirm
    case "$confirm" in
        [Yy]* ) 
            clean_up
            rm -f .current_state
            rm -rf $TF_DIR
            echo "Power-wash complete!"
            exit 0
            ;;
        * )
            echo "Power-wash cancelled."
            exit 0
            ;;
    esac
}

handle_dirty_state() {
    echo "!!!Current state is dirty!!!"
    echo "This means that something went wrong during terraform provisioning."
    echo "You can try to manually fix things by going into tf folder"
    echo "But probably best to destroy evertyhing and/or delete the project"
    echo "And start from scratch"
    exit 1
}

########################################
# The main demo deployment logic is here
handle_deploy_demo() { 
    # 0. Init
    #    Source any auto magic string replacements
    source <(read_config_tag TF_STRING_REPLACEMENTS)

    # 1. Check if transition is valid
    TRANSITION="${CURRENT_STATE},${DEMO_NAME}"
    if [[ -z "${VALID_TRANSITIONS[$TRANSITION]}" ]]; then
        echo "Error: Invalid transition from '$CURRENT_STATE' to '$DEMO_NAME'."
        exit 1
    fi

    # 2. Potentially switch the target demodeployment in place - 
    #    this is if we need some manual steps in between, see cymbal-air
    source <(read_config_tag SUBSTITUTE_TARGET_DEMO)

    # 3. Prepare files to copy based on demo name
    if [[ -v DEMO_FILES[$DEMO_NAME] ]]; then
        # Copy the files associated with the selected demo
        read -ra FILES_TO_COPY <<< "${DEMO_FILES[$DEMO_NAME]}"
    else
        echo "Error: Invalid demo name."
        exit 1
    fi

    # 4. Remove existing files from the TF directory
    rm -f ${TF_DIR}/*.tf 
    
    # 5. Copy files from the array (which includes path!) to a destination
    #    directory and file name excluding path (the ${file##*/} part)
    #    and replace some strings if needed
    for file in "${FILES_TO_COPY[@]}"; do
        cp "${file}" "${TF_DIR}/${file##*/}"
        
        # This is probably a huge antipattern, but it's useful
        # here we replace specific string with replacement string
        # in all tf files
        if [ -v TF_REPLACEMENTS ] && [ -f "${TF_DIR}/${file##*/}" ]; then
            # Iterate over replacements in pairs
            for ((i=0; i<${#TF_REPLACEMENTS[@]}; i+=2)); do
                OLD_STRING=${TF_REPLACEMENTS[i]}
                NEW_STRING=${TF_REPLACEMENTS[i+1]}

                # Replace the string using sed (with backup)
                sed -i "s/$OLD_STRING/$NEW_STRING/g" "${TF_DIR}/${file##*/}"
            done
        fi
    done
    
    # 6. Ask user to provide any tf variables which have no defaults
    #    this is so we can store them even if user transitions to clean state
    ./store-vars.sh
    
    # 7. Begin deployment - enter "dirty" state
    echo "dirty" > .current_state

    # 8. Deploy the demo using terraform
    (cd "${TF_DIR}" && terraform init && terraform apply)
    # Handle tf failures
    if [ $? -ne 0 ]; then
        print_tf_error "apply"
        exit 1
    fi

    # 9. Apply any custom state transitions or mark the desired state
    #    as the current state
    if [[ -n $(read_config_tag CUSTOM_STATE_TRANSITIONS) ]]; then
        source <(read_config_tag CUSTOM_STATE_TRANSITIONS)
    else
        echo $DEMO_NAME > .current_state
    fi

    # 10. All done!
    exit 0
}


main() {
    load_definitions

    case "$CURRENT_STATE,$DEMO_NAME" in
        # Any state with "power-wash" commands
        *,"power-wash")
            handle_power_wash
            exit 0
            ;;

        # Any state with clean command
        *,"clean")
            handle_clean
            exit 0
            ;;

        # Dirty state with any command or no command
        "dirty",* | "dirty,")
            handle_dirty_state
            exit 1
            ;;

        # Any state with "detach" command: Detach the configuration
        *,"detach")
            handle_detach
            exit 0
            ;;

        # No command: Display usage
        *,)
            handle_display_usage
            exit 0
            ;;

        # Deploy the demo
        *)
            handle_deploy_demo
            exit 0
            ;;
    esac
}

main $1