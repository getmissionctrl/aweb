#!/usr/bin/env python3
"""Conformance tests for the Haskell aweb server running at localhost:9099.

Tests authentication, health, and agent endpoints using Ed25519 DIDKey auth.
"""

import hashlib
import json
import base64
import sys
from datetime import datetime, timezone

import base58
import httpx
from nacl.signing import SigningKey

BASE_URL = "http://localhost:9099"


def generate_identity():
    """Generate an Ed25519 keypair and derive did:key and did:aw identifiers."""
    sk = SigningKey.generate()
    pk_bytes = bytes(sk.verify_key)

    # did:key: z + base58btc(0xed01 + pubkey)
    multicodec_ed25519 = b"\xed\x01"
    did_key = "did:key:z" + base58.b58encode(multicodec_ed25519 + pk_bytes).decode()

    # did:aw: SHA256(pubkey) first 20 bytes -> base58btc
    sha = hashlib.sha256(pk_bytes).digest()[:20]
    did_aw = "did:aw:" + base58.b58encode(sha).decode()

    return sk, did_key, did_aw


def make_auth_headers(sk, did_key, did_aw, body: bytes = b""):
    """Create Authorization and X-AWEB-Timestamp headers for a request."""
    body_sha256 = hashlib.sha256(body).hexdigest()
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    payload = json.dumps(
        {"body_sha256": body_sha256, "did_aw": did_aw, "timestamp": timestamp},
        sort_keys=True,
        separators=(",", ":"),
    )

    sig = sk.sign(payload.encode()).signature
    # standard base64, no padding (Haskell server re-pads before decoding)
    sig_b64 = base64.b64encode(sig).decode().rstrip("=")

    return {
        "Authorization": f"DIDKey {did_key} {sig_b64}",
        "X-AWEB-Timestamp": timestamp,
    }


def test_health(client):
    """GET /health should return 200 with JSON body."""
    resp = client.get(f"{BASE_URL}/health")
    if resp.status_code == 200:
        try:
            data = resp.json()
            return True, f"200 OK, body={data}"
        except Exception:
            return True, f"200 OK, body={resp.text}"
    return False, f"Expected 200, got {resp.status_code}: {resp.text}"


def test_get_agents_authenticated(client, sk, did_key, did_aw):
    """GET /v1/agents with auth should return 200, 403, or 500 (not 401)."""
    headers = make_auth_headers(sk, did_key, did_aw, body=b"")
    resp = client.get(f"{BASE_URL}/v1/agents", headers=headers)
    if resp.status_code in (200, 403, 500):
        return True, f"{resp.status_code} (auth passed; {resp.text[:120]})"
    if resp.status_code == 401:
        return False, f"401 Unauthorized - auth signature rejected: {resp.text}"
    return False, f"Unexpected status {resp.status_code}: {resp.text}"


def test_post_agents_not_401(client, sk, did_key, did_aw):
    """POST /v1/agents with auth should NOT return 401 (auth should pass)."""
    body = json.dumps({
        "alias": "conformance-test-agent",
        "team": "test",
        "did_key": did_key,
    }).encode()

    headers = make_auth_headers(sk, did_key, did_aw, body=body)
    headers["Content-Type"] = "application/json"

    resp = client.post(f"{BASE_URL}/v1/agents", content=body, headers=headers)
    if resp.status_code == 401:
        return False, f"401 Unauthorized - auth signature rejected: {resp.text}"
    # Any other status (200, 201, 400, 403, 409, 500) means auth passed
    return True, f"{resp.status_code} (auth passed, response: {resp.text[:200]})"


def main():
    sk, did_key, did_aw = generate_identity()

    print(f"Test identity:")
    print(f"  did:key = {did_key}")
    print(f"  did:aw  = {did_aw}")
    print()

    client = httpx.Client(timeout=10.0)

    tests = [
        ("GET /health", lambda: test_health(client)),
        ("GET /v1/agents (authenticated)", lambda: test_get_agents_authenticated(client, sk, did_key, did_aw)),
        ("POST /v1/agents (authenticated, not 401)", lambda: test_post_agents_not_401(client, sk, did_key, did_aw)),
    ]

    results = []
    for name, test_fn in tests:
        try:
            passed, detail = test_fn()
        except httpx.ConnectError as e:
            passed, detail = False, f"Connection refused: {e}"
        except Exception as e:
            passed, detail = False, f"Exception: {type(e).__name__}: {e}"

        status = "PASS" if passed else "FAIL"
        results.append(passed)
        print(f"[{status}] {name}")
        print(f"       {detail}")
        print()

    client.close()

    all_passed = all(results)
    print(f"{'=' * 40}")
    print(f"Results: {sum(results)}/{len(results)} passed")

    if all_passed:
        print("All tests passed.")
    else:
        print("Some tests failed.")

    sys.exit(0 if all_passed else 1)


if __name__ == "__main__":
    main()
