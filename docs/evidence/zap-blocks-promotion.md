# ZAP blocks a promotion

Dev builds #9 and #10, 2026-10-02. ZAP runs a passive baseline scan against the API deployed in staging. `zap/baseline.conf` sets ten clear, cheap-to-fix rules to FAIL, and every other rule stays at WARN, which is reported without failing the build.

Build #9 deployed commit `cbfd3d5` to staging and passed the smoke test, then ZAP found two FAIL rules: Express announced itself with `X-Powered-By`, and responses lacked `X-Content-Type-Options: nosniff`. The build stopped before the production approval.

```text
registered jsp-staging-api:7 with jsp-api:cbfd3d5b6616...
+ health={"status":"ok"}
FAIL-NEW: X-Content-Type-Options Header Missing [10021] x 1
FAIL-NEW: Server Leaks Information via "X-Powered-By" HTTP Response Header Field(s) [10037] x 4
FAIL-NEW: 2	FAIL-INPROG: 0	WARN-NEW: 0	WARN-INPROG: 0	INFO: 0	IGNORE: 0	PASS: 59
ERROR: script returned exit code 1
Finished: FAILURE
```

Report excerpt (archived with the build):

```text
Summary of Alerts: High 0, Medium 0, Low 2

[Low] Server Leaks Information via "X-Powered-By" HTTP Response Header Field(s)
  Plugin Id 10037, CWE 497, 4 instances, evidence "X-Powered-By: Express"
  GET /  /robots.txt  /sitemap.xml  /users

[Low] X-Content-Type-Options Header Missing
  Plugin Id 10021, CWE 693, 1 instance
  GET /users
```

Commit `c9c53af` added helmet and an integration test for the headers. Build #10 passed:

```text
registered jsp-staging-api:8 with jsp-api:c9c53af65af9...
PASS: X-Content-Type-Options Header Missing [10021]
PASS: Server Leaks Information via "X-Powered-By" HTTP Response Header Field(s) [10037]
FAIL-NEW: 0	FAIL-INPROG: 0	WARN-NEW: 0	WARN-INPROG: 0	INFO: 0	IGNORE: 0	PASS: 61
Finished: SUCCESS
```

Response headers on staging after the fix (`GET /users`):

```text
HTTP/1.1 200 OK
Content-Security-Policy: default-src 'self';base-uri 'self';font-src 'self' https: data:;form-action 'self';frame-ancestors 'self';img-src 'self' data:;object-src 'none';script-src 'self';script-src-attr 'none';style-src 'self' https: 'unsafe-inline';upgrade-insecure-requests
Referrer-Policy: no-referrer
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-Frame-Options: SAMEORIGIN
```

Both findings are rated Low by ZAP. They fail the build anyway because they leak information about the stack, cost one line to fix, and would be easy to reintroduce.
