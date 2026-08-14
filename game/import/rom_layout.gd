class_name RomLayout
extends RefCounted

## Where the data lives inside each supported cartridge.
##
## Offsets are absolute positions in the 2 MiB dump, not bank:address pairs, so
## a decoder never has to think about banking. Gold and Silver share the bank
## map, while a few data sections use per-game offsets; Crystal moved almost
## everything and is its own table.
##
## Every offset was located in the cartridges themselves, by searching for
## independently known bytes (the encoded string "BULBASAUR", Bulbasaur's
## published base stats), then cross-checked against the pret disassemblies for
## structure. An offset table is a claim about a specific dump, which is why an
## uncharacterised ROM is refused rather than guessed at.
##
## An offset is only trustworthy alongside its check: see
## [method RomImporter.verify_layout], run before anything is decoded.

const SPECIES_COUNT: int = 251
const NAME_LENGTH: int = 10
const BASE_STATS_SIZE: int = 32
const PIC_POINTER_SIZE: int = 3

## Map records are fixed-size entries in a 26-group table. Map dimensions are
## measured in 4x4-tile blocks, while event coordinates are measured in the
## resulting 2x2-cell walk grid.
const MAP_GROUP_COUNT: int = 26
const MAP_GROUP_POINTER_SIZE: int = 2
const MAP_RECORD_SIZE: int = 9
const MAP_ATTRIBUTES_SIZE: int = 12
const MAP_CONNECTION_RECORD_SIZE: int = 12
const MAP_CONNECTION_FLAG_EAST: int = 1
const MAP_CONNECTION_FLAG_WEST: int = 2
const MAP_CONNECTION_FLAG_SOUTH: int = 4
const MAP_CONNECTION_FLAG_NORTH: int = 8
const MAP_BLOCK_TILE_WIDTH: int = 4
const MAP_BLOCK_CELL_WIDTH: int = 2
const MAP_MAX_BLOCKS: int = 128
const MAP_MAX_WIDTH_BLOCKS: int = 40
const MAP_MAX_HEIGHT_BLOCKS: int = 54
const MAP_EVENT_HEADER_SIZE: int = 2
const MAP_WARP_EVENT_SIZE: int = 5
const MAP_COORD_EVENT_SIZE: int = 8
const MAP_BG_EVENT_SIZE: int = 5
const MAP_OBJECT_EVENT_SIZE: int = 13
const MAP_SCENE_SCRIPT_SIZE: int = 4
const MAP_CALLBACK_SIZE: int = 3
const MAP_MAX_SCENE_SCRIPTS: int = 32
const MAP_MAX_CALLBACKS: int = 16

## Normal and swarm wild encounter records are fixed-size tables keyed by map
## group and number. Grass carries three time-of-day rates and seven slots per
## time; water carries one rate and three slots. Fishing and roaming use their
## own source tables below.
const WILD_GRASS_RECORD_SIZE: int = 47
const WILD_WATER_RECORD_SIZE: int = 9
const WILD_GRASS_SLOT_COUNT: int = 7
const WILD_WATER_SLOT_COUNT: int = 3
const WILD_TIME_COUNT: int = 3
const WILD_TABLE_END: int = 0xFF
const WILD_GRASS_PROBABILITIES: Array[int] = [30, 60, 80, 90, 95, 99, 100]
const WILD_WATER_PROBABILITIES: Array[int] = [60, 90, 100]

## Fishing groups contain a chance byte and three CPU pointers. Each pointed
## rod table is a threshold/species/level stream whose final threshold is $FF.
## A species byte of zero means that the level byte indexes TimeFishGroups
## instead.
const FISH_GROUP_COUNT: int = 13
const FISH_GROUP_RECORD_SIZE: int = 7
const FISH_ROD_COUNT: int = 3
const FISH_TABLE_END: int = 0xFF
const FISH_TIME_GROUP_COUNT: int = 22
const FISH_TIME_GROUP_SIZE: int = 4
const FISH_MAX_ENTRIES: int = 8

## RoamMaps stores a start map, a count, that many target map pairs and a zero
## terminator. The complete table has sixteen source rows in all supported
## profiles.
const ROAM_MAP_COUNT: int = 16
const ROAM_TABLE_END: int = 0xFF

## TreeMonMaps and RockMonMaps are `(group, number, set)` triples ending in $FF.
## TreeMons is a pointer table into the same bank; each set is one or two
## `db %, species, level` tables, each ending in $FF. Sizes are never assumed:
## TreeMonSet_Rock ships a common table and no rare one, and pokegold's shared
## None/Unused/City set is five rows where every other set is six.
const TREEMON_MAP_RECORD_SIZE: int = 3
const TREEMON_TABLE_END: int = 0xFF
const TREEMON_MAX_ROWS: int = 16
const ASLEEP_TREEMON_TABLE_END: int = 0xFF
const ASLEEP_TREEMON_MAX_ROWS: int = 16

## The cartridge compares an 8-bit random value directly with these encoded
## percentage thresholds when it varies a surfing encounter's level. The
## values are the source's integer `$FF / 100 * percent` expressions.
const WILD_SURF_LEVEL_THRESHOLDS: Array[int] = [89, 165, 216, 242]

## The graphics stream supplies two blocks of 96 tiles: `LoadTilesetGFX`
## (home/map.asm) copies the first to vTiles2 in VRAM bank 0 and the second to
## vTiles5 in bank 1, at the same tile numbers. A metatile byte with the high bit
## set names the second block, because `_LoadOverworldAttrmapPals`
## (engine/tilesets/map_palettes.asm) reads the palette map at the full byte,
## takes bit 3 of the nibble as the VRAM bank, then clears bit 7 of the tile
## number. So the addressable span is 224: block 0 at 0..95, the 32 font tiles
## `_LoadFontsExtra1` owns at 96..127, and block 1 at 128..223. The strip carries
## all 224 with the font gap blank, so a metatile byte indexes it directly.
##
## Eight tilesets compress only one block; the cartridge copies whatever follows
## into bank 1 and no block of theirs ever names it, so the import blanks it.
## Metatile and collision tables are shorter for tilesets that never use all 128
## blocks; unused metatile entries may still contain $FF placeholders, which is
## why a tile number past the span resolves to 0 rather than to a read.
const TILESET_RECORD_SIZE: int = 15
const TILESET_TILE_COUNT: int = 224
const TILESET_BLOCK_TILES: int = 96
const TILESET_BLOCK_STRIDE: int = 128
const TILESET_META_BYTES_PER_BLOCK: int = 16
const TILESET_COLLISION_BYTES_PER_BLOCK: int = 4

## Overworld object graphics are six-byte records: CPU address, byte length,
## ROM bank, sprite type and default palette. The graphics are uncompressed
## 2bpp tiles. Palette records are four 15-bit colours, grouped by time of day
## and then by the eight overworld palette kinds.
const OVERWORLD_SPRITE_RECORD_SIZE: int = 6
const OVERWORLD_SPRITE_PALETTE_GROUP_COUNT: int = 32
const OVERWORLD_SPRITE_PALETTE_GROUP_BYTES: int = 8
const OVERWORLD_SPRITE_PALETTE_BYTES: int = OVERWORLD_SPRITE_PALETTE_GROUP_COUNT * OVERWORLD_SPRITE_PALETTE_GROUP_BYTES
const OVERWORLD_SPRITE_TYPES: Array = [1, 2, 3]
const OVERWORLD_SPRITE_PALETTE_COUNT: int = 8
## IconPointers has one null entry followed by the 38 reusable overworld icon
## shapes in constants/icon_constants.asm. The null entry is not graphic data.
const MON_ICON_COUNT: int = 38
const MON_ICON_TILES: int = 8
const MON_ICON_BYTES: int = MON_ICON_TILES * Gen2Tiles.TILE_BYTES

## Global overworld service tables. The source keeps these apart from map data:
## marts are an index table of item lists, phone contacts are fixed records,
## and audio is two far-pointer tables into the banked audio programs.
const MART_COUNT: int = 34
const MART_POINTER_SIZE: int = 2
const MART_RECORD_MAX_ITEMS: int = 16
const MART_TERMINATOR: int = 0xFF
## `NUM_FRUIT_TREES` (`constants/script_constants.asm`). `FruitTreeItems` is one
## item byte per tree, indexed by the `fruittree` command's operand less one, and
## both pins ship the same thirty rows.
const FRUIT_TREE_COUNT: int = 30
## The seven apricorn items, ascending, and where their run starts in the table.
## Rows 17 to 23 are `FRUITTREE_ROUTE_37_1` through `FRUITTREE_ROUTE_42_3`, and
## no other row bears one; both pins agree. Used to identify the table by
## content, since it has no header and no terminator.
const FRUIT_TREE_APRICORNS: Array[int] = [0x55, 0x59, 0x5C, 0x5D, 0x61, 0x63, 0x65]
const FRUIT_TREE_FIRST_APRICORN: int = 16
const PHONE_CONTACT_COUNT: int = 38
const PHONE_CONTACT_SIZE: int = 12
const SPECIAL_PHONE_CALL_COUNT: int = 8
const SPECIAL_PHONE_CALL_SIZE: int = 6
const PHONE_NON_TRAINER_NAME_POINTER_SIZE: int = 2
const AUDIO_POINTER_SIZE: int = 3
## Audio channel programs share subroutines within their bank, so one cached
## record keeps the complete 16 KiB bank window rather than truncating a valid
## jump target at the next top-level pointer.
const AUDIO_MAX_RECORD_BYTES: int = 0x4000
const AUDIO_WAVE_SAMPLE_COUNT: int = 10
const AUDIO_WAVE_SAMPLE_BYTES: int = 16
const AUDIO_DRUMKIT_COUNT: int = 6
const AUDIO_DRUMKIT_SAMPLE_COUNT: int = 13
const AUDIO_DRUMKIT_BYTES: int = 0x174
## `NUM_CRIES`, which is 68 rather than 67: constants/cry_constants.asm runs
## CRY_NIDORAN_M through CRY_DONPHAN inclusive. The pointer table's own last
## entry is CRY_DONPHAN and the next three bytes are already the SFX table, so a
## count of 67 dropped exactly one cry, the one species 232 asks for.
const AUDIO_CRY_COUNT: int = 68

## `PokemonCries` (data/pokemon/cries.asm): `mon_cry index, pitch, length` per
## species, six bytes a row. 255 rows, not 251: the table pads to `$ff` with four
## silent CRY_NIDORAN_M rows the way the pic tables pad.
##
## The table is what makes a cry per species rather than per stream: Ivysaur and
## Venusaur both play CRY_BULBASAUR and differ only in these two words.
const MON_CRY_COUNT: int = 255
const MON_CRY_ROW_SIZE: int = 6

## Rows pinned by value rather than by shape, since 255 six-byte rows of the
## right shape sit in more than one place. Species number to
## `[index, pitch, length]`, read off `data/pokemon/cries.asm`.
const MON_CRY_PINS: Dictionary = {
	1: [15, 128, 129],
	2: [15, 32, 256],
	3: [15, 0, 320],
	251: [55, 330, 273],
	252: [0, 0, 0],
}

## The overworld palette file contains 42 four-colour groups: morning, day,
## night and dark outdoor groups, the indoor group, and the two animated water
## groups. Palette maps use two nibbles per tile and reserve sixteen bytes for
## the font tiles between VRAM banks.
const WORLD_PALETTE_GROUP_COUNT: int = 42
const WORLD_PALETTE_GROUP_BYTES: int = 8
const WORLD_PALETTE_BYTES: int = WORLD_PALETTE_GROUP_COUNT * WORLD_PALETTE_GROUP_BYTES
const WORLD_PALETTE_MAP_BYTES: int = 0x70
const WORLD_ANIMATION_BANK: int = 0x3F
const WORLD_ANIMATION_COMMAND_BYTES: int = 4
const WORLD_ANIMATION_MAX_COMMANDS: int = 64

const MOVE_COUNT: int = 251
const MOVE_DATA_SIZE: int = 7

## Item numbers run from 1 to 255. The last several entries are the unused
## "TERU-SAMA" slots the cartridges ship with; they are decoded rather than
## trimmed, so an item number always indexes the table directly.
const ITEM_COUNT: int = 255
const ITEM_ATTRIBUTE_SIZE: int = 7
const ITEM_ATTRIBUTE_PARAM: int = 3
const ITEM_ATTRIBUTE_PERMISSIONS: int = 4
const ITEM_ATTRIBUTE_POCKET: int = 5
const ITEM_ATTRIBUTE_HELP: int = 6
## The item attribute table calls this field a pocket, but its value is the
## cartridge's item type: ITEM=1, KEY_ITEM=2, BALL=3, TM_HM=4.
const ITEM_POCKET_BALL: int = 3
const ITEMMENU_NOUSE: int = 0
const ITEMMENU_CURRENT: int = 4
const ITEMMENU_PARTY: int = 5
const ITEMMENU_CLOSE: int = 6
## Both permission bits read inverted: a set bit is what the item cannot do.
const ITEM_ATTRIBUTE_CANT_SELECT: int = 1 << 6
const ITEM_ATTRIBUTE_CANT_TOSS: int = 1 << 7
const TRADE_RECORD_SIZE: int = 32
const TRADE_NAME_LENGTH: int = 11
const TRADE_GENDER_EITHER: int = 0
const TRADE_GENDER_MALE: int = 1
const TRADE_GENDER_FEMALE: int = 2

## Type numbers are sparse: $00-$09 are the physical types, $14-$1B the special
## ones, and the run between is padding that still has a name entry. Reading all
## 28 keeps the table indexable by type number.
const TYPE_COUNT: int = 28
const TYPE_POINTER_SIZE: int = 2

## The type numbers themselves. Only the ones something here names are listed:
## the rest are reached by number, since a move's type byte is already one.
## $06 sits between ROCK and BUG and is the unused BIRD slot, which is why the
## physical types are not a contiguous run of nine.
const TYPE_NORMAL: int = 0x00
const TYPE_FIGHTING: int = 0x01
const TYPE_FLYING: int = 0x02
const TYPE_POISON: int = 0x03
const TYPE_GROUND: int = 0x04
const TYPE_ROCK: int = 0x05
## The unused physical type between Rock and Bug, and the run of ten between
## Steel and Fire that holds only `CURSE_TYPE`. No move and no species carries
## either, and both exist here because Hidden Power's type has to step over them
## (`constants/type_constants.asm`, `engine/battle/hidden_power.asm`).
const TYPE_BIRD: int = 0x06
const TYPE_UNUSED_START: int = 0x0A
const TYPE_UNUSED_END: int = 0x14
const TYPE_BUG: int = 0x07
const TYPE_GHOST: int = 0x08
const TYPE_STEEL: int = 0x09
const TYPE_FIRE: int = 0x14
const TYPE_WATER: int = 0x15
const TYPE_GRASS: int = 0x16
const TYPE_ELECTRIC: int = 0x17
const TYPE_PSYCHIC: int = 0x18
const TYPE_ICE: int = 0x19
const TYPE_DRAGON: int = 0x1A
const TYPE_DARK: int = 0x1B

## The longest move and item name in these games is twelve characters. This is
## the runaway guard for a terminator walk, not a field width.
const MAX_NAME_LENGTH: int = 16

