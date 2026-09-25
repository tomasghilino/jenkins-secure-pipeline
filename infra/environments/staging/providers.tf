provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "jenkins-secure-pipeline"
      Environment = "staging"
      ManagedBy   = "terraform"
    }
  }
}
