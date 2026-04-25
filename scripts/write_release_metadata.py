#!/usr/bin/env python3

import argparse
import json
from pathlib import Path
import sys
from datetime import datetime, timezone


def iso_to_rfc2822(value: str) -> str:
    dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return dt.astimezone(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S %z")


def main() -> int:
    parser = argparse.ArgumentParser(description="Write a release metadata entry.")
    parser.add_argument("--tag", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--published-at", required=True)
    parser.add_argument("--archive-url", required=True)
    parser.add_argument("--release-page-url", required=True)
    parser.add_argument("--notes-url", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    entry = {
        "tag": args.tag,
        "version": args.version,
        "buildNumber": args.build_number,
        "publishedAt": args.published_at,
        "pubDate": iso_to_rfc2822(args.published_at),
        "archiveURL": args.archive_url,
        "releasePageURL": args.release_page_url,
        "notesURL": args.notes_url,
    }

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(entry, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
