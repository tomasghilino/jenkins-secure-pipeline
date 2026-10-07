# Deployment guide

This is the practical side: how to run the API on your machine, create the AWS infrastructure, ship a change through the pipeline, roll it back and tear everything down. The commands assume a POSIX shell at the repository root and an AWS CLI profile from IAM Identity Center exported as `AWS_PROFILE`.

## What you need

- Docker with Compose
- Node.js 24 and npm, only if you want to run the tests outside containers
- Terraform 1.16, AWS CLI v2 and the Session Manager plugin
- An AWS account with an IAM Identity Center user allowed to administer it
- Admin access to the GitHub repository, to add a read-only deploy key

## Run it locally

```bash
cp .env.example .env
docker compose up --build
curl http://127.0.0.1:3000/health
```

Compose starts PostgreSQL, runs the migrations in a one-off container and then starts the API on `127.0.0.1:3000`. The API container runs with a read-only filesystem and no Linux capabilities, the same way it runs on ECS, so surprises show up on your machine first.

For the tests:

```bash
cd app
npm ci
npm test
npm run test:e2e
```

The integration tests start their own throwaway PostgreSQL with Testcontainers, so they need Docker but not the Compose stack.

## Create the AWS infrastructure

The stacks go in this order, because each one uses something the previous one created. One catch in a new account: S3 bucket names are global, so your state bucket needs a different name, and the `bucket` value in every `backend.tf` has to change to match.

| Step | Stack | Notes |
|---|---|---|
| 1 | `infra/bootstrap` | First apply with local state (`backend.tf` set aside), then `terraform init -migrate-state` moves its own state into the new bucket |
| 2 | `infra/shared` | ECR repository, registry scanning and the SNS alarm topic |
| 3 | `infra/ci` | CI network and the Jenkins host |
| 4 | `infra/environments/staging` and `production` | One environment each, about 12 minutes (most of it is RDS) |

Step 1 is a chicken-and-egg problem: Terraform needs the bucket to store its state, but the bucket is created by Terraform. That's why the first apply uses local state, and the state moves into the bucket right after.

Then the shared and CI stacks:

```bash
terraform -chdir=infra/shared init
terraform -chdir=infra/shared apply
terraform -chdir=infra/ci init
terraform -chdir=infra/ci apply
```

To get alarm emails, subscribe an address to the shared topic and click the confirmation link in the email AWS sends:

```bash
aws sns subscribe --protocol email --notification-endpoint you@example.com \
  --topic-arn "$(terraform -chdir=infra/shared output -raw alarm_topic_arn)"
```

### The Jenkins host

The host has no SSH. Open a shell with Session Manager and run `scripts/jenkins-ec2-bootstrap.sh` as root:

```bash
aws ssm start-session --target "$(terraform -chdir=infra/ci output -raw jenkins_instance_id)"
```

The first run generates a deploy key and prints its public half. Add it to the GitHub repository as a read-only deploy key and run the script again. The second run clones the repository into `/opt/jsp`, generates every secret on the host (`scripts/jenkins-local-secrets.sh`), installs a systemd unit that runs the Compose stack and configures SonarQube (`scripts/sonarqube-local-setup.sh`). It's safe to run it again later.

To open the web interfaces, keep a tunnel running and browse to `http://127.0.0.1:8080`, or to `:9000` if you start it with the `sonarqube` argument. The Jenkins admin password is in `/opt/jsp/jenkins/secrets/jenkins_admin_password` on the host.

```bash
scripts/jenkins-tunnel.sh
```

### The environments

An environment needs the commit SHA of an image that already exists in ECR. That sounds circular, but it isn't: the pipeline pushes the image before it reaches any deploy stage, so the first run gives you an image, and you create the environments with its SHA.

```bash
terraform -chdir=infra/environments/staging init
terraform -chdir=infra/environments/staging apply -var image_tag=<commit sha>
```

Production is the same command in `infra/environments/production`. A new database is empty until the first deploy runs the migrations.

## Ship a change

Push to `dev`. Jenkins polls GitHub every 5 minutes, or you can start it right away with "Scan Multibranch Pipeline Now". Other branches get all the CI checks but stop before anything is pushed or deployed.

