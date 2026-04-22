#!/usr/bin/env python3

import argparse
import base64
from pathlib import Path
import sys

from nacl.signing import SigningKey


def load_private_key(secret: str) -> SigningKey:
    raw = base64.b64decode(secret.strip())

    if len(raw) == 32:
        return SigningKey(raw)

    if len(raw) == 64:
        return SigningKey(raw[:32])

    raise ValueError("expected a base64-encoded 32-byte or 64-byte Ed25519 private key")


def main() -> int:
    parser = argparse.ArgumentParser(description="Sign a Sparkle update archive with Ed25519.")
    parser.add_argument("--archive", required=True, help="Path to the release archive")
    parser.add_argument("--private-key", required=True, help="Base64-encoded private Ed25519 key")
    parser.add_argument("--signature-out", required=True, help="Path to write the base64 signature")
    args = parser.parse_args()

    archive_path = Path(args.archive)
    archive_bytes = archive_path.read_bytes()

    signing_key = load_private_key(args.private_key)
    signature = signing_key.sign(archive_bytes).signature
    signature_base64 = base64.b64encode(signature).decode("ascii")

    Path(args.signature_out).write_text(signature_base64, encoding="utf-8")
    print(signature_base64)
    return 0


if __name__ == "__main__":
    sys.exit(main())
