resource "null_resource" "create_alloydb_trial_cluster" {
    triggers = {
        cluster_name = var.alloydb_cluster_name
        region       = var.region
        password     = var.alloydb_password
        project_id   = google_project.demo-project.project_id
        network_id   = google_compute_network.demo_network.id
        test_mode    = var.test_mode
    }

    provisioner "local-exec" {
        command = templatefile("${path.module}/alloydb-base-create-trial-cluster.sh.tpl", 
                  self.triggers)
    }

    provisioner "local-exec" {
        # Check if cluster is fully initialized before proceeding
        when = create
        command = <<EOT
            bash -c 'while true; do 
                status=$(gcloud alloydb clusters describe ${var.alloydb_cluster_name} --region=${var.region} --project=${google_project.demo-project.project_id} --format="value(state)");  # Add the project flag here
                [[ $status = READY ]] && break || echo "Cluster not ready yet, waiting..."; 
                sleep 5;  
            done'
        EOT
    }

    provisioner "local-exec" {
        when    = destroy
        command = templatefile("${path.module}/alloydb-base-destroy-trial-cluster.sh.tpl", 
                  self.triggers
                  ) 
    }

    # Ensure this resource is created before other resources that depend on it
    depends_on = [ google_project_service.alloydb_services ]
}

data "external" "alloydb_trial_cluster_name" {
  program = [
    "bash",
    "-c",
    <<EOT
      cluster_name=$(gcloud alloydb clusters describe ${var.alloydb_cluster_name} \
        --region=${var.region} \
        --project=${google_project.demo-project.project_id} \
        --format='value(name)')
      
      echo '{"name": "'"$cluster_name"'"}'
    EOT
  ]
  query = {
    # Add the implicit dependency, see https://github.com/hashicorp/terraform/issues/22005
    deployment = null_resource.create_alloydb_trial_cluster.id 
  }
}