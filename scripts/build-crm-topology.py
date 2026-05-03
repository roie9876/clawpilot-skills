#!/usr/bin/env python3
"""Generate the CRM-pipeline topology diagram (SVG + PNG).

Uses inline SVG with brand-styled Microsoft product icons (Outlook, Calendar,
Teams, Git, Dynamics 365). Renders to PNG via cairosvg.

Outputs:
  docs/crm-pipeline-topology.svg
  docs/crm-pipeline-topology.png

Run:  python3 scripts/build-crm-topology.py
"""
from __future__ import annotations
from pathlib import Path
import cairosvg

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "docs"
OUT_DIR.mkdir(exist_ok=True)
SVG_PATH = OUT_DIR / "crm-pipeline-topology.svg"
PNG_PATH = OUT_DIR / "crm-pipeline-topology.png"

W, H = 1600, 880

# ---- Icon library (inline SVG groups) -------------------------------------
ICON_OUTLOOK = """
<g>
  <rect x="0" y="0" width="56" height="56" rx="8" ry="8" fill="#0078D4"/>
  <rect x="6" y="14" width="34" height="28" fill="#fff"/>
  <path d="M6 14 L23 32 L40 14" stroke="#0078D4" stroke-width="2.4" fill="none"/>
  <text x="46" y="44" font-family="Segoe UI, Helvetica, Arial" font-size="20"
        font-weight="700" fill="#fff" text-anchor="middle">O</text>
</g>"""

ICON_CALENDAR = """
<g>
  <rect x="2" y="6" width="52" height="46" rx="6" ry="6" fill="#fff" stroke="#0078D4" stroke-width="2"/>
  <rect x="2" y="6" width="52" height="14" rx="6" ry="6" fill="#0078D4"/>
  <rect x="2" y="14" width="52" height="6" fill="#0078D4"/>
  <rect x="12" y="2" width="4" height="12" rx="1.5" fill="#0078D4"/>
  <rect x="40" y="2" width="4" height="12" rx="1.5" fill="#0078D4"/>
  <text x="28" y="44" font-family="Segoe UI, Helvetica, Arial" font-size="22"
        font-weight="700" fill="#0078D4" text-anchor="middle">31</text>
</g>"""

ICON_TEAMS = """
<g>
  <rect x="0" y="0" width="56" height="56" rx="8" ry="8" fill="#4B53BC"/>
  <circle cx="40" cy="20" r="6" fill="#fff" opacity="0.9"/>
  <path d="M30 38 a10 10 0 0 1 20 0 v6 h-20 z" fill="#fff" opacity="0.9"/>
  <rect x="6" y="14" width="22" height="28" rx="2" fill="#fff"/>
  <text x="17" y="36" font-family="Segoe UI, Helvetica, Arial" font-size="22"
        font-weight="700" fill="#4B53BC" text-anchor="middle">T</text>
</g>"""

ICON_GIT = """
<g>
  <circle cx="14" cy="14" r="6" fill="#F05032"/>
  <circle cx="14" cy="42" r="6" fill="#F05032"/>
  <circle cx="42" cy="28" r="6" fill="#F05032"/>
  <path d="M14 20 L14 36" stroke="#F05032" stroke-width="3" fill="none"/>
  <path d="M14 28 C 24 28, 32 28, 36 28" stroke="#F05032" stroke-width="3" fill="none"/>
</g>"""

# Dynamics 365 brand-styled icon — blue rounded square with stylized "D"
ICON_DYNAMICS = """
<g>
  <defs>
    <linearGradient id="dynGrad" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#0B5394"/>
      <stop offset="100%" stop-color="#002050"/>
    </linearGradient>
  </defs>
  <rect x="0" y="0" width="56" height="56" rx="8" ry="8" fill="url(#dynGrad)"/>
  <path d="M14 12 L14 44 L30 44 C 42 44, 46 36, 46 28 C 46 20, 42 12, 30 12 Z"
        fill="#fff"/>
  <path d="M22 20 L22 36 L30 36 C 36 36, 38 32, 38 28 C 38 24, 36 20, 30 20 Z"
        fill="#0B5394"/>
</g>"""


