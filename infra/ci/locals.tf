locals {
  name               = "jsp-ci"
  log_retention_days = 7

  # jenkins deploys into these stacks, and each one prefixes every resource name with its value
  deploy_environments = {
    staging    = "jsp-staging"
    production = "jsp-production"
  }
  ecs_arn_prefix = "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}"
}
