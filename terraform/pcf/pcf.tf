//// Declar vars

variable "project" {}
variable "region" {}
variable "resource-prefix" {}
variable "bosh-subnet-cidr-range" {}
variable "zone1" {}
variable "zone2" {}
variable "concourse-subnet-cidr-range" {}
variable "pcf-subnet-zone1-cidr-range" {}
variable "pcf-subnet-zone2-cidr-range" {}
variable "sys-domain" {}
variable "key-json" {}

//// Set GCP Provider info

provider "google" {
  project = "${var.project}"
  region = "${var.region}"
  # zone1 = "${var.zone1}"
  # zone2 = "${var.zone2}"
  credentials = "${var.key-json}"
}

/////////////////////////////////
//// Create Network Objects   ///
/////////////////////////////////

  //// Create GCP Virtual Network
  resource "google_compute_network" "vnet" {
    name       = "${var.resource-prefix}-vnet"
  }

  //// Create CloudFoundry Static IP address
  resource "google_compute_address" "cloudfoundry-public-ip" {
    name   = "${var.resource-prefix}-cloudfoundry-public-ip"
    region = "${var.region}"
  }

  //// Create Concourse Static IP address
  resource "google_compute_address" "concourse-public-ip" {
    name   = "${var.resource-prefix}-concourse-public-ip"
    region = "${var.region}"
  }

  //// Create Subnet for the BOSH director
  resource "google_compute_subnetwork" "subnet-bosh" {
    name          = "${var.resource-prefix}-subnet-bosh-${var.region}"
    ip_cidr_range = "${var.bosh-subnet-cidr-range}"
    network       = "${google_compute_network.vnet.self_link}"
  }

  //// Create Subnet for Concourse
  resource "google_compute_subnetwork" "subnet-concourse" {
    name          = "${var.resource-prefix}-subnet-concourse-${var.zone1}"
    ip_cidr_range = "${var.concourse-subnet-cidr-range}"
    network       = "${google_compute_network.vnet.self_link}"
  }

  //// Create Subnet for PCF - zone1
  resource "google_compute_subnetwork" "subnet-pcf-zone1" {
    name          = "${var.resource-prefix}-subnet-pcf-${var.zone1}"
    ip_cidr_range = "${var.pcf-subnet-zone1-cidr-range}"
    network       = "${google_compute_network.vnet.self_link}"
  }

    //// Create Subnet for PCF - zone2
  resource "google_compute_subnetwork" "subnet-pcf-zone2" {
    name          = "${var.resource-prefix}-subnet-pcf-${var.zone2}"
    ip_cidr_range = "${var.pcf-subnet-zone2-cidr-range}"
    network       = "${google_compute_network.vnet.self_link}"
  }

  //// Create Firewall Rule for allow-ssh
  resource "google_compute_firewall" "allow-ssh" {
    name    = "${var.resource-prefix}-allow-ssh"
    network = "${google_compute_network.vnet.name}"
    allow {
      protocol = "tcp"
      ports    = ["22"]
    }
    allow {
      protocol = "icmp"
    }
    source_ranges = ["0.0.0.0/0"]
    source_tags = ["allow-ssh"]
  }

  //// Create Firewall Rule for nat-traverse
  resource "google_compute_firewall" "nat-traverse" {
    name    = "${var.resource-prefix}-nat-traverse"
    network = "${google_compute_network.vnet.name}"

    allow {
      protocol = "icmp"
    }

    allow {
      protocol = "tcp"
    }

    allow {
      protocol = "udp"
    }
    target_tags = ["nat-traverse"]
    source_tags = ["nat-traverse"]
  }

  //// Create Firewall Rule for concourse
  resource "google_compute_firewall" "concourse" {
    name    = "${var.resource-prefix}-concourse"
    network = "${google_compute_network.vnet.name}"
    allow {
      protocol = "icmp"
    }
    allow {
      protocol = "tcp"
      ports    = ["8080","4443"]
    }
    source_ranges = ["0.0.0.0/0"]
    target_tags = ["concourse-public"]
}

  //// Create Firewall Rule for PCF
  resource "google_compute_firewall" "pcf-public" {
    name    = "${var.resource-prefix}-pcf-public"
    network = "${google_compute_network.vnet.name}"
    allow {
      protocol = "icmp"
    }
    allow {
      protocol = "tcp"
      ports    = ["80","443", "4443"]
    }
    source_ranges = ["0.0.0.0/0"]
    target_tags = ["pcf-public"]
}

  //// Create Firewall Rule for PCF - SSH
  resource "google_compute_firewall" "pcf-public-ssh" {
    name    = "${var.resource-prefix}-pcf-public-ssh"
    network = "${google_compute_network.vnet.name}"
    allow {
      protocol = "icmp"
    }
    allow {
      protocol = "tcp"
      ports    = ["2222"]
    }
    source_ranges = ["0.0.0.0/0"]
    target_tags = ["pcf-public-ssh"]
}

  //// Create HTTP Health Check Rule for PCF
  resource "google_compute_http_health_check" "pcf-public" {
  name         = "${var.resource-prefix}-pcf-public"
  request_path = "/v2/info"
  host         = "api.${var.sys-domain}"
  port         = 80

  healthy_threshold   = 10
  unhealthy_threshold = 2
  timeout_sec         = 5
  check_interval_sec  = 30
}

  //// Create HTTP Health Check Rule for Concourse
  resource "google_compute_http_health_check" "concourse-public" {
  name         = "${var.resource-prefix}-concourse-public"
  request_path = "/"
  host         = ""
  port         = 8080

  healthy_threshold   = 10
  unhealthy_threshold = 2
  timeout_sec         = 5
  check_interval_sec  = 30
}

  //// Create Target Pool for PCF
  resource "google_compute_target_pool" "pcf-public" {
  name          = "${var.resource-prefix}-pcf-public"
  health_checks = [
    "${google_compute_http_health_check.pcf-public.name}",
  ]
}

  //// Create Target Pool for PCF - SSH
  resource "google_compute_target_pool" "pcf-public-ssh" {
  name          = "${var.resource-prefix}-pcf-public-ssh"
}

  //// Create Target Pool for Concourse
  resource "google_compute_target_pool" "concourse-public" {
  name          = "${var.resource-prefix}-concourse-public"
  health_checks = [
    "${google_compute_http_health_check.concourse-public.name}",
  ]
}

  //// Create Forwarding for PCF - http
  resource "google_compute_forwarding_rule" "pcf-http" {
  name       = "${var.resource-prefix}-pcf-http"
  target     = "${google_compute_target_pool.pcf-public.self_link}"
  ip_address = "${google_compute_address.cloudfoundry-public-ip.address}"
  port_range = "80"
}

  //// Create Forwarding for PCF - https
  resource "google_compute_forwarding_rule" "pcf-https" {
  name       = "${var.resource-prefix}-pcf-https"
  target     = "${google_compute_target_pool.pcf-public.self_link}"
  ip_address = "${google_compute_address.cloudfoundry-public-ip.address}"
  port_range = "443"
}

  //// Create Forwarding for PCF - ssh
  resource "google_compute_forwarding_rule" "pcf-ssh" {
  name       = "${var.resource-prefix}-pcf-ssh"
  target     = "${google_compute_target_pool.pcf-public-ssh.self_link}"
  ip_address = "${google_compute_address.cloudfoundry-public-ip.address}"
  port_range = "2222"
}

  //// Create Forwarding for PCF - wss
  resource "google_compute_forwarding_rule" "pcf-wss" {
  name       = "${var.resource-prefix}-pcf-wss"
  target     = "${google_compute_target_pool.pcf-public.self_link}"
  ip_address = "${google_compute_address.cloudfoundry-public-ip.address}"
  port_range = "4443"
}

  //// Create Forwarding for Concourse - http
  resource "google_compute_forwarding_rule" "concourse-http" {
  name       = "${var.resource-prefix}-concourse-http"
  target     = "${google_compute_target_pool.concourse-public.self_link}"
  ip_address = "${google_compute_address.concourse-public-ip.address}"
  port_range = "8080"
}

  //// Create Forwarding for Concourse - https
  resource "google_compute_forwarding_rule" "concourse-https" {
  name       = "${var.resource-prefix}-concourse-https"
  target     = "${google_compute_target_pool.concourse-public.self_link}"
  ip_address = "${google_compute_address.concourse-public-ip.address}"
  port_range = "4443"
}

