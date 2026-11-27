# AWS FIS experiment templates for the game-day ladder (docs/06-game-day-plan.md).
# Every experiment stops automatically when a CUJ burn-rate alarm fires.
# AZ power interruption (L1b) and cross-Region connectivity (L2) come from the FIS
# scenario library (console) and are tagged into the same naming scheme.

locals {
  eks_cluster = "t1dx-eks-${var.region_code}"
}

# GD-L1a: provider latency -> breaker must open, retry amplification <= 1.25x.
resource "aws_fis_experiment_template" "provider_latency" {
  description = "GD-L1a: 5s latency on payment-adapter egress to ext-payment-switch"
  role_arn    = var.fis_role_arn

  dynamic "stop_condition" {
    for_each = var.stop_alarm_arns
    content {
      source = "aws:cloudwatch:alarm"
      value  = stop_condition.value
    }
  }

  action {
    name      = "provider-latency"
    action_id = "aws:eks:pod-network-latency"

    parameter {
      key   = "duration"
      value = "PT10M"
    }
    parameter {
      key   = "delayMilliseconds"
      value = "5000"
    }
    parameter {
      key   = "jitterMilliseconds"
      value = "500"
    }
    parameter {
      key   = "sources"
      value = var.provider_cidrs
    }
    parameter {
      key   = "kubernetesServiceAccount"
      value = "fis-experiment"
    }

    target {
      key   = "Pods"
      value = "payment-adapter-pods"
    }
  }

  target {
    name           = "payment-adapter-pods"
    resource_type  = "aws:eks:pod"
    selection_mode = "ALL"
    parameters = {
      clusterIdentifier = local.eks_cluster
      namespace         = "payments"
      selectorType      = "labelSelector"
      selectorValue     = "app=payment-adapter"
    }
  }

  tags = {
    Name = "t1dx-gd-l1a-provider-latency-${var.region_code}"
  }
}

# GD-L1c: Aurora writer failover under load -> write errors < 60 s, no duplicates.
resource "aws_fis_experiment_template" "aurora_writer_failover" {
  description = "GD-L1c: failover t1dx-aurora writer within the Region"
  role_arn    = var.fis_role_arn

  dynamic "stop_condition" {
    for_each = var.stop_alarm_arns
    content {
      source = "aws:cloudwatch:alarm"
      value  = stop_condition.value
    }
  }

  action {
    name      = "failover-writer"
    action_id = "aws:rds:failover-db-cluster"
    target {
      key   = "Clusters"
      value = "aurora"
    }
  }

  target {
    name           = "aurora"
    resource_type  = "aws:rds:cluster"
    selection_mode = "ALL"
    resource_arns  = [var.aurora_cluster_arn]
  }

  tags = {
    Name = "t1dx-gd-l1c-aurora-failover-${var.region_code}"
  }
}

# GD-L1d: isolate MSK subnets for 15 min -> transfers still accepted, outbox drains in order.
resource "aws_fis_experiment_template" "msk_isolation" {
  description = "GD-L1d: disrupt connectivity of t1dx-msk subnets"
  role_arn    = var.fis_role_arn

  dynamic "stop_condition" {
    for_each = var.stop_alarm_arns
    content {
      source = "aws:cloudwatch:alarm"
      value  = stop_condition.value
    }
  }

  action {
    name      = "isolate-msk"
    action_id = "aws:network:disrupt-connectivity"
    parameter {
      key   = "duration"
      value = "PT15M"
    }
    parameter {
      key   = "scope"
      value = "all"
    }
    target {
      key   = "Subnets"
      value = "msk-subnets"
    }
  }

  target {
    name           = "msk-subnets"
    resource_type  = "aws:ec2:subnet"
    selection_mode = "ALL"
    resource_tag {
      key   = "t1dx-tier"
      value = "msk"
    }
  }

  tags = {
    Name = "t1dx-gd-l1d-msk-isolation-${var.region_code}"
  }
}

# GD-L1e: kill 30% of transfer-svc pods under 2x load -> PDB respected, no CUJ burn.
resource "aws_fis_experiment_template" "transfer_pod_delete" {
  description = "GD-L1e: delete 30% of transfer-svc pods"
  role_arn    = var.fis_role_arn

  dynamic "stop_condition" {
    for_each = var.stop_alarm_arns
    content {
      source = "aws:cloudwatch:alarm"
      value  = stop_condition.value
    }
  }

  action {
    name      = "pod-delete"
    action_id = "aws:eks:pod-delete"
    parameter {
      key   = "kubernetesServiceAccount"
      value = "fis-experiment"
    }
    target {
      key   = "Pods"
      value = "transfer-pods"
    }
  }

  target {
    name           = "transfer-pods"
    resource_type  = "aws:eks:pod"
    selection_mode = "PERCENT(30)"
    parameters = {
      clusterIdentifier = local.eks_cluster
      namespace         = "payments"
      selectorType      = "labelSelector"
      selectorValue     = "app=transfer-svc"
    }
  }

  tags = {
    Name = "t1dx-gd-l1e-pod-delete-${var.region_code}"
  }
}
