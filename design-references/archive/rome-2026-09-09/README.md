# Rome city, 2026-09-09

The curated record of the regeneration described in `STATUS.md` under
"Sep 9 Rome city - regenerated on the Columbia rule".

- `sheets/` — the contact sheets the decisions were actually made from. Every one renders
  the candidates at 80/150/320px against the pieces they had to sit beside, because **80px
  is the only size that matters** and several variants that won at 320 lost at 80.
  `roster.png` is the one that diagnosed the problem: all 16 pieces laid out
  settlement-above-city, which is where "every other city is its own settlement grown"
  became visible.
- `variants/` — the nine generations, as returned by the model: still on their magenta
  chroma-key background, before retint/crop/fringe-cleanup. Kept raw on purpose, so a later
  reader can re-derive the finishing rather than inherit it.

`K3-straight-wider` is the one that shipped, after a retint to #E16256, fringe inpainting,
an alpha-bbox crop, and a `thicken_piece_edges.py --outer 7 --inner 0 --smooth` pass.

The full working directories for this session (`rome-gpt54/`, `rome-nb/`, `rome-roomy/`,
`rome-final-smooth/`, `rome-city-final/`, `rome-city-rebuild/`, `rome-city-regen/`,
`rome-city-hybrid/`, `rome-city-columbia/`) hold every intermediate, including the parameter
sweeps — 173MB, deliberately left untracked against a `.git` already at 472MB. They are on
Jake's machine if a specific trial is ever wanted back.
