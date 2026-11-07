# Empires Pass & Play requirements

Alex requested same-device multiplayer first on November 6 and authorized
implementation, simulator evidence, code review and merge on November 7.
Asynchronous play across two to four devices and timed live play follow in
[the separate online proposal](https://github.com/jakebeinart1/Settlers/pull/72).

## Product requirements

| Area | Player experience | Acceptance |
| --- | --- | --- |
| Setup | Pick Human, AI or an eligible Ghost in the existing player cards. Name each human and choose a civilization or Random. The start summary identifies Pass & Play. | Start with two, three or four people on the existing table. Preserve one-human play, name and civilization validation, seat order, AI difficulty, rules and board settings. Resume legacy three-seat saves. |
| Handoff | After another person is needed, the screen names them and explains the next action. They tap their own name to reveal their hand. | No private hand, card receipt, draft, action or VoiceOver element is available on the covered screen. A stale Ready action cannot claim the wrong seat. Keep the camera and fixed layout when the cover is lifted. |
| Turn and action ownership | The board identifies whose turn it is. A person responding outside that turn sees why they are needed. AI can finish its work while the phone is covered. | Play the opening snake in both directions, advance through mixed and all-human turns, and return to the original player after a discard, island harvest or trade. The next human can resume after an AI turn. |
| Trading | A human can offer a trade to a named human or negotiate with the AI as before. The recipient sees the terms and may decline even when they cannot afford them. | Only the intended recipient can answer. Accept changes both hands once; decline changes neither. The proposer gets the result. A directed offer survives a restart and has no timer during handoff. Bank trades keep their existing rules. |
| Resume | Returning to the menu, backgrounding or quitting keeps committed play. Resume behind the cover for the correct person. | Restore the same seats, board, phase and mandatory choice. No replayed roll, repeated trade, revealed hand or silently replaced save. A draft can be rebuilt if the phone changes hands. Unfinished shared recordings stay in private app storage and out of Game History and Files. |
| Results | Name the winner and show the table standings. Keep the local result with its match roster. | A Pass & Play match stays outside solo AI Elo and cloud identity attribution. Starting over preserves the existing save replacement warning and consequence for an unfinished rated solo game. |

## First-release choices

- Roles live in the existing player cards. Two or more humans make the table
  Pass & Play. Remember the last table setup. Guests are named for the match,
  with no sign-in, separate profile manager or lifetime guest rating. The app
  only updates the phone owner's name/civilization defaults from solo setup.
- Use a single recipient for human offers. Passing to each potential respondent
  for a table-wide offer would slow a shared-device game. Keep the existing AI
  competition behavior and ordinary bank trading. These defaults were chosen
  for the authorized first implementation and can be revisited after play.
- Lock the local view on app backgrounding, navigation out of the match and
  when action ownership changes. A phone sitting on a bot turn after resume
  stays covered until a human is owed a decision. No PIN is needed for this
  trusted in-person handoff. A shared replay appears in Game History after
  the game ends and its last private receipt has been acknowledged.
- Use the existing engine turn order and mandatory decisions. Keep Classic,
  Vast, Conquest and Voyages in scope. An island harvest or discard can belong
  to a different person than the turn owner. Accept existing legacy saves and
  preserve existing solo save, ratings and bot paths.

## Verification and PR evidence

Play through the normal New Game controls and cold resume with the existing
owned QA simulator. Cover 2 humans + AI and an all-human table, ordinary turns,
return to the correct person after off-turn decisions, directed trade accept
and decline, private receipts, completion and result attribution. Open Game
History during a handoff and after a win to check when the replay appears. Test old
checkpoint/replay decoding and legal trade recipient enforcement at the engine
boundary. Record focused tests separately from the required repository gate.

Capture and inspect each new visual state before merge. The PR gallery should
include setup roles, the first handoff, private active turn, bot wait, off-turn
handoff and choice, trade composition and response, return to the proposer,
locked resume and results. Identify any fixture-only images and keep original
captures. Check compact sizing, long names and accessibility before presenting
screenshots as evidence. Finish with independent spec and standards reviews.
