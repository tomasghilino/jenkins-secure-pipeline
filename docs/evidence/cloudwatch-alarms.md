# CloudWatch alarms and logs under failure

Each environment has two alarms that email a subscribed address through the shared SNS topic `jsp-alarms`: `<env>-http-5xx` (5 or more 5xx responses in a minute, from the API or from the load balancer) and `<env>-no-healthy-targets` (no task passing the health check for two minutes). Three controlled failures on staging on 2026-10-06 tested them, and each one was undone right after: demo revisions deregistered and deleted, desired count restored.

## 1. Healthy for the load balancer, broken for users

A revision with a wrong database name. `/health` does not touch the database, so ECS and the circuit breaker considered the deployment healthy.

```text
15:39:50  registered jsp-staging-api:22 with PGDATABASE=does-not-exist
15:42:36  service settled on jsp-staging-api:22
15:42:40  /health -> 200
15:42:40  /users x30 -> 500 500 500 ... (30 times)
15:45:20  jsp-staging-http-5xx      OK -> ALARM   (email sent)
15:45:27  restoring jsp-staging-api:21
15:48:20  jsp-staging-http-5xx      ALARM -> OK   (email sent), /users -> 200
```

The API logs, queried with Logs Insights, show the cause and every failed request. The client only received a generic 500 body.

```text
{"level":"error","pid":1,"timestamp":1791301432457,"message":"error: database \"does-not-exist\" does not exist\n    at /app/node_modules/pg-pool/index.js:45:11 ..."}
{"level":"error","pid":1,"timestamp":1791301432457,"message":{"method":"GET","path":"/users","status":500,"durationMs":19,"traceId":"Root=1-6ac51738-744a1540223785b313ea2089"},"context":"HTTP"}
```

A normal request looks like this:

```text
{"level":"log","pid":1,"timestamp":1791306781643,"message":{"method":"GET","path":"/users","status":200,"durationMs":8,"traceId":"Root=1-6ac52c1d-31ed06ae7dad1a240d0615bc"},"context":"HTTP"}
```

## 2. A bad deployment, and why an unhealthy-target alarm was dropped

A revision listening on port 3001 while the load balancer checks 3000. The circuit breaker rolled it back and the old task kept serving the whole time, but the first design of the second alarm, `UnHealthyHostCount >= 1`, never fired. ECS stops a task 34 ms after the load balancer marks it unhealthy, and the per-minute sample never sees it.

```text
16:03:17.987  (task 3825...) (port 3000) is unhealthy in target-group jsp-staging-app
16:03:18.021  (service api) has stopped 1 running tasks
16:03:40      deployment failed: tasks failed to start, rolling back
UnHealthyHostCount, maximum per minute: 0 for every minute of the demo
```

The alarm was replaced by `HealthyHostCount < 1` for two minutes, which is what users notice. A failed rollout is already reported by the red Jenkins build and undone by the circuit breaker.

## 3. Outage: the service runs no task

```text
16:13:12  desired/running 0/0
16:13:14  /users x10 -> 503 (the load balancer has no target)
16:16:20  jsp-staging-http-5xx              OK -> ALARM   (email sent)
16:18:20  jsp-staging-http-5xx              ALARM -> OK   (no more requests)
16:21:39  desired count back to 1
16:22:33  jsp-staging-no-healthy-targets    OK -> ALARM   (email sent)
16:25:33  jsp-staging-no-healthy-targets    ALARM -> OK   (email sent)
```

With traffic, the 5xx alarm caught the outage in about 3 minutes. With no target registered, the load balancer stops publishing `HealthyHostCount`. The alarm treats missing data as breaching, but CloudWatch first waits for late data, so it fired about 9 minutes after the last datapoint. Filling the gap with zeros (`FILL`) would react sooner, but a datapoint that arrives late would then raise a false alarm. The delay is accepted: the 5xx alarm is the fast signal, and the healthy-target alarm is the backstop when nobody is calling the API.
