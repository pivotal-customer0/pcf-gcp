// Subnet for the public Cloud Foundry components
resource "google_compute_subnetwork" "cf-public-subnet-1" {
  name          = "${var.resource-prefix}cf-public-${var.region}"
  ip_cidr_range = "10.200.0.0/16"
  network       = "${google_compute_network.cf.self_link}"
}

// Subnet for the private Cloud Foundry components
resource "google_compute_subnetwork" "cf-private-subnet-1" {
  name          = "${var.resource-prefix}cf-private-${var.region}"
  ip_cidr_range = "192.168.0.0/16"
  network       = "${google_compute_network.cf.self_link}"
}

// Allow access to CloudFoundry router
resource "google_compute_firewall" "cf-public" {
  name    = "${var.resource-prefix}cf-public"
  network = "${google_compute_network.cf.name}"

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "4443"]
  }

  target_tags = ["${var.resource-prefix}cf-public"]
}

// Allow access to SSH
resource "google_compute_firewall" "cf-ssh" {
  name    = "${var.resource-prefix}cf-ssh"
  network = "${google_compute_network.cf.name}"

  allow {
    protocol = "tcp"
    ports    = ["2222"]
  }

  target_tags = ["${var.resource-prefix}cf-ssh"]
}

// Allow open access to between internal VMs
resource "google_compute_firewall" "cf-internal" {
  name    = "${var.resource-prefix}cf-internal"
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

  target_tags = ["${var.resource-prefix}cf-internal"]
  source_tags = ["${var.resource-prefix}cf-internal", "${var.resource-prefix}bosh-internal"]
}

// Static IP address for forwarding rule
resource "google_compute_address" "cf" {
  name = "${var.resource-prefix}cf"
}

// Static IP address for forwarding rule
resource "google_compute_address" "cf-ssh" {
  name = "${var.resource-prefix}cf-ssh"
}

// Health check
resource "google_compute_http_health_check" "cf-public" {
  name                = "${var.resource-prefix}cf-public"
  host                = "api.sys.dw.gcp.cf-app.com"
  request_path        = "/v2/info"
  check_interval_sec  = 30
  timeout_sec         = 5
  healthy_threshold   = 10
  unhealthy_threshold = 2
  port = 80
}

// Load balancing target pool
resource "google_compute_target_pool" "cf-public" {
  name = "${var.resource-prefix}cf-public"

  health_checks = [
    "${google_compute_http_health_check.cf-public.name}"
  ]
}

// SSH target pool
resource "google_compute_target_pool" "cf-ssh" {
  name = "${var.resource-prefix}cf-ssh"
}

// HTTP forwarding rule
resource "google_compute_forwarding_rule" "cf-http" {
  name        = "${var.resource-prefix}cf-http"
  target      = "${google_compute_target_pool.cf-public.self_link}"
  port_range  = "80"
  ip_protocol = "TCP"
  ip_address  = "${google_compute_address.cf.address}"
}

// HTTP forwarding rule
resource "google_compute_forwarding_rule" "cf-https" {
  name        = "${var.resource-prefix}cf-https"
  target      = "${google_compute_target_pool.cf-public.self_link}"
  port_range  = "443"
  ip_protocol = "TCP"
  ip_address  = "${google_compute_address.cf.address}"
}

// SSH forwarding rule
resource "google_compute_forwarding_rule" "cf-ssh" {
  name        = "${var.resource-prefix}cf-ssh"
  target      = "${google_compute_target_pool.cf-ssh.self_link}"
  port_range  = "2222"
  ip_protocol = "TCP"
  ip_address  = "${google_compute_address.cf-ssh.address}"
}

// WSS forwarding rule
resource "google_compute_forwarding_rule" "cf-wss" {
  name        = "${var.resource-prefix}cf-wss"
  target      = "${google_compute_target_pool.cf-public.self_link}"
  port_range  = "4443"
  ip_protocol = "TCP"
  ip_address  = "${google_compute_address.cf.address}"
}