#!/bin/bash

TF_DIR="./tf"
COMPONENTS_DIR="./components"
DEMO_NAME="$1"
mkdir -p $TF_DIR

# Check if the current state exists
if [[ ! -f ".current_state" ]]; then
    echo "clean" > .current_state
fi

CURRENT_STATE=$(cat ".current_state")

declare -A VALID_TRANSITIONS=(
    ["clean,test-min"]="true"
    ["clean,alloydb-base"]="true"
    ["clean,cymbal-air"]=true
    ["test-min,clean"]="true"
    ["alloydb-base,clean"]="true"
    ["alloydb-base,cymbal-air"]="true"
    ["cymbal-air,clean"]="true"
    ["cymbal-air-base,cymbal-air"]="true"
    ["cymbal-air-base,clean"]="true"
)

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

echo_cymbal_air_oauth_instructions() {
  echo ""
  echo "!!!PLEASE READ THIS BEFORE CONTINUING!!!"
  echo -e "\a"
  echo "Cymbal Air Demo deployment requires a manual step!"
  echo "Follow the steps described in Prepare Client chapter"
  echo "for setting up Client Id (NOT the OAuth consent - that is done!)"
  echo "https://codelabs.developers.google.com/codelabs/genai-db-retrieval-app#prepare-client-id"
  echo "Do NOT follow the steps of the following  chapter 'Run Assistant Application'!"
  echo "Once you create the client, copy client id and run"
  echo "'./deploy.sh cymbal-air' again to continue.'"
}

if [[ $# -eq 0 ]]; then
    if [[ $CURRENT_STATE == "cymbal-air-base" ]]; then
        echo_cymbal_air_oauth_instructions
        echo ""
    fi
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

TEST_MINIMAL_FILES=(
    "alloydb-base-0-project.tf"
    "alloydb-base-vars.tf"
)

ALLOYDB_BASE_FILES=(
    "alloydb-base-0-project.tf"
    "alloydb-base-1-infrastructure.tf"
    "alloydb-base-2-cluster.tf"
    "alloydb-base-3-instance.tf"
    "alloydb-base-4-clientvm.tf"
    "alloydb-base-vars.tf"
)

CYMBAL_AIR_BASE_FILES=(
    "${ALLOYDB_BASE_FILES[@]}"
    "cymbal-air-demo-1.tf"
    "cymbal-air-demo-1-vars.tf"
)
# Check if demo name is valid
if [[ $DEMO_NAME == "test-min" ]]; then
    # File names to copy
    FILES_TO_COPY=("${TEST_MINIMAL_FILES[@]}")
elif [[ $DEMO_NAME == "alloydb-base" ]]; then
    # File names to copy
    FILES_TO_COPY=("${ALLOYDB_BASE_FILES[@]}")
elif [[ $DEMO_NAME == "cymbal-air" ]]; then
    # File names to copy
    FILES_TO_COPY=(
        "${CYMBAL_AIR_BASE_FILES[@]}"
    )
elif [[ $DEMO_NAME == "cymbal-air-oauth" ]]; then
     FILES_TO_COPY=(
        "${CYMBAL_AIR_BASE_FILES[@]}"
        "cymbal-air-demo-2-oauth.tf"
        "cymbal-air-demo-2-oauth-vars.tf"
    )
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

    # Copy files from the components directory
    for file in "${FILES_TO_COPY[@]}"; do
        cp "${COMPONENTS_DIR}/${file}" "${TF_DIR}/${file}"
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

    # Handle transition
    if [[ $DEMO_NAME == "cymbal-air" ]] &&
       [[ $CURRENT_STATE != "cymbal-air-base" ]] ; then
        echo "cymbal-air-base" > .current_state
        echo_cymbal_air_oauth_instructions
    elif [[ $DEMO_NAME == "cymbal-air-oauth" ]]; then
        echo "cymbal-air" > .current_state
        echo "You can now run ./cymbal-air-start.sh and point your browser to"
        echo "localhost:8081 to start the demo."
        echo ""
        echo "IMPORTANT: IT TAKES A WHILE FOR ALL THE CHANGES TO APPLY"
        echo ""
        echo "We recommend to wait ~30 minutes before starting the demo"
    else
        echo $DEMO_NAME > .current_state
    fi
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