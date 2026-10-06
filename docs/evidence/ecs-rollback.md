# ECS rolls back a deployment that never becomes healthy

Staging, 2026-10-05. A throwaway Jenkins job, never committed, ran the real deploy steps of the Jenkinsfile with one planted misconfiguration.

**What failed.** Revision `jsp-staging-api:16` used the same image as the healthy revision 15 but set `PORT=3001`, so the API listened on 3001 while the load balancer health check targets port 3000.

**How ECS detected it.** The ALB health check (`GET /health` every 15 s, unhealthy after 3 failures) marked each new task `unhealthy` with reason `Target.FailedHealthChecks`. ECS stopped every unhealthy task and launched another one. After the third consecutive failure, the deployment circuit breaker marked the deployment `FAILED`.

**What the rollback did.** ECS started a rollback deployment to the last deployment in `COMPLETED` state (revision 15) and drained the failed one. Revision 15 never stopped serving, because a rolling deployment keeps the old task until a new one is healthy.

**How the healthy version was restored.** About 8 minutes after the bad deployment started, the service ran only revision 15 again, in `COMPLETED` state. Jenkins saw that the service did not run the revision it had deployed, failed the build at `Roll out service`, printed the ECS events and skipped every later stage, so this image could never reach the production approval. `/health` answered 200 in all 64 checks taken during the demo.

Timeline from an observer polling every 10 seconds (local time, UTC-3):

| Time | ECS deployments | Load balancer target of the new task |
|---|---|---|
| 18:31:55 | rev 15 COMPLETED, 1 task running | |
| 18:33:24 | rev 16 IN_PROGRESS starts, rev 15 keeps running | |
| 18:34:55 | rev 16, first task | unhealthy, `Target.FailedHealthChecks` |
| 18:35:06 | rev 16 failed tasks: 1 | draining |
| 18:37:33 | rev 16, second task | unhealthy |
| 18:37:45 | rev 16 failed tasks: 2 | draining |
| 18:40:11 | rev 16, third task | unhealthy |
| 18:40:22 | rev 16 failed tasks: 3 | draining |
| 18:40:34 | rev 16 FAILED, rollback to rev 15 IN_PROGRESS | |
| 18:41:19 | rev 15 COMPLETED, the only deployment left | |

Jenkins console excerpt, ECS events newest first (UTC):

```text
the circuit breaker rolled the service back to jsp-staging-api:15, jsp-staging-api:16 never became healthy
21:41:16 (service api) has reached a steady state.
21:41:16 (service api) (deployment ecs-svc/...4098612) deployment completed.
21:40:29 (service api) rolling back to deployment ecs-svc/...4098612.
21:40:29 (service api) (deployment ecs-svc/...0067525) deployment failed: tasks failed to start.
21:40:24 (service api, taskSet ecs-svc/...0067525) has begun draining connections on 1 tasks.
21:40:14 (service api) deregistered 1 targets in (target-group jsp-staging-app)
21:40:13 (service api) has stopped 1 running tasks: (task c2b4bdea...).
21:40:13 (service api) (task c2b4bdea...) (port 3000) is unhealthy in (target-group jsp-staging-app) due to (reason Health checks failed).
Stage "Smoke test" skipped due to earlier failure(s)
Finished: FAILURE
```

ECS words the circuit breaker failure as "tasks failed to start" both for tasks that never start and for tasks that fail their health checks.

## Second occurrence: a real pipeline build (dev #16)

The deploy step copies the latest active revision of the task definition family and swaps only the image. The demo left its planted revision 16 as the latest one, so the next real build registered revision 17 with the new image but the same `PORT=3001`. The circuit breaker rolled staging back again, and the pipeline stopped before the production approval:

```text
the circuit breaker rolled the service back to jsp-staging-api:15, jsp-staging-api:17 never became healthy
(service api) (deployment ecs-svc/...5720898) deployment failed: tasks failed to start.
(service api) rolling back to deployment ecs-svc/...2654050.
Stage "Smoke test" skipped due to earlier failure(s)
Stage "ZAP baseline" skipped due to earlier failure(s)
Stage "Approve production" skipped due to earlier failure(s)
Stage "Deploy production" skipped due to earlier failure(s)
Stage "Verify production" skipped due to earlier failure(s)
Finished: FAILURE
```

Production stayed on `jsp-production-api:2`. Deregistering revisions 16 and 17 made revision 15 the latest active one again, and a new build of the same commit deployed normally. Lesson: a revision changed outside Terraform must be deregistered, because the pipeline builds every new revision on top of the latest one.
