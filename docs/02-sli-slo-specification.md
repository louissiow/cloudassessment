# 02. SLI/SLO specification

> Task 1 (20%). Selected cloud: AWS. Machine-readable version: [`../slo/slo-catalogue.yaml`](../slo/slo-catalogue.yaml). Alarm code: [`../terraform/observability/`](../terraform/observability/).

## 1. Why 99.99% has to be designed for

Error budget at 99.99%

| Window | Allowed bad time | Allowed bad requests (at about 4 M req/day) |
|---|---|---|
| 30 days | 4.32 min | about 12,000 of 120 M |
| 90 days | 12.96 min | - |
| 365 days | 52.6 min | - |

Serial composition of published AWS SLAs (credit thresholds, not real availability):

| Service | SLA |
|---|---|
| CloudFront | 99.9% |
| API Gateway | 99.95% |
| EKS (standard control plane) | 99.95% (99.99% with Provisioned Control Plane) |
| Aurora Multi-AZ | 99.99% |
| MSK Multi-AZ | 99.9% |
| Product if all were in series | ~ 99.69% |
| + 2 providers at 99.9% each | ~ 99.49% |

What this means for the design:

1. Keep the synchronous chain short. With the outbox pattern and a pending state, MSK and the providers are not on the path the customer waits on. What remains is CloudFront -> API GW -> EKS -> Aurora.
2. Most failures must be absorbed inside the Region, by the 3 AZs, Aurora Multi-AZ and zonal autoshift.
3. Regional failover is for disasters. One regional event uses about 6 months of budget at the 25-minute target and about 10 months at the 45-minute RTO (limitation L1 in the README).
4. In practice most budget is burnt by changes, so deployments are gated on burn rate.

## 2. SLI design principles

| Principle | Rule |
|---|---|
| Measure at the customer edge we control | Primary SLI source = API Gateway access logs (sees API GW throttles, integration timeouts and app 5xx in one place) |
| Cover "no traffic arrives" | Region-wide or edge failure produces *no* logs. CloudWatch Synthetics canaries run in both Regions as the second SLI source, plus CloudFront `5xxErrorRate` (`us-east-1`) as a cross-check. |
| Good / valid | Valid = all requests except 4xx caused by the client (400, 401, 403, 404, 409, 422). 429 and 5xx are bad, because a shed customer is still a failed customer. |
| Per-journey, not per-service | One SLI per CUJ. Routes map to CUJs in the alarm math (e.g. CUJ-01 = `POST /auth/login` + `POST /auth/otp/verify`) and alarms carry the `cuj` tag |
| Request-based | Traffic-weighted, so an outage at 2 AM costs less budget than one at noon. A minimum-traffic guard protects alerts. |
| Rolling 30-day window | Reported monthly and quarterly |

## 3. SLI specification

| SLO ID | CUJ | Type | SLI definition (good / valid) | Source (AWS) | Target |
|---|---|---|---|---|---|
| `slo-cuj01-avail` | CUJ-01 Login | Availability | `POST /auth/login` + `POST /auth/otp/verify` responses with status not 5xx or 429 / all excluding client 4xx | `t1dx-api-apse5` access logs -> metric filters (`t1dx/SLI` `SliTotal`, `SliBad`, dims `route`, `method`) | 99.99% |
| `slo-cuj01-latency` | CUJ-01 | Latency | Good responses with `responseLatency` < 1,500 ms / good responses | Same + API GW `Latency` p99 | 99.0% |
| `slo-cuj02-avail` | CUJ-02 Balance | Availability | `GET /accounts/*` status not 5xx or 429 | Same | 99.99% |
| `slo-cuj02-latency` | CUJ-02 | Latency | < 800 ms | Same | 99.0% |
| `slo-cuj03a-accept` | CUJ-03 Transfer accepted | Availability | `POST /transfers` returns 201/202 with a durable `transfer_id` or a business 4xx (insufficient funds) / all excluding client 4xx | Same | 99.99% |
| `slo-cuj03a-latency` | CUJ-03 | Latency | Accept < 1,000 ms | Same | 99.0% |
| `slo-cuj03b-complete` | CUJ-03 Transfer completed | Freshness | Transfers that reach a final state (`COMPLETED` / `REJECTED`) <= 30 s after acceptance / all accepted | `transfer-svc` EMF metric `TransferFinalisedWithin30s` | 99.9% |
| `slo-cuj04-notify` | CUJ-04 Notification | Freshness | Notifications handed to `ext-messaging` with 2xx <= 60 s after transfer completion / all due | `notification-svc` EMF metric | 99.9% |
| `slo-canary-cuj` | CUJ-01..03 | Synthetic | Canary runs passing / total, per Region | CloudWatch Synthetics `SuccessPercent` (`t1dx-canary-cuj-apse5` / `-apse1`) | 99.9% (period-based) |
| `slo-rpo` | Data | Freshness | Minutes with `AuroraGlobalDBRPOLag` < 300,000 ms / all minutes | CloudWatch `AWS/RDS` on the secondary cluster (`t1dx-aurora-apse1` in steady state; the metric is only published in the secondary Region) | 100% (objective) |