def icon(name: str, x: float, y: float, scale: float = 1.0) -> str:
    body = {
        "outlook": ICON_OUTLOOK,
        "calendar": ICON_CALENDAR,
        "teams": ICON_TEAMS,
        "git": ICON_GIT,
        "dynamics": ICON_DYNAMICS,
    }[name]
    return f'<g transform="translate({x} {y}) scale({scale})">{body}</g>'


# ---- Layout ---------------------------------------------------------------
SRC_X, SRC_W, SRC_H = 60, 220, 64
SRC_Y0, SRC_GAP = 200, 16
sources = [
    ("calendar", "M365 Calendar"),
    ("outlook", "Sent Emails (Outlook)"),
    ("teams", "Teams Chat (SSP)"),
    ("git", "Git Repos"),
]

DAL = dict(x=340, y=210, w=320, h=150)
SYNC = dict(x=1060, y=210, w=320, h=150)
MSX = dict(x=1060, y=470, w=320, h=150)
CR = dict(x=60, y=620, w=320, h=150)
LOG = dict(x=750, y=460, w=220, h=80)
EXT = dict(x=1100, y=700, w=220, h=110)


# ---- SVG assembly ---------------------------------------------------------
parts: list[str] = []
parts.append(
    f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" '
    f'width="{W}" height="{H}" font-family="Segoe UI, Helvetica, Arial, sans-serif">'
)
parts.append(f'<rect width="{W}" height="{H}" fill="#ffffff"/>')
parts.append('<rect x="20" y="180" width="1560" height="460" fill="#fafafa" rx="6"/>')

parts.append('''<defs>
  <marker id="arr" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse">
    <path d="M0 0 L10 5 L0 10 z" fill="#334155"/>
  </marker>
  <marker id="arrSoft" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse">
    <path d="M0 0 L10 5 L0 10 z" fill="#94a3b8"/>
  </marker>
  <marker id="arrFound" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse">
    <path d="M0 0 L10 5 L0 10 z" fill="#10b981"/>
  </marker>
  <filter id="softShadow" x="-10%" y="-10%" width="120%" height="130%">
    <feGaussianBlur in="SourceAlpha" stdDeviation="3"/>
    <feOffset dx="0" dy="2" result="offsetblur"/>
    <feComponentTransfer><feFuncA type="linear" slope="0.18"/></feComponentTransfer>
    <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
  </filter>
</defs>''')

parts.append(
    f'<text x="{W//2}" y="60" text-anchor="middle" font-size="30" font-weight="700" fill="#0f172a">'
    f'Customer CRM Pipeline — How These 4 Skills Work Together</text>'
)
parts.append(
    f'<text x="{W//2}" y="92" text-anchor="middle" font-size="16" fill="#475569">'
    f'M365 + Git activity, captured into daily logs, pushed to MSX (Dynamics 365)</text>'
)

parts.append(
    f'<text x="{SRC_X}" y="{SRC_Y0 - 22}" font-size="12" font-weight="700" fill="#64748b" letter-spacing="1.4">DATA SOURCES</text>'
)
parts.append(
    f'<text x="{CR["x"]}" y="{CR["y"] - 22}" font-size="12" font-weight="700" fill="#047857" letter-spacing="1.4">FOUNDATION (used by every skill)</text>'
)

