locals {
  name     = "jsp-production"
  app_port = 3000
  db_port  = 5432

  db_identifier      = "${local.name}-db"
  log_retention_days = 7
}
