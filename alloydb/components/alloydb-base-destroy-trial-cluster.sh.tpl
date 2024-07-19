#!/bin/bash
gcloud beta alloydb clusters delete "${cluster_name}" \
    --region="${region}" \
    --project="${project_id}" \
    --quiet