/////////////////////////////////////
//// Create BOSH bastion instance ///
/////////////////////////////////////

resource "google_compute_instance" "bosh-bastion" {
  name         = "${var.resource-prefix}-bosh-bastion"
  machine_type = "n1-standard-1"
  zone         = "${var.zone1}"

  tags = ["nat-traverse", "allow-ssh"]

  disk {
    image = "ubuntu-1404-trusty-v20160610"
  }

  network_interface {
    subnetwork = "${google_compute_subnetwork.subnet-bosh.name}"
    access_config {
      // Ephemeral
    }
  }

  service_account {
    scopes = ["cloud-platform"]
  }

  metadata {
    zone="${var.zone1}"
    region="${var.region}"
  }

  metadata_startup_script = <<EOF
#! /bin/bash
adduser --disabled-password --gecos "" bosh
apt-get update -y
apt-get upgrade -y
apt-get install -y build-essential zlibc zlib1g-dev ruby ruby-dev openssl libxslt-dev libxml2-dev libssl-dev libreadline6 libreadline6-dev libyaml-dev libsqlite3-dev sqlite3
curl -o /tmp/cf.tgz https://s3.amazonaws.com/go-cli/releases/v6.19.0/cf-cli_6.19.0_linux_x86-64.tgz
tar -zxvf /tmp/cf.tgz && mv cf /usr/bin/cf && chmod +x /usr/bin/cf
curl -o /usr/bin/bosh-init https://s3.amazonaws.com/bosh-init-artifacts/bosh-init-0.0.94-linux-amd64
chmod +x /usr/bin/bosh-init
gcloud config set compute/zone $zone
gcloud config set compute/region $region
mkdir -p /home/bosh/.ssh
ssh-keygen -t rsa -f /home/bosh/.ssh/bosh -C bosh -N ''
sed '1s/^/bosh:/' /home/bosh/.ssh/bosh.pub > /home/bosh/.ssh/bosh.pub.gcp
chown -R bosh:bosh /home/bosh/.ssh
gcloud compute project-info add-metadata --metadata-from-file sshKeys=/home/bosh/.ssh/bosh.pub.gcp
gem install bosh_cli
EOF

}

