terraform {
  backend "s3" {
    bucket = "jsp-tfstate-85c106dbda337c42825f1de78d"
    key    = "environments/production/terraform.tfstate"
    region = "us-east-1"

    encrypt = true
    # without kms_key_id, encrypt = true writes with sse-s3 and skips the state key
    kms_key_id   = "alias/jsp-tfstate"
    use_lockfile = true
  }
}
