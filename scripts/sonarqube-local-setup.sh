#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../jenkins/secrets"

sonar_url="http://127.0.0.1:9000"
project_key="jenkins-secure-pipeline"
webhook_url="http://controller:8080/sonarqube-webhook/"

api() {
  local method=$1 path=$2
  shift 2
  printf 'user = "%s:%s"\n' "$user" "$password" | curl -fsS -K - -X "$method" "$sonar_url/api/$path" "$@"
}

if [[ "$(curl -fsS "$sonar_url/api/system/status")" != *'"status":"UP"'* ]]; then
  echo "sonarqube is not up, run: docker compose -f jenkins/docker-compose.yml up -d --wait sonarqube" >&2
  exit 1
fi

user=admin
password=admin
if [[ "$(api GET authentication/validate)" == *'"valid":true'* ]]; then
  api POST users/change_password -d login=admin -d previousPassword=admin \
    --data-urlencode password@sonarqube_admin_password
  echo "default admin password replaced"
fi

password="$(cat sonarqube_admin_password)"
if [[ "$(api GET authentication/validate)" != *'"valid":true'* ]]; then
  echo "jenkins/secrets/sonarqube_admin_password does not match the sonarqube admin password" >&2
  exit 1
fi

if [[ "$(api GET "projects/search?projects=$project_key")" != *"\"key\":\"$project_key\""* ]]; then
  api POST projects/create -d "project=$project_key" -d "name=$project_key" \
    -d mainBranch=dev -d visibility=private > /dev/null
  echo "project $project_key created"
fi

token_is_valid() {
  [ -s sonarqube_token ] || return 1
  local user password
  user="$(cat sonarqube_token)"
  password=""
  [[ "$(api GET authentication/validate)" == *'"valid":true'* ]]
}

if ! token_is_valid; then
  if [[ "$(api GET user_tokens/search)" == *'"name":"jenkins"'* ]]; then
    api POST user_tokens/revoke -d name=jenkins
  fi
  response="$(api POST user_tokens/generate -d name=jenkins \
    -d type=PROJECT_ANALYSIS_TOKEN -d "projectKey=$project_key")"
  [[ $response =~ \"token\":\"([^\"]+)\" ]] || { echo "unexpected token response" >&2; exit 1; }
  printf '%s' "${BASH_REMATCH[1]}" > sonarqube_token
  echo "analysis token written to jenkins/secrets/sonarqube_token"
fi

if [[ "$(api GET "webhooks/list?project=$project_key")" != *'"name":"jenkins"'* ]]; then
  api POST webhooks/create -d name=jenkins -d "project=$project_key" \
    --data-urlencode "url=$webhook_url" --data-urlencode secret@sonarqube_webhook_secret > /dev/null
  echo "webhook to $webhook_url created"
fi

echo "sonarqube ready, start or restart the jenkins controller to load the token"
