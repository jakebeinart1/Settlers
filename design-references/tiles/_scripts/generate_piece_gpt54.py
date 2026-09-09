#!/usr/bin/env python3
"""Generate a square building-piece icon with OpenRouter's newest OpenAI image
model, `openai/gpt-5.4-image-2` (canonical `openai/gpt-5.4-image-2-20260421`,
listed on OpenRouter 2026-04-21 - GPT-5.4 reasoning driving GPT Image 2).

Why a second script instead of editing generate_icon.py: gpt-5.4-image-2 is a
CHAT model (`text+image+file -> text+image`), not an /v1/images model, so the
request shape is completely different - reference images ride in as message
content parts and the result comes back on `message.images`, not `data[0]`.
generate_icon.py's `openai/gpt-image-2` /v1/images path still works and is left
alone so existing approved art stays reproducible.

Usage:
  python3 generate_piece_gpt54.py <ref1.png>[,<ref2.png>,...] "<prompt>" <out.png>

The prompt MUST ask for "a solid flat magenta #FF00FF background, nothing else"
- this script chroma-keys that out to real alpha afterward and verifies it,
exactly like generate_icon.py does.
"""
import base64
import json
import os
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_screen import strip_chromakey, verify_transparency

# Default model. Override per-run with OPENROUTER_IMAGE_MODEL - e.g.
# "google/gemini-3.1-flash-image" (Nano Banana 2), which emits ~1.3k image
# tokens against gpt-5.4-image-2's ~8.3k and so costs roughly $0.08 an image
# against $0.25, at the price of not reasoning about the brief first.
MODEL = os.environ.get("OPENROUTER_IMAGE_MODEL", "openai/gpt-5.4-image-2")


def data_url(path: Path) -> str:
    return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode()


def main():
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    ref_paths = [Path(p) for p in sys.argv[1].split(",") if p]
    prompt = sys.argv[2]
    out_path = Path(sys.argv[3])

    api_key = os.environ.get("OPENROUTER_API_KEY")
    if not api_key:
        print("OPENROUTER_API_KEY not set in this shell", file=sys.stderr)
        sys.exit(1)

    content = [{"type": "text", "text": prompt}]
    for p in ref_paths:
        content.append({"type": "image_url", "image_url": {"url": data_url(p)}})

    payload = {
        "model": MODEL,
        "modalities": ["image", "text"],
        "messages": [{"role": "user", "content": content}],
    }

    # OpenRouter reserves a request's MAXIMUM possible cost against the key's
    # remaining credit before it runs, and this model's ceiling is 128k
    # completion tokens - so a request that will really cost ~$0.26 is refused
    # with `402 Payment Required` while ~$0.57 is still sitting on the key.
    # Capping max_tokens caps the reservation. One image measures ~8.3k output
    # tokens, so the 12k default leaves real headroom; raise it if a generation
    # ever comes back truncated.
    max_tokens = os.environ.get("OPENROUTER_MAX_TOKENS")
    if max_tokens:
        payload["max_tokens"] = int(max_tokens)

    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=600) as resp:
        result = json.load(resp)

    msg = result["choices"][0]["message"]
    images = msg.get("images") or []
    if not images:
        print("no image returned. text was:", repr(msg.get("content"))[:2000], file=sys.stderr)
        sys.exit(2)

    url = images[0]["image_url"]["url"]
    b64 = url.split(",", 1)[1]
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_bytes(base64.b64decode(b64))

    cost = result.get("usage", {}).get("cost")
    print(f"saved: {out_path}")
    print(f"cost: ${cost}" if cost is not None else "cost: (not reported)")

    strip_chromakey(out_path)
    verify_transparency(out_path)


if __name__ == "__main__":
    main()
