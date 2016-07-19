//// Set GCP Provider info

provider "google" {
  project = "${var.project}"
  region = "${var.region}"
  credentials = "${file("/tmp/terraform-bosh.key.json")}"
}

/////////////////////////////////
//// Create Network Objects   ///
/////////////////////////////////

  //// Create GCP Virtual Network
  resource "google_compute_network" "pcf" {
    name       = "${var.resource-prefix}-vnet-pcf"
  }

  //// Create BOSH Static IP address
  //resource "google_compute_address" "bosh-director-ip" {
  //  name = "${var.resource-prefix}-bosh-director-ip"
  // }

  //// Create Subnet for the BOSH director
  resource "google_compute_subnetwork" "subnet-bosh" {
    name          = "${var.resource-prefix}-subnet-bosh-${var.region}"
    ip_cidr_range = "${var.bosh-subnet-cidr-range}"
    network       = "${google_compute_network.pcf.self_link}"
  }

  //// Create Subnet for the Concourse
  resource "google_compute_subnetwork" "subnet-cc" {
    name          = "${var.resource-prefix}-subnet-cc-${var.region}"
    ip_cidr_range = "${var.cc-subnet-cidr-range}"
    network       = "${google_compute_network.pcf.self_link}"
  }

  //// Create Subnet for the PCF
  resource "google_compute_subnetwork" "subnet-pcf" {
    name          = "${var.resource-prefix}-subnet-pcf-${var.region}"
    ip_cidr_range = "${var.pcf-subnet-cidr-range}"
    network       = "${google_compute_network.pcf.self_link}"
  }

  //// Create Firewall Rule allow-ssh
  resource "google_compute_firewall" "allow-ssh" {
    name    = "${var.resource-prefix}-allow-ssh"
    network = "${google_compute_network.pcf.name}"
    allow {
      protocol = "tcp"
      ports    = ["22"]
    }
    allow {
      protocol = "icmp"
    }
    target_tags = ["allow-ssh"]
    source_tags = ["allow-ssh"]
  }

  //// Create Firewall Rule allow-ssh-public
  resource "google_compute_firewall" "allow-ssh-public" {
    name    = "${var.resource-prefix}-allow-ssh-public"
    network = "${google_compute_network.pcf.name}"
    allow {
      protocol = "tcp"
      ports    = ["22"]
    }
    allow {
      protocol = "icmp"
    }
    source_ranges = ["0.0.0.0/0"]
    target_tags   = ["allow-ssh-public"]
  }

  //// Create Firewall Rule nat-traverse
  resource "google_compute_firewall" "nat-traverse" {
    name    = "${var.resource-prefix}-nat-traverse"
    network = "${google_compute_network.pcf.name}"

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

  //// Create Firewall Rule concourse
  resource "google_compute_firewall" "concourse" {
    name    = "${var.resource-prefix}-concourse"
    network = "${google_compute_network.pcf.name}"
    allow {
      protocol = "icmp"
    }
    allow {
      protocol = "tcp"
      ports    = ["80","443"]
    }
    target_tags = ["concourse-public"]
}


/////////////////////////////////////
//// Create BOSH bastion instance ///
/////////////////////////////////////

resource "google_compute_instance" "bosh-bastion" {
  name         = "${var.resource-prefix}-bosh-bastion"
  machine_type = "n1-standard-1"
  zone         = "${var.zone}"

  tags = ["nat-traverse", "allow-ssh", "allow-ssh-public"]

  disk {
    image = "ubuntu-1404-trusty-v20160610"
  }

  network_interface {
    subnetwork = "${google_compute_subnetwork.subnet-bosh.name}"
    access_config {
      // nat_ip = "${google_compute_address.bosh-director-ip.self_link}"
    }
  }

  service_account {
    scopes = ["cloud-platform"]
  }

  metadata {
    zone="${var.zone}"
    region="${var.region}"
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
gcloud config set compute/zone $zone
gcloud config set compute/region $region
mkdir -p /home/bosh
ssh-keygen -t rsa -f /home/bosh/.ssh/bosh -C bosh -N ''
sed '1s/^/bosh:/' /home/bosh/.ssh/bosh.pub > /home/bosh/.ssh/bosh.pub.gcp
gcloud compute project-info add-metadata --metadata-from-file sshKeys=/home/bosh/.ssh/bosh.pub.gcp
EOT

}

/////////////////////////////////
//// Create NAT instance      ///
/////////////////////////////////

resource "google_compute_instance" "nat-gateway" {
  name           = "${var.resource-prefix}-nat-gateway"
  machine_type   = "n1-standard-1"
  zone           = "${var.zone}"
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

  metadata_startup_script = <<EOT
  #!/bin/bash
  "sudo sh -c 'echo 1 > /proc/sys/net/ipv4/ip_forward'"
  "sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE"
  EOT
}

//// Create NAT Route

resource "google_compute_route" "no-pubip-route" {
  name        = "${var.resource-prefix}-no-pubip-route"
  dest_range  = "0.0.0.0/0"
  network     = "${google_compute_network.pcf.name}"
  next_hop_instance = "${google_compute_instance.nat-gateway.name}"
  next_hop_instance_zone = "${var.zone}"
  priority    = 100
  tags        = ["no-ip"]
}
