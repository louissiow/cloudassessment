# Multi-window, multi-burn-rate alerting for CUJ availability SLOs (99.99%).
# Burn rate = error ratio / (1 - SLO). Budget ratio at 99.99% = 0.0001.
#   fast: 1h AND 5m at 14.4x -> error ratio > 0.144%  -> page
#   slow: 6h AND 30m at 6x   -> error ratio > 0.06%   -> page
# The 3-day budget-leak ticket is reported from CloudWatch Application Signals SLOs.
# See docs/02-sli-slo-specification.md section 5.

locals {
  cujs = {
    cuj01 = {
      cuj        = "CUJ-01"
      owner_team = "identity"
      slo        = 99.99
      routes = [
        { route = "/auth/login", method = "POST" },
        { route = "/auth/otp/verify", method = "POST" },
      ]
    }
    cuj02 = {
      cuj        = "CUJ-02"
      owner_team = "accounts"
      slo        = 99.99
      routes = [
        { route = "/accounts/{id}", method = "GET" },
        { route = "/accounts/{id}/transactions", method = "GET" },
      ]
    }
    cuj03 = {
      cuj        = "CUJ-03"
      owner_team = "payments"
      slo        = 99.99
      routes = [
        { route = "/transfers", method = "POST" },
      ]
    }
  }

  windows = {
    fast_long  = { pair = "fast", seconds = 3600, burn = 14.4 }
    fast_short = { pair = "fast", seconds = 300, burn = 14.4 }
    slow_long  = { pair = "slow", seconds = 21600, burn = 6 }
    slow_short = { pair = "slow", seconds = 1800, burn = 6 }
  }

  burn_alarms = {
    for combo in setproduct(keys(local.cujs), keys(local.windows)) :
    "${combo[0]}-${combo[1]}" => {
      cuj_key    = combo[0]
      window_key = combo[1]
      cuj        = local.cujs[combo[0]]
      window     = local.windows[combo[1]]
      threshold  = local.windows[combo[1]].burn * (1 - local.cujs[combo[0]].slo / 100)
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "burn" {
  for_each = local.burn_alarms

  alarm_name          = "t1dx-${each.value.cuj_key}-burn-${replace(each.value.window_key, "_", "-")}-${var.region_code}"
  alarm_description   = "${each.value.cuj.cuj} error ratio over ${each.value.window.seconds / 60} min above ${each.value.window.burn}x burn (threshold ${each.value.threshold}). Component of composite page alarm."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = each.value.threshold
  treat_missing_data  = "notBreaching" # no traffic -> synthetic canary alarms carry paging

  dynamic "metric_query" {
    for_each = { for i, r in each.value.cuj.routes : i => r }
    content {
      id = "bad${metric_query.key}"
      metric {
        namespace   = "t1dx/SLI"
        metric_name = "SliBad"
        period      = each.value.window.seconds
        stat        = "Sum"
        dimensions = {
          route  = metric_query.value.route
          method = metric_query.value.method
        }
      }
    }
  }

  dynamic "metric_query" {
    for_each = { for i, r in each.value.cuj.routes : i => r }
    content {
      id = "tot${metric_query.key}"
      metric {
        namespace   = "t1dx/SLI"
        metric_name = "SliTotal"
        period      = each.value.window.seconds
        stat        = "Sum"
        dimensions = {
          route  = metric_query.value.route
          method = metric_query.value.method
        }
      }
    }
  }

  metric_query {
    id          = "ratio"
    label       = "${each.value.cuj.cuj} error ratio"
    return_data = true
    # Low-traffic guard: report 0 when there are too few requests to judge.
    expression = format(
      "IF((%s) >= %d, (%s) / (%s), 0)",
      join(" + ", [for i, _ in each.value.cuj.routes : "FILL(tot${i}, 0)"]),
      var.min_requests_short_window,
      join(" + ", [for i, _ in each.value.cuj.routes : "FILL(bad${i}, 0)"]),
      join(" + ", [for i, _ in each.value.cuj.routes : "FILL(tot${i}, 0)"]),
    )
  }

  tags = {
    owner_team = each.value.cuj.owner_team
    cuj        = each.value.cuj.cuj
    route      = "component"
  }
}

# Page only when BOTH long and short windows breach.
resource "aws_cloudwatch_composite_alarm" "page" {
  for_each = {
    for combo in setproduct(keys(local.cujs), ["fast", "slow"]) :
    "${combo[0]}-${combo[1]}" => { cuj_key = combo[0], pair = combo[1] }
  }

  alarm_name        = "t1dx-${each.value.cuj_key}-${each.value.pair}-burn-${var.region_code}"
  alarm_description = "PAGE: ${local.cujs[each.value.cuj_key].cuj} ${each.value.pair} error-budget burn in ${var.region_code}. Runbook: docs/07-incident-command.md"
  alarm_rule = format(
    "ALARM(\"%s\") AND ALARM(\"%s\")",
    aws_cloudwatch_metric_alarm.burn["${each.value.cuj_key}-${each.value.pair}_long"].alarm_name,
    aws_cloudwatch_metric_alarm.burn["${each.value.cuj_key}-${each.value.pair}_short"].alarm_name,
  )
  actions_enabled = true
  alarm_actions   = [var.page_topic_arns[local.cujs[each.value.cuj_key].owner_team]]
  ok_actions      = [var.page_topic_arns[local.cujs[each.value.cuj_key].owner_team]]

  tags = {
    owner_team = local.cujs[each.value.cuj_key].owner_team
    cuj        = local.cujs[each.value.cuj_key].cuj
    route      = "page"
  }
}

# Two or more CUJs in fast burn in this Region = regional impairment signal D1 (auto-P1, pages IC).
resource "aws_cloudwatch_composite_alarm" "region_impairment" {
  alarm_name        = "t1dx-region-impairment-${var.region_code}"
  alarm_description = "PAGE IC: 2+ CUJs in fast burn in ${var.region_code}. Evaluate RB-DR-001 (docs/05-dr-runbook.md)."
  alarm_rule = join(" OR ", [
    for pair in [["cuj01", "cuj02"], ["cuj01", "cuj03"], ["cuj02", "cuj03"]] :
    "(ALARM(\"${aws_cloudwatch_composite_alarm.page["${pair[0]}-fast"].alarm_name}\") AND ALARM(\"${aws_cloudwatch_composite_alarm.page["${pair[1]}-fast"].alarm_name}\"))"
  ])
  alarm_actions = [var.page_topic_arns["sre-ic"]]

  tags = {
    owner_team = "sre-ic"
    cuj        = "multi"
    route      = "page"
  }
}

# RPO protection for the critical data set (Aurora Global Database).
# AuroraGlobalDBRPOLag is only published in the secondary Region, on the secondary cluster.
# The alarm is deployed in both Regions against the local cluster, so it follows the roles
# after a switchover or failover without a Terraform change. Missing data is left as
# "missing" because the current primary never publishes this metric; a secondary that stops
# reporting is caught by DR readiness check D5 (docs/05-dr-runbook.md).
resource "aws_cloudwatch_metric_alarm" "rpo_lag" {
  for_each = {
    warn = { threshold = 60000, topic = var.ticket_topic_arns["data-platform"], route = "ticket" }
    page = { threshold = 180000, topic = var.page_topic_arns["data-platform"], route = "page" }
  }

  alarm_name          = "t1dx-aurora-rpo-lag-${each.key}-${var.region_code}"
  alarm_description   = "AuroraGlobalDBRPOLag above ${each.value.threshold / 1000}s (RPO objective 300s) for t1dx-aurora-${var.region_code} while it is the secondary."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBRPOLag"
  dimensions          = { DBClusterIdentifier = "t1dx-aurora-${var.region_code}" }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = each.value.threshold
  treat_missing_data  = "missing" # see note above
  alarm_actions       = [each.value.topic]

  tags = {
    owner_team = "data-platform"
    cuj        = "data"
    route      = each.value.route
  }
}
