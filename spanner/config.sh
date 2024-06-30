#This is a configuration file for deploy.sh for 
#demos for a specific database
echo "don't run this file directly :)"
exit 1

#BEGIN_DEFINITIONS
declare -gA VALID_TRANSITIONS=(
    ["clean,landing-zone"]="true"
    ["clean,spanner-base"]="true"
    ["landing-zone,spanner-base"]="true"
    ["spanner-base,landing-zone"]="true"
)


SPANNER_BASE_FILES=(
    "${LANDING_ZONE_FILES[@]}"
    "$COMPONENTS_DIR/spanner-base-1-apis.tf"
    "$COMPONENTS_DIR/spanner-base-2-instance.tf"
)

declare -gA DEMO_FILES=(
    ["landing-zone"]="${LANDING_ZONE_FILES[*]}" 
    ["spanner-base"]="${SPANNER_BASE_FILES[*]}" 
)
#END_DEFINITIONS


#Custom help is run before the Usage block is displayed
#if no parameters are passed to the script 
#BEGIN_CUSTOM_HELP
#END_CUSTOM_HELP


#BEGIN_TF_STRING_REPLACEMENTS
TF_REPLACEMENTS=(
  "demo-database-client" "spanner-client"
)
#END_TF_STRING_REPLACEMENTS


#these are applied AFTER terraform apply
#this makes it possible to inject custom state, e.g. for
#cymbal-air oauth setup
#BEGIN_CUSTOM_STATE_TRANSITIONS
#END_CUSTOM_STATE_TRANSITIONS