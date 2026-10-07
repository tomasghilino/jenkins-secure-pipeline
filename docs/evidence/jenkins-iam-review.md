# Jenkins IAM review

Jenkins holds the most power in this setup: it can push images and deploy to both environments. So on October 6, 2026 I reviewed every IAM identity in the workloads account, checked what Jenkins actually uses, and removed what it didn't need.

## What exists

```text
IAM users: 0        access keys: 0        customer managed policies: 0
roles created by terraform: jsp-ci-jenkins, jsp-ci-flow-logs,
  jsp-{staging,production}-ecs-execution, -ecs-task, -flow-logs   (inline policies only)
human access: IAM Identity Center permission set (AdministratorAccess), no long lived keys
OrganizationAccountAccessRole: created by AWS Organizations, never used (break-glass path from the management account)
```

In short, there are no IAM users and no access keys anywhere. People log in through IAM Identity Center (SSO) and get temporary credentials, and everything else uses roles. `OrganizationAccountAccessRole` is the emergency way in from the management account; AWS Organizations created it and it was never used.

## Are the policies well written?

IAM Access Analyzer has a policy checker, `validate-policy`, that flags mistakes and risky patterns. It found nothing in any of the policies:

```text
jsp-ci-jenkins / push-api-image, deploy-api-staging, deploy-api-production   0 findings
jsp-*-ecs-execution / start-api-task                                           0 findings
jsp-*-flow-logs / write-flow-logs                                              0 findings
```

## What does Jenkins actually use?

IAM keeps "last accessed" data that shows which permissions a role really used. This is how it compared with what the Jenkins role was allowed to do:

```text
ecr   8 of 8 granted actions used (push to jsp-api)
ecs   DescribeServices, DescribeTaskDefinition, DescribeTasks, RunTask, UpdateService used
      (RegisterTaskDefinition and TagResource are not tracked by the report)
iam   reported as never used: the report does not track iam:PassRole, which every deploy needs
ssm   AmazonSSMManagedInstanceCore grants 12 actions, only UpdateInstanceInformation and
      ListInstanceAssociations were used; GetParameter/GetParameters on * (every parameter
      in the account) were never used
```

Two things to keep in mind when reading it. Some actions don't show up in the report at all, like `iam:PassRole` and `ecs:RegisterTaskDefinition`, so "never used" doesn't always mean "not needed". And the AWS managed policy for SSM granted 12 actions, including reading every parameter in the account, while Jenkins only used two of them.

## What I changed

- I replaced `AmazonSSMManagedInstanceCore` with a small inline policy, `ssm-agent`. It allows the agent's heartbeat and association check, only on the Jenkins instance, plus the four `ssmmessages` channels that SSM Agent 3.3.5226 uses for Run Command and Session Manager. I also dropped `ec2messages`: after a restart the agent logs AccessDenied on that older endpoint for about a minute and then stops trying.
- I split `ecs:UpdateService` from `DescribeServices` and added a condition on `ecs:task-definition`, so each service can only move to a revision of its own family. In practice, Jenkins can't put a staging revision on the production service, even by mistake.
- I thought about giving Jenkins `ecs:DeregisterTaskDefinition` to clean up failed revisions, and decided against it. That action only works on `*`, so Jenkins could deregister any task definition in the account.

## Proving it on the live role

`simulate-principal-policy` asks IAM "would this role be allowed to do X on Y?" without actually doing it. I tested what Jenkins must be able to do and what it must not:

```text
ecr:PutImage                   jsp-api repository                        allowed
ecr:PutImage                   another repository                        implicitDeny
ecs:UpdateService              staging service, staging revision         allowed
ecs:UpdateService              staging service, production revision      implicitDeny
ecs:UpdateService              production service, production revision   allowed
ecs:UpdateService              production service, staging revision      implicitDeny
iam:PassRole                   staging execution role to ecs tasks       allowed
iam:PassRole                   staging execution role to lambda          implicitDeny
ecs:DeregisterTaskDefinition   any task definition                       implicitDeny
ssm:UpdateInstanceInformation  jenkins instance                          allowed
ssm:GetParameter(s)            any parameter (allowed before)            implicitDeny
s3:ListAllMyBuckets            unrelated service                         implicitDeny
```

After the apply I restarted the SSM agent and checked that the host still showed as Online and that Run Command still worked.

## What I accepted, and why

- A few read-only lookups use `*` (`ecs:DescribeTaskDefinition`, `elasticloadbalancing:DescribeLoadBalancers`, `ecr:GetAuthorizationToken`) because AWS doesn't let you limit those actions to specific resources.
- The host can reach the internet on ports 443 and 80 (GitHub, registries, AWS APIs, and the HTTP load balancers until there's a domain with an ACM certificate) and on 22, for git over SSH with a read-only deploy key.
- Every branch builds on the same host and could use the role. The risk is small here because the repository is private and I'm the only committer. A real setup would deploy production from a separate account or role.
