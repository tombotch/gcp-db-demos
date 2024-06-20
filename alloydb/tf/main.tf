module "alloydb-base" {
  source              = "./modules/alloydb-base"
  gcp_project_id      = var.gcp_project_id
  region              = var.region
  alloydb_password    = var.alloydb_password
}