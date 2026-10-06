# SonarQube quality gate

SonarQube Community Build analyzes `app/src` on every `dev` build, and the `Quality gate` stage waits for the result through a webhook and fails the build when the gate fails. The gate is the built-in Sonar way, which judges new code: no new issues, at least 80% coverage and at most 3% duplication. The coverage and duplication conditions are ignored while there are fewer than 20 new lines.

State of the project on 2026-10-06, from the SonarQube web API:

```text
quality gate: OK

condition                      fails when    result
new_coverage                   < 80 %        OK
new_duplicated_lines_density   > 3 %         OK
new_violations                 > 0           OK (0)

bugs                    0
vulnerabilities         0
code smells             0
security hotspots       0
coverage             87.1 %   (unit and integration tests)
duplicated lines      0.0 %
lines of code         244
```

What each number means:

- **Bugs**: code that is likely wrong at runtime.
- **Vulnerabilities**: code that is exploitable as written.
- **Security hotspots**: security-sensitive code that a person has to review; it is not a confirmed problem.
- **Code smells**: maintainability issues.
- **Coverage**: lines executed by tests. Both suites produce LCOV reports, and SonarQube combines them.

The gate failed once on purpose during the project: a value generated with `Math.random()` raised rule S2245 (pseudorandom number generator where unpredictability matters), the build stopped, and the fix used `randomUUID()` from `node:crypto`.
