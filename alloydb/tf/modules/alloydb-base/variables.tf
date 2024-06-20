variable "gcp_project_id" {
  type        = string
  description = "Your Google Cloud Project ID"
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
  default     = "alloydb-demo-primary"
}

variable "alloydb_password" {
  type        = string
  description = "AlloyDB Password"
}