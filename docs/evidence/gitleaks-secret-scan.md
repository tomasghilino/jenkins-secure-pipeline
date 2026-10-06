# Gitleaks blocks a committed token

The `Secret scan` stage runs Gitleaks on the commit being built, before anything is installed or built. To show the gate without putting a credential in this repository's history, the same pinned image and command ran against a throwaway repository whose second commit adds a GitHub personal access token. The token was random characters with the `ghp_` prefix and was never valid.

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

In the pipeline that exit code fails the build, so no later stage runs. `--redact` keeps the secret out of the Jenkins log, and `--network none` keeps the scanner offline. The same check ran in the pipeline during the project on a throwaway branch with fake AWS keys, which was deleted afterwards.