## The type matchup chart: three bytes an entry, attacker then defender then the
## multiplier, and only the exceptions are listed. A pair that is not in the
## table is [constant MATCHUP_EFFECTIVE], which is why the whole of Generation 2
## fits in 332 bytes.
##
## Multipliers are in tenths as the cartridge stores them, applied by multiplying
## then dividing by ten. Tenths rather than a float because the games truncate
## after each of a defender's two types.
const MATCHUP_ENTRY_SIZE: int = 3
const MATCHUP_ATTACKER: int = 0
const MATCHUP_DEFENDER: int = 1
const MATCHUP_MULTIPLIER: int = 2

const MATCHUP_NO_EFFECT: int = 0
const MATCHUP_NOT_VERY_EFFECTIVE: int = 5
const MATCHUP_EFFECTIVE: int = 10
const MATCHUP_SUPER_EFFECTIVE: int = 20

## Every multiplier the table actually contains. [constant MATCHUP_EFFECTIVE] is
## not among them: a neutral matchup is an absent row, so a byte of 10 here would
## mean the walk has left the table.
const MATCHUP_MULTIPLIERS: Array = [
	MATCHUP_NO_EFFECT, MATCHUP_NOT_VERY_EFFECTIVE, MATCHUP_SUPER_EFFECTIVE,
]

## The table ends twice. $FE ends it for a defender under Foresight, and $FF ends
## it for everything else, so the rows between the two are exactly the matchups
## Foresight cancels: Normal and Fighting against a Ghost. Reading the rows as
## "true unless Foresight" rather than "extra under Foresight" is the way round
## the cartridge means them, and the flag in the cache is named for it.
const MATCHUP_END_FORESIGHT: int = 0xFE
const MATCHUP_END: int = 0xFF

## What the walk has to find. All three games carry the same chart, so unlike the
## trainer class count these are constants rather than layout entries.
const MATCHUP_COUNT: int = 108
const FORESIGHT_MATCHUP_COUNT: int = 2

## Runaway guard for the walk, well past the real end of the table.
const MAX_MATCHUPS: int = 256

## A type number the chart can name. The physical types run $00-$09 and the
## special ones $14-$1B; everything between is padding that a move may carry but
## that no matchup mentions.
const PHYSICAL_TYPES_END: int = 0x09
const SPECIAL_TYPES_START: int = 0x14

## One Pokedex entry (data/pokemon/dex_entries.asm): a terminated category
## string, then height and weight as little-endian words, then two terminated
## description pages.
##
## The page break is the terminator itself, not a code of its own: `MACRO page`
## in macros/scripts/text.asm is `db "@", \#`, so an entry ends after the second
## terminated run rather than at the first.
##
## Height is decimal digits of feet and inches (204 is 2'04") and weight is
## tenths of a pound (150 is 15.0 lb), which is why both are stored raw and
## formatted at draw time rather than converted here.
const DEX_ENTRY_PAGES: int = 2
const DEX_ENTRY_MEASUREMENT_BYTES: int = 2
## Runaway guard for a page walk, well past the longest entry in any of the
## three dumps (the longest measured is under 200 bytes).
const DEX_ENTRY_MAX_PAGE_LENGTH: int = 256
## The category is at most twelve characters, the same guard the move and item
## name walks use.
const DEX_ENTRY_MAX_CATEGORY_LENGTH: int = MAX_NAME_LENGTH

## Pointers are two bytes and bank-local, and the bank is chosen by species
## rather than stored: GetDexEntryPointer (engine/pokedex/pokedex_2.asm) rotates
## `species - 1` twice and masks to NUM_DEX_ENTRY_BANKS bits, which is
## `(species - 1) >> 6`. The four sections are species 1-64, 65-128, 129-192 and
## 193-251.
const DEX_ENTRY_POINTER_SIZE: int = 2
const DEX_ENTRY_BANK_SPECIES: int = 64
const DEX_ENTRY_BANK_COUNT: int = 4

## The three orderings Pokedex_OrderMonsByMode builds, as constants/ram_constants.asm
## numbers them. UNOWN is the fourth mode and is not one of these: it lists Unown
## forms rather than species, from its own table.
const DEXMODE_NEW: int = 0
const DEXMODE_OLD: int = 1
const DEXMODE_ABC: int = 2
const DEXMODE_UNOWN: int = 3

## Evolutions and level-up moves are one table, not two. A species' entry lists
## its evolutions, then a zero byte, then its level-up moves as level and move
## pairs, then another zero byte. One pointer answers both questions, which is
## why the two are decoded in the same pass rather than as separate tables.
##
## The pointers are two bytes rather than three: the entries sit in the pointer
## table's own bank, so there is no bank number to store.
const EVOS_ATTACKS_POINTER_SIZE: int = 2
const EVOS_ATTACKS_END: int = 0

## How a species evolves. The byte after the method is a level for
## [constant EVOLVE_LEVEL] and [constant EVOLVE_STAT], an item for
## [constant EVOLVE_ITEM], the item that has to be held for
## [constant EVOLVE_TRADE] ($FF when the trade needs none), and a time of day for
## [constant EVOLVE_HAPPINESS].
const EVOLVE_LEVEL: int = 1
const EVOLVE_ITEM: int = 2
const EVOLVE_TRADE: int = 3
const EVOLVE_HAPPINESS: int = 4
## The one method that takes a second parameter, and the one only Tyrogue uses:
## a level, and then which way Attack and Defense have to compare.
const EVOLVE_STAT: int = 5

## Every method the table can name, which is what makes an evolution entry
## checkable: the byte that opens one is either a method or the terminator.
const EVOLVE_METHODS: Array = [
	EVOLVE_LEVEL, EVOLVE_ITEM, EVOLVE_TRADE, EVOLVE_HAPPINESS, EVOLVE_STAT,
]

## What [constant EVOLVE_HAPPINESS] asks about besides the happiness itself.
## Golbat evolves at any time, Eevee into Espeon by day and Umbreon by night.
const TRIGGER_ANYTIME: int = 1
const TRIGGER_MORNDAY: int = 2
const TRIGGER_NITE: int = 3

## Which way Attack and Defense have to compare for [constant EVOLVE_STAT].
const ATTACK_OVER_DEFENSE: int = 1
const ATTACK_UNDER_DEFENSE: int = 2
const ATTACK_EQUALS_DEFENSE: int = 3

## The highest level these games count to, and so the highest a level-up move or
## a level evolution can name.
const MAX_LEVEL: int = 100

## Runaway guards for the two walks. Five evolutions is the most any species has
## and fourteen level-up moves is the most, so both are well clear.
const MAX_EVOLUTIONS: int = 8
const MAX_LEVEL_UP_MOVES: int = 32

## Every evolution in the table, counted. All three games agree, as they do about
## the type matchup chart, so this is a constant rather than a layout entry.
const EVOLUTION_COUNT: int = 122

## Muk, whose level-up moves are not in ascending order. The cartridges ship it
## that way in all three games, and it is not a decoding artefact: pret's own
## listing carries a comment saying so.
##
## Named rather than worked around, because the order is load bearing: filling a
## fresh Pokémon stops at the first entry above its level, so a Muk below 45
## never reaches the three moves after the level 45 one. Checking the order
## everywhere else is worth the exception, since scrambled levels are exactly
## what a wrong offset produces.
const UNSORTED_LEARNSET_SPECIES: int = 89

## Unown's entry in the main pic table is a deliberate $FF placeholder: its 26
## letter forms live in a table of their own.
const UNOWN_SPECIES: int = 201
const UNOWN_FORMS: int = 26

## The font is indexed by character code, not by position in a sheet: its first
## tile is code $80 ("A") and its last is $FF ("9"). That is not a coincidence of
## ordering, it is how the hardware prints at all. The font is loaded so that a
## character byte is already the tile number to draw, so the alphabet's runs in
## [Gen2Text] and the tiles here are the same run seen twice.
const FONT_TILES: int = 128
const FONT_FIRST_CODE: int = 0x80

## The alphabets and the digits: A-Z, a-z, 0-9. Every one of these has a glyph
## in every supported cartridge, and they are the runs [Gen2Text] builds
## arithmetically rather than listing.
const FONT_INK_RUNS: Array = [[0x80, 0x99], [0xA0, 0xB9], [0xF6, 0xFF]]

## Codes with no character in [Gen2Text], whose tiles are therefore blank. These
## sit between the runs above, which is what makes the pair a layout check: an
## offset out by a single tile drags a blank onto "z" and a glyph onto a code
## that has none, and both halves fail at once.
##
## Not every unmapped code is here. Crystal draws an arrow at $EB where Gold and
## Silver leave a hole, so only the runs all three agree on are checked.
const FONT_BLANK_RUNS: Array = [[0xBA, 0xBF], [0xC6, 0xCF], [0xD7, 0xDE]]

## Text box borders: eight to choose from, six tiles each, in the order
## ┌ ─ ┐ │ └ ┘. They are loaded at code $79, which is where the box-drawing
## codes start in [Gen2Text], so those codes address the border directly and a
## box is drawn by printing characters like anything else.
const FRAME_COUNT: int = 8
const FRAME_TILES: int = 6
const FRAME_FIRST_CODE: int = 0x79
## Positions within a frame.
const FRAME_TOP_LEFT: int = 0
const FRAME_HORIZONTAL: int = 1
const FRAME_TOP_RIGHT: int = 2
const FRAME_VERTICAL: int = 3
const FRAME_BOTTOM_LEFT: int = 4
const FRAME_BOTTOM_RIGHT: int = 5

## The battle HUD's own graphics, which sit in the same section as the font and
## the text box borders and are the rest of what a battle screen draws.
##
## [code]battle_font[/code] is 2bpp and carries "HP:", the nine fill levels of
## the HP bar and the battle screen's odds and ends. The two HUD borders are 1bpp
## and are the boxes a name and a level sit in, one shape for the enemy's and one
## for the player's. The exp bar is 2bpp and is seven fill levels and two ends.
const BATTLE_FONT_TILES: int = 32
## Where `_LoadFontsBattleExtra` puts its first tile: `ld hl, vTiles2 tile $60`.
## Its twenty-five tiles cover $60 to $78, so a code in that run addresses this
## strip rather than the main font while it is loaded, which is what
## [constant Gen2Text.FONT_BATTLE_EXTRA] names.
const BATTLE_FONT_FIRST_CODE: int = 0x60
const ENEMY_HUD_TILES: int = 4
const PLAYER_HUD_TILES: int = 6
const EXP_BAR_TILES: int = 9

## The trainer card's own graphics (engine/menus/trainer_card.asm).
##
## `CardStatusGFX` is six tiles but `_Option`'s page 1 asks for 86, running
## straight on into `LeaderGFX`, so the strip page 1 loads is those 86 tiles from
## the card_status offset. Pages 2 and 3 load 86 from the leaders offset, which
## overlaps it; both are imported, because that is what each page draws.
##
## The pic is a 5x7 picture. Crystal stores it column-major (`--columns` plus
## `PlaceGraphic`, which fills down each column) and Gold and Silver row-major
## (their own inline `.row`/`.col` loop), so the importer reorders Crystal's into
## the picture and both profiles reach the screen the same way.
const CARD_STATUS_TILES: int = 86
const CARD_LEADER_TILES: int = 86
const CARD_BADGE_TILES: int = 44
const CARD_RIGHT_CORNER_TILES: int = 1
const CARD_FRAME_TILES: int = 6
const CARD_PIC_COLUMNS: int = 5
const CARD_PIC_ROWS: int = 7
const CARD_PIC_TILES: int = CARD_PIC_COLUMNS * CARD_PIC_ROWS

## `DrawIntroPlayerPic`'s uncompressed 7x7 picture. Crystal stores Chris and
## Kris column-major; Gold and Silver use CAL's normal trainer picture instead.
const INTRO_PLAYER_PIC_COLUMNS: int = 7
const INTRO_PLAYER_PIC_ROWS: int = 7
const INTRO_PLAYER_PIC_TILES: int = INTRO_PLAYER_PIC_COLUMNS * INTRO_PLAYER_PIC_ROWS

## `InitGender`'s own background: one 2bpp tile of a single colour index, and the
## four-colour palette it is read through. `InitGenderScreen` ByteFills the whole
## tilemap with tile $00, which is where `LoadGenderScreenLightBlueTile` puts it,
## so the index in that tile is the field the box and menu are drawn over.
const GENDER_SCREEN_TILES: int = 1
const GENDER_SCREEN_PALETTE_COLORS: int = 4
## The index every pixel of the tile carries, which is `.Palette`'s second
## colour, RGB 09,30,31.
const GENDER_SCREEN_FILL_INDEX: int = 1

## `Copyright` (engine/menus/intro_menu.asm): 29 or 30 tiles requested into
## `vTiles2 tile $60`, and `CopyrightString` placed at (2,7). The string is
## `data/copyright.asm`, three `next`-separated rows of nothing but those tile
## codes, so the screen is the strip plus the code run and needs no font.
const COPYRIGHT_FIRST_CODE: int = 0x60
const COPYRIGHT_AT: Vector2i = Vector2i(2, 7)
## `PREDEFPAL_GAMEFREAK_LOGO_BG` (gfx/sgb/predef.pal), which `_CGB_GamefreakLogo`
## loads before `SplashScreen` draws the copyright. Its first colour is black and
## its last white, so the screen is white on black rather than the other way
## round.
const COPYRIGHT_PALETTE_COLORS: int = 4
## `PlaceString` stops at "@", and the rows are separated by `next`.
const COPYRIGHT_STRING_TERMINATOR: int = 0x50
const COPYRIGHT_STRING_NEXT: int = 0x4E
## Long enough for either pin's three rows; a run that reaches it has not found
## its terminator and is not the string.
const COPYRIGHT_STRING_MAX: int = 64
const COPYRIGHT_STRING_ROWS: int = 3

## `GameFreakLogoGFX` (engine/movie/splash.asm), which is two `INCBIN`s back to
## back rather than one run: `gamefreak_presents.1bpp` and then
## `gamefreak_logo.1bpp`. `Get1bpp` loads all 28 at once, but the halves are
## addressed apart. The BG strings index the first thirteen plus the logo's own
## first tile, which is blank and is the space in "GAME FREAK"; Gold's logo
## sprite draws the fifteen.
const PRESENTS_WORD_TILES: int = 13
const PRESENTS_LOGO_TILES: int = 15
const PRESENTS_GFX_TILES: int = PRESENTS_WORD_TILES + PRESENTS_LOGO_TILES
## The six tiles of "PRESENTS", which sit a row below "GAME FREAK" and so carry
## no ink in their top two rows.
const PRESENTS_SECOND_WORD_FIRST: int = 7
const PRESENTS_SECOND_WORD_TILES: int = 6
const PRESENTS_SECOND_WORD_CLEAR_ROWS: int = 2

## `GameFreakLogoStarsGFX`: `logo_star.2bpp` then `logo_sparkle.2bpp`, Gold and
## Silver only. Crystal spends the same beat on a Ditto instead.
const PRESENTS_STAR_TILES: int = 2
const PRESENTS_SPARKLE_TILES: int = 3
const PRESENTS_STARS_TILES: int = PRESENTS_STAR_TILES + PRESENTS_SPARKLE_TILES

