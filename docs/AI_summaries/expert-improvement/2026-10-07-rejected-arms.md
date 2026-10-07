# Rejected Expert arms — October 7, 2026

**Nothing promoted.** Ten arms screened against the shipping Expert
(`pointCompletingCardsV1`, main `83d8525`); three confirmations on unseen seeds,
all inconclusive under the bot-strength rule (95% interval must clear zero).
Recorded so the next attempt does not re-run them.

Method: reciprocal 1-v-3 / 3-v-1, four chairs per board seed, 4p / 10 VP /
randomized, bootstrap over seed families. Relative Elo = half the difference of
focal-seat Elo (Plackett-Luce, null 25%). Every game finished.

## Screens (128 families, 1,024 games each, seeds 100000+)

| Arm | What it changed | Rel. Elo | 95% |
|---|---|---:|---|
| road | Longest-road chain credit capped at what still contests the bonus; zero if unreachable | −14.4 | [−31.6, +2.6] |
| knight | Played-knight credit capped at rival best + 1 | −7.3 | [−15.4, 0.0] |
| road+knight | both | −17.9 | [−34.5, −0.9] |
| soft-rival | log-sum-exp (T = 0.5) over rivals instead of the max | −2.6 | [−24.3, +18.7] |
| accept | trade acceptance credited with the purchase it completes | −23.0 | [−39.5, −6.3] |
| monopoly (peeking) | B-002 readiness extended to Monopoly using the real haul | +24.6 | [+11.8, +37.7] |
| monopoly (fair) | same, haul = ledger-proven cards only | +19.1 | [+6.4, +31.9] |
| pre-roll knight | play the best knight before rolling when the robber touches own building | +14.8 | [−7.4, +36.2] |
| pre-roll knight, any | same without the robber condition | −4.5 | [−26.4, +17.2] |
| threat | full rival weight once any rival is within 2 public VP | −1.8 | [−10.3, +6.4] |

The capped road/knight credits were the clearest lesson: the fitted
"progress" credits are doing work beyond the bonus they nominally track.
The peeking Monopoly arm was never a candidate (hidden information).

## Confirmations (declared before running)

| Arm | Seeds | Games | Rel. Elo | 95% |
|---|---|---:|---:|---|
| monopoly (fair) | 200000–200511 | 4,096 | +5.0 | [−1.6, +11.8] |
| pre-roll knight | 400000–400511 | 4,096 | +5.9 | [−4.5, +16.2] |
| both combined | 600000–601023 | 8,192 | +4.1 | [−3.6, +11.6] |

Screen estimates of +15 to +19 shrank to about +5 on fresh seeds: the
winner's-curse pattern the bot-strength skill warns about. The combination did
not add. If either is real it is under ~10 Elo; resolving it needs ~30,000+
games per arm, which was not declared and was not run.

## Not a statement about humans

The online ladder showed Expert at 1061 below Jake at 1110 on ~10 rated games.
At that sample the gap is inside Elo noise; it does not establish that Expert
is weaker than Jake, and nothing here measured play against humans.
