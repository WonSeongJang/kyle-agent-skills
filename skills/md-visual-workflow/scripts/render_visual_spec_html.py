#!/usr/bin/env python3
"""Render visual-spec JSON into a clean standalone HTML preview.

The visual spec is intentionally small and flexible. It is meant to describe
the visual argument, not every pixel of the final design.
"""

from __future__ import annotations

import argparse
import html
import json
from pathlib import Path
from typing import Any


def esc(value: Any) -> str:
    return html.escape(str(value or ""))


def item_card(item: dict[str, Any], index: int | None = None) -> str:
    badge = item.get("badge")
    badge_html = f'<span class="item-badge">{esc(badge)}</span>' if badge else ""
    number_html = f'<span class="item-number">{index}</span>' if index is not None else ""
    meta = item.get("meta")
    meta_html = f'<p class="item-meta">{esc(meta)}</p>' if meta else ""
    return f"""
      <article class="item-card">
        <div class="item-topline">{number_html}{badge_html}</div>
        <h3>{esc(item.get("label") or item.get("title"))}</h3>
        <p>{esc(item.get("description"))}</p>
        {meta_html}
      </article>
    """


def render_flow(section: dict[str, Any]) -> str:
    items = section.get("items", [])
    parts: list[str] = []
    for idx, item in enumerate(items, start=1):
        parts.append(item_card(item, idx))
        if idx < len(items):
            parts.append('<div class="arrow" aria-hidden="true">-></div>')
    return f"""
    <section class="visual-section">
      <div class="section-heading">
        <span class="section-kicker">Flow</span>
        <h2>{esc(section.get("title"))}</h2>
      </div>
      <div class="flow-row">{''.join(parts)}</div>
    </section>
    """


def render_cards(section: dict[str, Any]) -> str:
    items = section.get("items", [])
    cards = "".join(item_card(item) for item in items)
    return f"""
    <section class="visual-section">
      <div class="section-heading">
        <span class="section-kicker">Cards</span>
        <h2>{esc(section.get("title"))}</h2>
      </div>
      <div class="card-grid">{cards}</div>
    </section>
    """


def render_comparison(section: dict[str, Any]) -> str:
    columns = section.get("columns") or section.get("items") or []
    rendered_columns: list[str] = []
    for column in columns:
        points = column.get("points") or []
        point_html = "".join(f"<li>{esc(point)}</li>" for point in points)
        rendered_columns.append(
            f"""
            <article class="compare-card">
              <div class="compare-label">{esc(column.get("badge"))}</div>
              <h3>{esc(column.get("label") or column.get("title"))}</h3>
              <p>{esc(column.get("description"))}</p>
              <ul>{point_html}</ul>
            </article>
            """
        )
    return f"""
    <section class="visual-section">
      <div class="section-heading">
        <span class="section-kicker">Compare</span>
        <h2>{esc(section.get("title"))}</h2>
      </div>
      <div class="comparison-grid">{''.join(rendered_columns)}</div>
    </section>
    """


def render_lanes(section: dict[str, Any]) -> str:
    lanes = section.get("lanes") or section.get("items") or []
    rendered_lanes: list[str] = []
    for lane in lanes:
        steps = lane.get("steps") or lane.get("items") or []
        steps_html = "".join(item_card(step, idx) for idx, step in enumerate(steps, start=1))
        rendered_lanes.append(
            f"""
            <article class="lane">
              <h3>{esc(lane.get("label") or lane.get("title"))}</h3>
              <div class="lane-steps">{steps_html}</div>
            </article>
            """
        )
    return f"""
    <section class="visual-section">
      <div class="section-heading">
        <span class="section-kicker">Lanes</span>
        <h2>{esc(section.get("title"))}</h2>
      </div>
      <div class="lane-grid">{''.join(rendered_lanes)}</div>
    </section>
    """