## `GameFreakDittoGFX`, one LZ run `GameFreakPresentsInit` splits over `vTiles0`
## and `vTiles1` as 128 tiles each. The OAM sets index the result with a stride
## of $10, so it is one 16x16 sheet.
const PRESENTS_DITTO_COLUMNS: int = 16
const PRESENTS_DITTO_TILES: int = PRESENTS_DITTO_COLUMNS * PRESENTS_DITTO_COLUMNS
## `gfx/splash/ditto.pal`, which `_CGB_GamefreakLogo` loads into both object
## palettes. Colour 0 is white and so transparent on a sprite; colour 2 is the
## pink the fade below moves.
const PRESENTS_DITTO_PALETTE_COLORS: int = 4
const PRESENTS_DITTO_FADE_COLOR: int = 2
## `GameFreakDittoPaletteFade` (`gfx/splash/ditto_fade.pal`), one colour per step
## of `GameFreakLogo_Transform`. Crystal only.
const PRESENTS_DITTO_FADE_COLORS: int = 16

## `PREDEFPAL_GAMEFREAK_LOGO_OB`, the object palette Gold and Silver draw the
## star, the logo and the sparkles through. It sits eight bytes in front of
## `PREDEFPAL_GAMEFREAK_LOGO_BG`, which is the copyright screen's own palette.
const PRESENTS_OBJECT_PALETTE_COLORS: int = 4

## The title screen (`_TitleScreen` on Crystal, `TitleScreen` on Gold and Silver,
## `engine/movie/title.asm`). Two different screens sharing a phase: Crystal
## decompresses three graphics and holds sixteen palettes of its own, while Gold
## and Silver decompress two halves of a logo over one `$FF`-terminated tilemap
## and animate a bird sprite behind a raw trail.
##
## Every offset was located the way the splash's were: the pinned PNG encoded as
## cartridge 2bpp and matched, or, for an LZ run, every offset in the bank
## decompressed and the one reproducing the PNG exactly kept. Each hits once.
const TITLE_SUICUNE_TILES: int = 256
## `--trim-end 4`: `DrawTitleGraphic` places 7 rows of 20 from `vTiles1`, and the
## four tiles past them are whitespace the build drops.
const TITLE_LOGO_TILES: int = 156
## `--interleave`, so the sheet is a column of 8x16 objects rather than rows:
## `InitializeBackground` walks five columns of six sprites, stepping the tile
## number by two each time.
const TITLE_CRYSTAL_TILES: int = 60
const TITLE_CRYSTAL_SPRITE_COLUMNS: int = 5
const TITLE_CRYSTAL_SPRITE_ROWS: int = 6
## `TitleScreenPalettes` (`gfx/title/title.pal`), copied whole into both buffers.
const TITLE_PALETTES: int = 16
const TITLE_PALETTE_COLORS: int = 4

## Gold and Silver's own halves. `TitleScreenGFX1` is `--trim-whitespace`, which
## takes the bottom of the logo from 120 tiles to 112.
const TITLE_LOGO_BOTTOM_TILES: int = 112
const TITLE_LOGO_TOP_TILES: int = 60
## `TitleScreenTilemap`, read a byte at a time until `-1`. Long enough for either
## pin's run; one that reaches this has not found its terminator.
const TITLE_TILEMAP_TERMINATOR: int = 0xFF
const TITLE_TILEMAP_MAX: int = 1024
## `debgcoord 0, 0`: the run is written straight into the BG map rather than into
## the tilemap a screen is drawn from, so a row is `TILEMAP_WIDTH` and not
## `SCREEN_WIDTH`. The twelve bytes past column 19 are off the right of the
## screen and are blanks.
const TITLE_TILEMAP_COLUMNS: int = 32
const TITLE_TILEMAP_VISIBLE_COLUMNS: int = 20
## `TitleScreenGFX3` is four drawn tiles on both profiles, but `TitleScreen`
## copies eight whatever it is: Gold ships four blank tiles behind its trail and
## Silver's four come off the head of the compressed Lugia, loaded into VRAM and
## never shown. The source says so at the `FarCopyBytes`.
const TITLE_TRAIL_DRAWN_TILES: int = 4
const TITLE_TRAIL_COPIED_TILES: int = 8

## `GSTitleBGPals` and `GSTitleOBPals`, contiguous in `engine/gfx/color.asm`.
const TITLE_BG_PALETTES: int = 5
const TITLE_OB_PALETTES: int = 2

## `engine/menus/start_menu.asm`'s `.PokedexDesc` through `.QuitDesc`, one
## contiguous run of `PlaceString` strings in the order they are defined, which
## is not the order `.Items` lists them in. MENU ACCOUNT is what draws one.
const MENU_DESCRIPTION_COUNT: int = 9
## Long enough for the longest ("Trainer's key device"); a run that reaches it
## has not found its terminator and is not the table.
const MENU_DESCRIPTION_MAX: int = 64
## The order the strings are laid out in, as the start menu's own item kinds.
## `quit` is the Bug Contest's, which this project never shows.
const MENU_DESCRIPTION_ORDER: Array[StringName] = [
	&"pokedex", &"pokemon", &"pack", &"pokegear", &"player", &"save", &"option",
	&"exit", &"quit",
]

## `data/text/common_2.asm`'s pack texts, each a `text_far` target the way the
## intro texts are: `UseItem`'s two refusals and `TossMenu`'s three.
const PACK_TEXT_MAX_BYTES: int = 256

## `gfx/font/bg_text.pal`, PAL_BG_TEXT. Stored whole rather than as a pair: a
## palette fade over a text box passes through its two middle colours even
## though a 1bpp glyph never draws them.
const TEXT_BG_PALETTE_COLORS: int = 4

## `ShrinkFrame`'s `ld c, 7 * 7`: both shrink pictures are the same 7x7 box the
## trainer and player pics fill, and `PlaceGraphic` lays them down each column.
const SHRINK_PIC_COLUMNS: int = 7
const SHRINK_PIC_ROWS: int = 7
const SHRINK_PIC_TILES: int = SHRINK_PIC_COLUMNS * SHRINK_PIC_ROWS
## The two sheet names the cache holds them under.
const SHRINK_PIC_NAMES: Array[String] = ["shrink_1", "shrink_2"]

## `_CGB_TrainerCard`'s eight background palettes, as the trainer classes it
## reads them from, in its own call order. Slot 0 is the player's own class,
## which is why the cache carries a class the trainer tables otherwise skip;
## slot 1 is Falkner's, which the source's own comment marks as Kris's card
## palette and which Clair borrows further down.
const CARD_PALETTE_CLASSES: Array[int] = [0, 1, 3, 2, 4, 7, 6, 5]

## `PREDEFPAL_CGB_BADGE` (gfx/sgb/predef.pal), the object palette every badge
## sprite is drawn with. Four colours rather than a pair, since a predef palette
## is stored whole.
const CARD_BADGE_PALETTE_COLORS: int = 4

## The region map (`_TownMap` and `PokegearMap`, engine/pokegear/pokegear.asm).
##
## `Pokegear_LoadGFX` builds one VRAM window for both screens: `TownMapGFX` at
## `vTiles2`, `PokegearGFX` at `vTiles2 tile $30` and `PokegearSpritesGFX` at
## `vTiles0`, which is where the cursor's tiles come from. All three are LZ runs.
const TOWN_MAP_TILES: int = 48
const TOWN_MAP_FIRST_TILE: int = 0x00
const POKEGEAR_TILES: int = 46
const POKEGEAR_FIRST_TILE: int = 0x30
const POKEGEAR_SPRITE_TILES: int = 9
## `FastShipGFX`, uncompressed and copied over the player icon's own tiles when
## the player is on the S.S. Aqua, so it is the same four-frame walk read from
## eight tiles rather than twenty-four.
const FAST_SHIP_TILES: int = 8

## `JohtoMap` and `KantoMap` (gfx/pokegear/johto.bin, kanto.bin): one tile number
## per cell of the whole screen, then `-1`. `FillTownMap` writes them from (0,0),
## so a region map covers the screen before any frame is drawn over it.
const TOWN_MAP_REGION_CELLS: int = 360
const TOWN_MAP_REGION_TERMINATOR: int = 0xFF
const TOWN_MAP_REGION_BYTES: int = TOWN_MAP_REGION_CELLS + 1

## `PokedexNestIconGFX`, the blinking marker `Pokedex_GetArea` puts on every
## landmark a species is found at. One uncompressed tile sitting directly behind
## `KantoMap`, so the region map locates it rather than a fourth offset.
const DEX_NEST_ICON_TILES: int = 1

## `TownMapPals`: a palette per tile id, condensed to nybbles, least significant
## first. It covers $00 to $5f; $60 and above take palette 0.
const TOWN_MAP_PALETTE_MAP_BYTES: int = 48
const TOWN_MAP_PALETTE_MAP_LIMIT: int = 0x60
## `MalePokegearPals`/`FemalePokegearPals` (`PokegearPals` on Gold and Silver),
## which are gfx/pokegear/pokegear.pal: border, earth, mountain, city, point of
## interest and mountain point of interest. Only the city palette differs between
## the two Crystal copies.
const TOWN_MAP_PALETTES: int = 6
const TOWN_MAP_PALETTE_COLORS: int = 4
## Every one of the six opens on the same off-white, which is what identifies the
## run: RGB 28,31,20.
const TOWN_MAP_PALETTE_FIRST_COLOR: int = 0x53FC

## The credits (`engine/movie/credits.asm`).
##
## `CreditsScript`'s commands, `const_def -1, -1`: the byte a command is not is a
## `CreditsStringsPointers` index.
const CREDITS_END: int = 0xFF
const CREDITS_WAIT: int = 0xFE
const CREDITS_SCENE: int = 0xFD
const CREDITS_CLEAR: int = 0xFC
const CREDITS_MUSIC: int = 0xFB
const CREDITS_WAIT2: int = 0xFA
const CREDITS_THEEND: int = 0xF9
## The commands that take one operand; the rest are one byte.
const CREDITS_OPERAND_COMMANDS: Array[int] = [
	CREDITS_WAIT, CREDITS_WAIT2, CREDITS_SCENE,
]

## `CreditsBorderGFX`, then the four `Credits*GFX` mon sheets, uncompressed and
## contiguous in that order, and `CreditsScript` directly behind them. So one
## pinned offset locates all six and the run's own length pins the script.
const CREDITS_BORDER_TILES: int = 9
## `Credits_LoadBorderGFX.Frames` steps in 16-tile blocks, which is the 4x4 cell
## the banner is five copies of.
const CREDITS_MON_FRAME_TILES: int = 16
const CREDITS_SCENES: int = 4
const CREDITS_SCENE_FRAMES: int = 4
## `TheEndGFX` (gfx/misc.asm), eight tiles across and two down.
const CREDITS_THE_END_TILES: int = 16
const CREDITS_THE_END_COLUMNS: int = 8

## `Credits`' own VRAM window: the current mon frame's sixteen tiles at
## `vTiles2`, the border at tile $20, "The End" at $40 and `CopyrightGFX` at $60,
## which is where `LoadFontsBattleExtra` would put its strip. Letters are $80 and
## up and are untouched.
const CREDITS_BORDER_FIRST_CODE: int = 0x20
const CREDITS_THE_END_FIRST_CODE: int = 0x40

## `CreditsPalettes` (gfx/credits/credits.pal). Crystal copies 24 bytes per
## scene, which is BG palettes 0, 1 and 2; Gold and Silver copy 8 twice, so
## palettes 0 and 1 are the same four colours.
const CREDITS_PALETTE_COLORS: int = 4
## Every scene's first palette closes on RGB 07,07,07 in all three dumps, which
## is what identifies the run.
const CREDITS_PALETTE_LAST_COLOR: int = 0x1CE7

## Long enough for either script and either longest string; one that reaches
## these has not terminated.
const CREDITS_SCRIPT_MAX_BYTES: int = 1024
const CREDITS_STRING_MAX_BYTES: int = 64

## The intro movie (`CrystalIntro`, engine/movie/intro.asm).
##
## Every graphic, tilemap, attrmap and palette the movie draws is one contiguous
## section behind the code, in the INCBIN order below, and each entry starts on a
## sixteen-byte boundary from the first. So one pinned offset walks all
## thirty-five: decompress an entry, round its length up to
## [constant INTRO_ENTRY_ALIGN], and that is where the next one starts.
const INTRO_ENTRY_ALIGN: int = 16
## `IntroScene28`'s own count, which the movie ends on.
const INTRO_SCENES: int = 28
## The tilemaps and attrmaps are whole 32x32 BG maps, not screens.
const INTRO_MAP_COLUMNS: int = 32
const INTRO_MAP_ROWS: int = 32
const INTRO_MAP_BYTES: int = INTRO_MAP_COLUMNS * INTRO_MAP_ROWS
## Every `ld bc, 16 palettes` the movie copies into `wBGPals1`/`wBGPals2`.
const INTRO_PALETTES: int = 16
const INTRO_PALETTE_COLORS: int = 4
## `Intro_Scene24_ApplyPaletteFade.FadePals` (gfx/intro/fade.pal): eight
## palettes, one of which is copied over all eight BG palettes at a time.
const INTRO_FADE_PALETTES: int = 8
## `Intro_Scene20_AppearUnown`'s `.pal1` and `.pal2`, one palette each and
## contiguous, so the first pins the second.
const INTRO_UNOWN_PALETTES: int = 2
## The section's entries, as (cache name, kind, tiles). `map` is a 32x32 BG map,
## `attr` its attribute plane, `pal` a raw [constant INTRO_PALETTES] run and
## `raw` uncompressed tiles; everything else is an LZ tile strip of that many
## tiles. The order is `engine/movie/intro.asm`'s own INCBIN order and is what
## the walk depends on.
const INTRO_SECTION: Array[Array] = [
	["suicune_run", "lz", 192],
	["pichu_wooper", "lz", 128],
	["background", "lz", 128],
	["background_map", "map", 0],
	["background_attr", "attr", 0],
	["background_palette", "pal", 0],
	["unowns", "lz", 128],
	["pulse", "lz", 16],
	["unown_a_map", "map", 0],
	["unown_a_attr", "attr", 0],
	["unown_hi_map", "map", 0],
	["unown_hi_attr", "attr", 0],
	["unowns_map", "map", 0],
	["unowns_attr", "attr", 0],
	["unowns_palette", "pal", 0],
	["crystal_unowns", "lz", 32],
	["crystal_unowns_map", "map", 0],
	["crystal_unowns_attr", "attr", 0],
	["crystal_unowns_palette", "pal", 0],
	["suicune_close", "lz", 256],
	["suicune_close_map", "map", 0],
	["suicune_close_attr", "attr", 0],
	["suicune_close_palette", "pal", 0],
	["suicune_jump", "lz", 128],
	["suicune_back", "lz", 128],
	["suicune_jump_map", "map", 0],
	["suicune_jump_attr", "attr", 0],
	["suicune_back_map", "map", 0],
	["suicune_back_attr", "attr", 0],
	["suicune_palette", "pal", 0],
	["unown_back", "lz", 48],
	["grass_1", "raw", 4],
	["grass_2", "raw", 4],
	["grass_3", "raw", 4],
	["grass_4", "raw", 1],
]
## `Intro_RustleGrass` swaps four tiles at `vTiles2 tile $09` between three of
## the grass strips; `IntroScene15` and `IntroScene19` load the fourth as a
## single sprite tile.
const INTRO_GRASS_FIRST_TILE: int = 0x09
## The blank the two Suicune scenes park in the sprite tile the dict points at.
const INTRO_GRASS_BLANK: String = "grass_4"

