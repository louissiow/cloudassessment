# 06. Game-day plan

> Task 4 (20%). Selected cloud: AWS. Goal: move DR and resilience from documented to tested. Experiments: [`../terraform/game-day/fis_experiments.tf`](../terraform/game-day/fis_experiments.tf).

## 1. Principles

| Principle | Practice |
|---|---|
| Build confidence in steps | L0 tabletop -> L1 component faults in staging -> L2 full Region switch in staging -> L3 planned switchover in production |
| Hypothesis first | Every experiment states its expected result in advance and gets a pass/fail |
| Always have a stop button | AWS FIS stop conditions wired to CUJ burn-rate composite alarms. A named abort owner. |
| Blast radius | Start with the smallest scope: 1 pod -> 1 AZ -> 1 Region. Staging before prod. Low-traffic window first |
| Test the people too | Game days cover the runbook, the IC and comms, not only the AWS services |
| Results change things | Every gap becomes a backlog item with an owner and a date |

## 2. Game-day ladder (90-day plan)

| Level | When | Environment | Scenario | Pass criteria |
|---|---|---|---|---|
| L0 Tabletop | Day 25 | Meeting room | "`apse5` impaired at 10:30 on salary day". Walk `RB-DR-001` with real people and real roles. | Every step has an owner. Authority is clear. Missing items are listed (expect many). |
| L1a Provider latency | Day 40 | Staging | Inject 5 s latency / 50% errors on `ext-payment-switch` stub egress | Breaker opens < 30 s. Retry amplification <= 1.25x. CUJ-03a SLO holds. CUJ-03b burns. No pod restarts. |
| L1b AZ power interruption | Day 45 | Staging | FIS scenario *AZ Availability: Power Interruption* on 1 AZ | Zonal shift is triggered. Aurora/MSK fail over within the AZ. CUJ SLOs hold. Page fires <= 2 min if a burn occurs. |
| L1c Aurora writer failover | Day 45 | Staging | `aws:rds:failover-db-cluster` under 2x load | Write errors < 60 s. No connection storm (RDS Proxy). Idempotency prevents duplicates. |
| L1d MSK outage | Day 50 | Staging | Block MSK subnets (`aws:network:disrupt-connectivity`) 15 min | Transfers still accepted (outbox grows). Backlog drains in priority order without overloading the provider stub. |
| L1e Pod kill under load | Day 50 | Staging | `aws:eks:pod-delete` 30% of `transfer-svc` | PDB respected. HPA recovers. No CUJ burn. |
| L2 Full Region switch | Day 60 | Staging (two Regions, same topology) | Ungraceful `t1dx-region-switch` with `apse5` cut off (FIS *Cross-Region: Connectivity* scenario + routing control) | RTO measured <= 25 min. RPO measured. Reconciliation finds and fixes the injected in-flight transfers. Canaries in `apse1` kept reporting. |
| L3 Production switchover | Day 85 | Production, Sun 02:00-06:00 MYT | Graceful switchover `apse5 -> apse1`, run for 2 h, then failback | RPO = 0. Customer error rate within the slow-burn threshold. RTO for the traffic shift <= 15 min. Failback clean. |
| Ongoing | Quarterly | Prod (graceful) + staging (ungraceful) | Rotate scenarios. Unannounced game day after 2 successful announced runs. | Trend RTO, time-to-decision and gaps closed |

## 3. Experiment template

| Field | Content |
|---|---|
| ID / name | e.g. `GD-L2-01 Region switch ungraceful` |
| Hypothesis | "If `apse5` is unreachable, we restore CUJ-01..03 from `apse1` within 25 min, with RPO < 60 s and without double payments." |
| Steady state | CUJ burn rate < 1x, RPO lag < 5 s, canaries green in both Regions |
| Method | FIS template ID + manual steps |
| Stop conditions | FIS stop condition = `t1dx-cuj03-fast-burn-apse5` (prod) / staging equivalent. Manual abort word: "RED". |
| Abort / rollback | Stop FIS. Run the plan in reverse (graceful). Owner: Platform lead. |
| Roles | Game master (SRE), IC (rotating, not the most senior person), scribe, observers, abort owner |
| Measures | Time per runbook step, total RTO, RPO, error budget consumed, pages received, wrong-turns |
| Comms | Pre-notify: service desk, CX, Risk, providers (for L2/L3). Status page notice for L3. |
| Output | Report in `t1dx-incident-evidence/gameday/<date>/`, backlog items, runbook updates |

## 4. L3 production switchover - run sheet

| Time (MYT) | Step | Owner |
|---|---|---|
| T-7 days | Change request (CAB). Risk/Compliance informed. Compliance decides whether regulator pre-notification applies. Providers informed of the `apse1` source IPs. | SRE |
| T-1 day | Go/no-go: plan evaluation clean, `t1dx-canary-dr-direct` green 24 h, error budget > 50% (do not game-day on a fragile week), no open P1/2 | IC |
| 01:30 | War room open. Roles confirmed. Dashboards: burn rate both Regions, RPO lag, Region switch execution view. | Game master |
| 02:00 | `start-plan-execution --action activate --target-region ap-southeast-1 --mode graceful` (run in `apse1`) | Platform lead |
| 02:00-02:15 | Watch: switchover RPO 0, scaling, routing flip, canaries | All |
| 02:15-04:15 | Run in `apse1`. Synthetic transfers every minute. Check reconciliation job = no diffs. | Payments ops |
| 04:15 | Failback: graceful activate `ap-southeast-5` (run in `apse5`) | Platform lead |
| 04:30 | Verify. Scale `apse1` back to warm at 06:30. | SRE |
| +5 business days | Review: timings vs RTO budget, gaps -> backlog | SRE |

## 5. Gaps we expect to find

From what I have seen, first DR tests tend to fail on items like these. Each one has a check in `t1dx-dr-validate` or in the plan evaluation:

| Likely gap | Check |
|---|---|
| Provider allowlist missing the DR egress IPs | V7 / `t1dx-canary-providers` from `apse1` |
| Secret or certificate exists only in `apse5` | V3 + Secrets Manager replication |
| Image tag not replicated | V5 + ECR replication rule |
| IAM role or policy missing in DR | Region switch plan evaluation (IAM checks every 30 min) |
| Config drift between Regions (manual console changes) | AWS Config + IaC drift detection in CI. Controllers such as the AWS Load Balancer Controller also overwrite manual changes to the resources they manage. |
| Capacity / quota lower in DR | Service Quotas alarms in `apse1` |
| People unsure who decides | L0 tabletop + authority in [05 section 2](05-dr-runbook.md#2-authority-and-decision) |

## 6. Security, cost, ownership

| | |
|---|---|
| Security | FIS role is least-privilege, scoped by tags (`gameday=allowed`). Experiments are logged in CloudTrail. Synthetic accounts are isolated from real customers. |
| Cost | Staging two-Region environment (can be scaled down outside game days). L3 = ~4 h of DR at full size. |
| Ownership | SRE designs and runs game days. Product and Platform teams take part and own their fixes. Head of Engineering sponsors (protects the time). |
