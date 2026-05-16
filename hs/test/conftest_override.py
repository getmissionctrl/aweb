"""
Python conformance test adapter for aweb-hs.

Usage:
  1. Start the Haskell server: nix build .#aweb-hs && ./result/bin/aweb-hs --port 8080
  2. Run Python tests against it:
     cd server && AWEB_TEST_URL=http://localhost:8080 uv run pytest tests/test_*_http.py

This conftest overrides the base_url fixture to point at the Haskell server.
"""
import os
import pytest


@pytest.fixture
def base_url():
    """Override base URL to target the Haskell server."""
    return os.environ.get("AWEB_TEST_URL", "http://localhost:8080")
