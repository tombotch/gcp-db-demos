terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.6" 
    }
  }
}

provider "google" {
  region  = var.region
}

#enable cloud billing api on the project running tf from
resource "null_resource" "enable_cloud_billing_api" {
  provisioner "local-exec" {
    command = "gcloud services enable cloudbilling.googleapis.com"
  }
}

#Create Project
resource "random_id" "unique_project_suffix" {
  byte_length = 3 
}

resource "google_project" "demo-project" {
  name       = "${var.demo_project_id}-${random_id.unique_project_suffix.hex}"
  project_id = "${var.demo_project_id}-${random_id.unique_project_suffix.hex}"

  billing_account = var.billing_account_id
  depends_on = [null_resource.enable_cloud_billing_api ]
}

output "project_id" {
  value = google_project.demo-project.project_id
}