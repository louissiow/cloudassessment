# Sources and AI assistance

> Selected cloud: AWS. AWS behaviour, limits and prices were checked against these sources on 26 Nov 2026. Prices and features change, so verify before you implement.

## AWS documentation and announcements

| Topic | Source | Used in |
|---|---|---|
| Aurora Global Database switchover vs failover, old-primary snapshot, write fencing, `rds.global_db_rpo`, global writer endpoint, `AuroraGlobalDBRPOLag` | [Using switchover or failover in Aurora Global Database](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database-disaster-recovery.html) | 05, terraform/recovery |
| Aurora Global Database Region support (Malaysia, Singapore) | [Supported Regions and DB engines for Aurora global databases](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Concepts.Aurora_Fea_Regions_DB-eng.Feature.GlobalDatabase.html) | README A3/A4 |
| Aurora DSQL Region list (no ap-southeast-5 endpoint) and multi-Region availability figures | [Aurora DSQL endpoints](https://docs.aws.amazon.com/general/latest/gr/dsql.html), [What is Aurora DSQL?](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/what-is-aurora-dsql.html) | 04 section 10 |
| ARC Region switch: plans run from the Region being activated, 30-min plan evaluation, pricing | [Introducing ARC Region switch (AWS News Blog)](https://aws.amazon.com/blogs/aws/introducing-amazon-application-recovery-controller-region-switch-a-multi-region-application-recovery-service) | 05, 06 |
| Region switch execution blocks (EKS scaling, Aurora Global DB, Aurora scaling, routing control, manual approval, Lambda). Capacity not guaranteed | [Add execution blocks](https://docs.aws.amazon.com/r53recovery/latest/dg/working-with-rs-execution-blocks.html), [Aurora scaling block (Jun 2026)](https://aws.amazon.com/about-aws/whats-new/2026/06/region-switch-aurora-scaling-neptune-failover) | 05 |
| `StartPlanExecution` parameters | [API reference](https://docs.aws.amazon.com/arc-region-switch/latest/api/API_StartPlanExecution.html) | 05 |
| ARC pricing (routing control cluster, Region switch plan, zonal shift) | [ARC pricing](https://aws.amazon.com/application-recovery-controller/pricing), [Routing control pricing](https://docs.aws.amazon.com/r53recovery/latest/dg/introduction-pricing-routing-control.html) | 00 |
| EKS + ARC zonal shift / autoshift. Karpenter zonal shift support | [EKS zonal shift](https://docs.aws.amazon.com/eks/latest/userguide/zone-shift.html), [Karpenter + ARC zonal shift (May 2026)](https://aws.amazon.com/about-aws/whats-new/2026/05/karpenter-arc-zonal-shift/), [EKS ARC support](https://aws.amazon.com/blogs/containers/amazon-eks-now-supports-amazon-application-recovery-controller) | 04 |
| FIS recovery action / zonal autoshift testing | [Testing zonal autoshift with AWS FIS](https://docs.aws.amazon.com/r53recovery/latest/dg/testing-zonal-autoshift-fis.html) | 06 |
| Incident Manager closed to new customers (7 Nov 2025) | [Incident Manager availability change](https://docs.aws.amazon.com/incident-manager/latest/userguide/incident-manager-availability-change.html), [Migration guides](https://docs.aws.amazon.com/incident-manager/latest/userguide/migration-guides.html) | README A7, 03 |
| CloudWatch SLOs: request vs period based, burn-rate look-back windows, multi-window composite alarms | [CloudWatch service level objectives](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-ServiceLevelObjectives.html), [Request-based SLOs](https://aws.amazon.com/about-aws/whats-new/2024/09/cloudwatch-application-signals-service-level-objectives), [Burn rate support](https://aws.amazon.com/about-aws/whats-new/2024/11/application-signals-burn-rate-application-performance-goals) | 02, 03 |
| MSK available in Malaysia Region | [What's New, Dec 2024](https://aws.amazon.com/about-aws/whats-new/2024/12/amazon-msk-asia-pacific-malaysia-region) | README A3 |
| MSK Replicator: identical topic names, offset sync | [Identical topic names (Sep 2024)](https://aws.amazon.com/about-aws/whats-new/2024/09/amazon-msk-cross-cluster-replication-identical-topic-names), [MSK Replicator active-passive](https://docs.aws.amazon.com/msk/latest/developerguide/msk-replicators-active-passive-cluster-setup.html) | 00, 05 |
| SLAs: MSK, EKS (99.95% standard, 99.99% Provisioned Control Plane), API Gateway 99.95%, Aurora Multi-AZ 99.99% | [MSK SLA](https://aws.amazon.com/msk/sla), [EKS SLA](https://aws.amazon.com/eks/sla/), [EKS 99.99% (Mar 2026)](https://aws.amazon.com/about-aws/whats-new/2026/03/amazon-eks-announces-sla-8xl-scaling-tier), [API Gateway SLA](https://aws.amazon.com/api-gateway/sla), [Aurora SLA](https://aws.amazon.com/aurora/sla/), [All AWS SLAs](https://aws.amazon.com/legal/service-level-agreements) | 02 |
| Malaysia Region launch | [AWS Asia Pacific (Malaysia) Region now open](https://aws.amazon.com/blogs/aws/now-open-aws-asia-pacific-malaysia-region) | README |

## Practice references (general SRE knowledge)

| Topic | Reference |
|---|---|
| Multi-window, multi-burn-rate alerting (14.4x / 6x / 1x) | Google, *The Site Reliability Workbook*, ch. 5 "Alerting on SLOs" |
| Error budget policy, toil cap (50%) | Google, *Site Reliability Engineering*, ch. 3 and 5 |
| Exponential backoff with full jitter. Retry budgets. Load shedding | AWS Builders' Library: "Timeouts, retries and backoff with jitter", "Using load shedding to avoid overload" |
| Static stability, control plane vs data plane | AWS Builders' Library: "Static stability using Availability Zones". AWS whitepaper "Advanced Multi-AZ Resilience Patterns" |
| Incident Command System roles | Google SRE book, ch. 14 "Managing Incidents" |
| Transactional outbox pattern | Standard microservices pattern (Richardson, *Microservices Patterns*) |

## AI assistance

| Item | Detail |
|---|---|
| Tool | Claude (Anthropic), via the Claude app |
| Used for | Breaking down the requirements, first drafts of the docs (including the executive summary), the diagram generator script and the Terraform/YAML samples. A final review pass for wording and checklist coverage. |
| Human work | Scope, Region choice and assumptions. Review and edit of every file. Checking AWS facts against the sources above. Arithmetic checks. Name-consistency check. Final decisions. |
| Automated checks run | YAML parse of all `*.yaml`. Mermaid render of every diagram block. `grep` name-consistency check. Architecture SVG rendered and visually inspected. |
| Not verified | `terraform validate` / `plan` (no AWS account or registry access during drafting) |
