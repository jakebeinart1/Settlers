# Empires victory emblem

The human victory headline replaces the generic party-popper emoji with an original painted gold hex, rising sun and ivory triumph banner. The hex and landscape refer to Empires territory; the banner signifies victory without selecting a civilization or game mode.

The [built-in generation prompts](victory-emblem/generation-prompt-full.md) retain the initial candidate and targeted refinement. The tall finial was removed and internal shapes simplified after review. The selected1254×1254RGBA PNG is copied unchanged into `victory-emblem.imageset`; native display is76×76points in the existing icon slot, with original colors and decorative accessibility hiding. Existing YOU WIN!, panel, scores, result actions and bot/multiple-human branches are unchanged.

Three existing native result flows pass: return to menu, same-table restart, and maximum-text actions. Root and independent review approve the [normal screen](victory-emblem/normal.png), [maximum-text headline](victory-emblem/maximum-title.png) and [scrolled actions](victory-emblem/maximum-actions.png). The forced-win fixture has zero-VP rows/no replay; this proves rendering and controls, not a naturally played win. Existing largest-text standings still wrap, and are outside this emblem-only change.

[Generation provenance](victory-emblem/generation-review.json), [raw focused summary](victory-emblem/focused-summary.json) and [independent art review](victory-emblem/final-victory-art-review.json) retain actual bytes and review scope. Build28 full gate and TestFlight delivery remain pending. Integration will be recorded in the feature PR.
