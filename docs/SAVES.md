# Save data

Project saves are separate from cartridge-derived `GameData` and the scene-free
battle engine. Slots live in Godot's `user://`, never in the repository.

## Canonical project model

Save format version 2 stores:

- game ID and ROM SHA-1, preventing use with another cache;
- player name, party order and each Pokémon's species, held item, level,
  experience, current HP, status, DVs, five Gen II stat-experience values,
  moves and PP;
- fourteen PC boxes with twenty ordered slots each. Boxed Pokémon use the same
  persistent model as party Pokémon. Gifts, eggs and catches fill the party
  first, then the first empty box slot in box order;
- an optional validated world snapshot: map ID, player cell, facing, movement
  mode, event flags, map scenes, inventory quantities, money, coins, phone
  contacts, seen species, repel steps, swarm state, roaming positions, source
  engine flags and the current day/hour/minute clock;
- imported-save and party-transaction identity fields: OT ID, nickname, OT,
  happiness, Pokerus and caught data;
- `is_egg` for received eggs. Eggs remain in the party model but the battle
  adapter rejects them until hatch behavior exists.

Derived battle stats are recalculated on load. Volatile state, including stages,
confusion, recharge, Disable, Encore, Fly, Dig, Rollout and rampage, is never
saved. The validator checks the selected `GameData`; three JSON slots exist per
game revision under `user://save_slots`. Box names, current-box UI state and
cartridge SRAM box placement are intentionally outside this model.

Version 1 project saves migrate in memory by adding fourteen empty boxes. The
migration preserves a missing world snapshot as missing; it does not invent a
map, player position or event state. The next successful save writes version 2.

## Player flow

The launcher selects an imported cache and opens `game/save/save_screen.tscn`.
It shows three slots as `EMPTY`, `READY` or `INCOMPATIBLE`, and rejects failed
`.sav` imports before calling `Gen2SaveStore.save`, so partial data cannot
replace a slot.

New games accept up to ten encoded characters and start Chikorita, Cyndaquil or
Totodile at level 5 holding Berry, with moves from the imported learnset. When
the source home map exists, they start at map group 24, map 7, cell 3,3 with
3000 money, from Crystal's `SPAWN_HOME` and `START_MONEY`. The party screen
shows all six positions, current and maximum HP, and persistent status; it
starts the development battle only after the same validated slot is selected in
`GameRuntime`.

After battle messages finish, `Gen2SaveBattleAdapter` writes player name,
Pokémon identity, held item, happiness, Pokerus, caught data, nickname, OT, HP,
status, experience, DVs, stat experience, moves and PP. Volatile state is
discarded.

Overworld writeback is transactional. A confirmed win saves after result
messages finish. A loss never overwrites the selected slot: the host validates
and reconstructs the source save party, then returns blackout recovery.
Continue enters the overworld only when a validated snapshot exists; F5 writes
map, player, items, currency, events, source engine flags and schedule state
through `Gen2SaveStore`. Daily engine flags reset when the saved world day
changes, while story flags such as Hall of Fame persist. Legacy saves without a
snapshot keep the configured development entry because migration does not
invent a world position. Item and currency references are
checked against the selected cache, and `Gen2WorldAPI.open_snapshot()` restores
the saved position without clamping it elsewhere.

The party screen opens `box_screen.tscn`, which presents one of fourteen numbered
boxes at a time with twenty fixed slots and a party selection column. Depositing
uses the current box's first free slot; withdrawal requires party capacity. Both
directions use `Gen2SaveStorage` to validate and write a candidate save before
updating the shared runtime object. The screen's current box is transient UI
state, and box names and cartridge SRAM placement remain outside the model.

The imported Players House PC opens the same box screen as an embedded
overworld overlay. Its close result resumes the paused source script with no
decoration change. Selected runtime saves persist transfers through the same
candidate-save boundary; injected scene-test and development saves use the
validated in-memory candidate without writing a slot.

Party-owned overworld transactions first modify a candidate `Gen2SaveData` and
live world snapshot. Gifts, eggs, NPC trades, item effects and catches commit
only after validation and optional persistence; a failed write restores live
world state. A full party routes a valid addition to the first free PC slot. If
the party and all 280 box slots are occupied, the transaction refuses before
consuming an item or ball and leaves the save and world state unchanged.

## Original Generation 2 shape

The model follows stable Crystal source fields. `box_struct` contains species,
item, four moves, OT ID, three-byte experience, five stat-experience words, DVs,
PP, happiness, Pokerus, caught data and level. `party_struct` adds status,
current/max HP and five derived stats.

Original SRAM also contains player, map, checksum, PC box, mail, Hall of Fame and
Crystal-specific regions. The first model imports only party data; the optional
project world snapshot is a separate canonical runtime shape and does not claim
to reproduce unsupported SRAM bytes.

## Cartridge SRAM boundary

`Gen2SramAdapter` accepts a raw `PackedByteArray`, supported ROM identity and
complete 32 KiB SRAM image, with trailing emulator RTC data allowed. Import
selects the primary copy, then backup, and rejects both if their 99/127 markers
or checksums fail. Gold/Silver use split backup regions; Crystal uses contiguous
ranges. A valid backup repairs the primary before patching, and both copies are
rewritten with little-endian 16-bit checksums.

It maps player name and six-party fields: species, item, moves, OT ID,
experience, stat experience, DVs, PP, happiness, Pokerus, caught data, level,
status, current HP, nickname and OT. Derived stats are rebuilt from selected
`GameData`; other bytes remain untouched. Export requires an existing valid SRAM
image and does not invent unsupported map or event state.

| Profile | Primary data | Checksum | Party | Backup |
|---|---|---|---|---|
| Gold/Silver | `0x2009..0x2D68` | `0x2D69` | `0x288A` | `0x0C6B`, `0x10E8`, `0x15C7`, `0x3D96`, `0x7E39` |
| Crystal | `0x2009..0x2B82` | `0x2D0D` | `0x2865` | `0x1209..0x1D82`, checksum `0x1F0D` |

Implementation and synthetic fixtures:

- `game/save/sram_adapter.gd`
- `tests/unit/test_save.gd`

Layout references: [Gold/Silver SRAM layout](https://raw.githubusercontent.com/pret/pokegold/master/ram/sram.asm), [Gold/Silver save routines](https://raw.githubusercontent.com/pret/pokegold/master/engine/menus/save.asm), [Crystal SRAM layout](https://raw.githubusercontent.com/pret/pokecrystal/master/ram/sram.asm), [Crystal save routines](https://raw.githubusercontent.com/pret/pokecrystal/master/engine/menus/save.asm), [Crystal Pokémon constants](https://raw.githubusercontent.com/pret/pokecrystal/master/constants/pokemon_data_constants.asm), [Crystal bank map](https://github.com/pret/pokecrystal/blob/master/layout.link), [Crystal RAM macros](https://github.com/pret/pokecrystal/blob/master/macros/ram.asm).
