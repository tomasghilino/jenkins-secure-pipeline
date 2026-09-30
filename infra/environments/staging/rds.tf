resource "aws_db_subnet_group" "main" {
  name_prefix = "${local.name}-db-"
  description = "Private database subnets"
  subnet_ids  = [aws_subnet.db_a.id, aws_subnet.db_b.id]

  tags = {
    Name = "${local.name}-db-subnet-group"
  }
}

# written out even though it matches the aws default, so the tls requirement is visible in code
resource "aws_db_parameter_group" "main" {
  name_prefix = "${local.name}-postgres17-"
  description = "PostgreSQL 17 settings"
  family      = "postgres17"

  # aws reports a value equal to the engine default as pending-reboot, so any other method shows a diff on every plan
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "main" {
  #checkov:skip=CKV_AWS_157:single az staging database, multi az doubles the cost
  #checkov:skip=CKV_AWS_293:staging is destroyed after every session
  #checkov:skip=CKV_AWS_118:basic cloudwatch metrics are enough for a short lived staging database
  #checkov:skip=CKV_AWS_353:basic cloudwatch metrics are enough for a short lived staging database
  #checkov:skip=CKV_AWS_161:the app authenticates with the password from secrets manager
  identifier     = local.db_identifier
  engine         = "postgres"
  engine_version = "17"
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "api"
  username = "api"
  port     = local.db_port

  # rds generates the password and keeps it in secrets manager, so it never reaches terraform state
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  parameter_group_name   = aws_db_parameter_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period    = 1
  copy_tags_to_snapshot      = true
  auto_minor_version_upgrade = true

  enabled_cloudwatch_logs_exports = ["postgresql"]

  # staging is destroyed after every session and holds no data worth keeping
  skip_final_snapshot = true
  deletion_protection = false

  # the log group must exist first, otherwise rds creates it without retention and outside terraform
  depends_on = [aws_cloudwatch_log_group.db]
}
