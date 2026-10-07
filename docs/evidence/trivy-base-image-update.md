# Trivy gate and a base image update

The app runs on a distroless base image, `gcr.io/distroless/nodejs24-debian13:nonroot`, pinned by digest. Distroless means the image has Node.js and the few libraries it needs, and nothing else: no shell and no package manager.

Trivy scans every image the pipeline builds and fails the build on a HIGH or CRITICAL vulnerability that already has a fix (`--ignore-unfixed`). If there's no fix yet, there's nothing to upgrade to, and failing every build would only teach people to ignore the scanner.

## The finding

In late September the base image's `libssl3t64` package had two HIGH CVEs. Debian had already released a fix, but distroless hadn't shipped a new image with it yet, so the gate failed and there was nothing I could update to.

Instead of turning the gate off, I checked whether the vulnerable code could actually be reached in this app. It couldn't: Node.js bundles its own OpenSSL and doesn't link the system library, the image has no shell, and the app has no native addons. So I accepted both CVEs in `.trivyignore` with an expiry date, `exp:2026-10-31`. If I forgot about them, the gate would start failing again on that date by itself.

## The fix

On October 6, 2026 distroless published a fixed image. Before pinning the new digest I checked its signature with cosign, to make sure the image was really built and signed by the distroless project and not by someone with access to the registry:

```text
$ cosign verify gcr.io/distroless/nodejs24-debian13:nonroot@sha256:9eeb7f5887d0... \
    --certificate-oidc-issuer https://accounts.google.com \
    --certificate-identity keyless@distroless.iam.gserviceaccount.com
The following checks were performed on each of these signatures:
  - The cosign claims were validated
  - Existence of the claims in the transparency log was verified offline
  - The code-signing certificate was verified using trusted certificate authority certificates
```

Then I ran the pipeline's gate (`trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1`) on both base images, with the exceptions removed:

```text
== base bb6b03d81066 (old)
gate exit 1
  CVE-2026-75804 libssl3t64 3.5.7-1~deb13u2 -> 3.5.7-1~deb13u3 HIGH
  CVE-2026-84782 libssl3t64 3.5.7-1~deb13u2 -> 3.5.7-1~deb13u3 HIGH
== base 9eeb7f5887d0 (new)
gate exit 0
```

The old base fails with the two CVEs and the new one passes. The API image built on the new base had no HIGH or CRITICAL findings and no secrets. MEDIUM and LOW findings still show up in the build log, they just don't fail the build. The same commit that bumped the digest deleted both exceptions, and I checked that the image still ran as the non-root user (uid 65532) with Node.js 24.21.0.
