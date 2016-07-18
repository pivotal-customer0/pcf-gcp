////
provider "google" {
  project = "${var.project}"
  region = "${var.region}"
  credentials = "${file("../deployment/terraform.key.json")}"
}

resource "google_compute_network" "cf" {
  name       = "${var.resource-prefix}cf"
}

//// Static IP address for forwarding rule
resource "google_compute_address" "bosh-director-ip" {
  name = "${var.resource-prefix}bosh-director-ip"
}

//// Subnet for the BOSH director
resource "google_compute_subnetwork" "bosh-subnet-1" {
  name          = "${var.resource-prefix}bosh-${var.region}"
  ip_cidr_range = "${var.cidr-piece}.0/24"
  network       = "${google_compute_network.cf.self_link}"
}

//// Allow SSH to BOSH bastion
resource "google_compute_firewall" "bosh-bastion" {
  name    = "bosh-bastion"
  network = "${google_compute_network.cf.name}"
  allow {
    protocol = "icmp"
  }
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  target_tags = ["bosh-bastion"]
}

//// Allow open access between internal MVs
resource "google_compute_firewall" "bosh-internal" {
  name    = "${var.resource-prefix}bosh-internal"
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
  target_tags = ["${var.resource-prefix}bosh-internal"]
  source_tags = ["${var.resource-prefix}bosh-internal"]
}

// Allow open access between internal MVs
resource "google_compute_firewall" "bosh-external" {
  name    = "${var.resource-prefix}bosh-external"
  network = "${google_compute_network.cf.name}"

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["22", "443", "4222", "6868", "25250", "25555", "25777", "8443"]
  }

  allow {
    protocol = "udp"
    ports    = ["53"]
  }
  target_tags = ["${var.resource-prefix}bosh-external"]
}

//////////////////////////
//// BOSH bastion host ///
//////////////////////////

resource "google_compute_instance" "bosh-bastion" {
  name         = "bosh-bastion"
  machine_type = "n1-standard-1"
  zone         = "${var.zone}"

  tags = ["bosh-bastion", "bosh-internal"]

  disk {
    image = "ubuntu-1404-trusty-v20160610"
  }

  network_interface {
    subnetwork = "${google_compute_subnetwork.bosh-subnet-1.name}"
    access_config {
        nat_ip
    }
  }

  metadata_startup_script = <<EOT
#!/bin/bash
apt-get update -y
apt-get upgrade -y
apt-get install -y build-essential zlibc zlib1g-dev ruby ruby-dev openssl libxslt-dev libxml2-dev libssl-dev libreadline6 libreadline6-dev libyaml-dev libsqlite3-dev sqlite3
gem install bosh_cli
curl -o /tmp/cf.tgz https://s3.amazonaws.com/go-cli/releases/v6.19.0/cf-cli_6.19.0_linux_x86-64.tgz
tar -zxvf /tmp/cf.tgz && mv cf /usr/bin/cf && chmod +x /usr/bin/cf
curl -o /usr/bin/bosh-init https://s3.amazonaws.com/bosh-init-artifacts/bosh-init-0.0.94-linux-amd64
chmod +x /usr/bin/bosh-init
EOT

  service_account {
    scopes = ["cloud-platform"]
  }
}