## `GoldSilverIntro` (pokegold/engine/movie/intro.asm), the movie Gold and Silver
## run where Crystal runs `CrystalIntro`: seventeen scenes over water, grass and
## fire rather than twenty-eight over Unown and Suicune.
##
## Its art section is the same shape as Crystal's, contiguous and
## [constant INTRO_ENTRY_ALIGN]-aligned, so the one pinned address walks all
## eleven entries. The names are pret's own file names, which are also the INCBIN
## order the walk depends on: `1` is the sheet a scene puts at `vTiles2` and `2`
## the one it puts at `vTiles0`, and `fire2` is the third at `vTiles1`.
const GS_INTRO_SCENES: int = 17
const GS_INTRO_SECTION: Array[Array] = [
	["water1", "lz", 128],
	["water_tilemap", "raw_bytes", 512],
	["water_meta", "raw_bytes", 272],
	["water2", "lz", 128],
	["grass1", "lz", 48],
	["grass_tilemap", "raw_bytes", 256],
	["grass_meta", "raw_bytes", 112],
	["grass2", "lz", 144],
	["fire1", "lz", 128],
	["fire2", "lz", 80],
	["fire3", "lz", 100],
]
## `Intro_DrawBackground` reads a 16-wide map of 2x2 metatiles through
## `Intro_Draw2x2Tiles`, which looks each byte up in the `.bin` four bytes at a
## time. `TILEMAP_WIDTH` is 32 (constants/hardware.inc), so a full draw is
## sixteen metatiles across and sixteen down, filling the whole BG map rather
## than the twenty visible columns.
const GS_INTRO_META_COLUMNS: int = 16
const GS_INTRO_META_BYTES: int = 4
## `ld de, Intro_WaterTilemap + 15 tiles`: the water scene starts fifteen
## metatile rows down its own map and scrolls up towards the surface, while the
## grass scene starts at its map's first row.
const GS_INTRO_WATER_FIRST_ROW: int = 15

## `Intro_LoadMagikarpPalettes`' inline `.MagikarpBGPal` and `.MagikarpOBPal`,
## and `_CGB_GSIntro.ShellderLaprasScene`'s `gfx/intro/shellder_lapras_bg.pal`
## and `_ob.pal`. Each pair is contiguous, so one pinned address per pair walks
## both; the object run is two palettes and every other one is a single palette.
const GS_INTRO_MAGIKARP_PALETTES: int = 2
const GS_INTRO_SHELLDER_LAPRAS_PALETTES: int = 3

## `PredefPals` (gfx/sgb/predef.pal), eight bytes an entry. The three the movie
## reads are contiguous, so the run's own base is what locates them, and that
## base is already pinned: `game_freak_presents.object_palette` is
## `PREDEFPAL_GAMEFREAK_LOGO_OB`, index 77 of this table, which is what
## `verify_gs_intro` checks the base against for nothing.
const GS_INTRO_PREDEF_SIZE: int = INTRO_PALETTE_COLORS * Gen2Palette.COLOR_BYTES
const GS_INTRO_PREDEF: Dictionary = {
	"jigglypuff_pikachu_bg": 56,
	"jigglypuff_pikachu_ob": 57,
	"starters_transition": 58,
	# `PalPacket_Pack + 1` is PACK, ROUTES, ROUTES, ROUTES, and `WipeAttrmap`
	# leaves every tile on palette 0, so PACK is the only one the screen shows.
	"pack": 60,
}
const GS_INTRO_PREDEF_GAMEFREAK_LOGO_OB: int = 77

## `OakRatings` (data/events/pokedex_ratings.asm): nineteen `rating` rows of a
## caught-count threshold, an sfx word and a text pointer, which `FindOakRating`
## walks until the count fits. The five texts around it are located from the
## table rather than pinned again: `engine/events/prof_oaks_pc.asm` lays the
## stubs out as `OakPCText1`, `2` and `3` in front of `OakRating01` and
## `OakPCText4` behind `OakRating19`, each a `text_far` and a `text_end`.
const OAK_RATING_COUNT: int = 19
const OAK_RATING_SIZE: int = 5
const OAK_TEXT_STUB_SIZE: int = 5
## Their order in the run, as offsets in stubs from `OakRating01`.
const OAK_TEXT_STUBS: Dictionary = {
	"ask": -3, "level": -2, "counts": -1, "closed": OAK_RATING_COUNT,
}
## The caught count `FindOakRating`'s last row answers, which is every species.
const OAK_RATING_LAST_THRESHOLD: int = 255
## Long enough for the longest rating; one that reaches it has not terminated.
const OAK_TEXT_MAX_BYTES: int = 256

## `PokemonCenterPC.Jumptable`'s five strings, one contiguous `@`-terminated run
## in the source's own row order, and the six `text_far` stubs the routine's
## own texts sit behind, which follow it at a fixed distance on all three
## cartridges.
const POKECENTER_PC_ROWS: Array[String] = [
	"players_pc", "bills_pc", "oaks_pc", "hall_of_fame", "turn_off",
]
## `PlayersPCMenuData.PlayersPCMenuPointers`' own seven. The run below is the
## order the *strings* are laid down in, which is not the jumptable's:
## `.TurnOff` sits before `.LogOff` while `PLAYERSPCITEM_LOG_OFF` is 5 and
## `PLAYERSPCITEM_TURN_OFF` is 6. `.WhichPC` names the jumptable, so a list entry
## is read through `POKECENTER_PC_PLAYERS_ORDER`.
const POKECENTER_PC_PLAYERS_AT: int = 0x168
const POKECENTER_PC_PLAYERS_ROWS: Array[String] = [
	"withdraw_item", "deposit_item", "toss_item", "mail_box", "decoration",
	"turn_off", "log_off",
]
const POKECENTER_PC_PLAYERS_ORDER: Array[String] = [
	"withdraw_item", "deposit_item", "toss_item", "mail_box", "decoration",
	"log_off", "turn_off",
]
const POKECENTER_PC_ROW_MAX_BYTES: int = 24
## `.WhichPC`: each list is a count, that many row indices and a `-1`. Both
## tables follow their own string run, so the walk that reads the strings is
## what finds them.
const POKECENTER_PC_LISTS: int = 3
const POKECENTER_PC_PLAYERS_LISTS: int = 2
const POKECENTER_PC_LIST_END: int = 0xFF
## Every `text_far` stub the two routines print through, as its own distance
## from the row run. The six the top menu uses are one consecutive block; the
## item PC's eight are scattered through `pokecenter_pc.asm` between the
## submenus that own them, so each is pinned rather than strided.
const POKECENTER_PC_TEXT_AT: Dictionary = {
	"ask_what_do": 0x1D2,
	"how_many_withdraw": 0x256,
	"withdrew": 0x25B,
	"no_room_withdraw": 0x260,
	"no_items": 0x2CD,
	"how_many_deposit": 0x374,
	"deposited": 0x379,
	"no_room_deposit": 0x37E,
	"turn_on": 0x42D,
	"whose": 0x432,
	"bills_pc": 0x437,
	"players_pc": 0x43C,
	"oaks_pc": 0x441,
	"closed": 0x446,
}

## `Landmarks` (data/maps/landmarks.asm): `db x + 8, y + 16` then a name pointer,
## so the stored bytes are already shadow-OAM coordinates and the raw x,y are
## screen pixels. Gold and Silver ship no `BATTLE TOWER`, so every landmark from
## it onward is one lower; see [Gen2WorldRadio]'s own constants.
const LANDMARK_RECORD_SIZE: int = 4
const LANDMARK_COUNT: int = 96
const LANDMARK_COUNT_GOLD_SILVER: int = 95
const LANDMARK_OAM_X: int = 8
const LANDMARK_OAM_Y: int = 16
## `GetLandmarkName` copies exactly this many bytes whatever the name's length.
const LANDMARK_NAME_BYTES: int = 18

## The battle animation data layer: the per-move scripts and the four tables the
## objects they spawn are built from.
##
## Every one of the five is stored as a contiguous region rather than entry by
## entry, because each is a pointer table immediately followed by the data it
## points at, and every pointer inside it is bank-local. Keeping the region whole
## means a cached address resolves by subtraction and the bytes are the
## cartridge's own; see [Gen2BattleAnimImporter].
##
## `BattleAnimations` (data/moves/animations.asm) is indexed by move number, so
## entry 0 is `BattleAnim_Dummy` and 1 is `BattleAnim_Pound`. Entries past
## [constant MOVE_COUNT] are the four the table pads to $100 with and then the
## non-move animations, which `wFXAnimID`'s high byte reaches.
const BATTLE_ANIM_SCRIPT_COUNT: int = 278
const BATTLE_ANIM_OBJECT_COUNT: int = 188
const BATTLE_ANIM_OBJECT_SIZE: int = 6
const BATTLE_ANIM_FRAMESET_COUNT: int = 185
const BATTLE_ANIM_OAM_SET_COUNT: int = 216
const BATTLE_ANIM_OAM_SET_SIZE: int = 4
## `dbsprite`: y, x, tile, attributes.
const BATTLE_ANIM_OAM_SPRITE_SIZE: int = 4
## `AnimObjGFX` is `const_def 1`, so index 0 is a slot no `anim_*gfx` names and
## the table is one longer than [code]NUM_BATTLE_ANIM_GFX[/code].
const BATTLE_ANIM_GFX_COUNT: int = 42
const BATTLE_ANIM_GFX_SIZE: int = 4
## `AnimObjGFX`'s last two rows are `anim_obj_gfx 1, NULL`:
## `BATTLE_ANIM_GFX_PLAYERHEAD` and `..._ENEMYFEET` are written into
## `wBattleAnimTileDict` by `BattleAnimCmd_BattlerGFX_1Row`/`_2Row` off the
## battler's own pic, and are named by no `anim_*gfx` command, so neither row
## has a sheet to decode.
const BATTLE_ANIM_GFX_FIRST_SHEET: int = 1
const BATTLE_ANIM_GFX_LAST_SHEET: int = 39

## `BattleAnimSineWave`, the 32-word table `BattleAnim_Sine` and `..._Cosine`
## multiply an amplitude by (engine/battle_anims/functions.asm). It sits in the
## same bank as the four tables above, immediately before `BattleAnimFrameData`.
const BATTLE_ANIM_SINE_SAMPLES: int = 32
const BATTLE_ANIM_SINE_BYTES: int = BATTLE_ANIM_SINE_SAMPLES * 2

## What that table holds, pinned the way [constant BAR_PALETTES] pins the bars'
## colours: the values are the check for the offset. It is `sine_table 32`, which
## rgbasm evaluates at assembly time, and entry 16 is why it is imported rather
## than re-derived: sin(pi/2) is 1.0, which lands on $0100 and not the $00FF an
## eight-bit derivation produces. The same 64 bytes are in all three dumps.
const BATTLE_ANIM_SINE_WAVE: Array[int] = [
	0x00, 0x00, 0x19, 0x00, 0x32, 0x00, 0x4A, 0x00, 0x62, 0x00, 0x79, 0x00, 0x8E, 0x00, 0xA2, 0x00,
	0xB5, 0x00, 0xC6, 0x00, 0xD5, 0x00, 0xE2, 0x00, 0xED, 0x00, 0xF5, 0x00, 0xFB, 0x00, 0xFF, 0x00,
	0x00, 0x01, 0xFF, 0x00, 0xFB, 0x00, 0xF5, 0x00, 0xED, 0x00, 0xE2, 0x00, 0xD5, 0x00, 0xC6, 0x00,
	0xB5, 0x00, 0xA2, 0x00, 0x8E, 0x00, 0x79, 0x00, 0x62, 0x00, 0x4A, 0x00, 0x32, 0x00, 0x19, 0x00,
]

## The eight `PAL_BATTLE_OB_*` object palettes an animation object's palette byte
## indexes, and which of them the cartridge stores.
##
## Only six are stored. `_CGB_BattleScreenLayout` (engine/gfx/cgb_layouts.asm)
## copies `BattleObjectPals` into `wOBPals1` from slot 2 on, four colours each,
## and fills slots 0 and 1 from the two battlers' own two-colour palettes through
## `LoadPalette_White_Col1_Col2_Black`, so `PAL_BATTLE_OB_ENEMY` and
## `PAL_BATTLE_OB_PLAYER` are whoever is on the field rather than table rows.
const BATTLE_OBJECT_PALETTE_COUNT: int = 8
const BATTLE_OBJECT_PALETTE_FIRST_STORED: int = 2
const BATTLE_OBJECT_PALETTES_STORED: int = 6
const BATTLE_OBJECT_PALETTE_COLORS: int = 4

## The names the cache keys them by, in the cartridge's own order from
## `PAL_BATTLE_OB_GRAY` on (constants/battle_anim_constants.asm).
const BATTLE_OBJECT_PALETTE_NAMES: Array = [
	"gray", "yellow", "red", "green", "blue", "brown",
]

## What those palettes hold, the way [constant BAR_PALETTES] pins the bars':
## content known independently of the offset, so the values are the check.
## `gfx/battle_anims/battle_anims.pal`, as packed 15-bit colours.
const BATTLE_OBJECT_PALETTES: Array = [
	[0x7FFF, 0x6739, 0x35AD, 0x0000],
	[0x7FFF, 0x1FFF, 0x061F, 0x0000],
	[0x7FFF, 0x627F, 0x195E, 0x0000],
	[0x7FFF, 0x072C, 0x01C5, 0x0000],
	[0x7FFF, 0x7D88, 0x7C81, 0x0000],
	[0x7FFF, 0x1E58, 0x0DF4, 0x0000],
]

## The four palettes a battle draws its bars with: the HP bar in green, yellow
## or red depending on how much is left, and the exp bar in blue. They are two
## colours each like a species' palette, white and black being implied, and they
## sit immediately before the species palettes in every game.
##
## The names are the cache's keys, and the order is the cartridge's.
const BAR_PALETTE_NAMES: Array = ["hp_green", "hp_yellow", "hp_red", "exp"]

## What those palettes hold. This is content whose value is known independently,
## like the first species name, so the check for the offset is the values
## themselves: every bar shares a light colour and differs in the dark one.
const BAR_PALETTES: Array = [
	[0x3F5E, 0x02E0], [0x3F5E, 0x02BF], [0x3F5E, 0x001F], [0x3F5E, 0x7E24],
]

## An HP bar is green down to half and yellow down to a fifth, measured in lit
## pixels rather than in hit points: what colours the bar is what is drawn.
const HP_GREEN_PIXELS: int = 24
const HP_YELLOW_PIXELS: int = 10

## The HP bar's fill levels within [constant BATTLE_FONT_TILES], and the exp
## bar's within its own strip. Each step lights one more column, which is two
## more pixels than the step before, and that progression is what proves the
## offset: nothing else in the section counts up like this.
const HP_BAR_FIRST_TILE: int = 2
const HP_BAR_LEVELS: int = 9
const EXP_BAR_LEVELS: int = 7
const BAR_STEP_PIXELS: int = 2

## Trainer classes are numbered from 1; class 0 is the player, who has a palette
## in the table but no pic in it. Crystal added one class to the sixty-six Gold
## and Silver have, so the count lives in the layout rather than here.
##
## Every trainer pic is this square, unlike a Pokémon's front pic.
const TRAINER_PIC_TILES: int = 7

## A second table indexed like the class names, pics and palettes, one pointer
## per class, holding the individual trainers. "LEADER" is the class name every
## gym leader shares; FALKNER is stored inside class 1's party entry beside the
## Pokémon he brings, so a class's identity always means reading two tables.
##
## Two-byte pointers in the pointer table's own bank, like [member evos_attacks]:
## the entries share that bank, so there is no bank number to store.
const TRAINER_PARTY_POINTER_SIZE: int = 2

