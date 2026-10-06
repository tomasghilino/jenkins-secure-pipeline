# Production receives the image staging tested

Dev build #15, commit `6b1890b`, 2026-10-05. One build validated the code, deployed staging, passed the smoke test and ZAP, waited for a person, and then deployed the same image to production.

```text
Deploy this image to production?
Approved by admin
admin approved <registry>/jsp-api:6b1890b4dcfb... for production
[Pipeline] { (Deploy production)
registered jsp-production-api:2 with <registry>/jsp-api:6b1890b4dcfb...
[Pipeline] { (Verify production)
Finished: SUCCESS
```

The digests of the running tasks (`aws ecs describe-tasks`) match each other and the ECR tag (`aws ecr describe-images`), so production runs the exact bytes staging tested:

| Where | Revision | Image digest |
|---|---|---|
| staging | jsp-staging-api:15 | sha256:4988f943015fd30300070212456b2fba324b20706d003d4469a787122169acb5 |
| production | jsp-production-api:2 | sha256:4988f943015fd30300070212456b2fba324b20706d003d4469a787122169acb5 |
| ECR tag `6b1890b` | | sha256:4988f943015fd30300070212456b2fba324b20706d003d4469a787122169acb5 |

An approval that is aborted or left unanswered for 30 minutes ends the build, and production keeps what it was running.
