# Empires domain language

Empires is a local hex-board strategy game. This glossary fixes the language for
the naval exploration product design; its rules and decisions live in the
[naval program](docs/AI_summaries/naval-exploration/README.md).

## Language

**Player hand**: The resources owned by one player, available for that player's
construction and trades across the map. It is not shared between players.
_Avoid_: Communal resource pool, shared player inventory.

**Resource bank**: The game's supply of resource cards, separate from every
player's hand.

**Ore**: The existing metal resource, used for the agreed ship recipe's iron.

**Naval mode (Voyages)**: The game mode built around purchasing independently
sailing ships, discovering randomized geography and establishing settlements.

**Ship**: A purchasable vessel with its own location and controlling player.
It sails independently and retains its identity when captured.
_Avoid_: Shipping-route segment, sea road.

**Sailing allowance**: Three one-hex sea steps available to each controlled ship
on its owner's turn. Newly launched or captured ships also receive three steps.

**Ship capture**: A transfer of a selected opposing ship's control enabled by
rolling 11. Control persists until a subsequent capture; it does not expire
automatically on the next 11.
_Avoid_: Temporary loan, automatic ownership reset, ship destruction.

**Discovery**: The public, permanent revelation of previously fogged geography.
Once discovered, a hex stays revealed for all players.

**Viewing range**: The two-hex reach from the actual ship position or settlement/
city corner. Naval rules version 2 measures a corner from all three canonical
touching hex centers; version 1 saved matches retain their original survey from
touching land centers. Previously discovered geography is never fogged again.

**Home survey**: The shared discovery of the home island before setup,
introduced by the opening mist withdrawal.

**Home settlement**: Either starting settlement can occupy any legal home-island
corner, inland or coastal. Later land expansion follows the player's own roads.
The ship-access rule only permits founding at the coastal corner an owned ship
actually touches; after founding, roads can expand inland on that island.

**Colony**: A player's settlement or city on an overseas island, separate from
the home island. It remains theirs when the founding ship sails away or is captured.

**Colony bonus**: A permanent point for founding on each of a player's first two
distinct overseas islands.

**Fog**: Concealment of undiscovered geography, including land and water, when
the fog setting is enabled. Its clearing is shown through a mist animation.

**Map family**: A geographic pattern whose individual layouts vary: Archipelago,
Peninsula or Twin Islands. Surprise me chooses one of these families.

**Resource-choice terrain**: Optional island terrain whose production grants the
adjacent settlement's player one bank card of their choice, or two for a city.
_Avoid_: A sixth resource, five simultaneous resource yields.

**Traditional bot**: Alex's term for the existing Classic difficulty. This is a
difficulty, distinct from the Classic game mode.

**Expert bot**: The existing Expert difficulty, with its strategy version
remembered by saved games.
