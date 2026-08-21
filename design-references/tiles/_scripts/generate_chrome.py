#!/usr/bin/env python3
"""Generate a wide UI-chrome frame (button backgrounds, banner/bank chips)
via OpenRouter, using one or more reference images for style guidance, at a
specific target aspect ratio that a single generation preset can't hit
directly.

The API's landscape preset is 1536x1024 (1.5:1) - narrower than the wide
short banners this app actually needs (~2.4:1 for action buttons, ~5.6:1 for
the bank/dev-card chip). Rather than stretching or content-cropping after
the fact, the PROMPT is responsible for confining the actual ornamented
design to a horizontal band vertically centered in the 1536x1024 canvas,
sized to the requested aspect ratio, with plain/transparent magenta above
and below it - this script then crops exactly to that band, so the crop
only ever removes intentionally-empty margin, never content.

Usage:
  python3 generate_chrome.py <ref1.png>[,<ref2.png>,...] "<prompt>" <out_path.png> <target_aspect>

<target_aspect> is width/height, e.g. 2.4 or 5.6. The prompt MUST itself
describe a magenta #FF00FF background and instruct the design to be
vertically centered within a band matching this aspect ratio out of the
1536x1024 canvas.
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
    if len(sys.argv) != 5:
        print("usage: generate_chrome.py <ref1.png>[,<ref2.png>,...] \"<prompt>\" <out_path.png> <target_aspect>", file=sys.stderr)
        sys.exit(1)

    ref_paths = [Path(p) for p in sys.argv[1].split(",")]
    prompt = sys.argv[2]
    out_path = Path(sys.argv[3])
    target_aspect = float(sys.argv[4])

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
        "size": "1536x1024",
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

    from PIL import Image
    im = Image.open(out_path)
    w, h = im.size
    target_h = round(w / target_aspect)
    if target_h > h:
        # Target is taller (relatively) than the source canvas - crop width instead.
        target_w = round(h * target_aspect)
        left = (w - target_w) // 2
        box = (left, 0, left + target_w, h)
    else:
        top = (h - target_h) // 2
        box = (0, top, w, top + target_h)
    cropped = im.crop(box)
    cropped.save(out_path)
    print(f"cropped to {cropped.size[0]}x{cropped.size[1]} (target aspect {target_aspect})")


if __name__ == "__main__":
    main()
