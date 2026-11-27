# Route 53 ARC routing controls for the Region-level traffic switch.
# t1dx-rc-apse5 = On (active), t1dx-rc-apse1 = Off (warm standby) in steady state.
# Flipped by ARC Region switch plan t1dx-region-switch (step 7) or, as fallback,
# `aws route53-recovery-cluster update-routing-control-states` (docs/05-dr-runbook.md section 4).

resource "aws_route53recoverycontrolconfig_cluster" "this" {
  provider = aws.usw2
  name     = "t1dx-arc-cluster" # US$2.50/hour; data plane spans 5 Regional endpoints
}

resource "aws_route53recoverycontrolconfig_control_panel" "this" {
  provider    = aws.usw2
  name        = "t1dx-arc-panel"
  cluster_arn = aws_route53recoverycontrolconfig_cluster.this.arn
}

resource "aws_route53recoverycontrolconfig_routing_control" "region" {
  for_each = toset(["apse5", "apse1"])

  provider          = aws.usw2
  name              = "t1dx-rc-${each.key}"
  cluster_arn       = aws_route53recoverycontrolconfig_cluster.this.arn
  control_panel_arn = aws_route53recoverycontrolconfig_control_panel.this.arn
}

# Never allow both Regions Off (which would make Route 53 failover answers undefined for customers).
# This is why the DR flip is a single atomic update: apse5 Off + apse1 On.
resource "aws_route53recoverycontrolconfig_safety_rule" "atleast_one_on" {
  provider          = aws.usw2
  name              = "t1dx-arc-atleast-one-on"
  control_panel_arn = aws_route53recoverycontrolconfig_control_panel.this.arn
  wait_period_ms    = 5000
  asserted_controls = [for rc in aws_route53recoverycontrolconfig_routing_control.region : rc.arn]

  rule_config {
    inverted  = false
    threshold = 1
    type      = "ATLEAST"
  }
}

# Route 53 health checks whose status is driven purely by routing control state.
resource "aws_route53_health_check" "routing_control" {
  for_each = aws_route53recoverycontrolconfig_routing_control.region

  type                = "RECOVERY_CONTROL"
  routing_control_arn = each.value.arn

  tags = {
    Name = "t1dx-hc-rc-${each.key}"
  }
}
