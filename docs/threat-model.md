# Threat model

A threat model is a structured way of asking "what could go wrong here, and what stops it?". This one covers what the repository builds: the Jenkins pipeline, the CI host and the two AWS environments. It goes through what's worth protecting, where trust changes hands, the threats that matter for this design, the control that answers each one, and the risks I accepted on purpose.

## What's worth protecting

| Asset | Where it lives | Why it matters |
|---|---|---|
| Source code and `Jenkinsfile` | Private GitHub repository | The `Jenkinsfile` decides what runs with the deploy permissions |
| Jenkins instance role | Instance metadata (IMDSv2) of the CI host | It pushes images and deploys staging and production |
| Container images | ECR repository `jsp-api`, immutable tags | They're the exact code running in each environment |
| Database and its password | RDS in private subnets, password kept by RDS in Secrets Manager | Application data |
| Terraform state | S3 bucket encrypted with a dedicated KMS key | Configuration and resource IDs of every stack |
| CI secrets | Root-only files on the CI host: deploy key, Jenkins and SonarQube admin passwords, SonarQube token | Whoever has them controls the pipeline |
| AWS account access | IAM Identity Center (SSO) | Control of everything above |

## Where trust changes hands

A trust boundary is any point where something less trusted talks to something more trusted. Those are the places where checks have to happen.

```mermaid
flowchart LR
    dev([Engineer]) -->|git push| github[GitHub]
    dev -->|SSO and SSM port forwarding| jenkins
    github -->|polled every 5 min with a read-only deploy key| jenkins
    subgraph civpc [CI VPC, no inbound ports]
        jenkins[Jenkins and SonarQube]
    end
    jenkins -->|instance role| awsapi[AWS APIs: ECR, ECS, ELB]
    jenkins -->|smoke test and ZAP| alb
    internet([Internet]) -->|HTTP 80| alb
    subgraph envvpc [Environment VPC]
        alb[Load balancer] --> tasks[ECS tasks] --> rds[(RDS)]
    end
```

1. Internet to load balancer. The only public entry point is port 80 on each environment's load balancer.
2. GitHub to Jenkins. Code from the repository becomes a pipeline that runs with AWS permissions, so whoever can change the `Jenkinsfile` can, in practice, use those permissions.
3. Jenkins to AWS. The instance role is the pipeline's identity in AWS.
4. Tasks to data. The tasks reach RDS and four AWS services over private paths, and RDS only accepts connections from the tasks.
5. People to AWS. Only through SSO sessions. There are no IAM users or access keys.

## Attack surface

This is everything an attacker could try to reach:

- Public: the HTTP listener of each environment's load balancer, and nothing else. ECS tasks and RDS have no public address, and the CI host's security group has no inbound rule at all.
- Administrative: the AWS console and CLI through SSO, and the Jenkins and SonarQube interfaces through SSM port forwarding.
- Supply chain: everything I didn't write but run anyway, like npm packages, base images, CI tool images, Jenkins plugins and the Terraform provider. Each one is pinned by version, digest or lock file.

## Threats and controls

Each row is one thing that could go wrong, what this repository does about it, and the risk that's still left. The last column matters as much as the middle one, because no control removes a risk completely.

| Threat | What the repository does | What's still left |
|---|---|---|
| A secret gets committed | Gitleaks scans the history on every build and fails it. CI secrets are generated on the host and ignored by Git. RDS creates the database password itself, so it never reaches Terraform state | A leaked secret still has to be rotated and removed from history |
| Someone steals Jenkins' credentials | No inbound ports, and SSM instead of SSH. IMDSv2 with a hop limit of 2 keeps the role away from containers inside Docker-in-Docker. The role only reaches one ECR repository and the two API services, can only move each service to a revision of its own task family, can only pass the ECS roles to ECS, and its SSM permissions only cover the agent on this instance | Every branch's `Jenkinsfile` runs on the same host and could use the role. The repository is private and I'm the only committer |
| A vulnerable base image or OS package | Distroless nonroot runtime, pinned by digest after checking its Cosign signature. Trivy fails the build on fixable HIGH and CRITICAL findings, and an accepted finding needs an expiry date. ECR scans on push. Every build archives a CycloneDX SBOM | Unfixed CVEs are reported, not blocked. Trivy can't see the Node.js runtime inside distroless, so the base image has to be bumped on Node security releases |
| A malicious or vulnerable dependency | `npm ci` from the lock file with install scripts disabled. `npm audit` fails on HIGH findings in production dependencies and verifies registry signatures. Trivy scans the lock file. CI tool images are pinned by digest, and the Trivy, jq and curl images were verified with Cosign first | A malicious release with valid signatures and no advisory yet would get through |
| The database is exposed to the internet | Private subnets, `publicly_accessible = false`, port 5432 open only to the tasks' security group, and TLS forced by the server and verified by the client against the RDS CA. A custom Checkov policy fails the build for any internet ingress other than ports 80 and 443 | Someone changing a security group by hand, outside Terraform |
| An IAM permission is too broad | The execution role pulls one repository, writes one log group and reads one secret. The task role has no permissions at all. Jenkins' policies were reviewed with IAM Access Analyzer and last-accessed data | People use `AdministratorAccess` through SSO |
| An insecure Terraform change | TFLint and Checkov run on every commit before anything is deployed, and each Checkov skip sits next to the code with its reason. The state is versioned, KMS-encrypted, TLS-only and locked during writes | Applies are run by a person from a workstation |
| A vulnerability in the running app | SonarQube quality gate. Security headers set with helmet. A ZAP baseline scan of staging blocks the promotion on FAIL rules | The scan is passive only. There's no authentication, rate limiting or WAF |
| A bad release reaches users | Immutable commit tags. Staging first, with migrations, smoke test and ZAP. Manual approval for production, which gets the same image digest. Circuit breaker rollback. Alarms on 5xx responses and on having no healthy targets | A release that breaks after the production verification has to be rolled back by hand |
| Data leaves through a compromised task | No NAT gateway and no public IPs: the tasks can only reach ECR, CloudWatch Logs, Secrets Manager and S3, through VPC endpoints | The endpoints keep the default full-access policy, so a compromised task could still upload data to an S3 bucket the attacker controls |
| Sensitive data ends up in logs | Request logs only carry method, path, status, duration and trace ID. ECS injects the database credentials and they're never logged. Clients get generic error messages | Internal error logs contain stack traces |

## Accepted risks and what's out of scope

Some things were left out on purpose:

- The API has no authentication. It's the payload of the pipeline, not a product.
- The load balancers only speak HTTP, because there's no domain to get an ACM certificate for.
- Staging and production share one AWS account.
- RDS runs in one availability zone with one day of backups and no deletion protection. Both environments are rebuilt every working session anyway.
- The Jenkins admin password is a file on the CI host, and Jenkins has no SSO.
- Detection and response (CloudTrail analysis, GuardDuty, Security Hub) are outside this project.

The [README](../README.md#what-would-change-in-production) lists what would change for a real production deployment.
