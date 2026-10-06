# Evidence

Excerpts from real builds and controlled failures, with account IDs, hostnames and secrets removed. Each file shows one control doing its job.

| File | What it shows |
|---|---|
| [pipeline-run.md](pipeline-run.md) | A full run with every stage and its duration, and which commit runs in each environment |
| [gitleaks-secret-scan.md](gitleaks-secret-scan.md) | Gitleaks failing on a committed token |
| [sonarqube-quality-gate.md](sonarqube-quality-gate.md) | The quality gate, its conditions and the project's numbers |
| [checkov-blocks-open-database.md](checkov-blocks-open-database.md) | A custom Checkov policy stopping a branch that opened the database to the internet |
| [trivy-base-image-update.md](trivy-base-image-update.md) | The Trivy gate, an accepted finding with an expiry date, and the signed base image that cleared it |
| [zap-blocks-promotion.md](zap-blocks-promotion.md) | ZAP stopping a build before the approval, and the fix |
| [production-promotion.md](production-promotion.md) | An approved promotion where production runs the image digest staging tested |
| [ecs-rollback.md](ecs-rollback.md) | The ECS circuit breaker rolling back a deployment that never became healthy |
| [cloudwatch-alarms.md](cloudwatch-alarms.md) | Both alarms firing during three controlled failures, the logs behind them, and an alarm design that was dropped |
| [jenkins-iam-review.md](jenkins-iam-review.md) | The IAM review of the account and the permissions removed from Jenkins |
| [terraform-module-refactor.md](terraform-module-refactor.md) | The move to a Terraform module, proven by comparing plans |
