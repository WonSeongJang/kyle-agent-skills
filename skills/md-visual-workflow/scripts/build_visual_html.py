#!/usr/bin/env python3
"""Build a clean Mermaid-enabled HTML preview from a Markdown file.

This intentionally supports a small Markdown subset so it stays dependency-free:
headings, paragraphs, bullets, fenced code blocks, and Mermaid blocks.
"""

from __future__ import annotations

import argparse
import html
from pathlib import Path


def render_markdown(markdown: str) -> str:
    lines = markdown.splitlines()
    out: list[str] = []
    paragraph: list[str] = []
    in_code = False
    code_lang = ""
    code_lines: list[str] = []
    in_list = False

    def flush_paragraph() -> None:
        nonlocal paragraph
        if paragraph:
            out.append(f"<p>{html.escape(' '.join(paragraph))}</p>")
            paragraph = []

    def close_list() -> None:
        nonlocal in_list
        if in_list:
            out.append("</ul>")
            in_list = False

    for raw in lines:
        line = raw.rstrip()

        if line.startswith("```"):
            if not in_code:
                flush_paragraph()
                close_list()
                in_code = True
                code_lang = line[3:].strip().lower()
                code_lines = []
            else:
                code = "\n".join(code_lines)
                if code_lang == "mermaid":
                    out.append(f'<div class="mermaid">{html.escape(code)}</div>')
                else:
                    out.append(
                        f'<pre><code class="language-{html.escape(code_lang)}">'
                        f"{html.escape(code)}</code></pre>"
                    )
                in_code = False
                code_lang = ""
                code_lines = []
            continue

        if in_code:
            code_lines.append(raw)
            continue

        if not line.strip():
            flush_paragraph()
            close_list()
            continue

        if line.startswith("#"):
            flush_paragraph()
            close_list()
            level = min(len(line) - len(line.lstrip("#")), 4)
            text = line[level:].strip()
            out.append(f"<h{level}>{html.escape(text)}</h{level}>")
            continue

        stripped = line.lstrip()
        if stripped.startswith("- "):
            flush_paragraph()
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{html.escape(stripped[2:].strip())}</li>")
            continue

        close_list()
        paragraph.append(line.strip())

    flush_paragraph()
    close_list()
    return "\n".join(out)


def build_html(title: str, body: str, mode: str) -> str:
    badge = "IDEA MODE" if mode == "idea" else "REPO MODE"
    return f"""<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{html.escape(title)}</title>
  <style>
    :root {{
      --bg: #f8fafc;
      --panel: #ffffff;
      --text: #0f172a;
      --muted: #475569;
      --line: #dbeafe;
      --accent: #2563eb;
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", "Noto Sans KR", sans-serif;
      line-height: 1.65;
    }}
    main {{
      width: min(1120px, calc(100vw - 48px));
      margin: 48px auto;
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 18px;
      padding: 44px;
      box-shadow: 0 18px 50px rgba(15, 23, 42, 0.08);
    }}
    .badge {{
      display: inline-flex;
      align-items: center;
      height: 30px;
      padding: 0 12px;
      border-radius: 999px;
      background: #dbeafe;
      color: #1d4ed8;
      font-weight: 800;
      font-size: 13px;
      letter-spacing: .04em;
    }}
    h1 {{ font-size: 34px; line-height: 1.2; margin: 18px 0 24px; }}
    h2 {{ font-size: 25px; margin: 40px 0 14px; border-top: 1px solid #e2e8f0; padding-top: 28px; }}
    h3 {{ font-size: 20px; margin: 28px 0 10px; }}
    h4 {{ font-size: 17px; margin: 22px 0 8px; color: var(--muted); }}
    p, li {{ font-size: 16px; }}
    p {{ margin: 10px 0; }}
    ul {{ padding-left: 22px; }}
    pre {{
      overflow: auto;
      background: #0f172a;
      color: #e2e8f0;
      border-radius: 12px;
      padding: 18px;
    }}
    .mermaid {{
      margin: 24px 0;
      padding: 20px;
      border: 1px solid #bfdbfe;
      border-radius: 14px;
      background: #f8fbff;
    }}
  </style>
</head>
<body>
  <main>
    <div class="badge">{badge}</div>
    <h1>{html.escape(title)}</h1>
    {body}
  </main>
  <script type="module">
    import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs';
    mermaid.initialize({{ startOnLoad: true, theme: 'base', securityLevel: 'loose' }});
  </script>
</body>
</html>
"""


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="Source Markdown file")
    parser.add_argument("--output", required=True, help="Output HTML file")
    parser.add_argument("--title", required=True, help="HTML title")
    parser.add_argument("--mode", choices=["idea", "repo"], default="idea")
    args = parser.parse_args()

    source = Path(args.input)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    body = render_markdown(source.read_text(encoding="utf-8"))
    output.write_text(build_html(args.title, body, args.mode), encoding="utf-8")
    print(output)


if __name__ == "__main__":
    main()
