# Spanner Instance
resource "google_spanner_instance" "spanner_instance" {
  config       = "regional-${var.region}" # Adjust if needed
  display_name = "spanner-demo"
  project      = google_project.demo-project.project_id
  num_nodes    = 1 # Start with one node and scale as needed
  depends_on   = [ google_project_service.spanner_services]
}