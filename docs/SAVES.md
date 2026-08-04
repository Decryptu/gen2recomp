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
not mixed into the first party-only save model. A future real `.sav` adapter
must map those regions explicitly and validate their checksums before exposing
them to the canonical model.

Primary references:

- [pret/pokecrystal `macros/ram.asm`](https://github.com/pret/pokecrystal/blob/master/macros/ram.asm)
- [pret/pokecrystal `constants/pokemon_data_constants.asm`](https://github.com/pret/pokecrystal/blob/master/constants/pokemon_data_constants.asm)
- [pret/pokecrystal `ram/sram.asm`](https://github.com/pret/pokecrystal/blob/master/ram/sram.asm)
