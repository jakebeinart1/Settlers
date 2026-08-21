#!/usr/bin/env python3
"""Generate one board-tile image via OpenRouter and save it as the next
version number in tiles/<type>/. Prints the actual cost from the API
response so TILES-PROGRESS.md can be kept accurate.

Usage:
  OPENROUTER_API_KEY=... python3 generate_tile.py <tile_type> "<prompt>"
"""
import base64
import json
import os
import sys
import urllib.request
from pathlib import Path

TILES_DIR = Path(__file__).resolve().parent.parent

def main():
    if len(sys.argv) != 3:
        print("usage: generate_tile.py <tile_type> \"<prompt>\"", file=sys.stderr)
        sys.exit(1)

    tile_type, prompt = sys.argv[1], sys.argv[2]
    out_dir = TILES_DIR / tile_type
    out_dir.mkdir(parents=True, exist_ok=True)

    api_key = os.environ.get("OPENROUTER_API_KEY")
    if not api_key:
        print("OPENROUTER_API_KEY not set in this shell", file=sys.stderr)
        sys.exit(1)

    existing = sorted(out_dir.glob("v*.png"))
    next_n = len(existing) + 1
    out_path = out_dir / f"v{next_n}.png"

    body = json.dumps({
        "model": "openai/gpt-image-2",
        "prompt": prompt,
        "size": "1024x1024",
        "quality": "medium",
        "background": "opaque",
    }).encode()

    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/images",
        data=body,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    with urllib.request.urlopen(req, timeout=120) as resp:
        result = json.load(resp)

    img_b64 = result["data"][0]["b64_json"]
    out_path.write_bytes(base64.b64decode(img_b64))

    cost = result.get("usage", {}).get("cost")
    print(f"saved: {out_path}")
    print(f"cost: ${cost}" if cost is not None else "cost: (not reported)")

if __name__ == "__main__":
    main()
