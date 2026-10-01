#!/bin/bash
set -euo pipefail

# sonarqube's elasticsearch refuses to start below this
echo 'vm.max_map_count = 262144' > /etc/sysctl.d/90-sonarqube.conf
sysctl --system

dnf install -y docker git
systemctl enable --now docker

# al2023 ships docker without the compose and buildx plugins; hashes pinned after a cosign check of the release signatures
compose_version=5.5.1
compose_sha256=db1889184726840f75c4f9c001048430d4f25b3be3cb084d3ddd762bc0aed576
buildx_version=0.37.2
buildx_sha256=982ca20490b45ed1ec8d99795974d3d874a358f75938c9c237305010e6b7e548

download=$(mktemp -d)
curl -fsSL -o "$download/docker-compose" "https://github.com/docker/compose/releases/download/v$compose_version/docker-compose-linux-x86_64"
curl -fsSL -o "$download/docker-buildx" "https://github.com/docker/buildx/releases/download/v$buildx_version/buildx-v$buildx_version.linux-amd64"
echo "$compose_sha256  $download/docker-compose" | sha256sum -c -
echo "$buildx_sha256  $download/docker-buildx" | sha256sum -c -

plugins=/usr/local/lib/docker/cli-plugins
mkdir -p "$plugins"
install -m 755 "$download/docker-compose" "$download/docker-buildx" "$plugins/"
rm -rf "$download"