## What a trainer's Pokémon carries, in the type byte between its name and its
## first Pokémon. The low bit says whether it holds an item, the high bit
## whether it knows chosen moves rather than whatever its level teaches it.
const TRAINER_MON_NORMAL: int = 0
const TRAINER_MON_MOVES: int = 1
const TRAINER_MON_ITEM: int = 2
const TRAINER_MON_ITEM_MOVES: int = 3
const TRAINER_MON_TYPES: Array = [
	TRAINER_MON_NORMAL, TRAINER_MON_MOVES, TRAINER_MON_ITEM, TRAINER_MON_ITEM_MOVES,
]

## How many move slots a stored-moves Pokémon carries in the table, whatever a
## zero slot in it means: nothing, the way [Gen2BattleMon] treats one.
const TRAINER_MON_MOVE_COUNT: int = 4

## One trainer's Pokémon list ends here; so does a class's whole party group, but
## the two terminators are not read the same way. A Pokémon's own end is read
## for real; a group's is only reached by the *next* class's pointer, because
## nothing marks a group's end from inside it. See [constant EMPTY_TRAINER_CLASS].
const TRAINER_PARTY_END: int = 0xFF

## What a trainer can carry. Six is the real maximum in all three games, not a
## rule this layout invents.
const MAX_TRAINER_PARTY_SIZE: int = 6

## Runaway guard for a single class's trainers, well past the real maximum of 31
## (the wandering trainer classes: YOUNGSTER, LASS and the like carry the most).
const MAX_TRAINERS_PER_CLASS: int = 64

## The trainer *attributes* table: a third table indexed the same way as the
## class names, pics, palettes and parties, one fixed-stride entry per class
## rather than a pointer, and it is where a class's own AI behaviour lives.
## Seven bytes: two item numbers this class may use, a base money reward, then
## two words of bit flags. Confirmed against `TrainerClassAttributes` entry by
## entry: Falkner opens with his listed bytes, class 5 (Pryce) is the first to
## differ with a Hyper Potion, and one class carries an AI move weight word of
## zero ([constant NO_AI]), which the check must allow rather than reject.
const TRAINER_ATTRIBUTES_SIZE: int = 7
const ATTR_ITEM1: int = 0
const ATTR_ITEM2: int = 1
const ATTR_BASE_REWARD: int = 2
const ATTR_AI_MOVE_WEIGHTS: int = 3
const ATTR_AI_ITEM_SWITCH: int = 5

## Which of a move's scoring routines run, as a bitfield: [constant AI_BASIC]
## always runs when any bit is set, and the rest layer their own nudges on top
## of it. A class can carry none of them ([constant NO_AI]), which is not a
## decoding failure: Twins are really that undiscerning on the cartridge.
const AI_BASIC: int = 1 << 0
const AI_SETUP: int = 1 << 1
const AI_TYPES: int = 1 << 2
const AI_OFFENSIVE: int = 1 << 3
const AI_SMART: int = 1 << 4
const AI_OPPORTUNIST: int = 1 << 5
const AI_AGGRESSIVE: int = 1 << 6
const AI_CAUTIOUS: int = 1 << 7
const AI_STATUS: int = 1 << 8
const AI_RISKY: int = 1 << 9
const NO_AI: int = 0

## Every bit [constant ATTR_AI_MOVE_WEIGHTS] can legally carry. A wrong offset
## reading this word as something else has roughly a 1.5% chance of landing
## inside this mask by accident, and has to do it 66 or 67 times running.
const AI_MOVE_WEIGHTS_MASK: int = AI_BASIC | AI_SETUP | AI_TYPES | AI_OFFENSIVE \
	| AI_SMART | AI_OPPORTUNIST | AI_AGGRESSIVE | AI_CAUTIOUS | AI_STATUS | AI_RISKY

## How a class uses its held items and when it switches out. Bit 3 is skipped
## in the cartridge's own numbering (`const_skip` in pret's source), which is
## why the flags jump from [constant SWITCH_SOMETIMES] to [constant ALWAYS_USE].
const SWITCH_OFTEN: int = 1 << 0
const SWITCH_RARELY: int = 1 << 1
const SWITCH_SOMETIMES: int = 1 << 2
const ALWAYS_USE: int = 1 << 4
const UNKNOWN_USE: int = 1 << 5
const CONTEXT_USE: int = 1 << 6

## Every bit [constant ATTR_AI_ITEM_SWITCH] can legally carry, bit 3 excluded.
const AI_ITEM_SWITCH_MASK: int = SWITCH_OFTEN | SWITCH_RARELY | SWITCH_SOMETIMES \
	| ALWAYS_USE | UNKNOWN_USE | CONTEXT_USE

## The trainer *DVs* table: a fifth trainer table, indexed the same way as the
## attributes table, one fixed two-byte entry per class rather than a pointer.
## Two nibbles a byte, attack and defense in the first, speed and special in the
## second: exactly the shape [method Gen2Stats.pack_dvs] packs into, so a class's
## two raw bytes read big-endian are a [Gen2BattleMon] DV word unchanged.
## Confirmed against `TrainerClassDVs` entry by entry in all three games, with
## Falkner opening the table and the closing class (66 in Gold and Silver, 67 in
## Crystal, which alone carries MYSTICALMAN) carrying its own.
const TRAINER_DVS_SIZE: int = 2

## The one trainer class with no party: Professor Elm's class, whose name and pic
## exist but who is never sent into battle. Its source label is followed
## immediately by the next class's, so its pointer equals that one, and the
## honest reading is zero trainers rather than a copy. Confirmed against pret's
## party data (`PokemonProfGroup` has no entries before `WillGroup`), same class
## number in every game.
const EMPTY_TRAINER_CLASS: int = 10

## Back pics are always this square. Front pics vary and carry their own size in
## the base stats.
const BACKPIC_TILES: int = 6
## The battle screen's frontpic window, and so the atlas cell size.
const FRONTPIC_MAX_TILES: int = 7

## Byte positions within a 32-byte base stats entry.
const STAT_HP: int = 1
const STAT_ATTACK: int = 2
const STAT_DEFENSE: int = 3
const STAT_SPEED: int = 4
const STAT_SP_ATTACK: int = 5
const STAT_SP_DEFENSE: int = 6
const OFFSET_TYPE1: int = 7
const OFFSET_TYPE2: int = 8
const OFFSET_CATCH_RATE: int = 9
const OFFSET_BASE_EXP: int = 10
const OFFSET_ITEM1: int = 11
const OFFSET_ITEM2: int = 12
const OFFSET_GENDER_RATIO: int = 13
const OFFSET_HATCH_CYCLES: int = 15
## Packed nibbles: width in the low half, height in the high half, in tiles.
const OFFSET_PIC_SIZE: int = 17
const OFFSET_GROWTH_RATE: int = 22
## Packed nibbles, one egg group per half.
const OFFSET_EGG_GROUPS: int = 23
const OFFSET_TMHM: int = 24
## Eight bytes of learnable flags, one bit per TM/HM/tutor number, indexed by the
## entry's own zero-based place in TMHMMoves. Sixty-four bits for sixty numbers,
## so the top four are always clear.
const TMHM_BYTES: int = 8

## data/moves/tmhm_moves.asm's TMHMMoves: fifty TMs, then seven HMs, then
## Crystal's three move tutors, then a zero terminator. Indexed by TMNUM, which
## is one-based, so entry n-1 is TM/HM number n. The first fifty-seven bytes are
## identical between the pins; only Crystal's tutor rows follow.
const TMHM_TM_COUNT: int = 50
const TMHM_HM_COUNT: int = 7
## data/text/name_input_chars.asm's four keyboards, one contiguous block in
## source order with every row 17 bytes wide. The block is byte identical in all
## three dumps, so only its offset is profile split.
const NAME_INPUT_ROW_BYTES: int = 17
## Rows per table, in block order: NameInputLower, BoxNameInputLower,
## NameInputUpper, BoxNameInputUpper. A name keyboard is 5 rows and a box
## keyboard 6, which is the whole of NamingScreen_IsTargetBox's `ld b, $5` /
## `ld b, $6` split.
const NAME_INPUT_TABLE_ROWS: Array[int] = [5, 6, 5, 6]
const NAME_INPUT_BLOCK_BYTES: int = 374
## NamingScreen_GetLastCharacter reads the keyboard by cursor column, and the
## cursor steps two tiles at a time, so a column is every second byte of a row.
const NAME_INPUT_COLUMNS: int = 9
const NAME_INPUT_COLUMN_STRIDE: int = 2
## The letter each keyboard's first row opens with, which is what pins the block.
const NAME_INPUT_LOWER_A: int = 0xA0
const NAME_INPUT_UPPER_A: int = 0x80
## The last row of every table: the case switch, DEL and END, encoded.
const NAME_INPUT_COMMAND_LOWER: Array[int] = [
	0x94, 0x8F, 0x8F, 0x84, 0x91, 0x7F, 0x7F, 0x83, 0x84,
	0x8B, 0x7F, 0x7F, 0x7F, 0x84, 0x8D, 0x83, 0x7F,
]
const NAME_INPUT_COMMAND_UPPER: Array[int] = [
	0xAB, 0xAE, 0xB6, 0xA4, 0xB1, 0x7F, 0x7F, 0x83, 0x84,
	0x8B, 0x7F, 0x7F, 0x7F, 0x84, 0x8D, 0x83, 0x7F,
]

## constants/item_constants.asm. TM01 is $bf and HM01 $f3, but the run is not
## contiguous: ITEM_C3 and ITEM_DC are dummy items inside it, which is why
## GetTMHMNumber skips them rather than subtracting.
const ITEM_TM01: int = 0xBF
const ITEM_HM01: int = 0xF3
const ITEM_DUMMY_TM04_05: int = 0xC3
const ITEM_DUMMY_TM28_29: int = 0xDC


## engine/items/items.asm's GetTMHMNumber: the one-based TM/HM number an item id
## carries, or 0 when [param item] is not one. The two dummy items in the range
## have no number of their own and answer 0 as well.
static func tmhm_number_for_item(item: int, count: int) -> int:
	if item < ITEM_TM01 or item == ITEM_DUMMY_TM04_05 or item == ITEM_DUMMY_TM28_29:
		return 0
	var value: int = item
	if value >= ITEM_DUMMY_TM04_05:
		if value >= ITEM_DUMMY_TM28_29:
			value -= 1
		value -= 1
	var number: int = value - ITEM_TM01 + 1
	return number if number >= 1 and number <= count else 0


## GetNumberedTMHM, the inverse: the item id a one-based TM/HM number carries.
static func item_for_tmhm_number(number: int, count: int) -> int:
	if number < 1 or number > count:
		return 0
	var value: int = number
	if value >= ITEM_DUMMY_TM04_05 - (ITEM_TM01 - 1):
		if value >= ITEM_DUMMY_TM28_29 - (ITEM_TM01 - 1) - 1:
			value += 1
		value += 1
	return value + ITEM_TM01 - 1

## Byte positions within a 7-byte move entry.
## The animation is the move's own number, which is what makes the table
## self-checking in the same way the base stats are.
const MOVE_ANIMATION: int = 0
const MOVE_EFFECT: int = 1
const MOVE_POWER: int = 2
const MOVE_TYPE: int = 3
const MOVE_ACCURACY: int = 4
const MOVE_PP: int = 5
const MOVE_EFFECT_CHANCE: int = 6

