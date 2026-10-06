# Terraform refactor into a module

Staging and production were first written as two flat stacks with the same 56 resources; only the name prefix, the VPC range and the `Environment` tag differed. Once both had worked through the whole pipeline, they were replaced by one module, `infra/modules/environment`, and two short callers:

```hcl
module "environment" {
  source = "../../modules/environment"

  name      = "jsp-staging"
  vpc_cidr  = "10.0.0.0/16"
  image_tag = var.image_tag
}
```

Both environments were destroyed at the time, so the state was empty and no resource had to be moved. With live infrastructure, `moved` blocks would map each old address to its new one, and the proof would be a plan with no changes.

The proof here was a plan comparison. Both versions were planned against the empty state, exported with `terraform show -json`, and compared resource by resource after removing the `module.environment.` prefix from the new addresses:

```text
===== staging
flat: 58 changes (56 managed resources), module: 58 changes
only in flat: []
only in module: []
same address, different values: []
root outputs equal: true
===== production
flat: 58 changes (56 managed resources), module: 58 changes
only in flat: []
only in module: []
same address, different values: []
root outputs equal: true
```

The two extra changes are IAM policy documents that Terraform reads during the apply. Both environments were then created from the module, and dev build #18 deployed, tested and promoted the API through them.

The refactor exposed one tool limitation: TFLint's `aws_resource_missing_tags` rule cannot see the provider of a module's caller, so it reported 45 resources as untagged even though they inherit the provider's default tags. The repository now enforces the tags where they are set, with `aws_provider_missing_default_tags` on every stack's provider. Four deliberately broken copies were checked: a missing tag on a provider, a provider without default tags, an invalid RDS instance class inside the module, and an unused module variable. TFLint failed on each one.
