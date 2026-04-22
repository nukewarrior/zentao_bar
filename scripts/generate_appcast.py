#!/usr/bin/env python3

import argparse
import json
from pathlib import Path
import sys
from xml.sax.saxutils import escape


def enclosure(item: dict[str, str]) -> str:
    return (
        f'<enclosure url="{escape(item["archiveURL"])}" '
        f'length="{escape(str(item["archiveLength"]))}" '
        'type="application/octet-stream" '
        f'sparkle:version="{escape(item["buildNumber"])}" '
        f'sparkle:shortVersionString="{escape(item["version"])}" '
        f'sparkle:edSignature="{escape(item["edSignature"])}" '
        f'sparkle:minimumSystemVersion="{escape(item["minimumSystemVersion"])}" />'
    )


def render_item(item: dict[str, str]) -> str:
    notes_url = escape(item["notesURL"])
    title = escape(f"Version {item['version']}")
    pub_date = escape(item["pubDate"])

    return f"""    <item>
      <title>{title}</title>
      <pubDate>{pub_date}</pubDate>
      <sparkle:releaseNotesLink>{notes_url}</sparkle:releaseNotesLink>
      {enclosure(item)}
    </item>"""


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a Sparkle appcast from release metadata")
    parser.add_argument("--input", required=True, help="releases.json path")
    parser.add_argument("--output", required=True, help="appcast.xml path")
    parser.add_argument("--feed-title", required=True, help="RSS channel title")
    parser.add_argument("--site-url", required=True, help="RSS channel link")
    parser.add_argument("--description", required=True, help="RSS channel description")
    args = parser.parse_args()

    releases = json.loads(Path(args.input).read_text(encoding="utf-8"))
    items = "\n".join(render_item(item) for item in releases)

    xml = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>{escape(args.feed_title)}</title>
    <link>{escape(args.site_url)}</link>
    <description>{escape(args.description)}</description>
{items}
  </channel>
</rss>
"""

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(xml, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
