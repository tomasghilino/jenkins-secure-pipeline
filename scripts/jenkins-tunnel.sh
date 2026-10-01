#!/usr/bin/env bash
set -euo pipefail

# usage: scripts/jenkins-tunnel.sh [jenkins|sonarqube]
service=${1:-jenkins}
case $service in
  jenkins) remote_port=8080; local_port=18080 ;;
  sonarqube) remote_port=9000; local_port=19000 ;;
  *) echo "usage: $0 [jenkins|sonarqube]" >&2; exit 1 ;;
esac

instance_id=$(aws ec2 describe-instances \
  --filters Name=tag:Name,Values=jsp-ci-jenkins Name=instance-state-name,Values=running \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)

if [ "$instance_id" = "None" ]; then
  echo "jsp-ci-jenkins is not running" >&2
  exit 1
fi

echo "$service on http://127.0.0.1:$local_port (ctrl+c to close)"
exec aws ssm start-session --target "$instance_id" \
  --document-name AWS-StartPortForwardingSession \
  --parameters "portNumber=$remote_port,localPortNumber=$local_port"
