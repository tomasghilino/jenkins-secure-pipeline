variable "region" {
  type    = string
  default = "us-east-1"
}

variable "image_tag" {
  description = "Git commit sha of the api image in ecr"
  type        = string
}
