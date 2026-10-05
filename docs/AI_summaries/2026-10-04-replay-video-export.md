# Replay video export implementation and verification

This note covers the local Share replay video product in the parent integration
checkout, based on shipped Build 16 (`38f7885`). Darwin owns replay export;
main owns integration and serial app verification. Separate Expert experiments
are another agent's work and were neither edited nor evaluated here.

## Product and privacy

The primary export is a silent 720 by 1280 H.264 MP4, created on the device with
the existing BoardView renderer. The sheet provides progress, cancel, retry,
AVKit preview and native sharing. There is no upload, public URL or new backend.
Raw JSONL stays available as a secondary diagnostic recording, behind a warning
about names, timestamps, hidden hands and deck order.

Video names default to Player 1 through Player 4; recorded names require explicit
opt-in. The renderer receives a public projection, not the replay screen or its
private score breakdown. Resources, development cards, army hands/decks, RNG and
pending private state are stripped. Captions omit stolen-resource identity and
scores use publicVictoryPoints. The source archive is not redacted or rewritten.

## Recorded rules and legacy limitations

GameLogStore now preserves each checkpoint move's exact rulesVersion through
optional JSONL Entry and GameLogEvent fields. Newly appended moves record the
current version. Old logs missing the field decode to nil without being blocked;
nil is never guessed as version 1. ReplayExportSequence uses RulesEngine.replay
for known versions in both preflight and emitted positions, and current apply
only for unknown versions. Unsupported known versions stop at a partial prefix.

All-known videos show Reconstructed with recorded rules. If any move's version
is unknown, every frame including opening and ending shows Current rules for
unknown moves and Older rules unknown. The sheet and result warn that older or
mixed-version games can differ from the original even when reconstruction
succeeds. The ordinary GameReplayTimeline remains unchanged and may still use
current rules; video version handling is not a fidelity claim about that screen.

Unfinished games, failed reconstruction and unverified endings are labelled
Partial replay from the first frame. A JSONL end marker alone cannot establish
a win. Zero-move recordings conservatively retain the unknown-rules notice.

## Lifetime and long games

Encoding awaits each rendered image and limits its pixel-buffer pool to three;
it does not retain all raster frames. At 30 fps, each move lasts 20 frames with
60 opening and 90 closing frames. A 600-move movie is about 405 seconds and
approximately 101 MB at the configured 2 Mbps bitrate; this is a size estimate,
not a measured output, runtime or peak-memory result. The source archive and
ordinary replay timeline still have their own memory costs.

Closing or backgrounding cancels the model-owned task. Archive-read cancellation
propagates to its detached reader; export checks cancellation during preflight,
encoding and after finalization. The model fences late success, and export
cleanup finishes before retry is allowed. Closing after success removes only
the generated UUID directory. A share extension retains its file until sharing
returns; abandoned exports are eligible for cleanup after 24 hours. Encoding
has no background-task guarantee, and finalization cancellation must await the
writer callback before cleanup.

## Evidence and remaining acceptance

Main reported all three ReplayVideoExporterTests passing: actual MP4 decoding
and board changes, cancellation/retry cleanup, and diagnostic preservation.
Those results precede the final version-metadata and lifecycle additions here.
The reported 75-test focused run failed only on an unrelated development-card
assertion matching ready inside already; main fixed that assertion. This note
does not claim that the subsequent run passed.

Latest source additions require main's next serial compile and focused run:

- ReplayExportSequenceTests checks version IDs surviving checkpoint export and
  semantic legacy robber replay. A nil-victim move accepted under version 1 but
  rejected under current rules must still move the public robber. Missing fields
  stay nil; mixed known/unknown movies warn on every position; future versions
  cannot silently fall back.
- ReplayExportModelTests closes during actual writer progress, waits for cleanup,
  verifies no shareable result or leftover movie, and retries. It also closes
  immediately while preparing and checks that the archive remains intact.
- ReplayExportPresentationTests covers hidden-state removal, name opt-in and
  public captions. ReplayExportFlowTests covers safe defaults, preview, partial
  labels and the diagnostic warning; it does not prove a completed share extension.

The export agent ran only scoped lint and source parsing, not app builds, gate,
simulator interaction or test compilation. Remaining product acceptance is the
new focused run, native share completion, a genuinely completed game's video,
long-game resource measurements and visual inspection on supported iOS 17.

## Owned files and identifiers

The export work changes GameReplayView and the narrowly authorized version
fields/write/read path in GameLogStore. New production files are
ReplayVideoExport, ReplayExportPresentation, ReplayExportSequence,
ReplayMovieWriter, ReplayVideoExporter, ReplayExportModel, ReplayExportSheet and
ReplayVideoFrameView. Dedicated tests are ReplayExportFixtures,
ReplayExportPresentationTests, ReplayExportSequenceTests, ReplayVideoExporterTests,
ReplayExportModelTests and ReplayExportFlowTests. Project generation, builds and
all unrelated shared changes remain main-owned; no shared-checkout commit was made.

AccessibilityID.ReplayExport contains open, sheet, names, create, progress,
cancel, error, preview, share and diagnostic. Identifier strings are unchanged:
replay.export and replay-export followed by the corresponding action name.
Only this registry namespace was added; unrelated registry edits were preserved.
