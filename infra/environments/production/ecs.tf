# the repository lives in the shared stack, so it is looked up by name
data "aws_ecr_repository" "api" {
  name = "jsp-api"
}

resource "aws_ecs_cluster" "main" {
  #checkov:skip=CKV_AWS_65:container insights bills custom metrics, basic ecs metrics are enough while it only lives for a session
  name = local.name
}

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# used by ecs itself to start the task: pull the image, read the secret, write logs
resource "aws_iam_role" "ecs_execution" {
  name_prefix        = "${local.name}-ecs-execution-"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

data "aws_iam_policy_document" "ecs_execution" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "PullApiImage"
    actions   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
    resources = [data.aws_ecr_repository.api.arn]
  }

  statement {
    sid       = "WriteApiLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.app.arn}:*"]
  }

  statement {
    sid       = "ReadDatabaseSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_db_instance.main.master_user_secret[0].secret_arn]
  }
}

resource "aws_iam_role_policy" "ecs_execution" {
  name   = "start-api-task"
  role   = aws_iam_role.ecs_execution.id
  policy = data.aws_iam_policy_document.ecs_execution.json
}

# used by the api code while it runs; it calls no aws api, so it gets no permissions
resource "aws_iam_role" "ecs_task" {
  name_prefix        = "${local.name}-ecs-task-"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_ecs_task_definition" "api" {
  family                   = "${local.name}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  # the empty lists and hostPort are the values aws stores anyway; leaving them out shows a replacement on every plan
  container_definitions = jsonencode([
    {
      name                   = "api"
      image                  = "${data.aws_ecr_repository.api.repository_url}:${var.image_tag}"
      essential              = true
      readonlyRootFilesystem = true
      linuxParameters = {
        capabilities = { add = [], drop = ["ALL"] }
      }
      portMappings   = [{ containerPort = local.app_port, hostPort = local.app_port, protocol = "tcp" }]
      mountPoints    = []
      volumesFrom    = []
      systemControls = []

      environment = [
        { name = "PGHOST", value = aws_db_instance.main.address },
        { name = "PGPORT", value = tostring(local.db_port) },
        { name = "PGDATABASE", value = aws_db_instance.main.db_name },
        # encrypted and the server certificate must match the rds hostname
        { name = "PGSSLMODE", value = "verify-full" },
      ]

      # ecs reads these keys from secrets manager at start, the values never appear in the task definition
      secrets = [
        { name = "PGUSER", valueFrom = "${aws_db_instance.main.master_user_secret[0].secret_arn}:username::" },
        { name = "PGPASSWORD", valueFrom = "${aws_db_instance.main.master_user_secret[0].secret_arn}:password::" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "api"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "api" {
  name             = "api"
  cluster          = aws_ecs_cluster.main.id
  task_definition  = aws_ecs_task_definition.api.arn
  desired_count    = 1
  launch_type      = "FARGATE"
  platform_version = "LATEST"
  propagate_tags   = "SERVICE"

  network_configuration {
    subnets          = [aws_subnet.app_a.id, aws_subnet.app_b.id]
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "api"
    container_port   = local.app_port
  }

  # after three new tasks in a row fail to start or fail the load balancer health check, ecs marks the
  # deployment failed and goes back to the last revision that completed
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # apply finishes only when the task is running and healthy behind the load balancer
  wait_for_steady_state = true

  # the target group must be attached to the load balancer before a service can use it
  depends_on = [aws_lb_listener.http]

  lifecycle {
    # jenkins deploys every commit as a new revision, terraform only sets the first one
    ignore_changes = [task_definition]
  }
}

resource "aws_cloudwatch_query_definition" "api_errors" {
  name            = "${local.name}/api-errors"
  log_group_names = [aws_cloudwatch_log_group.app.name]

  query_string = <<-EOT
    filter level in ["error", "fatal"]
    | fields @timestamp, context, message
    | sort @timestamp desc
    | limit 100
  EOT
}