## Gold and Silver share the world and battle layout, while a few variable-size
## data sections move because their content differs.
const GOLD_SILVER: Dictionary = {
	"species_names": 0x1B0B74,
	"base_stats": 0x51B0B,
	"pic_pointers": 0x48000,
	"unown_pic_pointers": 0x7C000,
	"palettes": 0xAD3D,
	"move_names": 0x1B1574,
	"item_names": 0x1B0000,
	"item_attributes": 0x68A0,
	"item_status_actions": 0xF0C7,
	"item_healing_hp": 0xF405,
	"world_trades": 0xFCC24,
	"world_trade_count": 6,
	"move_data": 0x41AFE,
	"tmhm_moves": 0x11A66,
	"tmhm_move_count": 57,
	"name_input_chars": 0x120B4,
	"string_buffer_pointers": 0x24000,
	## `data/text/common_2.asm`'s intro texts, each at its own `text_far` target.
	## Nested the way the trainer card is, so the -1 for what Gold and Silver do
	## not ship stays out of the flat offset checks. `_OakText3` is a bare
	## `text_promptbutton` and carries no words, so it has no offset here.
	# `engine/menus/start_menu.asm`'s description run and `data/text/common_2.asm`'s
	# five pack texts, all located by encoding what the source says they read and
	# matching the bytes. Each hits once per dump except the two refusals, which
	# the cartridge also keeps a copy of elsewhere; the common_2 copy is the one
	# beside the toss texts, which is what the offsets below are.
	"menu_text": {
		"descriptions": 0x12B15,
		"oak_no_time": 0x1945B2,
		"no_mon": 0x1945DB,
		"toss_ask": 0x194569,
		"toss_ask_quantity": 0x19457F,
		"toss_threw": 0x19459C,
	},
	"intro_text": {
		"oak_1": 0x195624,
		"oak_2": 0x195693,
		"oak_4": 0x1956D3,
		"oak_5": 0x19573F,
		"oak_6": 0x1957B7,
		"oak_7": 0x1957DD,
		## `engine/menus/init_gender.asm` is Crystal only, and so is its text.
		"gender": -1,
	},
	"evos_attacks": 0x427BD,
	"type_names": 0x509AE,
	"type_matchups": 0x34D01,
	"font": 0xF82F2,
	"frames": 0xF88F2,
	"bar_palettes": 0xAD2D,
	"battle_font": 0xF86F2,
	"enemy_hud": 0xF8BB2,
	"player_hud": 0xF8BD2,
	"exp_bar": 0xF8C02,
	# Trainer card. Located by converting the pinned gfx/trainer_card PNGs and
	# matching the bytes in the cartridge; the run is contiguous and
	# self-consistent, status running straight into the two leader copies and
	# then the two badge copies. Nested, the way wild_encounters is, so the -1
	# for what a profile does not ship stays out of the flat offset checks.
	"trainer_card": {
		# Gold and Silver ship no Kris pic and no right corner, and store the
		# card pic row-major rather than in columns.
		"pic_male": 0x2547F,
		"pic_female": -1,
		"pic_columns": false,
		"frame": 0x256AF,
		"status": 0x2570F,
		"leaders": 0x2576F,
		"badges": 0x2622F,
		"right_corner": -1,
		"badge_palette": 0xA385,
	},
	# The region map. `johto`, `kanto`, `palette_map` and `palette` were located
	# by assembling the pinned gfx/pokegear files and matching the bytes; the
	# three graphics by decompressing at every offset and keeping the run that
	# reproduces the pinned PNG exactly. Every hit is unique per dump. The
	# landmark table was located by its own x,y byte pairs at a stride of four,
	# which no other run in the cartridge matches. Nested the way trainer_card
	# is, so Gold and Silver's absent female palette stays out of the flat offset
	# checks.
	"town_map": {
		"gfx": 0xF8C92,
		"pokegear_gfx": 0x1C0E43,
		"sprites": 0x9149C,
		"fast_ship": 0x90C7C,
		"johto": 0x91F52,
		"kanto": 0x920BB,
		"palette_map": 0x91EAC,
		"palette": 0xBB6E,
		# `PokegearPals` is one run: no Kris, so no second city palette.
		"palette_female": -1,
		"landmarks": 0x92382,
		"landmark_count": LANDMARK_COUNT_GOLD_SILVER,
	},
	# `OakRatings`, located by its own nineteen ascending thresholds at a stride
	# of five, which hit once per dump. Everything else Prof Oak's PC says is
	# reached through the table's own text pointers.
	"oak_ratings": 0x2685B,
	# `PokemonCenterPC`'s own strings. The five row names are one run, and the
	# routine's six `text_far` stubs sit `POKECENTER_PC_TEXT_AT` past its start;
	# both were located by matching the row run's own bytes, which are unique in
	# a dump.
	"pokecenter_pc": 0x158D1,
	# The credits. `gfx` was located by converting the pinned gfx/credits PNGs
	# and matching the bytes: the border and the four mon sheets are one
	# contiguous run in `credits.asm`'s own INCBIN order and `CreditsScript`
	# follows it, so the run's length pins the script and the script's own
	# terminator pins `CreditsStringsPointers`. `palettes` is
	# gfx/credits/credits.pal assembled and matched, and `the_end` the same for
	# gfx/credits/theend.png. Each hits once per dump. Nested the way
	# trainer_card is.
	"credits": {
		"palettes": 0x86C1C,
		"gfx": 0x86CA6,
		"the_end": 0xCBCBD,
		"script": 0x87A36,
		"strings": 0x87B65,
		# `PlaceFarString`, so the strings are not in the table's own bank.
		"strings_bank": 0x70,
		# NUM_CREDITS_STRINGS, STAFF and COPYRIGHT
		# (constants/credits_constants.asm). All three are checked against the
		# script and the copyright screen rather than trusted.
		"string_count": 76,
		"staff": 51,
		"copyright": 71,
		# `GetCreditsPalette.UpdatePals` copies eight bytes twice into the same
		# two slots, so a scene is one palette rather than Crystal's three.
		"scene_palettes": 1,
		# `Credits_LoadBorderGFX.Frames`, as 16-tile blocks into the mon run.
		# The first three scenes ship three frames each and repeat the first.
		"frames": [0, 1, 0, 2, 3, 4, 3, 5, 6, 7, 6, 8, 9, 10, 11, 12],
	},
	# The copyright screen (`Copyright`, engine/menus/intro_menu.asm). The
	# graphic was located by encoding the pinned gfx/splash/copyright.png as
	# 2bpp and matching it, which hits once per dump; the string by assembling
	# data/copyright.asm's own code run, which hits twice because that file is
	# INCLUDEd for the credits as well, and the lower address is bank 1's, the
	# one `Copyright` reads. Nested the way trainer_card is.
	"copyright": {"gfx": 0xE4000, "tiles": 30, "string": 0x6513, "palette": 0xA4D5},
	# `GameFreakPresents`. `GameFreakLogoGFX` and `GameFreakLogoStarsGFX` were
	# located by encoding the four pinned gfx/splash PNGs as cartridge tiles and
	# matching them; each hits once per dump and the four runs are contiguous in
	# the order splash.asm INCBINs them. `object_palette` is
	# PREDEFPAL_GAMEFREAK_LOGO_OB, the entry in front of the copyright screen's
	# own. Nested the way trainer_card is, so Crystal's Ditto staying -1 here
	# stays out of the flat offset checks.
	"game_freak_presents": {
		"gfx": 0xE4B81,
		"stars": 0xE4C61,
		"ditto": -1,
		"ditto_palette": -1,
		"ditto_fade": -1,
		"object_palette": 0xA4CD,
	},
	# `TitleScreen`. Gold's numbers; Silver's three differences are patched in
	# `for_id`. `GSTitleOBPals` also appears in Crystal, which keeps the unused
	# Gold and Silver title screen's copy at a different address; that is a
	# leftover rather than a second candidate for this one. Nested the way
	# trainer_card is, so Crystal's -1s stay out of the flat offset checks.
	"title": {
		"logo_bottom": 0x98000,
		"logo_top": 0x98476,
		"tilemap": 0x98616,
		"trail": 0xE41E0,
		"trail_tiles": 8,
		"bird": 0xE4260,
		"bird_tiles": 88,
		"bg_palette": 0xBB36,
		"ob_palette": 0xBB5E,
		"suicune": -1,
		"logo": -1,
		"crystal": -1,
		"palettes": -1,
	},
	# `CrystalIntro` is Crystal's; Gold and Silver run `GoldSilverIntro` below.
	"intro_movie": {"section": -1, "fade": -1, "unown_pals": -1},
	# `GoldSilverIntro`'s art section. `Intro_WaterGFX1` is the only pinned
	# address in it: the section is contiguous and sixteen-byte aligned, so the
	# walk in `GS_INTRO_SECTION` reaches the other ten, and all eleven reproduce
	# pret's own build byte for byte. `magikarp_palettes` and
	# `shellder_lapras_palettes` are INCLUDEd inside the code rather than in that
	# section; each is a unique byte run whose object half sits directly behind
	# it. `predef_pals` is `PredefPals` itself, checked against the
	# `game_freak_presents.object_palette` this layout already pins.
	"gs_intro": {
		"section": 0xE54E8,
		"magikarp_palettes": 0x9126,
		"shellder_lapras_palettes": 0x96E1,
		"predef_pals": 0xA265,
	},
	"intro_player": {"pic_male": -1, "pic_female": -1},
	"gender_screen": {"tile": -1, "palette": -1},
	# `ShrinkPlayer`'s two intermediate pictures. Located from the routine's own
	# `ld hl` / `ld b` operand pairs, which is the only place either address
	# appears: the compressed bytes cannot be searched for the way a PNG can.
	"shrink_pics": {"first": 0xFB5BE, "second": 0xFB64E},
	## pokegold ships no `gfx/font/bg_text.pal`; its text boxes are coloured by
	## the SGB/CGB layout that drew the screen, not by a palette of their own.
	## Nested the way trainer_card is, so the -1 stays out of the flat offset
	## checks.
	"text_bg_palette": {"offset": -1},
	# Pokedex. Located by encoding Bulbasaur's known category and published
	# height and weight ("SEED", 204, 150) and matching the bytes, then finding
	# the only 251-pointer run whose four 64-species groups each ascend and
	# restart. Both order tables were located by encoding the pinned
	# data/pokemon/dex_order_*.asm species lists whole. Nested for the same
	# reason trainer_card is.
	"pokedex": {
		"entry_pointers": 0x44360,
		# BANK("Pokedex Entries 001-064") through 193-251.
		"entry_banks": [0x68, 0x69, 0x6A, 0x6B],
		"order_alpha": 0x40C65,
		"order_new": 0x40D60,
	},
	# Battle animations. `BattleAnimations` was located by matching
	# `BattleAnim_Pound` whole (d1 01 e0 01 31 d0 08 88 38 00 06 d0 01 88 38 00
	# 10 ff), then finding the run of 278 in-bank pointers whose second entry is
	# its address; the other four tables were located by assembling the pinned
	# data/battle_anims files and matching the bytes. Each hit is unique in the
	# dump. `sine` is the one that is not: the same 64 bytes appear four or five
	# times per dump, so it was located from `calc_sine_wave`'s own operand, the
	# `ld hl` at the end of the copy sharing this bank with the four tables, and
	# only that hit lies in the bank. Nested for the same reason trainer_card is.
	"battle_anims": {
		"scripts": 0xC900A,
		"objects": 0xCCAA5,
		"sine": 0xCE6C4,
		"framesets": 0xCE7A3,
		"oam_sets": 0xCEDF3,
		"object_gfx": 0xCFC3B,
	},
	# BattleObjectPals (engine/gfx/color.asm). Located by matching the pinned
	# gfx/battle_anims/battle_anims.pal whole; the hit is unique, and the
	# identically sized unused table beside it does not match.
	"battle_object_palettes": 0x9C09,
	"trainer_pic_pointers": 0x80000,
	"trainer_palettes": 0xB53D,
	"trainer_class_names": 0x1B0955,
	"trainer_classes": 66,
	"trainer_last_class": "ROCKET",
	"trainer_parties": 0x3993E,
	"trainer_party_total": 495,
	"trainer_party_last_trainer": "GRUNT",
	"trainer_attributes": 0x39562,
	"trainer_dvs": 0x27283,
	"trainer_dvs_last": 0x7EA8, # GRUNTF, class 66, "ROCKET" in-game: atk 7, def 14, spd 10, spc 8.
	"map_group_pointers": 0x940ED,
	"map_group_counts": [14, 7, 82, 9, 10, 8, 17, 7, 6, 17, 22, 13, 6, 8, 12, 8, 13, 14, 4, 4, 26, 9, 13, 13, 15, 11],
	"tilesets": 0x156BE,
	"tileset_block_counts": [128, 128, 128, 128, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64],
	"tileset_palette_bank": 0x02,
	"world_palette_offset": 0xB75E,
	"overworld_sprites": 0x147DE,
	"overworld_sprite_count": 95,
	"overworld_sprite_palettes": 0xB8AE,
	"overworld_icons": 0x8EABE,
	"mart_table": 0x162FE,
	"default_mart": 0x16469,
	"bargain_mart": 0x15EDA,
	"fruit_trees": 0x44091,
	"rooftop_mart_count": 0,
	"rooftop_mart_1": 0,
	"rooftop_mart_2": 0,
	"phone_contacts": 0x9043A,
	"phone_non_trainer_names": 0x903CD,
	"phone_non_trainer_names_bank": 0x24,
	"phone_non_trainer_name_count": 5,
	"special_phone_calls": 0x905F6,
	"phone_out_of_area_bank": 0x24,
	"phone_out_of_area_address": 0x4626,
	"phone_just_talk_bank": 0x24,
	"phone_just_talk_address": 0x462F,
	# SpecialCallOnlyWhenOutside and SpecialCallWhereverYouAre in engine/phone/phone.asm.
	"phone_condition_outside": 0x4190,
	"phone_condition_anywhere": 0x419F,
	"music_pointers": 0xE906E,
	"music_count": 93,
	"music_first_bank": 0x3A,
	"music_first_address": 0x5185,
	"sfx_pointers": 0xE925E,
	"sfx_count": 188,
	"sfx_first_bank": 0x3C,
	"sfx_first_address": 0x4B3F,
	"cry_pointers": 0xE9192,
	"cry_first_bank": 0x3C,
	"cry_first_address": 0x743D,
	"mon_cries": 0xF2747,
	"wave_samples": 0xE8DB2,
	"wave_samples_bank": 0x3A,
	"wave_samples_address": 0x4DB2,
	"drumkits": 0xE8E52,
	"drumkits_bank": 0x3A,
	"drumkits_address": 0x4E52,
	"world_animation_done": 0x42A2,
	"world_animation_functions": {
		0x42A2: "done", 0x42A5: "wait", 0x42A6: "timer_8", 0x42B0: "scroll_horizontal",
		0x4311: "scroll_vertical", 0x432E: "water", 0x4388: "flower",
		0x43E7: "lava_1", 0x4406: "lava_2", 0x4460: "tower",
		0x448E: "timer", 0x4493: "whirlpool", 0x44B1: "write_buffer",
		0x44BD: "read_buffer", 0x44F2: "water_palette", 0x452D: "cave_palette",
	},
	"world_animation_assets": {
		"water": {"offset": 0xFC348, "bytes": 64},
		"flower": {"offset": 0xFC3A7, "bytes": 64},
		"lava": {"offset": 0xFC420, "bytes": 64},
		"tower": {"offset": 0xFC57D, "bytes": 800},
		"whirlpool": {"offset": 0xFC8AD, "bytes": 256},
	},
	"wild_encounters": {
		"grass_johto": 0x2AB35,
		"water_johto": 0x2B669,
		"grass_kanto": 0x2B7C0,
		"water_kanto": 0x2BD43,
		"grass_johto_count": 61,
		"water_johto_count": 38,
		"grass_kanto_count": 30,
		"water_kanto_count": 24,
		"swarm_grass": 0x2BE1C,
		"swarm_grass_count": 4,
		"swarm_water": 0x2BED9,
		"swarm_water_count": 1,
		"fish_groups": 0x929F7,
		"fish_group_count": 13,
		"roam_maps": 0x2A95B,
		"roam_map_count": 16,
		"roaming": [
			{"species": 0xF3, "level": 40, "map_group": 2, "map_number": 5},
			{"species": 0xF4, "level": 40, "map_group": 10, "map_number": 4},
			{"species": 0xF5, "level": 40, "map_group": 1, "map_number": 12},
		],
		"tree_maps": 0xBA3E6,
		"tree_map_count": 34,
		"rock_maps": 0xBA44D,
		"rock_map_count": 4,
		"treemon_sets": 0xBA470,
		"treemon_set_count": 6,
		"asleep_treemons": {},
	},
	# Gold and Silver patch three bank numbers and pass the rest through. The
	# stored value is what the linker assigned before three pic sections were
	# moved; see FixPicBank in pokegold.
	"pic_bank_add": 0,
	"pic_bank_patch": {0x13: 0x1F, 0x14: 0x20, 0x1F: 0x2E},
}

