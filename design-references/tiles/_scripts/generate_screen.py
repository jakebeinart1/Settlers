#!/usr/bin/env python3
"""Generate a full-screen concept image via OpenRouter, using a real
screenshot as an image-to-image structural reference. Saves versioned
output into design-references/full-screen/.

Usage:
  python3 generate_screen.py <reference_image_path> "<prompt>" [--chromakey]

--chromakey: the API rejects background=transparent when input_references
are used (confirmed against the real endpoint - "background: not
supported. Accepted: auto, opaque" for this model in image-to-image mode),
so this asks the PROMPT to render on a solid magenta (#FF00FF) background
instead, then strips that exact color to real alpha transparency after the
fact, then verifies the result actually has transparent pixels - prints a
clear pass/fail rather than silently trusting it worked. The prompt you
pass MUST itself ask for "a solid flat magenta #FF00FF background, nothing
else" - this flag only does the post-processing + verification, not the
request wording.
"""
import base64
import json
import os
import sys
import urllib.request
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent.parent.parent / "full-screen"
MAGENTA = (255, 0, 255)
CHROMA_TOLERANCE = 60  # euclidean-ish per-channel distance to still count as "background"

def strip_chromakey(path: Path) -> None:
    from PIL import Image
    im = Image.open(path).convert("RGBA")
    pixels = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = pixels[x, y]
            if abs(r - MAGENTA[0]) < CHROMA_TOLERANCE and abs(g - MAGENTA[1]) < CHROMA_TOLERANCE and abs(b - MAGENTA[2]) < CHROMA_TOLERANCE:
                pixels[x, y] = (r, g, b, 0)
    im.save(path)

def verify_transparency(path: Path) -> None:
    try:
        from PIL import Image
    except ImportError:
        print("verify: PIL not available, could not check transparency", file=sys.stderr)
        return
    im = Image.open(path)
    if im.mode != "RGBA":
        print(f"verify: FAILED - image mode is {im.mode}, no alpha channel at all")
        return
    alpha = im.getchannel("A")
    min_a, max_a = alpha.getextrema()
    transparent_pixels = sum(1 for v in alpha.getdata() if v < 250)
    total = im.width * im.height
    if min_a == 255:
        print(f"verify: FAILED - has an alpha channel but every pixel is fully opaque (min={min_a}, max={max_a})")
    else:
        pct = 100 * transparent_pixels / total
        print(f"verify: OK - {pct:.1f}% of pixels have real transparency (alpha min={min_a}, max={max_a})")

def main():
    chromakey = "--chromakey" in sys.argv
    args = [a for a in sys.argv[1:] if a != "--chromakey"]
    if len(args) != 2:
        print("usage: generate_screen.py <reference_image_path>[,<reference_image_path2>,...] \"<prompt>\" [--chromakey]", file=sys.stderr)
        sys.exit(1)

    ref_paths = [Path(p) for p in args[0].split(",")]
    prompt = args[1]
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    api_key = os.environ.get("OPENROUTER_API_KEY")
    if not api_key:
        print("OPENROUTER_API_KEY not set in this shell", file=sys.stderr)
        sys.exit(1)

    existing = sorted(OUT_DIR.glob("v*.png"))
    next_n = len(existing) + 1
    out_path = OUT_DIR / f"v{next_n}.png"

    ref_data_urls = []
    for ref_path in ref_paths:
        ref_b64 = base64.b64encode(ref_path.read_bytes()).decode()
        ref_data_urls.append(f"data:image/png;base64,{ref_b64}")

    payload = {
        "model": "openai/gpt-image-2",
        "prompt": prompt,
        "size": "1024x1536",
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
    out_path.write_bytes(base64.b64decode(img_b64))

    cost = result.get("usage", {}).get("cost")
    print(f"saved: {out_path}")
    print(f"cost: ${cost}" if cost is not None else "cost: (not reported)")
    if chromakey:
        strip_chromakey(out_path)
        verify_transparency(out_path)

if __name__ == "__main__":
    main()
