#!/bin/bash
gcloud alloydb clusters create "${cluster_name}" \
    %{ if ! test_mode } --subscription-type=TRIAL \
    %{ endif } --region="${region}" \
    --password="${password}" \
    --project="${project_id}" \
    --network="${network_id}"