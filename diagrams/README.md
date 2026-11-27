# Diagrams

| File | What |
|---|---|
| `architecture.png` | Mandatory architecture diagram (selected cloud: AWS): trust boundaries TB1-TB6, numbered traffic flow 1-8, replication R1-R3, failure domains (Regions, AZs, external providers), security controls, key service names |
| `architecture.svg` | Same, vector (zoomable) |
| `src/build_architecture.py` | Diagram-as-code generator, so names match the docs and Terraform |
| `roadmap-gantt.png` | 90-day roadmap timeline used in docs/08 |
| `src/roadmap-gantt.mmd` | Mermaid source for the roadmap timeline (`mmdc -i diagrams/src/roadmap-gantt.mmd -o diagrams/roadmap-gantt.png -w 1600 -s 2 -b white`) |
| `src/render_png.js` | Renders the SVG to PNG with headless Chromium (Playwright) |

Rebuild:

```bash
python3 diagrams/src/build_architecture.py
node diagrams/src/render_png.js "$PWD/diagrams/architecture.svg" "$PWD/diagrams/architecture.png" 2
```

Flow key: 1 customer -> CloudFront, 2 origin resolved via Route 53 (ARC routing control health checks), 3 -> `t1dx-api-apse5`, 4 VPC Link -> NLB -> EKS, 5 `transfer-svc` -> RDS Proxy -> Aurora (transfer + idempotency key + outbox in one transaction), 6 outbox relay -> MSK (async), 7 `payment-adapter` -> Network Firewall -> `ext-payment-switch`, 8 `messaging-adapter` -> `ext-messaging`. R1 Aurora Global Database, R2 MSK Replicator, R3 ECR / Secrets Manager / KMS multi-Region keys.
