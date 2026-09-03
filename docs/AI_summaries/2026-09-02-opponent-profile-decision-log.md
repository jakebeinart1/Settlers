# Stable opponent profiles

Date: 2026-09-02
Branch: `codex/opponent-profiles`
Status: implemented and locally verified

## Problem

Production assigned Balanced, Aggressive, and Cautious by a bot's ordinal
chair. Moving a human, changing table size, or shuffling seats could therefore
change a named general's strategy while its civilization, appearance, and
dialogue stayed the same. Resume also trusted a separate civilization sidecar
even when the realized active-match record still held the exact assignment.

## Decisions

1. `OpponentProfile` is an app-domain value that composes stable ID, displayed
   general name, civilization, dialogue voice, and `OpponentStrategy`.
2. `OpponentStrategy` is the stable identifier; `BotPersonality` remains the
   tunable implementation. Persisting floating-point tuning values would turn
   every AI adjustment into a save migration.
3. Difficulty is not part of the profile. No calibrated ladder exists, and a
   style must not become stronger or weaker merely because its name changed.
4. The selected civilization currently selects the catalog opponent. This
   preserves the existing product model in which civilization determines the
   general and voice while removing seat-order behavior.
5. The realized active-match setup snapshots each bot's complete profile.
   Relaunch and Restart consume that snapshot, so future catalog edits do not
   retroactively change an in-progress opponent.
6. Restart preserves realized chairs and opponents while generating a fresh
   board according to the match's board setting. The New Game prefill remains
   the player's original configuration.
7. Game logs use schema v3 and snapshot profile ID, profile name, strategy,
   and civilization. V1/v2 rosters decode with empty profile fields.
8. `GameState` remains unaware of humans, bots, profiles, UI names, or voices.

## Acceptance evidence

- The catalog contains exactly one profile for every civilization and every
  currently measured strategy appears in the catalog.
- All 22 nonempty human-seat configurations across supported three- and
  four-seat tables assign no profile to humans and exactly one to every bot.
- The same general retains the same strategy when moved between bot chairs.
- Deleting the civilization sidecar still restores the exact civilizations
  and profiles from the active-match record.
- Relaunch restores a snapshotted profile rather than recomputing today's
  catalog entry.
- Restart preserves the realized opponent roster and does not overwrite the
  New Game prefill.
- A real first move writes profile ID, name, strategy, and civilization to the
  game archive.
- Existing v2 roster JSON remains readable.
- Legacy active matches retain their original ordinal Balanced/Aggressive/
  Cautious strategy assignment during migration.
- The realized active-match assignment outranks a stale same-sized
  civilization compatibility sidecar.

## Explicitly deferred

- Calibrated difficulty tiers.
- Player-facing profile selection; style labels remain hidden until blind
  recognition succeeds.
- A unified crash-atomic match envelope and match-ID validation across the
  game save, active setup, civilization compatibility sidecar, and active log.
- Persisting policy RNG for uninterrupted-versus-resumed trajectory identity.
