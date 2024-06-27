#!/bin/bash

OUTPUT_FILE="combined.tf"
TF_FILES=(*.tf)  # Collect all .tf files in the current directory

# Clear or create the output file
echo "" > "${OUTPUT_FILE}"

for file in "${TF_FILES[@]}"; do
  echo "### File: ${file} ###" >> "${OUTPUT_FILE}" # Add filename comment
  cat "${file}" >> "${OUTPUT_FILE}"                # Append file contents
  echo "" >> "${OUTPUT_FILE}"                     # Add a blank line for separation
done
