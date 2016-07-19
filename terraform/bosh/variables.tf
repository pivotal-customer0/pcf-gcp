variable "project" {
  type = "string"
  default = "mg-sandbox"
}

variable "region" {
  type = "string"
  default = "us-east1"
}

variable "zone" {
  type = "string"
  default = "us-east1-d"
}

variable "resource-prefix" {
  type = "string"
  default = "c0-run1"
}

variable "bosh-subnet-cidr-range" {
  type = "string"
  default = "10.0.0.0/24"
}

variable "cc-subnet-cidr-range" {
  type = "string"
  default = "10.0.2.0/24"
}

variable "pcf-subnet-cidr-range" {
  type = "string"
  default = "10.0.16.0/22"
}
