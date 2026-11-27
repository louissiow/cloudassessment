# Terraform samples

> Selected cloud: AWS. Samples cover the main controls, with the same names as the docs and diagram.
> Not applied. Written for Terraform >= 1.9 and the AWS provider ~> 6.0. Run `terraform init && terraform validate` in each folder before use.

| Folder | What | Docs |
|---|---|---|
| `observability/` | SLI metric filters on API Gateway access logs, multi-window burn-rate alarms + composite pages, RPO lag alarms, Synthetics canary | [02](../docs/02-sli-slo-specification.md), [03](../docs/03-observability-architecture.md) |
| `recovery/` | ARC routing control cluster/panel/controls/safety rule, Route 53 failover records for the CloudFront origin, Aurora Global Database across `ap-southeast-5` / `ap-southeast-1`, KMS multi-Region key | [05](../docs/05-dr-runbook.md) |
| `game-day/` | AWS FIS experiment templates with SLO-based stop conditions | [06](../docs/06-game-day-plan.md) |

Not included (configured in the console/CLI or in other stacks): ARC Region switch plan `t1dx-region-switch` (execution blocks listed in [05 section 4](../docs/05-dr-runbook.md)), zonal autoshift enablement, EKS clusters, MSK + MSK Replicator, API Gateway, CloudFront.

Note: the Route 53 ARC recovery control configuration API is only served from `us-west-2`, so those resources use a `us-west-2` provider alias. This is for configuration. Routing control state changes go through the cluster's 5 Regional data-plane endpoints.
