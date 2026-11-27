"""Builds diagrams/architecture.svg - t1dx Tier 1 digital service on AWS.

Diagram-as-code so names stay identical to docs/ and terraform/.
Usage:  python3 diagrams/src/build_architecture.py   (writes diagrams/architecture.svg)
PNG:    rendered from the SVG with headless Chromium (see diagrams/README.md).
"""
from pathlib import Path
from xml.sax.saxutils import escape

W, H = 1900, 1460
FONT = "Helvetica, Arial, sans-serif"

C = {
    "ink": "#1f2933",
    "muted": "#52606d",
    "region": "#1d4ed8",
    "region_bg": "#f5f8ff",
    "dr_bg": "#f7f7fb",
    "az": "#9aa5b1",
    "tb": "#c2410c",
    "aws": "#232f3e",
    "edge_bg": "#fff7ed",
    "box": "#ffffff",
    "svc": "#e0f2fe",
    "svc_bd": "#0369a1",
    "data": "#ede9fe",
    "data_bd": "#6d28d9",
    "msk": "#fef3c7",
    "msk_bd": "#b45309",
    "sec": "#dcfce7",
    "sec_bd": "#15803d",
    "repl": "#7c3aed",
    "ctrl": "#ea580c",
    "flow": "#111827",
    "standby": "#9aa5b1",
    "ext_bg": "#fdf2f8",
    "ext_bd": "#be185d",
}

out = []


def add(s):
    out.append(s)


def text(x, y, s, size=14, weight="normal", color=None, anchor="start", italic=False):
    style = "italic" if italic else "normal"
    add(
        f'<text x="{x}" y="{y}" font-family="{FONT}" font-size="{size}" font-weight="{weight}" '
        f'font-style="{style}" fill="{color or C["ink"]}" text-anchor="{anchor}">{escape(s)}</text>'
    )


def lines(x, y, rows, size=14, gap=None, **kw):
    gap = gap or int(size * 1.3)
    for i, r in enumerate(rows):
        if isinstance(r, tuple):
            s, w = r
            text(x, y + i * gap, s, size=size, weight=w, **kw)
        else:
            text(x, y + i * gap, r, size=size, **kw)


def rect(x, y, w, h, fill="#fff", stroke="#000", sw=1.5, rx=8, dash=None, opacity=1):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    add(
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" '
        f'fill-opacity="{opacity}" stroke="{stroke}" stroke-width="{sw}"{d}/>'
    )


def box(x, y, w, h, title, sub=(), fill=None, stroke=None, tsize=15, ssize=13, dash=None, center=True):
    rect(x, y, w, h, fill=fill or C["box"], stroke=stroke or C["aws"], dash=dash)
    cx = x + w / 2 if center else x + 10
    anchor = "middle" if center else "start"
    n = 1 + len(sub)
    total = tsize * 1.25 + len(sub) * ssize * 1.3
    ty = y + (h - total) / 2 + tsize
    text(cx, ty, title, size=tsize, weight="bold", anchor=anchor)
    for i, s in enumerate(sub):
        text(cx, ty + tsize * 0.35 + (i + 1) * ssize * 1.3, s, size=ssize, color=C["muted"], anchor=anchor)


