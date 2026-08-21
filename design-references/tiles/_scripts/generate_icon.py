#!/usr/bin/env python3
"""Generate a square building-piece icon via OpenRouter, using one or more
reference images (shape/style/material/texture references) for image-to-image
guidance. Unlike generate_screen.py (which always requests a portrait
1024x1536 canvas meant for full-screen concept art), this requests a square
1024x1024 canvas - the right proportions for the square pieces living in
design-references/approved/pieces/.

Usage:
  python3 generate_icon.py <ref1.png>[,<ref2.png>,...] "<prompt>" <out_path.png>

The prompt MUST itself ask for "a solid flat magenta #FF00FF background,
nothing else" - this script always chroma-keys that background out to real
alpha transparency afterward, then verifies the result actually has
transparent pixels.
"""
import base64
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import urllib.request
from generate_screen import strip_chromakey, verify_transparency


def main():
    if len(sys.argv) != 4:
        print("usage: generate_icon.py <ref1.png>[,<ref2.png>,...] \"<prompt>\" <out_path.png>", file=sys.stderr)
        sys.exit(1)

    ref_paths = [Path(p) for p in sys.argv[1].split(",")]
    prompt = sys.argv[2]
    out_path = Path(sys.argv[3])

    api_key = os.environ.get("OPENROUTER_API_KEY")
    if not api_key:
        print("OPENROUTER_API_KEY not set in this shell", file=sys.stderr)
        sys.exit(1)

    ref_data_urls = []
    for ref_path in ref_paths:
        ref_b64 = base64.b64encode(ref_path.read_bytes()).decode()
        ref_data_urls.append(f"data:image/png;base64,{ref_b64}")

    payload = {
        "model": "openai/gpt-image-2",
        "prompt": prompt,
        "size": "1024x1024",
        "quality": "medium",
        "input_references": [
            {"type": "image_url", "image_url": {"url": url}} for url in ref_data_urls
        ],
    }
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

    with urllib.request.urlopen(req, timeout=180) as resp:
        result = json.load(resp)

    img_b64 = result["data"][0]["b64_json"]
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_bytes(base64.b64decode(img_b64))

    cost = result.get("usage", {}).get("cost")
    print(f"saved: {out_path}")
    print(f"cost: ${cost}" if cost is not None else "cost: (not reported)")

    strip_chromakey(out_path)
    verify_transparency(out_path)


if __name__ == "__main__":
    main()
