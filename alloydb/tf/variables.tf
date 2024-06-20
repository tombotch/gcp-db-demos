variable "gcp_project_id" {
  type        = string
  description = "Your Google Cloud Project ID"
}

variable "region" {
  type        = string
  description = "Your Google Cloud Region"
  default     = "europe-west3"
}

variable "alloydb_password" {
  type        = string
  description = "AlloyDB Password"
}