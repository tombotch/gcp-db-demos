# AlloyDB Cluster
resource "google_alloydb_cluster" "alloydb_cluster" {
  cluster_id = var.alloydb_cluster_name
  location   = var.region  
  project    = google_project.demo-project.project_id

  network_config {
    network = google_compute_network.demo_network.id
  }

  initial_user {
    user     = "postgres"
    password = var.alloydb_password
  }

  depends_on = [ google_project_service.alloydb_services ]
}