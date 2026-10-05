# private paths from the app subnets to aws services, instead of a nat gateway
locals {
  interface_endpoints = ["ecr.api", "ecr.dkr", "logs", "secretsmanager"]
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.interface_endpoints)

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.app_a.id, aws_subnet.app_b.id]
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${local.name}-${replace(each.value, ".", "-")}-endpoint"
  }
}

# ecr stores image layers in s3; gateway endpoints are free and work through the route table
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.app.id]

  tags = {
    Name = "${local.name}-s3-endpoint"
  }
}
