#!/usr/bin/env python3

import argparse
import html
from pathlib import Path
import sys


def render_markdown(markdown_text: str) -> str:
    lines = markdown_text.splitlines()
    parts: list[str] = []
    in_list = False
    paragraph: list[str] = []

    def flush_paragraph() -> None:
        nonlocal paragraph
        if paragraph:
            parts.append(f"<p>{html.escape(' '.join(paragraph).strip())}</p>")
            paragraph = []

    def close_list() -> None:
        nonlocal in_list
        if in_list:
            parts.append("</ul>")
            in_list = False

    for raw_line in lines:
        line = raw_line.rstrip()

        if not line.strip():
            flush_paragraph()
            close_list()
            continue

        if line.startswith("### "):
            flush_paragraph()
            close_list()
            parts.append(f"<h3>{html.escape(line[4:].strip())}</h3>")
            continue

        if line.startswith("## "):
            flush_paragraph()
            close_list()
            parts.append(f"<h2>{html.escape(line[3:].strip())}</h2>")
            continue

        if line.startswith("# "):
            flush_paragraph()
            close_list()
            parts.append(f"<h1>{html.escape(line[2:].strip())}</h1>")
            continue

        if line.startswith("- "):
            flush_paragraph()
            if not in_list:
                parts.append("<ul>")
                in_list = True
            parts.append(f"<li>{html.escape(line[2:].strip())}</li>")
            continue

        close_list()
        paragraph.append(line.strip())

    flush_paragraph()
    close_list()

    return "\n".join(parts)


def main() -> int:
    parser = argparse.ArgumentParser(description="Render a GitHub Release body into a simple HTML page.")
    parser.add_argument("--title", required=True, help="HTML page title")
    parser.add_argument("--input", required=True, help="Markdown input path")
    parser.add_argument("--output", required=True, help="HTML output path")
    args = parser.parse_args()

    markdown_text = Path(args.input).read_text(encoding="utf-8")
    content = render_markdown(markdown_text)

    document = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(args.title)}</title>
  <style>
    body {{
      margin: 0;
      font: 16px/1.6 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
      background: #161816;
      color: #f3f5f2;
    }}
    main {{
      max-width: 760px;
      margin: 0 auto;
      padding: 40px 24px 64px;
    }}
    h1, h2, h3 {{
      line-height: 1.25;
      margin: 0 0 16px;
    }}
    h1 {{
      font-size: 34px;
    }}
    h2 {{
      font-size: 24px;
      margin-top: 28px;
    }}
    h3 {{
      font-size: 19px;
      margin-top: 22px;
    }}
    p, ul {{
      margin: 0 0 16px;
      color: #d3d7d1;
    }}
    a {{
      color: #3d98ff;
    }}
  </style>
</head>
<body>
  <main>
    {content}
  </main>
</body>
</html>
"""

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(document, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