CUJ-03 is split in two. Availability of the journey means the customer can submit a transfer and get a durable, truthful answer. That part is fully in our control, so it carries 99.99%. Completion depends on `ext-payment-switch` and gets its own SLO and budget. A provider outage then shows up as a provider problem, and Vendor Management has the numbers for provider SLA reviews.

Per-AZ and per-Region slices. Each SLI is also emitted with `region` and `az` dimensions from service EMF metrics. A grey failure in one AZ shows up as a slice that diverges from the others. That divergence triggers zonal shift ([04 section 8](04-resilience-architecture.md#8-capacity-strategy)).

## 4. Error budget policy

| Budget remaining (30-day rolling) | State | What happens | Who decides |
|---|---|---|---|
| > 50% | Normal | Ship features. Reliability backlog at the agreed 20% capacity. | Team |
| 25-50% | Caution | Risky changes need SRE review. Canary duration doubled. | Team + SRE |
| 0-25% | At risk | Only fixes, reliability work and security changes for that service. Top 2 budget consumers go to the next sprint. | Eng manager |
| Exhausted | Frozen | Feature freeze for the service until 7 days of burn < 1x. Post-incident actions are mandatory. Reviewed at the monthly reliability review. | Head of Engineering (SRE reports, does not decide) |
| Single incident > 20% of budget | - | Mandatory post-incident review within 5 business days | IC |

Exceptions: regulatory deadlines and security fixes override a freeze, with written approval from the Head of Engineering in the decision log.

## 5. Alerting on SLOs - multi-window, multi-burn-rate

Burn rate = observed error ratio / (1 - SLO). For 99.99%, the budget ratio is 0.0001.

| Alert | Long window | Short window | Burn rate | Error ratio threshold (99.99%) | Budget used if sustained | Action |
|---|---|---|---|---|---|---|
| Fast burn | 1 h | 5 min | 14.4x | > 0.144% | 2% in 1 h | Page (P2 by default, auto-P1 if 2+ CUJs) |
| Slow burn | 6 h | 30 min | 6x | > 0.06% | 5% in 6 h | Page |
| Budget leak | 3 d | 6 h | 1x | > 0.01% | 10% in 3 d | Ticket to owning team |

- Long *and* short windows must both breach (CloudWatch composite alarm, `AND`). The short window makes the alert reset quickly after recovery.
- Detection time for a full outage: at 100% errors, the 1-hour window crosses 0.144% after about 5 seconds of errors. The alarm fires on the next 1-minute evaluation, so MTTD ~ 1-2 min.
- Minimum traffic guard: fast and slow alerts also need `SliTotal` >= 500 in the short window. Below that (02:00-05:00 MYT), the synthetic canary alarm carries paging (2 consecutive failed runs from either canary Region). Each Region has its own alarm, because CloudWatch composite alarms cannot combine alarms from two Regions.
- Implementation: CloudWatch metric-math alarms on `t1dx/SLI` + composite alarms -> [`slo_burn_rate_alarms.tf`](../terraform/observability/slo_burn_rate_alarms.tf). CloudWatch Application Signals request-based SLOs on the same metrics give the attainment and budget-remaining views and the 3-day burn report (look-back windows 5, 30, 60 and 360 min, plus 3 d).
- Thresholds for latency SLOs (99.0%) use the same burn multipliers on a 1% budget.

## 6. Reporting

| Audience | Cadence | Content | Tool |
|---|---|---|---|
| On-call | Real time | Burn rate per CUJ, per Region/AZ | CloudWatch dashboard `t1dx-cuj-overview` |
| Service teams | Weekly | Budget remaining, top consumers (incidents, deploys) | Application Signals SLO view + Amazon Managed Grafana |
| Engineering leadership | Monthly reliability review | SLO attainment, policy state, top risks, DR readiness | Report generated from SLO metrics |
| Risk / Compliance | Quarterly | Attainment, incidents, DR test evidence | Exported report + evidence bucket links |

## 7. Security, cost, ownership

| | |
|---|---|
| Security | SLIs come from API Gateway access logs and EMF metrics. Metric dimensions are route template and method only, so no customer data ends up in metrics. Access logs are masked by the `t1dx-mask-pii` data protection policy. |
| Cost | Two custom metrics per CUJ per Region (`SliTotal`, `SliBad`) plus the burn-rate alarms. Low cardinality keeps the metric bill small. |
| Ownership | Each SLO has an `owner_team` in [`slo-catalogue.yaml`](../slo/slo-catalogue.yaml). SRE owns the framework and the alarm code. The Head of Engineering signs off the error budget policy. |

## 8. Validation of this spec

- [ ] Replay 30 days of API Gateway access logs through the metric filters. Check that `SliBad` matches known incident windows.
- [ ] Use CloudWatch SLO recommendations (based on the last 30 days) to sanity-check targets before they become binding.
- [ ] Run synthetic fault injection (FIS + canary) and confirm the fast-burn page fires in <= 2 min ([06](06-game-day-plan.md)).
- [ ] Review the targets after 90 days: tighten if met easily, renegotiate if not achievable at reasonable cost.
