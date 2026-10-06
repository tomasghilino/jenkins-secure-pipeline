plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.49.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# every stack sets these as provider default tags; the per resource rule cannot see the provider of a module's caller
rule "aws_provider_missing_default_tags" {
  enabled = true
  tags    = ["Project", "ManagedBy"]
}

rule "aws_security_group_inline_rules" {
  enabled = true
}

rule "aws_security_group_rule_deprecated" {
  enabled = true
}