src_centers = []
for i, (icon_name, label) in enumerate(sources):
    y = SRC_Y0 + i * (SRC_H + SRC_GAP)
    parts.append(
        f'<rect x="{SRC_X}" y="{y}" width="{SRC_W}" height="{SRC_H}" rx="10" '
        f'fill="#f8fafc" stroke="#cbd5e1" stroke-width="1" filter="url(#softShadow)"/>'
    )
    parts.append(icon(icon_name, SRC_X + 10, y + 4, scale=0.85))
    parts.append(
        f'<text x="{SRC_X + 70}" y="{y + SRC_H/2 + 5}" font-size="15" font-weight="600" fill="#1e293b">{label}</text>'
    )
    src_centers.append((SRC_X + SRC_W, y + SRC_H // 2))


def skill_box(b, title, body_lines, color_bg, color_border, color_title, icon_svg=None):
    parts.append(
        f'<rect x="{b["x"]}" y="{b["y"]}" width="{b["w"]}" height="{b["h"]}" rx="14" '
        f'fill="{color_bg}" stroke="{color_border}" stroke-width="2" filter="url(#softShadow)"/>'
    )
    if icon_svg:
        parts.append(icon_svg)
    title_x = b["x"] + (76 if icon_svg else 18)
    parts.append(
        f'<text x="{title_x}" y="{b["y"] + 36}" font-size="20" font-weight="700" fill="{color_title}">{title}</text>'
    )
    for i, line in enumerate(body_lines):
        parts.append(
            f'<text x="{b["x"] + 18}" y="{b["y"] + 70 + i*22}" font-size="14" fill="#1f2937">{line}</text>'
        )


skill_box(DAL, "/daily-activity-log",
    ["Aggregates calendar, email, Teams chat,",
     "and git commits into one activity-log.md",
     "per project — classified by CRM category."],
    "#eff6ff", "#2563eb", "#1e3a8a")

skill_box(SYNC, "/crm-activity-sync",
    ["Reads activity-log.md and creates",
     "milestone tasks in MSX. Idempotent,",
     "auto-joins deal teams."],
    "#eff6ff", "#2563eb", "#1e3a8a")

skill_box(MSX, "/msx-crm",
    ["Backend tool layer (Node CLI).",
     "Query accounts, opportunities,",
     "milestones, tasks, deal teams."],
    "#f5f3ff", "#7c3aed", "#5b21b6",
    icon_svg=icon("dynamics", MSX["x"] + 14, MSX["y"] + 14, scale=0.8))

skill_box(CR, "/customer-repo",
    ["Scaffolds the per-customer folder",
     "structure that every other skill",
     "reads &amp; writes inside."],
    "#ecfdf5", "#10b981", "#065f46")

# activity-log.md note
parts.append(
    f'<rect x="{LOG["x"]}" y="{LOG["y"]}" width="{LOG["w"]}" height="{LOG["h"]}" rx="10" '
    f'fill="#fffbeb" stroke="#d97706" stroke-width="2" filter="url(#softShadow)"/>'
)
parts.append(
    f'<text x="{LOG["x"] + LOG["w"]/2}" y="{LOG["y"] + 32}" text-anchor="middle" '
    f'font-size="18" font-weight="700" fill="#78350f">activity-log.md</text>'
)
parts.append(
    f'<text x="{LOG["x"] + LOG["w"]/2}" y="{LOG["y"] + 56}" text-anchor="middle" '
    f'font-size="13" fill="#92400e">(per customer project)</text>'
)

# External MSX (Dynamics 365)
parts.append(
    f'<rect x="{EXT["x"]}" y="{EXT["y"]}" width="{EXT["w"]}" height="{EXT["h"]}" rx="20" '
    f'fill="#fdf2f8" stroke="#db2777" stroke-width="2" filter="url(#softShadow)"/>'
)
parts.append(icon("dynamics", EXT["x"] + 14, EXT["y"] + 22, scale=1.1))
parts.append(
    f'<text x="{EXT["x"] + EXT["w"] - 16}" y="{EXT["y"] + 38}" text-anchor="end" '
    f'font-size="20" font-weight="700" fill="#9d174d">MSX</text>'
)
parts.append(
    f'<text x="{EXT["x"] + EXT["w"] - 16}" y="{EXT["y"] + 62}" text-anchor="end" '
    f'font-size="12" fill="#9d174d">Microsoft Sales</text>'
)
parts.append(
    f'<text x="{EXT["x"] + EXT["w"] - 16}" y="{EXT["y"] + 78}" text-anchor="end" '
    f'font-size="12" fill="#9d174d">Experience</text>'
)
parts.append(
    f'<text x="{EXT["x"] + EXT["w"] - 16}" y="{EXT["y"] + 96}" text-anchor="end" '
    f'font-size="11" fill="#be185d" font-style="italic">(Dynamics 365)</text>'
)


def line(x1, y1, x2, y2, marker="arr", stroke="#334155", width=2.4, dash=False):
    da = ' stroke-dasharray="6,5"' if dash else ""
    parts.append(
        f'<path d="M{x1} {y1} L{x2} {y2}" stroke="{stroke}" stroke-width="{width}" '
        f'fill="none" marker-end="url(#{marker})"{da}/>'
    )


# Sources -> /daily-activity-log (curved fan-in)
dal_in_x = DAL["x"]
dal_in_y = DAL["y"] + DAL["h"] // 2
for sx, sy in src_centers:
    cx = (sx + dal_in_x) / 2
    parts.append(
        f'<path d="M{sx} {sy} C {cx} {sy}, {cx} {dal_in_y}, {dal_in_x - 4} {dal_in_y}" '
        f'stroke="#94a3b8" stroke-width="2" fill="none" marker-end="url(#arrSoft)"/>'
    )

line(DAL["x"] + DAL["w"] // 2, DAL["y"] + DAL["h"],
     LOG["x"] + 60, LOG["y"], width=3)
parts.append(
    f'<text x="{DAL["x"] + DAL["w"]//2 + 80}" y="{DAL["y"] + DAL["h"] + 30}" '
    f'font-size="13" font-weight="600" fill="#475569">writes</text>'
)

line(LOG["x"] + LOG["w"], LOG["y"] + LOG["h"] // 2,
     SYNC["x"], SYNC["y"] + SYNC["h"] - 30, width=3)
parts.append(
    f'<text x="{LOG["x"] + LOG["w"] + 14}" y="{LOG["y"] + 30}" '
    f'font-size="13" font-weight="600" fill="#475569">reads</text>'
)

line(SYNC["x"] + SYNC["w"] // 2, SYNC["y"] + SYNC["h"],
     MSX["x"] + MSX["w"] // 2, MSX["y"], width=3)
parts.append(
    f'<text x="{SYNC["x"] + SYNC["w"]//2 + 12}" y="{SYNC["y"] + SYNC["h"] + 28}" '
    f'font-size="13" font-weight="600" fill="#475569">uses tools</text>'
)

line(MSX["x"] + MSX["w"] // 2, MSX["y"] + MSX["h"],
     EXT["x"] + EXT["w"] // 2, EXT["y"], width=3)
parts.append(
    f'<text x="{MSX["x"] + MSX["w"]//2 + 14}" y="{MSX["y"] + MSX["h"] + 28}" '
    f'font-size="13" font-weight="600" fill="#475569">OData / API</text>'
)

# /customer-repo -> log + dal (foundation, dashed green)
line(CR["x"] + CR["w"], CR["y"] + 40,
     DAL["x"] + 60, DAL["y"] + DAL["h"], stroke="#10b981",
     marker="arrFound", width=2, dash=True)
line(CR["x"] + CR["w"], CR["y"] + CR["h"] // 2,
     LOG["x"], LOG["y"] + LOG["h"] // 2, stroke="#10b981",
     marker="arrFound", width=2, dash=True)

# Legend
LEG_Y = H - 50
parts.append(
    f'<text x="60" y="{LEG_Y - 14}" font-size="11" font-weight="700" '
    f'fill="#64748b" letter-spacing="1.4">LEGEND</text>'
)
legend_items = [
    ("#eff6ff", "#2563eb", "Skill (LLM-driven)"),
    ("#f5f3ff", "#7c3aed", "Backend tool layer"),
    ("#ecfdf5", "#10b981", "Foundation / scaffold"),
    ("#fffbeb", "#d97706", "File on disk"),
    ("#fdf2f8", "#db2777", "External system"),
    ("#f8fafc", "#cbd5e1", "Data source"),
]
lx = 60
for fill, stroke, label in legend_items:
    parts.append(
        f'<rect x="{lx}" y="{LEG_Y - 4}" width="22" height="14" rx="3" '
        f'fill="{fill}" stroke="{stroke}" stroke-width="1.4"/>'
    )
    parts.append(
        f'<text x="{lx + 30}" y="{LEG_Y + 7}" font-size="13" fill="#1f2937">{label}</text>'
    )
    lx += 230

parts.append("</svg>")

svg = "\n".join(parts)
SVG_PATH.write_text(svg)
print(f"wrote {SVG_PATH}")

cairosvg.svg2png(bytestring=svg.encode("utf-8"),
                 output_width=W * 2, write_to=str(PNG_PATH))
print(f"wrote {PNG_PATH}  ({PNG_PATH.stat().st_size // 1024} KB)")
