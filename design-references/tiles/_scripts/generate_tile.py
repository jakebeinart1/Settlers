#!/usr/bin/env python3
"""Generate one board-tile image via OpenRouter and save it as the next
version number in tiles/<type>/. Prints the actual cost from the API
response so TILES-PROGRESS.md can be kept accurate.

Usage:
  OPENROUTER_API_KEY=... python3 generate_tile.py <tile_type> "<prompt>" [ref_image1.png,ref_image2.png,...]

Optional trailing arg: comma-separated reference image paths, used as
image-to-image style/color references (same input_references mechanism as
generate_screen.py) - pass the real target screenshot to match its exact
palette/texture instead of describing it in words.
"""
import base64
import json
import os
import sys
import urllib.request
from pathlib import Path

TILES_DIR = Path(__file__).resolve().parent.parent

def main():
    if len(sys.argv) not in (3, 4):
        print("usage: generate_tile.py <tile_type> \"<prompt>\" [ref1.png,ref2.png,...]", file=sys.stderr)
        sys.exit(1)

    tile_type, prompt = sys.argv[1], sys.argv[2]
    ref_paths = [Path(p) for p in sys.argv[3].split(",")] if len(sys.argv) == 4 else []
    out_dir = TILES_DIR / tile_type
    out_dir.mkdir(parents=True, exist_ok=True)

    api_key = os.environ.get("OPENROUTER_API_KEY")
    if not api_key:
        print("OPENROUTER_API_KEY not set in this shell", file=sys.stderr)
        sys.exit(1)

    existing = sorted(out_dir.glob("v*.png"))
    next_n = len(existing) + 1
    out_path = out_dir / f"v{next_n}.png"

    payload = {
        "model": "openai/gpt-image-2",
        "prompt": prompt,
        "size": "1024x1024",
        "quality": "medium",
    }
    if ref_paths:
        ref_data_urls = []
        for ref_path in ref_paths:
            ref_b64 = base64.b64encode(ref_path.read_bytes()).decode()
            ref_data_urls.append(f"data:image/png;base64,{ref_b64}")
        payload["input_references"] = [
            {"type": "image_url", "image_url": {"url": url}} for url in ref_data_urls
        ]
    else:
        payload["background"] = "opaque"

    body = json.dumps(payload).encode()

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
