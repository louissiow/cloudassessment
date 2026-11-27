# 05. DR runbook - regional recovery `apse5 -> apse1`

> Task 4 (20%). Selected cloud: AWS. Objectives: RTO 45 min, RPO 5 min for the [critical data set](01-reliability-model.md#5-critical-data-set-rpo-scope). Internal target: RTO 25 min.
> IaC: [`../terraform/recovery/`](../terraform/recovery/). Game days: [06](06-game-day-plan.md).

| | |
|---|---|
| Runbook ID | `RB-DR-001` |
| Owner | SRE (accountable), Platform (executes infra steps), Payments ops (reconciliation sign-off) |
| Pattern | Warm standby. Human-authorised, machine-executed. |
| Automation | ARC Region switch plan `t1dx-region-switch`, executed from `ap-southeast-1` |
| Last tested | Never -> L2 target Day 60, L3 target Day 85 ([08](08-roadmap-90-day.md)) |

## 0. Scope

| Event | Use this runbook? | Instead |
|---|---|---|
| Multi-service impairment of `ap-southeast-5` (several CUJs failing, AWS Health confirms a regional issue) | Yes | - |
| One AZ impaired | No | ARC zonal autoshift / manual zonal shift (automatic) |
| One service broken by a bad deploy | No | Rollback. A Region switch would carry the bad deploy with it. |
| `ext-payment-switch` down | No | Circuit breaker + pending mode ([04 section 5](04-resilience-architecture.md#5-circuit-breakers-and-bulkheads)). Failing over does not fix a provider. |
| Data corruption / bad migration | No | Point-in-time restore runbook `RB-DATA-002`. Global DB replicates corruption too. |
| Security compromise of the `apse5` account | Case by case | Security IR lead + IC decide jointly |
| Planned exercise / failback | Yes (graceful mode) | - |

## 1. Failure detection

A regional decision needs at least 2 independent signals. One alarm is not enough.

| # | Signal | Source | Where it runs |
|---|---|---|---|
| D1 | >= 2 CUJs in fast burn (composite alarm `t1dx-region-impairment-apse5`) | CloudWatch | `apse5` + monitoring account in `apse1` |
| D2 | Outside-in canaries failing from `apse1` (`t1dx-canary-cuj-apse1`) | CloudWatch Synthetics | `apse1` |
| D3 | AWS Health event for `ap-southeast-5` affecting EKS / RDS / MSK / API Gateway / EC2 | AWS Health -> EventBridge | Both Regions |
| D4 | Control-plane symptoms: EKS API errors, RDS API errors, CloudWatch metric gaps from `apse5` | Platform on-call | - |
| D5 | Standby is healthy: `t1dx-canary-dr-direct` green, Region switch plan evaluation no errors, `AuroraGlobalDBRPOLag` known | `apse1` | `apse1` |

D5 is a precondition. Failing over to an unhealthy standby makes things worse, so in that case stay and work the incident in the primary.

## 2. Authority and decision

| Item | Rule |
|---|---|
| Who decides | Incident Commander (IC) of the P1. Pre-delegated by the Head of Technology Operations through this runbook, so there is no need for a committee call during the outage. |
| Who must be informed *before* execution | Duty Head of Engineering (or delegate) + Risk duty officer. They are informed, their approval is not needed. If they cannot be reached within 5 min, the IC proceeds. |
| Two-person rule | The Region switch plan has a Manual approval block. The IC starts it. A second authorised person (Platform lead on call) approves. |
| Decision criteria (all must be true) | (a) D1 or D2 sustained >= 10 min, plus D3 or D4. (b) No credible ETA < 20 min from AWS / the primary investigation. (c) D5 green. (d) Not an excluded event (section 0). |
| Fast path | AWS Health confirms a regional outage with no ETA -> criteria (a) shortened to 5 min |
| Default if unsure at T+20 | Fail over. The RTO clock is the constraint. A planned failback is cheap (RPO 0). |
| Record | Every decision goes in the decision log with time and signals ([07 section 5](07-incident-command.md#5-decision-log)) |

## 3. RTO budget

| Phase | Steps | Target | Cumulative |
|---|---|---|---|
| Detect | Fast-burn page, canaries | 2 min | T+2 |
| Triage | IC assigned, signals D1-D5 checked | 5 min | T+7 |
| Decide | Criteria met (10-min sustain incl. triage) | 5 min | T+12 |
| Execute plan | Fence -> scale -> promote -> validate -> shift (section 4) | 10 min | T+22 |
| Verify | Canaries green through the edge, burn rate falling | 3 min | T+25 |
| Buffer | Unknowns, manual workarounds | 20 min | T+45 (RTO) |

> The clock starts from customer impact, which is earlier than the page. Timings are design estimates and must be measured in game days L2/L3. Region switch records execution time against the configured desired RTO.

## 4. Execution - Region switch plan `t1dx-region-switch` (activate `ap-southeast-1`, ungraceful)

Start it from the `ap-southeast-1` console or CLI. Plans execute in the Region being activated, so this has no dependency on `apse5`:

```bash
aws arc-region-switch start-plan-execution \
  --region ap-southeast-1 \
  --plan-arn "$T1DX_REGION_SWITCH_PLAN_ARN" \
  --target-region ap-southeast-1 \
  --action activate \
  --mode ungraceful \
  --comment "P1 INC-<id>: apse5 regional impairment. IC=<name>"
```

| Step | Execution block | What it does | Ungraceful behaviour | Est. time |
|---|---|---|---|---|
| 1 | Manual approval | Second authorised approver | - | 1 min |
| 2 | Custom action Lambda `t1dx-fence-apse5` | Fence writers first (best effort): scale outbox relay, `payment-adapter`, consumers and `transfer-svc` in `apse5` to 0 and set `region_role=standby` in AWS AppConfig. Skipped on error, because the Region may be unreachable. | Skip on failure | 1 min |
| 3 | EKS resource scaling | Scale `apse1` deployments to 100% of the `apse5` baseline. Karpenter brings nodes. ODCR covers 60%. | - | 5-8 min (parallel with 4-5) |
| 4 | Aurora Provisioned Scaling | Scale `t1dx-aurora-apse1` to the primary's instance class + 1 reader | - | Parallel |
| 5 | Aurora Global Database | Promote `t1dx-aurora-apse1`. Graceful = switchover (RPO 0). Ungraceful = failover with data loss allowed (RPO = lag at that moment). Aurora fences the old primary on a best-effort basis. | Failover | 2-5 min |
| 6 | Custom action Lambda `t1dx-dr-validate` | Dependency validation (section 5). Fails the plan if a hard check fails. | Runs | 2 min |
| 7 | ARC routing control | One atomic update: `t1dx-rc-apse5` -> Off and `t1dx-rc-apse1` -> On. CloudFront's origin hostname now resolves to `t1dx-api-apse1`. | - | 1 min |
| 8 | Route 53 health check block + canary | Confirm `t1dx-canary-cuj-apse1` passes through the public edge | - | 2 min |

Manual fallback (if the Region switch service itself is unavailable). Same order, using data-plane CLIs only:

```bash
# 1. Fence writers in apse5 (best effort; skip if the Region is unreachable)
kubectl --context t1dx-eks-apse5 -n payments scale deploy transfer-svc payment-adapter outbox-relay --replicas=0

# 2. Scale apse1 workloads (kubectl against t1dx-eks-apse1), then promote Aurora in apse1
aws rds failover-global-cluster --region ap-southeast-1 \
  --global-cluster-identifier t1dx-aurora-global \
  --target-db-cluster-identifier "$AURORA_APSE1_CLUSTER_ARN" \
  --allow-data-loss

# 3. Validate (section 5), then flip traffic atomically via any ARC cluster endpoint
#    (if one endpoint fails, retry against another of the cluster's 5 Regional endpoints)
aws route53-recovery-cluster update-routing-control-states \
  --update-routing-control-state-entries \
    "[{\"RoutingControlArn\":\"$RC_APSE5_ARN\",\"RoutingControlState\":\"Off\"},
      {\"RoutingControlArn\":\"$RC_APSE1_ARN\",\"RoutingControlState\":\"On\"}]" \
  --region "$ARC_ENDPOINT_REGION" --endpoint-url "$ARC_ENDPOINT_URL"

# 4. Confirm state
aws route53-recovery-cluster get-routing-control-state \
  --routing-control-arn "$RC_APSE1_ARN" \
  --region "$ARC_ENDPOINT_REGION" --endpoint-url "$ARC_ENDPOINT_URL"
```

> Do not flip routing controls from the ARC console during an event. Use the cluster's data-plane endpoints in 5 Regions, which are the highly available path. Safety rule `t1dx-arc-atleast-one-on` blocks any change that would leave both Regions Off, which is why the flip is one atomic update.

Why fence writers before promoting. Aurora fences the old primary on a *best-effort* basis. If fencing times out (for example, during multi-AZ failures), writes could briefly land there (split-brain). Stopping the writers in `apse5` first (step 2) narrows that window. Services connect through the Aurora global writer endpoint, which follows the new primary. A writer still running in `apse5` would therefore write cross-Region to the *new* primary (slower, but still one writer). RDS Proxy in `apse1` points at the promoted cluster and DNS TTLs on the writer path are kept short.

## 5. Dependency validation (`t1dx-dr-validate`)

| # | Check | Hard / soft | How |
|---|---|---|---|
| V1 | Aurora `apse1` is writer and accepts a write | Hard | Write + read a canary row through RDS Proxy `apse1` |
| V2 | `AuroraGlobalDBRPOLag` at failover recorded (for reconciliation) | Soft | Read last datapoint, store in the decision log |
| V3 | Secrets present and current (DB, provider mTLS certs, API keys) | Hard | Secrets Manager replica `GetSecretValue` |
| V4 | KMS multi-Region replica keys usable | Hard | `Decrypt` test |
| V5 | ECR images for current release tags present in `apse1` | Hard | `DescribeImages` for the release manifest |
| V6 | `t1dx-msk-apse1` topics exist, replicated offsets present for consumer groups | Hard | Admin API |
| V7 | `ext-payment-switch` reachable from `apse1` egress EIPs (allowlist) with mTLS | Hard | Provider status endpoint |
| V8 | `ext-messaging` reachable from `apse1` EIPs | Soft (degraded mode OK) | Provider status endpoint |
| V9 | EKS deployments at desired replicas, HPA/KEDA active | Hard | K8s API |
| V10 | API GW `t1dx-api-apse1` stage = current release, throttle quota >= 2x peak | Hard | API GW API |
| V11 | WAF web ACL attached to `t1dx-api-apse1` | Hard | WAFv2 API |
| V12 | Outbox relay running in `apse1`, republishing rows not confirmed in MSK `apse1` | Hard | Relay health endpoint |

## 6. Reconciliation

Starts immediately after traffic is on `apse1`. Owned by Payments ops with SRE support. Sign-off required before the incident is closed.

| Step | What | How |
|---|---|---|
| R1 | Find the loss window | `failover_time - RPO lag at failover (V2)` to `failover_time` |
| R2 | Recover unreplicated writes | When `apse5` returns, Aurora creates snapshot `rds:unplanned-global-failover-<old-primary>-<timestamp>`. Copy it to a manual snapshot immediately (system snapshots follow the backup retention period). Restore it to an isolated cluster `t1dx-aurora-recon`. Diff `transfers`, `ledger_entries` and `outbox` rows created in the loss window against the new primary. |
| R3 | Resolve in-flight payments | For every transfer in the window not `COMPLETED`/`REJECTED` on the new primary: query `ext-payment-switch` status by `transfer_id`. Provider = completed -> post ledger + mark completed. Provider = unknown / not received -> mark failed, release the hold, notify the customer. The provider is the source of truth for whether money moved. |
| R4 | Kafka gaps | The outbox relay in `apse1` republishes outbox rows from the loss window. Consumers dedupe on `event_id` (section 4 of [04](04-resilience-architecture.md#4-idempotency)). |
| R5 | Duplicates | Idempotency keys (replicated) block duplicate customer retries. A duplicate provider submission is blocked by the provider's idempotency on `transfer_id`. |
| R6 | Notifications | Re-send for transfers whose status changed in R3. Duplicates are acceptable. |
| R7 | Evidence | Diff report, counts and customer impact list stored in `t1dx-incident-evidence` |
| R8 | Sign-off | Payments ops lead + Finance control: ledger totals match provider settlement reports for the day |

## 7. Communication during DR

| When | Who | What |
|---|---|---|
| Decision made | Comms lead | Internal P1 channel + leadership: "Invoking regional DR, ETA 25 min" |
| Every 15 min | Comms lead | Internal update ([07 section 4](07-incident-command.md#4-communication-cadence)) |
| Customer-facing | Comms lead + Marketing/CX | Status page + in-app banner: "Some transfers may show pending" |
| Regulator | Risk/Compliance liaison | Per BNM RMiT notification requirements (Compliance owns content and timing) |
| Providers | Vendor liaison | Notify both providers of the source IP change (pre-agreed) |

## 8. Failback `apse1 -> apse5` (planned, graceful)

| Step | Action |
|---|---|
| F1 | `apse5` healthy for >= 24 h. AWS Health event closed. Root cause understood. |
| F2 | Aurora: old Region automatically rejoined as a secondary. Confirm `AuroraGlobalDBRPOLag` ~ 0. |
| F3 | MSK: enable the pre-defined reverse replicator `t1dx-msk-replicator-apse1-to-apse5` (defined in IaC, created at failback). Wait for lag ~ 0. |
| F4 | Change window approved (CAB emergency or standard). Low-traffic window (e.g. Sun 02:00 MYT). |
| F5 | Run the plan graceful to activate `ap-southeast-5`: Aurora switchover (RPO 0), scale `apse5`, routing controls flip. Run it from `ap-southeast-5`. |
| F6 | Verify canaries + burn rate. Keep `apse1` at full size for 2 h, then scale back to warm (30%). |
| F7 | Reset replication direction (`apse5 -> apse1`). Delete the reverse replicator. Confirm the plan evaluation is clean. |
| F8 | Post-incident review covers DR timings vs RTO. Update this runbook. |

## 9. Security, cost, ownership

| | |
|---|---|
| Security | Recovery roles are pre-provisioned in both Regions, with break-glass access behind MFA. The Region switch plan needs a second approver (section 2). No IAM or DNS records are changed during the event. |
| Cost | Steady-state standby cost is in [00 section 6](00-architecture-overview.md#6-cost-order-of-magnitude-to-verify-in-aws-pricing-calculator). After a failover `apse1` runs at full size, so the bill is close to the primary run rate until failback. |
| Ownership | IC decides (section 2). Platform on call approves and runs the plan. Payments ops owns reconciliation. Comms lead handles updates and Risk/Compliance owns regulator notification. |

## 10. Known limitations of this runbook

- Ungraceful RPO is seconds, not zero. Reconciliation (section 6) is required. RPO is bounded by the `AuroraGlobalDBRPOLag` alarms (60 s warn, 180 s page).
- `rds.global_db_rpo` is not set. It would block commits on the primary when the DR Region lags, turning a DR problem into a primary outage. AWS also advises against it in two-Region setups during failover. I chose availability and an alarm on lag instead. Risk needs to sign off this trade-off.
- Capacity beyond the 60% ODCR is not guaranteed during a regional event (AWS notes that scaling blocks do not guarantee capacity).
- Global services (CloudFront, Route 53) are a shared fate across both Regions. Residual risk accepted.
