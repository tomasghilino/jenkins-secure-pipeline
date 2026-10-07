# CloudWatch alarms and logs under failure

Each environment has two alarms, and both send an email through the shared SNS topic `jsp-alarms`:

- `<env>-http-5xx` goes off when there are 5 or more 5xx responses in a minute, whether they come from the API or from the load balancer.
- `<env>-no-healthy-targets` goes off when no task has passed the health check for two minutes.

To test them I broke staging in three different ways on October 6, 2026, and undid each one right after (demo revisions deregistered and deleted, desired count restored).

## 1. Healthy for the load balancer, broken for users

This is the sneaky one. I deployed a revision with the wrong database name. `/health` doesn't touch the database, so the load balancer and the ECS circuit breaker thought everything was fine, while every request that needed the database returned a 500.

```text
15:39:50  registered jsp-staging-api:22 with PGDATABASE=does-not-exist
15:42:36  service settled on jsp-staging-api:22
15:42:40  /health -> 200
15:42:40  /users x30 -> 500 500 500 ... (30 times)
15:45:20  jsp-staging-http-5xx      OK -> ALARM   (email sent)
15:45:27  restoring jsp-staging-api:21
15:48:20  jsp-staging-http-5xx      ALARM -> OK   (email sent), /users -> 200
```

The alarm fired less than three minutes after the errors started, and went back to OK once the previous revision was back. A rollback can't catch this case, because the deployment looks healthy, so this is the case the 5xx alarm is for.

The client only got a generic 500 body with no details. The real cause was in the API logs, which I found with Logs Insights:

```text
{"level":"error","pid":1,"timestamp":1791301432457,"message":"error: database \"does-not-exist\" does not exist\n    at /app/node_modules/pg-pool/index.js:45:11 ..."}
{"level":"error","pid":1,"timestamp":1791301432457,"message":{"method":"GET","path":"/users","status":500,"durationMs":19,"traceId":"Root=1-6ac51738-744a1540223785b313ea2089"},"context":"HTTP"}
```

For comparison, a normal request looks like this:

```text
{"level":"log","pid":1,"timestamp":1791306781643,"message":{"method":"GET","path":"/users","status":200,"durationMs":8,"traceId":"Root=1-6ac52c1d-31ed06ae7dad1a240d0615bc"},"context":"HTTP"}
```

Every log line is JSON, so you can filter by status, path or duration. The `traceId` is the `X-Amzn-Trace-Id` header the load balancer adds to each request, which lets you follow one request across the load balancer and the API logs.

## 2. A bad deployment, and an alarm that didn't work

Same trick as the [rollback demo](ecs-rollback.md): a revision listening on port 3001 while the load balancer checks 3000. The circuit breaker rolled it back and the old task kept serving the whole time.

The problem was my first design for the second alarm, `UnHealthyHostCount >= 1`, meaning "alert if any task is unhealthy". It never fired. ECS stops an unhealthy task 34 milliseconds after the load balancer marks it, and a metric that is sampled once per minute never sees it:

```text
16:03:17.987  (task 3825...) (port 3000) is unhealthy in target-group jsp-staging-app
16:03:18.021  (service api) has stopped 1 running tasks
16:03:40      deployment failed: tasks failed to start, rolling back
UnHealthyHostCount, maximum per minute: 0 for every minute of the demo
```

So I replaced it with `HealthyHostCount < 1` for two minutes, which is what users actually care about: is anything serving? A failed rollout is covered anyway, because the Jenkins build goes red and the circuit breaker undoes it.

## 3. Outage: no task running at all

I set the service's desired count to 0, so there was nothing behind the load balancer:

```text
16:13:12  desired/running 0/0
16:13:14  /users x10 -> 503 (the load balancer has no target)
16:16:20  jsp-staging-http-5xx              OK -> ALARM   (email sent)
16:18:20  jsp-staging-http-5xx              ALARM -> OK   (no more requests)
16:21:39  desired count back to 1
16:22:33  jsp-staging-no-healthy-targets    OK -> ALARM   (email sent)
16:25:33  jsp-staging-no-healthy-targets    ALARM -> OK   (email sent)
```

With requests coming in, the 5xx alarm caught the outage in about 3 minutes. The healthy-targets alarm was much slower, and here's why. With no target registered, the load balancer stops publishing `HealthyHostCount` at all. The alarm treats missing data as a problem, but CloudWatch first waits a while in case the data is only late, so it fired about 9 minutes after the last datapoint.

I could make it react sooner by treating missing data as zero (`FILL`), but then any datapoint that arrives late would raise a false alarm. I accepted the delay: the 5xx alarm is the fast signal, and the healthy-targets alarm is the backup for when nobody is calling the API.
