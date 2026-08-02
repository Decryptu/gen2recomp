class_name RomLayout
extends RefCounted

## Where the data lives inside each supported cartridge.
##
## Offsets are absolute positions in the 2 MiB dump, not bank:address pairs, so
## a decoder never has to think about banking. Gold and Silver share a layout;
## Crystal moved almost everything and is its own table.
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

const MOVE_COUNT: int = 251
const MOVE_DATA_SIZE: int = 7

## Item numbers run from 1 to 255. The last several entries are the unused
## "TERU-SAMA" slots the cartridges ship with; they are decoded rather than
## trimmed, so an item number always indexes the table directly.
const ITEM_COUNT: int = 255

## Type numbers are sparse: $00-$09 are the physical types, $14-$1B the special
## ones, and the run between is padding that still has a name entry. Reading all
## 28 keeps the table indexable by type number.
const TYPE_COUNT: int = 28
const TYPE_POINTER_SIZE: int = 2

## The longest move and item name in these games is twelve characters. This is
## the runaway guard for a terminator walk, not a field width.
const MAX_NAME_LENGTH: int = 16

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

## Trainer classes are numbered from 1; class 0 is the player, who has a palette
## in the table but no pic in it. Crystal added one class to the sixty-six Gold
## and Silver have, so the count lives in the layout rather than here.
##
## Every trainer pic is this square, unlike a Pokémon's front pic.
const TRAINER_PIC_TILES: int = 7

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

## Gold and Silver are byte-identical in every table below; only content differs.
const GOLD_SILVER: Dictionary = {
	"species_names": 0x1B0B74,
	"base_stats": 0x51B0B,
	"pic_pointers": 0x48000,
	"unown_pic_pointers": 0x7C000,
	"palettes": 0xAD3D,
	"move_names": 0x1B1574,
	"item_names": 0x1B0000,
	"move_data": 0x41AFE,
	"type_names": 0x509AE,
	"font": 0xF82F2,
	"frames": 0xF88F2,
	"trainer_pic_pointers": 0x80000,
	"trainer_palettes": 0xB53D,
	"trainer_class_names": 0x1B0955,
	"trainer_classes": 66,
	"trainer_last_class": "ROCKET",
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
	"move_data": 0x41AFB,
	"type_names": 0x5097B,
	"font": 0xF8200,
	"frames": 0xF8800,
	"trainer_pic_pointers": 0x128000,
	"trainer_palettes": 0xB0CE,
	"trainer_class_names": 0x2C1EF,
	"trainer_classes": 67,
	"trainer_last_class": "MYSTICALMAN",
	# Crystal's equivalent table is a contiguous $48-$5F, so the whole remap
	# collapses to a constant: PICS_FIX in pokecrystal.
	"pic_bank_add": 0x36,
	"pic_bank_patch": {},
}


## The layout for a game id, or an empty Dictionary if it is not characterised.
static func for_id(id: StringName) -> Dictionary:
	match id:
		RomRegistry.GOLD, RomRegistry.SILVER:
			return GOLD_SILVER
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


static func trainer_class_count(layout: Dictionary) -> int:
	return int(layout["trainer_classes"])


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


static func move_data_offset(layout: Dictionary, move: int) -> int:
	return int(layout["move_data"]) + (move - 1) * MOVE_DATA_SIZE


## Type names are reached through a pointer table rather than stored inline,
## because every unused type number points at the same "NORMAL" string. The
## pointers are two bytes, not three: the strings sit in the table's own bank.
static func type_name_pointer_offset(layout: Dictionary, type_number: int) -> int:
	return int(layout["type_names"]) + type_number * TYPE_POINTER_SIZE


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
