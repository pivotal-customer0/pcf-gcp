// Static IP address for NAT server 1
resource "google_compute_address" "nat-1" {
  name = "nat-1-${var.region}"
}

// Static IP address for NAT server 2
resource "google_compute_address" "nat-2" {
  name = "nat-2-${var.region}"
}

// Allow access from CloudFoundry to CloudFoundry
// via HTTP, HTTPs and WebSocket
resource "google_compute_firewall" "cf-allow-http-https-wss-from-within" {
  name    = "cf-allow-http-https-wss-from-within${var.region}"
  network = "${google_compute_network.cf.name}"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["${google_compute_address.nat-1.address}/32","${google_compute_address.nat-2.address}/32"]
  target_tags = ["pcf-lb-${var.region}"]
}

resource "google_compute_route" "nat-primary" {
  name        = "nat-primary-${var.region}"
  dest_range  = "0.0.0.0/0"
  network       = "${google_compute_network.cf.name}"
  next_hop_instance = "${google_compute_instance.nat-instance-private-with-nat-subnet-1-primary.name}"
  next_hop_instance_zone = "${var.zone}"
  priority    = 800
  tags = ["pcf-vms"]
}

resource "google_compute_route" "nat-secondary" {
  name        = "nat-secondary-${var.region}"
  dest_range  = "0.0.0.0/0"
  network       = "${google_compute_network.cf.name}"
  next_hop_instance = "${google_compute_instance.nat-instance-private-with-nat-subnet-1-secondary.name}"
  next_hop_instance_zone = "${var.zone-2}"
  priority    = 900
  tags = ["pcf-vms"]
}

// NAT server (primary)
resource "google_compute_instance" "nat-instance-private-with-nat-subnet-1-primary" {
  name         = "nat-instance-private-with-nat-${var.region}-primary"
  machine_type = "n1-standard-1"
  zone         = "${var.zone}"

  tags = ["nat", "ssh"]

  disk {
    image = "ubuntu-1404-trusty-v20160627"
  }

  network_interface {
    subnetwork = "${google_compute_subnetwork.bosh-subnet-1.name}"
    access_config {
      nat_ip = "${google_compute_address.nat-1.address}"
    }
  }

  can_ip_forward = true

  metadata_startup_script = <<EOT
#!/bin/bash
apt-get update -y
apt-get upgrade -y
sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
EOT
}

// NAT server (secondary)
resource "google_compute_instance" "nat-instance-private-with-nat-subnet-1-secondary" {
  name         = "nat-instance-private-with-nat-${var.region}-secondary"
  machine_type = "n1-standard-1"
  zone         = "${var.zone-2}"

  tags = ["nat", "ssh"]

  disk {
    image = "ubuntu-1404-trusty-v20160627"
  }

  network_interface {
  subnetwork = "${google_compute_subnetwork.bosh-subnet-1.name}"
    access_config {
      nat_ip = "${google_compute_address.nat-2.address}"
    }
  }

  can_ip_forward = true

  metadata_startup_script = <<EOT
#!/bin/bash
apt-get update -y
apt-get upgrade -y
sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
EOT
}
