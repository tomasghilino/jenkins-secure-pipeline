# Checkov blocks an open database port

A throwaway branch, `demo-checkov-open-db`, added a security group rule that opened PostgreSQL (5432) on the database to `0.0.0.0/0`. Checkov's built-in checks catch 0.0.0.0/0 on ports 22 and 80 but not on 5432, so the repository adds a custom policy, `CKV2_JSP_1` in `checkov/internet_ingress.yaml`: an ingress rule open to the internet must be exactly port 80 or 443.

The branch build failed at `Checkov` and skipped `Docker build`, so nothing was packaged. The next commit on the branch removed the rule and the build passed. The branch was deleted afterwards.

![Jenkins build of the demo branch failing at the Checkov stage with CKV2_JSP_1](checkov-blocks-open-database.png)
