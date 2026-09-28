plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.49.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

rule "aws_resource_missing_tags" {
  enabled = true
  tags    = ["Project", "ManagedBy"]
}

rule "aws_security_group_inline_rules" {
  enabled = true
}

rule "aws_security_group_rule_deprecated" {
  enabled = true
}