def render_timeline(section: dict[str, Any]) -> str:
    items = section.get("items", [])
    timeline = "".join(
        f"""
        <article class="timeline-item">
          <span>{idx}</span>
          <div>
            <h3>{esc(item.get("label") or item.get("title"))}</h3>
            <p>{esc(item.get("description"))}</p>
          </div>
        </article>
        """
        for idx, item in enumerate(items, start=1)
    )
    return f"""
    <section class="visual-section">
      <div class="section-heading">
        <span class="section-kicker">Timeline</span>
        <h2>{esc(section.get("title"))}</h2>
      </div>
      <div class="timeline">{timeline}</div>
    </section>
    """


def render_section(section: dict[str, Any]) -> str:
    section_type = (section.get("type") or "cards").lower()
    if section_type == "flow":
        return render_flow(section)
    if section_type == "comparison":
        return render_comparison(section)
    if section_type == "lanes":
        return render_lanes(section)
    if section_type == "timeline":
        return render_timeline(section)
    return render_cards(section)


def build_html(spec: dict[str, Any]) -> str:
    theme = spec.get("theme") or {}
    accent = theme.get("accent") or "#2563eb"
    secondary = theme.get("secondary") or "#16a34a"
    mode = (spec.get("mode") or "idea").upper()
    sections = "\n".join(render_section(section) for section in spec.get("sections", []))
    notes = spec.get("notes") or []
    notes_html = ""
    if notes:
        notes_html = "<aside class=\"notes\"><h2>Source Notes</h2><ul>"
        notes_html += "".join(f"<li>{esc(note)}</li>" for note in notes)
        notes_html += "</ul></aside>"

    return f"""<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{esc(spec.get("title"))}</title>
  <style>
    :root {{
      --bg: #f8fafc;
      --panel: #ffffff;
      --text: #0f172a;
      --muted: #475569;
      --line: #dbeafe;
      --accent: {esc(accent)};
      --secondary: {esc(secondary)};
      --soft-accent: color-mix(in srgb, var(--accent) 10%, white);
      --soft-secondary: color-mix(in srgb, var(--secondary) 10%, white);
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", "Noto Sans KR", sans-serif;
      line-height: 1.55;
    }}
    main {{
      width: min(1180px, calc(100vw - 48px));
      margin: 40px auto;
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 18px;
      padding: 42px;
      box-shadow: 0 18px 50px rgba(15, 23, 42, 0.08);
    }}
    header {{
      display: grid;
      gap: 12px;
      margin-bottom: 30px;
    }}
    .badge-row {{
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      align-items: center;
    }}
    .mode-badge, .audience-badge {{
      display: inline-flex;
      align-items: center;
      min-height: 30px;
      padding: 5px 12px;
      border-radius: 999px;
      font-size: 13px;
      font-weight: 800;
    }}
    .mode-badge {{
      background: var(--soft-accent);
      color: var(--accent);
    }}
    .audience-badge {{
      background: #f1f5f9;
      color: var(--muted);
    }}
    h1 {{
      margin: 0;
      font-size: 38px;
      line-height: 1.18;
      letter-spacing: 0;
    }}
    .subtitle {{
      max-width: 900px;
      margin: 0;
      color: var(--muted);
      font-size: 18px;
    }}
    .message {{
      margin-top: 8px;
      padding: 16px 18px;
      border-left: 5px solid var(--accent);
      background: var(--soft-accent);
      border-radius: 12px;
      font-size: 17px;
      font-weight: 700;
    }}
    .visual-section {{
      margin-top: 30px;
      padding-top: 28px;
      border-top: 1px solid #e2e8f0;
    }}
    .section-heading {{
      display: flex;
      align-items: baseline;
      justify-content: space-between;
      gap: 16px;
      margin-bottom: 18px;
    }}
    .section-kicker {{
      order: 2;
      color: var(--accent);
      font-size: 12px;
      font-weight: 900;
      text-transform: uppercase;
    }}
    h2 {{
      margin: 0;
      font-size: 24px;
      line-height: 1.25;
    }}
    h3 {{
      margin: 8px 0 8px;
      font-size: 18px;
      line-height: 1.3;
    }}
    p {{
      margin: 0;
      color: var(--muted);
      font-size: 15px;
    }}
    .flow-row {{
      display: flex;
      align-items: stretch;
      gap: 12px;
    }}
    .card-grid, .comparison-grid, .lane-grid {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 14px;
    }}
    .item-card, .compare-card, .lane {{
      min-width: 0;
      border: 1px solid #cbd5e1;
      border-radius: 14px;
      background: #ffffff;
      padding: 17px;
      box-shadow: 0 8px 24px rgba(15, 23, 42, 0.05);
    }}
    .item-topline {{
      display: flex;
      gap: 8px;
      min-height: 28px;
      align-items: center;
    }}
    .item-number {{
      display: inline-grid;
      place-items: center;
      width: 26px;
      height: 26px;
      border-radius: 999px;
      background: var(--accent);
      color: #ffffff;
      font-size: 13px;
      font-weight: 900;
    }}
    .item-badge, .compare-label {{
      display: inline-flex;
      align-items: center;
      min-height: 24px;
      padding: 3px 9px;
      border-radius: 999px;
      background: var(--soft-secondary);
      color: var(--secondary);
      font-size: 12px;
      font-weight: 900;
    }}
    .item-meta {{
      margin-top: 10px;
      color: #64748b;
      font-size: 13px;
    }}
    .arrow {{
      display: grid;
      place-items: center;
      min-width: 24px;
      color: var(--accent);
      font-size: 22px;
      font-weight: 900;
    }}
    .compare-card ul, .notes ul {{
      margin: 12px 0 0;
      padding-left: 20px;
      color: var(--muted);
    }}
    .lane-steps {{
      display: grid;
      gap: 12px;
      margin-top: 14px;
    }}
    .timeline {{
      display: grid;
      gap: 14px;
    }}
    .timeline-item {{
      display: grid;
      grid-template-columns: 34px 1fr;
      gap: 14px;
      align-items: start;
      padding: 16px;
      border: 1px solid #cbd5e1;
      border-radius: 14px;
      background: #ffffff;
    }}
    .timeline-item span {{
      display: grid;
      place-items: center;
      width: 34px;
      height: 34px;
      border-radius: 999px;
      background: var(--accent);
      color: #ffffff;
      font-weight: 900;
    }}
    .notes {{
      margin-top: 30px;
      padding: 18px;
      border-radius: 14px;
      background: #f8fafc;
      border: 1px dashed #cbd5e1;
    }}
    @media (max-width: 900px) {{
      main {{ width: min(100vw - 24px, 720px); padding: 24px; }}
      h1 {{ font-size: 30px; }}
      .flow-row {{ display: grid; }}
      .arrow {{ transform: rotate(90deg); }}
      .section-heading {{ display: grid; }}
      .section-kicker {{ order: 0; }}
    }}
  </style>
</head>
<body>
  <main>
    <header>
      <div class="badge-row">
        <span class="mode-badge">{esc(mode)}</span>
        <span class="audience-badge">{esc(spec.get("audience"))}</span>
      </div>
      <h1>{esc(spec.get("title"))}</h1>
      <p class="subtitle">{esc(spec.get("subtitle"))}</p>
      <div class="message">{esc(spec.get("message"))}</div>
    </header>
    {sections}
    {notes_html}
  </main>
</body>
</html>
"""


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="visual-spec JSON file")
    parser.add_argument("--output", required=True, help="output HTML file")
    args = parser.parse_args()

    source = Path(args.input)
    output = Path(args.output)
    spec = json.loads(source.read_text(encoding="utf-8"))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(build_html(spec), encoding="utf-8")
    print(output)


if __name__ == "__main__":
    main()
