# registry level because aws is deprecating the per-repository scan on push setting
resource "aws_ecr_registry_scanning_configuration" "main" {
  scan_type = "BASIC"

  rule {
    scan_frequency = "SCAN_ON_PUSH"

    repository_filter {
      filter      = "*"
      filter_type = "WILDCARD"
    }
  }
}

resource "aws_ecr_repository" "api" {
  #checkov:skip=CKV_AWS_163:scan on push is configured for the whole registry above
  name                 = "jsp-api"
  image_tag_mutability = "IMMUTABLE"

  encryption_configuration {
    encryption_type = "KMS"
  }
}

# only untagged images expire: any tagged one may be the image running in production
resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images after 7 days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 7
      }
      action = {
        type = "expire"
      }
    }]
  })
}
