# Install and confgiure Google provider
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "7.9.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
  zone    = var.gcp_zone
}

# Reserve a static external IP address
resource "google_compute_address" "static_ip" {
  name = "${var.instance_name}-ip"
}

# Define the Compute Engine VM
resource "google_compute_instance" "vm_instance" {
  name         = var.instance_name
  machine_type = "e2-medium"
  tags         = ["http-server", "https-server"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network = "default"
    access_config {
      nat_ip = google_compute_address.static_ip.address
    }
  }

  metadata_startup_script = file("${path.module}/startup-script.sh")

  service_account {
    email  = "default"
    scopes = ["cloud-platform"]
  }
}

# Define the firewall rule to allow HTTP and HTTPS traffic
resource "google_compute_firewall" "allow_http_https" {
  name    = "allow-http-https"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  target_tags = ["http-server", "https-server"]
  source_ranges = ["0.0.0.0/0"]
}