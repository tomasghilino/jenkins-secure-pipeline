# ZAP blocks a promotion

Dev builds #9 and #10, October 2, 2026.

The other scanners read code, dependencies or images. ZAP is different: it talks to the running app in staging over HTTP, like a visitor would, and looks at what comes back. The pipeline runs ZAP's baseline scan, which is passive. It browses the API and inspects the responses, but it doesn't attack anything.

ZAP has dozens of rules. In `zap/baseline.conf` I set ten of them to FAIL, all clear problems that are cheap to fix. Everything else stays at WARN, which shows up in the report without breaking the build. If every informational finding blocked a deploy, people would quickly learn to ignore the scanner.

## Build #9: blocked

Build #9 deployed commit `cbfd3d5` to staging and passed the smoke test. Then ZAP found two FAIL rules:

- Express announced itself in every response with `X-Powered-By: Express`. It's like a sign on the door telling a burglar which alarm brand you have.
- Responses were missing `X-Content-Type-Options: nosniff`. Without it, a browser may ignore the content type the server declared and guess it from the body. If a user's name contained a script, a browser that guesses could treat the `/users` response as a page and run it.

The build stopped before the production approval:

```text
registered jsp-staging-api:7 with jsp-api:cbfd3d5b6616...
+ health={"status":"ok"}
FAIL-NEW: X-Content-Type-Options Header Missing [10021] x 1
FAIL-NEW: Server Leaks Information via "X-Powered-By" HTTP Response Header Field(s) [10037] x 4
FAIL-NEW: 2	FAIL-INPROG: 0	WARN-NEW: 0	WARN-INPROG: 0	INFO: 0	IGNORE: 0	PASS: 59
ERROR: script returned exit code 1
Finished: FAILURE
```

Report excerpt, archived with the build:

```text
Summary of Alerts: High 0, Medium 0, Low 2

[Low] Server Leaks Information via "X-Powered-By" HTTP Response Header Field(s)
  Plugin Id 10037, CWE 497, 4 instances, evidence "X-Powered-By: Express"
  GET /  /robots.txt  /sitemap.xml  /users

[Low] X-Content-Type-Options Header Missing
  Plugin Id 10021, CWE 693, 1 instance
  GET /users
```

## Build #10: fixed

Commit `c9c53af` added helmet, a small Express middleware that sets secure headers and removes `X-Powered-By`, plus an integration test that checks the headers, so they can't quietly disappear later. Build #10 passed:

```text
registered jsp-staging-api:8 with jsp-api:c9c53af65af9...
PASS: X-Content-Type-Options Header Missing [10021]
PASS: Server Leaks Information via "X-Powered-By" HTTP Response Header Field(s) [10037]
FAIL-NEW: 0	FAIL-INPROG: 0	WARN-NEW: 0	WARN-INPROG: 0	INFO: 0	IGNORE: 0	PASS: 61
Finished: SUCCESS
```

These are the response headers on staging after the fix (`GET /users`):

```text
HTTP/1.1 200 OK
Content-Security-Policy: default-src 'self';base-uri 'self';font-src 'self' https: data:;form-action 'self';frame-ancestors 'self';img-src 'self' data:;object-src 'none';script-src 'self';script-src-attr 'none';style-src 'self' https: 'unsafe-inline';upgrade-insecure-requests
Referrer-Policy: no-referrer
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-Frame-Options: SAMEORIGIN
```

ZAP rates both findings as Low. I still made them fail the build because they give away information about the stack, each one takes a line to fix, and they're easy to bring back by accident.