const CRYSTAL: Dictionary = {
	"species_names": 0x53384,
	"base_stats": 0x51424,
	"pic_pointers": 0x120000,
	"unown_pic_pointers": 0x124000,
	"palettes": 0xA8CE,
	"move_names": 0x1C9F29,
	"item_names": 0x1C8000,
	"item_attributes": 0x67C1,
	"item_status_actions": 0xF071,
	"item_healing_hp": 0xF3AF,
	"world_trades": 0xFCE58,
	"world_trade_count": 7,
	"move_data": 0x41AFB,
	"tmhm_moves": 0x1167A,
	"tmhm_move_count": 60,
	"name_input_chars": 0x11CE7,
	"string_buffer_pointers": 0x24000,
	## See the Gold and Silver block above. Crystal moves `_OakText6` and
	## `_OakText7` out of the run the other four sit in, so the six are located
	## one by one rather than walked.
	# See the Gold and Silver block above for how these were located.
	"menu_text": {
		"descriptions": 0x1274E,
		"oak_no_time": 0x1C0BEE,
		"no_mon": 0x1C0C17,
		"toss_ask": 0x1C0BA5,
		"toss_ask_quantity": 0x1C0BBB,
		"toss_threw": 0x1C0BD8,
	},
	"intro_text": {
		"oak_1": 0x1C1D35,
		"oak_2": 0x1C1DA4,
		"oak_4": 0x1C1DE5,
		"oak_5": 0x1C1E51,
		"oak_6": 0x1C4000,
		"oak_7": 0x1C4026,
		"gender": 0x1C0CA3,
	},
	"evos_attacks": 0x425B1,
	"type_names": 0x5097B,
	"type_matchups": 0x34BB1,
	"font": 0xF8200,
	"frames": 0xF8800,
	"bar_palettes": 0xA8BE,
	"battle_font": 0xF8600,
	"enemy_hud": 0xF8AC0,
	"player_hud": 0xF8AE0,
	"exp_bar": 0xF8B10,
	# Trainer card; see the Gold and Silver block above for how these were
	# located. Crystal splits the card pic in two by gender and stores both
	# column-major, and adds the one-tile right corner Gold and Silver lack.
	"trainer_card": {
		"pic_male": 0x88365,
		"pic_female": 0x88595,
		"pic_columns": true,
		"frame": 0x887C5,
		"status": 0x25523,
		"leaders": 0x25583,
		"badges": 0x26043,
		"right_corner": 0x265C3,
		"badge_palette": 0x9F16,
	},
	# The region map; see the Gold and Silver block above for how these were
	# located. Every asset is byte identical across the three dumps, so only the
	# addresses differ. Crystal adds Kris's own city palette and the ninety-sixth
	# landmark, `BATTLE TOWER`.
	"town_map": {
		"gfx": 0xF8BA0,
		"pokegear_gfx": 0x1DE2E4,
		"sprites": 0x914DD,
		"fast_ship": 0x90CB2,
		"johto": 0x91FFF,
		"kanto": 0x92168,
		"palette_map": 0x91F4B,
		"palette": 0xB729,
		"palette_female": 0xB759,
		"landmarks": 0x1CA8C3,
		"landmark_count": LANDMARK_COUNT,
	},
	# See the Gold and Silver block above; the table is byte identical and only
	# its address moves.
	"oak_ratings": 0x2667F,
	# See the Gold and Silver block above; the run is byte identical and only its
	# address moves.
	"pokecenter_pc": 0x155FA,
	# See the Gold and Silver block above for how these were located. Crystal's
	# strings sit in the pointer table's own bank, since it prints them with
	# `PlaceString` rather than `PlaceFarString`, and each of its four scenes is
	# three palettes rather than one.
	"credits": {
		"palettes": 0x109B6A,
		"gfx": 0x109C24,
		"the_end": 0xCBD2E,
		"script": 0x10ACB4,
		"strings": 0x10AE13,
		"strings_bank": 0x42,
		"string_count": 103,
		"staff": 72,
		"copyright": 98,
		"scene_palettes": 3,
		"frames": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
	},
	# See the Gold and Silver block above for how this was located.
	"copyright": {"gfx": 0xE4000, "tiles": 29, "string": 0x63FD, "palette": 0xA066},
	# See the Gold and Silver block above for how these were located. Crystal
	# ships no star or sparkle: its beat is the Ditto, whose compressed run
	# cannot be searched for as bytes and was instead found by decompressing at
	# every offset in the dump and keeping the one that produced the pinned
	# gfx/splash/ditto.png exactly. Both of its palettes are unique eight- and
	# thirty-two-byte runs, and `ditto_fade` sits directly in front of the
	# graphic, which is where splash.asm puts it.
	"game_freak_presents": {
		"gfx": 0xE47CC,
		"stars": -1,
		"ditto": 0x109407,
		"ditto_palette": 0x9521,
		"ditto_fade": 0xE47AC,
		"object_palette": 0xA05E,
	},
	# `_TitleScreen`. A different screen from Gold and Silver's, so the two
	# halves of this entry have nothing in common but the key: the three LZ runs
	# and the sixteen palettes sit contiguous in `engine/movie/title.asm`'s own
	# INCBIN order, ending on the palettes.
	"title": {
		"suicune": 0x10EF46,
		"logo": 0x10F326,
		"crystal": 0x10FCEE,
		"palettes": 0x10FEDE,
		"logo_bottom": -1,
		"logo_top": -1,
		"tilemap": -1,
		"trail": -1,
		"trail_tiles": 0,
		"bird": -1,
		"bird_tiles": 0,
		"bg_palette": -1,
		"ob_palette": -1,
	},
	# `CrystalIntro`'s art section. `IntroSuicuneRunGFX` is the only pinned
	# address: the section is contiguous and sixteen-byte aligned, so the walk in
	# `INTRO_SECTION` reaches the other thirty-four. Found by decompressing at
	# every offset in the dump and keeping the one that produced the pinned
	# gfx/intro/suicune_run.png exactly. `fade` and `unown_pals` are INCLUDEd
	# inside the code rather than in that section; both are unique byte runs, and
	# `unown_1.pal` pins `unown_2.pal` directly behind it.
	"intro_movie": {"section": 0xE555D, "fade": 0xE519C, "unown_pals": 0xE538D},
	# Crystal ships no `GoldSilverIntro`. Nested the way trainer_card is, so the
	# -1s stay out of the flat offset checks.
	"gs_intro": {
		"section": -1,
		"magikarp_palettes": -1,
		"shellder_lapras_palettes": -1,
		"predef_pals": -1,
	},
	# `engine/gfx/player_gfx.asm`: ChrisPic and KrisPic. Located by converting
	# the pinned 56x56 PNGs with rgbgfx --columns and matching the full runs.
	"intro_player": {"pic_male": 0x888A9, "pic_female": 0x88BB9},
	# `engine/menus/init_gender.asm`: LoadGenderScreenPal's inline `.Palette`
	# (gfx/new_game/gender_screen.pal) and LoadGenderScreenLightBlueTile's
	# `.LightBlueTile`. The palette's eight bytes are unique in the dump; the
	# tile, sixteen bytes of one repeated index, is not, so it is taken from the
	# `ld de` operand thirteen bytes past the palette. Crystal only.
	"gender_screen": {"tile": 0x48E71, "palette": 0x48E5C},
	# See the Gold and Silver block above for how these were located.
	"shrink_pics": {"first": 0x4D249, "second": 0x4D2D9},
	# `gfx/font/bg_text.pal`, BG palette 7. Located from `LoadOW_BGPal7`'s own
	# `ld hl` operand, whose `ld de` is wBGPals1 + PAL_BG_TEXT; the eight bytes
	# are unique in the dump as well.
	"text_bg_palette": {"offset": 0x49418},
	# Pokedex; see the Gold and Silver block above for how these were located.
	# Both order tables sit at the same offsets in all three dumps; the entries
	# and their banks do not, and Gold and Silver do not even share description
	# text with each other, so every profile is read from its own cartridge.
	"pokedex": {
		"entry_pointers": 0x44378,
		"entry_banks": [0x60, 0x6E, 0x73, 0x74],
		"order_alpha": 0x40C65,
		"order_new": 0x40D60,
	},
	# Battle animations; see the Gold and Silver block above for how these were
	# located. All five tables sit in the same two banks in every dump and only
	# the addresses within them move.
	"battle_anims": {
		"scripts": 0xC906F,
		"objects": 0xCCB56,
		"sine": 0xCE77F,
		"framesets": 0xCE85E,
		"oam_sets": 0xCEEAE,
		"object_gfx": 0xCFCF6,
	},
	"battle_object_palettes": 0x979C,
	"trainer_pic_pointers": 0x128000,
	"trainer_palettes": 0xB0CE,
	"trainer_class_names": 0x2C1EF,
	"trainer_classes": 67,
	"trainer_last_class": "MYSTICALMAN",
	"trainer_parties": 0x39999,
	"trainer_party_total": 541,
	"trainer_party_last_trainer": "EUSINE",
	"trainer_attributes": 0x3959C,
	"trainer_dvs": 0x270D6,
	"trainer_dvs_last": 0x9888, # MYSTICALMAN, class 67: atk 9, def 8, spd 8, spc 8.
	"map_group_pointers": 0x94000,
	"map_group_counts": [14, 7, 91, 9, 10, 8, 17, 7, 6, 17, 24, 13, 6, 8, 12, 8, 13, 14, 4, 6, 26, 16, 13, 13, 15, 11],
	"tilesets": 0x4D596,
	"tileset_block_counts": [128, 128, 128, 128, 128, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 40, 64, 64, 64, 64, 64],
	"tileset_palette_bank": 0x13,
	"world_palette_offset": 0xB319,
	"overworld_sprites": 0x14736,
	## NUM_OVERWORLD_SPRITES (constants/sprite_constants.asm), which is the last
	## constant's own value: SPRITE_STANDING_YOUNGSTER is $66. Crystal's four rows
	## past pokegold's SPRITE_SILVER_TROPHY are Kris, Kris on a bike, Kurt
	## outside, the three beasts and the standing youngster. Reading 99 stopped at
	## SPRITE_SUICUNE and left thirteen map objects with no sprite, which is also
	## no collision: see Gen2WorldAPI.object_at().
	"overworld_sprite_count": 102,
	"overworld_sprite_palettes": 0xB469,
	"overworld_icons": 0x8EC0D,
	"mart_table": 0x160A9,
	"default_mart": 0x16214,
	"bargain_mart": 0x15C51,
	"fruit_trees": 0x44097,
	"rooftop_mart_count": 2,
	"rooftop_mart_1": 0x15AEE,
	"rooftop_mart_2": 0x15AFF,
	"phone_contacts": 0x9045F,
	"phone_non_trainer_names": 0x903D6,
	"phone_non_trainer_names_bank": 0x24,
	"phone_non_trainer_name_count": 6,
	"special_phone_calls": 0x90627,
	"phone_out_of_area_bank": 0x24,
	"phone_out_of_area_address": 0x4657,
	"phone_just_talk_bank": 0x24,
	"phone_just_talk_address": 0x4660,
	# Crystal's relocated special-call condition routines.
	"phone_condition_outside": 0x4188,
	"phone_condition_anywhere": 0x4197,
	"music_pointers": 0xE906E,
	"music_count": 103,
	"music_first_bank": 0x3A,
	"music_first_address": 0x51A3,
	"sfx_pointers": 0xE927C,
	"sfx_count": 207,
	"sfx_first_bank": 0x3C,
	"sfx_first_address": 0x4B3F,
	"cry_pointers": 0xE91B0,
	"cry_first_bank": 0x3C,
	"cry_first_address": 0x747D,
	"mon_cries": 0xF2787,
	"wave_samples": 0xE8DB2,
	"wave_samples_bank": 0x3A,
	"wave_samples_address": 0x4DB2,
	"drumkits": 0xE8E52,
	"drumkits_bank": 0x3A,
	"drumkits_address": 0x4E52,
	"world_animation_done": 0x42FB,
	"world_animation_functions": {
		0x42FB: "done", 0x42FE: "wait", 0x42FF: "timer_8", 0x4309: "scroll_horizontal",
		0x436A: "scroll_vertical", 0x4387: "fountain", 0x4402: "water",
		0x445C: "forest_left", 0x44C4: "forest_right", 0x44F2: "forest_left_2",
		0x451C: "forest_right_2", 0x456D: "flower", 0x45CC: "lava_1",
		0x45EB: "lava_2", 0x4645: "tower", 0x4673: "timer", 0x4678: "whirlpool",
		0x4696: "write_buffer", 0x46A2: "read_buffer", 0x46D7: "water_palette",
		0x471E: "cave_palette",
	},
	"world_animation_assets": {
		"water": {"offset": 0xFC41C, "bytes": 64},
		"flower": {"offset": 0xFC58C, "bytes": 64},
		"fountain": {"offset": 0xFC3B2, "bytes": 80},
		"forest": {"offset": 0xFC484, "bytes": 64},
		"lava": {"offset": 0xFC605, "bytes": 64},
		"tower": {"offset": 0xFC778, "bytes": 800},
		"whirlpool": {"offset": 0xFCAA8, "bytes": 256},
	},
	"wild_encounters": {
		"grass_johto": 0x2A5E9,
		"water_johto": 0x2B11D,
		"grass_kanto": 0x2B274,
		"water_kanto": 0x2B7F7,
		"grass_johto_count": 61,
		"water_johto_count": 38,
		"grass_kanto_count": 30,
		"water_kanto_count": 24,
		"swarm_grass": 0x2B8D0,
		"swarm_grass_count": 2,
		"swarm_water": -1,
		"swarm_water_count": 0,
		"fish_groups": 0x92488,
		"fish_group_count": 13,
		"roam_maps": 0x2A40F,
		"roam_map_count": 16,
		"roaming": [
			{"species": 0xF3, "level": 40, "map_group": 2, "map_number": 5},
			{"species": 0xF4, "level": 40, "map_group": 10, "map_number": 4},
		],
		"tree_maps": 0xB825E,
		"tree_map_count": 34,
		"rock_maps": 0xB82C5,
		"rock_map_count": 4,
		"treemon_sets": 0xB82E8,
		"treemon_set_count": 9,
		# CheckSleepingTreeMon and data/wild/treemons_asleep.asm are Crystal
		# only; pokegold ships neither. File order is Nite, Day, Morn.
		"asleep_treemons": {"nite": 0x3EB5D, "day": 0x3EB69, "morn": 0x3EB6F},
	},
	# Crystal's equivalent table is a contiguous $48-$5F, so the whole remap
	# collapses to a constant: PICS_FIX in pokecrystal.
	"pic_bank_add": 0x36,
	"pic_bank_patch": {},
}


## The layout for a game id, or an empty Dictionary if it is not characterised.
static func for_id(id: StringName) -> Dictionary:
	match id:
		RomRegistry.GOLD:
			return GOLD_SILVER
		RomRegistry.SILVER:
			var silver: Dictionary = GOLD_SILVER.duplicate(true)
			# Gold and Silver share the icon format but their banks differ by ten
			# bytes at this table.
			silver["overworld_icons"] = 0x8EAA4
			silver["item_attributes"] = 0x6866
			silver["item_status_actions"] = 0xF0C5
			silver["item_healing_hp"] = 0xF403
			# `CopyrightString` sits in bank 1 on both, sixty bytes apart.
			var copyright: Dictionary = (silver["copyright"] as Dictionary).duplicate()
			copyright["string"] = 0x64D9
			silver["copyright"] = copyright
			# The splash graphics sit in the same bank on both, 440 bytes apart.
			var presents: Dictionary = (
				silver["game_freak_presents"] as Dictionary
			).duplicate()
			presents["gfx"] = 0xE49C9
			presents["stars"] = 0xE4AA9
			silver["game_freak_presents"] = presents
			# `GoldSilverIntro`'s art sits in the same bank on both, the same 440
			# bytes apart as the splash graphics. Every other address the movie
			# reads is identical on the two cartridges, and so is the art itself.
			var gs_intro: Dictionary = (silver["gs_intro"] as Dictionary).duplicate()
			gs_intro["section"] = 0xE5330
			silver["gs_intro"] = gs_intro
			# Silver's logo bottom sits at Gold's address and its top 34 bytes
			# later. Its trail is four tiles rather than eight, which is why the
			# Lugia behind it starts 64 bytes earlier: `TitleScreen` copies 8
			# tiles either way, so Silver's last four are the head of the
			# compressed Lugia, loaded into VRAM and never drawn.
			var title: Dictionary = (silver["title"] as Dictionary).duplicate()
			title["logo_top"] = 0x98498
			title["tilemap"] = 0x9862A
			title["trail_tiles"] = 4
			title["bird"] = 0xE4220
			title["bird_tiles"] = 128
			silver["title"] = title
			return silver
		RomRegistry.CRYSTAL:
			return CRYSTAL
	return {}


static func is_characterised(id: StringName) -> bool:
	return not for_id(id).is_empty()


## Translates the bank number stored in a pic pointer into the bank the data is
## really in.
##
## The tables were written before the pic sections were shuffled between banks
## and nobody rebuilt them, so the game repairs each pointer as it loads it.
## Reproducing that is not optional: the stored numbers are simply wrong.
static func fix_pic_bank(layout: Dictionary, stored: int) -> int:
	var patch: Dictionary = layout["pic_bank_patch"]
	if patch.has(stored):
		return patch[stored]
	return stored + int(layout["pic_bank_add"])


## `LoadNamingScreenGFX`'s four sheets, which sit either side of the keyboard
## block in `engine/menus/naming_screen.asm`'s own order: the border and the
## cursor before it, then End, MiddleLine and UnderLine after. Nothing else is
## between them, so each is located from the block rather than pinned again.
## The whole 446-byte run is byte identical in all three dumps.
const NAMING_BORDER_TILES: int = 1
const NAMING_CURSOR_TILES: int = 2
const NAMING_MARKER_TILES: int = 1
const TILE_BYTES_2BPP: int = 16
const TILE_BYTES_1BPP: int = 8


