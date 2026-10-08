# Development-card emblems

Full-size sources (1024px, alpha) for `Settlers/Assets.xcassets/devcard-*.imageset`
(trimmed to the art, squared, 360px). Wired in through `DevCardEmblem`, the one view
every dev-card icon goes through (28pt inventory, 44pt compact face, ~104pt full face).

Made 2026-10-08 with `openai/gpt-5.4-image-2` (~$0.23 each) via the restored
`generate_piece_gpt54.py` (`git show 4ed54cc^:design-references/tiles/_scripts/generate_piece_gpt54.py`),
with a contact sheet of five shipped pieces (Britannia, Norse, Aztec, Japan, Egypt cities)
as the only reference. Shared style clause:

> Render it in EXACTLY the rugged style of the attached game pieces: flat straight-on front
> view, very thick slightly uneven hand-inked black outline, flat colour fill with rough
> crackled stone/plaster brush texture and darker hand-painted shading in the cracks, no
> glossy highlights, no 3D perspective, no gradients [...] Must stay readable when shrunk to
> 28 pixels [...] Solid flat magenta #FF00FF background, nothing else.

Per card: knight = plumed great-helm + kite shield (steel blue, gold cross); road = cobbled
road + signpost (terracotta, brown); plenty = harvest basket of wheat and apples; monopoly =
open crimson chest of gold coins; vp = ivory crown in a green laurel wreath.

After the chroma key, 1-4k magenta fringe pixels per image remained along the outline;
they were repainted outline-ink (`r,b > 120 and g < 0.6*min(r,b)`).

Next round: draft with a cheap model first (`google/gemini-3.1-flash-image`) and only
escalate on a quality miss. Known nits Jake accepted for now: the road's orange reads close
to the Brick resource, and the crown is small at 28pt inside its wreath.
