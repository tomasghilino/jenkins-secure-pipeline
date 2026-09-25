provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "jenkins-secure-pipeline"
      Stack     = "bootstrap"
      ManagedBy = "terraform"
    }
  }
}