static func naming_border_offset(layout: Dictionary) -> int:
	return int(layout["name_input_chars"]) \
		- (NAMING_BORDER_TILES + NAMING_CURSOR_TILES) * TILE_BYTES_2BPP


static func naming_cursor_offset(layout: Dictionary) -> int:
	return naming_border_offset(layout) + NAMING_BORDER_TILES * TILE_BYTES_2BPP


## `NamingScreenGFX_End` sits first after the block and is unreferenced in both
## pins, so the two markers the screen does draw are one and two tiles past it.
static func naming_middle_line_offset(layout: Dictionary) -> int:
	return int(layout["name_input_chars"]) + NAME_INPUT_BLOCK_BYTES + TILE_BYTES_1BPP


static func naming_under_line_offset(layout: Dictionary) -> int:
	return naming_middle_line_offset(layout) + TILE_BYTES_1BPP


## Where [param table] of NAME_INPUT_TABLE_ROWS starts, counted from the block
## in source order, since the four keyboards are stored back to back with no
## header between them.
static func name_input_table_offset(layout: Dictionary, table: int) -> int:
	var at: int = int(layout["name_input_chars"])
	for before: int in table:
		at += NAME_INPUT_TABLE_ROWS[before] * NAME_INPUT_ROW_BYTES
	return at


## `data/text_buffers.asm`'s StringBufferPointers, in `text_buffer` argument
## order: wStringBuffer3, 4, 5, then 2, 1, then the two battle nicknames. The
## table is what turns a `TX_RAM` address back into a buffer this project fills,
## and the addresses are WRAM, so they differ between Gold/Silver and Crystal.
const STRING_BUFFER_POINTER_COUNT: int = 7
const STRING_BUFFER_POINTER_SIZE: int = 2

## `STRING_BUFFER_LENGTH` (`constants/script_constants.asm`). The five general
## buffers are one contiguous run, which is what [method RomImporter.verify_layout]
## checks the table against.
const STRING_BUFFER_LENGTH: int = 19

## Indices into the table, from the comment on `TextCommand_STRINGBUFFER`
## (`home/text.asm:902`). Only the five general buffers are ordered by stride;
## the two nicknames live elsewhere in WRAM.
const STRING_BUFFER_3: int = 0
const STRING_BUFFER_4: int = 1
const STRING_BUFFER_5: int = 2
const STRING_BUFFER_2: int = 3
const STRING_BUFFER_1: int = 4


static func string_buffer_pointer_offset(layout: Dictionary, index: int) -> int:
	return int(layout["string_buffer_pointers"]) + index * STRING_BUFFER_POINTER_SIZE


static func species_name_offset(layout: Dictionary, species: int) -> int:
	return int(layout["species_names"]) + (species - 1) * NAME_LENGTH


static func base_stats_offset(layout: Dictionary, species: int) -> int:
	return int(layout["base_stats"]) + (species - 1) * BASE_STATS_SIZE


static func dex_entry_pointer_offset(layout: Dictionary, species: int) -> int:
	var pokedex: Dictionary = layout["pokedex"]
	return int(pokedex["entry_pointers"]) + (species - 1) * DEX_ENTRY_POINTER_SIZE


## The bank a species' Pokedex entry lives in, by
## `GetDexEntryPointer`'s `(species - 1) >> 6`.
static func dex_entry_bank(layout: Dictionary, species: int) -> int:
	var pokedex: Dictionary = layout["pokedex"]
	var banks: Array = pokedex["entry_banks"]
	return int(banks[(species - 1) / DEX_ENTRY_BANK_SPECIES])


## Where a species' Pokedex entry starts in the dump, given the bank-local
## [param address] read from the table.
static func dex_entry_offset(layout: Dictionary, species: int, address: int) -> int:
	return RomFile.linear(dex_entry_bank(layout, species), address)


## The palette table carries a leading entry before Bulbasaur, so unlike every
## other table here it is indexed by species number directly.
static func palette_offset(layout: Dictionary, species: int) -> int:
	return int(layout["palettes"]) + species * Gen2Palette.ENTRY_BYTES


## Pointers come in pairs, front then back.
static func pic_pointer_offset(layout: Dictionary, species: int, back: bool) -> int:
	var pair: int = (species - 1) * 2 + (1 if back else 0)
	return int(layout["pic_pointers"]) + pair * PIC_POINTER_SIZE


static func unown_pic_pointer_offset(layout: Dictionary, form: int, back: bool) -> int:
	var pair: int = form * 2 + (1 if back else 0)
	return int(layout["unown_pic_pointers"]) + pair * PIC_POINTER_SIZE


## One of the four bar palettes, by its position in [constant BAR_PALETTE_NAMES].
static func bar_palette_offset(layout: Dictionary, index: int) -> int:
	return int(layout["bar_palettes"]) + index * Gen2Palette.PAIR_BYTES


static func trainer_class_count(layout: Dictionary) -> int:
	return int(layout["trainer_classes"])


static func map_group_count(layout: Dictionary, group: int) -> int:
	var counts: Array = layout.get("map_group_counts", [])
	if group < 1 or group > counts.size():
		return 0
	return int(counts[group - 1])


static func map_count(layout: Dictionary) -> int:
	var out: int = 0
	for count: int in layout.get("map_group_counts", []):
		out += count
	return out


static func map_group_pointer_offset(layout: Dictionary, group: int) -> int:
	return int(layout["map_group_pointers"]) + (group - 1) * MAP_GROUP_POINTER_SIZE


static func map_record_offset(layout: Dictionary, group_pointer: int, number: int) -> int:
	return RomFile.linear(bank_of(int(layout["map_group_pointers"])), group_pointer) \
		+ (number - 1) * MAP_RECORD_SIZE


static func tileset_count(layout: Dictionary) -> int:
	return (layout.get("tileset_block_counts", []) as Array).size()


static func tileset_offset(layout: Dictionary, number: int) -> int:
	return int(layout["tilesets"]) + number * TILESET_RECORD_SIZE


static func tileset_block_count(layout: Dictionary, number: int) -> int:
	var counts: Array = layout.get("tileset_block_counts", [])
	if number < 0 or number >= counts.size():
		return 0
	return int(counts[number])


static func overworld_sprite_offset(layout: Dictionary, number: int) -> int:
	return int(layout["overworld_sprites"]) + (number - 1) * OVERWORLD_SPRITE_RECORD_SIZE


static func overworld_sprite_count(layout: Dictionary) -> int:
	return int(layout.get("overworld_sprite_count", 0))


static func overworld_icon_offset(layout: Dictionary, number: int) -> int:
	return int(layout.get("overworld_icons", -1)) \
		+ (number - 1) * MON_ICON_BYTES


## Trainer pics have no back half and no size of their own, so unlike the
## Pokémon table this one is a flat run of three-byte pointers, indexed from the
## first class rather than from the player.
static func trainer_pic_pointer_offset(layout: Dictionary, trainer_class: int) -> int:
	return int(layout["trainer_pic_pointers"]) + (trainer_class - 1) * PIC_POINTER_SIZE


## The palette table opens with the player, who is a trainer class with no pic,
## so it is indexed by class number where the pic table is indexed by class
## number minus one. The two are one entry out of step on purpose.
static func trainer_palette_offset(layout: Dictionary, trainer_class: int) -> int:
	return int(layout["trainer_palettes"]) + trainer_class * Gen2Palette.PAIR_BYTES


## Where a trainer class's own pointer sits in the trainer party table. The
## pointer itself still has to be resolved through [method bank_of] on this
## offset and [method RomFile.linear], the same as [method evos_attacks_pointer_offset].
static func trainer_party_pointer_offset(layout: Dictionary, trainer_class: int) -> int:
	return int(layout["trainer_parties"]) + (trainer_class - 1) * TRAINER_PARTY_POINTER_SIZE


## A trainer class's own entry in the attributes table, indexed the same way as
## [method trainer_pic_pointer_offset] and [method trainer_party_pointer_offset]:
## from the first class rather than from the player.
static func trainer_attributes_offset(layout: Dictionary, trainer_class: int) -> int:
	return int(layout["trainer_attributes"]) + (trainer_class - 1) * TRAINER_ATTRIBUTES_SIZE


## A trainer class's own entry in the DVs table, indexed the same way as
## [method trainer_attributes_offset].
static func trainer_dvs_offset(layout: Dictionary, trainer_class: int) -> int:
	return int(layout["trainer_dvs"]) + (trainer_class - 1) * TRAINER_DVS_SIZE


## How many bytes one Pokémon occupies in a trainer's party, past its level and
## species: nothing for [constant TRAINER_MON_NORMAL], an item, four moves, or
## both, depending on the type byte its trainer opens with.
static func trainer_mon_extra_size(mon_type: int) -> int:
	var size: int = 0
	if mon_type == TRAINER_MON_ITEM or mon_type == TRAINER_MON_ITEM_MOVES:
		size += 1
	if mon_type == TRAINER_MON_MOVES or mon_type == TRAINER_MON_ITEM_MOVES:
		size += TRAINER_MON_MOVE_COUNT
	return size


static func move_data_offset(layout: Dictionary, move: int) -> int:
	return int(layout["move_data"]) + (move - 1) * MOVE_DATA_SIZE


## One species' entry in the combined evolution and level-up move table. The
## pointer is two bytes and the entry it names is in the pointer table's own
## bank, so [method bank_of] on the table itself resolves it.
static func evos_attacks_pointer_offset(layout: Dictionary, species: int) -> int:
	return int(layout["evos_attacks"]) + (species - 1) * EVOS_ATTACKS_POINTER_SIZE


## How many bytes one evolution entry occupies. [constant EVOLVE_STAT] carries a
## second parameter and so is a byte longer than the rest.
##
## The cartridge never needs this: it skips the evolutions by reading bytes until
## it meets the terminator, which works because no byte inside an entry is ever
## zero. Something that decodes them rather than skipping them does need it.
static func evolution_size(method: int) -> int:
	return 4 if method == EVOLVE_STAT else 3


## Type names are reached through a pointer table rather than stored inline,
## because every unused type number points at the same "NORMAL" string. The
## pointers are two bytes, not three: the strings sit in the table's own bank.
static func type_name_pointer_offset(layout: Dictionary, type_number: int) -> int:
	return int(layout["type_names"]) + type_number * TYPE_POINTER_SIZE


## Whether a byte is a type number the matchup chart could be talking about.
##
## The type numbers are sparse, and the run between the two groups is padding
## that a move's type byte may legitimately hold but that no matchup names. A
## walk that has left the table lands in that gap almost immediately, which is
## most of what makes this a check worth having.
static func is_matchup_type(value: int) -> bool:
	if value <= PHYSICAL_TYPES_END:
		return true
	return value >= SPECIAL_TYPES_START and value < TYPE_COUNT


## Where `OakRatings` row [param index] starts.
static func oak_rating_offset(layout: Dictionary, index: int) -> int:
	return int(layout.get("oak_ratings", -1)) + index * OAK_RATING_SIZE


## The dump offset one of `prof_oaks_pc.asm`'s five text stubs sits at, counted
## in stubs from `OakRating01`, whose address the table's first row carries.
static func oak_text_stub_offset(rom: RomFile, layout: Dictionary, name: String) -> int:
	var table: int = int(layout.get("oak_ratings", -1))
	if not rom.in_bounds(table, OAK_RATING_SIZE) or not OAK_TEXT_STUBS.has(name):
		return -1
	var first: int = rom.u16le(table + 3) + int(OAK_TEXT_STUBS[name]) * OAK_TEXT_STUB_SIZE
	return RomFile.linear(bank_of(table), first)


## Where the `text_far` stub [param name] names sits.
static func pokecenter_pc_text_offset(layout: Dictionary, name: String) -> int:
	var at: int = int(layout.get("pokecenter_pc", -1))
	if at < 0 or not POKECENTER_PC_TEXT_AT.has(name):
		return -1
	return at + int(POKECENTER_PC_TEXT_AT[name])


## `Credits_LoadBorderGFX.Frames`, as 16-tile block indices into the mon run.
static func credits_frames(layout: Dictionary) -> Array:
	var stored: Variant = (layout.get("credits", {}) as Dictionary).get("frames", [])
	return stored if stored is Array else []


## How many tiles the four mon sheets occupy together, which is what the highest
## block `.Frames` names says. Zero for a cartridge with no credits.
static func credits_mon_tiles(layout: Dictionary) -> int:
	var frames: Array = credits_frames(layout)
	if frames.is_empty():
		return 0
	var highest: int = 0
	for block: Variant in frames:
		highest = maxi(highest, int(block))
	return (highest + 1) * CREDITS_MON_FRAME_TILES


## Where `CreditsPichuGFX` and its three neighbours start: directly behind
## `CreditsBorderGFX`, which is the one offset pinned. -1 without a credits entry.
static func credits_mon_gfx_offset(layout: Dictionary) -> int:
	var at: int = int((layout.get("credits", {}) as Dictionary).get("gfx", -1))
	return at + CREDITS_BORDER_TILES * Gen2Tiles.TILE_BYTES if at >= 0 else -1


## The dump offset `CreditsStringsPointers` entry [param index] names. Its bank
## is the strings' own rather than the table's, since Gold and Silver reach them
## with `PlaceFarString`.
static func credits_string_offset(rom: RomFile, layout: Dictionary, index: int) -> int:
	var entry: Dictionary = layout.get("credits", {})
	var table: int = int(entry.get("strings", -1))
	if table < 0 or index < 0 or index >= int(entry.get("string_count", 0)):
		return -1
	var at: int = table + index * 2
	if not rom.in_bounds(at, 2):
		return -1
	return RomFile.linear(int(entry.get("strings_bank", 0)), rom.u16le(at))


## `PokedexNestIconGFX`, which `INCBIN`s directly behind `kanto.bin` in the same
## bank; -1 for a cartridge with no region map.
static func dex_nest_icon_offset(layout: Dictionary) -> int:
	var kanto: int = int((layout.get("town_map", {}) as Dictionary).get("kanto", -1))
	return kanto + TOWN_MAP_REGION_BYTES if kanto >= 0 else -1


static func landmark_count(layout: Dictionary) -> int:
	return int((layout.get("town_map", {}) as Dictionary).get("landmark_count", 0))


## Where landmark [param index]'s four-byte record starts.
static func landmark_offset(layout: Dictionary, index: int) -> int:
	var entry: Dictionary = layout.get("town_map", {})
	return int(entry.get("landmarks", -1)) + index * LANDMARK_RECORD_SIZE


## The dump offset landmark [param index]'s name pointer addresses. The pointer
## is two bytes, so the string is in the table's own bank.
static func landmark_name_offset(rom: RomFile, layout: Dictionary, index: int) -> int:
	var record: int = landmark_offset(layout, index)
	if not rom.in_bounds(record, LANDMARK_RECORD_SIZE):
		return -1
	return RomFile.linear(bank_of(record), rom.u16le(record + 2))


static func font_offset(layout: Dictionary) -> int:
	return int(layout["font"])


## Frames are stored back to back in selection order, six tiles of 1bpp each.
static func frame_offset(layout: Dictionary, frame: int) -> int:
	return int(layout["frames"]) + frame * FRAME_TILES * Gen2Tiles.TILE_1BPP_BYTES


## The bank a dump offset falls in, for resolving a pointer that carries an
## address but no bank number of its own.
static func bank_of(offset: int) -> int:
	@warning_ignore("integer_division")
	return offset / RomFile.BANK_SIZE
