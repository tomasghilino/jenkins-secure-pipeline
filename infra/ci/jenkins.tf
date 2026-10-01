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
