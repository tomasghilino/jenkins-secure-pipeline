data "aws_region" "current" {}

locals {
  region   = data.aws_region.current.region
  app_port = 3000
  db_port  = 5432

  db_identifier      = "${var.name}-db"
  log_retention_days = 7
}
