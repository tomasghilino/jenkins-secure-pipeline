resource "aws_lb" "main" {
  #checkov:skip=CKV_AWS_150:environments are destroyed after every session, a long lived production would turn it on
  #checkov:skip=CKV_AWS_91:no request history while an environment only lives for a session, a long lived production would send access logs to s3
  #checkov:skip=CKV2_AWS_20:https needs an acm certificate and a domain
  #checkov:skip=CKV2_AWS_28:a waf web acl adds a monthly cost, production would add aws managed rules
  name               = "${var.name}-alb"
  load_balancer_type = "application"
  internal           = false
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  security_groups    = [aws_security_group.alb.id]

  drop_invalid_header_fields = true
  enable_deletion_protection = false
}

resource "aws_lb_target_group" "app" {
  #checkov:skip=CKV_AWS_378:traffic from the load balancer to the tasks stays inside the vpc
  name        = "${var.name}-app"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  protocol    = "HTTP"
  port        = local.app_port

  # the api stops in under 10 seconds, so waiting the default 300 only slows deploys and destroys
  deregistration_delay = 30

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  #checkov:skip=CKV_AWS_2:https needs an acm certificate and a domain
  #checkov:skip=CKV_AWS_103:no tls listener until there is a domain
  load_balancer_arn = aws_lb.main.arn
  protocol          = "HTTP"
  port              = 80

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
