# SonarQube quality gate

SonarQube reads the code in `app/src` on every `dev` build and decides whether it passes a quality gate. Jenkins waits for that answer, which SonarQube sends back through a webhook, and fails the build if the gate fails.

I use the built-in gate, Sonar way. It only judges new code, which is how most teams use it: you don't have to fix every old problem before shipping, but a new change can't make things worse. The conditions are no new issues, at least 80% test coverage and at most 3% duplicated lines. Coverage and duplication are skipped when a change has fewer than 20 new lines, so a one-line fix isn't blocked by a percentage.

Here's the project on October 6, 2026, from the SonarQube web API:

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

What each number means, in plain words:

- Bugs are code that will probably do the wrong thing when it runs.
- Vulnerabilities are code that someone could exploit as it is written.
- Security hotspots are places that touch something sensitive and need a person to look at them. They aren't confirmed problems.
- Code smells don't break anything today, but they make the code harder to maintain.
- Coverage is the share of lines the tests actually run. The unit and integration tests each produce a report, and SonarQube merges them.

## The time it failed

I broke the gate on purpose once. A value was generated with `Math.random()`, and SonarQube raised rule S2245: `Math.random()` is predictable, so it shouldn't be used where a value needs to be hard to guess. The build stopped at the quality gate. The fix was `randomUUID()` from `node:crypto`, which uses a cryptographically secure generator.