This is how long build #19 took, with my approval in the middle:

| Part | Stages | Time |
|---|---|---|
| CI | Checkout, Gitleaks, npm install and audit, lint, typecheck, unit tests, integration tests, SonarQube, Terraform checks, Docker build, Trivy and SBOM, push to ECR | 4.5 min |
| Staging | Register revision, migrate database, roll out service, smoke test, ZAP baseline | 5 min |
| Approval | Waits up to 30 minutes for the `admin` user | as long as the reviewer takes |
| Production | Register revision, migrate database, roll out service, verify | 4 min |

Each deploy copies the latest task definition revision, changes only the image to the new commit tag and registers that as a new revision. The migrations run as a one-off task with that revision, and only then does the service move to it. Jenkins waits for the service to settle and fails the build if the service ended up on any other revision, which is how a rollback turns into a red build.

When the build reaches `Approve production`, open it in Jenkins and choose Deploy to production. Production then gets the image staging just tested, without rebuilding anything. Abort, or no answer within 30 minutes, ends the build and leaves production as it was.

## Roll back

There are three ways back, depending on how bad things are:

- If the new tasks fail the health check, you don't have to do anything. The ECS circuit breaker returns the service to the last completed deployment, and Jenkins fails the build and prints the latest ECS events.
- The normal way is to revert the commit on `dev`. The pipeline tests the revert like any other change and promotes it after approval.
- In an emergency, point the service back at the previous revision by hand, then revert the commit so the next deploy doesn't bring the problem back:

```bash
aws ecs update-service --cluster jsp-production --service api --task-definition jsp-production-api:<previous revision>
```

## Tear it down

At the end of every working session:

1. Let running builds finish, or abort the one waiting for approval.
2. Destroy both environments. Here `image_tag` only has to be a valid SHA, because nothing is created from it.

   ```bash
   terraform -chdir=infra/environments/staging destroy -var image_tag=<commit sha>
   terraform -chdir=infra/environments/production destroy -var image_tag=<commit sha>
   ```

3. Deregister the task definition revisions Jenkins registered. Terraform doesn't know about them, so it won't clean them up:

   ```bash
   for family in jsp-staging-api jsp-production-api; do
     for arn in $(aws ecs list-task-definitions --family-prefix "$family" --status ACTIVE --query 'taskDefinitionArns[]' --output text); do
       aws ecs deregister-task-definition --task-definition "$arn" > /dev/null
     done
   done
   ```

4. Stop the Jenkins host. Stopping keeps the Jenkins and SonarQube data, and the next session just starts it again.

   ```bash
   aws ec2 stop-instances --instance-ids "$(terraform -chdir=infra/ci output -raw jenkins_instance_id)"
   ```

5. Check that nothing billable is left, for example with `aws rds describe-db-instances`, `aws elbv2 describe-load-balancers` and `aws ec2 describe-vpc-endpoints`.

To remove absolutely everything, go in reverse order: destroy `infra/ci`, then delete the images and destroy `infra/shared`, and finally destroy `infra/bootstrap` after lifting its `prevent_destroy`, moving its state back to a local file and emptying the versioned bucket.

## Cost

Prices for us-east-1, checked in September 2026.

| Resource | Cost | When |
|---|---|---|
| Jenkins host (t3a.large and its public IPv4) | about 0.08 USD/h | While running; stopped between sessions |
| Jenkins volume (40 GB gp3) | 3.20 USD/month | Always, also while stopped |
| One environment | about 0.15 USD/h | While it exists |
| Fixed | about 1.50 USD/month | KMS key, state bucket, ECR storage |

The biggest part of an environment's cost is the four interface endpoints in two zones (0.08 USD/h). The rest is the load balancer (about 0.03 USD/h), RDS db.t3.micro (about 0.02 USD/h), the Fargate task and the load balancer's public IPs. Alarms cost 0.10 USD per alarm metric per month, prorated by the hour. A four-hour session with Jenkins and both environments comes to about 1.50 USD. A NAT gateway would have added about 0.045 USD/h per zone plus data processing. A 20 USD monthly AWS budget in the management account keeps an eye on the total.
