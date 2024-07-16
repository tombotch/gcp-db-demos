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
declare -g SNAPSHOTS_DIR=".snapshots"
declare -g BACKUPS_DIR=".backup"
# Check if IS_DRY_RUN is set in the environment
if [[ -z "${IS_DRY_RUN+x}" ]]; then  # Check if IS_DRY_RUN is unset
  declare -g IS_DRY_RUN=false         # Set default to false if unset
else
  declare -g IS_DRY_RUN="${IS_DRY_RUN}"
  echo "DRY RUN: $IS_DRY_RUN" >&2  
fi
# Check if TF_AUTO_APPROVE is set in the environment
if [[ -z "${TF_AUTO_APPROVE+x}" ]]; then
  declare -g TF_AUTO_APPROVE=false         # Set default to false if unset
else
 # Convert the environment variable value to lowercase for easier comparison
  declare -g TF_AUTO_APPROVE=$(echo "$TF_AUTO_APPROVE" | tr '[:upper:]' '[:lower:]')
  # Check if the lowercase value is "true"
  if [[ "$TF_AUTO_APPROVE" == "true" ]]; then
    declare -g TF_AUTO_APPROVE=true
  else
    declare -g TF_AUTO_APPROVE=false
  fi
  echo "AUTO APPROVE: $TF_AUTO_APPROVE" >&2  
fi
mkdir -p $TF_DIR #create the dir if it doesn't exist


