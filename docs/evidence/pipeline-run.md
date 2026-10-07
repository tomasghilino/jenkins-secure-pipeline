# A full pipeline run

This is dev build #19, commit `1e60116`, from October 6, 2026. Every stage passed, I approved the promotion, and production got the same image staging had tested. The durations come from the Jenkins pipeline graph.

Reading it top to bottom, the first four and a half minutes are checks that don't need AWS at all: secrets, dependencies, tests, code quality, Terraform, and the image with its scans. Staging takes about five more minutes, most of it in `Roll out service`, where ECS starts the new task, waits for it to pass the load balancer health checks and drains the old one. The approval sat there for almost 12 minutes because that's how long I took to click it.

```text
Checkout                   1.3s
Secret scan                4.3s
Node                      52.6s
  Install                   14.8s
  Dependency audit          19.1s
  Lint                       3.7s
  Typecheck                  6.2s
  Unit tests                 4.8s
Integration tests         19.4s
SonarQube                 53.6s
  Analysis                  52.2s
  Quality gate               1.2s
Terraform                 82.0s
  Format and validate       57.6s
  TFLint                    10.4s
  Checkov                   13.6s
Docker build              23.0s
Trivy                     25.0s
  Filesystem scan           10.3s
  Image scan                 8.7s
  SBOM                       0.8s
Push to ECR                9.9s
Deploy staging           268.7s
  Register revision          6.1s
  Migrate database          87.0s
  Roll out service         175.1s
Smoke test                 5.0s
ZAP baseline              32.7s
Approve production       700.9s   (waiting for a person)
Deploy production        243.1s
  Register revision          6.2s
  Migrate database          61.8s
  Roll out service         174.4s
Verify production          5.7s
Finished: SUCCESS
```

## Which commit runs where

Every image is tagged with the commit SHA that built it, so if someone asks "what's running in production right now?", the task definition answers it. Later that same day, two more commits went through staging, and I didn't approve either of them for production:

```text
staging     jsp-staging-api:25     jsp-api:2f51a4c69a7d  sha256:0c3499f8fea2...  2f51a4c fix: tighten jenkins permissions
production  jsp-production-api:6   jsp-api:1e601167cc85  sha256:2302da1283e6...  1e60116 fix: update distroless base image
```

Staging has the newest commit. Production is still on `1e60116`, the last one I approved.
