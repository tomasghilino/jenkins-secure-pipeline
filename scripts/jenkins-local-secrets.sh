#!/usr/bin/env bash
set -euo pipefail

jenkins_dir="$(cd "$(dirname "$0")/../jenkins" && pwd)"
secrets_dir="$jenkins_dir/secrets"
mkdir -p "$secrets_dir"

if [ ! -f "$secrets_dir/agent_ssh_key" ]; then
  ssh-keygen -q -t ed25519 -N "" -C jenkins-agent -f "$secrets_dir/agent_ssh_key"
fi

if [ ! -f "$secrets_dir/github_deploy_key" ]; then
  ssh-keygen -q -t ed25519 -N "" -C jenkins-secure-pipeline-deploy -f "$secrets_dir/github_deploy_key"
fi

if [ ! -f "$secrets_dir/jenkins_admin_password" ]; then
  openssl rand -base64 24 | tr -d '\r\n' > "$secrets_dir/jenkins_admin_password"
fi

if [ ! -f "$secrets_dir/sonarqube_admin_password" ]; then
  password=""
  # sonarqube rejects passwords without upper, lower, digit and special characters
  until [[ $password =~ [[:upper:]] && $password =~ [[:lower:]] && $password =~ [[:digit:]] && $password =~ [^[:alnum:]] ]]; do
    password="$(openssl rand -base64 24 | tr -d '\r\n')"
  done
  printf '%s' "$password" > "$secrets_dir/sonarqube_admin_password"
fi

if [ ! -f "$secrets_dir/sonarqube_db_password" ]; then
  openssl rand -hex 32 | tr -d '\r\n' > "$secrets_dir/sonarqube_db_password"
fi

if [ ! -f "$secrets_dir/sonarqube_webhook_secret" ]; then
  openssl rand -hex 32 | tr -d '\r\n' > "$secrets_dir/sonarqube_webhook_secret"
fi

printf 'sonar.jdbc.password=%s\n' "$(cat "$secrets_dir/sonarqube_db_password")" > "$secrets_dir/sonarqube.properties"
printf 'JENKINS_AGENT_SSH_PUBKEY=%s\n' "$(cat "$secrets_dir/agent_ssh_key.pub")" > "$jenkins_dir/.env"
echo "local jenkins secrets ready in $secrets_dir"
