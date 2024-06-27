#Provision Client VM
resource "google_compute_instance" "alloydb-client" {
  name         = "alloydb-client"
  machine_type = "e2-medium"
  zone         = "${var.region}-a" 
  project      = google_project.demo-project.project_id
 

  boot_disk {
    initialize_params {
      image = "projects/debian-cloud/global/images/debian-12-bookworm-v20240617"
    }
  }

  network_interface {
    network = google_compute_network.demo_network.id
  }

  service_account {
    email  = "${google_project.demo-project.number}-compute@developer.gserviceaccount.com"
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_integrity_monitoring = true
    enable_secure_boot          = true
    enable_vtpm                 = true
  }

  depends_on = [ google_alloydb_instance.primary_instance ]
}

resource "time_sleep" "wait_for_alloydb_clientvm_boot" {
  create_duration = "120s"  # Adjust the wait time based on your VM boot time

  depends_on = [google_compute_instance.alloydb-client]
}

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
  depends_on = [time_sleep.wait_for_alloydb_clientvm_boot]
}

#Install and config Postgres Client
resource "null_resource" "install_postgresql_client" {
  depends_on = [google_project_iam_member.default_compute_sa_alloydb_viewer]

  provisioner "local-exec" {
    command = <<-EOT
      gcloud compute ssh alloydb-client --zone=${var.region}-a --tunnel-through-iap \
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