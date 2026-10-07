# Gitleaks blocks a committed token

The first real stage of the pipeline, `Secret scan`, runs Gitleaks before anything gets installed or built. It reads the whole history up to the commit being built, not only the latest change. That matters because deleting a secret in a later commit doesn't remove it from Git: anyone who clones the repository can still find it.

I didn't want a credential in this repository's history, not even a fake one. So for this demo I ran the exact same pinned image and command against a throwaway repository whose second commit adds a GitHub personal access token. The token was random characters with the `ghp_` prefix and was never valid.

```text
$ docker run --rm -v "$PWD:/repo" -w /repo --network none --entrypoint= \
    ghcr.io/gitleaks/gitleaks:v8.30.1@sha256:c00b6bd0... \
    gitleaks git --redact --verbose --no-banner --log-opts=HEAD .
INF 2 commits scanned.
WRN leaks found: 1
Finding:     githubToken: "REDACTED",
Secret:      REDACTED
RuleID:      github-pat
Entropy:     4.821928
File:        config.ts
Line:        3
Commit:      <sha>
Author:      demo
Date:        2026-10-06T17:27:16Z
Fingerprint: <sha>:config.ts:github-pat:3

exit code 1
```

Gitleaks exits with code 1, and in Jenkins that fails the build, so nothing after it runs. Two flags are worth pointing out. `--redact` hides the secret in the output, so the token doesn't end up copied into the Jenkins log, and `--network none` runs the scanner with no network access at all.

During the project I also ran the same check inside the real pipeline, on a throwaway branch with fake AWS keys, and deleted the branch afterwards.
