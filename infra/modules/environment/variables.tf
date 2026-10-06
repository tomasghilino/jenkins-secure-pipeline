variable "name" {
  description = "Prefix for every resource name, for example jsp-staging"
  type        = string
}

variable "vpc_cidr" {
  description = "Address range of the environment vpc"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && endswith(var.vpc_cidr, "/16")
    error_message = "vpc_cidr must be a /16 block, for example 10.0.0.0/16."
  }
}

variable "image_tag" {
  description = "Git commit sha of the api image in ecr"
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.image_tag))
    error_message = "image_tag must be a full 40 character git commit sha."
  }
}
