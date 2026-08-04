# Save data

The project keeps persistent player data separate from cartridge-derived
`GameData` and from the scene-free battle engine. Save slots live under
Godot's `user://` directory and are never written into the repository.

## Current canonical model

The first save format stores the fields needed to restore a player party:

- game ID and ROM SHA-1, so a slot cannot be opened against another cache;
- party order and player name;
- each Pokémon's species, held item, level, experience, current HP and status;
- DVs, five Generation 2 stat-experience values, moves and remaining PP;
- identity fields reserved for later save import: OT ID, nickname, original
  trainer, happiness, Pokerus and caught data.

Derived battle stats are recalculated when a save is loaded. Volatile battle
state, such as stat stages, confusion, recharge, Disable, Encore, Fly, Dig,
Rollout and rampage, is never saved.

The format is versioned and validated against the selected `GameData` before a
slot is accepted. The current implementation provides three slots per game
revision and stores them as JSON under `user://save_slots`.

## Original Generation 2 shape

The canonical model follows the stable fields in the original Crystal source.
Its `box_struct` contains species, item, four moves, OT ID, three-byte
experience, five stat-experience words, DVs, PP, happiness, Pokerus, caught
data and level. Its `party_struct` adds status, current HP, maximum HP and the
five derived battle stats.

The original SRAM save also contains player, map, Pokémon, checksum, PC box,
mail, Hall of Fame and Crystal-specific data. Those regions are intentionally
not mixed into the first party-only save model. The cartridge adapter validates
the complete save boundary but exposes only the player and party fields until
the canonical model owns map, inventory, box and event state explicitly.

## Cartridge SRAM boundary

`Gen2SramAdapter` is the first real cartridge boundary. It accepts a raw SRAM
image as `PackedByteArray`, requires the supported ROM identity and a complete
32 KiB SRAM image, and accepts trailing bytes so emulator files with extra RTC
data are not truncated. Import selects the primary copy first, then the backup
copy, and refuses the image when both marker pairs or checksums fail.

The adapter currently maps the player name and the six-slot party: species,
held item, moves, OT ID, experience, stat experience, DVs, PP, happiness,
Pokerus, caught data, level, status, current HP, nickname and original trainer.
Derived party stats are regenerated from the selected `GameData` on export.
The primary copy is repaired from a valid backup before it is patched, and both
copies are rewritten with their little-endian 16-bit checksums. Bytes outside
those fields remain untouched. Export therefore needs an existing valid SRAM
image and does not pretend to create map or event state that the canonical
model does not own yet.

Gold and Silver share the same split backup layout. Their primary game data is
`0x2009..0x2D68`, with the checksum at `0x2D69`, the party at `0x288A`, and
backup data spread across SRAM banks at `0x0C6B`, `0x10E8`, `0x15C7`, `0x3D96`
and `0x7E39`. Crystal uses its own contiguous game data ranges, with primary
data at `0x2009..0x2B82`, checksum at `0x2D0D`, party at `0x2865`, and backup
data at `0x1209..0x1D82`, checksum at `0x1F0D`.

The implementation and synthetic fixtures live in:

- `game/save/sram_adapter.gd`
- `tests/unit/test_save.gd`

The layout and save behavior are based on pret's source: [Gold and Silver SRAM
layout](https://raw.githubusercontent.com/pret/pokegold/master/ram/sram.asm),
[Gold and Silver save routines](https://raw.githubusercontent.com/pret/pokegold/master/engine/menus/save.asm),
[Crystal SRAM layout](https://raw.githubusercontent.com/pret/pokecrystal/master/ram/sram.asm),
[Crystal save routines](https://raw.githubusercontent.com/pret/pokecrystal/master/engine/menus/save.asm),
[Crystal Pokémon data constants](https://raw.githubusercontent.com/pret/pokecrystal/master/constants/pokemon_data_constants.asm),
and the [Crystal SRAM bank map](https://raw.githubusercontent.com/pret/pokecrystal/master/layout.link).

Primary references:

- [pret/pokecrystal `macros/ram.asm`](https://github.com/pret/pokecrystal/blob/master/macros/ram.asm)
- [pret/pokecrystal `constants/pokemon_data_constants.asm`](https://github.com/pret/pokecrystal/blob/master/constants/pokemon_data_constants.asm)
- [pret/pokecrystal `ram/sram.asm`](https://github.com/pret/pokecrystal/blob/master/ram/sram.asm)
