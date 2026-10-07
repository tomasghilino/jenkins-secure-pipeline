# Evidence

These are excerpts from real builds and from failures I caused on purpose, to show that each check actually stops something. Account IDs, hostnames and secrets were removed.

If you only have a few minutes, start with the full pipeline run, then the rollback and the alarms, which are the best stories.

| File | What you'll see |
|---|---|
| [pipeline-run.md](pipeline-run.md) | One complete run, how long each stage took, and how to tell which commit runs in each environment |
| [gitleaks-secret-scan.md](gitleaks-secret-scan.md) | Gitleaks catching a token committed to a repository |
| [sonarqube-quality-gate.md](sonarqube-quality-gate.md) | What the quality gate checks, the project's numbers, and the time it failed |
| [checkov-blocks-open-database.md](checkov-blocks-open-database.md) | A branch that opened the database to the internet, stopped by a custom Checkov policy |
| [trivy-base-image-update.md](trivy-base-image-update.md) | Two vulnerabilities in the base image, why they were accepted for a few weeks, and the update that fixed them |
| [zap-blocks-promotion.md](zap-blocks-promotion.md) | ZAP finding two header problems on staging and stopping the build before the approval |
| [production-promotion.md](production-promotion.md) | Proof that production runs the exact image staging tested |
| [ecs-rollback.md](ecs-rollback.md) | A release that never became healthy, and ECS putting the previous version back by itself |
| [cloudwatch-alarms.md](cloudwatch-alarms.md) | Three outages caused on purpose, the alarm emails, the logs behind them, and an alarm idea that didn't work |
| [jenkins-iam-review.md](jenkins-iam-review.md) | What Jenkins is allowed to do in AWS, and the permissions I removed |
| [terraform-module-refactor.md](terraform-module-refactor.md) | How I proved that moving the Terraform into a module changed nothing |
