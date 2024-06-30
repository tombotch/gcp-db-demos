resource "google_spanner_database" "cymbal-air-database" {
  instance            = google_spanner_instance.demo_instance.name
  name                = "assistantdemo"
  deletion_protection = false
  project             = google_project.demo-project.project_id
}