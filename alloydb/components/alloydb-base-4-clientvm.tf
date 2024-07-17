

#Add AlloyDB Viwer to the default compute SA
locals {
  default_compute_sa_roles = [
    "roles/alloydb.viewer",
    "roles/alloydb.client"
  ]
}

resource "google_project_iam_member" "default_compute_sa_alloydb_viewer" {
  for_each = toset(local.default_compute_sa_roles)
  project  = google_project.demo-project.project_id
  role     = each.key
  member   = "serviceAccount:${google_project.demo-project.number}-compute@developer.gserviceaccount.com"
  depends_on = [time_sleep.wait_for_database_clientvm_boot]
}

#Install and config Postgres Client
resource "null_resource" "install_postgresql_client" {
  depends_on = [google_project_iam_member.default_compute_sa_alloydb_viewer,
                google_alloydb_instance.primary_instance,
                time_sleep.wait_for_database_clientvm_boot] 

  provisioner "local-exec" {
    command = <<-EOT
      gcloud compute ssh ${var.clientvm-name} --zone=${var.region}-a --tunnel-through-iap \
      --project ${google_project.demo-project.project_id} --command='touch ~/.profile &&
      sudo apt install postgresql-client -y &&
      echo "export PROJECT_ID=\${google_project.demo-project.project_id}" >> ~/.profile &&
      echo "export REGION=\${var.region}" >> ~/.profile &&
      echo "export ADBCLUSTER=\${var.alloydb_cluster_name}" >> ~/.profile &&
      echo "export PGHOST=\$(gcloud alloydb instances describe ${var.alloydb_primary_name} --cluster=\$ADBCLUSTER --region=\$REGION --format=\"value(ipAddress)\")" >> ~/.profile &&
      echo "export PGUSER=postgres" >> ~/.profile'
    EOT
  }
}

resource "local_file" "alloydb_client_script" {
  filename = "../alloydb-client.sh"
  content = <<-EOT
#!/bin/bash 
gcloud compute ssh ${var.clientvm-name} --zone=${var.region}-a --tunnel-through-iap \
--project ${google_project.demo-project.project_id} 
  EOT
}