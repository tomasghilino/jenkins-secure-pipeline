# Terraform refactor into a module

At first, staging and production were two flat Terraform stacks with the same 56 resources each. Only three things differed: the name prefix, the VPC address range and the `Environment` tag. Writing them flat first made every resource easy to see and understand. Once both had worked end to end through the pipeline, keeping two copies in sync was just a chance to make mistakes, so I moved them into one module, `infra/modules/environment`, with two short callers:

```hcl
module "environment" {
  source = "../../modules/environment"

  name      = "jsp-staging"
  vpc_cidr  = "10.0.0.0/16"
  image_tag = var.image_tag
}
```

## How I proved nothing changed

A refactor should change the code, not the infrastructure. Both environments were destroyed at the time, so the state was empty and nothing had to be moved. With live infrastructure you'd add `moved` blocks that map each old address to its new one, and the proof would be a plan that says no changes.

With nothing live to compare against, I compared plans instead. I planned both versions against the empty state, exported each plan with `terraform show -json`, removed the `module.environment.` prefix from the new addresses and compared them resource by resource:

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

Same resources, same values, same outputs. The two extra changes on each side are IAM policy documents that Terraform reads during the apply. After that I created both environments from the module, and dev build #18 deployed, tested and promoted the API through them.

## A TFLint surprise

The refactor uncovered a TFLint limitation. Its `aws_resource_missing_tags` rule can't see the provider of the module's caller, so it reported 45 resources as untagged, even though they inherit the provider's default tags. So I moved the check to where the tags are actually set, with `aws_provider_missing_default_tags` on every stack's provider.

To be sure TFLint still catches real mistakes, I tried four deliberately broken copies: a provider missing a tag, a provider with no default tags, an invalid RDS instance class inside the module, and an unused module variable. TFLint failed on all four.
