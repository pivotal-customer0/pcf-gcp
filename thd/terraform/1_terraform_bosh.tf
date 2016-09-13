variable "projectid" {
    type = "string"
    default = "REPLACE-WITH-YOUR-GOOGLE-PROJECT-ID"
}

variable "region" {
    type = "string"
    default = "us-central1"
}

variable "zone" {
    type = "string"
    default = "us-cental1-b"
}

variable "zone-2" {
    type = "string"
    default = "us-east1-c"
}

variable "cidr" {
    type = "string"
    default = "10.0.0.0/26"
}

variable "pivnet" {
    type = "string"
    default = "REPLACE WITH PIVNET ACCESS TOKEN"
}

variable "ert" {
    type = "string"
    default = "https://network.pivotal.io/api/v2/products/elastic-runtime/releases/2100/product_files/5630/download"
}

provider "google" {
    project = "${var.projectid}"
    region = "${var.region}"
}

// Ops Manager image
 resource "google_compute_image" "ops-manager-image" {
  name         = "ops-manager-image"
	raw_disk {
	  source = "https://storage.googleapis.com/ops-manager-ci/ops-manager-images/pivotal-ops-manager-20160902t190735-cac7a32.tar.gz"
	}
}

// Networks //

resource "google_compute_network" "cf" {
  name       = "cf-${var.region}"
}

// Subnet for the BOSH director
resource "google_compute_subnetwork" "bosh-subnet-1" {
  name          = "bosh-${var.region}"
  ip_cidr_range = "${var.cidr}"
  network       = "${google_compute_network.cf.self_link}"
}

// Firewall Rules //

// Allow SSH to jumpbox
resource "google_compute_firewall" "jumpbox-allow-ssh" {
  name    = "jumpbox-allow-ssh-${var.region}"
  network = "${google_compute_network.cf.name}"
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["151.140.0.0/16","165.130.0.0/16","207.11.0.0/17","50.207.27.182/32","96.83.24.238/32"]
  target_tags = ["jumpbox"]
}

// Allow access to Ops Manager
resource "google_compute_firewall" "opsman-allow-http-https" {
  name    = "opsman-allow-http-https-${var.region}"
  network = "${google_compute_network.cf.name}"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["151.140.0.0/16","165.130.0.0/16","207.11.0.0/17","50.207.27.182/32","96.83.24.238/32"]
  target_tags = ["opsman"]
}

// Allow SSH from jumpbox to Ops Manager
resource "google_compute_firewall" "opsman-allow-ssh" {
  name    = "cf-allow-ssh-${var.region}"
  network = "${google_compute_network.cf.name}"
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_tags = ["jumpbox"]
  target_tags = ["opsman", "nat"]
}


// Allow open access between internal VMs
resource "google_compute_firewall" "cf-allow-internal" {
  name    = "cf-allow-internal-${var.region}"
  network = "${google_compute_network.cf.name}"
  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }
//  source_tags = ["pcf-vms"]
// subnets are bosh and ers
  source_ranges = ["10.0.0.0/26", "10.0.16.0/20"]
}

// VMs //

// jumpbox
resource "google_compute_instance" "jumpbox" {
  name         = "jumpbox-${var.region}"
  machine_type = "n1-standard-2"
  zone         = "${var.zone}"

  tags = ["jumpbox"]

  disk {
    image = "ubuntu-1404-trusty-v20160809a"
    size = "50"
  }

  network_interface {
    subnetwork = "${google_compute_subnetwork.bosh-subnet-1.name}"
    access_config {
      // Ephemeral IP
    }
  }

  service_account {
    scopes = ["cloud-platform"]
  }
}


// Ops Manager VM
resource "google_compute_instance" "ops-manager-vm" {
  name         = "ops-manager-vm-${var.region}"
  machine_type = "n1-standard-2"
  zone         = "${var.zone-2}"

  tags = ["opsman"]

  disk {
    image = "${google_compute_image.ops-manager-image.name}"
    size = "50"
  }


  network_interface {
    subnetwork = "${google_compute_subnetwork.bosh-subnet-1.name}"
    access_config {
      // Ephemeral IP
    }
  }

  metadata_startup_script = <<EOT
#!/bin/bash
apt-get update -y
apt-get upgrade -y
apt-get install git
cd /home/ubuntu
mkdir repos
cd repos
git clone https://github.com/patrickcrocker/pcf-stuff.git
cd pcf-stuff
export PIVNET_TOKEN=${var.pivnet}
./pivnet-download.sh ${var.ert}
EOT

  service_account {
    scopes = ["cloud-platform"]
  }
}
