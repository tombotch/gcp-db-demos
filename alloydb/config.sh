#This is a configuration file for deploy.sh for 
#demos for a specific database
echo "don't run this file directly :)"
exit 1

#BEGIN_DEFINITIONS
declare -gA VALID_TRANSITIONS=(
    ["clean,test-min"]="true"
    ["clean,alloydb-base"]="true"
    ["clean,cymbal-air"]=true
    ["alloydb-base,cymbal-air"]="true"
    ["cymbal-air-base,alloydb-base"]="true"
    ["cymbal-air-base,cymbal-air"]="true"
    ["cymbal-air,alloydb-base"]="true"
)

TEST_MINIMAL_FILES=(
    "$CORE_COMPONENTS_DIR/00-landing-zone.tf"
    "$CORE_COMPONENTS_DIR/09-landing-zone-vars.tf"
)

ALLOYDB_BASE_FILES=(
    "${LANDING_ZONE_FILES[@]}"
    "$COMPONENTS_DIR/alloydb-base-1-apis.tf"
    "$COMPONENTS_DIR/alloydb-base-2-cluster.tf"
    "$COMPONENTS_DIR/alloydb-base-3-instance.tf"
    "$COMPONENTS_DIR/alloydb-base-4-clientvm.tf"
    "$COMPONENTS_DIR/alloydb-base-vars.tf"
)

CYMBAL_AIR_BASE_FILES=(
    "${ALLOYDB_BASE_FILES[@]}"
    "$COMPONENTS_DIR/cymbal-air-demo-1.tf"
    "$COMPONENTS_DIR/cymbal-air-demo-1-vars.tf"
)

CYMBAL_AIR_FILES=(
    "${CYMBAL_AIR_BASE_FILES[@]}"
    "$COMPONENTS_DIR/cymbal-air-demo-2-oauth.tf"
    "$COMPONENTS_DIR/cymbal-air-demo-2-oauth-vars.tf"
)


declare -gA DEMO_FILES=(
  ["test-min"]="${TEST_MINIMAL_FILES[*]}"
  ["alloydb-base"]="${ALLOYDB_BASE_FILES[*]}" 
  ["cymbal-air"]="${CYMBAL_AIR_BASE_FILES[*]}"
  ["cymbal-air-oauth"]="${CYMBAL_AIR_FILES[*]}"
)


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
#END_DEFINITIONS


#Custom help is run before the Usage block is displayed
#if no parameters are passed to the script 
#BEGIN_CUSTOM_HELP
    if [[ $CURRENT_STATE == "cymbal-air-base" ]]; then
            echo_cymbal_air_oauth_instructions
            echo ""
    fi
#END_CUSTOM_HELP


#BEGIN_TF_STRING_REPLACEMENTS
TF_REPLACEMENTS=(
  "demo-database-client" "alloydb-client"
)
#END_TF_STRING_REPLACEMENTS

#BEGIN_SUBSTITUTE_TARGET_DEMO
if [[ $DEMO_NAME == "cymbal-air" ]] &&
   [[ $CURRENT_STATE == "cymbal-air-base" ]]; then
    DEMO_NAME="cymbal-air-oauth"
fi
#END_SUBSTITUTE_TARGET_DEMO


#these are applied AFTER terraform apply
#this makes it possible to inject custom state, e.g. for
#cymbal-air oauth setup
#BEGIN_CUSTOM_STATE_TRANSITIONS
    echo "Custom transitions"
    if [[ $DEMO_NAME == "cymbal-air" ]] &&
       [[ $CURRENT_STATE != "cymbal-air-base" ]] ; then
        echo "cymbal-air-base" > .current_state
        echo_cymbal_air_oauth_instructions
    elif [[ $DEMO_NAME == "cymbal-air-oauth" ]]; then
        echo "cymbal-air" > .current_state
        echo "You can now run ./cymbal-air-start.sh and point your browser to"
        echo "localhost:8081 to start the demo."
        echo ""
    else
        echo $DEMO_NAME > .current_state
    fi
#END_CUSTOM_STATE_TRANSITIONS