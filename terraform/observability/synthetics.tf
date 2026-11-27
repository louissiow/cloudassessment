# Outside-in canary for CUJ-01..03 through the public edge (t1dx-cf-edge).
# Deployed in both Regions: t1dx-canary-cuj-apse5 and t1dx-canary-cuj-apse1.
# Canary names are limited to 255 chars, lowercase, digits, hyphens, underscores.

# Node.js Puppeteer runtimes before 11.0 load the handler from nodejs/node_modules/ in the zip.
data "archive_file" "canary" {
  type        = "zip"
  output_path = "${path.module}/build/cuj_api_canary.zip"

  source {
    content  = file("${path.module}/../../canary/cuj_api_canary.js")
    filename = "nodejs/node_modules/cuj_api_canary.js"
  }
}

resource "aws_synthetics_canary" "cuj" {
  name                 = "t1dx-canary-cuj-${var.region_code}"
  artifact_s3_location = "s3://${var.canary_artifact_bucket}/canary/${var.region_code}/"
  execution_role_arn   = var.canary_execution_role_arn
  handler              = "cuj_api_canary.handler"
  zip_file             = data.archive_file.canary.output_path
  runtime_version      = var.canary_runtime_version
  start_canary         = true

  schedule {
    expression = "rate(1 minute)"
  }

  run_config {
    timeout_in_seconds = 50
    environment_variables = {
      BASE_URL = var.public_api_base_url
    }
  }

  success_retention_period = 7
  failure_retention_period = 30

  tags = {
    owner_team = "sre"
    cuj        = "CUJ-01,CUJ-02,CUJ-03"
  }
}

# Dead man's switch: missing canary data is treated as failure.
resource "aws_cloudwatch_metric_alarm" "canary" {
  alarm_name          = "t1dx-canary-cuj-failing-${var.region_code}"
  alarm_description   = "Synthetic CUJ journeys failing from ${var.region_code} (2 consecutive runs). Carries paging in low-traffic hours."
  namespace           = "CloudWatchSynthetics"
  metric_name         = "SuccessPercent"
  dimensions          = { CanaryName = aws_synthetics_canary.cuj.name }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  comparison_operator = "LessThanThreshold"
  threshold           = 100
  treat_missing_data  = "breaching"
  alarm_actions       = [var.page_topic_arns["sre-ic"]]

  tags = {
    owner_team = "sre"
    cuj        = "synthetic"
    route      = "page"
  }
}
