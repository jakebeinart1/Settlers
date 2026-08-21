#!/usr/bin/env python3
"""Generate a wide UI-chrome frame (button backgrounds, banner/bank chips)
via OpenRouter, using one or more reference images for style guidance, at a
specific target aspect ratio that a single generation preset can't hit
directly.

The API's landscape preset is 1536x1024 (1.5:1) - narrower than the wide
short banners this app actually needs (~2.4:1 for action buttons, ~5.6:1 for
the bank/dev-card chip). The PROMPT asks the model to confine the actual
ornamented design to a horizontal band vertically centered in the 1536x1024
canvas, matching the target aspect ratio, with plain/transparent magenta
above and below - but the model doesn't always hit that exactly or
consistently between separate calls (e.g. one button's plaque ending up
noticeably shorter than another's, despite both requesting the same
aspect). Every consumer of these assets uses `.scaledToFill()` + clip, which
scales the WHOLE canvas including any such margin to cover its container -
so an inconsistent margin becomes an inconsistent visible gap around the
plaque once composited, not just wasted canvas.

To make this robust against the model not hitting the requested band
exactly, this script doesn't trust the prompt alone: after chromakey, it
tight-crops to the actual alpha content bounding box first (so the saved
asset's canvas always has zero dead margin, regardless of what the model
generated around it), then - only if that bbox doesn't already match
`target_aspect` - crops *further inward* to hit it exactly. It only ever
crops, never pads, so the final asset is guaranteed 100% content, edge to
edge, no matter how far off the raw generation was.

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
    im = Image.open(out_path).convert("RGBA")

    # Tight-crop to the actual content bbox and STOP - never trust the
    # prompt to have hit the requested target_aspect exactly, and never
    # crop further inward to force it once cropped tight, since the
    # design's corner ornament lives right at that bbox's edges and a
    # second aspect-driven crop would eat into it (the actual bug this is
    # fixing: three separately-generated plaques each left a different
    # amount of dead margin, so cropping each ~exactly to target_aspect
    # from the ORIGINAL 1536x1024 canvas left a different amount of that
    # dead margin baked into each final asset - a small but inconsistent
    # gap around the plaque once `.scaledToFill()` scaled that dead margin
    # to cover the button along with everything else). The achieved
    # aspect after this tight crop is printed but not enforced - a few
    # percent off `target_aspect` costs a little extra even/symmetric
    # `.scaledToFill()` crop at render time, which is harmless; dead
    # margin baked into the asset is not.
    bbox = im.getchannel("A").getbbox()
    if bbox is None:
        raise SystemExit(f"{out_path}: fully transparent after chromakey, nothing to crop")
    safety = 3
    bbox = (bbox[0] + safety, bbox[1] + safety, bbox[2] - safety, bbox[3] - safety)
    cropped = im.crop(bbox)
    cropped.save(out_path)
    achieved_aspect = cropped.size[0] / cropped.size[1]
    print(f"tight-cropped to content bbox: {cropped.size[0]}x{cropped.size[1]} (aspect {achieved_aspect:.2f}, requested {target_aspect})")


if __name__ == "__main__":
    main()
