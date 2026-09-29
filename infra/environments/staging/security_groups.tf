# no rules on purpose: anything launched without an explicit security group gets no traffic
resource "aws_default_security_group" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name}-default-sg"
  }
}

resource "aws_security_group" "alb" {
  #checkov:skip=CKV2_AWS_5:attached when the load balancer is added
  name_prefix = "${local.name}-alb-"
  description = "Public application load balancer"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name}-alb-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_from_internet" {
  #checkov:skip=CKV_AWS_260:public entry point, https needs an acm certificate and a domain
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from the internet"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Requests and health checks to the app"
  ip_protocol                  = "tcp"
  from_port                    = local.app_port
  to_port                      = local.app_port
  referenced_security_group_id = aws_security_group.app.id
}

resource "aws_security_group" "app" {
  #checkov:skip=CKV2_AWS_5:attached when the ecs service is added
  name_prefix = "${local.name}-app-"
  description = "API tasks"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name}-app-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "Requests and health checks from the load balancer"
  ip_protocol                  = "tcp"
  from_port                    = local.app_port
  to_port                      = local.app_port
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "app_to_db" {
  security_group_id            = aws_security_group.app.id
  description                  = "PostgreSQL to the database"
  ip_protocol                  = "tcp"
  from_port                    = local.db_port
  to_port                      = local.db_port
  referenced_security_group_id = aws_security_group.db.id
}

resource "aws_vpc_security_group_egress_rule" "app_to_endpoints" {
  security_group_id            = aws_security_group.app.id
  description                  = "HTTPS to the interface endpoints"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.endpoints.id
}

resource "aws_vpc_security_group_egress_rule" "app_to_s3" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS to S3 through the gateway endpoint, for image layers"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = aws_vpc_endpoint.s3.prefix_list_id
}

# no egress rules: the database never opens connections, and replies pass because security groups are stateful
resource "aws_security_group" "db" {
  name_prefix = "${local.name}-db-"
  description = "PostgreSQL database"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name}-db-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from the app"
  ip_protocol                  = "tcp"
  from_port                    = local.db_port
  to_port                      = local.db_port
  referenced_security_group_id = aws_security_group.app.id
}

# no egress rules: the endpoints only answer requests
resource "aws_security_group" "endpoints" {
  name_prefix = "${local.name}-endpoints-"
  description = "Interface VPC endpoints"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name}-endpoints-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_app" {
  security_group_id            = aws_security_group.endpoints.id
  description                  = "HTTPS from the app"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.app.id
}
