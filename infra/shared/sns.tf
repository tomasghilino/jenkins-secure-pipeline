# every environment sends its alarms here; the stack outlives the environments, so an email confirms its subscription once
# subscriptions are added by hand, which keeps addresses out of the repository and the state
resource "aws_sns_topic" "alarms" {
  #checkov:skip=CKV_AWS_26:alarm messages hold no sensitive data, and cloudwatch cannot publish to a topic encrypted with the aws managed key
  name = "jsp-alarms"
}
