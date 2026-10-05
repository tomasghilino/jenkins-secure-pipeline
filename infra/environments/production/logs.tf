resource "aws_cloudwatch_log_group" "app" {
  #checkov:skip=CKV_AWS_158:encrypted at rest with an aws owned key, a customer key per session would pile up keys pending deletion
  #checkov:skip=CKV_AWS_338:logs only matter while the environment is up, a long lived production would keep a year
  name              = "/ecs/${local.name}-api"
  retention_in_days = local.log_retention_days
}

# rds writes to this exact name, so terraform creates it first to control retention and delete it on destroy
resource "aws_cloudwatch_log_group" "db" {
  #checkov:skip=CKV_AWS_158:encrypted at rest with an aws owned key, a customer key per session would pile up keys pending deletion
  #checkov:skip=CKV_AWS_338:logs only matter while the environment is up, a long lived production would keep a year
  name              = "/aws/rds/instance/${local.db_identifier}/postgresql"
  retention_in_days = local.log_retention_days
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  #checkov:skip=CKV_AWS_158:encrypted at rest with an aws owned key, a customer key per session would pile up keys pending deletion
  #checkov:skip=CKV_AWS_338:logs only matter while the environment is up, a long lived production would keep a year
  name              = "/vpc/${local.name}-flow-logs"
  retention_in_days = local.log_retention_days
}

# one record per connection attempt in the vpc, accepted or rejected by a security group
resource "aws_flow_log" "main" {
  vpc_id                   = aws_vpc.main.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn             = aws_iam_role.flow_logs.arn
  max_aggregation_interval = 60

  tags = {
    Name = "${local.name}-flow-log"
  }
}

# saved in the logs insights console, so nobody has to remember the flow log field names
resource "aws_cloudwatch_query_definition" "rejected_connections" {
  name            = "${local.name}/rejected-connections"
  log_group_names = [aws_cloudwatch_log_group.flow_logs.name]

  query_string = <<-EOT
    filter action = "REJECT"
    | stats count(*) as attempts by srcAddr, dstPort
    | sort attempts desc
    | limit 50
  EOT
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }

    # only flow logs created in this account can use the role
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name_prefix        = "${local.name}-flow-logs-"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json
}

data "aws_iam_policy_document" "flow_logs_write" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["${aws_cloudwatch_log_group.flow_logs.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "write-flow-logs"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs_write.json
}
