#!/bin/bash

TF_DIR="./tf"
COMPONENTS_DIR="./components"
CORE_COMPONENTS_DIR="../$COMPONENTS_DIR"
DEMO_NAME="$1"
CONFIG_FILE="config.sh"

mkdir -p $TF_DIR

# Check if the current state exists
if [[ ! -f ".current_state" ]]; then
    echo "clean" > .current_state
fi

CURRENT_STATE=$(cat ".current_state")

LANDING_ZONE_FILES=(
    "$CORE_COMPONENTS_DIR/00-landing-zone.tf"
    "$CORE_COMPONENTS_DIR/01-landing-zone-network.tf"
    "$CORE_COMPONENTS_DIR/02-landing-zone-apis.tf"
    "$CORE_COMPONENTS_DIR/09-landing-zone-vars.tf"
)

#Source definitions from config
source <(awk '/#BEGIN_DEFINITIONS/,/#END_DEFINITIONS/' $CONFIG_FILE) 

clean_up() {
    rm -f ${TF_DIR}/*.tf
    rm -f ${TF_DIR}/terraform.tfstate*
    rm -f ${TF_DIR}/.terraform.*
    rm -rf ${TF_DIR}/.terraform
    rm -f cymbal-air-start.sh
}   

if [[ $DEMO_NAME == "detach" ]]; then
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
fi


if [[ $CURRENT_STATE == "dirty" ]]; then
    echo "!!!Current state is dirty!!!"
    echo "This means that something went wrong during terraform provisioning."
    echo "You can try to manually fix things by going into tf folder"
    echo "But probably best to destroy evertyhing and/or delete the project"
    echo "And start from scratch"
    exit 1
fi

if [[ $# -eq 0 ]]; then
    source <(awk '/#BEGIN_CUSTOM_HELP/,/#END_CUSTOM_HELP/' $CONFIG_FILE) 
    
    echo "Usage: $0 <demo_name>"
    echo "Currently supported demos, given current state '$CURRENT_STATE':"
    for transition in "${!VALID_TRANSITIONS[@]}"; do
        # Check if the transition starts from the current state
        # and that target is not test-min
        if [[ "${transition%,*}" == "$CURRENT_STATE" ]] && [[ "${transition#*,}" != "test-min" ]]; then 
            echo "- ${transition#*,}" # Print the target demo of the transition
        fi
    done
    exit 1
fi

# Check if transition is valid
TRANSITION="${CURRENT_STATE},${DEMO_NAME}"
if [[ -z "${VALID_TRANSITIONS[$TRANSITION]}" ]]; then
    echo "Error: Invalid transition from '$CURRENT_STATE' to '$DEMO_NAME'."
    exit 1
fi


if [[ $DEMO_NAME == "cymbal-air" ]] &&
   [[ $CURRENT_STATE == "cymbal-air-base" ]]; then
    DEMO_NAME="cymbal-air-oauth"
fi


#Prepare files to copy based on demo name
if [[ -v DEMO_FILES[$DEMO_NAME] ]]; then
    # Copy the files associated with the selected demo
    read -ra FILES_TO_COPY <<< "${DEMO_FILES[$DEMO_NAME]}"
elif [[ $DEMO_NAME == "clean" ]]; then
    # File names to copy
    FILES_TO_COPY=(
    )
else
    echo "Error: Invalid demo name."
    exit 1
fi

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

if [[ $DEMO_NAME != "clean" ]]; then
    # Remove existing files from the TF directory
    rm -f ${TF_DIR}/*.tf

    # Copy files from the array (which includes path!) to a destination
    # directory and file name excluding path (the ${file##*/} part)
    for file in "${FILES_TO_COPY[@]}"; do
        cp "${file}" "${TF_DIR}/${file##*/}"
    done
    
    #any new wars to apply?
    ./store-vars.sh
    
    echo "dirty" > .current_state

    (cd "${TF_DIR}" && terraform init && terraform apply)
    # Handle tf failures
    if [ $? -ne 0 ]; then
        print_tf_error "apply"
        exit 1
    fi

    #Source any custom state transitions
    source <(awk '/#BEGIN_CUSTOM_STATE_TRANSITIONS/,/#END_CUSTOM_STATE_TRANSITIONS/' $CONFIG_FILE) 
    
else
    (cd "${TF_DIR}" && terraform destroy)
    #Handle tf failures
    if [ $? -ne 0 ]; then
        print_tf_error "destroy"
        exit 1
    fi
    #Clean up
    clean_up
    echo "clean" > .current_state
fi    