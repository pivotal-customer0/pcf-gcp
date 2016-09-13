variable "projectid" {
    type = "string"
}

variable "region" {
    type = "string"
    default = "us-east1"
}

variable "zone-1" {
    type = "string"
    default = "us-east1-c"
}

variable "run-id" {
    type = "string"
    default = "1"
}

variable "test-num-instances" {
    type = "string"
    default = "1"
}

provider "google" {
    project = "${var.projectid}"
    region = "${var.region}"
}

resource "google_compute_network" "net" {
  name       = "net"
}

// Private subnet with NAT
resource "google_compute_subnetwork" "private-with-nat-subnet-1" {
  name          = "private-with-nat-${var.region}"
  ip_cidr_range = "10.240.0.0/24"
  network       = "${google_compute_network.net.self_link}"
}

resource "google_compute_route" "nat-primary" {
  name        = "nat-primary"
  dest_range  = "0.0.0.0/0"
  network       = "${google_compute_network.net.name}"
  next_hop_instance = "${google_compute_instance.nat-instance-private-with-nat-subnet-1-primary.name}"
  next_hop_instance_zone = "${var.zone-1}"
  priority    = 800
  tags = ["no-ip"]
}

resource "google_compute_route" "nat-secondary" {
  name        = "nat-secondary"
  dest_range  = "0.0.0.0/0"
  network       = "${google_compute_network.net.name}"
  next_hop_instance = "${google_compute_instance.nat-instance-private-with-nat-subnet-1-secondary.name}"
  next_hop_instance_zone = "${var.zone-1}"
  priority    = 800
  tags = ["no-ip"]
}

// Allow SSH 
resource "google_compute_firewall" "ssh" {
  name    = "bastion-ssh"
  network = "${google_compute_network.net.name}"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags = ["ssh"]
}

// Allow all traffic within subnet
resource "google_compute_firewall" "intra-subnet-open" {
  name    = "intra-subnet-open"
  network = "${google_compute_network.net.name}"

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["1-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["1-65535"]
  }

  source_ranges = ["10.240.0.0/24"]
}

// NAT server (primary)
resource "google_compute_instance" "nat-instance-private-with-nat-subnet-1-primary" {
  name         = "nat-instance-private-with-nat-${var.region}-primary"
  machine_type = "n1-standard-1"
  zone         = "${var.zone-1}"

  tags = ["nat", "ssh"]

  disk {
    image = "ubuntu-1404-trusty-v20160627"
  }

  network_interface {
    subnetwork = "${google_compute_subnetwork.private-with-nat-subnet-1.name}"
    access_config {
      // Ephemeral IP
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
  zone         = "${var.zone-1}"

  tags = ["nat", "ssh"]

  disk {
    image = "ubuntu-1404-trusty-v20160627"
  }

  network_interface {
    subnetwork = "${google_compute_subnetwork.private-with-nat-subnet-1.name}"
    access_config {
      // Ephemeral IP
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

// Bastion host
resource "google_compute_instance" "bastion-server" {
  name         = "bastion-server"
  machine_type = "n1-standard-1"
  zone         = "${var.zone-1}"

  tags = ["ssh"]

  disk {
    image = "ubuntu-1404-trusty-v20160627"
  }

  network_interface {
    subnetwork = "${google_compute_subnetwork.private-with-nat-subnet-1.name}"
    access_config {
      // Ephemeral IP
    }
  }
}

resource "google_compute_instance_template" "no-ip-client" {
  name         = "no-ip-client-${var.region}-1"
  machine_type = "n1-standard-4"

  tags = ["no-ip"]

  disk {
    source_image = "ubuntu-1404-trusty-v20160627"
    auto_delete = true
    boot = true
  }

  network_interface {
    subnetwork = "${google_compute_subnetwork.private-with-nat-subnet-1.name}"
  }

  service_account {
    scopes = [
              "https://www.googleapis.com/auth/logging.write",
              "https://www.googleapis.com/auth/monitoring.write",
              "https://www.googleapis.com/auth/servicecontrol",
              "https://www.googleapis.com/auth/service.management.readonly",
              "https://www.googleapis.com/auth/devstorage.full_control"
            ]
  }

  metadata {
    run-id = "${var.run-id}"
    startup-script = <<EOT
#!/bin/bash
runid=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/run-id)
instance=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/id)
curl -s -o /dev/null -w 'num_connects:\t%{num_connects}\nsize_download:\t%{size_download}\nspeed_download:\t%{speed_download}\ntime_connect:\t%{time_connect}\ntime_total:\t%{time_total}\n' https://storage.googleapis.com/nat-perf-test/15g > /tmp/$instance.txt
gsutil cp /tmp/$instance.txt gs://nat-perf-test/$runid/$instance.txt
EOT
  }
}

resource "google_compute_instance_group_manager" "no-ip-clients" {
  name               = "no-ip-clients"

  target_size        = "${var.test-num-instances}"
  base_instance_name = "no-ip-client"
  instance_template  = "${google_compute_instance_template.no-ip-client.self_link}"
  update_strategy    = "NONE"
  zone               = "${var.zone-1}"

}
