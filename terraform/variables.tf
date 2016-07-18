variable "region" {
  type = "string"
  default = "us-east1"
}

variable "zone" {
  type = "string"
  default = "us-east1-d"
}

variable "project" {
  type = "string"
}

variable "resource-prefix" {
  type = "string"
  default = ""
}

variable "cidr-piece" {
  type = "string"
}