/////////////////////////////////
//// Create NAT instance      ///
/////////////////////////////////

resource "google_compute_instance" "nat-gateway" {
  name           = "${var.resource-prefix}-nat-gateway"
  machine_type   = "n1-standard-1"
  zone           = "${var.zone1}"
  can_ip_forward = true
  tags = ["nat-traverse", "allow-ssh"]

  disk {
    image = "ubuntu-1404-trusty-v20160610"
  }

  network_interface {
    subnetwork = "${google_compute_subnetwork.subnet-bosh.name}"
    access_config {
      // Ephemeral
    }
  }

  metadata_startup_script = <<EOF
#! /bin/bash
sudo sh -c 'echo 1 > /proc/sys/net/ipv4/ip_forward'
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
EOF

}

//// Create NAT Route

resource "google_compute_route" "no-pubip-route" {
  name        = "${var.resource-prefix}-no-pubip-route"
  dest_range  = "0.0.0.0/0"
  network     = "${google_compute_network.vnet.name}"
  next_hop_instance = "${google_compute_instance.nat-gateway.name}"
  next_hop_instance_zone = "${var.zone1}"
  priority    = 800
  tags        = ["no-ip"]
}

output "CloudFoundry IP Address" {
    value = "${google_compute_address.cloudfoundry-public-ip.address}"
}

output "Concourse IP Address" {
    value = "${google_compute_address.concourse-public-ip.address}"
}

output "Zone 1 - Concourse Subnet" {
    value = "${var.concourse-subnet-cidr-range}"
}

output "Zone 1 - CloudFoundry Subnet" {
    value = "${var.pcf-subnet-zone1-cidr-range}"
}

output "Zone 2 - CloudFoundry Subnet" {
    value = "${var.pcf-subnet-zone2-cidr-range}"
}
