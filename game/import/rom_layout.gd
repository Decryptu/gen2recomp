class_name RomLayout
extends RefCounted

## Where the data lives inside each supported cartridge.
##
## Offsets are absolute positions in the 2 MiB dump, not bank:address pairs, so
## a decoder never has to think about banking. Gold and Silver share the bank
## map, while a few data sections use per-game offsets; Crystal moved almost
## everything and is its own table.
##
## Every offset here was located in the cartridges themselves, by searching for
## content whose bytes are known independently (the encoded string "BULBASAUR",
## Bulbasaur's published base stats), and then cross-checked against the pret
## disassemblies for structure. That is why there is no entry for a ROM that is
## not in [RomRegistry]: an offset table is a claim about a specific dump, and
## the honest answer for an uncharacterised one is a refusal, not a guess.
##
## An offset is only trustworthy alongside the check that proves it: see
## [method RomImporter.verify_layout], which the importer runs before it decodes
## anything.

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

## The cartridge compares an 8-bit random value directly with these encoded
## percentage thresholds when it varies a surfing encounter's level. The
## values are the source's integer `$FF / 100 * percent` expressions.
const WILD_SURF_LEVEL_THRESHOLDS: Array[int] = [89, 165, 216, 242]

## The graphics stream supplies the 96 tiles loaded by the overworld. Metatile
## and collision tables are shorter for tilesets that never use all 128 blocks;
## unused metatile entries may still contain $FF placeholders.
const TILESET_RECORD_SIZE: int = 15
const TILESET_TILE_COUNT: int = 96
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

## Global overworld service tables. The source keeps these apart from map data:
## marts are an index table of item lists, phone contacts are fixed records,
## and audio is two far-pointer tables into the banked audio programs.
const MART_COUNT: int = 34
const MART_POINTER_SIZE: int = 2
const MART_RECORD_MAX_ITEMS: int = 16
const MART_TERMINATOR: int = 0xFF
const PHONE_CONTACT_COUNT: int = 38
const PHONE_CONTACT_SIZE: int = 12
const SPECIAL_PHONE_CALL_COUNT: int = 8
const SPECIAL_PHONE_CALL_SIZE: int = 6
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
const AUDIO_CRY_COUNT: int = 67

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
const ITEMMENU_CURRENT: int = 4
const ITEMMENU_PARTY: int = 5
const ITEMMENU_CLOSE: int = 6
const ITEM_ATTRIBUTE_CANT_SELECT: int = 1 << 6
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
const TYPE_ROCK: int = 0x05
const TYPE_GHOST: int = 0x08
const TYPE_STEEL: int = 0x09

## The longest move and item name in these games is twelve characters. This is
## the runaway guard for a terminator walk, not a field width.
const MAX_NAME_LENGTH: int = 16

## The type matchup chart: three bytes an entry, attacker then defender then the
## multiplier, and only the exceptions are listed. A pair that is not in the
## table is [constant MATCHUP_EFFECTIVE], which is why the whole of Generation 2
## fits in 332 bytes.
##
## Multipliers are in tenths, as the cartridge stores them, so a matchup is
## applied by multiplying and then dividing by ten. Keeping the tenth rather
## than a float is not pedantry: the games truncate after each of a defender's
## two types, and a Pokémon that survives on one hit point does so because of it.
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
## It is worth naming rather than working around, because the order is load
## bearing. Filling a fresh Pokémon's moves stops at the first entry above the
## level being filled for, so a Muk below 45 never reaches the three moves listed
## after the level 45 one and is short of what its level says it should know.
## Checking the order everywhere else is worth the one exception: scrambled
## levels are exactly what a wrong offset produces.
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
const ENEMY_HUD_TILES: int = 4
const PLAYER_HUD_TILES: int = 6
const EXP_BAR_TILES: int = 9

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

## The trainer *party* table is a second table indexed the same way as the class
## names, pics and palettes, one pointer per class, and it is where the game's
## individual trainers actually live. "LEADER" is the class name every gym
## leader shares; FALKNER is a name stored inside class 1's own party entry,
## next to the Pokémon he brings. Reading a class's identity therefore always
## means reading two tables, not one.
##
## The pointer is two bytes, in the pointer table's own bank, exactly like
## [member evos_attacks]: the entries sit in the same bank as the pointers that
## address them, so there is no bank number to store.
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
## Seven bytes: two item numbers a trainer of this class may use, a base money
## reward, then two words of bit flags. Confirmed against pret's own
## `TrainerClassAttributes`, entry by entry: Falkner opens the table with the
## bytes his own listing gives, class 5 (Pryce) is the first to differ (he may
## use a Hyper Potion), and one class further down the list carries an AI move
## weight word of zero ([constant NO_AI]), which the check below has to allow
## rather than reject as garbage.
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
## Two nibbles a byte, attack and defense in the first and speed and special in
## the second, which is exactly the shape [method Gen2Stats.pack_dvs] already
## packs a DV word into: a class's two raw bytes, read as one big-endian
## integer, are a [Gen2BattleMon] DV word with no repacking. Confirmed against
## pret's own `TrainerClassDVs` entry by entry in all three games: Falkner opens
## the table with his own known DVs, and the class that closes it (class 66 in
## Gold and Silver, 67 in Crystal, since Crystal alone carries MYSTICALMAN)
## carries its own.
const TRAINER_DVS_SIZE: int = 2

## The one trainer class with no party of its own: the eleven o'clock scholar,
## Professor Elm's class in the class table, whose name and pic exist but who
## the games never send into a battle. Its own label in the source is followed
## immediately by the next class's with nothing between, so its pointer equals
## the next class's, and the honest reading of that is zero trainers rather than
## a copy of somebody else's. Confirmed against pret's own party data
## (`PokemonProfGroup` has no entries before `WillGroup`, in that order), and
## the same class number in every game.
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
const TMHM_BYTES: int = 8

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
	"mart_table": 0x162FE,
	"default_mart": 0x16469,
	"bargain_mart": 0x15EDA,
	"rooftop_mart_count": 0,
	"rooftop_mart_1": 0,
	"rooftop_mart_2": 0,
	"phone_contacts": 0x9043A,
	"special_phone_calls": 0x905F6,
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
	"overworld_sprite_count": 99,
	"overworld_sprite_palettes": 0xB469,
	"mart_table": 0x160A9,
	"default_mart": 0x16214,
	"bargain_mart": 0x15C51,
	"rooftop_mart_count": 2,
	"rooftop_mart_1": 0x15AEE,
	"rooftop_mart_2": 0x15AFF,
	"phone_contacts": 0x9045F,
	"special_phone_calls": 0x90627,
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
			silver["item_attributes"] = 0x6866
			silver["item_status_actions"] = 0xF0C5
			silver["item_healing_hp"] = 0xF403
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


static func species_name_offset(layout: Dictionary, species: int) -> int:
	return int(layout["species_names"]) + (species - 1) * NAME_LENGTH


static func base_stats_offset(layout: Dictionary, species: int) -> int:
	return int(layout["base_stats"]) + (species - 1) * BASE_STATS_SIZE


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
