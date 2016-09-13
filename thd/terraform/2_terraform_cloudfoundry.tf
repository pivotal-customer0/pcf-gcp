// Declare vars

variable "sys-domain" {
    type = "string"
    default = "REPACE WITH SYSTEM DOMAIN"
}

variable "cf-cidr" {
    type = "string"
    default = "10.0.16.0/20"
}

// Subnet for the private Cloud Foundry components
resource "google_compute_subnetwork" "cf-private-subnet-1" {
  name          = "cf-private-${var.region}"
  ip_cidr_range = "${var.cf-cidr}"
  network       = "${google_compute_network.cf.self_link}"
}

// Allow access to CloudFoundry via HTTP, HTTPs and WebSocket
resource "google_compute_firewall" "cf-allow-http-https-wss" {
  name    = "cf-allow-http-https-wss-${var.region}"
  network = "${google_compute_network.cf.name}"

  allow {
    protocol = "tcp"
//    ports    = ["80", "443", "2222"]
    ports    = ["80", "443"]
  }

  source_ranges = ["151.140.0.0/16","165.130.0.0/16","207.11.0.0/17","50.207.27.182/32","96.83.24.238/32"]
  target_tags = ["pcf-lb-${var.region}"]
}

// Static IP address for forwarding rule
resource "google_compute_address" "cf-sys" {
  name = "pcf-sys-${var.region}"
}

// Static IP address for forwarding rule
resource "google_compute_address" "cf-apps" {
  name = "pcf-apps-${var.region}"
}

// Health check
resource "google_compute_http_health_check" "cf-health-check" {
  name                = "cf-health-check-${var.region}"
  host                = "api.${var.sys-domain}"
  request_path        = "/v2/info"
  check_interval_sec  = 30
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 2
  port = 80
}

// Load balancing target pool
resource "google_compute_target_pool" "pcf-lb" {
  name = "pcf-lb-${var.region}"

  health_checks = [
    "${google_compute_http_health_check.cf-health-check.name}"
  ]
}

// HTTP forwarding rule
resource "google_compute_forwarding_rule" "cf-sys-http" {
  name        = "cf-sys-http-${var.region}"
  target      = "${google_compute_target_pool.pcf-lb.self_link}"
  port_range  = "80"
  ip_protocol = "TCP"
  ip_address  = "${google_compute_address.cf-sys.address}"
}

// HTTPS forwarding rule
resource "google_compute_forwarding_rule" "cf-sys-https" {
  name        = "cf-sys-https-${var.region}"
  target      = "${google_compute_target_pool.pcf-lb.self_link}"
  port_range  = "443"
  ip_protocol = "TCP"
  ip_address  = "${google_compute_address.cf-sys.address}"
}

// SSH forwarding rule
/* resource "google_compute_forwarding_rule" "cf-sys-ssh" { */
/*   name        = "cf-sys-ssh-${var.region}" */
/*   target      = "${google_compute_target_pool.pcf-lb.self_link}" */
/*   port_range  = "2222" */
/*   ip_protocol = "TCP" */
/*   ip_address  = "${google_compute_address.cf-sys.address}" */
/* } */

// HTTP forwarding rule
resource "google_compute_forwarding_rule" "cf-apps-http" {
  name        = "cf-apps-http-${var.region}"
  target      = "${google_compute_target_pool.pcf-lb.self_link}"
  port_range  = "80"
  ip_protocol = "TCP"
  ip_address  = "${google_compute_address.cf-apps.address}"
}

// HTTPS forwarding rule
resource "google_compute_forwarding_rule" "cf-apps-https" {
  name        = "cf-apps-https-${var.region}"
  target      = "${google_compute_target_pool.pcf-lb.self_link}"
  port_range  = "443"
  ip_protocol = "TCP"
  ip_address  = "${google_compute_address.cf-apps.address}"
}
