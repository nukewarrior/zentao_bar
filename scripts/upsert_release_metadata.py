#!/usr/bin/env python3

import argparse
import json
from pathlib import Path
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description="Insert or replace a release metadata entry in releases.json")
    parser.add_argument("--existing", required=True, help="Existing releases.json path")
    parser.add_argument("--entry", required=True, help="New entry json path")
    parser.add_argument("--output", required=True, help="Output releases.json path")
    args = parser.parse_args()

    existing_path = Path(args.existing)
    if existing_path.exists():
        existing = json.loads(existing_path.read_text(encoding="utf-8"))
    else:
        existing = []

    entry = json.loads(Path(args.entry).read_text(encoding="utf-8"))
    filtered = [item for item in existing if item.get("tag") != entry.get("tag")]
    filtered.append(entry)
    filtered.sort(key=lambda item: item.get("publishedAt", ""), reverse=True)

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(filtered, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
