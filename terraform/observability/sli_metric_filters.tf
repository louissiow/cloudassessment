# SLI source: API Gateway access logs for t1dx-api-<region>.
# Access log format (JSON) must include, unquoted for numeric comparison:
#   {"requestId":"$context.requestId","httpMethod":"$context.httpMethod",
#    "resourcePath":"$context.resourcePath","status":$context.status,
#    "responseLatency":$context.responseLatency,"traceparent":"$context.requestOverride.header.traceparent"}
# Metrics: t1dx/SLI SliTotal, SliBad with dimensions route + method (route = resource template, low cardinality).

locals {
  access_log_group = "/aws/apigateway/t1dx-api-${var.region_code}/access"
}

resource "aws_cloudwatch_log_metric_filter" "sli_total" {
  name           = "t1dx-sli-total-${var.region_code}"
  log_group_name = local.access_log_group
  # Valid requests = everything except client-caused 4xx.
  pattern = "{ $.status != 400 && $.status != 401 && $.status != 403 && $.status != 404 && $.status != 409 && $.status != 422 }"

  metric_transformation {
    name      = "SliTotal"
    namespace = "t1dx/SLI"
    value     = "1"
    unit      = "Count"
    dimensions = {
      route  = "$.resourcePath"
      method = "$.httpMethod"
    }
  }
}

resource "aws_cloudwatch_log_metric_filter" "sli_bad" {
  name           = "t1dx-sli-bad-${var.region_code}"
  log_group_name = local.access_log_group
  # Bad = 5xx (incl. API GW integration timeouts) and 429 (throttled/shed customers).
  pattern = "{ $.status >= 500 || $.status = 429 }"

  metric_transformation {
    name      = "SliBad"
    namespace = "t1dx/SLI"
    value     = "1"
    unit      = "Count"
    dimensions = {
      route  = "$.resourcePath"
      method = "$.httpMethod"
    }
  }
}

resource "aws_cloudwatch_log_data_protection_policy" "access_logs" {
  log_group_name = local.access_log_group
  policy_document = jsonencode({
    Name    = "t1dx-mask-pii"
    Version = "2021-06-01"
    Configuration = {
      CustomDataIdentifier = [
        { Name = "MyKad", Regex = "\\d{6}-\\d{2}-\\d{4}" } # Malaysian IC number
      ]
    }
    Statement = [
      {
        Sid            = "audit"
        DataIdentifier = ["arn:aws:dataprotection::aws:data-identifier/EmailAddress", "arn:aws:dataprotection::aws:data-identifier/CreditCardNumber", "MyKad"]
        Operation      = { Audit = { FindingsDestination = {} } }
      },
      {
        Sid            = "mask"
        DataIdentifier = ["arn:aws:dataprotection::aws:data-identifier/EmailAddress", "arn:aws:dataprotection::aws:data-identifier/CreditCardNumber", "MyKad"]
        Operation      = { Deidentify = { MaskConfig = {} } }
      }
    ]
  })
}
