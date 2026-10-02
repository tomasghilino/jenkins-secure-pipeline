data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_ecr_repository" "api" {
  name = "jsp-api"
}

resource "aws_security_group" "jenkins" {
  name_prefix = "${local.name}-jenkins-"
  description = "Jenkins and SonarQube host"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name}-jenkins-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "jenkins_https" {
  security_group_id = aws_security_group.jenkins.id
  description       = "HTTPS to GitHub, registries, npm and AWS APIs"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "jenkins_http" {
  security_group_id = aws_security_group.jenkins.id
  description       = "HTTP to the staging load balancer for smoke tests and ZAP"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  # the load balancer ips change every time staging is created, and it has no tls listener yet
  cidr_ipv4 = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "jenkins_git_ssh" {
  security_group_id = aws_security_group.jenkins.id
  description       = "Git over SSH to GitHub with the deploy key"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = "0.0.0.0/0"
}

data "aws_iam_policy_document" "jenkins_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "jenkins" {
  name_prefix        = "${local.name}-jenkins-"
  assume_role_policy = data.aws_iam_policy_document.jenkins_assume.json
}

resource "aws_iam_role_policy_attachment" "jenkins_ssm" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "jenkins_ecr_push" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [data.aws_ecr_repository.api.arn]
  }
}

resource "aws_iam_role_policy" "jenkins_ecr_push" {
  name   = "push-api-image"
  role   = aws_iam_role.jenkins.id
  policy = data.aws_iam_policy_document.jenkins_ecr_push.json
}

data "aws_iam_policy_document" "jenkins_deploy_staging" {
  # these read only calls do not support resource level permissions
  statement {
    sid       = "Lookups"
    actions   = ["ecs:DescribeTaskDefinition", "elasticloadbalancing:DescribeLoadBalancers"]
    resources = ["*"]
  }

  statement {
    sid       = "RegisterApiRevisions"
    actions   = ["ecs:RegisterTaskDefinition"]
    resources = ["${local.ecs_arn_prefix}:task-definition/${local.staging_name}-api:*"]
  }

  statement {
    sid       = "RunMigrations"
    actions   = ["ecs:RunTask"]
    resources = ["${local.ecs_arn_prefix}:task-definition/${local.staging_name}-api:*"]

    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = ["${local.ecs_arn_prefix}:cluster/${local.staging_name}"]
    }
  }

  statement {
    sid       = "WatchMigrations"
    actions   = ["ecs:DescribeTasks"]
    resources = ["${local.ecs_arn_prefix}:task/${local.staging_name}/*"]
  }

  # tags are copied onto new revisions and migration tasks, and can only be set while creating them
  statement {
    sid     = "TagOnCreate"
    actions = ["ecs:TagResource"]
    resources = [
      "${local.ecs_arn_prefix}:task-definition/${local.staging_name}-api:*",
      "${local.ecs_arn_prefix}:task/${local.staging_name}/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "ecs:CreateAction"
      values   = ["RegisterTaskDefinition", "RunTask"]
    }
  }

  statement {
    sid       = "DeployApiService"
    actions   = ["ecs:DescribeServices", "ecs:UpdateService"]
    resources = ["${local.ecs_arn_prefix}:service/${local.staging_name}/api"]
  }

  # the staging roles use name prefixes, and staging recreates them every session
  statement {
    sid     = "PassApiTaskRoles"
    actions = ["iam:PassRole"]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.staging_name}-ecs-execution-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.staging_name}-ecs-task-*",
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "jenkins_deploy_staging" {
  name   = "deploy-api-staging"
  role   = aws_iam_role.jenkins.id
  policy = data.aws_iam_policy_document.jenkins_deploy_staging.json
}

resource "aws_iam_instance_profile" "jenkins" {
  name_prefix = "${local.name}-jenkins-"
  role        = aws_iam_role.jenkins.name
}

resource "aws_instance" "jenkins" {
  #checkov:skip=CKV_AWS_88:the public ip is only for egress, the security group has no ingress and access goes through ssm
  #checkov:skip=CKV_AWS_126:detailed monitoring is paid and five minute metrics are enough for one ci host
  ami                         = data.aws_ssm_parameter.al2023.insecure_value
  instance_type               = "t3a.large"
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.jenkins.id]
  iam_instance_profile        = aws_iam_instance_profile.jenkins.name
  associate_public_ip_address = true
  ebs_optimized               = true
  user_data                   = file("${path.module}/user-data.sh")

  # standard mode never bills surplus cpu credits, a long build just runs slower
  credit_specification {
    cpu_credits = "standard"
  }

  # hop limit 2 reaches the jenkins containers on the host, build containers nested in dind are one hop too far
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 40
    encrypted   = true

    tags = {
      Name = "${local.name}-jenkins-root"
    }
  }

  tags = {
    Name = "${local.name}-jenkins"
  }

  lifecycle {
    # a new al2023 release would otherwise replace the host and its disk with the jenkins and sonarqube data
    ignore_changes = [ami]
  }
}
