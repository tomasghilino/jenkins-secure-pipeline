# the topic lives in the shared stack, so a confirmed email subscription survives every environment rebuild
data "aws_sns_topic" "alarms" {
  name = "jsp-alarms"
}

locals {
  alarm_topics = [data.aws_sns_topic.alarms.arn]
}

# server errors from the api, plus the ones the load balancer returns itself when no task answers
resource "aws_cloudwatch_metric_alarm" "http_5xx" {
  alarm_name          = "${var.name}-http-5xx"
  alarm_description   = "5 or more 5xx responses in a minute, from the api or from the load balancer"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 5
  # one bad minute raises the alarm and two clean minutes clear it, so it does not flap
  evaluation_periods  = 2
  datapoints_to_alarm = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_topics
  ok_actions          = local.alarm_topics

  metric_query {
    id          = "errors"
    label       = "5xx responses"
    expression  = "FILL(api, 0) + FILL(alb, 0)"
    return_data = true
  }

  metric_query {
    id = "api"

    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      dimensions  = { LoadBalancer = aws_lb.main.arn_suffix }
      stat        = "Sum"
      period      = 60
    }
  }

  metric_query {
    id = "alb"

    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_ELB_5XX_Count"
      dimensions  = { LoadBalancer = aws_lb.main.arn_suffix }
      stat        = "Sum"
      period      = 60
    }
  }
}

# every request fails when no task passes the health check; an unhealthy count would not work here, because ecs
# stops a task within a second of it turning unhealthy and the per minute sample never sees it
resource "aws_cloudwatch_metric_alarm" "no_healthy_targets" {
  alarm_name          = "${var.name}-no-healthy-targets"
  alarm_description   = "No api task has passed the load balancer health check for two minutes"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  statistic           = "Minimum"
  period              = 60
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  # two minutes in a row, so ecs replacing a crashed task does not raise it
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  # with no target registered the load balancer publishes nothing, which cloudwatch counts as breaching only after
  # waiting about ten minutes for late data; the 5xx alarm reacts sooner whenever there is traffic
  treat_missing_data = "breaching"
  alarm_actions      = local.alarm_topics
  ok_actions         = local.alarm_topics

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }

  # created after the first task is healthy, so a new environment does not raise it while it starts
  depends_on = [aws_ecs_service.api]
}
