# Jenkins IAM review

Review of every IAM identity in the workloads account on 2026-10-06, then the changes made to the Jenkins instance role.

## Inventory

```text
IAM users: 0        access keys: 0        customer managed policies: 0
roles created by terraform: jsp-ci-jenkins, jsp-ci-flow-logs,
  jsp-{staging,production}-ecs-execution, -ecs-task, -flow-logs   (inline policies only)
human access: IAM Identity Center permission set (AdministratorAccess), no long lived keys
OrganizationAccountAccessRole: created by AWS Organizations, never used (break-glass path from the management account)
```

## Policy lint (IAM Access Analyzer validate-policy)

```text
jsp-ci-jenkins / push-api-image, deploy-api-staging, deploy-api-production   0 findings
jsp-*-ecs-execution / start-api-task                                           0 findings
jsp-*-flow-logs / write-flow-logs                                              0 findings
```

## What the Jenkins role really used (IAM last accessed, action level)

```text
ecr   8 of 8 granted actions used (push to jsp-api)
ecs   DescribeServices, DescribeTaskDefinition, DescribeTasks, RunTask, UpdateService used
      (RegisterTaskDefinition and TagResource are not tracked by the report)
iam   reported as never used: the report does not track iam:PassRole, which every deploy needs
ssm   AmazonSSMManagedInstanceCore grants 12 actions, only UpdateInstanceInformation and
      ListInstanceAssociations were used; GetParameter/GetParameters on * (every parameter
      in the account) were never used
```

## Changes

- `AmazonSSMManagedInstanceCore` replaced by an inline `ssm-agent` policy: heartbeat and association check scoped to the Jenkins instance ARN, plus the four `ssmmessages` channels (SSM Agent 3.3.5226 uses them for Run Command and Session Manager). `ec2messages` dropped: after a restart the agent logs AccessDenied on the old endpoint for about one minute and then stops trying.
- `ecs:UpdateService` split from `DescribeServices` and conditioned on `ecs:task-definition`, so each service only moves to a revision of its own family.
- `ecs:DeregisterTaskDefinition` was considered for cleaning up failed revisions and rejected: it only supports `*`, so Jenkins could deregister any task definition in the account.

## Verification on the live role (simulate-principal-policy)

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

After the apply the SSM agent was restarted: PingStatus Online and Run Command working through the message gateway.

## Accepted and documented

- Read-only lookups on `*` (`ecs:DescribeTaskDefinition`, `elasticloadbalancing:DescribeLoadBalancers`, `ecr:GetAuthorizationToken`): these actions do not support resource-level permissions.
- Egress 443 and 80 to the internet (GitHub, registries, AWS APIs; HTTP load balancers until there is a domain and ACM) and 22 (git over SSH with the read-only deploy key).
- Every branch build runs on the same host and could use the role; mitigated by a private repository with a single committer. A real setup would use a separate account or role for production deploys.
