terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.6" 
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.region
}

# Enable Required APIs
resource "null_resource" "enable_service_usage_api" {
  provisioner "local-exec" {
    command = "gcloud services enable serviceusage.googleapis.com"
  }
}

locals {
  apis_to_enable = [
    "alloydb.googleapis.com",
    "compute.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "vpcaccess.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
    "iam.googleapis.com",
    "iap.googleapis.com"
  ]
}

resource "google_project_service" "project_services" {
  for_each           = toset(local.apis_to_enable)
  service            = each.key
  disable_on_destroy = false
  depends_on         = [null_resource.enable_service_usage_api]
}

# Network Resources
resource "google_compute_network" "alloydb_network" {
  name                    = "alloydb-network"
  auto_create_subnetworks = true 
  depends_on              = [google_project_service.project_services]
}

resource "google_compute_global_address" "psa_range" {
  name          = "psa-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 24
  network       = google_compute_network.alloydb_network.id # Or your custom network
}

resource "google_service_networking_connection" "private_service_access" {
  network                 = google_compute_network.alloydb_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa_range.name]
}

resource "google_compute_firewall" "allow_iap_ssh" {
  name          = "allow-iap-ssh"
  network       = google_compute_network.alloydb_network.id
  direction     = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
}

# Create a NAT gateway
resource "google_compute_router" "nat-router" {
  name    = "nat-router"
  region  = var.region
  network = google_compute_network.alloydb_network.name
}

resource "google_compute_router_nat" "nat-config" {
  name                               = "nat-config"
  router                             = google_compute_router.nat-router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}


# AlloyDB Cluster
resource "google_alloydb_cluster" "alloydb_cluster" {
  cluster_id = var.alloydb_cluster_name
  location   = var.region  
  
  network_config {
    network = google_compute_network.alloydb_network.id
  }

  initial_user {
    user     = "postgres"
    password = var.alloydb_password
  }
}

# AlloyDB Instance
resource "google_alloydb_instance" "primary_instance" {
  cluster     = google_alloydb_cluster.alloydb_cluster.name
  instance_id = var.alloydb_primary_name
  instance_type = "PRIMARY"
  machine_config {
    cpu_count = 2
  }
}

# Compute Engine VM
resource "google_compute_instance" "alloydb-client" {
  name         = "alloydb-client"
  machine_type = "e2-medium"
  zone         = "${var.region}-a"  

  boot_disk {
    initialize_params {
      image = "projects/debian-cloud/global/images/debian-12-bookworm-v20240617"
    }
  }

  network_interface {
    network = google_compute_network.alloydb_network.id
  }

  #service_account {
  #  email  = "${var.compute_service_account_name}@${var.gcp_project_id}.iam.gserviceaccount.com"
  #  scopes = ["cloud-platform"]
  #}

  shielded_instance_config {
    enable_integrity_monitoring = true
    enable_secure_boot          = true
    enable_vtpm                 = true
  }

}

resource "time_sleep" "wait_for_vm_boot" {
  create_duration = "120s"  # Adjust the wait time based on your VM boot time

  depends_on = [google_compute_instance.alloydb-client]
}

resource "null_resource" "install_postgresql_client" {
  depends_on = [time_sleep.wait_for_vm_boot]

  provisioner "local-exec" {
    command = "gcloud compute ssh alloydb-client --zone=europe-west3-a --tunnel-through-iap --command='sudo apt install postgresql-client -y'"
  }
}
