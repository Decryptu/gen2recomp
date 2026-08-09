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
  engine flags, the script memory bytes `readmem`/`loadmem` address, the current
  day/hour/minute clock and the daylight-saving flag;
- imported-save and party-transaction identity fields: OT ID, nickname, OT,
  happiness, Pokerus and caught data;
- `is_egg` for received eggs. An egg keeps its party slot and is skipped when
  the battle party is built, matching the cartridge refusing it as a combatant
  rather than removing it; the writeback puts it back in the same slot. Hatch
  behavior does not exist yet.

Derived battle stats are recalculated on load. Volatile state, including stages,
confusion, recharge, Disable, Encore, trapping, Fly, Dig, Rollout and rampage,
is never saved, and neither is the battle's own weather. A held item is not
volatile: a berry eaten in a battle is gone from the party afterwards.
The validator checks the selected `GameData`. Slots live under
`user://save_slots` per game revision and are created on demand rather than
preallocated, up to `Gen2SaveStore.MAX_SLOTS`; a slot number is still its file
name, so slots written before this stay where they were. Each save carries its
own `label`, the player's name for the slot, so an exported file names itself;
an empty label means fall back to the player name. Box names, current-box UI
state and cartridge SRAM box placement are intentionally outside this model.

Older project saves migrate in memory one version step at a time: version 1
gains fourteen empty boxes, version 2 gains an empty label. Migration preserves
a missing world snapshot as missing; it does not invent a map, player position
or event state. The next successful save writes version 3.

## Player flow

The launcher selects an imported cache and opens `game/save/save_screen.tscn`.
It lists the slots that exist as `READY` or `INCOMPATIBLE`, offers a new one at
the lowest free number, and rejects failed `.sav` imports before calling
`Gen2SaveStore.save`, so partial data cannot replace a slot. A game with no
saves lists none and has nothing selected.

New games accept up to ten encoded characters and start with an empty party,
matching Crystal's new-game initialization. When the source home map exists,
they start at map group 24, map 7, cell 3,3 with 3000 money, from Crystal's
`SPAWN_HOME` and `START_MONEY`. The imported Elm's Lab scripts offer Chikorita,
Cyndaquil or Totodile at level 5 holding Berry; the party host creates the first
save Pokémon only after the player confirms the source choice. The party screen
shows all six positions, current and maximum HP and persistent status, and
starts the development battle only once `GameRuntime` holds the same validated
slot.

After battle messages finish, `Gen2SaveBattleAdapter` writes player name,
Pokémon identity, held item, happiness, Pokerus, caught data, nickname, OT, HP,
status, experience, DVs, stat experience, moves and PP. Volatile state is
discarded.

Overworld writeback is transactional. A confirmed win saves after result
messages finish; a loss never overwrites the slot, and the host validates and
reconstructs the source save party before returning blackout recovery. Continue
enters the overworld only with a validated snapshot; the start menu's SAVE
writes map, player, items, currency, events, source engine flags and schedule
state through
`Gen2SaveStore`, with item and currency references checked against the selected
cache. Daily engine flags reset when the saved world day changes while story
flags such as Hall of Fame persist. Saves without a snapshot keep the configured
development entry, since migration invents no world position, and
`Gen2WorldAPI.open_snapshot()` restores a saved position without clamping it.

`box_screen.tscn`, opened from the party screen or from the imported Players
House PC as an embedded overworld overlay, presents one numbered box at a time
with twenty fixed slots and a party selection column. Depositing uses the
current box's first free slot, withdrawal requires party capacity, and both go
through `Gen2SaveStorage` to validate and write a candidate save before the
shared runtime object changes. The last party member cannot be boxed. The
current box is transient UI state; box names and SRAM placement stay outside the
model. Closing the embedded overlay resumes the paused source script with no
decoration change. Selected runtime saves persist transfers; injected scene-test
and development saves use the validated in-memory candidate without writing a
slot.

Party-owned overworld transactions modify a candidate `Gen2SaveData` and the
live world snapshot first. Gifts, eggs, NPC trades, source `HealParty` recovery,
item effects and catches commit only after validation and optional persistence,
and a failed write restores live world state. A full party routes a valid
addition to the first free PC slot; with the party and all 280 box slots
occupied the transaction refuses before consuming an item or ball, leaving save
and world state unchanged.

## Slot durability

A slot is two files. `Gen2SaveStore.save()` writes `slot_N.json` complete, then
copies it to `slot_N.json.bak`, following the cartridge's primary-then-backup
order in `_SaveGameData`. Each file begins with a header line carrying a 16-bit
additive checksum over its JSON payload, the algorithm `Checksum` uses in
`engine/menus/save.asm`, so a truncated or altered copy is refused rather than
loaded. Neither write depends on rename atomicity, which Godot does not provide
on Windows.

A load takes the primary and falls back to the backup on any failure: a missing
file, a bad header or checksum, invalid JSON, a failed migration or a validator
rejection. When both fail, the primary's message is reported. A slot counts as
occupied while either copy exists, so a lost primary cannot present itself as an
empty slot that a new game would overwrite. Unlike `TryLoadSaveFile`, a load
never repairs the weak copy, because drawing the slot menu loads every slot;
the next save rewrites both. Slots written before the header existed load
unchecked, which is also how an exported file with no header is accepted.

Export copies a slot file verbatim, header included. Import reads one back,
refuses a save recorded against another cartridge, and lands it in the lowest
free slot with that number written into the copy.

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
