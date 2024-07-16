#there were issues with provisioning primary too soon
resource "time_sleep" "wait_for_network" {
  create_duration = "30s"

  depends_on = [google_service_networking_connection.private_service_access]
}

# AlloyDB Instance
resource "google_alloydb_instance" "primary_instance" {
  cluster           = sed_alloydb_cluster_name
  instance_id       = var.alloydb_primary_name
  instance_type     = "PRIMARY"
  availability_type = "ZONAL"
  machine_config {
    cpu_count = 2
  }
  depends_on = [alloydb_instance_depends_on]
}