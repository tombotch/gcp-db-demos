variable "demo_project_id" {
  type        = string
  description = "New Cloud Project ID for this demo. Choose a unique ID (letters, numbers, hyphens)"
}

variable "billing_account_id" {
  type        = string
  description = "Billing account id associated with this project"
}

variable "region" {
  type        = string
  description = "Your Google Cloud Region"
  default     = "europe-west3"
}

variable "alloydb_cluster_name" {
  type        = string
  description = "AlloyDB Cluster Name"
  default     = "alloydb-demo-cluster"
}

variable "alloydb_primary_name" {
  type        = string
  description = "AlloyDB Primary Name"
  default     = "alloydb-demo-cluster-primary"
}

variable "alloydb_password" {
  type        = string
  description = "AlloyDB Password"
}