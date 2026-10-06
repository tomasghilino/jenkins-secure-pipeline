# Trivy gate and a base image update

The runtime image is `gcr.io/distroless/nodejs24-debian13:nonroot`, pinned by digest. In late September its `libssl3t64` package had two HIGH CVEs with a Debian fix that distroless had not shipped yet. They were accepted in `.trivyignore` with `exp:2026-10-31`, after checking they were not reachable: Node.js bundles its own OpenSSL and does not link the system library, the image has no shell, and there are no native addons. The expiry makes the gate fail again if the exception is forgotten.

On 2026-10-06 distroless published a fixed digest. Its signature was checked before pinning it:

```text
$ cosign verify gcr.io/distroless/nodejs24-debian13:nonroot@sha256:9eeb7f5887d0... \
    --certificate-oidc-issuer https://accounts.google.com \
    --certificate-identity keyless@distroless.iam.gserviceaccount.com
The following checks were performed on each of these signatures:
  - The cosign claims were validated
  - Existence of the claims in the transparency log was verified offline
  - The code-signing certificate was verified using trusted certificate authority certificates
```

The pipeline's gate (`trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1`) on both base images, without the exception:

```text
== base bb6b03d81066 (old)
gate exit 1
  CVE-2026-75804 libssl3t64 3.5.7-1~deb13u2 -> 3.5.7-1~deb13u3 HIGH
  CVE-2026-84782 libssl3t64 3.5.7-1~deb13u2 -> 3.5.7-1~deb13u3 HIGH
== base 9eeb7f5887d0 (new)
gate exit 0
```

The API image built on the new base had no HIGH or CRITICAL findings and no secrets. MEDIUM and LOW findings are reported in the build log without failing it. The commit that bumped the digest also removed both exceptions, and the image still ran as uid 65532 with Node.js 24.21.0.
