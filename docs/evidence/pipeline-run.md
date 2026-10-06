# A full pipeline run

Dev build #19, commit `1e60116` (2026-10-06): every stage passed, a person approved the promotion, and production received the image staging had tested. Stage durations come from the Jenkins pipeline graph.

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

Every image is tagged with its commit SHA, so the running task definition answers that question. Later the same day, after three more commits went through staging without being approved for production:

```text
staging     jsp-staging-api:25     jsp-api:2f51a4c69a7d  sha256:0c3499f8fea2...  2f51a4c fix: tighten jenkins permissions
production  jsp-production-api:6   jsp-api:1e601167cc85  sha256:2302da1283e6...  1e60116 fix: update distroless base image
```

Staging runs the newest commit. Production still runs `1e60116`, the last one a person approved.
