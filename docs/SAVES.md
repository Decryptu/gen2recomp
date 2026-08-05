# Save data

Project saves are separate from cartridge-derived `GameData` and the
scene-free battle engine. Slots live under Godot's `user://`, never in the
repository.

## Canonical project model

The versioned first format stores:

- game ID and ROM SHA-1, preventing use with another cache;
- player name and party order;
- an optional validated overworld snapshot containing the map ID, player cell,
  facing, movement mode, event flags, map scenes, inventory quantities, money,
  coins, phone contacts, repel steps, swarm state and roaming positions;
- each Pokémon's species, held item, level, experience, current HP, status,
  DVs, five Generation 2 stat-experience values, moves and PP;
- identity fields used by imported saves and party transactions: OT ID, nickname,
  original trainer, happiness, Pokerus and caught data;
- an `is_egg` marker for received eggs. Eggs remain in the party model but are
  rejected by the battle adapter until hatch behavior exists.

Derived battle stats are recalculated on load. Volatile state, including stat
stages, confusion, recharge, Disable, Encore, Fly, Dig, Rollout and rampage,
is never saved. The validator checks the selected `GameData`; three JSON slots
are available per game revision under `user://save_slots`.

## Player flow

The launcher selects an imported cache and opens `game/save/save_screen.tscn`.
The screen shows three explicit slots as `EMPTY`, `READY` or `INCOMPATIBLE` and
rejects a failed original `.sav` import before calling
`Gen2SaveStore.save`, so partial data cannot replace a slot.

New games accept a name of up to ten encoded characters and start Chikorita,
Cyndaquil or Totodile at level 5 holding Berry, with moves from the imported
learnset. When the selected cache contains the source home map, the save also
starts at map group 24, map 7, cell 3,3 with 3000 money. These values come from
Crystal's `SPAWN_HOME` record and `START_MONEY` constant. `game/save/party_screen.tscn`
shows all six positions, current and derived maximum HP, and persistent status.
It starts the development battle only after the same validated slot is selected
in `GameRuntime`.

After pending battle messages finish, `Gen2SaveBattleAdapter` writes back the
player name, Pokémon identity, held item, happiness, Pokerus, caught data,
nickname, original trainer, HP, status, experience, DVs, stat experience, moves
and PP. Volatile battle state is discarded.

Overworld battle writeback is transactional. A confirmed win is saved only
after its visible result messages finish. A loss never overwrites the selected
slot: the host validates and reconstructs the source save party, then returns a
blackout recovery result to the overworld. Continue enters the overworld when a
validated snapshot exists, and F5 writes the current map, player, item,
currency, event and schedule state back through `Gen2SaveStore`. Legacy project
saves without a world snapshot do not invent progress state and remain on the
configured development entry until a migration path exists. The validator
checks item and currency references against the selected cartridge cache, and
`Gen2WorldAPI.open_snapshot()` restores a saved position without clamping it to
another location.

Party-owned overworld transactions use a candidate `Gen2SaveData` and a live
world snapshot. Gifts, eggs, NPC trades, item effects and catches are applied to
that candidate first; validation and optional persistence happen before the
candidate replaces the caller's save. A failed write restores the live world
state. The current model refuses a sixth-party addition rather than sending it
to a PC box, because boxes are not yet canonical project data.

## Original Generation 2 shape

The model follows stable fields in the original Crystal source. `box_struct`
contains species, item, four moves, OT ID, three-byte experience, five
stat-experience words, DVs, PP, happiness, Pokerus, caught data and level.
`party_struct` adds status, current/max HP and five derived stats.

Original SRAM also contains player, map, checksum, PC box, mail, Hall of Fame
and Crystal-specific regions. The first model deliberately keeps cartridge SRAM
import party-only. The optional project-save world snapshot is a separate
canonical runtime shape and does not claim to reproduce unsupported SRAM bytes.

## Cartridge SRAM boundary

`Gen2SramAdapter` accepts a raw `PackedByteArray`, a supported ROM identity and
a complete 32 KiB SRAM image. It permits trailing emulator RTC data. Import
selects the primary copy, then the backup, and refuses both if their 99/127
markers or checksums fail. Gold and Silver use split backup regions; Crystal uses
contiguous ranges. A valid backup repairs the primary before patching, and
both copies are rewritten with little-endian 16-bit checksums.

The adapter maps player name and six-party fields: species, item, moves, OT ID,
experience, stat experience, DVs, PP, happiness, Pokerus, caught data, level,
status, current HP, nickname and original trainer. Derived stats are rebuilt
from selected `GameData`; bytes outside those fields stay untouched. Export
requires an existing valid SRAM image and does not invent unsupported map or
event state.

Gold/Silver primary data is `0x2009..0x2D68`, checksum `0x2D69`, party `0x288A`,
with backup at `0x0C6B`, `0x10E8`, `0x15C7`, `0x3D96`, `0x7E39`.
Crystal primary data is `0x2009..0x2B82`, checksum `0x2D0D`, party `0x2865`,
and backup `0x1209..0x1D82`, checksum `0x1F0D`.

Implementation and synthetic fixtures:

- `game/save/sram_adapter.gd`
- `tests/unit/test_save.gd`

Layout references: [Gold/Silver SRAM layout](https://raw.githubusercontent.com/pret/pokegold/master/ram/sram.asm), [Gold/Silver save routines](https://raw.githubusercontent.com/pret/pokegold/master/engine/menus/save.asm), [Crystal SRAM layout](https://raw.githubusercontent.com/pret/pokecrystal/master/ram/sram.asm), [Crystal save routines](https://raw.githubusercontent.com/pret/pokecrystal/master/engine/menus/save.asm), [Crystal Pokémon constants](https://raw.githubusercontent.com/pret/pokecrystal/master/constants/pokemon_data_constants.asm), [Crystal bank map](https://github.com/pret/pokecrystal/blob/master/layout.link), [Crystal RAM macros](https://github.com/pret/pokecrystal/blob/master/macros/ram.asm).
