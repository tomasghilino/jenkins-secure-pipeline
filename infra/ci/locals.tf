locals {
  name               = "jsp-ci"
  log_retention_days = 7

  # jenkins deploys into the staging stack, which prefixes every resource name with this
  staging_name   = "jsp-staging"
  ecs_arn_prefix = "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}"
}
