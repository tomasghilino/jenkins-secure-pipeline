variable "region" {
  type    = string
  default = "us-east-1"
}

variable "image_tag" {
  description = "Git commit sha of the api image in ecr"
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.image_tag))
    error_message = "image_tag must be a full 40 character git commit sha."
  }
}