#this should replace $CURRENT_STATE across the script, eventually
get_current_state() {
    local state=$(cat ".current_state" 2>/dev/null || echo "clean")
    echo "$state"
}


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

    # Create the VALID_TRANSITIONS dictionary from TRANSITIONS
    # This is historic for backwards compatibility for now
    declare -gA VALID_TRANSITIONS
    for transition in "${TRANSITIONS[@]}"; do
        VALID_TRANSITIONS["$transition"]="true"
    done

    # Get the list of previous states as an array
    #declare -a previous_states_data="( $(list_previous_states) )"
    local previous_states_data=($(list_previous_states))

    # Create the associative array by sourcing the output
    declare -gA PREVIOUS_STATES_DICT
    if [[ ${#previous_states_data[@]} -gt 0 ]]; then
        eval "PREVIOUS_STATES_DICT=(${previous_states_data[@]})"
    fi 

    # Add previous states as valid transitions
    for state in "${!PREVIOUS_STATES_DICT[@]}"; do
        if [[ "$state" != "$CURRENT_STATE" ]]; then 
            VALID_TRANSITIONS["$CURRENT_STATE,$state"]="true" 
        fi
    done
}


clean_up() {
    echo "Cleaning up $(pwd)!"
    rm -f ${TF_DIR}/*.tf
    rm -f ${TF_DIR}/terraform.tfstate*
    rm -f ${TF_DIR}/.terraform.*
    rm -rf ${TF_DIR}/.terraform
    find . -type f -name "*.sh" ! -name "deploy.sh" ! -name "config.sh" \
         ! -name "store-vars.sh" -delete 
    rm -rf ${SNAPSHOTS_DIR}
    find . -maxdepth 1 -type f -name ".*" -delete
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


get_latest_snapshot_dir() {
    local latest_snapshot_dir
    latest_snapshot_dir=$(ls -1d "$SNAPSHOTS_DIR"/* 2>/dev/null | sort -n | tail -1)

    if [[ -n $latest_snapshot_dir ]]; then
        echo $(basename "$latest_snapshot_dir")
    fi
}


list_previous_states() {
    local previous_states=() 
    if [[ -d "$SNAPSHOTS_DIR" ]] && [[ -n $(ls -A "$SNAPSHOTS_DIR") ]]; then 
        for snapshot_dir in "$SNAPSHOTS_DIR"/*/; do
            snapshot_number=$(basename "$snapshot_dir")
            previous_state=$(cat "$snapshot_dir/.current_state" 2> /dev/null)
            previous_states+=("[\"$previous_state\"]=\"$snapshot_number\"")  
        done
    fi

    # Output the dictionary in a format that can be easily sourced
    echo "${previous_states[@]}"
}

#this will create a copy of the current configuration in the target dir,
#can be used for detach or for backup
create_copy() {
    local destination_dir="$1"
    mkdir -p "$destination_dir"

    # Copy files and folders, excluding components, deployments, and test
    find . -mindepth 1 -maxdepth 1 \
        -not -path './components' -a -not -path './deployments' -a -not -path './test' \
        -a -not -path "./$BACKUPS_DIR" -a -not -path "./$SNAPSHOTS_DIR" \
        ! -type l -print0 | 
        xargs -0 cp -ra --target-directory="$destination_dir"

    # Copy symlinks as regular files
    find . -mindepth 1 -maxdepth 1 -type l -print0 | 
        xargs -0 -n 1 -r cp -L --target-directory="$destination_dir"

    # Copy snapshots via temp folder to avoid nested copy
    if [[ -d "$SNAPSHOTS_DIR" ]]; then  # Check if .snapshots directory exists
        local temp_snapshots_dir=$(mktemp -d)
        cp -r $SNAPSHOTS_DIR/ "$temp_snapshots_dir/"
        mv "$temp_snapshots_dir/$SNAPSHOTS_DIR" "$destination_dir/"
        rm -rf "$temp_snapshots_dir"
    fi
}


#as we change config, we store snapshots of each configuration so we can
#navigate back
store_snapshot() {
    local latest_snapshot_number=$(get_latest_snapshot_dir)
    local next_number=1
    if [[ -n $latest_snapshot_number ]]; then
        next_number=$((latest_snapshot_number + 1))
    fi

    local snapshot_dir="$SNAPSHOTS_DIR/$next_number"
    create_copy "$snapshot_dir" 
}


create_backup() {
    local timestamp=$(date +%Y%m%d_%H_%M_%S_%N)
    local backup_dir="$BACKUPS_DIR/$timestamp"
    create_copy "$backup_dir"
}

get_project_id() {
    local dry_run_project_id_file=".dry_run_project_id"

    if [[ $IS_DRY_RUN == true ]]; then
        if [[ -f "$dry_run_project_id_file" ]]; then
            # Read from file if it exists
            cat "$dry_run_project_id_file"
        else
            # Generate and store in file if it doesn't exist
            local random_suffix=$(head -c 200 /dev/urandom | tr -dc 'a-f0-9'| fold -w 4 | head -n 1)
            local dry_run_project_id="dry-run-$random_suffix"
            echo "$dry_run_project_id" > "$dry_run_project_id_file"
            echo "$dry_run_project_id"
        fi
    else
        echo "$(cd $TF_DIR && terraform output -raw project_id)"
    fi
}


#Because target deployment might be valid from clean state, but might have some prereqs,
#we use VALID_TRANSITIONS to find dependencies.
#
#Assumption is that a deployment has utmost 1 dependency at a certain point
#But might have multiple prior dependencies
#
#Some deployemnts are valid from multiple states - in that case, we take
#The first prior state as the default dependency
#
# ["alloydb-base,cymbal-air"]="true"
# ["alloydb-trial,cymbal-air"]="true"
#
#This would identify alloydb-base as dependency
#
#The function also considers current state - if a dependency is already deployed,
#It will return ""
function find_targets_dependency() {
    local target_state="$1"

    # Check if the current state is a valid transition to the target state
    if [[ "${VALID_TRANSITIONS[$CURRENT_STATE,$target_state]}" == "true" ]]; then
        echo ""  # Return empty string if the current state is already valid
        return 0
    fi


    # Iterate through the ORDERED_TRANSITIONS array
    for transition in "${TRANSITIONS[@]}"; do
        #echo "looking for: $target_state, found ${transition#*,} coming from " >&3

        # Check if the transition leads to the target state and doesn't start from "clean"
        if [[ "${transition#*,}" == "$target_state" ]] && 
           [[ "${transition%,*}" != "clean" ]] && #; then
           [[ "${transition%,*}" != "$(get_current_state)" ]]; then
            echo "${transition%,*}"  # Output the first non-clean prior state and exit the loop
            break
        fi
    done
    echo ""
}


#returns list of valid targets for the current state
function get_valid_targets() {
    local current_state="$1"
    local valid_transitions=()

    if [[ "$current_state" == "clean" ]]; then
        # If the state is clean, get all possible target demos
        for transition in "${!VALID_TRANSITIONS[@]}"; do
            target_demo="${transition#*,}"
            if [[ ! "$target_demo" =~ "test" ]]; then  # Exclude demos with "test" in their name
                valid_transitions+=("$target_demo")
            fi
        done
    else
        # If the state is not clean, use the existing logic
        for transition in "${!VALID_TRANSITIONS[@]}"; do
            if [[ "${transition%,*}" == "$current_state" ]] && [[ "${transition#*,}" != "test-min" ]]; then
                valid_transitions+=("${transition#*,}") 
            fi
        done

        # Add previous states as valid transitions
        for state in "${!PREVIOUS_STATES_DICT[@]}"; do
            if [[ "$state" != "$current_state" ]]; then
                valid_transitions+=("$state")
            fi
        done

        valid_transitions+=("clean")
    fi

    #remove duplicates
    valid_transitions=($(printf '%s\n' "${valid_transitions[@]}" | sort -u))

    echo "${valid_transitions[@]}"  # Output the array of valid transitions
}


handle_display_usage() {
    source <(read_config_tag CUSTOM_HELP) 
    
    echo "Usage: $0 <demo_name>"
    echo "Currently supported demos, given current state '$CURRENT_STATE':"
    
    # Get the valid transitions and iterate over them
    valid_transitions_array=($(get_valid_targets "$CURRENT_STATE"))
    for demo_name in "${valid_transitions_array[@]}"; do
        echo "- $demo_name"
    done
}


handle_detach() {
     if [ "$CURRENT_STATE" = "clean" ]; then
        echo "Current state is clean, nothing to detach!"
        exit 0
    fi

    create_backup
    
    DEPLOYMENTS_DIR="./deployments"
    mkdir -p $DEPLOYMENTS_DIR
    NEW_DIR="deployments/$(get_project_id)"
    echo "Moving current config to $NEW_DIR!"
    create_copy "$NEW_DIR"

    # Edit files in place
    # TODO: at least don't edit deploy.sh, move this to config
    sed -i 's/COMPONENTS_DIR=".\/components"/COMPONENTS_DIR="..\/..\/components"/' ${NEW_DIR}/deploy.sh
    
    # Remove files
    clean_up
    rm -rf ${TF_DIR} || true

    # TODO: REMOVE
    #mv ${TF_DIR} ${NEW_DIR} 
    #mv cymbal-air-start.sh ${NEW_DIR}/ || true
    #mv .current_state ${NEW_DIR}/ || true
    #cp deploy.sh ${NEW_DIR}/ || true
    #sed -i 's/TF_DIR=".\/tf"/TF_DIR="."/' ${NEW_DIR}/deploy.sh
    #cp store-vars.sh ${NEW_DIR}/ || true
    #sed -i 's/TF_DIR=".\/tf"/TF_DIR="."/' ${NEW_DIR}/store-vars.sh
    #cp config.sh ${NEW_DIR}/ || true
    #mv ${SNAPSHOTS_DIR} ${NEW_DIR}/ || true
    #mv ${BACKUPS_DIR} ${NEW_DIR}/ || true
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

        if [[ $IS_DRY_RUN == true ]]; then
            echo "Dry run mode: Skipping terraform destroy."
        else
            (cd "${TF_DIR}" && terraform destroy $([ "$TF_AUTO_APPROVE" == true ] && echo "-auto-approve")) 2> "$TF_LOG"
        fi
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
            #keep the backups to be on the safe side
            #rm -rf ${BACKUPS_DIR}
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


apply_tf_state() {
    # 6. Ask user to provide any tf variables which have no defaults
    #    this is so we can store them even if user transitions to clean state
    ./store-vars.sh
    
    # 7. Begin deployment - enter "dirty" state
    echo "dirty" > .current_state

    # 8. Deploy the demo using terraform
    if [[ $IS_DRY_RUN == true ]]; then
        echo "Dry run mode: Skipping terraform apply."
    else
        (cd "${TF_DIR}" && terraform init && terraform apply $([ "$TF_AUTO_APPROVE" == true ] && echo "-auto-approve"))
    fi
    if [ $? -ne 0 ]; then
        print_tf_error "apply"
        return 1
    fi

    # 9. Apply any custom state transitions or mark the desired state
    #    as the current state
    if [[ -n $(read_config_tag CUSTOM_STATE_TRANSITIONS) ]]; then
        source <(read_config_tag CUSTOM_STATE_TRANSITIONS)
    else
        echo $DEMO_NAME > .current_state
    fi
    return 0
}


handle_back() {
    # Get the snapshot number for the desired state
    snapshot_number=${PREVIOUS_STATES_DICT["$DEMO_NAME"]}

    if [[ -z $snapshot_number ]]; then
        echo "Error: No snapshot found for state '$DEMO_NAME'"
        exit 1
    fi

    local snapshot_dir="$SNAPSHOTS_DIR/$snapshot_number"

    if [[ ! -d "$snapshot_dir" ]]; then
        echo "Error: Snapshot directory not found."
        exit 1
    fi

    create_backup

    # Remove existing files from the TF directory
    rm -f ${TF_DIR}/*.{tf,tfvars}

    # Restore config from snapshot, but don't overwrite terraform state!
    cp -r "$snapshot_dir"/"${TF_DIR}"/*.{tf,tfvars} "${TF_DIR}"

    apply_tf_state
    if [[ $? -ne 0 ]]; then  # Check if apply_tf_state failed
        echo "Error: Failed to apply Terraform state. Restoring from backup..."

        # Restore from backup
        rm -rf "${TF_DIR}"/*  # Clean up the failed restoration
        # Restore all files, including hidden state files
        cp -r "$backup_dir"/"${TF_DIR}"/{.,}* "${TF_DIR}"

        apply_tf_state

        exit 1
    fi

    # Clean up snapshots older than or equal to the restored one
    latest_snapshot_number=$(get_latest_snapshot_dir)
    for ((i=snapshot_number; i<= $latest_snapshot_number; i++)); do
        rm -rf "$SNAPSHOTS_DIR/$i"
    done
}



########################################
# The main demo deployment logic is here
handle_deploy_demo() { 
    # 0. Init
    #    Source any auto magic string replacements
    source <(read_config_tag TF_STRING_REPLACEMENTS)

    # 1. Check if transition is valid
    # Since 2024_07_15, we don't check for valid transition if current state is clean
    TRANSITION="${CURRENT_STATE},${DEMO_NAME}"
    if [[ "$CURRENT_STATE" != "clean" ]] &&
       [[ -z "${VALID_TRANSITIONS[$TRANSITION]}" ]]; then
        echo "Error: Invalid transition from '$CURRENT_STATE' to '$DEMO_NAME'."
        exit 1
    fi

    # 1.5. If state=clean and we found find_targets_dependency, make recursive call
    # to deploy dependenci(es)
    dependency=$(find_targets_dependency "$DEMO_NAME")
    if [[ -n "$dependency" ]]; then
        echo "Deploying required dependency: $dependency"
        # Recursvie dependency deployment
        ./deploy.sh "$dependency"  
        if [[ $? -ne 0 ]]; then  # Check if the dependency deployment failed
            echo "Error: Failed to deploy dependency '$dependency'. Exiting." >&2
            exit 1
        fi
        #to make sure there are no state and other issues, we invoke deployment of
        #final demo again and exit
        ./deploy.sh "$DEMO_NAME"
        exit $?
    fi
    #if there is no dependency, we proceed as normal, deploying the target demo
    #if we found it, above code should recursivelly deploy all dependencies, so we can
    #continue normally

    # 2. Potentially switch the target demodeployment in place - 
    #    this is if we need some manual steps in between, see cymbal-air
    source <(read_config_tag SUBSTITUTE_TARGET_DEMO)

    # 3. Check if we are going back to a previous state
    if [[ -v PREVIOUS_STATES_DICT[$DEMO_NAME] ]]; then
        handle_back  # Call the handle_back function
        exit 0
    fi

    # 4 Store snapshot of the current state
    if [[ $CURRENT_STATE != "clean" ]]; then
        store_snapshot
    fi

    # 5. Prepare files to copy based on demo name
    if [[ -v DEMO_FILES[$DEMO_NAME] ]]; then
        # Copy the files associated with the selected demo
        read -ra FILES_TO_COPY <<< "${DEMO_FILES[$DEMO_NAME]}"
    else
        echo "Error: Invalid demo name."
        exit 1
    fi

    # 6. Copy files from the array (which includes path!) to a destination
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
                #If we ever want to do it with perl
                #perl -0777 -pi -e "s/$OLD_STRING/$NEW_STRING/gs" "${TF_DIR}/${file##*/}"
            done
        fi
    done
    
    # 7. Apply the changes
    apply_tf_state
    if [[ $? -ne 0 ]]; then
        exit 1
    fi

    # All done!
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

        # Any state with "backup" command: Backup the configuration
        *,"backup")
            create_backup
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

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    #Strict error handling breaks terraform destroy network issue loop, disabling for now
    #set -e  # Enable strict error handling
    main $1  #"$@"  # Call your main function with arguments
else
    # Script is being sourced
    # Make functions available for testing, but don't execute the main logic
    echo "Sourcing, nothing to do"
fi