def arrow(pts, color=None, sw=2, dash=None, head=True, marker="arrow"):
    color = color or C["flow"]
    d = " ".join(f"{'M' if i == 0 else 'L'}{x},{y}" for i, (x, y) in enumerate(pts))
    dd = f' stroke-dasharray="{dash}"' if dash else ""
    m = f' marker-end="url(#{marker}-{color.strip("#")})"' if head else ""
    add(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{sw}"{dd}{m}/>')


def step(x, y, n, color=None):
    color = color or C["flow"]
    add(f'<circle cx="{x}" cy="{y}" r="13" fill="{color}"/>')
    text(x, y + 5, str(n), size=13, weight="bold", color="#fff", anchor="middle")


def pill(x, y, w, s, fill=None, stroke=None, size=13):
    rect(x, y, w, 24, fill=fill or C["sec"], stroke=stroke or C["sec_bd"], sw=1, rx=12)
    text(x + w / 2, y + 17, s, size=size, anchor="middle", color=C["ink"])


def tb_label(x, y, s):
    w = 7.4 * len(s) + 18
    rect(x, y - 16, w, 22, fill="#fff", stroke=C["tb"], sw=1.2, rx=4)
    text(x + 9, y, s, size=13, weight="bold", color=C["tb"])


markers = {C["flow"], C["repl"], C["ctrl"], C["standby"], C["ext_bd"]}

add(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">')
add("<defs>")
for col in markers:
    add(
        f'<marker id="arrow-{col.strip("#")}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" '
        f'markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{col}"/></marker>'
    )
add("</defs>")
rect(0, 0, W, H, fill="#ffffff", stroke="#ffffff", rx=0)

# ---------------------------------------------------------------- title
text(30, 38, "t1dx – Tier 1 digital service · Selected cloud: AWS", size=24, weight="bold")
text(30, 62, "Warm standby: primary ap-southeast-5 (Malaysia) → recovery ap-southeast-1 (Singapore) · "
     "RTO 45 min (target 25) · RPO 5 min · CUJ availability 99.99%", size=15, color=C["muted"])

# ---------------------------------------------------------------- legend
lx, ly = 1320, 80
rect(lx, ly, 550, 118, fill="#fafafa", stroke="#d0d5dd", rx=6)
text(lx + 12, ly + 22, "Legend", size=14, weight="bold")
arrow([(lx + 14, ly + 42), (lx + 64, ly + 42)])
text(lx + 72, ly + 47, "sync request (numbered)", size=13)
arrow([(lx + 14, ly + 66), (lx + 64, ly + 66)], dash="7 5")
text(lx + 72, ly + 71, "async / standby path", size=13)
arrow([(lx + 14, ly + 90), (lx + 64, ly + 90)], color=C["repl"], sw=3, dash="2 4")
text(lx + 72, ly + 95, "cross-Region replication", size=13)
arrow([(lx + 280, ly + 42), (lx + 330, ly + 42)], color=C["ctrl"], dash="5 3")
text(lx + 338, ly + 47, "recovery control", size=13)
rect(lx + 280, ly + 58, 50, 18, fill="none", stroke=C["tb"], dash="8 5", rx=3)
text(lx + 338, ly + 72, "trust boundary (TBn)", size=13)
rect(lx + 280, ly + 84, 50, 18, fill=C["region_bg"], stroke=C["region"], sw=2.5, rx=3)
text(lx + 338, ly + 98, "failure domain (Region/AZ)", size=13)

# ---------------------------------------------------------------- internet
rect(30, 80, 1270, 110, fill="#fafafa", stroke="#d0d5dd", rx=6)
text(44, 102, "Internet (untrusted)", size=14, weight="bold", color=C["muted"])
box(560, 98, 340, 76, "Customers", ["Mobile app + web · traceparent + Idempotency-Key"])
box(60, 112, 300, 62, "CloudWatch RUM", ["real-user signals (web + mobile)"], fill="#f8fafc")
box(960, 112, 320, 62, "Synthetics canaries", ["t1dx-canary-cuj-apse5 / -apse1"], fill="#f8fafc")

# ---------------------------------------------------------------- global edge
rect(30, 214, 1840, 128, fill=C["edge_bg"], stroke=C["tb"], dash="9 6", rx=8)
tb_label(44, 236, "TB1  Internet → AWS edge (global)")
box(470, 246, 520, 86, "t1dx-cf-edge · Amazon CloudFront", [
    "AWS WAF (managed + rate rules) · Shield Advanced · TLS 1.2+",
    "API behaviour: no cache · origin connection attempts = 1",
])
box(50, 246, 380, 86, "Amazon Route 53 (public zone)", [
    "api-origin.t1dx.example · failover records",
    "RECOVERY_CONTROL health checks",
])
box(1040, 246, 470, 86, "ARC routing control · t1dx-arc-cluster", [
    "t1dx-rc-apse5 = ON · t1dx-rc-apse1 = OFF",
    "safety rule t1dx-arc-atleast-one-on · 5-Region data plane",
], stroke=C["ctrl"])
box(1530, 246, 320, 86, "ARC Region switch", [
    "plan t1dx-region-switch",
    "executed from Region being activated",
], stroke=C["ctrl"])

# flow 1: customers -> CloudFront
arrow([(730, 174), (730, 244)])
step(752, 210, 1)
# 2: CloudFront resolves origin in Route 53
arrow([(470, 289), (432, 289)])
step(451, 271, 2)
# routing control -> health checks
arrow([(1040, 300), (1015, 300), (1015, 337), (240, 337), (240, 334)], color=C["ctrl"], dash="5 3")
text(880, 356, "routing-control state drives DNS answer", size=12, color=C["ctrl"], anchor="end")

# ---------------------------------------------------------------- regions


def region(x0, code, name, role, primary):
    Wr = 860
    y0 = 372
    rect(x0, y0, Wr, 700, fill=C["region_bg"] if primary else C["dr_bg"], stroke=C["region"], sw=2.5, rx=10)
    text(x0 + 16, y0 + 26, f"Region {name}", size=17, weight="bold", color=C["region"])
    text(x0 + Wr - 16, y0 + 26, role, size=14, weight="bold",
         color=C["region"] if primary else C["muted"], anchor="end")
    text(x0 + 16, y0 + 46, "Failure domain: Region · 3 AZs", size=13, color=C["muted"], italic=True)

    # API gateway (TB2)
    tb_label(x0 + 16, y0 + 74, "TB2  edge → regional API")
    box(x0 + 250, y0 + 58, Wr - 270, 58, f"t1dx-api-{code} · API Gateway REST (Regional)", [
        "regional WAF (CloudFront-only header) · per-route throttling · integration timeout 8 s",
    ], stroke=C["aws"])

    # VPC boundary
    vy = y0 + 132
    rect(x0 + 14, vy, Wr - 28, 552, fill="#ffffff", stroke=C["tb"], dash="9 6", rx=8, opacity=0.6)
    tb_label(x0 + 26, vy + 22, "TB3  private VPC (no public workload subnets)")

    # AZ lanes
    lane_x = x0 + 30
    lane_w = (Wr - 60) / 3
    for i, az in enumerate("abc"):
        lx_ = lane_x + i * lane_w
        rect(lx_ + 3, vy + 34, lane_w - 6, 508, fill="none", stroke=C["az"], sw=1.2, dash="3 4", rx=6)
        text(lx_ + lane_w / 2, vy + 52, f"AZ {az}", size=13, weight="bold", color=C["muted"], anchor="middle")

    # NLB
    box(x0 + 40, vy + 62, Wr - 80, 40, "VPC Link → internal NLB (pod IP targets, cross-zone)", [], tsize=14)

    # EKS
    ey = vy + 116
    rect(x0 + 40, ey, Wr - 80, 200, fill=C["svc"], stroke=C["svc_bd"], sw=1.8)
    text(x0 + 52, ey + 22, f"t1dx-eks-{code} · Amazon EKS", size=15, weight="bold", color=C["svc_bd"])
    cap = "100% capacity" if primary else "30% running · 60% ODCR · scales on switch"
    text(x0 + Wr - 52, ey + 22, cap, size=13, color=C["muted"], anchor="end")
    svcs = ["auth-svc", "account-svc", "notification-svc", "messaging-adapter",
            "payment-adapter", "reconciliation-job", "transfer-svc", "outbox-relay"]
    pw = (Wr - 80 - 50) / 4
    for i, s in enumerate(svcs):
        r, c = divmod(i, 4)
        px = x0 + 50 + c * (pw + 10)
        py = ey + 96 + r * 44
        rect(px, py, pw, 34, fill="#fff", stroke=C["svc_bd"], sw=1.2, rx=6,
             dash=None if primary else "4 3")
        text(px + pw / 2, py + 22, s, size=14, weight="bold", anchor="middle")
    text(x0 + 52, ey + 44, "Karpenter (zonal-shift aware) · PDB + topology spread · HPA/KEDA · PriorityClass t1dx-critical",
         size=13, color=C["ink"])
    text(x0 + 52, ey + 63, "ARC zonal autoshift (EKS + NLB) · EKS Pod Identity · NetworkPolicies · Resilience4j breakers",
         size=13, color=C["ink"])
    text(x0 + 52, ey + 82, "OTel → CloudWatch Observability add-on (ADOT) · Application Signals",
         size=13, color=C["muted"])

    # TB4 data
    dy = ey + 214
    tb_label(x0 + 40, dy + 14, "TB4  workload → data (IAM auth, TLS, KMS)")
    box(x0 + 40, dy + 24, (Wr - 80) * 0.66, 34, f"RDS Proxy (IAM auth) → t1dx-aurora-{code} cluster", [], tsize=13)
    box(x0 + 40 + (Wr - 80) * 0.68, dy + 24, (Wr - 80) * 0.32, 34, f"t1dx-msk-{code} (IAM + TLS)", [], tsize=13,
        fill=C["msk"], stroke=C["msk_bd"])
    for i in range(3):
        lx_ = lane_x + i * lane_w
        if primary:
            a_t = ["Aurora writer", "Aurora reader", None][i]
        else:
            a_t = ["Aurora secondary (writer-ready)", "reader added on switch", None][i]
        if a_t:
            rect(lx_ + 12, dy + 68, lane_w - 24, 34, fill=C["data"], stroke=C["data_bd"], sw=1.4,
                 dash=None if (primary or i == 0) else "4 3")
            text(lx_ + lane_w / 2, dy + 90, a_t, size=13, weight="bold", anchor="middle")
        rect(lx_ + 12, dy + 108, lane_w - 24, 30, fill=C["msk"], stroke=C["msk_bd"], sw=1.2)
        text(lx_ + lane_w / 2, dy + 128, f"MSK broker {i + 1}", size=13, anchor="middle")
    text(x0 + 40 + lane_w * 2 + 20, dy + 90, f"t1dx-aurora-{code}", size=13, weight="bold", color=C["data_bd"])

    # egress TB5
    gy = dy + 152
    box(x0 + 40, gy, Wr - 80, 52, "Egress: AWS Network Firewall (domain/IP allowlist) → NAT GW",
        [f"static EIPs ({code}) pre-registered at both providers · mTLS client certs (Secrets Manager)"],
        tsize=14, stroke=C["tb"])
    return {
        "api": (x0 + 250 + (Wr - 270) / 2, y0 + 58),
        "api_bottom": (x0 + 520, y0 + 116),
        "nlb_top": (x0 + 520, vy + 62),
        "nlb_bottom": (x0 + 520, vy + 102),
        "eks_top": (x0 + 520, ey),
        "eks_bottom": ey + 200,
        "data_y": dy,
        "egress_bottom": (x0 + Wr / 2, gy + 52),
        "x0": x0,
        "lane_x": lane_x,
        "lane_w": lane_w,
        "ey": ey,
        "gy": gy,
    }


A = region(30, "apse5", "ap-southeast-5 (Malaysia)", "PRIMARY · ACTIVE", True)
B = region(1010, "apse1", "ap-southeast-1 (Singapore)", "RECOVERY · WARM STANDBY", False)

# CloudFront -> API GW (via Route 53 answer)
arrow([(600, 332), (600, 400), (A["api"][0], 400), (A["api"][0], A["api"][1])])
step(620, 380, 3)
arrow([(900, 332), (900, 364), (B["api"][0], 364), (B["api"][0], B["api"][1])], color=C["standby"], dash="7 5")
text(1200, 358, "after Region switch (standby path)", size=12, color=C["muted"])
# Region switch control arrows
arrow([(1690, 332), (1690, 372)], color=C["ctrl"], dash="5 3")
text(1700, 360, "activate apse1", size=12, color=C["ctrl"])

for R, primary in ((A, True), (B, False)):
    col = C["flow"] if primary else C["standby"]
    dash = None if primary else "7 5"
    arrow([R["api_bottom"], R["nlb_top"]], color=col, dash=dash)
    arrow([R["nlb_bottom"], R["eks_top"]], color=col, dash=dash)

step(A["api_bottom"][0] + 22, (A["api_bottom"][1] + A["nlb_top"][1]) / 2, 4)
# 5: transfer-svc -> RDS proxy ; 6 outbox -> MSK ; within region A
lx, lw, ey = A["lane_x"], A["lane_w"], A["ey"]
pw = (860 - 80 - 50) / 4
ts_x = A["x0"] + 50 + 2 * (pw + 10) + pw / 2 - 30   # transfer-svc
ob_x = A["x0"] + 50 + 3 * (pw + 10) + pw / 2   # outbox-relay centre
arrow([(ts_x, ey + 174), (ts_x, A["data_y"] + 24)])
step(ts_x + 22, ey + 196, 5)
arrow([(ob_x, ey + 174), (ob_x, A["data_y"] + 24)], dash="7 5")
step(ob_x + 22, ey + 196, 6)
# 7 / 8 to providers
egA = A["egress_bottom"]
egB = B["egress_bottom"]

# ---------------------------------------------------------------- replication in the gap
gx1, gx2 = 890, 1010
ry_a = A["data_y"] + 85
ry_m = A["data_y"] + 123
ry_e = A["ey"] + 60
arrow([(gx1 - 6, ry_a), (gx2 + 6, ry_a)], color=C["repl"], sw=3, dash="2 4")
arrow([(gx1 - 6, ry_m), (gx2 + 6, ry_m)], color=C["repl"], sw=3, dash="2 4")
arrow([(gx1 - 6, ry_e), (gx2 + 6, ry_e)], color=C["repl"], sw=3, dash="2 4")
rect(gx1 + 4, ry_e - 98, 112, 86, fill="#fff", stroke=C["repl"], sw=1, rx=6)
lines(gx1 + 60, ry_e - 80, [("R3", "bold"), "ECR images", "Secrets Mgr", "KMS MRK"], size=12, gap=17,
      anchor="middle", color=C["repl"])
rect(gx1 + 4, ry_a - 70, 112, 60, fill="#fff", stroke=C["repl"], sw=1, rx=6)
lines(gx1 + 60, ry_a - 52, [("R1", "bold"), "Aurora Global", "DB  (< 1 s)"], size=12, gap=17,
      anchor="middle", color=C["repl"])
rect(gx1 + 4, ry_m + 10, 112, 60, fill="#fff", stroke=C["repl"], sw=1, rx=6)
lines(gx1 + 60, ry_m + 28, [("R2", "bold"), "MSK Replicator", "+ offset sync"], size=12, gap=17,
      anchor="middle", color=C["repl"])
text(950, 1060, "t1dx-aurora-global", size=12, weight="bold", color=C["data_bd"], anchor="middle")

# ---------------------------------------------------------------- external providers (TB5)
py0 = 1100
rect(330, py0, 1240, 124, fill=C["ext_bg"], stroke=C["tb"], dash="9 6", rx=8)
tb_label(344, py0 + 22, "TB5  VPC → external providers (third-party failure domain)")
box(420, py0 + 38, 440, 60, "Provider A · ext-payment-switch", ["real-time payments · idempotent API · status query"],
    stroke=C["ext_bd"])
box(1040, py0 + 38, 440, 60, "Provider B · ext-messaging", ["SMS OTP + push · callbacks via API GW"],
    stroke=C["ext_bd"])
yb = 1086  # routing lane between Regions and provider zone
arrow([egA, (egA[0], yb), (830, yb), (830, py0 + 36)], dash="7 5")
step(egA[0] - 22, egA[1] + 16, 7)
arrow([(egA[0] + 160, egA[1]), (egA[0] + 160, yb - 8), (1240, yb - 8), (1240, py0 + 36)], dash="7 5")
step(egA[0] + 182, egA[1] + 16, 8)
arrow([egB, (egB[0], yb), (1420, yb), (1420, py0 + 36)], color=C["standby"], dash="7 5")
text(egB[0] + 12, yb - 4, "standby egress (EIPs allowlisted)", size=12, color=C["muted"])
text(950, py0 + 116, "mTLS · per-provider circuit breaker + bulkhead · retry budget 10% · timeouts 3 s / 2 s",
     size=13, color=C["ext_bd"], anchor="middle")

# ---------------------------------------------------------------- shared accounts
sy = 1250
rect(30, sy, 1840, 196, fill="#f8fafc", stroke="#d0d5dd", rx=8)
text(44, sy + 24, "Shared accounts (AWS Organizations + Control Tower) · present in both Regions", size=15,
     weight="bold", color=C["muted"])
tb_label(1500, sy + 24, "TB6  operators → AWS")
cards = [
    ("Observability account", ["CloudWatch cross-account observability",
                               "Application Signals SLOs · burn-rate alarms",
                               "Logs · Transaction Search · Synthetics",
                               "Amazon Managed Prometheus + Grafana"], C["svc_bd"]),
    ("Security + log archive", ["CloudTrail org trail · AWS Config",
                                "GuardDuty (EKS, RDS) · Security Hub",
                                "S3 Object Lock: t1dx-incident-evidence",
                                "CloudWatch Logs data protection (PII mask)"], C["sec_bd"]),
    ("Operator access", ["IAM Identity Center · MFA",
                         "break-glass roles (both Regions)",
                         "SCPs · recovery roles pre-provisioned",
                         "AWS Health → EventBridge"], C["tb"]),
    ("Alert routing (hybrid, justified)", ["Alarms → EventBridge / SNS t1dx-page-<team>",
                                          "→ bank paging / ITSM (SaaS)",
                                          "Amazon Q Developer in chat apps",
                                          "Incident Manager closed to new customers"], C["ext_bd"]),
]
cw = (1840 - 50) / 4
for i, (t, rows, col) in enumerate(cards):
    cx = 40 + i * (cw + 10)
    rect(cx, sy + 40, cw - 10, 146, fill="#fff", stroke=col, sw=1.6)
    text(cx + 12, sy + 64, t, size=15, weight="bold", color=col)
    lines(cx + 12, sy + 88, rows, size=13, gap=22)

add("</svg>")

dst = Path(__file__).resolve().parents[1] / "architecture.svg"
dst.write_text("\n".join(out), encoding="utf-8")
print(f"wrote {dst}")
