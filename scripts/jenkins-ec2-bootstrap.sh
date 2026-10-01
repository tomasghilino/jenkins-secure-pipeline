#!/usr/bin/env bash
set -euo pipefail

# runs as root on the jenkins ec2 host through ssm run command, safe to run again after a push
repo_url=git@github.com:tomasghilino/jenkins-secure-pipeline.git
repo_dir=/opt/jsp
deploy_key=/root/.ssh/jsp-deploy-key
known_hosts=/root/.ssh/jsp-known-hosts

install -d -m 700 /root/.ssh
if [ ! -f "$deploy_key" ]; then
  ssh-keygen -q -t ed25519 -N "" -C jenkins-ec2-deploy -f "$deploy_key"
fi
echo "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl" > "$known_hosts"
export GIT_SSH_COMMAND="ssh -i $deploy_key -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$known_hosts"

if ! git ls-remote "$repo_url" HEAD > /dev/null; then
  echo "add this public key as a read-only deploy key on github, then run the bootstrap again:" >&2
  cat "$deploy_key.pub" >&2
  exit 1
fi

if [ -d "$repo_dir/.git" ]; then
  git -C "$repo_dir" pull --ff-only
else
  git clone --branch dev "$repo_url" "$repo_dir"
fi
cd "$repo_dir"

secrets=jenkins/secrets
mkdir -p "$secrets"
install -m 600 "$deploy_key" "$secrets/github_deploy_key"
install -m 644 "$deploy_key.pub" "$secrets/github_deploy_key.pub"
scripts/jenkins-local-secrets.sh

# the containers run as non-root users that read their bind-mounted secret files, the 700 directory keeps other host users out
open_secrets() {
  chmod 700 "$secrets"
  chmod 644 "$secrets"/*
}

compose() {
  docker compose --progress quiet -f jenkins/docker-compose.yml -f jenkins/docker-compose.ec2.yml "$@"
}

open_secrets
compose build
compose up -d --wait sonarqube
scripts/sonarqube-local-setup.sh
open_secrets

# brings the stack back after a stop and start of the instance, and stops it cleanly before docker on shutdown
cat > /etc/systemd/system/jenkins-stack.service <<EOF
[Unit]
Description=Jenkins and SonarQube containers
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$repo_dir
ExecStart=/usr/bin/docker compose -f jenkins/docker-compose.yml -f jenkins/docker-compose.ec2.yml up -d --wait
ExecStop=/usr/bin/docker compose -f jenkins/docker-compose.yml -f jenkins/docker-compose.ec2.yml stop -t 60
TimeoutStartSec=900
TimeoutStopSec=180

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now jenkins-stack.service
compose up -d --wait
echo "jenkins stack is up, open it with scripts/jenkins-tunnel.sh"
