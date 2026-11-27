# Executive summary

> Selected cloud: AWS. Primary Region `ap-southeast-5` (Malaysia), recovery Region `ap-southeast-1` (Singapore), warm standby.

## The problem

The service has plenty of alerts but is slow to catch the failures customers actually feel. Retry storms have caused two regional incidents. DR has never been run end to end, and teams disagree on who owns reliability work.

I read these as one gap. Nobody has written down what "working" means for the customer, so neither the alerting nor the roadmap has anything to anchor to.

## What I propose

Detection comes first. Login, view balance and transfer acceptance are held to 99.99%, about 4.32 minutes of failure in 30 days. Completion by the payment switch is measured on its own at 99.9%, so a provider outage stays out of the 99.99% budget. Only SLO burn-rate alerts page anyone. A full outage should page within 1 to 2 minutes.

My reading of the two regional incidents is retries stacking up. CloudFront, the service client and the provider SDK each retried three times, which is 27x load on a dependency that is already slow. Now only one layer retries, capped at 10% of traffic, and every transfer carries an idempotency key so a retry cannot send the money twice. Worst case comes down to 1.21x.

For DR, Singapore runs a warm standby on Aurora Global Database. ARC routing controls move the traffic, and the switch is started from Singapore so it does not need the failed Region. Regional failover is a person's call on two independent signals, because automatic failover on a ledger risks split-brain. The 90 days end with a real production switchover. The design target is 25 minutes against the 45-minute RTO, and I would not trust that number until a game day has timed it.

On ownership, the team that ships a service owns its reliability. SRE owns the SLO framework and incident command, and leads DR. When a service runs out of error budget, feature work on it stops. SRE toil is capped at 50%.

## 90-day plan

| Days | Focus | Exit |
|---|---|---|
| 1-30 | Detection and governance | Burn-rate paging live, error budget policy signed |
| 31-60 | Retry budgets and DR automation | Staging Region switch in 25 minutes or less |
| 61-90 | Production DR proof and toil | Production switchover and failback done, SRE toil under 40% |

This needs SRE full time, about 30% of the platform team and 20% of sprint capacity from the payments and auth teams. The warm standby costs about 40-60% of the primary run cost ([docs/00 section 6](docs/00-architecture-overview.md#6-cost-order-of-magnitude-to-verify-in-aws-pricing-calculator)).

## Decisions needed from the bank

1. Risk and Compliance approval to replicate the critical data set to Singapore under BNM RMiT. Without it the design falls back to multi-AZ in Malaysia and the RTO and RPO have to be renegotiated.
2. Head of Engineering sign-off on the error budget policy, including reporting a regional failover against its own DR objective. One real regional event uses about six months of a 99.99% budget.

## Not proven yet

The Terraform has not been applied to an AWS account, and the RTO timings are estimates until game days L2 and L3. Detail is in the [README](README.md) and [docs 00-08](docs/).
