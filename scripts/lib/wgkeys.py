#!/usr/bin/env python3
"""Generate a WireGuard Curve25519 keypair (base64), stdout as JSON."""
from __future__ import annotations

import base64
import json
import sys

from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from cryptography.hazmat.primitives import serialization


def gen_keypair() -> dict[str, str]:
    priv = X25519PrivateKey.generate()
    priv_bytes = priv.private_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PrivateFormat.Raw,
        encryption_algorithm=serialization.NoEncryption(),
    )
    pub_bytes = priv.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    return {
        "privateKey": base64.b64encode(priv_bytes).decode("ascii"),
        "publicKey": base64.b64encode(pub_bytes).decode("ascii"),
    }


def main() -> int:
    count = 1
    if len(sys.argv) > 1:
        count = int(sys.argv[1])
    if count == 1:
        print(json.dumps(gen_keypair()))
    else:
        print(json.dumps([gen_keypair() for _ in range(count)]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
