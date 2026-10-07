# ECS rolls back a deployment that never becomes healthy

Short version: I shipped a release to staging that could never pass its health check. ECS noticed, gave up after three tries and put the previous version back by itself. The old version kept answering requests the whole time, and the pipeline stopped before the bad release got anywhere near production.

## The setup

Every ECS deploy registers a new revision of the task definition, which is a numbered copy of the container settings (image, environment variables, CPU and memory). Staging was running revision 15, healthy.

I registered revision 16 with the same image and one wrong setting, `PORT=3001`. The API started fine, but on port 3001, while the load balancer checks `GET /health` on port 3000. Seen from the load balancer, the new task was dead. The deploy ran from a throwaway Jenkins job that used the real deploy steps of the Jenkinsfile, so nothing of the demo was committed.

## What happened

ECS starts the new task next to the old one and only removes the old one once the new one is healthy. The load balancer calls `/health` every 15 seconds and marks a task unhealthy after 3 failures in a row. This is what an observer polling every 10 seconds saw (local time, UTC-3):

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

Each new task failed its checks, so ECS stopped it and tried another one. After the third failure the deployment circuit breaker tripped. It works like the fuse in a house: instead of retrying forever, it marks the deployment `FAILED` and goes back to the last deployment that completed, revision 15.

The whole thing took about 8 minutes. I called `/health` 64 times during the demo and got a 200 every time, so a user would not have noticed anything.

## What Jenkins did

After a deploy, Jenkins checks which revision the service actually ended up running. It had deployed 16 and the service was back on 15, so the build failed at `Roll out service`, printed the ECS events and skipped every later stage. That image could never reach the production approval.

ECS events from the Jenkins console, newest first (UTC):

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

One confusing detail: ECS says "tasks failed to start" even when the tasks did start and only failed their health checks. It uses the same message for both cases.

## Then it happened again, for real

This part wasn't planned. Jenkins builds each new revision by copying the latest one and swapping only the image. After the demo, the latest revision was still the broken 16, so the next real build (dev #16) registered revision 17 with the new image and the same `PORT=3001`. The circuit breaker rolled staging back again:

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

Production was never touched and stayed on `jsp-production-api:2`. I deregistered revisions 16 and 17, which made 15 the latest one again, and a new build of the same commit deployed normally.

The lesson: if you change a task definition by hand, outside Terraform, clean it up afterwards, because the pipeline builds on top of whatever revision is the latest.
