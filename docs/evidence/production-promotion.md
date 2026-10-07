# Production receives the image staging tested

Dev build #15, commit `6b1890b`, October 5, 2026.

The point of staging is to test the exact thing that will go to production. If the pipeline rebuilt the image after the approval, production would get a new artifact nobody had tested, even with the same code. So this pipeline builds the image once, and production gets that same image after a person approves it.

In this build a single run validated the code, deployed staging, passed the smoke test and ZAP, waited for me, and then deployed to production:

```text
Deploy this image to production?
Approved by admin
admin approved <registry>/jsp-api:6b1890b4dcfb... for production
[Pipeline] { (Deploy production)
registered jsp-production-api:2 with <registry>/jsp-api:6b1890b4dcfb...
[Pipeline] { (Verify production)
Finished: SUCCESS
```

To prove it was the same image, I compared digests. A digest is a hash of the image's content, so changing a single byte gives a different digest. The running tasks (`aws ecs describe-tasks`) and the ECR tag (`aws ecr describe-images`) all show the same one:

| Where | Revision | Image digest |
|---|---|---|
| staging | jsp-staging-api:15 | sha256:4988f943015fd30300070212456b2fba324b20706d003d4469a787122169acb5 |
| production | jsp-production-api:2 | sha256:4988f943015fd30300070212456b2fba324b20706d003d4469a787122169acb5 |
| ECR tag `6b1890b` | | sha256:4988f943015fd30300070212456b2fba324b20706d003d4469a787122169acb5 |

If the approval is aborted, or nobody answers for 30 minutes, the build ends and production keeps running what it had.
