class_name RomImporter
extends RefCounted

## Decodes a verified cartridge into the cache under [code]user://[/code].
##
## The ROM is an asset database, read once and released. Nothing downstream holds
## a reference, and nothing in the engine reads cartridge bytes at play time.
##
## The order matters: verify the hash, then the layout, then decode. A wrong
## offset produces plausible garbage rather than an error, and garbage in the
## cache is indistinguishable from real data later, so [method verify_layout]
## checks values whose correct answers are known independently.

## Atlas cells are the largest pic of their kind so a renderer can index them
## arithmetically; smaller pics sit in the top-left of their cell and record
## their real size.
const ATLAS_COLUMNS: int = 16

## Falkner is trainer class 1 in all three games, and the class in the middle is
## a walk check on a table whose entries are terminated rather than padded. The
## class that ends the table differs between games and lives in [RomLayout].
const TRAINER_FIRST_CLASS: String = "LEADER"
const TRAINER_MIDDLE_CLASS: int = 22
const TRAINER_MIDDLE_CLASS_NAME: String = "YOUNGSTER"

## What the evolution and learnset table is known to say, independently of the
## cartridge. The first species evolves at sixteen into the second and opens with
## Tackle at level one; the last has no evolution at all. One at each end of the
## pointer table, so a start that is right and a stride that is not fails too.
const FIRST_EVOLUTION_LEVEL: int = 16
const FIRST_LEARNSET_MOVE: int = 33

## Two independently pinned EggMovePointers rows, one at each side of the
## breeding divide between the profiles. Staryu loses its three inherited moves
## in Crystal; Bulbasaur loses Charm there and keeps the other five.
const EGG_MOVE_BULBASAUR_SPECIES: int = 1
const EGG_MOVE_STARYU_SPECIES: int = 120
const EGG_MOVES_BULBASAUR_GOLD_SILVER: Array[int] = [113, 130, 219, 204, 13, 80]
const EGG_MOVES_BULBASAUR_CRYSTAL: Array[int] = [113, 130, 219, 13, 80]
const EGG_MOVES_STARYU_GOLD_SILVER: Array[int] = [62, 112, 48]
const EGG_MOVES_STARYU_CRYSTAL: Array[int] = []

## Tyrogue, the only species that evolves on a stat comparison, and the number of
## ways it can go. It is worth checking on its own: [constant RomLayout.EVOLVE_STAT]
## is the one entry that is four bytes rather than three, so a decoder that has
## the size wrong stays in step everywhere except here and comes out the far side
## of Tyrogue reading rubbish.
const STAT_EVOLUTION_SPECIES: int = 236
const STAT_EVOLUTION_COUNT: int = 3

## HM01's move, which is TMHMMoves' row 51 and so the entry directly after the
## fifty TMs. Checking it is what pins the table: a run of legal move numbers
## elsewhere in the bank would pass the range and terminator checks alone.
const MOVE_CUT: int = 0x0F

## What the trainer *party* table is known to say, independently of the
## cartridge, which is a different table from [constant TRAINER_FIRST_CLASS]:
## that one is the class every gym leader shares ("LEADER"), and this one is the
## individual trainer stored inside class 1's own entry. Falkner's level 7
## Pidgey and level 9 Pidgeotto are the same in all three games.
const TRAINER_PARTY_FIRST_NAME: String = "FALKNER"
const TRAINER_PARTY_FIRST_LEVEL_1: int = 7
const TRAINER_PARTY_FIRST_SPECIES_1: int = 16
const TRAINER_PARTY_FIRST_LEVEL_2: int = 9
const TRAINER_PARTY_FIRST_SPECIES_2: int = 17

## Falkner's own entry in the trainer attributes table, known independently of
## the cartridge from pret's `TrainerClassAttributes`: no items, a reward of 25,
## and the AI flag word every gym leader shares.
const TRAINER_ATTR_FIRST_REWARD: int = 25
const TRAINER_ATTR_FIRST_AI_MOVE_WEIGHTS: int = RomLayout.AI_BASIC | RomLayout.AI_SETUP \
	| RomLayout.AI_SMART | RomLayout.AI_AGGRESSIVE | RomLayout.AI_CAUTIOUS \
	| RomLayout.AI_STATUS | RomLayout.AI_RISKY
const TRAINER_ATTR_FIRST_AI_ITEM_SWITCH: int = RomLayout.CONTEXT_USE | RomLayout.SWITCH_SOMETIMES

## Falkner's own DVs, known independently of the cartridge from pret's
## `TrainerClassDVs`: attack 9, defense 10, speed 7, special 7, packed the way
## [method Gen2Stats.pack_dvs] packs a DV word.
const TRAINER_DVS_FIRST: int = 0x9A77

## What the first and last Pokedex entries are known to say, independently of
## the cartridge: the published category, height as decimal feet and inches, and
## weight in tenths of a pound. All three dumps agree on every one of these;
## it is the description text, not the measurements, that differs between them.
const DEX_FIRST_CATEGORY: String = "SEED"
const DEX_FIRST_HEIGHT: int = 204
const DEX_FIRST_WEIGHT: int = 150
const DEX_LAST_CATEGORY: String = "TIMETRAVEL"
const DEX_LAST_HEIGHT: int = 200
const DEX_LAST_WEIGHT: int = 110

## The species each order table opens with, known from pret's
## `NewPokedexOrder` (Chikorita, the first of the new dex) and
## `AlphabeticalPokedexOrder` (Abra).
const DEX_ORDER_NEW_FIRST: int = 152
const DEX_ORDER_ALPHA_FIRST: int = 63

var _lz: Gen2Lz = Gen2Lz.new()


## Sanity-checks [RomLayout] against the cartridge before anything is decoded.
## Returns { ok, message }.
static func verify_layout(rom: RomFile) -> Dictionary:
	var layout: Dictionary = RomLayout.for_id(rom.id)
	if layout.is_empty():
		return {"ok": false, "message": "No layout for %s." % rom.id}

	var data: PackedByteArray = rom.bytes()

	# The first and last species, decoded through the text codec. Wrong offset,
	# wrong table or wrong character map all fail here.
	var first: String = Gen2Text.decode(
		data, RomLayout.species_name_offset(layout, 1), RomLayout.NAME_LENGTH
	)
	if first != "BULBASAUR":
		return {"ok": false, "message": "Species name table: expected BULBASAUR, read %s." % first}

	var last: String = Gen2Text.decode(
		data, RomLayout.species_name_offset(layout, RomLayout.SPECIES_COUNT),
		RomLayout.NAME_LENGTH
	)
	if last != "CELEBI":
		return {"ok": false, "message": "Species name table: expected CELEBI, read %s." % last}

	# Every base stats entry opens with its own Pokédex number, so the whole
	# table self-checks in one pass, and a stride that is off by any amount
	# stops matching immediately.
	for species: int in range(1, RomLayout.SPECIES_COUNT + 1):
		var stored: int = rom.u8(RomLayout.base_stats_offset(layout, species))
		if stored != species:
			return {
				"ok": false,
				"message": "Base stats entry %d claims to be %d." % [species, stored],
			}

	# Palettes have no self-identifying field, so they are checked structurally:
	# a colour is 15 bits, and no species is drawn in two blacks. An offset that
	# lands on the wrong table, or a stride that runs past the end of the right
	# one, breaks one of those. This check exists because a palette table that
	# was one whole table too far along still decoded into sprites that were the
	# correct shapes in the wrong colours, which nothing else would catch.
	for species: int in range(1, RomLayout.SPECIES_COUNT + 1):
		var entry: int = RomLayout.palette_offset(layout, species)
		var packed: Array = []
		for i: int in int(float(Gen2Palette.ENTRY_BYTES) / float(Gen2Palette.COLOR_BYTES)):
			packed.append(rom.u16le(entry + i * Gen2Palette.COLOR_BYTES))
		for color: int in packed:
			if color & 0x8000:
				return {
					"ok": false,
					"message": "Palette %d has bit 15 set ($%04X); not colour data." % [
						species, color,
					],
				}
		if packed.count(0) == packed.size():
			return {"ok": false, "message": "Palette %d is blank." % species}

	# Move and item names are variable-length, so one wrong byte at the start
	# slides every entry after it and still reads as words. Checking the last
	# entry of each table catches that; checking only the first would not.
	var moves: PackedStringArray = Gen2Text.decode_sequence(
		data, int(layout["move_names"]), RomLayout.MOVE_COUNT, RomLayout.MAX_NAME_LENGTH
	)
	if moves.size() != RomLayout.MOVE_COUNT:
		return {"ok": false, "message": "Move name table ran out after %d." % moves.size()}
	if moves[0] != "POUND":
		return {"ok": false, "message": "Move name table: expected POUND, read %s." % moves[0]}
	if moves[RomLayout.MOVE_COUNT - 1] != "BEAT UP":
		return {
			"ok": false,
			"message": "Move name table: expected BEAT UP, read %s." % moves[
				RomLayout.MOVE_COUNT - 1
			],
		}

	# Every move entry opens with its animation, which is the move's own number,
	# so the whole table self-checks the way the base stats do. The type byte is
	# range-checked in the same pass because it indexes the type name table.
	for move: int in range(1, RomLayout.MOVE_COUNT + 1):
		var entry: int = RomLayout.move_data_offset(layout, move)
		var animation: int = rom.u8(entry + RomLayout.MOVE_ANIMATION)
		if animation != move:
			return {"ok": false, "message": "Move entry %d claims to be %d." % [move, animation]}
		var type_number: int = rom.u8(entry + RomLayout.MOVE_TYPE)
		if type_number >= RomLayout.TYPE_COUNT:
			return {
				"ok": false,
				"message": "Move %d has type $%02X, past the end of the type table." % [
					move, type_number,
				],
			}

	var items: PackedStringArray = Gen2Text.decode_sequence(
		data, int(layout["item_names"]), RomLayout.ITEM_COUNT, RomLayout.MAX_NAME_LENGTH
	)
	if items.size() != RomLayout.ITEM_COUNT:
		return {"ok": false, "message": "Item name table ran out after %d." % items.size()}
	if items[0] != "MASTER BALL":
		return {"ok": false, "message": "Item name table: expected MASTER BALL, read %s." % items[0]}
	# Four entries in, so a start that is right but a walk that is not still
	# fails here.
	if items[3] != "GREAT BALL":
		return {"ok": false, "message": "Item 4: expected GREAT BALL, read %s." % items[3]}

	var item_metadata: Dictionary = verify_item_metadata(rom, layout)
	if not bool(item_metadata.get("ok", false)):
		return item_metadata

	var trades: Dictionary = verify_world_trades(rom, layout)
	if not bool(trades.get("ok", false)):
		return trades

	# The first and last type, either side of the padding run in the middle.
	var first_type: String = type_name(rom, layout, 0)
	if first_type != "NORMAL":
		return {"ok": false, "message": "Type table: expected NORMAL, read %s." % first_type}
	var last_type: String = type_name(rom, layout, RomLayout.TYPE_COUNT - 1)
	if last_type != "DARK":
		return {"ok": false, "message": "Type table: expected DARK, read %s." % last_type}

	var matchups: Dictionary = verify_matchups(rom, layout)
	if not matchups["ok"]:
		return matchups

	var evos_attacks: Dictionary = verify_evos_attacks(rom, layout)
	if not evos_attacks["ok"]:
		return evos_attacks

	var egg_moves: Dictionary = verify_egg_moves(rom, layout)
	if not egg_moves["ok"]:
		return egg_moves

	var pokedex: Dictionary = verify_pokedex(rom, layout)
	if not pokedex["ok"]:
		return pokedex

	var font: Dictionary = verify_font(rom, layout)
	if not font["ok"]:
		return font

	var frames: Dictionary = verify_frames(rom, layout)
	if not frames["ok"]:
		return frames

	var battle: Dictionary = verify_battle_graphics(rom, layout)
	if not battle["ok"]:
		return battle

	var trainers: Dictionary = verify_trainers(rom, layout)
	if not trainers["ok"]:
		return trainers

	var trainer_parties: Dictionary = verify_trainer_parties(rom, layout)
	if not trainer_parties["ok"]:
		return trainer_parties

	var trainer_attributes: Dictionary = verify_trainer_attributes(rom, layout)
	if not trainer_attributes["ok"]:
		return trainer_attributes

	var trainer_dvs: Dictionary = verify_trainer_dvs(rom, layout)
	if not trainer_dvs["ok"]:
		return trainer_dvs

	var world: Dictionary = Gen2WorldImporter.verify_layout(rom)
	if not world["ok"]:
		return world

	var encounters: Dictionary = Gen2WorldEncounterImporter.verify_layout(rom)
	if not encounters["ok"]:
		return encounters

	var services: Dictionary = Gen2WorldServicesImporter.verify_layout(rom)
	if not services["ok"]:
		return services

	var battle_anims: Dictionary = Gen2BattleAnimImporter.verify_layout(rom)
	if not battle_anims["ok"]:
		return battle_anims

	var name_input: Dictionary = verify_name_input_chars(rom, layout)
	if not name_input["ok"]:
		return name_input

	var intro_text: Dictionary = verify_intro_text(rom, layout)
	if not intro_text["ok"]:
		return intro_text

	var string_buffers: Dictionary = verify_string_buffer_pointers(rom, layout)
	if not string_buffers["ok"]:
		return string_buffers

	var gender_screen: Dictionary = verify_gender_screen(rom, layout)
	if not gender_screen["ok"]:
		return gender_screen

	var text_palette: Dictionary = verify_text_bg_palette(rom, layout)
	if not text_palette["ok"]:
		return text_palette

	var shrink: Dictionary = verify_shrink_pics(rom, layout)
	if not shrink["ok"]:
		return shrink

	var copyright: Dictionary = verify_copyright(rom, layout)
	if not copyright["ok"]:
		return copyright

	var presents: Dictionary = verify_game_freak_presents(rom, layout)
	if not presents["ok"]:
		return presents

	var title: Dictionary = verify_title(rom, layout)
	if not title["ok"]:
		return title

	var town_map: Dictionary = verify_town_map(rom, layout)
	if not town_map["ok"]:
		return town_map

	var oak_ratings: Dictionary = verify_oak_ratings(rom, layout)
	if not oak_ratings["ok"]:
		return oak_ratings

	var pokecenter_pc: Dictionary = verify_pokecenter_pc(rom, layout)
	if not pokecenter_pc["ok"]:
		return pokecenter_pc

	var unown_words: Dictionary = verify_unown_words(rom, layout)
	if not unown_words["ok"]:
		return unown_words

	var unown_walls: Dictionary = verify_unown_walls(rom, layout)
	if not unown_walls["ok"]:
		return unown_walls

	var intro_movie: Dictionary = verify_intro_movie(rom, layout)
	if not intro_movie["ok"]:
		return intro_movie

	var gs_intro: Dictionary = verify_gs_intro(rom, layout)
	if not gs_intro["ok"]:
		return gs_intro

	var unown_puzzle: Dictionary = verify_unown_puzzle(rom, layout)
	if not unown_puzzle["ok"]:
		return unown_puzzle

	var credits: Dictionary = verify_credits(rom, layout)
	if not credits["ok"]:
		return credits

	var menu_text: Dictionary = verify_menu_text(rom, layout)
	if not menu_text["ok"]:
		return menu_text

	var mart_text: Dictionary = verify_mart_text(rom, layout)
	if not mart_text["ok"]:
		return mart_text

	var name_rater_text: Dictionary = verify_name_rater_text(rom, layout)
	if not name_rater_text["ok"]:
		return name_rater_text

	var move_deleter_text: Dictionary = verify_move_deleter_text(rom, layout)
	if not move_deleter_text["ok"]:
		return move_deleter_text

	var day_care_text: Dictionary = verify_day_care_text(rom, layout)
	if not day_care_text["ok"]:
		return day_care_text

	var map_entry_sign: Dictionary = verify_map_entry_sign(rom, layout)
	if not map_entry_sign["ok"]:
		return map_entry_sign

	var pack: Dictionary = verify_pack(rom, layout)
	if not pack["ok"]:
		return pack

	var pc: Dictionary = verify_pc(rom, layout)
	if not pc["ok"]:
		return pc

	var descriptions: Dictionary = verify_descriptions(rom, layout)
	if not descriptions["ok"]:
		return descriptions

	return {"ok": true, "message": "Layout verified."}


## `gfx/sgb/predef.pal`'s PREDEFPAL_GAMEFREAK_LOGO_BG, the palette
## `_CGB_GamefreakLogo` loads before the copyright is drawn: black, two greys and
## white, in that order. The eight bytes appear once in each dump, so they pin
## themselves.
const COPYRIGHT_COLORS: Array[int] = [0x0000, 0x2D68, 0x56B5, 0x7FFF]


## `Copyright`'s two halves, which check each other: the string is nothing but
## the codes the strip draws, so a run whose every code lands inside the strip,
## whose rows are the source's three and which ends at "@" cannot be a text or
## another graphic's neighbour. The strip itself is checked for having a lit
## pixel in it, since a blank run of the right length would otherwise pass.
static func verify_copyright(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout.get("copyright", {})
	if entry.is_empty():
		return {"ok": true, "message": "No copyright screen on this cartridge."}
	var tiles: int = int(entry.get("tiles", 0))
	var gfx: int = int(entry.get("gfx", -1))
	if tiles <= 0 or not rom.in_bounds(gfx, tiles * Gen2Tiles.TILE_BYTES):
		return {"ok": false, "message": "The copyright graphic is outside the cartridge."}
	var ink: bool = false
	for index: int in tiles * Gen2Tiles.TILE_BYTES:
		if rom.u8(gfx + index) != 0:
			ink = true
			break
	if not ink:
		return {"ok": false, "message": "The copyright graphic is blank."}
	var codes: PackedByteArray = read_copyright_string(rom, layout)
	if codes.is_empty():
		return {"ok": false, "message": "The copyright string has no terminator."}
	var rows: int = 1
	for code: int in codes:
		if code == RomLayout.COPYRIGHT_STRING_NEXT:
			rows += 1
			continue
		if code < RomLayout.COPYRIGHT_FIRST_CODE \
			or code >= RomLayout.COPYRIGHT_FIRST_CODE + tiles:
			return {
				"ok": false,
				"message": "Copyright string code $%02X is outside its %d tiles." % [
					code, tiles,
				],
			}
	var palette: int = int(entry.get("palette", -1))
	if not rom.in_bounds(palette, COPYRIGHT_COLORS.size() * Gen2Palette.COLOR_BYTES):
		return {"ok": false, "message": "The copyright palette is outside the cartridge."}
	for index: int in COPYRIGHT_COLORS.size():
		var stored: int = rom.u16le(palette + index * Gen2Palette.COLOR_BYTES)
		if stored != COPYRIGHT_COLORS[index]:
			return {
				"ok": false,
				"message": "Copyright palette colour %d is $%04X, expected $%04X." % [
					index, stored, COPYRIGHT_COLORS[index],
				],
			}
	if rows != RomLayout.COPYRIGHT_STRING_ROWS:
		return {
			"ok": false,
			"message": "The copyright string has %d rows, expected %d." % [
				rows, RomLayout.COPYRIGHT_STRING_ROWS,
			],
		}
	return {"ok": true, "message": "Copyright screen verified."}


## `gfx/splash/ditto.pal`, the palette `_CGB_GamefreakLogo` gives both object
## palettes. Colour 2 is the pink `GameFreakDittoPaletteFade` moves to orange, so
## the fade's first entry has to be this one.
const PRESENTS_DITTO_COLORS: Array[int] = [0x7FFF, 0x016D, 0x7197, 0x0000]
## `gfx/sgb/predef.pal`'s PREDEFPAL_GAMEFREAK_LOGO_OB: white, white and twice the
## yellow `GameFreakPresents_UpdateLogoPal` rotates the logo into.
const PRESENTS_OBJECT_COLORS: Array[int] = [0x7FFF, 0x7FFF, 0x03D9, 0x03D9]
## The eleven `SPRITE_ANIM_OAMSET_GAMEFREAK_LOGO_*` base tiles
## (`data/sprite_anims/oam.asm`), which is what says a 4096-byte graphic is the
## Ditto animation rather than another sheet of the same size.
const PRESENTS_DITTO_OAM_BASES: Array[int] = [
	0xD0, 0xD3, 0xD6, 0x6C, 0x68, 0x64, 0x60, 0x0C, 0x08, 0x04, 0x00,
]


## `GameFreakPresents`' art, identified by content rather than by bounds.
##
## The 1bpp run is two graphics, so it is checked as two: every tile of the
## thirteen-tile word strip carries ink, the six that spell "PRESENTS" are clear
## across their top rows because that word sits a row lower than the one above
## it, and the fourteenth tile - the logo's own top-left corner - is blank,
## which is why `GameFreakPresents_PlaceGameFreak` can use it as the space in
## "GAME FREAK". A neighbouring 1bpp run would have to be blank in exactly that
## tile and inked in exactly the other twelve.
static func verify_game_freak_presents(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout.get("game_freak_presents", {})
	if entry.is_empty():
		return {"ok": true, "message": "No GameFreak Presents art on this cartridge."}
	var gfx: int = int(entry.get("gfx", -1))
	var bytes: int = RomLayout.PRESENTS_GFX_TILES * Gen2Tiles.TILE_1BPP_BYTES
	if not rom.in_bounds(gfx, bytes):
		return {"ok": false, "message": "The GameFreak logo graphic is outside the cartridge."}
	# "GAME FREAK" is capitals on the top seven rows of its tiles, which is what
	# pins the run to a byte rather than to a tile.
	if rom.u8(gfx) == 0 or rom.u8(gfx + Gen2Tiles.TILE_1BPP_BYTES - 1) != 0:
		return {"ok": false, "message": "The GameFreak word strip does not start on a tile."}
	for tile: int in RomLayout.PRESENTS_WORD_TILES:
		if not _tile_1bpp_has_ink(rom, gfx, tile):
			return {
				"ok": false,
				"message": "GameFreak word tile %d is blank." % tile,
			}
	for index: int in RomLayout.PRESENTS_SECOND_WORD_TILES:
		var tile: int = RomLayout.PRESENTS_SECOND_WORD_FIRST + index
		for row: int in RomLayout.PRESENTS_SECOND_WORD_CLEAR_ROWS:
			if rom.u8(gfx + tile * Gen2Tiles.TILE_1BPP_BYTES + row) != 0:
				return {
					"ok": false,
					"message": "\"PRESENTS\" tile %d has ink on row %d." % [tile, row],
				}
	if _tile_1bpp_has_ink(rom, gfx, RomLayout.PRESENTS_WORD_TILES):
		return {"ok": false, "message": "The GameFreak logo's first tile is not blank."}
	var logo_ink: bool = false
	for index: int in RomLayout.PRESENTS_LOGO_TILES:
		if _tile_1bpp_has_ink(rom, gfx, RomLayout.PRESENTS_WORD_TILES + index):
			logo_ink = true
			break
	if not logo_ink:
		return {"ok": false, "message": "The GameFreak logo graphic is blank."}

	var palette: Dictionary = _verify_presents_palettes(rom, entry)
	if not palette["ok"]:
		return palette
	return _verify_presents_sprites(rom, entry)


## The star and sparkle strip on Gold and Silver, the Ditto sheet on Crystal.
## Neither profile carries the other's, and a -1 says so.
static func _verify_presents_sprites(rom: RomFile, entry: Dictionary) -> Dictionary:
	var stars: int = int(entry.get("stars", -1))
	if stars >= 0:
		if not rom.in_bounds(stars, RomLayout.PRESENTS_STARS_TILES * Gen2Tiles.TILE_BYTES):
			return {"ok": false, "message": "The splash star graphic is outside the cartridge."}
		# splash.asm INCBINs the stars directly behind the logo, so the two pin
		# each other.
		var after: int = int(entry.get("gfx", -1)) \
			+ RomLayout.PRESENTS_GFX_TILES * Gen2Tiles.TILE_1BPP_BYTES
		if stars != after:
			return {
				"ok": false,
				"message": "The splash stars are not behind the logo graphic.",
			}
		for index: int in RomLayout.PRESENTS_STAR_TILES:
			if _tile_2bpp_lit(rom, stars, index) == 0:
				return {"ok": false, "message": "Splash star tile %d is blank." % index}
		# `.Frameset_GSGameFreakLogoSparkle` runs its three tiles as one spark
		# closing in on its own centre, so tile n is blank across its outer n rows
		# top and bottom and lit on the two just inside them, and each carries
		# fewer lit pixels than the one before.
		var last_lit: int = Gen2Tiles.TILE_PIXELS + 1
		for index: int in RomLayout.PRESENTS_SPARKLE_TILES:
			var tile: int = RomLayout.PRESENTS_STAR_TILES + index
			for row: int in Gen2Tiles.TILE_HEIGHT:
				var edge: bool = row < index or row >= Gen2Tiles.TILE_HEIGHT - index
				var rim: bool = row == index or row == Gen2Tiles.TILE_HEIGHT - 1 - index
				var lit_row: bool = _row_2bpp_lit(rom, stars, tile, row)
				if edge == lit_row or (rim and not lit_row):
					return {
						"ok": false,
						"message": "Sparkle tile %d row %d does not close in." % [
							index, row,
						],
					}
			var lit: int = _tile_2bpp_lit(rom, stars, tile)
			if lit >= last_lit:
				return {
					"ok": false,
					"message": "Sparkle tile %d is not smaller than the one before." % index,
				}
			last_lit = lit
		return {"ok": true, "message": "GameFreak Presents verified."}

	var ditto: int = int(entry.get("ditto", -1))
	if ditto < 0:
		return {"ok": false, "message": "This cartridge has neither a splash star nor a Ditto."}
	var sheet: PackedByteArray = Gen2Lz.new().decompress(rom.bytes(), ditto)
	var wanted: int = RomLayout.PRESENTS_DITTO_TILES * Gen2Tiles.TILE_BYTES
	if sheet.size() != wanted:
		return {
			"ok": false,
			"message": "The Ditto graphic decompressed to %d bytes, wanted %d." % [
				sheet.size(), wanted,
			],
		}
	# Every `SPRITE_ANIM_OAMSET_GAMEFREAK_LOGO_*` base has to land on a drawn
	# part of the sheet, and the sheet's own first tile is the blank corner
	# above the Ditto.
	if _sheet_tile_lit(sheet, 0) != 0:
		return {"ok": false, "message": "The Ditto sheet's first tile is not blank."}
	for base: int in PRESENTS_DITTO_OAM_BASES:
		var ink: bool = false
		for row: int in 6:
			for column: int in 4:
				var tile: int = (base + row * RomLayout.PRESENTS_DITTO_COLUMNS + column) & 0xFF
				if _sheet_tile_lit(sheet, tile) > 0:
					ink = true
					break
			if ink:
				break
		if not ink:
			return {
				"ok": false,
				"message": "The Ditto sheet is blank at OAM base $%02X." % base,
			}
	return {"ok": true, "message": "GameFreak Presents verified."}


## The object palette both profiles share, and Crystal's two Ditto palettes. The
## fade opens on the colour the Ditto is already wearing, which is what ties the
## two together rather than checking each alone.
static func _verify_presents_palettes(rom: RomFile, entry: Dictionary) -> Dictionary:
	var object_palette: int = int(entry.get("object_palette", -1))
	var size: int = Gen2Palette.COLOR_BYTES
	if not rom.in_bounds(object_palette, PRESENTS_OBJECT_COLORS.size() * size):
		return {"ok": false, "message": "The splash object palette is outside the cartridge."}
	for index: int in PRESENTS_OBJECT_COLORS.size():
		var stored: int = rom.u16le(object_palette + index * size)
		if stored != PRESENTS_OBJECT_COLORS[index]:
			return {
				"ok": false,
				"message": "Splash object colour %d is $%04X, expected $%04X." % [
					index, stored, PRESENTS_OBJECT_COLORS[index],
				],
			}
	var ditto_palette: int = int(entry.get("ditto_palette", -1))
	if ditto_palette < 0:
		return {"ok": true, "message": "Splash palettes verified."}
	if not rom.in_bounds(ditto_palette, PRESENTS_DITTO_COLORS.size() * size):
		return {"ok": false, "message": "The Ditto palette is outside the cartridge."}
	for index: int in PRESENTS_DITTO_COLORS.size():
		var stored: int = rom.u16le(ditto_palette + index * size)
		if stored != PRESENTS_DITTO_COLORS[index]:
			return {
				"ok": false,
				"message": "Ditto colour %d is $%04X, expected $%04X." % [
					index, stored, PRESENTS_DITTO_COLORS[index],
				],
			}
	var fade: int = int(entry.get("ditto_fade", -1))
	if not rom.in_bounds(fade, RomLayout.PRESENTS_DITTO_FADE_COLORS * size):
		return {"ok": false, "message": "The Ditto fade palette is outside the cartridge."}
	# splash.asm INCLUDEs the fade directly in front of `GameFreakLogoGFX`, so
	# the two pin each other.
	if fade + RomLayout.PRESENTS_DITTO_FADE_COLORS * size != int(entry.get("gfx", -1)):
		return {
			"ok": false,
			"message": "The Ditto fade is not in front of the logo graphic.",
		}
	if rom.u16le(fade) != PRESENTS_DITTO_COLORS[RomLayout.PRESENTS_DITTO_FADE_COLOR]:
		return {
			"ok": false,
			"message": "The Ditto fade does not open on the Ditto's own colour.",
		}
	# Pink to orange, one colour per step: blue falls and green rises the whole
	# way, which no neighbouring palette run does for sixteen entries.
	var last: Vector2i = Vector2i(-1, 32)
	for index: int in RomLayout.PRESENTS_DITTO_FADE_COLORS:
		var packed: int = rom.u16le(fade + index * size)
		var green: int = (packed >> 5) & 0x1F
		var blue: int = (packed >> 10) & 0x1F
		if green < last.x or blue > last.y:
			return {
				"ok": false,
				"message": "Ditto fade colour %d does not run pink to orange." % index,
			}
		last = Vector2i(green, blue)
	return {"ok": true, "message": "Splash palettes verified."}


## `GSTitleOBPals` (`gfx/title/title_fg.pal`), which Gold and Silver share: a
## white and three copies of one dark grey, then the yellow pair the bird is
## drawn in. Three identical colours in a row is what makes it unmistakable.
const TITLE_OB_COLORS: Array[int] = [
	0x7FFF, 0x0CC7, 0x0CC7, 0x0CC7, 0x7FFF, 0x03FF, 0x02DA, 0x0000,
]

## The first colour of `GSTitleBGPals`, which is white on both profiles, and of
## Crystal's own `TitleScreenPalettes`, which is not: its first palette is the
## copyright line's, black on a black background.
const TITLE_BG_FIRST_COLOR: int = 0x7FFF
const TITLE_CRYSTAL_FIRST_COLORS: Array[int] = [0x0000, 0x0013, 0x7D0F, 0x7D0F]

## How far past the end of an LZ run its neighbour may start. The INCBIN'd `.lz`
## files carry a few bytes past the terminator `Decompress` stops on, so the
## symbols in a section are consecutive without being flush.
const TITLE_RUN_GAP_MAX: int = 16


## The title screen's art, which is two different screens under one key.
##
## Crystal's three LZ runs and its palettes are one contiguous section in
## `engine/movie/title.asm`'s INCBIN order, so each pins the next: a run that
## decompresses to the wrong number of tiles, or whose neighbour does not follow
## it, is not the one being looked for. Gold and Silver's logo halves pin their
## tilemap the same way, and their trail pins the bird behind it.
static func verify_title(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout.get("title", {})
	if entry.is_empty():
		return {"ok": true, "message": "No title screen art on this cartridge."}
	if int(entry.get("suicune", -1)) >= 0:
		return _verify_crystal_title(rom, entry)
	return _verify_gs_title(rom, entry)


## `TitleSuicuneGFX`, `TitleLogoGFX`, `TitleCrystalGFX` and
## `TitleScreenPalettes`, in that order and nothing between them.
static func _verify_crystal_title(rom: RomFile, entry: Dictionary) -> Dictionary:
	var runs: Array = [
		["suicune", int(entry["suicune"]), RomLayout.TITLE_SUICUNE_TILES],
		["logo", int(entry["logo"]), RomLayout.TITLE_LOGO_TILES],
		["crystal", int(entry["crystal"]), RomLayout.TITLE_CRYSTAL_TILES],
	]
	var sheets: Dictionary = {}
	for run: Array in runs:
		var unpacked: Dictionary = _verify_title_run(rom, String(run[0]), int(run[1]), int(run[2]))
		if not unpacked["ok"]:
			return unpacked
		sheets[run[0]] = unpacked["sheet"]
		var next: int = int(unpacked["end"])
		var follows: int = int(entry["palettes"]) if run[0] == "crystal" else int(
			entry["logo"] if run[0] == "suicune" else entry["crystal"]
		)
		if follows < next or follows - next > TITLE_RUN_GAP_MAX:
			return {
				"ok": false,
				"message": "The title %s run does not end in front of the next symbol." % run[0],
			}

	# `InitializeBackground` builds thirty 8x16 objects out of the crystal, so
	# the sheet is a column with blank corners rather than a rectangle.
	var crystal: PackedByteArray = sheets["crystal"]
	if _sheet_tile_lit(crystal, 0) != 0 or _sheet_tile_lit(crystal, 1) == 0:
		return {"ok": false, "message": "The title crystal does not open on a blank corner."}

	var suicune: PackedByteArray = sheets["suicune"]
	# `LoadSuicuneFrame` draws six rows of eight from each of `.Frames`' bases,
	# which are two sheets of 128 tiles apart. Every frame has to be drawn on.
	for base: int in [0x00, 0x08, 0x80, 0x88]:
		var ink: bool = false
		for row: int in 6:
			for column: int in 8:
				if _sheet_tile_lit(suicune, base + row * 16 + column) > 0:
					ink = true
					break
			if ink:
				break
		if not ink:
			return {"ok": false, "message": "The Suicune sheet is blank at frame $%02X." % base}

	var palettes: int = int(entry["palettes"])
	var size: int = Gen2Palette.COLOR_BYTES
	if not rom.in_bounds(palettes, RomLayout.TITLE_PALETTES * RomLayout.TITLE_PALETTE_COLORS * size):
		return {"ok": false, "message": "The title palettes are outside the cartridge."}
	for index: int in TITLE_CRYSTAL_FIRST_COLORS.size():
		var stored: int = rom.u16le(palettes + index * size)
		if stored != TITLE_CRYSTAL_FIRST_COLORS[index]:
			return {
				"ok": false,
				"message": "Title colour %d is $%04X, expected $%04X." % [
					index, stored, TITLE_CRYSTAL_FIRST_COLORS[index],
				],
			}
	return {"ok": true, "message": "Title screen verified."}


## `TitleScreenGFX1` and `GFX2` over `TitleScreenTilemap`, and `GFX3`'s raw trail
## in front of `GFX4`'s bird.
static func _verify_gs_title(rom: RomFile, entry: Dictionary) -> Dictionary:
	var bottom: Dictionary = _verify_title_run(
		rom, "logo bottom", int(entry["logo_bottom"]), RomLayout.TITLE_LOGO_BOTTOM_TILES
	)
	if not bottom["ok"]:
		return bottom
	var top_at: int = int(entry["logo_top"])
	if top_at < int(bottom["end"]) or top_at - int(bottom["end"]) > TITLE_RUN_GAP_MAX:
		return {"ok": false, "message": "The title logo's halves are not consecutive."}
	var top: Dictionary = _verify_title_run(
		rom, "logo top", top_at, RomLayout.TITLE_LOGO_TOP_TILES
	)
	if not top["ok"]:
		return top
	# `--trim-whitespace` takes the bottom half down from 120 tiles to 112 by
	# dropping blank tiles off the end, so its last tile is drawn on. A run of the
	# right length whose tail is blank is a different graphic.
	if _sheet_tile_lit(bottom["sheet"], RomLayout.TITLE_LOGO_BOTTOM_TILES - 1) == 0:
		return {"ok": false, "message": "The title logo's bottom half ends on a blank tile."}

	var tilemap_at: int = int(entry["tilemap"])
	if tilemap_at < int(top["end"]) or tilemap_at - int(top["end"]) > TITLE_RUN_GAP_MAX:
		return {"ok": false, "message": "The title tilemap does not follow the logo."}
	var tilemap: PackedByteArray = read_title_tilemap(rom, {"title": entry})
	if tilemap.is_empty():
		return {"ok": false, "message": "The title tilemap has no terminator in range."}
	if tilemap.size() % RomLayout.TITLE_TILEMAP_COLUMNS != 0:
		return {
			"ok": false,
			"message": "The title tilemap is %d bytes, not whole rows." % tilemap.size(),
		}

	var trail: int = int(entry["trail"])
	var trail_tiles: int = int(entry["trail_tiles"])
	if not rom.in_bounds(trail, trail_tiles * Gen2Tiles.TILE_BYTES):
		return {"ok": false, "message": "The title trail is outside the cartridge."}
	for tile: int in RomLayout.TITLE_TRAIL_DRAWN_TILES:
		if _tile_2bpp_lit(rom, trail, tile) == 0:
			return {"ok": false, "message": "Title trail tile %d is blank." % tile}
	# Gold's own run is eight tiles, and the four past the trail are the
	# whitespace the source names at its `FarCopyBytes`.
	for index: int in trail_tiles - RomLayout.TITLE_TRAIL_DRAWN_TILES:
		var tile: int = RomLayout.TITLE_TRAIL_DRAWN_TILES + index
		if _tile_2bpp_lit(rom, trail, tile) != 0:
			return {"ok": false, "message": "Title trail tile %d is not blank." % tile}
	# The bird starts where the trail's own tiles stop, which is what pins it.
	var bird_at: int = trail + trail_tiles * Gen2Tiles.TILE_BYTES
	if int(entry["bird"]) != bird_at:
		return {"ok": false, "message": "The title bird is not behind the trail."}
	var bird: Dictionary = _verify_title_run(
		rom, "bird", bird_at, int(entry["bird_tiles"])
	)
	if not bird["ok"]:
		return bird

	var size: int = Gen2Palette.COLOR_BYTES
	var bg: int = int(entry["bg_palette"])
	var ob: int = int(entry["ob_palette"])
	if not rom.in_bounds(bg, RomLayout.TITLE_BG_PALETTES * RomLayout.TITLE_PALETTE_COLORS * size):
		return {"ok": false, "message": "The title palettes are outside the cartridge."}
	if ob != bg + RomLayout.TITLE_BG_PALETTES * RomLayout.TITLE_PALETTE_COLORS * size:
		return {"ok": false, "message": "The title object palettes do not follow the background's."}
	if rom.u16le(bg) != TITLE_BG_FIRST_COLOR:
		return {"ok": false, "message": "The title background palette does not open on white."}
	for index: int in TITLE_OB_COLORS.size():
		var stored: int = rom.u16le(ob + index * size)
		if stored != TITLE_OB_COLORS[index]:
			return {
				"ok": false,
				"message": "Title object colour %d is $%04X, expected $%04X." % [
					index, stored, TITLE_OB_COLORS[index],
				],
			}
	return {"ok": true, "message": "Title screen verified."}


## One LZ run, checked for decompressing to exactly [param tiles] tiles.
## Answers the decompressed sheet and the offset one past the run's terminator,
## which is what pins whatever the section puts behind it.
static func _verify_title_run(
	rom: RomFile, name: String, at: int, tiles: int
) -> Dictionary:
	if at < 0:
		return {"ok": false, "message": "The title %s has no address." % name}
	var lz := Gen2Lz.new()
	var sheet: PackedByteArray = lz.decompress(rom.bytes(), at)
	var wanted: int = tiles * Gen2Tiles.TILE_BYTES
	if sheet.size() != wanted:
		return {
			"ok": false,
			"message": "The title %s decompressed to %d bytes, wanted %d." % [
				name, sheet.size(), wanted,
			],
		}
	return {"ok": true, "sheet": sheet, "end": at + lz.consumed}


## The region map, identified by content rather than by bounds.
##
## The two region tilemaps pin the graphic they are drawn out of: every one of
## their 720 cells names a tile inside `TownMapGFX`'s 48, which no unrelated
## 360-byte run does, and each ends on its own `-1`. The palette map is checked
## the same way, against the six palettes it selects between, and the palette run
## by the off-white all six open on. The landmark table checks its two ends and
## every name pointer in between: `SPECIAL` sits at (0,0) with the only zeroed
## record, the last row is the Fast Ship, and a pointer that leaves the table's
## own bank is not a name.
static func verify_town_map(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout.get("town_map", {})
	if entry.is_empty():
		return {"ok": true, "message": "No region map on this cartridge."}

	for run: Array in [
		["town map graphic", int(entry["gfx"]), RomLayout.TOWN_MAP_TILES],
		["Pokegear graphic", int(entry["pokegear_gfx"]), RomLayout.POKEGEAR_TILES],
		["Pokegear sprites", int(entry["sprites"]), RomLayout.POKEGEAR_SPRITE_TILES],
	]:
		var lz := Gen2Lz.new()
		var sheet: PackedByteArray = lz.decompress(rom.bytes(), int(run[1]))
		var wanted: int = int(run[2]) * Gen2Tiles.TILE_BYTES
		if sheet.size() != wanted:
			return {
				"ok": false,
				"message": "The %s decompressed to %d bytes, wanted %d." % [
					run[0], sheet.size(), wanted,
				],
			}

	var fast_ship: int = int(entry.get("fast_ship", -1))
	if not rom.in_bounds(fast_ship, RomLayout.FAST_SHIP_TILES * Gen2Tiles.TILE_BYTES):
		return {"ok": false, "message": "The Fast Ship icon is outside the cartridge."}

	for region: String in ["johto", "kanto"]:
		var cells: PackedByteArray = read_town_map_region(rom, layout, region)
		if cells.size() != RomLayout.TOWN_MAP_REGION_CELLS:
			return {
				"ok": false,
				"message": "The %s map is %d cells, wanted %d." % [
					region, cells.size(), RomLayout.TOWN_MAP_REGION_CELLS,
				],
			}
		for cell: int in cells:
			if cell >= RomLayout.TOWN_MAP_TILES:
				return {
					"ok": false,
					"message": "The %s map names tile $%02X, past its %d tiles." % [
						region, cell, RomLayout.TOWN_MAP_TILES,
					],
				}

	var nest_check: Dictionary = verify_dex_nest_icon(rom, layout)
	if not bool(nest_check["ok"]):
		return nest_check

	var cards: Dictionary = read_pokegear_cards(rom, layout)
	if cards.size() != RomLayout.POKEGEAR_CARD_ORDER.size():
		return {
			"ok": false,
			"message": "The Pokegear cards decoded to %d tilemaps, wanted %d." % [
				cards.size(), RomLayout.POKEGEAR_CARD_ORDER.size(),
			],
		}
	for name: String in cards:
		for cell: int in cards[name] as PackedByteArray:
			# Every card is drawn out of the same VRAM window the region map is,
			# so a tile past the two sheets and the font is a wrong offset.
			if cell >= RomLayout.POKEGEAR_FIRST_TILE + RomLayout.POKEGEAR_TILES \
				and cell < Gen2Text.SPACE:
				return {
					"ok": false,
					"message": "The %s card names tile $%02X, past its sheets." % [
						name, cell,
					],
				}

	var texts: Dictionary = read_pokegear_texts(rom, layout)
	if texts.size() != RomLayout.POKEGEAR_TEXT_NAMES.size():
		return {"ok": false, "message": "The Pokegear texts did not decode."}
	for name: String in texts:
		if String(texts[name]).is_empty():
			return {"ok": false, "message": "Pokegear text %s is empty." % name}

	var palette_map: int = int(entry["palette_map"])
	if not rom.in_bounds(palette_map, RomLayout.TOWN_MAP_PALETTE_MAP_BYTES):
		return {"ok": false, "message": "The region palette map is outside the cartridge."}
	for index: int in RomLayout.TOWN_MAP_PALETTE_MAP_BYTES:
		var packed: int = rom.u8(palette_map + index)
		if (packed & 0x0F) >= RomLayout.TOWN_MAP_PALETTES \
			or (packed >> 4) >= RomLayout.TOWN_MAP_PALETTES:
			return {
				"ok": false,
				"message": "Region palette map byte %d is $%02X, past its %d palettes." % [
					index, packed, RomLayout.TOWN_MAP_PALETTES,
				],
			}

	for name: String in ["palette", "palette_female"]:
		var at: int = int(entry.get(name, -1))
		if at < 0:
			continue
		var colors: int = RomLayout.TOWN_MAP_PALETTES * RomLayout.TOWN_MAP_PALETTE_COLORS
		if not rom.in_bounds(at, colors * Gen2Palette.COLOR_BYTES):
			return {"ok": false, "message": "The region %s is outside the cartridge." % name}
		for palette: int in RomLayout.TOWN_MAP_PALETTES:
			var first: int = rom.u16le(
				at + palette * RomLayout.TOWN_MAP_PALETTE_COLORS * Gen2Palette.COLOR_BYTES
			)
			if first != RomLayout.TOWN_MAP_PALETTE_FIRST_COLOR:
				return {
					"ok": false,
					"message": "Region %s %d opens on $%04X, expected $%04X." % [
						name, palette, first, RomLayout.TOWN_MAP_PALETTE_FIRST_COLOR,
					],
				}

	return verify_landmarks(rom, layout)


## `PokedexNestIconGFX` is one tile with no header and no neighbour to pin it
## against, so it is identified by content: every one of its eight rows carries
## ink and every plane byte is its own bit reversal, the icon being symmetric
## about its vertical axis. No other tile behind `KantoMap` is both.
static func verify_dex_nest_icon(rom: RomFile, layout: Dictionary) -> Dictionary:
	var at: int = RomLayout.dex_nest_icon_offset(layout)
	if not rom.in_bounds(at, RomLayout.DEX_NEST_ICON_TILES * Gen2Tiles.TILE_BYTES):
		return {"ok": false, "message": "The dex nest icon is outside the cartridge."}
	for row: int in Gen2Tiles.TILE_HEIGHT:
		var low: int = rom.u8(at + row * 2)
		var high: int = rom.u8(at + row * 2 + 1)
		if (low | high) == 0:
			return {"ok": false, "message": "Dex nest icon row %d is blank." % row}
		for plane: int in [low, high]:
			if _reverse_byte(plane) != plane:
				return {
					"ok": false,
					"message": "Dex nest icon row %d is not symmetric." % row,
				}
	return {"ok": true, "message": ""}


static func _reverse_byte(value: int) -> int:
	var out: int = 0
	for bit: int in 8:
		out = (out << 1) | ((value >> bit) & 1)
	return out


static func verify_landmarks(rom: RomFile, layout: Dictionary) -> Dictionary:
	var count: int = RomLayout.landmark_count(layout)
	var bank: int = RomLayout.bank_of(RomLayout.landmark_offset(layout, 0))
	if not rom.in_bounds(
		RomLayout.landmark_offset(layout, 0), count * RomLayout.LANDMARK_RECORD_SIZE
	):
		return {"ok": false, "message": "The landmark table is outside the cartridge."}
	for index: int in count:
		var record: int = RomLayout.landmark_offset(layout, index)
		var at: int = RomLayout.landmark_name_offset(rom, layout, index)
		if RomLayout.bank_of(at) != bank:
			return {
				"ok": false,
				"message": "Landmark %d's name pointer leaves bank $%02X." % [index, bank],
			}
		var zeroed: bool = rom.u8(record) == 0 and rom.u8(record + 1) == 0
		if zeroed != (index == 0):
			return {
				"ok": false,
				"message": "Landmark %d is at (0,0); only LANDMARK_SPECIAL is." % index,
			}
	var first: String = Gen2Text.decode(
		rom.bytes(), RomLayout.landmark_name_offset(rom, layout, 0),
		RomLayout.LANDMARK_NAME_BYTES
	)
	if first != "SPECIAL":
		return {"ok": false, "message": "Landmark 0: expected SPECIAL, read %s." % first}
	var last: String = Gen2Text.decode(
		rom.bytes(), RomLayout.landmark_name_offset(rom, layout, count - 1),
		RomLayout.LANDMARK_NAME_BYTES
	)
	if last != "FAST SHIP":
		return {
			"ok": false,
			"message": "Landmark %d: expected FAST SHIP, read %s." % [count - 1, last],
		}
	return {"ok": true, "message": "Region map verified."}


## `OakRatings`, identified by content: nineteen rows whose thresholds ascend and
## whose last is every species, each naming a text stub inside the table's own
## bank, and the five stubs around it that are `text_far` and nothing else.
static func verify_oak_ratings(rom: RomFile, layout: Dictionary) -> Dictionary:
	var table: int = int(layout.get("oak_ratings", -1))
	if not rom.in_bounds(
		table, RomLayout.OAK_RATING_COUNT * RomLayout.OAK_RATING_SIZE
	):
		return {"ok": false, "message": "The Oak rating table is outside the cartridge."}
	var bank: int = RomLayout.bank_of(table)
	var previous: int = -1
	for index: int in RomLayout.OAK_RATING_COUNT:
		var row: int = RomLayout.oak_rating_offset(layout, index)
		var threshold: int = rom.u8(row)
		if threshold <= previous:
			return {
				"ok": false,
				"message": "Oak rating %d's threshold %d does not follow %d." % [
					index, threshold, previous,
				],
			}
		previous = threshold
		if RomLayout.bank_of(RomFile.linear(bank, rom.u16le(row + 3))) != bank:
			return {
				"ok": false,
				"message": "Oak rating %d's text leaves bank $%02X." % [index, bank],
			}
	if previous != RomLayout.OAK_RATING_LAST_THRESHOLD:
		return {
			"ok": false,
			"message": "The last Oak rating stops at %d, not %d." % [
				previous, RomLayout.OAK_RATING_LAST_THRESHOLD,
			],
		}
	for name: String in RomLayout.OAK_TEXT_STUBS:
		if read_oak_text(rom, layout, RomLayout.oak_text_stub_offset(rom, layout, name)).is_empty():
			return {"ok": false, "message": "Oak's %s text did not decode." % name}
	return {"ok": true, "message": "Prof Oak's PC verified."}


## `PokemonCenterPC`'s five row strings and the six `text_far` stubs behind
## them, identified by content: the run has to end on TURN OFF and every stub
## has to decode, which is what says the one pinned address is right.
static func verify_pokecenter_pc(rom: RomFile, layout: Dictionary) -> Dictionary:
	var rows: PackedStringArray = read_pokecenter_pc_rows(rom, layout)
	if rows.size() != RomLayout.POKECENTER_PC_ROWS.size():
		return {"ok": false, "message": "The Pokemon Center PC's rows are outside the cartridge."}
	if read_pokecenter_pc_lists(rom, layout).size() != RomLayout.POKECENTER_PC_LISTS \
		or read_pokecenter_pc_rows(rom, layout, true).size() \
			!= RomLayout.POKECENTER_PC_PLAYERS_ROWS.size() \
		or read_pokecenter_pc_lists(rom, layout, true).size() \
			!= RomLayout.POKECENTER_PC_PLAYERS_LISTS:
		return {"ok": false, "message": "The Pokemon Center PC's menu tables did not read."}
	if rows[rows.size() - 1] != "TURN OFF":
		return {
			"ok": false,
			"message": "The Pokemon Center PC's last row is \"%s\", not TURN OFF." % rows[
				rows.size() - 1
			],
		}
	for name: String in RomLayout.POKECENTER_PC_TEXT_AT:
		if read_oak_text(
			rom, layout, RomLayout.pokecenter_pc_text_offset(layout, name)
		).is_empty():
			return {
				"ok": false,
				"message": "The Pokemon Center PC's %s text did not decode." % name,
			}
	return {"ok": true, "message": "The Pokemon Center PC verified."}


## `engine/items/mart.asm`'s own `text_far` stubs, identified by content: all
## twenty-nine have to decode and the standard welcome has to be the word the
## shop opens with, which is what says the one pinned address is right.
static func verify_mart_text(rom: RomFile, layout: Dictionary) -> Dictionary:
	for name: String in RomLayout.MART_TEXT_AT:
		if read_oak_text(rom, layout, RomLayout.mart_text_offset(layout, name)).is_empty():
			return {"ok": false, "message": "The mart's %s text did not decode." % name}
	var welcome: String = read_oak_text(
		rom, layout, RomLayout.mart_text_offset(layout, "welcome")
	)
	if not welcome.begins_with("Welcome!"):
		return {
			"ok": false,
			"message": "The mart's welcome text is \"%s\", not the shop's own." % welcome,
		}
	return {"ok": true, "message": "The mart's texts verified."}


## `engine/events/name_rater.asm`'s ten `text_far` stubs, identified by content
## the way the mart's are: all ten have to decode and the routine's opening line
## has to be the one he introduces himself with.
static func verify_name_rater_text(rom: RomFile, layout: Dictionary) -> Dictionary:
	for name: String in RomLayout.NAME_RATER_TEXT_ORDER:
		if read_oak_text(rom, layout, RomLayout.name_rater_text_offset(layout, name)).is_empty():
			return {
				"ok": false, "message": "The Name Rater's %s text did not decode." % name,
			}
	var hello: String = read_oak_text(
		rom, layout, RomLayout.name_rater_text_offset(layout, "hello")
	)
	if not hello.begins_with("Hello, hello!"):
		return {
			"ok": false,
			"message": "The Name Rater's hello text is \"%s\", not his own." % hello,
		}
	return {"ok": true, "message": "The Name Rater's texts verified."}


## `engine/events/move_deleter.asm`'s eight `text_far` stubs, identified by
## content the same way.
static func verify_move_deleter_text(rom: RomFile, layout: Dictionary) -> Dictionary:
	for name: String in RomLayout.MOVE_DELETER_TEXT_ORDER:
		if read_oak_text(
			rom, layout, RomLayout.move_deleter_text_offset(layout, name)
		).is_empty():
			return {
				"ok": false, "message": "The move deleter's %s text did not decode." % name,
			}
	var intro: String = read_oak_text(
		rom, layout, RomLayout.move_deleter_text_offset(layout, "intro")
	)
	if not intro.contains("MOVE DELETER"):
		return {
			"ok": false,
			"message": "The move deleter's intro is \"%s\", not his own." % intro,
		}
	return {"ok": true, "message": "The move deleter's texts verified."}


## The Day-Care's thirty-two `text_far` stubs across its four runs, identified
## by content the same way: every stub has to decode and the man's opening line
## has to be his own, which is what says the four pins are the four runs.
static func verify_day_care_text(rom: RomFile, layout: Dictionary) -> Dictionary:
	for name: String in day_care_text_names():
		if read_oak_text(
			rom, layout, RomLayout.day_care_text_offset(layout, name)
		).is_empty():
			return {
				"ok": false, "message": "The Day-Care's %s text did not decode." % name,
			}
	var intro: String = read_oak_text(
		rom, layout, RomLayout.day_care_text_offset(layout, "man_intro")
	)
	if not intro.begins_with("I'm the DAY-CARE"):
		return {
			"ok": false,
			"message": "The Day-Care man's intro is \"%s\", not his own." % intro,
		}
	return {"ok": true, "message": "The Day-Care's texts verified."}


## Every stub name across the four runs, in run order.
static func day_care_text_names() -> Array[String]:
	var out: Array[String] = []
	for run: Array in RomLayout.DAY_CARE_TEXT_RUNS:
		for name: Variant in run[1] as Array:
			out.append(String(name))
	return out


## `UnownWords`, twenty-six words in form order, A first. Empty on any failure,
## since a half table would give the dex a blank word rather than a wrong
## address.
static func read_unown_words(rom: RomFile, layout: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for form: int in range(1, RomLayout.UNOWN_WORD_ENTRIES):
		var at: int = RomLayout.unown_word_offset(rom, layout, form)
		if at < 0 or not rom.in_bounds(at, RomLayout.UNOWN_WORD_MAX_LENGTH):
			return PackedStringArray()
		var word: String = ""
		for step: int in RomLayout.UNOWN_WORD_MAX_LENGTH:
			var code: int = rom.u8(at + step)
			if code == RomLayout.UNOWN_WORD_TERMINATOR:
				break
			var letter: int = code - RomLayout.FIRST_UNOWN_CHAR
			if letter < 0 or letter >= RomLayout.UNOWN_FORMS:
				return PackedStringArray()
			word += char("A".unicode_at(0) + letter)
		if word.is_empty():
			return PackedStringArray()
		out.append(word)
	return out


## The words, plus the two things that say the table is where the layout says:
## its zeroth entry is form A's again, and the run starts where the table ends.
static func verify_unown_words(rom: RomFile, layout: Dictionary) -> Dictionary:
	var words: PackedStringArray = read_unown_words(rom, layout)
	if words.size() != RomLayout.UNOWN_FORMS:
		return {"ok": false, "message": "The Unown words did not decode."}
	var table: int = int(layout.get("unown_words", -1))
	var first: int = RomLayout.unown_word_offset(rom, layout, 0)
	if first != RomLayout.unown_word_offset(rom, layout, 1):
		return {"ok": false, "message": "The Unown word table does not open on form A twice."}
	if first != table + RomLayout.UNOWN_WORD_ENTRIES * RomLayout.UNOWN_WORD_POINTER_SIZE:
		return {"ok": false, "message": "The Unown words do not follow their own table."}
	for form: int in RomLayout.UNOWN_FORMS:
		if not words[form].begins_with(char("A".unicode_at(0) + form)):
			return {
				"ok": false,
				"message": "Unown word %d is \"%s\", which is not its own letter." % [
					form, words[form],
				],
			}
	return {"ok": true, "message": "Unown words verified."}


## `UnownWalls`, the four chamber words in `UNOWNWORDS_*` order. Empty on a dump
## that does not ship them, which is Gold and Silver, and on any failure.
static func read_unown_walls(rom: RomFile, layout: Dictionary) -> PackedStringArray:
	var at: int = int(layout.get("unown_walls", -1))
	if at < 0 or not rom.in_bounds(at, RomLayout.UNOWN_WALL_COUNT * RomLayout.UNOWN_WALL_MAX_LENGTH):
		return PackedStringArray()
	var out: PackedStringArray = PackedStringArray()
	for wall: int in RomLayout.UNOWN_WALL_COUNT:
		var word: String = ""
		for step: int in RomLayout.UNOWN_WALL_MAX_LENGTH:
			var code: int = rom.u8(at)
			at += 1
			if code == RomLayout.UNOWN_WALL_TERMINATOR:
				break
			var letter: String = RomLayout.unown_wall_letter(code)
			if letter.is_empty():
				return PackedStringArray()
			word += letter
		if word.is_empty():
			return PackedStringArray()
		out.append(word)
	return out


## The four words, by shape and by the one the Kabuto chamber's own `setval`
## names. A dump without the table reads as none rather than as four wrong words.
static func verify_unown_walls(rom: RomFile, layout: Dictionary) -> Dictionary:
	if int(layout.get("unown_walls", -1)) < 0:
		return {"ok": true, "message": "No Unown walls in this dump."}
	var walls: PackedStringArray = read_unown_walls(rom, layout)
	if walls.size() != RomLayout.UNOWN_WALL_COUNT:
		return {"ok": false, "message": "The Unown wall words did not decode."}
	if walls[RomLayout.UNOWNWORDS_ESCAPE] != "ESCAPE":
		return {
			"ok": false,
			"message": "The first Unown wall reads \"%s\", not the word UNOWNWORDS_ESCAPE names." % [
				walls[RomLayout.UNOWNWORDS_ESCAPE],
			],
		}
	var seen: Dictionary = {}
	for word: String in walls:
		if seen.has(word):
			return {"ok": false, "message": "Two Unown walls read \"%s\"." % word}
		seen[word] = true
	return {"ok": true, "message": "Unown walls verified."}


## One of the two row runs, in the source's own order. Empty when the run is out
## of bounds, which is what a wrong address gives.
static func read_pokecenter_pc_rows(
	rom: RomFile, layout: Dictionary, players: bool = false
) -> PackedStringArray:
	var at: int = _pokecenter_pc_rows_at(layout, players)
	var count: int = RomLayout.POKECENTER_PC_PLAYERS_ROWS.size() if players \
		else RomLayout.POKECENTER_PC_ROWS.size()
	if at < 0 or not rom.in_bounds(at, count * RomLayout.POKECENTER_PC_ROW_MAX_BYTES):
		return PackedStringArray()
	return Gen2Text.decode_sequence(
		rom.bytes(), at, count, RomLayout.POKECENTER_PC_ROW_MAX_BYTES
	)


static func _pokecenter_pc_rows_at(layout: Dictionary, players: bool) -> int:
	var at: int = int(layout.get("pokecenter_pc", -1))
	if at < 0:
		return -1
	return at + RomLayout.POKECENTER_PC_PLAYERS_AT if players else at


## `.WhichPC` behind one of the row runs: each list is a count, that many row
## indices and a `-1`. Empty when a list runs off the end of the cartridge or
## names a row the run above does not have.
static func read_pokecenter_pc_lists(
	rom: RomFile, layout: Dictionary, players: bool = false
) -> Array:
	var at: int = _pokecenter_pc_rows_at(layout, players)
	var names: Array[String] = RomLayout.POKECENTER_PC_PLAYERS_ROWS if players \
		else RomLayout.POKECENTER_PC_ROWS
	if at < 0 or not rom.in_bounds(at, names.size() * RomLayout.POKECENTER_PC_ROW_MAX_BYTES):
		return []
	## `terminated_end` already answers past the `@`, which is where the next
	## string starts.
	for _row: String in names:
		at = Gen2Text.terminated_end(
			rom.bytes(), at, RomLayout.POKECENTER_PC_ROW_MAX_BYTES
		)
	var out: Array = []
	var lists: int = RomLayout.POKECENTER_PC_PLAYERS_LISTS if players \
		else RomLayout.POKECENTER_PC_LISTS
	for _list: int in lists:
		if not rom.in_bounds(at, 1):
			return []
		var count: int = rom.u8(at)
		if count <= 0 or count > names.size() or not rom.in_bounds(at, count + 2):
			return []
		var rows: Array = []
		for index: int in count:
			var row: int = rom.u8(at + 1 + index)
			if row >= names.size():
				return []
			rows.append(row)
		if rom.u8(at + 1 + count) != RomLayout.POKECENTER_PC_LIST_END:
			return []
		out.append(rows)
		at += count + 2
	return out


## One `text_far` stub, followed and decoded. Empty when the stub is not one,
## which is what a table that is not `OakRatings` produces.
static func read_oak_text(rom: RomFile, _layout: Dictionary, stub: int) -> String:
	if not rom.in_bounds(stub, RomLayout.OAK_TEXT_STUB_SIZE) \
		or rom.u8(stub) != Gen2TextStream.TX_FAR:
		return ""
	var at: int = RomFile.linear(rom.u8(stub + 3), rom.u16le(stub + 1))
	var decoded: Dictionary = Gen2WorldScript.decode_text(
		rom.slice(at, RomLayout.OAK_TEXT_MAX_BYTES)
	)
	if not bool(decoded.get("ok", false)):
		return ""
	return String(decoded["text"])


## `CrystalIntro`'s art section, walked whole from its one pinned address.
##
## Every entry is decompressed and its length checked against what the routine
## that loads it asks VRAM for, then the next entry's address is that length
## rounded up to [constant RomLayout.INTRO_ENTRY_ALIGN]. Thirty-five entries in a
## row landing on their exact sizes is what says the address is right; a walk
## that starts anywhere else fails inside the first two.
##
## Returns {name: PackedByteArray} in `INTRO_SECTION` order, or an empty
## Dictionary if any entry does not decompress to its own size.
static func read_intro_section(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout.get("intro_movie", {})
	var at: int = int(entry.get("section", -1))
	if at < 0:
		return {}
	var lz := Gen2Lz.new()
	var out: Dictionary = {}
	for row: Array in RomLayout.INTRO_SECTION:
		var name: String = String(row[0])
		var kind: String = String(row[1])
		var wanted: int = _intro_entry_bytes(kind, int(row[2]))
		var raw: PackedByteArray = PackedByteArray()
		var consumed: int = 0
		if kind == "pal" or kind == "raw":
			if not rom.in_bounds(at, wanted):
				return {}
			raw = rom.slice(at, wanted)
			consumed = wanted
		else:
			raw = lz.decompress(rom.bytes(), at)
			consumed = lz.consumed
			if lz.failed or raw.size() != wanted:
				return {}
		out[name] = raw
		at += _aligned(consumed, RomLayout.INTRO_ENTRY_ALIGN)
	return out


## `GoldSilverIntro`'s art section, walked the same way `CrystalIntro`'s is: one
## pinned address, each entry checked against the size the routine that loads it
## asks VRAM for, and the next address that size rounded up to
## [constant RomLayout.INTRO_ENTRY_ALIGN].
##
## The two `.tilemap`s and two `.bin`s are uncompressed and pret checks them in
## as binary, so their lengths are the file's rather than a tile count.
##
## Returns {name: PackedByteArray} in `GS_INTRO_SECTION` order, or an empty
## Dictionary if any entry does not decompress to its own size.
static func read_gs_intro_section(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout.get("gs_intro", {})
	var at: int = int(entry.get("section", -1))
	if at < 0:
		return {}
	var lz := Gen2Lz.new()
	var out: Dictionary = {}
	for row: Array in RomLayout.GS_INTRO_SECTION:
		var name: String = String(row[0])
		var raw_bytes: bool = String(row[1]) == "raw_bytes"
		var wanted: int = int(row[2]) if raw_bytes else int(row[2]) * Gen2Tiles.TILE_BYTES
		var raw: PackedByteArray = PackedByteArray()
		var consumed: int = 0
		if raw_bytes:
			if not rom.in_bounds(at, wanted):
				return {}
			raw = rom.slice(at, wanted)
			consumed = wanted
		else:
			raw = lz.decompress(rom.bytes(), at)
			consumed = lz.consumed
			if lz.failed or raw.size() != wanted:
				return {}
		out[name] = raw
		at += _aligned(consumed, RomLayout.INTRO_ENTRY_ALIGN)
	return out


static func _intro_entry_bytes(kind: String, tiles: int) -> int:
	match kind:
		"map", "attr":
			return RomLayout.INTRO_MAP_BYTES
		"pal":
			return RomLayout.INTRO_PALETTES * RomLayout.INTRO_PALETTE_COLORS \
				* Gen2Palette.COLOR_BYTES
		_:
			return tiles * Gen2Tiles.TILE_BYTES


static func _aligned(value: int, to: int) -> int:
	return ((value + to - 1) / to) * to


## The intro movie. The section walk above is most of the check; what is left is
## content, and the two palette runs INCLUDEd inside the code rather than in it.
##
## `unown_1.pal` is byte-identical to the first palette of `fade.pal`, which is
## the same "two INCLUDEs of one picture check each other" the copyright string
## gives the credits: the two are pinned independently, so each confirms the
## other's address for nothing.
static func verify_intro_movie(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout.get("intro_movie", {})
	if entry.is_empty() or int(entry.get("section", -1)) < 0:
		return {"ok": true, "message": "No intro movie on this cartridge."}

	var section: Dictionary = read_intro_section(rom, layout)
	if section.is_empty():
		return {"ok": false, "message": "The intro movie section does not walk."}

	# `IntroScene3` puts the background sheet's 128 tiles at `vTiles2`, which is
	# where a BG tile number below $80 reads from, so no cell of its map may name
	# a tile the sheet does not hold.
	for cell: int in RomLayout.INTRO_MAP_BYTES:
		if int((section["background_map"] as PackedByteArray)[cell]) >= 0x80:
			return {
				"ok": false,
				"message": "The intro background map names a tile outside its sheet.",
			}
	# `IntroScene1` and `IntroScene26` both open on a cleared screen and fade the
	# Unown in: the first eight palettes of the Unown run are black and of the
	# crystal run white, which is what each scene fades away from.
	var unown_check: Dictionary = _verify_intro_palette_run(
		section["unowns_palette"], 0x0000, "Unown"
	)
	if not unown_check["ok"]:
		return unown_check
	var crystal_check: Dictionary = _verify_intro_palette_run(
		section["crystal_unowns_palette"], 0x7FFF, "crystal Unown"
	)
	if not crystal_check["ok"]:
		return crystal_check

	var fade: int = int(entry.get("fade", -1))
	var pals: int = int(entry.get("unown_pals", -1))
	var fade_bytes: int = RomLayout.INTRO_FADE_PALETTES \
		* RomLayout.INTRO_PALETTE_COLORS * Gen2Palette.COLOR_BYTES
	var pal_bytes: int = RomLayout.INTRO_UNOWN_PALETTES \
		* RomLayout.INTRO_PALETTE_COLORS * Gen2Palette.COLOR_BYTES
	if not rom.in_bounds(fade, fade_bytes) or not rom.in_bounds(pals, pal_bytes):
		return {"ok": false, "message": "The intro fade palettes are outside the cartridge."}
	for colour: int in RomLayout.INTRO_PALETTE_COLORS:
		var offset: int = colour * Gen2Palette.COLOR_BYTES
		if rom.u16le(fade + offset) != rom.u16le(pals + offset):
			return {
				"ok": false,
				"message": "The intro fade does not open on the first Unown palette.",
			}
	return {"ok": true, "message": "Intro movie verified."}


## `_UnownPuzzle`'s art. The walk is most of the check: seven records whose
## lengths are the sizes the routine copies into VRAM, each address the previous
## entry's own consumed length, so one wrong pin fails the next entry.
##
## What the walk cannot see is that a puzzle picture is square: the four are
## six by six tiles because `ConvertLoadedPuzzlePieces` doubles them into the
## twelve-by-twelve grid the sixteen three-by-three pieces are cut from.
static func verify_unown_puzzle(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout.get("unown_puzzle", {})
	if entry.is_empty() or int(entry.get("section", -1)) < 0:
		return {"ok": true, "message": "No Unown puzzle on this cartridge."}

	var section: Dictionary = read_unown_puzzle_section(rom, layout)
	if section.is_empty():
		return {"ok": false, "message": "The Unown puzzle section does not walk."}

	var side: int = RomLayout.UNOWN_PUZZLE_PICTURE_TILES
	for name: String in RomLayout.UNOWN_PUZZLE_PICTURES:
		var tiles: int = int(section[name].size()) / Gen2Tiles.TILE_BYTES
		if tiles != side * side:
			return {
				"ok": false,
				"message": "The %s puzzle is not %d by %d tiles." % [name, side, side],
			}

	if RomLayout.predef_palette_offset(layout, RomLayout.PREDEFPAL_UNOWN_PUZZLE) < 0:
		return {"ok": false, "message": "No PredefPals pin for the Unown puzzle palette."}
	return {"ok": true, "message": "Unown puzzle verified."}

## `GoldSilverIntro`. The section walk is most of the check; what is left is the
## three palette runs outside it and the two metatile maps, which name their own
## `.bin` entries and so check the pair.
##
## `predef_pals` is checked against `game_freak_presents.object_palette`, which
## this layout pins independently: that offset is `PREDEFPAL_GAMEFREAK_LOGO_OB`,
## index 77 of the same table, so each address confirms the other for nothing.
static func verify_gs_intro(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout.get("gs_intro", {})
	if entry.is_empty() or int(entry.get("section", -1)) < 0:
		return {"ok": true, "message": "No Gold and Silver intro on this cartridge."}

	var section: Dictionary = read_gs_intro_section(rom, layout)
	if section.is_empty():
		return {"ok": false, "message": "The Gold and Silver intro section does not walk."}

	# `Intro_Draw2x2Tiles` reads four bytes at `meta + 4 * tilemap[n]`, so no
	# metatile a map names may sit past the end of its own `.bin`.
	for pair: Array in [["water", "water"], ["grass", "grass"]]:
		var map: PackedByteArray = section["%s_tilemap" % pair[0]]
		var meta: PackedByteArray = section["%s_meta" % pair[1]]
		var metatiles: int = meta.size() / RomLayout.GS_INTRO_META_BYTES
		for cell: int in map.size():
			if int(map[cell]) >= metatiles:
				return {
					"ok": false,
					"message": "The %s map names a metatile outside its own table." % pair[0],
				}

	var predef: int = int(entry.get("predef_pals", -1))
	var logo: int = int((layout.get("game_freak_presents", {}) as Dictionary).get(
		"object_palette", -1
	))
	var wanted: int = predef \
		+ RomLayout.GS_INTRO_PREDEF_GAMEFREAK_LOGO_OB * RomLayout.GS_INTRO_PREDEF_SIZE
	if predef < 0 or logo != wanted:
		return {
			"ok": false,
			"message": "The predef palettes do not hold the GameFreak logo's own.",
		}
	for name: String in ["magikarp_palettes", "shellder_lapras_palettes"]:
		var palettes: int = RomLayout.GS_INTRO_MAGIKARP_PALETTES \
			if name == "magikarp_palettes" else RomLayout.GS_INTRO_SHELLDER_LAPRAS_PALETTES
		if not rom.in_bounds(
			int(entry.get(name, -1)), palettes * RomLayout.GS_INTRO_PREDEF_SIZE
		):
			return {
				"ok": false,
				"message": "The Gold and Silver intro %s are outside the cartridge." % name,
			}
	return {"ok": true, "message": "Gold and Silver intro verified."}


## Eight palettes of one repeated colour, which is what a scene fades out of.
static func _verify_intro_palette_run(
	raw: PackedByteArray, colour: int, name: String
) -> Dictionary:
	var colors: int = RomLayout.INTRO_FADE_PALETTES * RomLayout.INTRO_PALETTE_COLORS
	for index: int in colors:
		var at: int = index * Gen2Palette.COLOR_BYTES
		if raw[at] | (raw[at + 1] << 8) != colour:
			return {
				"ok": false,
				"message": "The intro %s palettes do not open on one colour." % name,
			}
	return {"ok": true, "message": ""}


## The credits (`engine/movie/credits.asm`), whose five runs each pin the next.
##
## `CreditsBorderGFX` is the only pinned graphics offset: the four mon sheets
## follow it and `CreditsScript` follows them, so the run's own length is what
## says the offset is right. The script's terminator then puts
## `CreditsStringsPointers` where the layout claims it is, and the string the
## `copyright` index names has to be the copyright screen's own, which the layout
## pins separately in another bank. Content, not neighbours, identifies the two
## uncompressed graphics and the palettes.
static func verify_credits(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout.get("credits", {})
	if entry.is_empty():
		return {"ok": true, "message": "No credits on this cartridge."}

	var palettes: Dictionary = _verify_credits_palettes(rom, entry)
	if not palettes["ok"]:
		return palettes

	var graphics: Dictionary = _verify_credits_gfx(rom, layout, entry)
	if not graphics["ok"]:
		return graphics

	var script: PackedByteArray = read_credits_script(rom, layout)
	if script.is_empty():
		return {"ok": false, "message": "The credits script has no terminator."}
	if int(entry["script"]) + script.size() != int(entry["strings"]):
		return {
			"ok": false,
			"message": "The credits string table does not follow the script.",
		}
	var walked: Dictionary = _verify_credits_script(script, entry)
	if not walked["ok"]:
		return walked

	return _verify_credits_strings(rom, layout, entry)


## `CreditsPalettes`. Structural, plus the one colour every scene shares: each
## opens a scene's first palette and closes it on RGB 07,07,07 in all three
## dumps, so a run of four that does not is not this table.
static func _verify_credits_palettes(rom: RomFile, entry: Dictionary) -> Dictionary:
	var at: int = int(entry["palettes"])
	var stride: int = int(entry["scene_palettes"]) * RomLayout.CREDITS_PALETTE_COLORS
	var length: int = RomLayout.CREDITS_SCENES * stride * 2
	if not rom.in_bounds(at, length):
		return {"ok": false, "message": "The credits palettes are outside the cartridge."}
	if at >= int(entry["gfx"]):
		return {"ok": false, "message": "The credits palettes are behind the graphics."}
	for colour: int in RomLayout.CREDITS_SCENES * stride:
		if rom.u16le(at + colour * 2) & 0x8000:
			return {"ok": false, "message": "A credits palette colour is not 15-bit."}
	for scene: int in RomLayout.CREDITS_SCENES:
		var last: int = at + (scene * stride + RomLayout.CREDITS_PALETTE_COLORS - 1) * 2
		if rom.u16le(last) != RomLayout.CREDITS_PALETTE_LAST_COLOR:
			return {
				"ok": false,
				"message": "Credits scene %d's palette does not close on RGB 07,07,07." % scene,
			}
	return {"ok": true, "message": "Credits palettes verified."}


## The two uncompressed graphics, each by content. The border is a dither drawn
## in colours 0 and 2 alone, so every low-plane byte in it is zero and its last
## tile is colour 2 whole; "The End" uses colours 0, 1 and 3 alone, so no
## high-plane bit in it stands without the low-plane bit under it.
static func _verify_credits_gfx(
	rom: RomFile, layout: Dictionary, entry: Dictionary
) -> Dictionary:
	var at: int = int(entry["gfx"])
	var tiles: int = RomLayout.CREDITS_BORDER_TILES + RomLayout.credits_mon_tiles(layout)
	if not rom.in_bounds(at, tiles * Gen2Tiles.TILE_BYTES):
		return {"ok": false, "message": "The credits graphics are outside the cartridge."}
	if at + tiles * Gen2Tiles.TILE_BYTES != int(entry["script"]):
		return {"ok": false, "message": "The credits script does not follow the graphics."}
	for row: int in RomLayout.CREDITS_BORDER_TILES * Gen2Tiles.TILE_HEIGHT:
		if rom.u8(at + row * 2) != 0:
			return {"ok": false, "message": "The credits border is not drawn in colour 2."}
	var solid: int = at + (RomLayout.CREDITS_BORDER_TILES - 1) * Gen2Tiles.TILE_BYTES
	for row: int in Gen2Tiles.TILE_HEIGHT:
		if rom.u8(solid + row * 2 + 1) != 0xFF:
			return {"ok": false, "message": "The credits border's last tile is not solid."}

	var the_end: int = int(entry["the_end"])
	if not rom.in_bounds(the_end, RomLayout.CREDITS_THE_END_TILES * Gen2Tiles.TILE_BYTES):
		return {"ok": false, "message": "The End graphic is outside the cartridge."}
	var ink: int = 0
	for row: int in RomLayout.CREDITS_THE_END_TILES * Gen2Tiles.TILE_HEIGHT:
		var low: int = rom.u8(the_end + row * 2)
		var high: int = rom.u8(the_end + row * 2 + 1)
		if high & ~low & 0xFF:
			return {"ok": false, "message": "The End graphic uses colour 2."}
		ink |= low
	if ink == 0:
		return {"ok": false, "message": "The End graphic is blank."}
	return {"ok": true, "message": "Credits graphics verified."}


## `ParseCredits`' own walk. A byte that is not one of the seven commands is a
## string index, so a run that is not `CreditsScript` names one past the table
## almost at once; the two indices the layout pins are checked against the walk
## rather than trusted.
static func _verify_credits_script(script: PackedByteArray, entry: Dictionary) -> Dictionary:
	var count: int = int(entry["string_count"])
	if script[0] != RomLayout.CREDITS_CLEAR:
		return {"ok": false, "message": "The credits script does not open on a clear."}
	var highest: int = -1
	var first_string: int = -1
	var step: int = 0
	var terminated: bool = false
	while step < script.size():
		var command: int = script[step]
		step += 1
		if command == RomLayout.CREDITS_END:
			terminated = true
			break
		if command >= RomLayout.CREDITS_THEEND:
			if command in RomLayout.CREDITS_OPERAND_COMMANDS:
				step += 1
			continue
		if command >= count:
			return {
				"ok": false,
				"message": "The credits script names string %d of %d." % [command, count],
			}
		if first_string < 0:
			first_string = command
		highest = maxi(highest, command)
		## A string is followed by the line it prints on, which is never a
		## command byte.
		step += 1
	if not terminated or step != script.size():
		return {"ok": false, "message": "The credits script's last command is cut short."}
	if highest != count - 1:
		return {
			"ok": false,
			"message": "The credits script's highest string is %d, not %d." % [
				highest, count - 1,
			],
		}
	if first_string != int(entry["staff"]):
		return {
			"ok": false,
			"message": "The credits script opens on string %d, not STAFF %d." % [
				first_string, int(entry["staff"]),
			],
		}
	return {"ok": true, "message": "Credits script verified."}


## `CreditsStringsPointers`. Every entry has to terminate inside the strings'
## own bank, and the `copyright` one has to be the copyright screen's string:
## `data/copyright.asm` is INCLUDEd once for each and the layout pins the two
## addresses independently, so they check each other.
static func _verify_credits_strings(
	rom: RomFile, layout: Dictionary, entry: Dictionary
) -> Dictionary:
	var bank: int = int(entry["strings_bank"])
	for index: int in int(entry["string_count"]):
		var at: int = RomLayout.credits_string_offset(rom, layout, index)
		if RomLayout.bank_of(at) != bank:
			return {"ok": false, "message": "Credits string %d leaves bank $%02X." % [index, bank]}
		if read_credits_string(rom, layout, index).is_empty():
			return {"ok": false, "message": "Credits string %d has no terminator." % index}
	var copyright: PackedByteArray = read_credits_string(
		rom, layout, int(entry["copyright"])
	)
	var screen: PackedByteArray = read_copyright_string(rom, layout)
	if copyright != screen:
		return {
			"ok": false,
			"message": "The credits copyright string is not the copyright screen's.",
		}
	return {"ok": true, "message": "Credits verified."}


## `CreditsScript` whole, terminator included. Empty when it does not terminate.
static func read_credits_script(rom: RomFile, layout: Dictionary) -> PackedByteArray:
	var at: int = int((layout.get("credits", {}) as Dictionary).get("script", -1))
	if at < 0:
		return PackedByteArray()
	for length: int in range(1, RomLayout.CREDITS_SCRIPT_MAX_BYTES + 1):
		if not rom.in_bounds(at + length - 1, 1):
			break
		if rom.u8(at + length - 1) == RomLayout.CREDITS_END:
			return rom.slice(at, length)
	return PackedByteArray()


## One credits string as the tile codes `PlaceString` writes, the `@` dropped.
## Empty when it does not terminate, which is what an index outside the table
## produces.
static func read_credits_string(
	rom: RomFile, layout: Dictionary, index: int
) -> PackedByteArray:
	var at: int = RomLayout.credits_string_offset(rom, layout, index)
	if at < 0:
		return PackedByteArray()
	for length: int in RomLayout.CREDITS_STRING_MAX_BYTES:
		if not rom.in_bounds(at + length, 1):
			break
		if rom.u8(at + length) == Gen2Text.TERMINATOR:
			return rom.slice(at, length)
	return PackedByteArray()


## `FillTownMap`'s own loop: tile numbers until `-1`, which is not copied.
static func read_town_map_region(
	rom: RomFile, layout: Dictionary, region: String
) -> PackedByteArray:
	var at: int = int((layout.get("town_map", {}) as Dictionary).get(region, -1))
	var out: PackedByteArray = PackedByteArray()
	if at < 0:
		return out
	for step: int in RomLayout.TOWN_MAP_REGION_CELLS + 1:
		if not rom.in_bounds(at + step, 1):
			return PackedByteArray()
		var byte: int = rom.u8(at + step)
		if byte == RomLayout.TOWN_MAP_REGION_TERMINATOR:
			return out
		out.append(byte)
	return PackedByteArray()


## `Pokegear_LoadTilemapRLE` over the three cards in the run's own order, each
## answered as its twelve rows of tile numbers. A card that does not decode to
## exactly that many cells answers empty, which is what a wrong offset gives.
static func read_pokegear_cards(rom: RomFile, layout: Dictionary) -> Dictionary:
	var at: int = int((layout.get("town_map", {}) as Dictionary).get("cards", -1))
	var out: Dictionary = {}
	if at < 0 or not rom.in_bounds(at, RomLayout.POKEGEAR_CARD_TILEMAP_BYTES):
		return out
	var end: int = at + RomLayout.POKEGEAR_CARD_TILEMAP_BYTES
	for name: String in RomLayout.POKEGEAR_CARD_ORDER:
		var cells: PackedByteArray = PackedByteArray()
		while at < end and rom.u8(at) != RomLayout.POKEGEAR_CARD_TERMINATOR:
			if at + 1 >= end:
				return {}
			var tile: int = rom.u8(at)
			for _step: int in rom.u8(at + 1):
				cells.append(tile)
			at += 2
		if cells.size() != RomLayout.POKEGEAR_CARD_CELLS:
			return {}
		out[name] = cells
		at += 1
	return out


## `_PokegearAskWhoCallText` and its neighbour, read one after the other from the
## first: each decode answers where it ended, which is where the next begins.
static func read_pokegear_texts(rom: RomFile, layout: Dictionary) -> Dictionary:
	var at: int = int((layout.get("town_map", {}) as Dictionary).get("card_texts", -1))
	var out: Dictionary = {}
	var window: int = RomLayout.POKEGEAR_TEXT_NAMES.size() * RomLayout.POKEGEAR_TEXT_MAX_BYTES
	if at < 0 or not rom.in_bounds(at, window):
		return out
	var data: PackedByteArray = rom.slice(at, window)
	var offset: int = 0
	for name: String in RomLayout.POKEGEAR_TEXT_NAMES:
		var decoded: Dictionary = Gen2TextStream.decode(data, offset)
		if not bool(decoded.get("ok", false)):
			return {}
		out[name] = String(decoded["text"])
		offset = int(decoded["bytes"])
	return out


## `LoadTitleScreenTilemap`'s own loop: bytes until `-1`, which is not copied.
## Empty when no terminator is reached inside the bounded window, which is what a
## wrong offset produces.
static func read_title_tilemap(rom: RomFile, layout: Dictionary) -> PackedByteArray:
	var entry: Dictionary = layout.get("title", {})
	var at: int = int(entry.get("tilemap", -1))
	if at < 0:
		return PackedByteArray()
	var out: PackedByteArray = PackedByteArray()
	for step: int in RomLayout.TITLE_TILEMAP_MAX:
		if not rom.in_bounds(at + step, 1):
			return PackedByteArray()
		var byte: int = rom.u8(at + step)
		if byte == RomLayout.TITLE_TILEMAP_TERMINATOR:
			return out
		out.append(byte)
	return PackedByteArray()


static func _tile_1bpp_has_ink(rom: RomFile, offset: int, tile: int) -> bool:
	for row: int in Gen2Tiles.TILE_1BPP_BYTES:
		if rom.u8(offset + tile * Gen2Tiles.TILE_1BPP_BYTES + row) != 0:
			return true
	return false


static func _tile_2bpp_lit(rom: RomFile, offset: int, tile: int) -> int:
	var count: int = 0
	for row: int in Gen2Tiles.TILE_HEIGHT:
		var at: int = offset + tile * Gen2Tiles.TILE_BYTES + row * 2
		var lit: int = rom.u8(at) | rom.u8(at + 1)
		for bit: int in Gen2Tiles.TILE_WIDTH:
			if lit & (1 << bit):
				count += 1
	return count


static func _row_2bpp_lit(rom: RomFile, offset: int, tile: int, row: int) -> bool:
	var at: int = offset + tile * Gen2Tiles.TILE_BYTES + row * 2
	return (rom.u8(at) | rom.u8(at + 1)) != 0


static func _sheet_tile_lit(sheet: PackedByteArray, tile: int) -> int:
	var count: int = 0
	for index: int in Gen2Tiles.TILE_BYTES:
		var at: int = tile * Gen2Tiles.TILE_BYTES + index
		if at >= sheet.size():
			break
		var byte: int = sheet[at]
		for bit: int in 8:
			if byte & (1 << bit):
				count += 1
	return count


## The code run at the layout's string offset, up to but not including "@".
## Empty when no terminator is reached inside the bounded window, which is what
## a wrong offset produces.
static func read_copyright_string(rom: RomFile, layout: Dictionary) -> PackedByteArray:
	var entry: Dictionary = layout.get("copyright", {})
	var at: int = int(entry.get("string", -1))
	var out := PackedByteArray()
	if at < 0:
		return out
	for index: int in RomLayout.COPYRIGHT_STRING_MAX:
		if not rom.in_bounds(at + index, 1):
			return PackedByteArray()
		var code: int = rom.u8(at + index)
		if code == RomLayout.COPYRIGHT_STRING_TERMINATOR:
			return out
		out.append(code)
	return PackedByteArray()


## `data/text/common_2.asm`'s intro texts. Each is a `text_far` target, so it
## opens with the `text` macro's own $00 and runs to a terminator, and each is
## pinned by the first words it says: a text stream of the right shape in the
## wrong place still walks to a terminator and still decodes into words.
static func verify_intro_text(rom: RomFile, layout: Dictionary) -> Dictionary:
	var offsets: Dictionary = layout["intro_text"]
	for key: String in INTRO_TEXT_OPENINGS:
		var at: int = int(offsets.get(key, -1))
		if at < 0:
			# Only the gender text is allowed to be absent, and only where
			# init_gender.asm is.
			if key == INTRO_TEXT_GENDER:
				continue
			return {"ok": false, "message": "Intro text %s has no offset." % key}
		if rom.u8(at) != TEXT_MACRO_START:
			return {
				"ok": false,
				"message": "Intro text %s does not open with the text macro." % key,
			}
		var anchor: Array = INTRO_TEXT_OPENINGS[key]
		var opening: String = String(anchor[1])
		var read: String = Gen2Text.decode(
			rom.bytes(), at + 1 + int(anchor[0]), opening.length()
		)
		if read != opening:
			return {
				"ok": false,
				"message": "Intro text %s reads \"%s\", not \"%s\"." % [key, read, opening],
			}
	return {"ok": true, "message": "Intro texts verified."}


## The `text` macro's own byte, which every `text_far` target opens with.
const TEXT_MACRO_START: int = 0x00
const INTRO_TEXT_GENDER: String = "gender"
## The longest of them is `_OakText7` at 192 bytes; the slice is read to its own
## terminator, so this is only a bound on a runaway stream.
const INTRO_TEXT_MAX_BYTES: int = 512

## What each intro text opens with, as a byte to skip and the plain characters
## after it. Short anchors, the way the species and item tables are anchored:
## enough to say this is the right text and not enough to be a copy of it.
## `_OakText7` opens on `<PLAYER>`, which is one byte and eight characters, so
## its anchor starts behind it.
const INTRO_TEXT_OPENINGS: Dictionary = {
	"oak_1": [0, "Hello!"],
	"oak_2": [0, "This world"],
	"oak_4": [0, "People and"],
	"oak_5": [0, "But we"],
	"oak_6": [0, "Now, what"],
	"oak_7": [1, ", are you"],
	INTRO_TEXT_GENDER: [0, "Are you a boy?"],
}


## What each pack text opens with once its `text` macro byte is past. Short
## anchors, the way the intro texts are anchored.
## The pack's own five, and the six a field item says. Every one is
## `data/text/common_*.asm`, which no other importer reads, so each is pinned by
## its own opening rather than by a table.
const PACK_TEXT_OPENINGS: Dictionary = {
	"oak_no_time": "OAK:",
	"no_mon": "You don't have a",
	"toss_ask": "Throw away how",
	"toss_ask_quantity": "Throw away ",
	"toss_threw": "Threw away",
	"escape_rope": "<PLAYER> used an",
	"itemfinder_nearby": "Yes! ITEMFINDER",
	"itemfinder_nope": "Nope! ITEMFINDER",
	## `#` is the charmap's own ligature and decodes spelled out, the way
	## MENU_DESCRIPTION_FIRST does.
	"sacred_ash": "<PLAYER>'s POKéMON",
	"squirtbottle": "<PLAYER> sprinkled",
	"coin_case": "Coins:",
}
## The first and last of `.PokedexDesc` through `.QuitDesc`, which is what says a
## nine-string run is that run and not another one in the same bank. As decoded
## rather than as written: `#MON` is the charmap's own ligature and comes back
## out spelled.
const MENU_DESCRIPTION_FIRST: String = "POKéMON\ndatabase"
const MENU_DESCRIPTION_LAST: String = "Quit and\nbe judged."


## The start menu's description run and the pack's five texts.
##
## The run is checked by content at both ends and by shape in between: nine
## strings, each terminated inside its own bound, which no neighbouring text run
## in the bank satisfies with those two at the ends. The five texts are checked
## the way the intro texts are, by the `text` macro byte and the words after it.
static func verify_menu_text(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout.get("menu_text", {})
	if entry.is_empty():
		return {"ok": true, "message": "No menu text on this cartridge."}
	var descriptions: Array[String] = read_menu_descriptions(rom, layout)
	if descriptions.size() != RomLayout.MENU_DESCRIPTION_COUNT:
		return {
			"ok": false,
			"message": "The start menu descriptions read %d of %d strings." % [
				descriptions.size(), RomLayout.MENU_DESCRIPTION_COUNT,
			],
		}
	if descriptions[0] != MENU_DESCRIPTION_FIRST:
		return {
			"ok": false,
			"message": "The first start menu description is \"%s\"." % descriptions[0],
		}
	if descriptions[descriptions.size() - 1] != MENU_DESCRIPTION_LAST:
		return {
			"ok": false,
			"message": "The last start menu description is \"%s\"." % descriptions[
				descriptions.size() - 1
			],
		}
	for key: String in PACK_TEXT_OPENINGS:
		var at: int = int(entry.get(key, -1))
		## -1 is a text this cartridge has nothing usable at; only the Coin
		## Case's is, and only on Gold and Silver.
		if at < 0:
			continue
		if not rom.in_bounds(at, RomLayout.PACK_TEXT_MAX_BYTES):
			return {"ok": false, "message": "Pack text %s is outside the cartridge." % key}
		if rom.u8(at) != TEXT_MACRO_START:
			return {
				"ok": false,
				"message": "Pack text %s does not open with the text macro." % key,
			}
		var decoded: Dictionary = Gen2WorldScript.decode_text(
			rom.slice(at, RomLayout.PACK_TEXT_MAX_BYTES)
		)
		if not bool(decoded.get("ok", false)):
			return {"ok": false, "message": "Pack text %s did not decode." % key}
		if not String(decoded["text"]).begins_with(String(PACK_TEXT_OPENINGS[key])):
			return {
				"ok": false,
				"message": "Pack text %s reads \"%s\"." % [key, decoded["text"]],
			}
	return {"ok": true, "message": "Menu text verified."}


## The nine descriptions at the layout's own offset, in the order the source
## defines them. Short when a string runs past its bound, which is what a wrong
## offset produces.
static func read_menu_descriptions(rom: RomFile, layout: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var at: int = int((layout.get("menu_text", {}) as Dictionary).get("descriptions", -1))
	if at < 0:
		return out
	var data: PackedByteArray = rom.bytes()
	for _index: int in RomLayout.MENU_DESCRIPTION_COUNT:
		if not rom.in_bounds(at, 1):
			return []
		var end: int = Gen2Text.terminated_end(data, at, RomLayout.MENU_DESCRIPTION_MAX)
		if end <= at or end - at >= RomLayout.MENU_DESCRIPTION_MAX:
			return []
		out.append(Gen2Text.decode(data, at, end - at))
		at = end
	return out


## data/text/name_input_chars.asm. Nothing in the block identifies itself, so it
## is pinned by content at both ends of every table: row 0 has to be the nine
## letters the table opens with, and the last row has to be the command row,
## which is what NamingScreen_GetCursorPosition reads by column. A run of text
## bytes elsewhere in the bank passes neither.
## StringBufferPointers checked against what `ram/wram.asm` says about its
## targets, not against an address this project chose.
##
## wStringBuffer1..5 are five consecutive `ds STRING_BUFFER_LENGTH` runs, so the
## five general entries must sit one stride apart in the order
## `data/text_buffers.asm` lists them. A wrong offset lands on unrelated words
## and fails the stride; a right offset in the wrong dump fails the WRAM range.
static func verify_string_buffer_pointers(rom: RomFile, layout: Dictionary) -> Dictionary:
	var at: int = int(layout.get("string_buffer_pointers", -1))
	var bytes: int = RomLayout.STRING_BUFFER_POINTER_COUNT * RomLayout.STRING_BUFFER_POINTER_SIZE
	if not rom.in_bounds(at, bytes):
		return {"ok": false, "message": "String buffer pointers are outside the cartridge."}

	var pointers: Array = []
	for index: int in RomLayout.STRING_BUFFER_POINTER_COUNT:
		var address: int = rom.u16le(RomLayout.string_buffer_pointer_offset(layout, index))
		if address < 0xC000 or address >= 0xE000:
			return {
				"ok": false,
				"message": "String buffer %d points at $%04X, which is not WRAM." % [
					index, address,
				],
			}
		pointers.append(address)

	var third: int = int(pointers[RomLayout.STRING_BUFFER_3])
	var stride: int = RomLayout.STRING_BUFFER_LENGTH
	var expected: Dictionary = {
		RomLayout.STRING_BUFFER_1: third - 2 * stride,
		RomLayout.STRING_BUFFER_2: third - stride,
		RomLayout.STRING_BUFFER_4: third + stride,
		RomLayout.STRING_BUFFER_5: third + 2 * stride,
	}
	for index: int in expected:
		if int(pointers[index]) != int(expected[index]):
			return {
				"ok": false,
				"message": "String buffer entry %d is $%04X, expected $%04X." % [
					index, pointers[index], expected[index],
				],
			}
	return {"ok": true, "pointers": pointers}


static func verify_name_input_chars(rom: RomFile, layout: Dictionary) -> Dictionary:
	var at: int = int(layout.get("name_input_chars", -1))
	if not rom.in_bounds(at, RomLayout.NAME_INPUT_BLOCK_BYTES):
		return {"ok": false, "message": "Name input table is outside the cartridge."}
	for table: int in RomLayout.NAME_INPUT_TABLE_ROWS.size():
		var start: int = RomLayout.name_input_table_offset(layout, table)
		var rows: int = RomLayout.NAME_INPUT_TABLE_ROWS[table]
		# Tables 0 and 1 are the lower keyboards and open on "a"; 2 and 3 are the
		# upper ones and open on "A".
		var lower: bool = table < 2
		var first: int = RomLayout.NAME_INPUT_LOWER_A if lower else RomLayout.NAME_INPUT_UPPER_A
		for column: int in RomLayout.NAME_INPUT_COLUMNS:
			var expected: int = first + column
			var stored: int = rom.u8(start + column * RomLayout.NAME_INPUT_COLUMN_STRIDE)
			if stored != expected:
				return {
					"ok": false,
					"message": "Name input table %d letter %d is $%02X, expected $%02X." % [
						table, column, stored, expected,
					],
				}
		# The last row of every table is the command row, in the columns
		# NamingScreen_GetCursorPosition splits on.
		var command: int = start + (rows - 1) * RomLayout.NAME_INPUT_ROW_BYTES
		var expected_row: Array[int] = (
			RomLayout.NAME_INPUT_COMMAND_LOWER if lower else RomLayout.NAME_INPUT_COMMAND_UPPER
		)
		if Array(rom.slice(command, RomLayout.NAME_INPUT_ROW_BYTES)) != Array(expected_row):
			return {"ok": false, "message": "Name input table %d has no command row." % table}

	# LoadNamingScreenGFX's four sheets are located from the block, so what has
	# to be checked is that the run really extends that far and that the two
	# markers are the dashes the entry draws. Both are one 1bpp tile of two lit
	# rows, and which rows they are is the whole difference between them.
	var border: int = RomLayout.naming_border_offset(layout)
	var last: int = RomLayout.naming_under_line_offset(layout)
	if not rom.in_bounds(border, last - border + RomLayout.TILE_BYTES_1BPP):
		return {"ok": false, "message": "Name input graphics run past the cartridge."}
	var markers: Dictionary = {
		RomLayout.naming_middle_line_offset(layout): NAMING_MIDDLE_LINE_ROWS,
		RomLayout.naming_under_line_offset(layout): NAMING_UNDER_LINE_ROWS,
	}
	for marker: int in markers:
		for row: int in RomLayout.TILE_BYTES_1BPP:
			var expected_byte: int = NAMING_MARKER_INK if row in markers[marker] else 0
			if rom.u8(marker + row) != expected_byte:
				return {
					"ok": false,
					"message": "Name entry marker at $%X row %d is $%02X, expected $%02X." % [
						marker, row, rom.u8(marker + row), expected_byte,
					],
				}
	return {"ok": true, "message": "Name input tables and graphics verified."}


## `gfx/naming_screen/middle_line.1bpp` and `underline.1bpp`: seven lit pixels
## on two rows each, which is what tells the dash under an unreached slot from
## the one under the next character.
const NAMING_MARKER_INK: int = 0x7F
const NAMING_MIDDLE_LINE_ROWS: Array[int] = [3, 4]
const NAMING_UNDER_LINE_ROWS: Array[int] = [6, 7]


## `gfx/new_game/gender_screen.pal`'s four colours, which pin the palette:
## white, the light blue the field is filled with, a darker blue, and black.
const GENDER_SCREEN_COLORS: Array[int] = [0x7FFF, 0x7FC9, 0x7D61, 0x0000]


## `gfx/font/bg_text.pal`'s own four colours, which pin the palette. -1 on Gold
## and Silver, which ship no palette of their own for a text box.
const TEXT_BG_COLORS: Array[int] = [0x7FFF, 0x7268, 0x40A5, 0x0000]


## `ShrinkPlayer`'s two pictures. Both are LZ runs, so the check is that each
## decompresses to exactly the 7x7 box `ShrinkFrame` asks `PlaceGraphic` for: a
## wrong address either fails the decompressor or lands on a run of the wrong
## size, and neither of those is the shrink.
static func verify_shrink_pics(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout["shrink_pics"]
	var wanted: int = RomLayout.SHRINK_PIC_TILES * Gen2Tiles.TILE_BYTES
	var lz := Gen2Lz.new()
	for key: String in ["first", "second"]:
		var at: int = int(entry[key])
		if not rom.in_bounds(at):
			return {"ok": false, "message": "Shrink pic %s is outside the cartridge." % key}
		var raw: PackedByteArray = lz.decompress(rom.bytes(), at)
		if lz.failed or raw.size() != wanted:
			return {
				"ok": false,
				"message": "Shrink pic %s decompressed to %d bytes, wanted %d." % [
					key, raw.size(), wanted,
				],
			}
	return {"ok": true, "message": "Shrink pics verified."}


static func verify_text_bg_palette(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: int = int((layout.get("text_bg_palette", {}) as Dictionary).get("offset", -1))
	if entry < 0:
		return {"ok": true, "message": "No text palette on this cartridge."}
	if not rom.in_bounds(entry, TEXT_BG_COLORS.size() * Gen2Palette.COLOR_BYTES):
		return {"ok": false, "message": "The text palette is outside the cartridge."}
	for index: int in TEXT_BG_COLORS.size():
		var stored: int = rom.u16le(entry + index * Gen2Palette.COLOR_BYTES)
		if stored != TEXT_BG_COLORS[index]:
			return {
				"ok": false,
				"message": "Text palette colour %d is $%04X, expected $%04X." % [
					index, stored, TEXT_BG_COLORS[index],
				],
			}
	return {"ok": true, "message": "Text palette verified."}


## `LoadGenderScreenPal` and `LoadGenderScreenLightBlueTile`, whose bytes sit
## thirteen apart in the same routine pair.
##
## The palette's eight bytes appear once in the dump, so they pin themselves.
## The tile does not: sixteen bytes of one repeated index occur hundreds of
## times, so it is checked for being exactly that, on the index the palette's
## light blue sits at. Both are -1 on Gold and Silver, which ship no gender
## screen at all.
static func verify_gender_screen(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout.get("gender_screen", {})
	var palette: int = int(entry.get("palette", -1))
	var tile: int = int(entry.get("tile", -1))
	if palette < 0 and tile < 0:
		return {"ok": true, "message": "No gender screen on this cartridge."}
	if not rom.in_bounds(palette, RomLayout.GENDER_SCREEN_PALETTE_COLORS * Gen2Palette.COLOR_BYTES) \
			or not rom.in_bounds(tile, RomLayout.TILE_BYTES_2BPP):
		return {"ok": false, "message": "Gender screen graphics are outside the cartridge."}

	for index: int in GENDER_SCREEN_COLORS.size():
		var stored: int = rom.u16le(palette + index * Gen2Palette.COLOR_BYTES)
		if stored != GENDER_SCREEN_COLORS[index]:
			return {
				"ok": false,
				"message": "Gender screen colour %d is $%04X, expected $%04X." % [
					index, stored, GENDER_SCREEN_COLORS[index],
				],
			}

	# One 2bpp tile whose every pixel is GENDER_SCREEN_FILL_INDEX: each row is
	# the low plane lit and the high plane clear.
	var low: int = 0xFF if (RomLayout.GENDER_SCREEN_FILL_INDEX & 1) != 0 else 0x00
	var high: int = 0xFF if (RomLayout.GENDER_SCREEN_FILL_INDEX & 2) != 0 else 0x00
	for row: int in Gen2Tiles.TILE_HEIGHT:
		if rom.u8(tile + row * 2) != low or rom.u8(tile + row * 2 + 1) != high:
			return {
				"ok": false,
				"message": "Gender screen tile row %d is not a solid index %d." % [
					row, RomLayout.GENDER_SCREEN_FILL_INDEX,
				],
			}
	return {"ok": true, "message": "Gender screen graphics verified."}


## `gfx/pack/pack.pal` and `pack_f.pal`, six palettes each, which pin both sets:
## every dump ships them byte identical and Crystal stores Kris's immediately
## after Chris's, inside `_CGB_PackPals` itself.
const PACK_CHRIS_COLORS: Array[int] = [
	0x7FFF, 0x7DEF, 0x7C00, 0x0000, 0x7FFF, 0x7DEF, 0x7C00, 0x0000,
	0x7D7F, 0x7DEF, 0x7C00, 0x0000, 0x7FFF, 0x7DEF, 0x7C00, 0x001F,
	0x7FFF, 0x7DEF, 0x001F, 0x0000, 0x7FFF, 0x1E67, 0x1E67, 0x0000,
]
const PACK_KRIS_COLORS: Array[int] = [
	0x7FFF, 0x7DDF, 0x7CFF, 0x0000, 0x7FFF, 0x7DDF, 0x7CFF, 0x0000,
	0x7DEF, 0x7DDF, 0x7CFF, 0x0000, 0x7FFF, 0x7DDF, 0x7CFF, 0x001F,
	0x7FFF, 0x7DDF, 0x001F, 0x0000, 0x7FFF, 0x1E67, 0x1E67, 0x0000,
]
## What `DrawPocketName`'s tilemap sits before `PackMenuGFX` by in every dump.
## The two were located independently, so the constant gap is what says both are
## right rather than both being plausible.
const PACK_NAME_TILEMAP_GAP: int = 0x135


## `MapEntryFrameGFX`, which `gfx/font.asm` lays down immediately before
## `FontsExtra2_UpArrowGFX`. The two were pinned independently, so the sheet
## ending exactly where the arrow starts is what says both are right.
static func verify_map_entry_sign(rom: RomFile, layout: Dictionary) -> Dictionary:
	var at: int = int(layout.get("map_entry_sign", -1))
	if at < 0:
		return {"ok": true, "message": "No map name sign on this cartridge."}
	var bytes: int = RomLayout.MAP_ENTRY_SIGN_TILES * RomLayout.TILE_BYTES_2BPP
	if not rom.in_bounds(at, bytes):
		return {"ok": false, "message": "The map name sign is outside the cartridge."}
	var arrow: int = int((layout.get("up_arrow", {}) as Dictionary).get("offset", -1))
	if at + bytes != arrow:
		return {
			"ok": false,
			"message": "The map name sign ends at $%X, expected the up arrow's $%X." % [
				at + bytes, arrow,
			],
		}
	return {"ok": true, "message": "Map name sign verified."}


## The pack screen's four runs. Both palette sets are checked colour for colour,
## the tilemap for being where it is relative to the sheet and for naming only
## tiles the sheet carries, and every run for being inside the cartridge.
static func verify_pack(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout.get("pack", {})
	if entry.is_empty():
		return {"ok": true, "message": "No pack screen on this cartridge."}
	var menu_gfx: int = int(entry["menu_gfx"])
	var names: int = int(entry["pocket_names"])
	if not rom.in_bounds(menu_gfx, RomLayout.PACK_MENU_TILES * RomLayout.TILE_BYTES_2BPP) \
		or not rom.in_bounds(
			RomLayout.pack_gfx_offset(layout),
			RomLayout.PACK_TILES * RomLayout.TILE_BYTES_2BPP
		) \
		or not rom.in_bounds(names, RomLayout.PACK_NAME_CELLS):
		return {"ok": false, "message": "Pack graphics are outside the cartridge."}
	if menu_gfx - names != PACK_NAME_TILEMAP_GAP:
		return {
			"ok": false,
			"message": "The pack tilemap sits $%X before its sheet, expected $%X." % [
				menu_gfx - names, PACK_NAME_TILEMAP_GAP,
			],
		}
	for cell: int in RomLayout.PACK_NAME_CELLS:
		var tile: int = rom.u8(names + cell)
		if tile >= RomLayout.PACK_FIRST_TILE:
			return {
				"ok": false,
				"message": "Pack tilemap cell %d is tile $%02X, past the sheet." % [
					cell, tile,
				],
			}

	var sets: Array = [["palettes", PACK_CHRIS_COLORS], ["female_palettes", PACK_KRIS_COLORS]]
	for set_row: Array in sets:
		var at: int = int(entry.get(String(set_row[0]), -1))
		if at < 0:
			continue
		var want: Array[int] = set_row[1]
		if not rom.in_bounds(at, want.size() * Gen2Palette.COLOR_BYTES):
			return {"ok": false, "message": "Pack palettes are outside the cartridge."}
		for index: int in want.size():
			var stored: int = rom.u16le(at + index * Gen2Palette.COLOR_BYTES)
			if stored != want[index]:
				return {
					"ok": false,
					"message": "Pack %s colour %d is $%04X, expected $%04X." % [
						set_row[0], index, stored, want[index],
					],
				}
	return {"ok": true, "message": "Pack graphics verified."}


## `PCMailGFX`, the four tiles `BillsPC_InitGFX` copies to `vTiles2 tile $5c`:
## the mail marker `PCMonInfo` prints for a held mail, the item marker beside it,
## and the two halves of each. Byte identical in all three dumps.
const PC_MAIL_BYTES: Array[int] = [
	0xFF, 0xFF, 0xFF, 0x81, 0xFF, 0xC3, 0xFF, 0xA5,
	0xFF, 0x99, 0xFF, 0x81, 0xFF, 0x81, 0xFF, 0xFF,
	0xFF, 0xFF, 0x81, 0xFF, 0xFF, 0xFF, 0xBD, 0xE7,
	0xBD, 0xFF, 0x81, 0xFF, 0x81, 0xFF, 0xFF, 0xFF,
	0x00, 0x00, 0x38, 0x38, 0x3C, 0x3C, 0x3E, 0x3E,
	0x3E, 0x3E, 0x3C, 0x3C, 0x38, 0x38, 0x00, 0x00,
	0x00, 0x00, 0x1C, 0x1C, 0x3C, 0x3C, 0x7C, 0x7C,
	0x7C, 0x7C, 0x3C, 0x3C, 0x1C, 0x1C, 0x00, 0x00,
]
## `BillsPCOrangePalette`, `gfx/pc/orange.pal` encoded.
const PC_ORANGE_COLORS: Array[int] = [0x01FF, 0x0197, 0x00EF, 0x0000]
## The most padding an aligned `PCSelectLZ` leaves before `PCMailGFX`: the run
## is `--align 4` on Gold and Silver and `--align 1` on Crystal.
const PC_SELECT_MAX_PADDING: int = 4


## Bill's PC's own three runs. The mail sheet and the palette are checked byte
## for byte, and the cursor sheet by decompressing: a run that yields exactly
## eight tiles and ends where the mail sheet begins is the one the source names,
## which is the same neighbour argument `verify_pack` makes.
static func verify_pc(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout.get("pc", {})
	if entry.is_empty():
		return {"ok": true, "message": "No PC screen on this cartridge."}
	var select: int = int(entry["select_gfx"])
	var mail: int = int(entry["mail_gfx"])
	var orange: int = int(entry["orange_palette"])
	if not rom.in_bounds(mail, PC_MAIL_BYTES.size()) \
		or not rom.in_bounds(orange, PC_ORANGE_COLORS.size() * Gen2Palette.COLOR_BYTES) \
		or select < 0 or select >= mail:
		return {"ok": false, "message": "PC graphics are outside the cartridge."}
	for index: int in PC_MAIL_BYTES.size():
		if rom.u8(mail + index) != PC_MAIL_BYTES[index]:
			return {
				"ok": false,
				"message": "PCMailGFX byte %d is $%02X, expected $%02X." % [
					index, rom.u8(mail + index), PC_MAIL_BYTES[index],
				],
			}
	for index: int in PC_ORANGE_COLORS.size():
		var stored: int = rom.u16le(orange + index * Gen2Palette.COLOR_BYTES)
		if stored != PC_ORANGE_COLORS[index]:
			return {
				"ok": false,
				"message": "PC orange colour %d is $%04X, expected $%04X." % [
					index, stored, PC_ORANGE_COLORS[index],
				],
			}
	var lz := Gen2Lz.new()
	var raw: PackedByteArray = lz.decompress(rom.bytes(), select)
	if lz.failed or raw.size() != RomLayout.PC_SELECT_TILES * Gen2Tiles.TILE_BYTES:
		return {
			"ok": false,
			"message": "PCSelectLZ decompresses to %d bytes, expected %d." % [
				raw.size(), RomLayout.PC_SELECT_TILES * Gen2Tiles.TILE_BYTES,
			],
		}
	var padding: int = mail - select - lz.consumed
	if padding < 0 or padding > PC_SELECT_MAX_PADDING:
		return {
			"ok": false,
			"message": "PCSelectLZ ends %d bytes before PCMailGFX." % padding,
		}
	return {"ok": true, "message": "PC graphics verified."}


## Walks the type matchup chart from its offset to the terminator.
##
## Returns an Array of { attacker, defender, multiplier, negated_by_foresight },
## empty if the walk ran away without finding an end. Rows after the $FE marker
## carry the flag: they stop applying once Foresight identifies the defender,
## which is how a Ghost becomes hittable by Normal without a second table.
static func read_matchups(rom: RomFile, layout: Dictionary) -> Array:
	var at: int = int(layout["type_matchups"])
	var out: Array = []
	var after_foresight: bool = false

	for _step: int in RomLayout.MAX_MATCHUPS:
		if not rom.in_bounds(at, RomLayout.MATCHUP_ENTRY_SIZE):
			return []

		var attacker: int = rom.u8(at + RomLayout.MATCHUP_ATTACKER)
		if attacker == RomLayout.MATCHUP_END:
			return out
		if attacker == RomLayout.MATCHUP_END_FORESIGHT:
			# The first marker is one byte, not an entry: the rows it separates
			# follow immediately after it.
			after_foresight = true
			at += 1
			continue

		out.append({
			"attacker": attacker,
			"defender": rom.u8(at + RomLayout.MATCHUP_DEFENDER),
			"multiplier": rom.u8(at + RomLayout.MATCHUP_MULTIPLIER),
			"negated_by_foresight": after_foresight,
		})
		at += RomLayout.MATCHUP_ENTRY_SIZE

	return []


## The matchup chart, checked by the shape a chart of exceptions has to have.
##
## No name and no number, but hard to land on by accident: every row is two
## sparse type numbers and one of three multipliers, the run must reach $FE then
## $FF at exactly the right distance, and both ends are known content. A wrong
## offset fails on the first row, since the padding run between the two type
## groups is most of the byte range.
static func verify_matchups(rom: RomFile, layout: Dictionary) -> Dictionary:
	var rows: Array = read_matchups(rom, layout)
	if rows.is_empty():
		return {"ok": false, "message": "Type matchups: no terminator within reach."}

	for index: int in rows.size():
		var row: Dictionary = rows[index]
		for side: String in ["attacker", "defender"]:
			var type_number: int = int(row[side])
			if not RomLayout.is_matchup_type(type_number):
				return {
					"ok": false,
					"message": "Type matchup %d: %s is $%02X, not a type." % [
						index, side, type_number,
					],
				}
		# A neutral matchup is an absent row, so a byte of ten here would mean the
		# walk is reading something that is not the chart.
		if not RomLayout.MATCHUP_MULTIPLIERS.has(int(row["multiplier"])):
			return {
				"ok": false,
				"message": "Type matchup %d has multiplier %d, which the chart never stores." % [
					index, int(row["multiplier"]),
				],
			}

	var negated: Array = rows.filter(func(row: Dictionary) -> bool:
		return bool(row["negated_by_foresight"])
	)
	if rows.size() != RomLayout.MATCHUP_COUNT + RomLayout.FORESIGHT_MATCHUP_COUNT:
		return {
			"ok": false,
			"message": "Type matchups: read %d rows, expected %d." % [
				rows.size(), RomLayout.MATCHUP_COUNT + RomLayout.FORESIGHT_MATCHUP_COUNT,
			],
		}
	if negated.size() != RomLayout.FORESIGHT_MATCHUP_COUNT:
		return {
			"ok": false,
			"message": "Type matchups: %d rows past the Foresight marker, expected %d." % [
				negated.size(), RomLayout.FORESIGHT_MATCHUP_COUNT,
			],
		}

	# Both ends, as content whose answer is known independently. The chart opens
	# with Normal against Rock and closes with Steel against itself, and the two
	# rows Foresight cancels are the Ghost immunities.
	var checks: Array = [
		[rows[0], RomLayout.TYPE_NORMAL, RomLayout.TYPE_ROCK,
			RomLayout.MATCHUP_NOT_VERY_EFFECTIVE, "the first row"],
		[rows[RomLayout.MATCHUP_COUNT - 1], RomLayout.TYPE_STEEL, RomLayout.TYPE_STEEL,
			RomLayout.MATCHUP_NOT_VERY_EFFECTIVE, "the last row"],
		[negated[0], RomLayout.TYPE_NORMAL, RomLayout.TYPE_GHOST,
			RomLayout.MATCHUP_NO_EFFECT, "the first Foresight row"],
		[negated[1], RomLayout.TYPE_FIGHTING, RomLayout.TYPE_GHOST,
			RomLayout.MATCHUP_NO_EFFECT, "the second Foresight row"],
	]
	for check: Array in checks:
		var row: Dictionary = check[0]
		if int(row["attacker"]) != int(check[1]) or int(row["defender"]) != int(check[2]) \
			or int(row["multiplier"]) != int(check[3]):
			return {
				"ok": false,
				"message": "Type matchups: %s is $%02X against $%02X at x%d/10." % [
					check[4], int(row["attacker"]), int(row["defender"]), int(row["multiplier"]),
				],
			}

	return {"ok": true, "message": ""}


## Walks one species' entry in the combined evolution and level-up move table.
##
## Returns { evolutions, learnset }, empty if both terminators were not where a
## well-formed entry has them. An evolution is
## { method, parameter, condition, target }, a level-up move { level, move };
## [code]condition[/code] is zero except for [constant RomLayout.EVOLVE_STAT],
## the only method asking two questions.
##
## Level-up moves keep the cartridge's order rather than being sorted: the order
## decides which move a fresh Pokémon ends up with when more than four are on
## offer, and one species really is out of order (see
## [constant RomLayout.UNSORTED_LEARNSET_SPECIES]).
static func read_evos_attacks(rom: RomFile, layout: Dictionary, species: int) -> Dictionary:
	var table: int = RomLayout.evos_attacks_pointer_offset(layout, species)
	if not rom.in_bounds(table, RomLayout.EVOS_ATTACKS_POINTER_SIZE):
		return {}

	# The pointer is an address with no bank, so it has to be one the switchable
	# window can hold: the entry is in the pointer table's own bank.
	var address: int = rom.u16le(table)
	if address < RomFile.BANK_SIZE or address >= RomFile.BANK_SIZE * 2:
		return {}
	var at: int = RomFile.linear(RomLayout.bank_of(table), address)

	var evolutions: Array = []
	while rom.in_bounds(at) and rom.u8(at) != RomLayout.EVOS_ATTACKS_END:
		if evolutions.size() >= RomLayout.MAX_EVOLUTIONS:
			return {}
		var method: int = rom.u8(at)
		if not RomLayout.EVOLVE_METHODS.has(method):
			return {}
		var size: int = RomLayout.evolution_size(method)
		if not rom.in_bounds(at, size):
			return {}
		# The target is always last, which is what makes the four-byte method fit
		# the same shape as the three-byte ones.
		evolutions.append({
			"method": method,
			"parameter": rom.u8(at + 1),
			"condition": rom.u8(at + 2) if method == RomLayout.EVOLVE_STAT else 0,
			"target": rom.u8(at + size - 1),
		})
		at += size

	if not rom.in_bounds(at):
		return {}
	at += 1

	var learnset: Array = []
	while rom.in_bounds(at) and rom.u8(at) != RomLayout.EVOS_ATTACKS_END:
		if learnset.size() >= RomLayout.MAX_LEVEL_UP_MOVES or not rom.in_bounds(at, 2):
			return {}
		learnset.append({"level": rom.u8(at), "move": rom.u8(at + 1)})
		at += 2

	if not rom.in_bounds(at):
		return {}
	return {"evolutions": evolutions, "learnset": learnset}


## One species' inherited move list from EggMovePointers. Returns { moves } on
## success, including an empty list, and an empty Dictionary for a malformed
## pointer, move id or unterminated list.
##
## The address has no bank byte, so it must name the switchable window and is
## resolved against the pointer table's bank. The walk stops at that bank's end,
## not merely the dump's end: continuing into the next bank would turn a missing
## terminator into plausible data from an unrelated section.
static func read_egg_moves(rom: RomFile, layout: Dictionary, species: int) -> Dictionary:
	if species < 1 or species > RomLayout.SPECIES_COUNT \
		or not layout.has("egg_move_pointers"):
		return {}
	var table: int = RomLayout.egg_move_pointer_offset(layout, species)
	if not rom.in_bounds(table, RomLayout.EGG_MOVE_POINTER_SIZE):
		return {}

	var address: int = rom.u16le(table)
	if address < RomFile.BANK_SIZE or address >= RomFile.BANK_SIZE * 2:
		return {}
	var bank: int = RomLayout.bank_of(table)
	var at: int = RomFile.linear(bank, address)
	var bank_end: int = mini((bank + 1) * RomFile.BANK_SIZE, rom.size())
	var moves: Array[int] = []
	while at < bank_end:
		var move: int = rom.u8(at)
		at += 1
		if move == RomLayout.EGG_MOVE_END:
			return {"moves": moves}
		if move < 1 or move > RomLayout.MOVE_COUNT:
			return {}
		moves.append(move)
	return {}


## Checks all 251 inherited-move lists before they can enter the cache. The
## census pins the complete table while Bulbasaur and Staryu distinguish the
## Gold/Silver data from Crystal's revision.
static func verify_egg_moves(rom: RomFile, layout: Dictionary) -> Dictionary:
	for key: String in ["egg_move_pointers", "egg_move_count", "egg_move_species_count"]:
		if not layout.has(key):
			return {"ok": false, "message": "No egg-move layout field %s." % key}

	var entries: Array = []
	var total: int = 0
	var nonempty: int = 0
	for species: int in range(1, RomLayout.SPECIES_COUNT + 1):
		var entry: Dictionary = read_egg_moves(rom, layout, species)
		if entry.is_empty():
			return {
				"ok": false,
				"message": "Species %d has no readable egg-move list." % species,
			}
		var moves: Array = entry["moves"]
		entries.append(moves)
		total += moves.size()
		if not moves.is_empty():
			nonempty += 1

	var expected_total: int = int(layout["egg_move_count"])
	if total != expected_total:
		return {
			"ok": false,
			"message": "Read %d egg moves, expected %d." % [total, expected_total],
		}
	var expected_nonempty: int = int(layout["egg_move_species_count"])
	if nonempty != expected_nonempty:
		return {
			"ok": false,
			"message": "%d species have egg moves, expected %d." % [
				nonempty, expected_nonempty,
			],
		}

	var bulbasaur: Array[int] = EGG_MOVES_BULBASAUR_GOLD_SILVER
	var staryu: Array[int] = EGG_MOVES_STARYU_GOLD_SILVER
	if rom.id == RomRegistry.CRYSTAL:
		bulbasaur = EGG_MOVES_BULBASAUR_CRYSTAL
		staryu = EGG_MOVES_STARYU_CRYSTAL
	elif rom.id != RomRegistry.GOLD and rom.id != RomRegistry.SILVER:
		return {"ok": false, "message": "No egg-move profile for %s." % rom.id}

	if entries[EGG_MOVE_BULBASAUR_SPECIES - 1] != bulbasaur:
		return {
			"ok": false,
			"message": "Bulbasaur egg moves are %s, expected %s." % [
				entries[EGG_MOVE_BULBASAUR_SPECIES - 1], bulbasaur,
			],
		}
	if entries[EGG_MOVE_STARYU_SPECIES - 1] != staryu:
		return {
			"ok": false,
			"message": "Staryu egg moves are %s, expected %s." % [
				entries[EGG_MOVE_STARYU_SPECIES - 1], staryu,
			],
		}
	return {"ok": true, "message": ""}


## Walks one species' Pokedex entry (data/pokemon/dex_entries.asm).
##
## Returns { category, height, weight, pages }, empty if the pointer or the walk
## left the cartridge. [code]pages[/code] is always
## [constant RomLayout.DEX_ENTRY_PAGES] strings.
##
## Height and weight are the cartridge's own numbers rather than converted
## measurements: height is decimal digits of feet and inches and weight is tenths
## of a pound, and `DisplayDexEntry` prints both by punctuating the digits. A
## zero in either is the source's own "no measurement" and is kept, since
## `.skip_height` and `.skip_weight` leave the row blank rather than printing a
## zero.
static func read_dex_entry(rom: RomFile, layout: Dictionary, species: int) -> Dictionary:
	var table: int = RomLayout.dex_entry_pointer_offset(layout, species)
	if not rom.in_bounds(table, RomLayout.DEX_ENTRY_POINTER_SIZE):
		return {}

	# The pointer carries no bank; the bank is chosen by species number, so the
	# address still has to be one the switchable window can hold.
	var address: int = rom.u16le(table)
	if address < RomFile.BANK_SIZE or address >= RomFile.BANK_SIZE * 2:
		return {}

	var data: PackedByteArray = rom.bytes()
	var at: int = RomLayout.dex_entry_offset(layout, species, address)
	if not rom.in_bounds(at):
		return {}

	var category: String = Gen2Text.decode(
		data, at, RomLayout.DEX_ENTRY_MAX_CATEGORY_LENGTH
	)
	at = Gen2Text.terminated_end(data, at, RomLayout.DEX_ENTRY_MAX_CATEGORY_LENGTH)

	var measurements: int = RomLayout.DEX_ENTRY_MEASUREMENT_BYTES * 2
	if not rom.in_bounds(at, measurements):
		return {}
	var height: int = rom.u16le(at)
	var weight: int = rom.u16le(at + RomLayout.DEX_ENTRY_MEASUREMENT_BYTES)
	at += measurements

	# The page break is the terminator itself (macros/scripts/text.asm's `page`
	# is `db "@"`), so the two pages are simply two consecutive runs.
	var pages: PackedStringArray = PackedStringArray()
	for page: int in RomLayout.DEX_ENTRY_PAGES:
		if not rom.in_bounds(at):
			return {}
		pages.append(Gen2Text.decode(data, at, RomLayout.DEX_ENTRY_MAX_PAGE_LENGTH))
		at = Gen2Text.terminated_end(data, at, RomLayout.DEX_ENTRY_MAX_PAGE_LENGTH)
	if at > rom.size():
		return {}

	return {"category": category, "height": height, "weight": weight, "pages": pages}


## The evolution and learnset table, checked species by species.
##
## Nothing says which species an entry belongs to, so the shape is checked: 251
## pointers into the banked window, each naming evolutions whose methods come
## from a set of five and whose targets are real species, then level-up moves at
## real levels teaching real moves. A wrong pointer fails on its first byte,
## since most byte values are neither an evolution method nor a terminator. On
## top of that, levels ascend in all but one species, the totals are known, and
## both ends are independently known content.
static func verify_evos_attacks(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entries: Array = []
	var evolutions: int = 0

	for species: int in range(1, RomLayout.SPECIES_COUNT + 1):
		var entry: Dictionary = read_evos_attacks(rom, layout, species)
		if entry.is_empty():
			return {
				"ok": false,
				"message": "Species %d has no readable evolution and learnset entry." % species,
			}

		for evolution: Dictionary in entry["evolutions"]:
			var check: Dictionary = _evolution_check(species, evolution)
			if not check["ok"]:
				return check
		evolutions += (entry["evolutions"] as Array).size()

		var learnset: Array = entry["learnset"]
		# Every species learns something by levelling, even the ones that learn it
		# all at level one, so an empty run means the walk is not on the table.
		if learnset.is_empty():
			return {"ok": false, "message": "Species %d learns no moves at all." % species}

		var previous: int = 0
		for move: Dictionary in learnset:
			var level: int = int(move["level"])
			var number: int = int(move["move"])
			if level < 1 or level > RomLayout.MAX_LEVEL:
				return {
					"ok": false,
					"message": "Species %d learns a move at level %d." % [species, level],
				}
			if number < 1 or number > RomLayout.MOVE_COUNT:
				return {
					"ok": false,
					"message": "Species %d learns move %d, which does not exist." % [
						species, number,
					],
				}
			if level < previous and species != RomLayout.UNSORTED_LEARNSET_SPECIES:
				return {
					"ok": false,
					"message": "Species %d learns at level %d after level %d." % [
						species, level, previous,
					],
				}
			previous = level

		entries.append(entry)

	if evolutions != RomLayout.EVOLUTION_COUNT:
		return {
			"ok": false,
			"message": "Read %d evolutions, expected %d." % [
				evolutions, RomLayout.EVOLUTION_COUNT,
			],
		}

	return _verify_known_evos_attacks(entries)


## One evolution entry, checked against what its method is allowed to say.
static func _evolution_check(species: int, evolution: Dictionary) -> Dictionary:
	var method: int = int(evolution["method"])
	var parameter: int = int(evolution["parameter"])
	var target: int = int(evolution["target"])

	if target < 1 or target > RomLayout.SPECIES_COUNT:
		return {
			"ok": false,
			"message": "Species %d evolves into %d, which does not exist." % [species, target],
		}

	match method:
		RomLayout.EVOLVE_LEVEL, RomLayout.EVOLVE_STAT:
			if parameter < 1 or parameter > RomLayout.MAX_LEVEL:
				return {
					"ok": false,
					"message": "Species %d evolves at level %d." % [species, parameter],
				}
		RomLayout.EVOLVE_HAPPINESS:
			if parameter < RomLayout.TRIGGER_ANYTIME or parameter > RomLayout.TRIGGER_NITE:
				return {
					"ok": false,
					"message": "Species %d evolves on happiness trigger %d." % [species, parameter],
				}

	if method == RomLayout.EVOLVE_STAT:
		var condition: int = int(evolution["condition"])
		if condition < RomLayout.ATTACK_OVER_DEFENSE \
			or condition > RomLayout.ATTACK_EQUALS_DEFENSE:
			return {
				"ok": false,
				"message": "Species %d evolves on stat comparison %d." % [species, condition],
			}

	return {"ok": true, "message": ""}


## The three entries whose contents are known independently of the cartridge.
static func _verify_known_evos_attacks(entries: Array) -> Dictionary:
	var first: Dictionary = entries[0]
	var first_evolutions: Array = first["evolutions"]
	if first_evolutions.size() != 1 \
		or int(first_evolutions[0]["method"]) != RomLayout.EVOLVE_LEVEL \
		or int(first_evolutions[0]["parameter"]) != FIRST_EVOLUTION_LEVEL \
		or int(first_evolutions[0]["target"]) != 2:
		return {
			"ok": false,
			"message": "Species 1 should evolve into species 2 at level %d." % FIRST_EVOLUTION_LEVEL,
		}

	var first_learnset: Array = first["learnset"]
	if int(first_learnset[0]["level"]) != 1 \
		or int(first_learnset[0]["move"]) != FIRST_LEARNSET_MOVE:
		return {
			"ok": false,
			"message": "Species 1 should open with move %d at level 1, not move %d at level %d." % [
				FIRST_LEARNSET_MOVE, int(first_learnset[0]["move"]),
				int(first_learnset[0]["level"]),
			],
		}

	# The last species is the far end of the pointer table, and it is one of the
	# ones that never evolves.
	var last_evolutions: Array = entries[RomLayout.SPECIES_COUNT - 1]["evolutions"]
	if not last_evolutions.is_empty():
		return {
			"ok": false,
			"message": "Species %d should not evolve, and has %d evolutions." % [
				RomLayout.SPECIES_COUNT, last_evolutions.size(),
			],
		}

	var stat_evolutions: Array = entries[STAT_EVOLUTION_SPECIES - 1]["evolutions"]
	if stat_evolutions.size() != STAT_EVOLUTION_COUNT:
		return {
			"ok": false,
			"message": "Species %d should have %d evolutions, and has %d." % [
				STAT_EVOLUTION_SPECIES, STAT_EVOLUTION_COUNT, stat_evolutions.size(),
			],
		}
	for evolution: Dictionary in stat_evolutions:
		if int(evolution["method"]) != RomLayout.EVOLVE_STAT:
			return {
				"ok": false,
				"message": "Species %d should evolve on a stat comparison, and uses method %d." % [
					STAT_EVOLUTION_SPECIES, int(evolution["method"]),
				],
			}

	return {"ok": true, "message": ""}


## One of the two orderings `Pokedex_OrderMonsByMode` reads
## (data/pokemon/dex_order_new.asm, dex_order_alpha.asm), as species numbers.
## Empty if the table is outside the cartridge.
static func read_dex_order(rom: RomFile, layout: Dictionary, key: String) -> PackedInt32Array:
	var pokedex: Dictionary = layout["pokedex"]
	var at: int = int(pokedex.get(key, -1))
	if not rom.in_bounds(at, RomLayout.SPECIES_COUNT):
		return PackedInt32Array()
	var out: PackedInt32Array = PackedInt32Array()
	for index: int in RomLayout.SPECIES_COUNT:
		out.append(rom.u8(at + index))
	return out


## The Pokedex entries and the two order tables.
##
## The entries have no self-identifying field, so they are checked the way the
## palettes are: every one of the 251 has to walk to a category and two pages
## without leaving the cartridge, and the two ends have to say what they are
## independently known to say. A pointer table that is one entry out still walks
## into readable text, which is why the measurements are checked and not just
## the strings.
##
## Each order table has to be a permutation of the whole species range. That is
## a stronger check than a range check: a run of legal species numbers elsewhere
## in the bank would pass the latter, and only the real table has every species
## exactly once.
static func verify_pokedex(rom: RomFile, layout: Dictionary) -> Dictionary:
	if not layout.has("pokedex"):
		return {"ok": false, "message": "No Pokedex offsets for this game."}

	var entries: Array = []
	for species: int in range(1, RomLayout.SPECIES_COUNT + 1):
		var entry: Dictionary = read_dex_entry(rom, layout, species)
		if entry.is_empty():
			return {
				"ok": false,
				"message": "Pokedex entry %d does not read as an entry." % species,
			}
		if String(entry["category"]).is_empty():
			return {"ok": false, "message": "Pokedex entry %d has no category." % species}
		var pages: PackedStringArray = entry["pages"]
		for page: int in pages.size():
			if pages[page].is_empty():
				return {
					"ok": false,
					"message": "Pokedex entry %d has an empty page %d." % [species, page + 1],
				}
		entries.append(entry)

	var first: Dictionary = entries[0]
	if String(first["category"]) != DEX_FIRST_CATEGORY \
		or int(first["height"]) != DEX_FIRST_HEIGHT \
		or int(first["weight"]) != DEX_FIRST_WEIGHT:
		return {
			"ok": false,
			"message": "Pokedex entry 1: expected %s %d %d, read %s %d %d." % [
				DEX_FIRST_CATEGORY, DEX_FIRST_HEIGHT, DEX_FIRST_WEIGHT,
				String(first["category"]), int(first["height"]), int(first["weight"]),
			],
		}

	var last: Dictionary = entries[RomLayout.SPECIES_COUNT - 1]
	if String(last["category"]) != DEX_LAST_CATEGORY \
		or int(last["height"]) != DEX_LAST_HEIGHT \
		or int(last["weight"]) != DEX_LAST_WEIGHT:
		return {
			"ok": false,
			"message": "Pokedex entry %d: expected %s %d %d, read %s %d %d." % [
				RomLayout.SPECIES_COUNT, DEX_LAST_CATEGORY, DEX_LAST_HEIGHT, DEX_LAST_WEIGHT,
				String(last["category"]), int(last["height"]), int(last["weight"]),
			],
		}

	for order: Array in [
		["order_new", DEX_ORDER_NEW_FIRST], ["order_alpha", DEX_ORDER_ALPHA_FIRST],
	]:
		var key: String = order[0]
		var species_numbers: PackedInt32Array = read_dex_order(rom, layout, key)
		if species_numbers.size() != RomLayout.SPECIES_COUNT:
			return {"ok": false, "message": "Dex order table %s is outside the ROM." % key}
		if species_numbers[0] != int(order[1]):
			return {
				"ok": false,
				"message": "Dex order table %s: expected species %d first, read %d." % [
					key, int(order[1]), species_numbers[0],
				],
			}
		var seen: Dictionary = {}
		for number: int in species_numbers:
			if number < 1 or number > RomLayout.SPECIES_COUNT or seen.has(number):
				return {
					"ok": false,
					"message": "Dex order table %s is not a permutation: %d." % [key, number],
				}
			seen[number] = true

	return {"ok": true, "message": ""}


## The font carries no name and no number, so it is checked against the one
## thing that is known about it independently: the charmap.
##
## The font is indexed by character code, so the letters and digits [Gen2Text]
## claims must have ink and the runs it has no character for must be blank. Those
## runs sit between the alphabets, so an offset out by one tile drags a blank
## onto "z" and a glyph onto an unmapped code, failing both ways at once.
static func verify_font(rom: RomFile, layout: Dictionary) -> Dictionary:
	var offset: int = RomLayout.font_offset(layout)
	var length: int = RomLayout.FONT_TILES * Gen2Tiles.TILE_1BPP_BYTES
	if not rom.in_bounds(offset, length):
		return {"ok": false, "message": "Font runs past the end of the dump."}

	for run: Array in RomLayout.FONT_INK_RUNS:
		for code: int in range(run[0], run[1] + 1):
			if _glyph_ink(rom, offset, code) == 0:
				return {
					"ok": false,
					"message": "Font: code $%02X (%s) has no glyph." % [
						code, Gen2Text.character(code),
					],
				}

	for run: Array in RomLayout.FONT_BLANK_RUNS:
		for code: int in range(run[0], run[1] + 1):
			if _glyph_ink(rom, offset, code) != 0:
				return {
					"ok": false,
					"message": "Font: code $%02X has a glyph but no character." % code,
				}

	# No glyph fills a row of eight: every character leaves the spacing column
	# clear, and most leave more. A run of $FF is graphics, not a font.
	for i: int in length:
		if rom.u8(offset + i) == 0xFF:
			return {"ok": false, "message": "Font: solid row at byte %d; not font data." % i}

	return verify_font_extra(rom, layout)


## `FontExtra` has no address of its own: it is the entry before `Font` in
## `gfx/font.asm`, so it is checked by what it draws. Every code
## `_LoadFontsExtra1` puts on screen is a glyph, and the ellipsis is one row of
## three dots on the seventh, which no neighbouring sheet read a tile early or
## late reproduces.
static func verify_font_extra(rom: RomFile, layout: Dictionary) -> Dictionary:
	var offset: int = RomLayout.font_extra_offset(layout)
	if not rom.in_bounds(offset, RomLayout.FONT_EXTRA_TILES * Gen2Tiles.TILE_BYTES):
		return {"ok": false, "message": "FontExtra runs past the end of the dump."}

	for code: int in range(
		RomLayout.FONT_EXTRA_LOADED_FIRST, RomLayout.FONT_EXTRA_LOADED_LAST + 1
	):
		if _extra_glyph_rows(rom, offset, code).count(0) == Gen2Tiles.TILE_1BPP_BYTES:
			return {
				"ok": false,
				"message": "FontExtra: code $%02X has no glyph." % code,
			}

	var ellipsis: Array[int] = _extra_glyph_rows(rom, offset, Gen2Text.ELLIPSIS_CODE)
	if ellipsis[6] == 0 or ellipsis.count(0) != Gen2Tiles.TILE_1BPP_BYTES - 1:
		return {
			"ok": false,
			"message": "FontExtra: $%02X is not the ellipsis." % Gen2Text.ELLIPSIS_CODE,
		}

	return {"ok": true, "message": ""}


## One 2bpp tile of `FontExtra` as eight row masks, a set bit per lit pixel.
static func _extra_glyph_rows(rom: RomFile, offset: int, code: int) -> Array[int]:
	var at: int = offset \
		+ (code - RomLayout.FONT_EXTRA_FIRST_CODE) * Gen2Tiles.TILE_BYTES
	var rows: Array[int] = []
	for row: int in Gen2Tiles.TILE_1BPP_BYTES:
		rows.append(rom.u8(at + 2 * row) | rom.u8(at + 2 * row + 1))
	return rows


## Ink in the tile for one character code, in pixels.
static func _glyph_ink(rom: RomFile, offset: int, code: int) -> int:
	var at: int = offset + (code - RomLayout.FONT_FIRST_CODE) * Gen2Tiles.TILE_1BPP_BYTES
	var ink: int = 0
	for row: int in Gen2Tiles.TILE_1BPP_BYTES:
		var byte: int = rom.u8(at + row)
		for bit: int in 8:
			ink += (byte >> bit) & 1
	return ink


## Frames are checked by the shape a border has to have rather than by content,
## because all eight are decoration and none of them says which it is.
static func verify_frames(rom: RomFile, layout: Dictionary) -> Dictionary:
	var seen: Array = []

	for frame: int in RomLayout.FRAME_COUNT:
		var offset: int = RomLayout.frame_offset(layout, frame)
		var tiles: PackedByteArray = rom.slice(
			offset, RomLayout.FRAME_TILES * Gen2Tiles.TILE_1BPP_BYTES
		)
		if tiles.is_empty():
			return {"ok": false, "message": "Frame %d runs past the end of the dump." % frame}

		# A border is inset from the top of its tile row, so the top-left, top and
		# top-right tiles all open with blank scanlines.
		for tile: int in [
			RomLayout.FRAME_TOP_LEFT, RomLayout.FRAME_HORIZONTAL, RomLayout.FRAME_TOP_RIGHT
		]:
			for row: int in 2:
				if tiles[tile * Gen2Tiles.TILE_1BPP_BYTES + row] != 0:
					return {
						"ok": false,
						"message": "Frame %d tile %d has ink on row %d of its top edge." % [
							frame, tile, row,
						],
					}

		# The two bottom corners continue the vertical edge they hang from, so
		# their first row is one the vertical tile also draws.
		var left: int = tiles[RomLayout.FRAME_BOTTOM_LEFT * Gen2Tiles.TILE_1BPP_BYTES]
		var right: int = tiles[RomLayout.FRAME_BOTTOM_RIGHT * Gen2Tiles.TILE_1BPP_BYTES]
		if left == 0 or left != right:
			return {
				"ok": false,
				"message": "Frame %d corners do not meet its sides ($%02X, $%02X)." % [
					frame, left, right,
				],
			}
		var vertical: PackedByteArray = tiles.slice(
			RomLayout.FRAME_VERTICAL * Gen2Tiles.TILE_1BPP_BYTES,
			(RomLayout.FRAME_VERTICAL + 1) * Gen2Tiles.TILE_1BPP_BYTES
		)
		if not vertical.has(left):
			return {
				"ok": false,
				"message": "Frame %d side never draws $%02X, which its corners do." % [frame, left],
			}

		# Eight identical frames would mean the table is not where it is claimed
		# to be, or is not a table at all.
		if seen.has(tiles):
			return {"ok": false, "message": "Frame %d repeats an earlier frame." % frame}
		seen.append(tiles)

	return {"ok": true, "message": ""}


## The battle HUD's graphics, checked by the one thing they do that nothing else
## in the section does: they count. The pinned palette values every bar and page
## is drawn with are checked here too, the stats screen's included: they are the
## same bars and the same kind of check.
##
## A bar's fill levels are consecutive tiles each lighting one more column, so
## the ink climbs by exactly two pixels a step, which a wrong offset does not
## land on. The two HUD borders have neither content nor a progression, so they
## are checked like the text box frames: every tile has ink, no two alike.
static func verify_battle_graphics(rom: RomFile, layout: Dictionary) -> Dictionary:
	var data: PackedByteArray = rom.bytes()

	# The bar palettes are known values rather than a shape, so they are checked
	# as the species names are: against what they have to say.
	for index: int in RomLayout.BAR_PALETTE_NAMES.size():
		var entry: int = RomLayout.bar_palette_offset(layout, index)
		var wanted: Array = RomLayout.BAR_PALETTES[index]
		for colour: int in wanted.size():
			var read: int = rom.u16le(entry + colour * Gen2Palette.COLOR_BYTES)
			if read != int(wanted[colour]):
				return {
					"ok": false,
					"message": "Bar palette %s colour %d: expected $%04X, read $%04X." % [
						RomLayout.BAR_PALETTE_NAMES[index], colour, wanted[colour], read,
					],
				}

	# `StatsScreenPagePals` and `StatsScreenPals`, one run and one check: the
	# three tints are the three page palettes' own colour 1, so a run that reads
	# right in both halves cannot be the wrong run.
	for index: int in RomLayout.STATS_PAGE_PALETTES:
		var page: int = RomLayout.stats_page_palette_offset(layout, index)
		var wanted_page: Array = RomLayout.STATS_SCREEN_PAGE_PALETTES[index]
		for colour: int in wanted_page.size():
			var read_page: int = rom.u16le(page + colour * Gen2Palette.COLOR_BYTES)
			if read_page != int(wanted_page[colour]):
				return {
					"ok": false,
					"message": "Stats page palette %d colour %d: expected $%04X, read $%04X." % [
						index, colour, wanted_page[colour], read_page,
					],
				}
		var tint: int = rom.u16le(RomLayout.stats_page_tint_offset(layout, index))
		if tint != int(RomLayout.STATS_SCREEN_PAGE_TINTS[index]):
			return {
				"ok": false,
				"message": "Stats page tint %d: expected $%04X, read $%04X." % [
					index, RomLayout.STATS_SCREEN_PAGE_TINTS[index], tint,
				],
			}

	# `BattleObjectPals`, checked the same way and for the same reason: a palette
	# table one table out still decodes into colours.
	for index: int in RomLayout.BATTLE_OBJECT_PALETTES_STORED:
		var wanted: Array = RomLayout.BATTLE_OBJECT_PALETTES[index]
		for colour: int in wanted.size():
			var read: int = rom.u16le(
				int(layout["battle_object_palettes"])
					+ (index * RomLayout.BATTLE_OBJECT_PALETTE_COLORS + colour)
					* Gen2Palette.COLOR_BYTES
			)
			if read != int(wanted[colour]):
				return {
					"ok": false,
					"message": "Battle object palette %s colour %d: expected $%04X, read $%04X." % [
						RomLayout.BATTLE_OBJECT_PALETTE_NAMES[index], colour,
						wanted[colour], read,
					],
				}

	var battle_font: PackedByteArray = Gen2Tiles.decode_2bpp_strip(
		data, int(layout["battle_font"]), RomLayout.BATTLE_FONT_TILES
	)
	var hp_bar: Dictionary = _verify_bar(
		battle_font, RomLayout.BATTLE_FONT_TILES, RomLayout.HP_BAR_FIRST_TILE,
		RomLayout.HP_BAR_LEVELS, "HP bar"
	)
	if not hp_bar["ok"]:
		return hp_bar

	var exp_bar: PackedByteArray = Gen2Tiles.decode_2bpp_strip(
		data, int(layout["exp_bar"]), RomLayout.EXP_BAR_TILES
	)
	var levels: Dictionary = _verify_bar(
		exp_bar, RomLayout.EXP_BAR_TILES, 0, RomLayout.EXP_BAR_LEVELS, "exp bar"
	)
	if not levels["ok"]:
		return levels

	## `StatsScreenPageTilesGFX` carries no progression to sweep, so it is
	## checked on the two tiles the source names by shape: tile 0 is the
	## vertical divider, two lit columns on every row, and tile 14 is the `'⁂'`
	## `constants/charmap.asm` points at. Both pin the address, which is walked
	## back from the enemy HUD rather than stored.
	var stats_tiles: PackedByteArray = Gen2Tiles.decode_2bpp_strip(
		data, RomLayout.stats_tiles_offset(layout), RomLayout.STATS_TILES
	)
	var divider: PackedByteArray = _strip_tile(
		stats_tiles, RomLayout.STATS_TILES, 0
	)
	for row: int in Gen2Tiles.TILE_HEIGHT:
		for column: int in Gen2Tiles.TILE_WIDTH:
			var lit: bool = divider[row * Gen2Tiles.TILE_WIDTH + column] != 0
			if lit != (column < 2):
				return {
					"ok": false,
					"message": "Stats tiles: the vertical divider is not two columns wide.",
				}
	if _ink(_strip_tile(stats_tiles, RomLayout.STATS_TILES, RomLayout.STATS_SHINY_TILE)) == 0:
		return {"ok": false, "message": "Stats tiles: the shiny icon is blank."}

	for name: String in ["enemy_hud", "player_hud"]:
		var tiles: int = RomLayout.ENEMY_HUD_TILES if name == "enemy_hud" \
			else RomLayout.PLAYER_HUD_TILES
		var strip: PackedByteArray = Gen2Tiles.decode_1bpp_strip(
			data, int(layout[name]), tiles
		)
		var seen: Array = []
		for tile: int in tiles:
			var pixels: PackedByteArray = _strip_tile(strip, tiles, tile)
			if _ink(pixels) == 0:
				return {"ok": false, "message": "%s tile %d is blank." % [name, tile]}
			if seen.has(pixels):
				return {"ok": false, "message": "%s tile %d repeats an earlier one." % [name, tile]}
			seen.append(pixels)

	return {"ok": true, "message": ""}


## One bar's fill levels: consecutive tiles whose ink climbs by a fixed step.
static func _verify_bar(
	strip: PackedByteArray, tiles: int, first: int, levels: int, what: String
) -> Dictionary:
	if strip.size() != tiles * Gen2Tiles.TILE_WIDTH * Gen2Tiles.TILE_HEIGHT:
		return {"ok": false, "message": "%s: strip decoded short." % what}

	var previous: int = _ink(_strip_tile(strip, tiles, first))
	if previous == 0:
		return {"ok": false, "message": "%s: the empty level has no ink." % what}

	for level: int in range(1, levels):
		var ink: int = _ink(_strip_tile(strip, tiles, first + level))
		if ink != previous + RomLayout.BAR_STEP_PIXELS:
			return {
				"ok": false,
				"message": "%s: level %d has %d pixels, expected %d." % [
					what, level, ink, previous + RomLayout.BAR_STEP_PIXELS,
				],
			}
		previous = ink

	return {"ok": true, "message": ""}


## One tile out of a strip, as its own buffer.
static func _strip_tile(strip: PackedByteArray, tiles: int, tile: int) -> PackedByteArray:
	var width: int = tiles * Gen2Tiles.TILE_WIDTH
	var out: PackedByteArray = PackedByteArray()
	out.resize(Gen2Tiles.TILE_PIXELS)
	for row: int in Gen2Tiles.TILE_HEIGHT:
		for column: int in Gen2Tiles.TILE_WIDTH:
			out[row * Gen2Tiles.TILE_WIDTH + column] = strip[
				row * width + tile * Gen2Tiles.TILE_WIDTH + column
			]
	return out


## Lit pixels in a decoded tile, whatever colour they are.
static func _ink(pixels: PackedByteArray) -> int:
	var out: int = 0
	for index: int in pixels:
		if index != 0:
			out += 1
	return out


## The three trainer tables, each checked by what is known about it independently.
##
## Checked together because they are three views of one numbering, so a mistake
## shows up as the three disagreeing: names say what a class is, the palette
## table has one entry more than the pic table because the player owns the first,
## and pic entries must decompress to the one size every trainer is drawn at.
static func verify_trainers(rom: RomFile, layout: Dictionary) -> Dictionary:
	var count: int = RomLayout.trainer_class_count(layout)
	var names: PackedStringArray = Gen2Text.decode_sequence(
		rom.bytes(), int(layout["trainer_class_names"]), count, RomLayout.MAX_NAME_LENGTH
	)
	if names.size() != count:
		return {"ok": false, "message": "Trainer class names ran out after %d." % names.size()}
	# Falkner opens the table, and the classes are terminated rather than padded,
	# so the far end is checked as well as the near one. The class in the middle
	# catches a start that is right and a walk that is not.
	if names[0] != TRAINER_FIRST_CLASS:
		return {
			"ok": false,
			"message": "Trainer class 1: expected %s, read %s." % [TRAINER_FIRST_CLASS, names[0]],
		}
	if names[TRAINER_MIDDLE_CLASS - 1] != TRAINER_MIDDLE_CLASS_NAME:
		return {
			"ok": false,
			"message": "Trainer class %d: expected %s, read %s." % [
				TRAINER_MIDDLE_CLASS, TRAINER_MIDDLE_CLASS_NAME, names[TRAINER_MIDDLE_CLASS - 1],
			],
		}
	var last_class: String = String(layout["trainer_last_class"])
	if names[count - 1] != last_class:
		return {
			"ok": false,
			"message": "Trainer class %d: expected %s, read %s." % [
				count, last_class, names[count - 1],
			],
		}

	# Palettes are checked structurally, as the species ones are, and then at one
	# entry past the end: the table is the player plus every class, so whatever
	# follows it must not read as a palette. Without that, an offset that slid by
	# a whole entry would pass every check above it.
	for trainer_class: int in range(0, count + 1):
		var check: Dictionary = _trainer_palette_check(rom, layout, trainer_class)
		if not check["ok"]:
			return check
	if _trainer_palette_check(rom, layout, count + 1)["ok"]:
		return {
			"ok": false,
			"message": "Trainer palette table has a %dth entry; it should end at %d." % [
				count + 2, count + 1,
			],
		}

	# Every pointer has to address the switchable window of a bank that exists.
	# The two ends are decompressed as well, which is what proves the bank repair
	# is the same one the Pokémon pics need.
	var lz := Gen2Lz.new()
	var wanted: int = RomLayout.TRAINER_PIC_TILES * RomLayout.TRAINER_PIC_TILES \
		* Gen2Tiles.TILE_BYTES
	for trainer_class: int in range(1, count + 1):
		var offset: int = RomLayout.trainer_pic_pointer_offset(layout, trainer_class)
		var pointer: Dictionary = rom.far_pointer(offset)
		var address: int = int(pointer["address"])
		if address < RomFile.BANK_SIZE or address >= RomFile.BANK_SIZE * 2:
			return {
				"ok": false,
				"message": "Trainer pic %d points at $%04X, outside the banked window." % [
					trainer_class, address,
				],
			}
		var start: int = RomFile.linear(
			RomLayout.fix_pic_bank(layout, int(pointer["bank"])), address
		)
		if not rom.in_bounds(start):
			return {"ok": false, "message": "Trainer pic %d points past the dump." % trainer_class}
		if trainer_class != 1 and trainer_class != count:
			continue
		var raw: PackedByteArray = lz.decompress(rom.bytes(), start)
		if lz.failed or raw.size() < wanted:
			return {
				"ok": false,
				"message": "Trainer pic %d decompressed to %d bytes, wanted %d." % [
					trainer_class, raw.size(), wanted,
				],
			}

	return {"ok": true, "message": ""}


## One trainer palette entry, checked the way a species' is: fifteen-bit colours,
## and never two blacks.
static func _trainer_palette_check(
	rom: RomFile, layout: Dictionary, trainer_class: int
) -> Dictionary:
	var entry: int = RomLayout.trainer_palette_offset(layout, trainer_class)
	if not rom.in_bounds(entry, Gen2Palette.PAIR_BYTES):
		return {"ok": false, "message": "Trainer palette %d is past the end." % trainer_class}

	var first: int = rom.u16le(entry)
	var second: int = rom.u16le(entry + Gen2Palette.COLOR_BYTES)
	if (first | second) & 0x8000:
		return {
			"ok": false,
			"message": "Trainer palette %d has bit 15 set ($%04X, $%04X)." % [
				trainer_class, first, second,
			],
		}
	if first == 0 and second == 0:
		return {"ok": false, "message": "Trainer palette %d is blank." % trainer_class}
	return {"ok": true, "message": ""}


## Reads the whole trainer party table in one pass: every class's individual
## trainers, each a name, a type and a party.
##
## Not [method verify_trainers]'s table: that is the class every gym leader
## shares ("LEADER"), this is the trainer inside it ("FALKNER"), read through
## different pointers, one per class in both.
##
## Nothing in a class's bytes says where its group ends, so its span is bounded
## by the *next* class's pointer, and the last class is walked until a byte that
## cannot open a name. One class per game shares its pointer with the next, the
## one class never sent into battle: its honest span is empty, not a copy of the
## next. See [constant RomLayout.EMPTY_TRAINER_CLASS].
##
## Returns { ok, message, classes, total }, [code]classes[/code] being one Array
## of trainers per class, in order.
static func read_trainer_parties(rom: RomFile, layout: Dictionary) -> Dictionary:
	var count: int = RomLayout.trainer_class_count(layout)
	var table: int = int(layout["trainer_parties"])
	var bank: int = RomLayout.bank_of(table)

	var pointers: Array = []
	for trainer_class: int in range(1, count + 1):
		var offset: int = RomLayout.trainer_party_pointer_offset(layout, trainer_class)
		if not rom.in_bounds(offset, RomLayout.TRAINER_PARTY_POINTER_SIZE):
			return {
				"ok": false,
				"message": "Trainer party pointer %d is past the end." % trainer_class,
			}
		pointers.append(rom.u16le(offset))

	var classes: Array = []
	var total: int = 0
	for trainer_class: int in range(1, count + 1):
		var address: int = pointers[trainer_class - 1]
		if address < RomFile.BANK_SIZE or address >= RomFile.BANK_SIZE * 2:
			return {
				"ok": false,
				"message": "Trainer class %d's party points at $%04X, outside the banked window." % [
					trainer_class, address,
				],
			}
		var at: int = RomFile.linear(bank, address)

		# The pointers are non-decreasing in class order in every game but one,
		# so the class after this one is what bounds it; the walk itself proves
		# the offset, because a span that has slid cannot tile the region.
		var end: int = -1
		if trainer_class < count:
			var next_address: int = pointers[trainer_class]
			if next_address < address:
				return {
					"ok": false,
					"message": "Trainer class %d's party pointer goes backwards." % trainer_class,
				}
			end = RomFile.linear(bank, next_address)

		var group: Dictionary = _read_trainer_group(rom, at, end)
		if not group["ok"]:
			return {
				"ok": false,
				"message": "Trainer class %d: %s" % [trainer_class, group["message"]],
			}

		classes.append(group["trainers"])
		total += (group["trainers"] as Array).size()

	return {"ok": true, "message": "", "classes": classes, "total": total}


## One class's span of trainers: read from [param start] to exactly
## [param end], or, when [param end] is negative because this is the last
## class, until a byte that cannot open a name (the padding past the real
## table) is met. A span that overshoots [param end] is caught here rather than
## left for the next class to notice, because there may not be a next class.
static func _read_trainer_group(rom: RomFile, start: int, end: int) -> Dictionary:
	var trainers: Array = []
	var at: int = start

	while true:
		if end >= 0:
			if at == end:
				break
			if at > end:
				return {"ok": false, "message": "a trainer's own party walked past the next class."}
		elif not rom.in_bounds(at) or rom.u8(at) == 0:
			break

		if trainers.size() >= RomLayout.MAX_TRAINERS_PER_CLASS:
			return {"ok": false, "message": "more trainers than any real class carries."}

		var trainer: Dictionary = _read_one_trainer(rom, at)
		if trainer.is_empty():
			return {"ok": false, "message": "a trainer at $%X did not parse." % at}

		trainers.append(trainer)
		at = int(trainer["_next"])

	return {"ok": true, "message": "", "trainers": trainers}


## One trainer: a $50-terminated name, a type byte, its Pokémon and $FF. Returns
## an empty Dictionary for anything that does not parse as that shape, which is
## most byte values, since a level, a species and a move number are all
## range-checked as they are read.
static func _read_one_trainer(rom: RomFile, at: int) -> Dictionary:
	var start: int = at
	var end: int = at
	while rom.in_bounds(end) and rom.u8(end) != Gen2Text.TERMINATOR:
		end += 1
		if end - start > RomLayout.MAX_NAME_LENGTH:
			return {}
	if not rom.in_bounds(end):
		return {}
	var name: String = Gen2Text.decode(rom.bytes(), start, end - start)

	var pos: int = end + 1
	if not rom.in_bounds(pos):
		return {}
	var mon_type: int = rom.u8(pos)
	if not RomLayout.TRAINER_MON_TYPES.has(mon_type):
		return {}
	pos += 1

	var party: Array = []
	while rom.in_bounds(pos) and rom.u8(pos) != RomLayout.TRAINER_PARTY_END:
		if party.size() >= RomLayout.MAX_TRAINER_PARTY_SIZE:
			return {}
		if not rom.in_bounds(pos, 2):
			return {}
		var level: int = rom.u8(pos)
		var species: int = rom.u8(pos + 1)
		if level < 1 or level > RomLayout.MAX_LEVEL:
			return {}
		if species < 1 or species > RomLayout.SPECIES_COUNT:
			return {}
		pos += 2

		var extra: int = RomLayout.trainer_mon_extra_size(mon_type)
		if not rom.in_bounds(pos, extra):
			return {}
		var item: int = 0
		var moves: Array = []
		if mon_type == RomLayout.TRAINER_MON_ITEM or mon_type == RomLayout.TRAINER_MON_ITEM_MOVES:
			item = rom.u8(pos)
			pos += 1
		if mon_type == RomLayout.TRAINER_MON_MOVES or mon_type == RomLayout.TRAINER_MON_ITEM_MOVES:
			for slot: int in RomLayout.TRAINER_MON_MOVE_COUNT:
				var move: int = rom.u8(pos + slot)
				if move > RomLayout.MOVE_COUNT:
					return {}
				moves.append(move)
			pos += RomLayout.TRAINER_MON_MOVE_COUNT

		party.append({"level": level, "species": species, "item": item, "moves": moves})

	if not rom.in_bounds(pos) or party.is_empty():
		return {}
	pos += 1

	return {"name": name, "type": mon_type, "party": party, "_next": pos}


## The trainer party table, checked by everything known about it independently:
## the walk itself (see [method _read_trainer_group]), the one class with no
## party of its own, the total trainer count, and Falkner's team at one end and
## the last class's first trainer's name at the other.
static func verify_trainer_parties(rom: RomFile, layout: Dictionary) -> Dictionary:
	var result: Dictionary = read_trainer_parties(rom, layout)
	if not result["ok"]:
		return result

	var classes: Array = result["classes"]
	if int(result["total"]) != int(layout["trainer_party_total"]):
		return {
			"ok": false,
			"message": "Read %d trainers, expected %d." % [
				result["total"], layout["trainer_party_total"],
			],
		}

	for trainer_class: int in range(1, classes.size() + 1):
		var group: Array = classes[trainer_class - 1]
		var should_be_empty: bool = trainer_class == RomLayout.EMPTY_TRAINER_CLASS
		if should_be_empty != group.is_empty():
			return {
				"ok": false,
				"message": "Trainer class %d has %d trainers; expected %s." % [
					trainer_class, group.size(), "none" if should_be_empty else "at least one",
				],
			}

	var falkner: Dictionary = classes[0][0]
	if String(falkner["name"]) != TRAINER_PARTY_FIRST_NAME:
		return {
			"ok": false,
			"message": "Trainer class 1's first trainer: expected %s, read %s." % [
				TRAINER_PARTY_FIRST_NAME, falkner["name"],
			],
		}
	var falkner_party: Array = falkner["party"]
	if falkner_party.size() != 2 \
		or int(falkner_party[0]["level"]) != TRAINER_PARTY_FIRST_LEVEL_1 \
		or int(falkner_party[0]["species"]) != TRAINER_PARTY_FIRST_SPECIES_1 \
		or int(falkner_party[1]["level"]) != TRAINER_PARTY_FIRST_LEVEL_2 \
		or int(falkner_party[1]["species"]) != TRAINER_PARTY_FIRST_SPECIES_2:
		return {"ok": false, "message": "Falkner's party does not match what is known of it."}

	var last_group: Array = classes[classes.size() - 1]
	var last_trainer: Dictionary = last_group[0]
	var wanted_last: String = String(layout["trainer_party_last_trainer"])
	if String(last_trainer["name"]) != wanted_last:
		return {
			"ok": false,
			"message": "Last trainer class's first trainer: expected %s, read %s." % [
				wanted_last, last_trainer["name"],
			],
		}

	return {"ok": true, "message": ""}


## One trainer class's own entry in the attributes table: two item numbers,
## a base money reward, and the two flag words the AI reads. A fixed stride,
## not a pointer, so unlike the party table nothing here is walked.
static func read_trainer_attributes(rom: RomFile, layout: Dictionary, trainer_class: int) -> Dictionary:
	var offset: int = RomLayout.trainer_attributes_offset(layout, trainer_class)
	return {
		"item1": rom.u8(offset + RomLayout.ATTR_ITEM1),
		"item2": rom.u8(offset + RomLayout.ATTR_ITEM2),
		"base_reward": rom.u8(offset + RomLayout.ATTR_BASE_REWARD),
		"ai_move_weights": rom.u16le(offset + RomLayout.ATTR_AI_MOVE_WEIGHTS),
		"ai_item_switch": rom.u16le(offset + RomLayout.ATTR_AI_ITEM_SWITCH),
	}


## The trainer attributes table, checked entry by entry: neither flag word may
## carry a bit past what [constant RomLayout.AI_MOVE_WEIGHTS_MASK] and
## [constant RomLayout.AI_ITEM_SWITCH_MASK] define, which a wrong offset fails
## almost immediately and has to pass 66 or 67 times running to slip through by
## chance. Falkner's own entry is content whose answer is known independently,
## the same anchor [constant TRAINER_FIRST_CLASS] gives the class name table.
static func verify_trainer_attributes(rom: RomFile, layout: Dictionary) -> Dictionary:
	var count: int = RomLayout.trainer_class_count(layout)

	for trainer_class: int in range(1, count + 1):
		var offset: int = RomLayout.trainer_attributes_offset(layout, trainer_class)
		if not rom.in_bounds(offset, RomLayout.TRAINER_ATTRIBUTES_SIZE):
			return {
				"ok": false,
				"message": "Trainer attributes %d is past the end." % trainer_class,
			}

		var entry: Dictionary = read_trainer_attributes(rom, layout, trainer_class)
		var weights: int = int(entry["ai_move_weights"])
		if weights & ~RomLayout.AI_MOVE_WEIGHTS_MASK:
			return {
				"ok": false,
				"message": "Trainer attributes %d: AI move weights $%04X use undefined bits." % [
					trainer_class, weights,
				],
			}
		var switch_flags: int = int(entry["ai_item_switch"])
		if switch_flags & ~RomLayout.AI_ITEM_SWITCH_MASK:
			return {
				"ok": false,
				"message": "Trainer attributes %d: item/switch flags $%04X use undefined bits." % [
					trainer_class, switch_flags,
				],
			}

	var falkner: Dictionary = read_trainer_attributes(rom, layout, 1)
	if int(falkner["item1"]) != 0 or int(falkner["item2"]) != 0 \
		or int(falkner["base_reward"]) != TRAINER_ATTR_FIRST_REWARD \
		or int(falkner["ai_move_weights"]) != TRAINER_ATTR_FIRST_AI_MOVE_WEIGHTS \
		or int(falkner["ai_item_switch"]) != TRAINER_ATTR_FIRST_AI_ITEM_SWITCH:
		return {"ok": false, "message": "Trainer class 1's attributes do not match what is known of it."}

	return {"ok": true, "message": ""}


## One trainer class's own entry in the DVs table, packed into the same DV word
## shape [method Gen2BattleMon.create] takes as [code]dv_word[/code]: the two
## raw bytes read as one big-endian integer are already attack, defense, speed
## and special in [method Gen2Stats.pack_dvs]'s own nibble order, so nothing
## here has to unpack and repack them.
static func read_trainer_dvs(rom: RomFile, layout: Dictionary, trainer_class: int) -> int:
	var offset: int = RomLayout.trainer_dvs_offset(layout, trainer_class)
	return (rom.u8(offset) << 8) | rom.u8(offset + 1)


## No structural shape to check: every nibble is a legal DV, so a wrong offset
## still looks plausible. Settled by content known independently at both ends,
## like the move and item name tables: Falkner opens with his own known DVs, and
## the closing class (different per game, since only Crystal carries MYSTICALMAN)
## carries its own as [code]trainer_dvs_last[/code].
static func verify_trainer_dvs(rom: RomFile, layout: Dictionary) -> Dictionary:
	var count: int = RomLayout.trainer_class_count(layout)
	var last_offset: int = RomLayout.trainer_dvs_offset(layout, count)
	if not rom.in_bounds(last_offset, RomLayout.TRAINER_DVS_SIZE):
		return {"ok": false, "message": "Trainer DVs table is past the end."}

	var falkner: int = read_trainer_dvs(rom, layout, 1)
	if falkner != TRAINER_DVS_FIRST:
		return {
			"ok": false,
			"message": "Trainer class 1's DVs: expected $%04X, read $%04X." % [
				TRAINER_DVS_FIRST, falkner,
			],
		}

	var last: int = read_trainer_dvs(rom, layout, count)
	var expected_last: int = int(layout["trainer_dvs_last"])
	if last != expected_last:
		return {
			"ok": false,
			"message": "Trainer class %d's DVs: expected $%04X, read $%04X." % [
				count, expected_last, last,
			],
		}

	return {"ok": true, "message": ""}


## Resolves one entry of the type name pointer table.
static func type_name(rom: RomFile, layout: Dictionary, type_number: int) -> String:
	var table: int = RomLayout.type_name_pointer_offset(layout, type_number)
	var address: int = rom.u16le(table)
	var offset: int = RomFile.linear(RomLayout.bank_of(table), address)
	return Gen2Text.decode(rom.bytes(), offset, RomLayout.MAX_NAME_LENGTH)


## Imports [param rom] into its cache directory, replacing whatever was there.
##
## [param on_progress] is called as [code](stage, done, total)[/code] if given.
## Returns { ok, message, directory, species, elapsed_ms }.
func import_rom(rom: RomFile, on_progress: Callable = Callable()) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	var directory: String = RomCache.directory_for(rom.id, rom.sha1)
	var result: Dictionary = {
		"ok": false,
		"message": "",
		"directory": directory,
		"species": 0,
		"moves": 0,
		"items": 0,
		"types": 0,
		"matchups": 0,
		"trainers": 0,
		"trainer_party_count": 0,
		"evolutions": 0,
		"learnset_moves": 0,
		"egg_moves": 0,
		"maps": 0,
		"tilesets": 0,
		"overworld_sprites": 0,
		"menus": 0,
		"marts": 0,
		"phone_contacts": 0,
		"special_phone_calls": 0,
		"phone_scripts": 0,
		"music": 0,
		"sfx": 0,
		"battle_anims": 0,
		"battle_anim_gfx_tiles": 0,
		"elapsed_ms": 0,
	}

	var layout: Dictionary = RomLayout.for_id(rom.id)
	var check: Dictionary = verify_layout(rom)
	if not check["ok"]:
		result["message"] = check["message"]
		return result

	# A half-written cache from an interrupted run must not be mistaken for a
	# good one, so the old directory goes before the new one is built and the
	# manifest is only marked complete at the very end.
	RomCache.clear(directory)
	if not RomCache.prepare(directory):
		result["message"] = "Could not create %s." % directory
		return result

	var species: Array = _import_species(rom, layout, on_progress)
	if species.is_empty():
		result["message"] = "Decoded no species."
		return result

	var pics: Dictionary = _import_pics(rom, layout, species, on_progress)
	if pics.is_empty():
		result["message"] = "Could not decode pics."
		return result

	# Crystal's alone; Gold and Silver have no pic animation, so an empty answer
	# is the honest one rather than a failure.
	var pic_anims: Dictionary = _import_pic_anims(rom, layout, species)
	if pic_anims.is_empty() and not RomLayout.pic_anim(layout).is_empty():
		result["message"] = "Could not decode pic animations."
		return result

	var tiles: Dictionary = _import_tiles(rom, layout, on_progress)
	if tiles.is_empty():
		result["message"] = "Could not write the font."
		return result

	var dex_orders: Dictionary = _import_dex_orders(rom, layout)
	if dex_orders.is_empty():
		result["message"] = "Dex order tables are outside the cartridge."
		return result

	var moves: Array = _import_moves(rom, layout, on_progress)
	var tmhm_moves: Array = _import_tmhm_moves(rom, layout)
	if tmhm_moves.is_empty():
		result["message"] = "TM/HM move table is outside the cartridge or malformed."
		return result
	var happiness_changes: Array = _import_happiness_changes(rom, layout)
	if happiness_changes.is_empty():
		result["message"] = "Happiness change table is outside the cartridge or malformed."
		return result
	var name_input_chars: Array = _import_name_input_chars(rom, layout)
	var string_buffers: Array = _import_string_buffer_pointers(rom, layout)
	var intro_text: Dictionary = _import_intro_text(rom, layout)
	if intro_text.is_empty():
		result["message"] = "Intro text is outside the cartridge or malformed."
		return result
	var items: Array = _import_items(rom, layout, on_progress)
	var trades: Array = _import_world_trades(rom, layout)
	var types: Array = _import_types(rom, layout, on_progress)
	var matchups: Array = read_matchups(rom, layout)
	var trainers: Array = _import_trainers(rom, layout, on_progress)
	var world: Dictionary = Gen2WorldImporter.import_to_cache(rom, layout, directory, on_progress)
	if not bool(world.get("ok", false)):
		result["message"] = String(world.get("message", "Could not import overworld data."))
		return result
	var encounters: Dictionary = Gen2WorldEncounterImporter.import_to_cache(rom, layout, directory)
	if not bool(encounters.get("ok", false)):
		result["message"] = String(encounters.get("message", "Could not import wild encounter data."))
		return result
	var services: Dictionary = Gen2WorldServicesImporter.import_to_cache(
		rom, layout, directory,
		world.get("scripts", {}), world.get("standard_scripts", {}),
		world.get("text", {}), world.get("movements", {})
	)
	if not bool(services.get("ok", false)):
		result["message"] = String(services.get("message", "Could not import world service data."))
		return result
	var battle_anims: Dictionary = Gen2BattleAnimImporter.import_to_cache(rom, layout, directory)
	if not bool(battle_anims.get("ok", false)):
		result["message"] = String(
			battle_anims.get("message", "Could not import battle animation data.")
		)
		return result

	if not RomCache.write_json(RomCache.species_path(directory), species):
		result["message"] = "Could not write species data."
		return result
	if not pic_anims.is_empty() and not RomCache.write_section(
		RomCache.pic_anims_path(directory),
		RomCache.blob_path(RomCache.pic_anims_path(directory)), pic_anims
	):
		result["message"] = "Could not write pic animation data."
		return result
	if not RomCache.write_json(RomCache.moves_path(directory), moves):
		result["message"] = "Could not write move data."
		return result
	if not RomCache.write_json(RomCache.tmhm_moves_path(directory), tmhm_moves):
		result["message"] = "Could not write TM/HM move data."
		return result
	if not RomCache.write_json(
		RomCache.happiness_changes_path(directory), happiness_changes
	):
		result["message"] = "Could not write happiness change data."
		return result
	if not RomCache.write_json(RomCache.name_input_chars_path(directory), name_input_chars):
		result["message"] = "Could not write name input data."
		return result
	if not RomCache.write_json(RomCache.text_buffers_path(directory), string_buffers):
		result["message"] = "Could not write string buffer pointers."
		return result
	if not RomCache.write_json(RomCache.intro_text_path(directory), intro_text):
		result["message"] = "Could not write intro text."
		return result
	if not RomCache.write_json(RomCache.dex_orders_path(directory), dex_orders):
		result["message"] = "Could not write dex order data."
		return result
	if not RomCache.write_json(RomCache.items_path(directory), items):
		result["message"] = "Could not write item data."
		return result
	if not RomCache.write_json(RomCache.world_trades_path(directory), trades):
		result["message"] = "Could not write world trade data."
		return result
	if not RomCache.write_json(RomCache.types_path(directory), types):
		result["message"] = "Could not write type data."
		return result
	if not RomCache.write_json(RomCache.matchups_path(directory), matchups):
		result["message"] = "Could not write the type matchup chart."
		return result
	if not RomCache.write_json(RomCache.trainers_path(directory), trainers):
		result["message"] = "Could not write trainer data."
		return result

	var evolutions: int = _count_in(species, "evolutions")
	var learnset_moves: int = _count_in(species, "learnset")
	var egg_moves: int = _count_in(species, "egg_moves")
	var trainer_party_count: int = _count_in(trainers, "trainers")

	var manifest: Dictionary = {
		"format_version": RomCache.FORMAT_VERSION,
		"game_id": String(rom.id),
		"sha1": rom.sha1,
		"species_count": species.size(),
		"evolution_count": evolutions,
		"learnset_move_count": learnset_moves,
		"egg_move_count": egg_moves,
		"move_count": moves.size(),
		"item_count": items.size(),
		"world_trade_count": trades.size(),
		"type_count": types.size(),
		"matchup_count": matchups.size(),
		"trainer_count": trainers.size(),
		"trainer_party_count": trainer_party_count,
		"world_map_count": int(world["maps"]),
		"world_tileset_count": int(world["tilesets"]),
		"world_grass_encounter_count": int(encounters["grass"]),
		"world_water_encounter_count": int(encounters["water"]),
		"world_swarm_grass_encounter_count": int(encounters["swarm_grass"]),
		"world_swarm_water_encounter_count": int(encounters["swarm_water"]),
		"world_fishing_group_count": int(encounters["fish_groups"]),
		"world_roam_map_count": int(encounters["roam_maps"]),
		"world_tree_map_count": int(encounters["tree_maps"]),
		"world_rock_map_count": int(encounters["rock_maps"]),
		"world_treemon_set_count": int(encounters["treemon_sets"]),
		"world_bug_contest_mon_count": int(encounters["bug_contest_mons"]),
		"world_bug_contestant_count": int(encounters["bug_contestants"]),
		"overworld_sprite_count": int(world["overworld_sprites"]),
		"overworld_effect_count": int(world["overworld_effects"]),
		"world_menu_count": int(services["menus"]),
		"world_mart_count": int(services["marts"]),
		"world_phone_contact_count": int(services["phone_contacts"]),
		"world_special_phone_call_count": int(services["special_phone_calls"]),
		"world_phone_script_count": int(services["phone_scripts"]),
		"world_music_count": int(services["music"]),
		"world_sfx_count": int(services["sfx"]),
		"battle_anim_script_count": int(battle_anims["scripts"]),
		"battle_anim_object_count": int(battle_anims["objects"]),
		"battle_anim_frameset_count": int(battle_anims["framesets"]),
		"battle_anim_oam_set_count": int(battle_anims["oam_sets"]),
		"battle_anim_gfx": {
			"sheets": int(battle_anims["gfx_sheets"]),
			"tiles": int(battle_anims["gfx_tiles"]),
		},
		"bar_palettes": _import_bar_palettes(rom, layout),
		"player_palettes": _import_player_palettes(rom, layout),
		"transition_palettes": _import_transition_palettes(rom, layout),
		"battle_grayscale_palette": _import_battle_grayscale_palette(rom, layout),
		"move_screen_palette": _import_move_screen_palette(rom, layout),
		"stats_screen_palettes": _import_stats_screen_palettes(rom, layout),
		"card_palettes": _import_card_palettes(rom, layout),
		"pokedex_palettes": _import_pokedex_palettes(rom, layout),
		"pc_palette": _import_pc_palette(rom, layout),
		"gender_screen_palette": _import_gender_screen_palette(rom, layout),
		"menu_text": _import_menu_text(rom, layout),
		"mart_text": _import_mart_text(rom, layout),
		"name_rater_text": _import_name_rater_text(rom, layout),
		"move_deleter_text": _import_move_deleter_text(rom, layout),
		"day_care_text": _import_day_care_text(rom, layout),
		"copyright_string": _import_copyright_string(rom, layout),
		"copyright_palette": _import_copyright_palette(rom, layout),
		"presents_palettes": _import_presents_palettes(rom, layout),
		"title": _import_title(rom, layout),
		"pack": _import_pack(rom, layout),
		"town_map": _import_town_map(rom, layout),
		"intro_movie": _import_intro_movie(rom, layout),
		"gs_intro": _import_gs_intro(rom, layout),
		"oak_ratings": _import_oak_ratings(rom, layout),
		"pokecenter_pc": _import_pokecenter_pc(rom, layout),
		"unown_puzzle": _import_unown_puzzle(rom, layout),
		"unown_words": Array(read_unown_words(rom, layout)),
		"unown_walls": Array(read_unown_walls(rom, layout)),
		"credits": _import_credits(rom, layout),
		"text_bg_palette": _import_text_bg_palette(rom, layout),
		"battle_object_palettes": _import_battle_object_palettes(rom, layout),
		"atlases": pics,
		## `PokemonPalettes` entry EGG, which `Hatch_LoadFrontpicPal` reaches
		## through `GetBaseData`. It is a species-shaped record with no species
		## behind it, so it is stored beside the atlases rather than in the
		## species table every other palette lives in.
		"egg_pic": {
			"tiles": RomLayout.EGG_PIC_TILES,
			"palette": _read_egg_palette(rom, layout),
		},
		"tiles": tiles,
		"complete": true,
	}
	if not RomCache.write_json(RomCache.manifest_path(directory), manifest):
		result["message"] = "Could not write manifest."
		return result

	## [Gen2WorldCatalog]'s sidecar, written here so a player never pays its
	## scan: it decodes every command of every script this import just wrote,
	## and the first mod-enabled map entry is where it would otherwise land.
	## After the manifest, because the scan opens the cache it describes.
	var catalogued: GameData = GameData.open_directory(directory)
	if catalogued != null:
		RomCache.write_json(
			RomCache.world_catalog_path(directory),
			Gen2WorldCatalog.build(catalogued).to_dict()
		)

	result["ok"] = true
	result["species"] = species.size()
	result["moves"] = moves.size()
	result["items"] = items.size()
	result["types"] = types.size()
	result["matchups"] = matchups.size()
	result["trainers"] = trainers.size()
	result["trainer_party_count"] = trainer_party_count
	result["maps"] = int(world["maps"])
	result["tilesets"] = int(world["tilesets"])
	result["grass_encounters"] = int(encounters["grass"])
	result["water_encounters"] = int(encounters["water"])
	result["swarm_grass_encounters"] = int(encounters["swarm_grass"])
	result["swarm_water_encounters"] = int(encounters["swarm_water"])
	result["fishing_groups"] = int(encounters["fish_groups"])
	result["roam_maps"] = int(encounters["roam_maps"])
	result["tree_maps"] = int(encounters["tree_maps"])
	result["rock_maps"] = int(encounters["rock_maps"])
	result["treemon_sets"] = int(encounters["treemon_sets"])
	result["bug_contest_mons"] = int(encounters["bug_contest_mons"])
	result["bug_contestants"] = int(encounters["bug_contestants"])
	result["overworld_sprites"] = int(world["overworld_sprites"])
	result["menus"] = int(services["menus"])
	result["marts"] = int(services["marts"])
	result["phone_contacts"] = int(services["phone_contacts"])
	result["special_phone_calls"] = int(services["special_phone_calls"])
	result["phone_scripts"] = int(services["phone_scripts"])
	result["music"] = int(services["music"])
	result["sfx"] = int(services["sfx"])
	result["battle_anims"] = int(battle_anims["scripts"])
	result["battle_anim_gfx_tiles"] = int(battle_anims["gfx_tiles"])
	result["evolutions"] = evolutions
	result["learnset_moves"] = learnset_moves
	result["egg_moves"] = egg_moves
	result["elapsed_ms"] = Time.get_ticks_msec() - started
	result["message"] = ("Imported %d species, %d moves, %d items, %d type matchups, "
		+ "%d trainer classes carrying %d trainers, %d maps, %d tilesets, %d grass encounter maps, "
		+ "%d water encounter maps, %d swarm grass maps, %d swarm water maps, "
		+ "%d fishing groups, %d roaming maps, %d headbutt tree maps "
		+ "and %d overworld sprites, "
		+ "%d menus, %d marts, %d phone contacts, %d phone script resources, "
		+ "%d music tracks and %d sound effects, "
		+ "%d battle animations over %d graphics tiles, "
		+ "%d evolutions, %d level-up moves and %d egg moves in %d ms.") % [
		species.size(), moves.size(), items.size(), matchups.size(), trainers.size(),
		trainer_party_count, int(world["maps"]), int(world["tilesets"]),
		int(encounters["grass"]), int(encounters["water"]),
		int(encounters["swarm_grass"]), int(encounters["swarm_water"]),
		int(encounters["fish_groups"]), int(encounters["roam_maps"]),
		int(encounters["tree_maps"]),
		int(world["overworld_sprites"]),
		int(services["menus"]), int(services["marts"]), int(services["phone_contacts"]),
		int(services["phone_scripts"]),
		int(services["music"]), int(services["sfx"]),
		int(battle_anims["scripts"]), int(battle_anims["gfx_tiles"]),
		evolutions, learnset_moves, egg_moves, result["elapsed_ms"],
	]
	return result


## Rows of one list across every species, for the manifest's counts.
static func _count_in(species: Array, key: String) -> int:
	var out: int = 0
	for entry: Dictionary in species:
		out += (entry[key] as Array).size()
	return out


func _import_species(rom: RomFile, layout: Dictionary, on_progress: Callable) -> Array:
	var data: PackedByteArray = rom.bytes()
	var out: Array = []

	for species: int in range(1, RomLayout.SPECIES_COUNT + 1):
		var stats: int = RomLayout.base_stats_offset(layout, species)
		var dimensions: int = rom.u8(stats + RomLayout.OFFSET_PIC_SIZE)
		var egg_groups: int = rom.u8(stats + RomLayout.OFFSET_EGG_GROUPS)
		var palette: int = RomLayout.palette_offset(layout, species)
		var evos_attacks: Dictionary = read_evos_attacks(rom, layout, species)
		var inherited: Dictionary = read_egg_moves(rom, layout, species)
		var dex: Dictionary = read_dex_entry(rom, layout, species)

		out.append({
			"number": species,
			"name": Gen2Text.decode(
				data, RomLayout.species_name_offset(layout, species), RomLayout.NAME_LENGTH
			),
			"stats": {
				"hp": rom.u8(stats + RomLayout.STAT_HP),
				"attack": rom.u8(stats + RomLayout.STAT_ATTACK),
				"defense": rom.u8(stats + RomLayout.STAT_DEFENSE),
				"speed": rom.u8(stats + RomLayout.STAT_SPEED),
				"sp_attack": rom.u8(stats + RomLayout.STAT_SP_ATTACK),
				"sp_defense": rom.u8(stats + RomLayout.STAT_SP_DEFENSE),
			},
			"types": [
				rom.u8(stats + RomLayout.OFFSET_TYPE1),
				rom.u8(stats + RomLayout.OFFSET_TYPE2),
			],
			"catch_rate": rom.u8(stats + RomLayout.OFFSET_CATCH_RATE),
			"base_exp": rom.u8(stats + RomLayout.OFFSET_BASE_EXP),
			"held_items": [
				rom.u8(stats + RomLayout.OFFSET_ITEM1),
				rom.u8(stats + RomLayout.OFFSET_ITEM2),
			],
			"gender_ratio": rom.u8(stats + RomLayout.OFFSET_GENDER_RATIO),
			"hatch_cycles": rom.u8(stats + RomLayout.OFFSET_HATCH_CYCLES),
			"growth_rate": rom.u8(stats + RomLayout.OFFSET_GROWTH_RATE),
			"egg_groups": [egg_groups >> 4, egg_groups & 0x0F],
			"tmhm": Array(rom.slice(stats + RomLayout.OFFSET_TMHM, RomLayout.TMHM_BYTES)),
			# Both halves of one table, which is why they arrive together and are
			# stored on the species rather than in tables of their own.
			"evolutions": evos_attacks.get("evolutions", []),
			"learnset": evos_attacks.get("learnset", []),
			"egg_moves": inherited.get("moves", []),
			"front_tiles": [dimensions & 0x0F, dimensions >> 4],
			# The Pokedex entry. On the species rather than in a table of its
			# own because it is asked for by species number and nothing else,
			# the same reason the learnset lives here.
			"dex": {
				"category": dex.get("category", ""),
				"height": int(dex.get("height", 0)),
				"weight": int(dex.get("weight", 0)),
				"pages": Array(dex.get("pages", PackedStringArray())),
			},
			"palette": {
				"normal": [rom.u16le(palette), rom.u16le(palette + 2)],
				"shiny": [rom.u16le(palette + 4), rom.u16le(palette + 6)],
			},
		})

		if on_progress.is_valid():
			on_progress.call("species", species, RomLayout.SPECIES_COUNT)

	return out


## The two dex orderings, keyed by the mode that reads each. Empty on any layout
## failure, which the caller reports rather than caching a half table.
##
## The third ordering, DEXMODE_OLD, has no table: `.OldMode` counts from 1 to
## 251, so storing it would be storing the species range twice.
func _import_dex_orders(rom: RomFile, layout: Dictionary) -> Dictionary:
	var new_order: PackedInt32Array = read_dex_order(rom, layout, "order_new")
	var alpha_order: PackedInt32Array = read_dex_order(rom, layout, "order_alpha")
	if new_order.size() != RomLayout.SPECIES_COUNT \
		or alpha_order.size() != RomLayout.SPECIES_COUNT:
		return {}
	return {"new": Array(new_order), "alpha": Array(alpha_order)}


func _import_moves(rom: RomFile, layout: Dictionary, on_progress: Callable) -> Array:
	var names: PackedStringArray = Gen2Text.decode_sequence(
		rom.bytes(), int(layout["move_names"]), RomLayout.MOVE_COUNT, RomLayout.MAX_NAME_LENGTH
	)
	var out: Array = []
	## `PrintMoveDescription`'s own line, which the TM/HM pocket prints for the
	## move a TM teaches.
	var descriptions: Array[String] = read_descriptions(
		rom, int(layout.get("move_descriptions", -1)), RomLayout.MOVE_DESCRIPTION_COUNT
	)

	for move: int in range(1, RomLayout.MOVE_COUNT + 1):
		var entry: int = RomLayout.move_data_offset(layout, move)
		# The animation byte is dropped: it is the move's own number, and it is
		# already spent proving the table is where the layout says it is.
		out.append({
			"number": move,
			"name": names[move - 1],
			"description": descriptions[move - 1] if move <= descriptions.size() else "",
			"effect": rom.u8(entry + RomLayout.MOVE_EFFECT),
			"power": rom.u8(entry + RomLayout.MOVE_POWER),
			"type": rom.u8(entry + RomLayout.MOVE_TYPE),
			"accuracy": rom.u8(entry + RomLayout.MOVE_ACCURACY),
			"pp": rom.u8(entry + RomLayout.MOVE_PP),
			"effect_chance": rom.u8(entry + RomLayout.MOVE_EFFECT_CHANCE),
		})

		if on_progress.is_valid():
			on_progress.call("moves", move, RomLayout.MOVE_COUNT)

	return out


## data/moves/tmhm_moves.asm's TMHMMoves, in TMNUM order. Empty on any layout or
## content failure, which the caller reports rather than caching a half table.
##
## Checked rather than trusted: every entry has to be a real move number, the
## terminating zero has to be there, and HM01's row has to be CUT. The last is
## what actually pins the table, since a nearby run of bytes can pass the first
## two.
func _import_tmhm_moves(rom: RomFile, layout: Dictionary) -> Array:
	var at: int = int(layout.get("tmhm_moves", -1))
	var count: int = int(layout.get("tmhm_move_count", 0))
	if count <= RomLayout.TMHM_TM_COUNT or not rom.in_bounds(at, count + 1):
		return []
	if rom.u8(at + count) != 0:
		return []
	var out: Array = []
	for index: int in count:
		var move: int = rom.u8(at + index)
		if move <= 0 or move > RomLayout.MOVE_COUNT:
			return []
		out.append(move)
	if int(out[RomLayout.TMHM_TM_COUNT]) != MOVE_CUT:
		return []
	return out


## data/events/happiness_changes.asm's HappinessChanges, one row of three signed
## changes per HAPPINESS_* constant. Empty on any layout or content failure.
##
## Checked rather than trusted: no change is larger than twenty either way, and
## the first row has to be `+5, +3, +2`, which is what pins the table. Signed
## because `ChangeHappiness` reads the byte as one: its `cp $64` puts everything
## from 100 up on the subtracting branch.
func _import_happiness_changes(rom: RomFile, layout: Dictionary) -> Array:
	var at: int = int(layout.get("happiness_changes", -1))
	var count: int = int(layout.get("happiness_change_count", 0))
	var width: int = RomLayout.HAPPINESS_CHANGE_WIDTH
	if count <= 0 or not rom.in_bounds(at, count * width):
		return []
	var out: Array = []
	for row: int in count:
		var changes: Array = []
		for column: int in width:
			var raw: int = rom.u8(at + row * width + column)
			## `cp $64` is where the routine splits, so a byte from 100 up is
			## the subtracting branch rather than a large rise.
			var change: int = raw - 256 if raw >= 0x64 else raw
			if absi(change) > 20:
				return []
			changes.append(change)
		out.append(changes)
	return out if out[0] == [5, 3, 2] else []


## data/text/name_input_chars.asm's four keyboards, each a list of 17-byte rows
## in source order. Kept as raw cartridge codes rather than decoded text: a row
## carries PK, MN and the two gender signs, which are one byte and one glyph but
## not one character, and the screen writes the byte itself into the name.
func _import_name_input_chars(rom: RomFile, layout: Dictionary) -> Array:
	var out: Array = []
	for table: int in RomLayout.NAME_INPUT_TABLE_ROWS.size():
		var start: int = RomLayout.name_input_table_offset(layout, table)
		var rows: Array = []
		for row: int in RomLayout.NAME_INPUT_TABLE_ROWS[table]:
			var at: int = start + row * RomLayout.NAME_INPUT_ROW_BYTES
			rows.append(Array(rom.slice(at, RomLayout.NAME_INPUT_ROW_BYTES)))
		out.append(rows)
	return out


## StringBufferPointers as WRAM addresses, in `text_buffer` argument order.
##
## Stored rather than derived because the addresses move between Gold/Silver and
## Crystal, and a `TX_RAM` operand is an address: without the table there is no
## way back from `$CFA4` to the buffer a script filled.
func _import_string_buffer_pointers(rom: RomFile, layout: Dictionary) -> Array:
	var out: Array = []
	for index: int in RomLayout.STRING_BUFFER_POINTER_COUNT:
		out.append(rom.u16le(RomLayout.string_buffer_pointer_offset(layout, index)))
	return out


## The intro texts, decoded to strings the way species names are, since each is
## one whole value rather than a run a script indexes into. `<PLAYER>` stays a
## marker: the screen that prints it is the one that knows the name.
##
## A text a profile does not ship is left out rather than stored empty, so a
## caller can tell "Gold has no gender screen" from "the text failed to decode".
func _import_intro_text(rom: RomFile, layout: Dictionary) -> Dictionary:
	var offsets: Dictionary = layout["intro_text"]
	var out: Dictionary = {}
	for key: String in INTRO_TEXT_OPENINGS:
		var at: int = int(offsets.get(key, -1))
		if at < 0:
			continue
		var decoded: Dictionary = Gen2WorldScript.decode_text(
			rom.slice(at, INTRO_TEXT_MAX_BYTES)
		)
		if not bool(decoded.get("ok", false)):
			return {}
		out[key] = String(decoded["text"])
	return out


func _import_items(rom: RomFile, layout: Dictionary, on_progress: Callable) -> Array:
	var names: PackedStringArray = Gen2Text.decode_sequence(
		rom.bytes(), int(layout["item_names"]), RomLayout.ITEM_COUNT, RomLayout.MAX_NAME_LENGTH
	)
	var out: Array = []
	var status_masks: Dictionary = _read_item_status_masks(rom, layout)
	var healing_amounts: Dictionary = _read_item_healing_amounts(rom, layout)
	## `PrintItemDescription`'s own line, which the pack's text box prints under
	## the pocket the row is in.
	var descriptions: Array[String] = read_descriptions(
		rom, int(layout.get("item_descriptions", -1)), RomLayout.ITEM_COUNT
	)

	for item: int in range(1, RomLayout.ITEM_COUNT + 1):
		var at: int = int(layout["item_attributes"]) + (item - 1) * RomLayout.ITEM_ATTRIBUTE_SIZE
		var packed_menu: int = rom.u8(at + RomLayout.ITEM_ATTRIBUTE_HELP)
		var parameter: int = rom.u8(at + RomLayout.ITEM_ATTRIBUTE_PARAM)
		if parameter == 0xFF:
			parameter = -1
		var entry: Dictionary = {
			"number": item,
			"name": names[item - 1],
			"price": rom.u16le(at),
			"effect": rom.u8(at + 2),
			"parameter": parameter,
			"permissions": rom.u8(at + RomLayout.ITEM_ATTRIBUTE_PERMISSIONS),
			"pocket": rom.u8(at + RomLayout.ITEM_ATTRIBUTE_POCKET),
			"field_menu": packed_menu >> 4,
			"battle_menu": packed_menu & 0x0F,
		}
		if item <= descriptions.size():
			entry["description"] = descriptions[item - 1]
		if status_masks.has(item):
			entry["status_mask"] = int(status_masks[item])
		if healing_amounts.has(item):
			entry["heal_amount"] = int(healing_amounts[item])
		out.append(entry)
		if on_progress.is_valid():
			on_progress.call("items", item, RomLayout.ITEM_COUNT)

	return out


## One `table_width 2` description table, as [param count] decoded texts in
## entry order. Every pointer is an address inside the table's own bank, which is
## what `PrintItemDescription` and `PrintMoveDescription` read them as; an entry
## that leaves the bank or runs past [constant RomLayout.DESCRIPTION_MAX_BYTES]
## without a terminator answers an empty Array, since a wrong table decodes as
## words rather than failing.
static func read_descriptions(rom: RomFile, at: int, count: int) -> Array[String]:
	var out: Array[String] = []
	if at < 0 or not rom.in_bounds(at, count * 2):
		return out
	var bank: int = at / RomFile.BANK_SIZE
	var data: PackedByteArray = rom.bytes()
	for index: int in count:
		var address: int = rom.u16le(at + index * 2)
		if address < 0x4000 or address >= 0x8000:
			return [] as Array[String]
		var offset: int = bank * RomFile.BANK_SIZE + (address - 0x4000)
		var end: int = Gen2Text.terminated_end(
			data, offset, RomLayout.DESCRIPTION_MAX_BYTES
		)
		if end <= offset or end - offset >= RomLayout.DESCRIPTION_MAX_BYTES:
			return [] as Array[String]
		out.append(Gen2Text.decode(data, offset, end - offset))
	return out


## Both description tables, checked by decoding every entry of each.
static func verify_descriptions(rom: RomFile, layout: Dictionary) -> Dictionary:
	if read_descriptions(
		rom, int(layout.get("item_descriptions", -1)), RomLayout.ITEM_COUNT
	).size() != RomLayout.ITEM_COUNT:
		return {"ok": false, "message": "The item descriptions do not decode."}
	if read_descriptions(
		rom, int(layout.get("move_descriptions", -1)), RomLayout.MOVE_DESCRIPTION_COUNT
	).size() != RomLayout.MOVE_DESCRIPTION_COUNT:
		return {"ok": false, "message": "The move descriptions do not decode."}
	return {"ok": true, "message": "Descriptions verified."}


static func verify_item_metadata(rom: RomFile, layout: Dictionary) -> Dictionary:
	var attributes: int = int(layout.get("item_attributes", -1))
	if not rom.in_bounds(attributes, RomLayout.ITEM_COUNT * RomLayout.ITEM_ATTRIBUTE_SIZE):
		return {"ok": false, "message": "Item attribute table is outside the ROM."}
	if rom.u8(attributes + RomLayout.ITEM_ATTRIBUTE_POCKET) != RomLayout.ITEM_POCKET_BALL:
		return {"ok": false, "message": "Master Ball is not in the cartridge ball pocket."}
	var poke_ball: int = attributes + 4 * RomLayout.ITEM_ATTRIBUTE_SIZE
	if rom.u8(poke_ball + RomLayout.ITEM_ATTRIBUTE_POCKET) != RomLayout.ITEM_POCKET_BALL:
		return {"ok": false, "message": "Poke Ball is not in the cartridge ball pocket."}
	var status_at: int = int(layout.get("item_status_actions", -1))
	var status_found: bool = false
	for index: int in 32:
		if rom.u8(status_at + index * 3) == 0xFF:
			status_found = true
			break
	if not status_found:
		return {"ok": false, "message": "Status-healing item table has no terminator."}
	var healing_at: int = int(layout.get("item_healing_hp", -1))
	var healing_found: bool = false
	for index: int in 32:
		if rom.u8(healing_at + index * 3) == 0xFF:
			healing_found = true
			break
	if not healing_found:
		return {"ok": false, "message": "HP-healing item table has no terminator."}
	return {"ok": true, "message": ""}


static func verify_world_trades(rom: RomFile, layout: Dictionary) -> Dictionary:
	var count: int = int(layout.get("world_trade_count", 0))
	var at: int = int(layout.get("world_trades", -1))
	if count <= 0 or not rom.in_bounds(at, count * RomLayout.TRADE_RECORD_SIZE):
		return {"ok": false, "message": "NPC trade table is outside the ROM."}
	for index: int in count:
		var row: int = at + index * RomLayout.TRADE_RECORD_SIZE
		if rom.u8(row + 1) <= 0 or rom.u8(row + 1) > RomLayout.SPECIES_COUNT \
			or rom.u8(row + 2) <= 0 or rom.u8(row + 2) > RomLayout.SPECIES_COUNT:
			return {"ok": false, "message": "NPC trade %d has an invalid species." % index}
		if rom.u8(row + 30) > RomLayout.TRADE_GENDER_FEMALE or rom.u8(row + 31) != 0:
			return {"ok": false, "message": "NPC trade %d has an invalid record tail." % index}
	return {"ok": true, "message": ""}


static func _read_item_status_masks(rom: RomFile, layout: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var at: int = int(layout["item_status_actions"])
	for index: int in 32:
		var item: int = rom.u8(at)
		if item == 0xFF:
			break
		if item <= 0 or item > RomLayout.ITEM_COUNT:
			break
		out[item] = rom.u8(at + 2)
		at += 3
	return out


static func _read_item_healing_amounts(rom: RomFile, layout: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var at: int = int(layout["item_healing_hp"])
	for index: int in 32:
		var item: int = rom.u8(at)
		if item == 0xFF:
			break
		if item <= 0 or item > RomLayout.ITEM_COUNT:
			break
		out[item] = rom.u16le(at + 1)
		at += 3
	return out


static func _import_world_trades(rom: RomFile, layout: Dictionary) -> Array:
	var out: Array = []
	var count: int = int(layout["world_trade_count"])
	var at: int = int(layout["world_trades"])
	for index: int in count:
		var row: int = at + index * RomLayout.TRADE_RECORD_SIZE
		out.append({
			"trade_id": index,
			"dialog": rom.u8(row),
			"requested_species": rom.u8(row + 1),
			"offered_species": rom.u8(row + 2),
			"nickname": Gen2Text.decode_fixed(
				rom.bytes(), row + 3, RomLayout.TRADE_NAME_LENGTH
			),
			"dvs": (rom.u8(row + 14) << 8) | rom.u8(row + 15),
			"item": rom.u8(row + 16),
			"ot_id": rom.u16le(row + 17),
			"ot_name": Gen2Text.decode_fixed(
				rom.bytes(), row + 19, RomLayout.TRADE_NAME_LENGTH
			),
			"gender": rom.u8(row + 30),
		})
	return out


func _import_types(rom: RomFile, layout: Dictionary, on_progress: Callable) -> Array:
	var out: Array = []

	for type_number: int in RomLayout.TYPE_COUNT:
		out.append({"number": type_number, "name": type_name(rom, layout, type_number)})
		if on_progress.is_valid():
			on_progress.call("types", type_number + 1, RomLayout.TYPE_COUNT)

	return out


## Decodes the trainer classes: a name and the two colours the class is drawn in.
##
## A class has one palette and no shiny counterpart, so the pair is stored flat,
## and the pic is found by class number in the trainer atlas.
##
## Behind the classes sit the party table (who carries what), the attributes
## table (how the class's AI plays it) and the DVs table. All four stay on one
## entry rather than in separate cache files, because they are four tables one
## class number addresses, not four separate questions.
func _import_trainers(rom: RomFile, layout: Dictionary, on_progress: Callable) -> Array:
	var count: int = RomLayout.trainer_class_count(layout)
	var names: PackedStringArray = Gen2Text.decode_sequence(
		rom.bytes(), int(layout["trainer_class_names"]), count, RomLayout.MAX_NAME_LENGTH
	)
	var parties: Dictionary = RomImporter.read_trainer_parties(rom, layout)
	var classes: Array = parties["classes"] if parties["ok"] else []
	var out: Array = []

	for trainer_class: int in range(1, count + 1):
		var palette: int = RomLayout.trainer_palette_offset(layout, trainer_class)
		out.append({
			"number": trainer_class,
			"name": names[trainer_class - 1],
			"palette": [rom.u16le(palette), rom.u16le(palette + Gen2Palette.COLOR_BYTES)],
			"trainers": classes[trainer_class - 1] if trainer_class - 1 < classes.size() else [],
			"attributes": RomImporter.read_trainer_attributes(rom, layout, trainer_class),
			"dvs": RomImporter.read_trainer_dvs(rom, layout, trainer_class),
		})

		if on_progress.is_valid():
			on_progress.call("trainers", trainer_class, count)

	return out


## The four colours a battle draws its bars in. Small enough to live in the
## manifest beside the atlas metadata rather than in a file of its own.
## `GetPlayerOrMonPalettePointer`'s two: the colours the player's own back pic is
## drawn in while it is standing on the field, before a Pokemon is sent out.
##
## They are the first two rows of `TrainerPalettes`, which the cartridge shares
## with two trainer classes on purpose ("Chris uses the same colors as Cal",
## "Kris shares Falkner's palette"), so they are read at the table rather than
## through a class number.
func _import_player_palettes(rom: RomFile, layout: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for index: int in RomLayout.PLAYER_PALETTE_NAMES.size():
		var entry: int = RomLayout.trainer_palette_offset(layout, index)
		out[RomLayout.PLAYER_PALETTE_NAMES[index]] = [
			rom.u16le(entry), rom.u16le(entry + Gen2Palette.COLOR_BYTES),
		]
	return out


## `StartTrainerBattle_LoadPokeBallGraphics.pals` and its `.darkpals`, four
## colours each: the whole background is put on `PAL_BG_TEXT` and filled with
## one of them, which is why a trainer transition turns the map red.
func _import_transition_palettes(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout.get("battle_transition", {}) as Dictionary
	var out: Dictionary = {}
	for index: int in RomLayout.TRANSITION_PALETTE_NAMES.size():
		var at: int = int(entry.get("palette" if index == 0 else "dark_palette", -1))
		if at < 0:
			continue
		var colors: Array = []
		for color: int in RomLayout.TRANSITION_PALETTE_COLORS:
			colors.append(rom.u16le(at + color * Gen2Palette.COLOR_BYTES))
		out[RomLayout.TRANSITION_PALETTE_NAMES[index]] = colors
	return out


func _import_bar_palettes(rom: RomFile, layout: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for index: int in RomLayout.BAR_PALETTE_NAMES.size():
		var entry: int = RomLayout.bar_palette_offset(layout, index)
		out[RomLayout.BAR_PALETTE_NAMES[index]] = [
			rom.u16le(entry), rom.u16le(entry + Gen2Palette.COLOR_BYTES),
		]
	return out


## `_CGB_BattleGrayscale`'s own palette, which is `PredefPals`' `BLACKOUT` entry
## and is what every background and object palette holds from the moment a battle
## is entered until `GetSGBLayout SCGB_BATTLE_COLORS` runs, several hundred
## frames later on the far side of `BattleIntroSlidingPics`.
func _import_battle_grayscale_palette(rom: RomFile, layout: Dictionary) -> Array:
	return _import_predef_palette(rom, layout, RomLayout.PREDEFPAL_BLACKOUT)


## `_CGB_MoveList`'s background palette, `PREDEFPAL_GOLDENROD`, which is the one
## colour on the move screen that is not a bar or a mon icon.
func _import_move_screen_palette(rom: RomFile, layout: Dictionary) -> Array:
	return _import_predef_palette(rom, layout, RomLayout.PREDEFPAL_GOLDENROD)


## One whole `PredefPals` entry. Empty for a layout with no pin, which is what a
## caller that draws white and black falls back on.
func _import_predef_palette(rom: RomFile, layout: Dictionary, index: int) -> Array:
	var at: int = RomLayout.predef_palette_offset(layout, index)
	if at < 0 or not rom.in_bounds(at, RomLayout.PREDEF_PALETTE_SIZE):
		return []
	var out: Array = []
	for colour: int in RomLayout.PREDEF_PALETTE_COLORS:
		out.append(rom.u16le(at + colour * Gen2Palette.COLOR_BYTES))
	return out


## `StatsScreenPagePals` and `StatsScreenPals`: the three page indicators' whole
## palettes, and the three colours `LoadStatsScreenPals` tints the open page's
## background with.
func _import_stats_screen_palettes(rom: RomFile, layout: Dictionary) -> Dictionary:
	var pages: Array = []
	var tints: Array = []
	for index: int in RomLayout.STATS_PAGE_PALETTES:
		var page: int = RomLayout.stats_page_palette_offset(layout, index)
		var tint: int = RomLayout.stats_page_tint_offset(layout, index)
		if page < 0 or not rom.in_bounds(tint, Gen2Palette.COLOR_BYTES):
			return {}
		var colors: Array = []
		for colour: int in RomLayout.STATS_PAGE_PALETTE_COLORS:
			colors.append(rom.u16le(page + colour * Gen2Palette.COLOR_BYTES))
		pages.append(colors)
		tints.append(rom.u16le(tint))
	return {"pages": pages, "tints": tints}


## The six `BattleObjectPals` an animation object is drawn with, four colours
## each rather than a pair, since `_CGB_BattleScreenLayout` copies them in whole.
##
## Slots 0 and 1 are not here and are not table rows: the layout fills them from
## the two battlers' own palettes, so an object asking for either is asking for
## whoever is on the field.
func _import_battle_object_palettes(rom: RomFile, layout: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var entry: int = int(layout["battle_object_palettes"])
	for index: int in RomLayout.BATTLE_OBJECT_PALETTES_STORED:
		var colors: Array = []
		for color: int in RomLayout.BATTLE_OBJECT_PALETTE_COLORS:
			colors.append(rom.u16le(
				entry
					+ (index * RomLayout.BATTLE_OBJECT_PALETTE_COLORS + color)
					* Gen2Palette.COLOR_BYTES
			))
		out[RomLayout.BATTLE_OBJECT_PALETTE_NAMES[index]] = colors
	return out


## `_CGB_TrainerCard`'s palettes: its eight background slots, each a trainer
## class pair `LoadPalette_White_Col1_Col2_Black` expands, and the badge object
## palette it takes from `PredefPals` whole.
##
## Slot 0 is trainer class 0, the player, whose pair sits in the class table but
## whose class the pic tables skip, so this is the only place it is read.
func _import_card_palettes(rom: RomFile, layout: Dictionary) -> Dictionary:
	var background: Array = []
	for trainer_class: int in RomLayout.CARD_PALETTE_CLASSES:
		var entry: int = RomLayout.trainer_palette_offset(layout, trainer_class)
		background.append([
			rom.u16le(entry), rom.u16le(entry + Gen2Palette.COLOR_BYTES),
		])
	var badge: Array = []
	var badge_entry: int = int((layout["trainer_card"] as Dictionary)["badge_palette"])
	for index: int in RomLayout.CARD_BADGE_PALETTE_COLORS:
		badge.append(rom.u16le(badge_entry + index * Gen2Palette.COLOR_BYTES))
	return {"background": background, "badge": badge}


## `_CGB_Pokedex`'s three palettes.
##
## `interface` is PREDEFPAL_POKEDEX, the four colours the whole screen is drawn
## through; `question_mark` is what an unseen species' Slowpoke picture wears,
## which `_CGB_Pokedex` fills the 7x7 pic box with; `cursor` is object palette 7,
## the arrow's own. All three are four colours stored whole rather than as a
## pair, the way `card_badge_palette` is.
func _import_pokedex_palettes(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout.get("pokedex", {})
	var out: Dictionary = {}
	for name: String in ["interface", "question_mark", "cursor"]:
		var at: int = int(entry.get("%s_palette" % name, -1))
		if at < 0:
			continue
		var colors: Array = []
		for index: int in Gen2Palette.COLORS_PER_PIC:
			colors.append(rom.u16le(at + index * Gen2Palette.COLOR_BYTES))
		out[name] = colors
	return out


## `BillsPCOrangePalette`, the four colours `_CGB_BillsPC` puts on the mon-pic
## box while `wCurPartySpecies` is $ff, which is every row holding no Pokemon.
func _import_pc_palette(rom: RomFile, layout: Dictionary) -> Array:
	var entry: Dictionary = layout.get("pc", {})
	if entry.is_empty():
		return []
	var at: int = int(entry["orange_palette"])
	var out: Array = []
	for index: int in RomLayout.PC_PALETTE_COLORS:
		out.append(rom.u16le(at + index * Gen2Palette.COLOR_BYTES))
	return out


## `Palette_TextBG7`, the four colours a text box is drawn through. Only index 0
## and index 3 are ever a pixel, since the font is 1bpp; the two between them are
## what a palette fade over a box passes through. Empty on Gold and Silver.
func _import_text_bg_palette(rom: RomFile, layout: Dictionary) -> Array:
	var entry: int = int((layout["text_bg_palette"] as Dictionary)["offset"])
	if entry < 0:
		return []
	var out: Array = []
	for index: int in RomLayout.TEXT_BG_PALETTE_COLORS:
		out.append(rom.u16le(entry + index * Gen2Palette.COLOR_BYTES))
	return out


## `LoadGenderScreenPal`'s four colours, stored whole rather than as a pair: the
## screen is a background fill with a text box over it, not a pic drawn through
## `LoadPalette_White_Col1_Col2_Black`. Empty on a profile with no gender screen.
func _import_gender_screen_palette(rom: RomFile, layout: Dictionary) -> Array:
	var entry: int = int((layout["gender_screen"] as Dictionary)["palette"])
	if entry < 0:
		return []
	var out: Array = []
	for index: int in RomLayout.GENDER_SCREEN_PALETTE_COLORS:
		out.append(rom.u16le(entry + index * Gen2Palette.COLOR_BYTES))
	return out


## The start menu's nine descriptions, keyed by the menu item each belongs to,
## and the pack's five texts. A text's unfilled slots stay as
## [Gen2TextStream]'s own markers: the quantity and the item name are only known
## while the box is up.
func _import_menu_text(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout.get("menu_text", {})
	if entry.is_empty():
		return {}
	var out: Dictionary = {}
	var descriptions: Dictionary = {}
	var read: Array[String] = read_menu_descriptions(rom, layout)
	for index: int in read.size():
		descriptions[String(RomLayout.MENU_DESCRIPTION_ORDER[index])] = read[index]
	out["descriptions"] = descriptions
	for key: String in PACK_TEXT_OPENINGS:
		var at: int = int(entry.get(key, -1))
		if at < 0:
			continue
		var decoded: Dictionary = Gen2WorldScript.decode_text(
			rom.slice(at, RomLayout.PACK_TEXT_MAX_BYTES)
		)
		if not bool(decoded.get("ok", false)):
			return {}
		out[key] = String(decoded["text"])
	return out


## The mart's own boxes, by the name `RomLayout.MART_TEXT_AT` gives each stub.
func _import_mart_text(rom: RomFile, layout: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for name: String in RomLayout.MART_TEXT_AT:
		out[name] = read_oak_text(rom, layout, RomLayout.mart_text_offset(layout, name))
	return out


## The Name Rater's own boxes, by the name `RomLayout.NAME_RATER_TEXT_ORDER`
## gives each stub.
func _import_name_rater_text(rom: RomFile, layout: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for name: String in RomLayout.NAME_RATER_TEXT_ORDER:
		out[name] = read_oak_text(
			rom, layout, RomLayout.name_rater_text_offset(layout, name)
		)
	return out


## The Day-Care's own boxes, by the name
## `RomImporter.day_care_text_names` gives each stub.
func _import_day_care_text(rom: RomFile, layout: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for name: String in day_care_text_names():
		out[name] = read_oak_text(
			rom, layout, RomLayout.day_care_text_offset(layout, name)
		)
	return out


## The move deleter's own boxes, by the name
## `RomLayout.MOVE_DELETER_TEXT_ORDER` gives each stub.
func _import_move_deleter_text(rom: RomFile, layout: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for name: String in RomLayout.MOVE_DELETER_TEXT_ORDER:
		out[name] = read_oak_text(
			rom, layout, RomLayout.move_deleter_text_offset(layout, name)
		)
	return out


## The splash's object palettes: PREDEFPAL_GAMEFREAK_LOGO_OB on every profile,
## and on Crystal `gfx/splash/ditto.pal` with the sixteen-step fade
## `GameFreakLogo_Transform` walks through its third colour.
func _import_presents_palettes(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout.get("game_freak_presents", {})
	if entry.is_empty():
		return {}
	var out: Dictionary = {
		"object": _packed_palette(
			rom, int(entry.get("object_palette", -1)),
			RomLayout.PRESENTS_OBJECT_PALETTE_COLORS
		),
	}
	var ditto: Array = _packed_palette(
		rom, int(entry.get("ditto_palette", -1)), RomLayout.PRESENTS_DITTO_PALETTE_COLORS
	)
	if not ditto.is_empty():
		out["ditto"] = ditto
		out["ditto_fade"] = _packed_palette(
			rom, int(entry.get("ditto_fade", -1)), RomLayout.PRESENTS_DITTO_FADE_COLORS
		)
	return out


## The credits: `CreditsScript`, every `CreditsStringsPointers` entry as the tile
## codes it is, `CreditsPalettes` and `.Frames`' block indices.
##
## The strings stay codes rather than text for the same reason the copyright
## screen's does: `CreditsStringsPointers.Copyright` is nothing but tile numbers
## into `CopyrightGFX`, which `Credits` loads over $60 the way `Copyright` does.
func _import_credits(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout.get("credits", {})
	if entry.is_empty():
		return {}
	var script: Array = []
	for command: int in read_credits_script(rom, layout):
		script.append(command)
	var strings: Array = []
	for index: int in int(entry["string_count"]):
		var codes: Array = []
		for code: int in read_credits_string(rom, layout, index):
			codes.append(code)
		strings.append(codes)
	var scene_colors: int = int(entry["scene_palettes"]) * RomLayout.CREDITS_PALETTE_COLORS
	return {
		"script": script,
		"strings": strings,
		"staff": int(entry["staff"]),
		"copyright": int(entry["copyright"]),
		"scene_palettes": int(entry["scene_palettes"]),
		"palettes": _packed_palette(
			rom, int(entry["palettes"]), RomLayout.CREDITS_SCENES * scene_colors
		),
		"frames": RomLayout.credits_frames(layout).duplicate(),
	}


func _packed_palette(rom: RomFile, at: int, colors: int) -> Array:
	if at < 0:
		return []
	var out: Array = []
	for index: int in colors:
		out.append(rom.u16le(at + index * Gen2Palette.COLOR_BYTES))
	return out


## The pack screen's data half: `DrawPocketName`'s 5x12 tilemap and the palettes
## `_CGB_PackPals` fills the attrmap with. The graphics go through the tile table
## with the rest of the strips.
##
## Both palette sets are six palettes, not the eight the copy asks for; the two
## past them are read out of whatever follows and no attribute names them.
func _import_pack(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout.get("pack", {})
	if entry.is_empty():
		return {}
	var names: Array = []
	for cell: int in RomLayout.PACK_NAME_CELLS:
		names.append(rom.u8(int(entry["pocket_names"]) + cell))
	var colors: int = RomLayout.PACK_PALETTES * RomLayout.PACK_PALETTE_COLORS
	return {
		"pocket_names": names,
		"palettes": _packed_palette(rom, int(entry["palettes"]), colors),
		"female_palettes": _packed_palette(
			rom, int(entry.get("female_palettes", -1)), colors
		),
	}


## `CopyrightString`, as the tile codes it is. Kept as codes rather than as text
## because none of them is a character: `Copyright` loads its own graphic over
## tiles $60 and up, and the string addresses those tiles directly.
func _import_copyright_string(rom: RomFile, layout: Dictionary) -> Array:
	var out: Array = []
	for code: int in read_copyright_string(rom, layout):
		out.append(code)
	return out


## PREDEFPAL_GAMEFREAK_LOGO_BG, whole: the copyright screen is one 2bpp graphic
## on a blank map, so all four of its colours are drawn.
func _import_copyright_palette(rom: RomFile, layout: Dictionary) -> Array:
	var at: int = int((layout.get("copyright", {}) as Dictionary).get("palette", -1))
	if at < 0:
		return []
	var out: Array = []
	for index: int in RomLayout.COPYRIGHT_PALETTE_COLORS:
		out.append(rom.u16le(at + index * Gen2Palette.COLOR_BYTES))
	return out


## The intro movie's tile strips and its four BG maps with their attribute
## planes, all out of one walk of the section.
##
## A map is a byte run keyed by a name, so it is written the way a strip is and
## read back with `GameData.intro_map()`; it is not a sheet and gets no entry in
## the manifest's tile table. `Intro_LoadTilemap` copies the top-left 20x18 of
## one into `wTilemap`, which is why the whole 32x32 is kept rather than a
## screen.
func _import_intro_sheets(rom: RomFile, layout: Dictionary) -> Dictionary:
	var section: Dictionary = read_intro_section(rom, layout)
	if section.is_empty():
		return {}
	var directory: String = RomCache.directory_for(rom.id, rom.sha1)
	var out: Dictionary = {}
	for row: Array in RomLayout.INTRO_SECTION:
		var name: String = String(row[0])
		var kind: String = String(row[1])
		var raw: PackedByteArray = section[name]
		var path: String = RomCache.tile_path(directory, "intro_%s" % name)
		match kind:
			"pal":
				continue
			"map", "attr":
				if not RomCache.write_indices(path, raw):
					return {}
			_:
				var tiles: int = int(row[2])
				if not RomCache.write_indices(
					path, Gen2Tiles.decode_2bpp_strip(raw, 0, tiles)
				):
					return {}
				out["intro_%s" % name] = _strip_sheet_entry(tiles)
	return out


## The intro movie's palettes: the five sixteen-palette runs inside the section,
## `Intro_Scene24_ApplyPaletteFade`'s eight and `Intro_Scene20_AppearUnown`'s
## two, plus the names of the maps written beside the sheets.
##
## The fades `CrystalIntro_UnownFade` and `Intro_FadeUnownWordPals` run through
## are `for hue, 32` tables the assembler generates, not cartridge data, so they
## are computed in [Gen2IntroMovie] rather than imported.
func _import_intro_movie(rom: RomFile, layout: Dictionary) -> Dictionary:
	var section: Dictionary = read_intro_section(rom, layout)
	if section.is_empty():
		return {}
	var entry: Dictionary = layout["intro_movie"]
	var palettes: Dictionary = {}
	var maps: Array = []
	for row: Array in RomLayout.INTRO_SECTION:
		var name: String = String(row[0])
		match String(row[1]):
			"pal":
				palettes[name] = _unpacked_words(section[name])
			"map", "attr":
				maps.append(name)
	palettes["fade"] = _packed_palette(
		rom, int(entry["fade"]),
		RomLayout.INTRO_FADE_PALETTES * RomLayout.INTRO_PALETTE_COLORS
	)
	palettes["unown"] = _packed_palette(
		rom, int(entry["unown_pals"]),
		RomLayout.INTRO_UNOWN_PALETTES * RomLayout.INTRO_PALETTE_COLORS
	)
	return {"palettes": palettes, "maps": maps}


## `GoldSilverIntro`'s seven tile strips. The two `.tilemap`s and two `.bin`s are
## metatile data rather than pixels, so they go beside the movie's own entry
## through [method _import_gs_intro] rather than into the tile table.
func _import_gs_intro_sheets(rom: RomFile, layout: Dictionary) -> Dictionary:
	var section: Dictionary = read_gs_intro_section(rom, layout)
	if section.is_empty():
		return {}
	var directory: String = RomCache.directory_for(rom.id, rom.sha1)
	var out: Dictionary = {}
	for row: Array in RomLayout.GS_INTRO_SECTION:
		if String(row[1]) == "raw_bytes":
			continue
		var name: String = String(row[0])
		var tiles: int = int(row[2])
		if not RomCache.write_indices(
			RomCache.tile_path(directory, "gs_intro_%s" % name),
			Gen2Tiles.decode_2bpp_strip(section[name], 0, tiles)
		):
			return {}
		out["gs_intro_%s" % name] = _strip_sheet_entry(tiles)
	return out


## `GoldSilverIntro`'s metatile maps and its palettes.
##
## The four `.tilemap`/`.bin` runs are byte runs keyed by a name, written the way
## the Crystal movie's BG maps are and read back with `GameData.gs_intro_map()`.
## The palettes are `Intro_LoadMagikarpPalettes`' pair, the shellder and lapras
## run, and the three `PredefPals` entries the scenes load through
## `GetPredefPal`; the DMG register orders every scene fades through are code
## rather than data and live in [Gen2GoldSilverIntro].
func _import_gs_intro(rom: RomFile, layout: Dictionary) -> Dictionary:
	var section: Dictionary = read_gs_intro_section(rom, layout)
	if section.is_empty():
		return {}
	var entry: Dictionary = layout["gs_intro"]
	var directory: String = RomCache.directory_for(rom.id, rom.sha1)
	var maps: Array = []
	for row: Array in RomLayout.GS_INTRO_SECTION:
		if String(row[1]) != "raw_bytes":
			continue
		var name: String = String(row[0])
		if not RomCache.write_indices(
			RomCache.tile_path(directory, "gs_intro_%s" % name), section[name]
		):
			return {}
		maps.append(name)
	var colors: int = RomLayout.INTRO_PALETTE_COLORS
	var palettes: Dictionary = {
		"magikarp": _packed_palette(
			rom, int(entry["magikarp_palettes"]),
			RomLayout.GS_INTRO_MAGIKARP_PALETTES * colors
		),
		"shellder_lapras": _packed_palette(
			rom, int(entry["shellder_lapras_palettes"]),
			RomLayout.GS_INTRO_SHELLDER_LAPRAS_PALETTES * colors
		),
	}
	var predef: int = int(entry["predef_pals"])
	for name: String in RomLayout.GS_INTRO_PREDEF:
		palettes[name] = _packed_palette(
			rom,
			predef + int(RomLayout.GS_INTRO_PREDEF[name]) * RomLayout.GS_INTRO_PREDEF_SIZE,
			colors
		)
	return {"palettes": palettes, "maps": maps}


static func _unpacked_words(raw: PackedByteArray) -> Array:
	var out: Array = []
	for index: int in raw.size() / Gen2Palette.COLOR_BYTES:
		var at: int = index * Gen2Palette.COLOR_BYTES
		out.append(raw[at] | (raw[at + 1] << 8))
	return out


## `ShrinkPlayer`'s two pictures, which are LZ runs rather than tile strips and
## are laid out by `PlaceGraphic` the way every 7x7 pic is: as one 56x56 buffer
## per picture, so a screen draws them the way it draws the player's own.
func _import_shrink_pics(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout["shrink_pics"]
	var offsets: Array = [int(entry["first"]), int(entry["second"])]
	var side: int = RomLayout.SHRINK_PIC_COLUMNS * Gen2Tiles.TILE_WIDTH
	var directory: String = RomCache.directory_for(rom.id, rom.sha1)
	var out: Dictionary = {}
	for index: int in offsets.size():
		var raw: PackedByteArray = _lz.decompress(rom.bytes(), int(offsets[index]))
		if _lz.failed or raw.size() < RomLayout.SHRINK_PIC_TILES * Gen2Tiles.TILE_BYTES:
			return {}
		var name: String = RomLayout.SHRINK_PIC_NAMES[index]
		var pixels: PackedByteArray = Gen2Tiles.decode_pic(
			raw, RomLayout.SHRINK_PIC_COLUMNS, RomLayout.SHRINK_PIC_ROWS
		)
		if not RomCache.write_indices(RomCache.tile_path(directory, name), pixels):
			return {}
		out[name] = {
			"width": side,
			"height": side,
			"tiles": RomLayout.SHRINK_PIC_TILES,
			"first_code": 0,
			"bits": 2,
		}
	return out


## The title screen's palettes and, on Gold and Silver, its tilemap. The
## graphics themselves go through [method _import_title_sheets] with the rest of
## the tile strips.
##
## Crystal's sixteen palettes are one run `_TitleScreen` copies whole into both
## buffers; Gold and Silver's are five background and two object palettes that
## `GetSGBLayout` and `LoadTitleScreenPals` load separately, so they are kept
## apart under the names the source gives them.
func _import_title(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout.get("title", {})
	if entry.is_empty():
		return {}
	if int(entry.get("palettes", -1)) >= 0:
		return {
			"palettes": _packed_palette(
				rom, int(entry["palettes"]),
				RomLayout.TITLE_PALETTES * RomLayout.TITLE_PALETTE_COLORS
			),
		}
	return {
		"bg_palettes": _packed_palette(
			rom, int(entry["bg_palette"]),
			RomLayout.TITLE_BG_PALETTES * RomLayout.TITLE_PALETTE_COLORS
		),
		"ob_palettes": _packed_palette(
			rom, int(entry["ob_palette"]),
			RomLayout.TITLE_OB_PALETTES * RomLayout.TITLE_PALETTE_COLORS
		),
		"tilemap": Array(read_title_tilemap(rom, layout)),
	}


## The region map's data half: both region tilemaps, `TownMapPals`' palette map,
## the landmark table, the palettes the six tile classes are drawn through, and
## the other three Pokegear cards, which share the whole of that VRAM window.
##
## A landmark's name is kept as the codes it is rather than as text, because
## `TownMap_ConvertLineBreakCharacters` rewrites one of those codes before the
## name is placed and a decoded string cannot say which byte it was: `<BSP>` is a
## space everywhere else and a ligature ahead of it moves the character index off
## the tile index.
func _import_town_map(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout.get("town_map", {})
	if entry.is_empty():
		return {}
	var out: Dictionary = {
		"johto": Array(read_town_map_region(rom, layout, "johto")),
		"kanto": Array(read_town_map_region(rom, layout, "kanto")),
		"palette_map": Array(
			rom.slice(int(entry["palette_map"]), RomLayout.TOWN_MAP_PALETTE_MAP_BYTES)
		),
		"palettes": _packed_palette(
			rom, int(entry["palette"]),
			RomLayout.TOWN_MAP_PALETTES * RomLayout.TOWN_MAP_PALETTE_COLORS
		),
		"landmarks": _import_landmarks(rom, layout),
	}
	if int(entry.get("palette_female", -1)) >= 0:
		out["palettes_female"] = _packed_palette(
			rom, int(entry["palette_female"]),
			RomLayout.TOWN_MAP_PALETTES * RomLayout.TOWN_MAP_PALETTE_COLORS
		)
	var decoded: Dictionary = read_pokegear_cards(rom, layout)
	var cards: Dictionary = {}
	for name: String in decoded:
		cards[name] = Array(decoded[name] as PackedByteArray)
	out["cards"] = cards
	out["card_texts"] = read_pokegear_texts(rom, layout)
	return out


func _import_landmarks(rom: RomFile, layout: Dictionary) -> Array:
	var out: Array = []
	for index: int in RomLayout.landmark_count(layout):
		var record: int = RomLayout.landmark_offset(layout, index)
		var at: int = RomLayout.landmark_name_offset(rom, layout, index)
		var codes: Array = []
		for step: int in RomLayout.LANDMARK_NAME_BYTES:
			var code: int = rom.u8(at + step)
			if code == Gen2Text.TERMINATOR:
				break
			codes.append(code)
		out.append({
			# The stored bytes carry the hardware's own OAM offsets; the screen
			# positions are what a caller wants.
			"x": rom.u8(record) - RomLayout.LANDMARK_OAM_X,
			"y": rom.u8(record + 1) - RomLayout.LANDMARK_OAM_Y,
			"codes": codes,
		})
	return out


## Prof Oak's PC: the four texts around the rating and the nineteen rows
## `FindOakRating` bands the caught count through, each with the sfx it plays.
func _import_oak_ratings(rom: RomFile, layout: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for name: String in RomLayout.OAK_TEXT_STUBS:
		out[name] = read_oak_text(
			rom, layout, RomLayout.oak_text_stub_offset(rom, layout, name)
		)
	var rows: Array = []
	for index: int in RomLayout.OAK_RATING_COUNT:
		var row: int = RomLayout.oak_rating_offset(layout, index)
		rows.append({
			"threshold": rom.u8(row),
			# `rating` stores the sfx as a word, though every id is a byte.
			"sfx": rom.u16le(row + 1),
			"text": read_oak_text(
				rom, layout, RomFile.linear(RomLayout.bank_of(row), rom.u16le(row + 3))
			),
		})
	out["ratings"] = rows
	return out


## `PokemonCenterPC`'s rows and the routine's own six texts, both keyed by the
## names `RomLayout` gives them so nothing downstream counts positions.
func _import_pokecenter_pc(rom: RomFile, layout: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for players: bool in [false, true]:
		var names: Array[String] = RomLayout.POKECENTER_PC_PLAYERS_ROWS if players \
			else RomLayout.POKECENTER_PC_ROWS
		var rows: PackedStringArray = read_pokecenter_pc_rows(rom, layout, players)
		var stored: Dictionary = {}
		for index: int in mini(rows.size(), names.size()):
			stored[String(names[index])] = rows[index]
		out["players_rows" if players else "rows"] = stored
		out["players_lists" if players else "lists"] = read_pokecenter_pc_lists(
			rom, layout, players
		)
	var texts: Dictionary = {}
	for name: String in RomLayout.POKECENTER_PC_TEXT_AT:
		texts[name] = read_oak_text(
			rom, layout, RomLayout.pokecenter_pc_text_offset(layout, name)
		)
	out["texts"] = texts
	return out


## `Pokegear_LoadGFX`'s three LZ runs, each as one strip of tiles.
func _import_town_map_sheets(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout.get("town_map", {})
	if entry.is_empty():
		return {}
	var directory: String = RomCache.directory_for(rom.id, rom.sha1)
	var out: Dictionary = {}
	for run: Array in [
		["town_map", int(entry["gfx"]), RomLayout.TOWN_MAP_TILES],
		["pokegear", int(entry["pokegear_gfx"]), RomLayout.POKEGEAR_TILES],
		["pokegear_sprites", int(entry["sprites"]), RomLayout.POKEGEAR_SPRITE_TILES],
	]:
		var name: String = String(run[0])
		var tiles: int = int(run[2])
		var raw: PackedByteArray = _lz.decompress(rom.bytes(), int(run[1]))
		if _lz.failed or raw.size() < tiles * Gen2Tiles.TILE_BYTES:
			return {}
		var indices: PackedByteArray = Gen2Tiles.decode_2bpp_strip(raw, 0, tiles)
		if not RomCache.write_indices(RomCache.tile_path(directory, name), indices):
			return {}
		out[name] = _strip_sheet_entry(tiles)
	return out


## `BillsPC_InitGFX`'s two runs: the compressed cursor sheet and the mail and
## item markers stored uncompressed behind it.
func _import_pc_sheets(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout.get("pc", {})
	if entry.is_empty():
		return {}
	var directory: String = RomCache.directory_for(rom.id, rom.sha1)
	var raw: PackedByteArray = _lz.decompress(rom.bytes(), int(entry["select_gfx"]))
	if _lz.failed or raw.size() < RomLayout.PC_SELECT_TILES * Gen2Tiles.TILE_BYTES:
		return {}
	var out: Dictionary = {}
	for run: Array in [
		["pc_select", Gen2Tiles.decode_2bpp_strip(raw, 0, RomLayout.PC_SELECT_TILES),
			RomLayout.PC_SELECT_TILES],
		["pc_mail", Gen2Tiles.decode_2bpp_strip(
			rom.bytes(), int(entry["mail_gfx"]), RomLayout.PC_MAIL_TILES),
			RomLayout.PC_MAIL_TILES],
	]:
		if not RomCache.write_indices(
			RomCache.tile_path(directory, String(run[0])), run[1]
		):
			return {}
		out[String(run[0])] = _strip_sheet_entry(int(run[2]))
	return out


## `Pokedex_LoadGFX`'s two LZ runs, each as one strip of tiles.
##
## Kept out of the fixed table [method _import_tiles] uses for the same reason
## the region map's are: a compressed run has to be decompressed before its tile
## count is even known.
func _import_pokedex_sheets(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout.get("pokedex", {})
	if not entry.has("gfx"):
		return {}
	var directory: String = RomCache.directory_for(rom.id, rom.sha1)
	var out: Dictionary = {}
	for run: Array in [
		["pokedex", int(entry["gfx"]), RomLayout.POKEDEX_TILES],
		["pokedex_slowpoke", int(entry["slowpoke"]), RomLayout.POKEDEX_SLOWPOKE_TILES],
	]:
		var name: String = String(run[0])
		var tiles: int = int(run[2])
		var raw: PackedByteArray = _lz.decompress(rom.bytes(), int(run[1]))
		if _lz.failed or raw.size() < tiles * Gen2Tiles.TILE_BYTES:
			return {}
		var indices: PackedByteArray = Gen2Tiles.decode_2bpp_strip(raw, 0, tiles)
		if not RomCache.write_indices(RomCache.tile_path(directory, name), indices):
			return {}
		out[name] = _strip_sheet_entry(tiles)
	return out


## The title screen's graphics, each as one strip of tiles.
##
## Every one but the trail is an LZ run, so they cannot go through the fixed
## table [method _import_tiles] uses: each is decompressed first and the strip
## written from the result. The names are the source's own symbols with the
## profile split dropped, since a cache only ever holds one cartridge's.
func _import_title_sheets(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout.get("title", {})
	if entry.is_empty():
		return {}
	var runs: Array = []
	if int(entry.get("suicune", -1)) >= 0:
		runs = [
			["title_suicune", int(entry["suicune"]), RomLayout.TITLE_SUICUNE_TILES],
			["title_logo", int(entry["logo"]), RomLayout.TITLE_LOGO_TILES],
			["title_crystal", int(entry["crystal"]), RomLayout.TITLE_CRYSTAL_TILES],
		]
	else:
		runs = [
			[
				"title_logo_bottom", int(entry["logo_bottom"]),
				RomLayout.TITLE_LOGO_BOTTOM_TILES,
			],
			["title_logo_top", int(entry["logo_top"]), RomLayout.TITLE_LOGO_TOP_TILES],
			["title_bird", int(entry["bird"]), int(entry["bird_tiles"])],
		]

	var directory: String = RomCache.directory_for(rom.id, rom.sha1)
	var out: Dictionary = {}
	for run: Array in runs:
		var name: String = String(run[0])
		var tiles: int = int(run[2])
		var raw: PackedByteArray = _lz.decompress(rom.bytes(), int(run[1]))
		if _lz.failed or raw.size() < tiles * Gen2Tiles.TILE_BYTES:
			return {}
		var indices: PackedByteArray = Gen2Tiles.decode_2bpp_strip(raw, 0, tiles)
		if not RomCache.write_indices(RomCache.tile_path(directory, name), indices):
			return {}
		out[name] = _strip_sheet_entry(tiles)
	return out


func _strip_sheet_entry(tiles: int) -> Dictionary:
	return {
		"width": tiles * Gen2Tiles.TILE_WIDTH,
		"height": Gen2Tiles.TILE_HEIGHT,
		"tiles": tiles,
		"first_code": 0,
		"bits": 2,
	}


## `_UnownPuzzle`'s art section. `PuzzlePieceBorderData.TileBordersGFX` is pinned
## on its own because thirty-four bytes of code sit between it and the run;
## everything from `UnownPuzzleCursorGFX` on is one walk, each address the
## previous entry's consumed length, with no alignment between them.
##
## Returns {name: PackedByteArray} in `UNOWN_PUZZLE_SECTION` order plus
## `tile_borders`, or an empty Dictionary if any entry does not decompress to
## its own size.
static func read_unown_puzzle_section(rom: RomFile, layout: Dictionary) -> Dictionary:
	var entry: Dictionary = layout.get("unown_puzzle", {})
	var borders: int = int(entry.get("tile_borders", -1))
	var at: int = int(entry.get("section", -1))
	if borders < 0 or at < 0:
		return {}
	var border_bytes: int = RomLayout.UNOWN_PUZZLE_BORDER_TILES * Gen2Tiles.TILE_BYTES
	if not rom.in_bounds(borders, border_bytes):
		return {}
	var lz := Gen2Lz.new()
	var out: Dictionary = {"tile_borders": rom.slice(borders, border_bytes)}
	for row: Array in RomLayout.UNOWN_PUZZLE_SECTION:
		var name: String = String(row[0])
		var wanted: int = int(row[2]) * Gen2Tiles.TILE_BYTES
		var raw: PackedByteArray = PackedByteArray()
		var consumed: int = 0
		if String(row[1]) == "raw":
			if not rom.in_bounds(at, wanted):
				return {}
			raw = rom.slice(at, wanted)
			consumed = wanted
		else:
			raw = lz.decompress(rom.bytes(), at)
			consumed = lz.consumed
			if lz.failed or raw.size() != wanted:
				return {}
		out[name] = raw
		at += consumed
		## The four pictures' own `.lz` files are zero-padded past the `$ff` the
		## decompressor stops on: four bytes after Ho-Oh's stream, fifteen after
		## Aerodactyl's, ten after Kabuto's, none after START>CANCEL's. A `$00`
		## after a terminator cannot be a command, so the fill is skipped rather
		## than modelled as an alignment, which no power of two fits. The walk
		## still checks itself: every entry behind the fill has to decompress to
		## exactly its own size.
		while rom.in_bounds(at) and rom.u8(at) == 0:
			at += 1
	return out


## The seven strips above, written the way the intro's are, plus the one palette
## `_CGB_UnownPuzzle` draws the whole screen in.
func _import_unown_puzzle_sheets(rom: RomFile, layout: Dictionary) -> Dictionary:
	var section: Dictionary = read_unown_puzzle_section(rom, layout)
	if section.is_empty():
		return {}
	var directory: String = RomCache.directory_for(rom.id, rom.sha1)
	var out: Dictionary = {}
	var rows: Array = [
		["tile_borders", "raw", RomLayout.UNOWN_PUZZLE_BORDER_TILES]
	]
	rows.append_array(RomLayout.UNOWN_PUZZLE_SECTION)
	for row: Array in rows:
		var name: String = String(row[0])
		var tiles: int = int(row[2])
		var path: String = RomCache.tile_path(directory, "unown_puzzle_%s" % name)
		if not RomCache.write_indices(
			path, Gen2Tiles.decode_2bpp_strip(section[name], 0, tiles)
		):
			return {}
		out["unown_puzzle_%s" % name] = _strip_sheet_entry(tiles)
	return out


## `_CGB_UnownPuzzle`: `PalPacket_UnownPuzzle` names PREDEFPAL_UNOWN_PUZZLE for
## all four background palettes, and object palette 0 is the same entry with its
## first colour overwritten red, which is the colour the cursor is drawn in.
func _import_unown_puzzle(rom: RomFile, layout: Dictionary) -> Dictionary:
	var palette: Array = _import_predef_palette(
		rom, layout, RomLayout.PREDEFPAL_UNOWN_PUZZLE
	)
	if palette.is_empty():
		return {}
	return {"palette": palette}


## `GameFreakDittoGFX`, the one LZ run in the splash. `GameFreakPresentsInit`
## splits it over `vTiles0` and `vTiles1` as 128 tiles each, and the OAM sets
## index the result with a stride of $10, so it is kept as one strip of 256 and
## a page turns a tile number into a column. Empty on a profile with no Ditto.
func _import_ditto_sheet(rom: RomFile, layout: Dictionary) -> Dictionary:
	var at: int = int((layout.get("game_freak_presents", {}) as Dictionary).get("ditto", -1))
	if at < 0:
		return {}
	var raw: PackedByteArray = _lz.decompress(rom.bytes(), at)
	var wanted: int = RomLayout.PRESENTS_DITTO_TILES * Gen2Tiles.TILE_BYTES
	if _lz.failed or raw.size() < wanted:
		return {}
	var indices: PackedByteArray = Gen2Tiles.decode_2bpp_strip(
		raw, 0, RomLayout.PRESENTS_DITTO_TILES
	)
	var directory: String = RomCache.directory_for(rom.id, rom.sha1)
	if not RomCache.write_indices(RomCache.tile_path(directory, "game_freak_ditto"), indices):
		return {}
	return {
		"game_freak_ditto": {
			"width": RomLayout.PRESENTS_DITTO_TILES * Gen2Tiles.TILE_WIDTH,
			"height": Gen2Tiles.TILE_HEIGHT,
			"tiles": RomLayout.PRESENTS_DITTO_TILES,
			"first_code": 0,
			"bits": 2,
		},
	}


## Decodes the fixed tile sheets: the font, the eight text box borders and the
## battle HUD's graphics, each as one strip of tiles.
##
## None is compressed or per-species, so there is nothing to look up: each is a
## fixed run of tiles at a known place. Strips, because each is addressed by a
## number (a character code, a tile in a bar) and a strip turns that number into
## a horizontal offset and nothing else.
##
## [code]first_code[/code] is the character code the first tile draws, zero for
## graphics sheets. [code]bits[/code] is the cartridge's storage: font and
## borders 1bpp, battle graphics 2bpp.
func _import_tiles(rom: RomFile, layout: Dictionary, on_progress: Callable) -> Dictionary:
	var data: PackedByteArray = rom.bytes()
	var card: Dictionary = layout["trainer_card"]
	var intro_player: Dictionary = layout["intro_player"]
	var presents: Dictionary = layout.get("game_freak_presents", {})
	var sheets: Dictionary = {
		"font": {
			"offset": RomLayout.font_offset(layout),
			"tiles": RomLayout.FONT_TILES,
			"first_code": RomLayout.FONT_FIRST_CODE,
			"bits": 1,
		},
		"font_extra": {
			"offset": RomLayout.font_extra_offset(layout),
			"tiles": RomLayout.FONT_EXTRA_TILES,
			"first_code": RomLayout.FONT_EXTRA_FIRST_CODE,
			"bits": 2,
		},
		"frames": {
			"offset": RomLayout.frame_offset(layout, 0),
			"tiles": RomLayout.FRAME_COUNT * RomLayout.FRAME_TILES,
			"first_code": RomLayout.FRAME_FIRST_CODE,
			"bits": 1,
		},
		"battle_font": {
			"offset": int(layout["battle_font"]),
			"tiles": RomLayout.BATTLE_FONT_TILES,
			"first_code": 0,
			"bits": 2,
		},
		# `'▲'`, the one tile a scrolling menu needs that no font strip carries:
		# Crystal loads it out of a 2bpp sheet of its own and Gold and Silver
		# out of the second tile of a 1bpp pair.
		"up_arrow": {
			"offset": int((layout.get("up_arrow", {}) as Dictionary).get("offset", -1)),
			"tiles": 1,
			"first_code": Gen2Text.UP_ARROW_CODE,
			"bits": int((layout.get("up_arrow", {}) as Dictionary).get("bits", 2)),
		},
		"enemy_hud": {
			"offset": int(layout["enemy_hud"]),
			"tiles": RomLayout.ENEMY_HUD_TILES,
			"first_code": 0,
			"bits": 1,
		},
		"player_hud": {
			"offset": int(layout["player_hud"]),
			"tiles": RomLayout.PLAYER_HUD_TILES,
			"first_code": 0,
			"bits": 1,
		},
		"exp_bar": {
			"offset": int(layout["exp_bar"]),
			"tiles": RomLayout.EXP_BAR_TILES,
			"first_code": 0,
			"bits": 2,
		},
		## `LoadBallIconGFX`, the party balls `BattleStart_TrainerHuds` puts
		## over both huds while a battle is opening.
		"ball_icons": {
			"offset": int(layout["ball_icons"]),
			"tiles": RomLayout.BALL_ICON_TILES,
			"first_code": 0,
			"bits": 2,
		},
		## `BattleTransitionTiles`, the two `DoBattleTransition` wipes with.
		"battle_transition": {
			"offset": int((layout["battle_transition"] as Dictionary)["tiles"]),
			"tiles": RomLayout.BATTLE_TRANSITION_TILES,
			"first_code": 0,
			"bits": 2,
		},
		## `StatsScreenPageTilesGFX`, which the stats screen and the move
		## screen both load at `vTiles2 tile $31`.
		"stats_tiles": {
			"offset": RomLayout.stats_tiles_offset(layout),
			"tiles": RomLayout.STATS_TILES,
			"first_code": 0,
			"bits": 2,
		},
		"card_status": {
			"offset": int(card["status"]),
			"tiles": RomLayout.CARD_STATUS_TILES,
			"first_code": 0,
			"bits": 2,
		},
		"card_leaders": {
			"offset": int(card["leaders"]),
			"tiles": RomLayout.CARD_LEADER_TILES,
			"first_code": 0,
			"bits": 2,
		},
		"card_badges": {
			"offset": int(card["badges"]),
			"tiles": RomLayout.CARD_BADGE_TILES,
			"first_code": 0,
			"bits": 2,
		},
		"card_frame": {
			"offset": int(card["frame"]),
			"tiles": RomLayout.CARD_FRAME_TILES,
			"first_code": 0,
			"bits": 2,
		},
		## `Footprints`, one 1bpp strip of every species' four tiles.
		## `Pokedex_GetAndPlaceFootprint` addresses a half at a time, so the
		## strip is stored the cartridge's way and read through
		## [method GameData.footprint_tiles] rather than reordered here.
		## `UnownFont`, which `Pokedex_LoadUnownFont` inverts over the dex
		## sheet's own tiles rather than loading beside it.
		"unown_font": {
			"offset": int(layout["pokedex"]["unown_font"]),
			"tiles": RomLayout.UNOWN_FONT_TILES,
			"first_code": 0,
			"bits": 2,
		},
		"footprints": {
			"offset": int(layout["pokedex"]["footprints"]),
			"tiles": RomLayout.FOOTPRINT_SLOTS * RomLayout.FOOTPRINT_TILES,
			"first_code": 0,
			"bits": 1,
		},
		## LoadNamingScreenGFX's own four. The border and the cursor are 2bpp,
		## the two entry markers 1bpp, and all four are located from the keyboard
		## block they are stored beside.
		"naming_border": {
			"offset": RomLayout.naming_border_offset(layout),
			"tiles": RomLayout.NAMING_BORDER_TILES,
			"first_code": 0,
			"bits": 2,
		},
		"naming_cursor": {
			"offset": RomLayout.naming_cursor_offset(layout),
			"tiles": RomLayout.NAMING_CURSOR_TILES,
			"first_code": 0,
			"bits": 2,
		},
		"naming_middle_line": {
			"offset": RomLayout.naming_middle_line_offset(layout),
			"tiles": RomLayout.NAMING_MARKER_TILES,
			"first_code": 0,
			"bits": 1,
		},
		"naming_under_line": {
			"offset": RomLayout.naming_under_line_offset(layout),
			"tiles": RomLayout.NAMING_MARKER_TILES,
			"first_code": 0,
			"bits": 1,
		},
		## `Copyright`'s own strip, requested into `vTiles2 tile $60`. first_code
		## is that $60, so the string's codes address the strip directly.
		"copyright": {
			"offset": int((layout["copyright"] as Dictionary)["gfx"]),
			"tiles": int((layout["copyright"] as Dictionary)["tiles"]),
			"first_code": RomLayout.COPYRIGHT_FIRST_CODE,
			"bits": 2,
		},
		## `GameFreakLogoGFX`. Two graphics, one `Get1bpp`: the BG strings index
		## the head of it and Gold's logo sprite the tail, so it stays the one
		## strip the cartridge loads.
		"game_freak_logo": {
			"offset": int(presents.get("gfx", -1)),
			"tiles": RomLayout.PRESENTS_GFX_TILES,
			"first_code": 0,
			"bits": 1,
		},
		"card_pic_male": {
			"offset": int(card["pic_male"]),
			"tiles": RomLayout.CARD_PIC_TILES,
			"first_code": 0,
			"bits": 2,
			"columns": RomLayout.CARD_PIC_COLUMNS,
			"column_major": bool(card["pic_columns"]),
		},
	}
	## `Credits`' own three requests. `CreditsBorderGFX` goes to `vTiles2 tile
	## $20` and `TheEndGFX` to `$40`, so each carries its own first_code and a
	## tile number resolves straight into a strip; the mon sheets are addressed
	## by `.Frames`' block rather than by tile number and stay one run.
	var credits: Dictionary = layout.get("credits", {})
	if not credits.is_empty():
		sheets["credits_border"] = {
			"offset": int(credits["gfx"]),
			"tiles": RomLayout.CREDITS_BORDER_TILES,
			"first_code": RomLayout.CREDITS_BORDER_FIRST_CODE,
			"bits": 2,
		}
		sheets["credits_the_end"] = {
			"offset": int(credits["the_end"]),
			"tiles": RomLayout.CREDITS_THE_END_TILES,
			"first_code": RomLayout.CREDITS_THE_END_FIRST_CODE,
			"bits": 2,
		}
		sheets["credits_mons"] = {
			"offset": RomLayout.credits_mon_gfx_offset(layout),
			"tiles": RomLayout.credits_mon_tiles(layout),
			"first_code": 0,
			"bits": 2,
		}
	## Crystal only: pokegold ships neither a Kris pic nor the right corner, and
	## says so with the -1 every layout uses for data a profile does not carry.
	if int(card["pic_female"]) >= 0:
		sheets["card_pic_female"] = {
			"offset": int(card["pic_female"]),
			"tiles": RomLayout.CARD_PIC_TILES,
			"first_code": 0,
			"bits": 2,
			"columns": RomLayout.CARD_PIC_COLUMNS,
			"column_major": bool(card["pic_columns"]),
		}
	if int(card["right_corner"]) >= 0:
		sheets["card_right_corner"] = {
			"offset": int(card["right_corner"]),
			"tiles": RomLayout.CARD_RIGHT_CORNER_TILES,
			"first_code": 0,
			"bits": 2,
		}
	if int(intro_player["pic_male"]) >= 0:
		sheets["intro_player_male"] = {
			"offset": int(intro_player["pic_male"]),
			"tiles": RomLayout.INTRO_PLAYER_PIC_TILES,
			"first_code": 0,
			"bits": 2,
			"columns": RomLayout.INTRO_PLAYER_PIC_COLUMNS,
			"column_major": true,
		}
	if int(intro_player["pic_female"]) >= 0:
		sheets["intro_player_female"] = {
			"offset": int(intro_player["pic_female"]),
			"tiles": RomLayout.INTRO_PLAYER_PIC_TILES,
			"first_code": 0,
			"bits": 2,
			"columns": RomLayout.INTRO_PLAYER_PIC_COLUMNS,
			"column_major": true,
		}
	## `GameFreakLogoStarsGFX`, Gold and Silver's own beat. Crystal spends it on
	## the Ditto instead and says so with a -1.
	if int(presents.get("stars", -1)) >= 0:
		sheets["game_freak_stars"] = {
			"offset": int(presents["stars"]),
			"tiles": RomLayout.PRESENTS_STARS_TILES,
			"first_code": 0,
			"bits": 2,
		}

	## `MapEntryFrameGFX`, the map name sign's frame. Crystal only: Gold and
	## Silver ship neither the sheet nor `InitMapNameSign`, and say so with the
	## -1 every absent record uses.
	if int(layout.get("map_entry_sign", -1)) >= 0:
		sheets["map_entry_sign"] = {
			"offset": int(layout["map_entry_sign"]),
			"tiles": RomLayout.MAP_ENTRY_SIGN_TILES,
			"first_code": 0,
			"bits": 2,
		}

	var gender_screen: Dictionary = layout["gender_screen"]
	if int(gender_screen["tile"]) >= 0:
		sheets["gender_screen"] = {
			"offset": int(gender_screen["tile"]),
			"tiles": RomLayout.GENDER_SCREEN_TILES,
			"first_code": 0,
			"bits": 2,
		}

	## `TitleScreenGFX3`, the one title graphic that is not compressed: Gold and
	## Silver only, and Gold's own four blank tiles behind it are kept, since
	## `TitleScreen` copies eight tiles whatever the trail's own length is.
	var region_map: Dictionary = layout.get("town_map", {})
	if int(region_map.get("fast_ship", -1)) >= 0:
		sheets["fast_ship"] = {
			"offset": int(region_map["fast_ship"]),
			"tiles": RomLayout.FAST_SHIP_TILES,
			"first_code": 0,
			"bits": 2,
		}

	## `PokedexNestIconGFX`, the AREA screen's own object tile.
	if RomLayout.dex_nest_icon_offset(layout) >= 0:
		sheets["dex_nest_icon"] = {
			"offset": RomLayout.dex_nest_icon_offset(layout),
			"tiles": RomLayout.DEX_NEST_ICON_TILES,
			"first_code": 0,
			"bits": 2,
		}

	## `Pack_InitGFX`'s own two runs. The pocket pictures are one strip of all
	## four rather than the fifteen tiles `DrawPackGFX` requests, since a cache
	## holds what the cartridge stores and the screen picks its pocket out of it.
	var pack: Dictionary = layout.get("pack", {})
	if not pack.is_empty():
		sheets["pack_menu"] = {
			"offset": int(pack["menu_gfx"]),
			"tiles": RomLayout.PACK_MENU_TILES,
			"first_code": 0,
			"bits": 2,
		}
		sheets["pack_pockets"] = {
			"offset": RomLayout.pack_gfx_offset(layout),
			"tiles": RomLayout.PACK_TILES,
			"first_code": 0,
			"bits": 2,
		}
		if int(pack.get("female_gfx", -1)) >= 0:
			sheets["pack_pockets_female"] = {
				"offset": int(pack["female_gfx"]),
				"tiles": RomLayout.PACK_TILES,
				"first_code": 0,
				"bits": 2,
			}

	var title: Dictionary = layout.get("title", {})
	if int(title.get("trail", -1)) >= 0:
		sheets["title_trail"] = {
			"offset": int(title["trail"]),
			"tiles": int(title["trail_tiles"]),
			"first_code": 0,
			"bits": 2,
		}

	var written: Dictionary = _import_shrink_pics(rom, layout)
	written.merge(_import_ditto_sheet(rom, layout), true)
	written.merge(_import_title_sheets(rom, layout), true)
	written.merge(_import_town_map_sheets(rom, layout), true)
	written.merge(_import_pokedex_sheets(rom, layout), true)
	written.merge(_import_pc_sheets(rom, layout), true)
	written.merge(_import_intro_sheets(rom, layout), true)
	written.merge(_import_gs_intro_sheets(rom, layout), true)
	written.merge(_import_unown_puzzle_sheets(rom, layout), true)
	var done: int = 0
	for name: String in sheets:
		var sheet: Dictionary = sheets[name]
		var count: int = sheet["tiles"]
		var indices: PackedByteArray = _decode_strip(data, sheet)
		var directory: String = RomCache.directory_for(rom.id, rom.sha1)
		if not RomCache.write_indices(RomCache.tile_path(directory, name), indices):
			return {}
		written[name] = {
			"width": count * Gen2Tiles.TILE_WIDTH,
			"height": Gen2Tiles.TILE_HEIGHT,
			"tiles": count,
			"first_code": sheet["first_code"],
			"bits": sheet["bits"],
		}

		done += 1
		if on_progress.is_valid():
			on_progress.call("tiles", done, sheets.size())

	return written


static func _decode_strip(data: PackedByteArray, sheet: Dictionary) -> PackedByteArray:
	if int(sheet["bits"]) == 1:
		return Gen2Tiles.decode_1bpp_strip(data, int(sheet["offset"]), int(sheet["tiles"]))
	var strip: PackedByteArray = Gen2Tiles.decode_2bpp_strip(
		data, int(sheet["offset"]), int(sheet["tiles"])
	)
	## Only the card pic carries a column count, and only Crystal stores it that
	## way; Gold and Silver hold the same picture row-major already.
	var columns: int = int(sheet.get("columns", 0))
	if columns <= 0 or not bool(sheet.get("column_major", false)):
		return strip
	return _rows_from_columns(strip, columns, int(sheet["tiles"]) / columns)


## Crystal's card pic is stored column-major, since `PlaceGraphic` fills down
## each column and its PNG is converted with `--columns`. Gold and Silver store
## the same picture row-major for their own inline loop. This turns the first
## into the second, so a screen reads one order on both profiles.
static func _rows_from_columns(
	strip: PackedByteArray, columns: int, rows: int
) -> PackedByteArray:
	var tile_pixels: int = Gen2Tiles.TILE_WIDTH * Gen2Tiles.TILE_HEIGHT
	if strip.size() < columns * rows * tile_pixels:
		return strip
	var out := PackedByteArray()
	out.resize(strip.size())
	for column: int in columns:
		for row: int in rows:
			var source_tile: int = column * rows + row
			var target_tile: int = row * columns + column
			for y: int in Gen2Tiles.TILE_HEIGHT:
				for x: int in Gen2Tiles.TILE_WIDTH:
					var from: int = source_tile * Gen2Tiles.TILE_WIDTH \
						+ y * (strip.size() / Gen2Tiles.TILE_HEIGHT) + x
					var to: int = target_tile * Gen2Tiles.TILE_WIDTH \
						+ y * (strip.size() / Gen2Tiles.TILE_HEIGHT) + x
					out[to] = strip[from]
	return out


## `PokemonPalettes` entry EGG, in the same two-pair shape a species carries.
func _read_egg_palette(rom: RomFile, layout: Dictionary) -> Dictionary:
	var at: int = RomLayout.palette_offset(layout, RomLayout.EGG_SPECIES)
	return {
		"normal": [rom.u16le(at), rom.u16le(at + 2)],
		"shiny": [rom.u16le(at + 4), rom.u16le(at + 6)],
	}


func _import_pics(
	rom: RomFile, layout: Dictionary, species: Array, on_progress: Callable
) -> Dictionary:
	var front: Dictionary = _new_atlas(RomLayout.FRONTPIC_MAX_TILES, RomLayout.SPECIES_COUNT)
	var back: Dictionary = _new_atlas(RomLayout.BACKPIC_TILES, RomLayout.SPECIES_COUNT)
	var unown_front: Dictionary = _new_atlas(RomLayout.FRONTPIC_MAX_TILES, RomLayout.UNOWN_FORMS)
	# `GetAnimatedEnemyFrontpic` loads the tiles past the pic's own `w * h` out
	# of the same decompressed run, into VRAM behind the padded 7x7 block. They
	# are frames, not a picture, so they get an atlas rather than a slot in the
	# one beside them.
	var animated: bool = not RomLayout.pic_anim(layout).is_empty()
	var front_anim: Dictionary = _new_atlas(RomLayout.FRONTPIC_MAX_TILES, RomLayout.SPECIES_COUNT)
	var unown_front_anim: Dictionary = _new_atlas(
		RomLayout.FRONTPIC_MAX_TILES, RomLayout.UNOWN_FORMS
	)
	var unown_back: Dictionary = _new_atlas(RomLayout.BACKPIC_TILES, RomLayout.UNOWN_FORMS)
	# `EggPic` is entry EGG of `PokemonPicPointers`, past the 251 species and the
	# unused slot between them, and `GetEggFrontpic` loads it the way any other
	# front pic is loaded. It gets an atlas of its own because there is no
	# species record to hang it on: EGG is a party species, not a Pokemon.
	var egg_front: Dictionary = _new_atlas(RomLayout.FRONTPIC_MAX_TILES, 1)
	var egg_side: int = RomLayout.EGG_PIC_TILES
	## Gold and Silver's table stops at NUM_POKEMON, so `_GetFrontpic` answers
	## EGG with `ld hl, EggPic` and the pic is at an address like a back pic.
	## Their picture is a different one.
	##
	## Crystal's run carries two animation frames that nothing reads:
	## `GetEggFrontpic` is `GetMonFrontpic`, not `GetAnimatedFrontpic`, and
	## `AnimateMon_CheckIfPokemon` refuses EGG before any script is read.
	var egg_at: int = int(layout.get("egg_pic", -1))
	if egg_at >= 0:
		_decode_lz_into(rom, egg_at, egg_side, egg_side, egg_front, 0)
	else:
		_decode_into(
			rom, layout, RomLayout.pic_pointer_offset(layout, RomLayout.EGG_SPECIES, false),
			egg_side, egg_side, egg_front, 0
		)
	var trainer_classes: int = RomLayout.trainer_class_count(layout)
	var trainers: Dictionary = _new_atlas(RomLayout.TRAINER_PIC_TILES, trainer_classes)
	# `GetTrainerBackpic`'s three, which are the player standing on the field
	# before a Pokemon is sent out rather than anybody's front pic.
	var player_back: Dictionary = _new_atlas(
		RomLayout.PLAYER_BACKPIC_TILES, RomLayout.PLAYER_BACKPICS.size()
	)
	var backpics: Dictionary = layout.get("player_backpic", {}) as Dictionary
	var side: int = RomLayout.PLAYER_BACKPIC_TILES
	for slot: int in RomLayout.PLAYER_BACKPICS.size():
		var kind: String = RomLayout.PLAYER_BACKPICS[slot]
		var at: int = int(backpics.get(kind, -1))
		if at < 0:
			continue
		# "Kris's backpic is uncompressed" (`GetKrisBackpic`): it is a plain
		# 2bpp run where the other two are LZ behind `GetTrainerBackpic`'s own
		# `.Decompress`. All three are stored column major, the way every pic is.
		if kind == "kris":
			_blit_pic(
				rom.bytes().slice(at, at + side * side * Gen2Tiles.TILE_BYTES),
				side, side, player_back, slot
			)
			continue
		_decode_lz_into(rom, at, side, side, player_back, slot)

	for entry: Dictionary in species:
		var number: int = entry["number"]
		var tiles: Array = entry["front_tiles"]
		var slot: int = number - 1

		# Unown's main-table entry is a placeholder. Its forms are decoded into
		# their own atlas, and the species slot gets form A so a caller that
		# does not know about forms still gets a sprite rather than a hole.
		var source: int = number
		if number == RomLayout.UNOWN_SPECIES:
			for form: int in RomLayout.UNOWN_FORMS:
				_decode_into(
					rom, layout, RomLayout.unown_pic_pointer_offset(layout, form, false),
					tiles[0], tiles[1], unown_front, form
				)
				if animated:
					_decode_into(
						rom, layout, RomLayout.unown_pic_pointer_offset(layout, form, false),
						tiles[0], tiles[1], unown_front_anim, form, tiles[0] * tiles[1]
					)
				_decode_into(
					rom, layout, RomLayout.unown_pic_pointer_offset(layout, form, true),
					RomLayout.BACKPIC_TILES, RomLayout.BACKPIC_TILES, unown_back, form
				)
			_decode_into(
				rom, layout, RomLayout.unown_pic_pointer_offset(layout, 0, false),
				tiles[0], tiles[1], front, slot
			)
			_decode_into(
				rom, layout, RomLayout.unown_pic_pointer_offset(layout, 0, true),
				RomLayout.BACKPIC_TILES, RomLayout.BACKPIC_TILES, back, slot
			)
		else:
			_decode_into(
				rom, layout, RomLayout.pic_pointer_offset(layout, source, false),
				tiles[0], tiles[1], front, slot
			)
			if animated:
				_decode_into(
					rom, layout, RomLayout.pic_pointer_offset(layout, source, false),
					tiles[0], tiles[1], front_anim, slot, tiles[0] * tiles[1]
				)
			_decode_into(
				rom, layout, RomLayout.pic_pointer_offset(layout, source, true),
				RomLayout.BACKPIC_TILES, RomLayout.BACKPIC_TILES, back, slot
			)

		if on_progress.is_valid():
			on_progress.call("pics", number, RomLayout.SPECIES_COUNT)

	# Trainer pics share the pointer form and the bank repair, and differ in that
	# every one of them is the same square and none of them has a back half.
	for trainer_class: int in range(1, trainer_classes + 1):
		_decode_into(
			rom, layout, RomLayout.trainer_pic_pointer_offset(layout, trainer_class),
			RomLayout.TRAINER_PIC_TILES, RomLayout.TRAINER_PIC_TILES, trainers, trainer_class - 1
		)

		if on_progress.is_valid():
			on_progress.call("trainer pics", trainer_class, trainer_classes)

	var directory: String = RomCache.directory_for(rom.id, rom.sha1)
	var atlases: Dictionary = {
		"front": front, "back": back, "unown_front": unown_front, "unown_back": unown_back,
		"trainers": trainers, "player_back": player_back, "egg_front": egg_front,
	}
	# `AnimateFrontpic` is Crystal's alone, so the two atlases behind the front
	# pics are written only where something reads them.
	if animated:
		atlases["front_anim"] = front_anim
		atlases["unown_front_anim"] = unown_front_anim
	var written: Dictionary = {}
	for name: String in atlases:
		var atlas: Dictionary = atlases[name]
		if not RomCache.write_indices(RomCache.pic_path(directory, name), atlas["pixels"]):
			return {}
		written[name] = {
			"width": atlas["width"],
			"height": atlas["height"],
			"cell": atlas["cell"],
			"columns": ATLAS_COLUMNS,
			"decoded": atlas["decoded"],
		}
	return written


func _new_atlas(cell_tiles: int, cells: int) -> Dictionary:
	var cell: int = cell_tiles * Gen2Tiles.TILE_WIDTH
	var rows: int = ceili(float(cells) / ATLAS_COLUMNS)
	var width: int = ATLAS_COLUMNS * cell
	var height: int = rows * cell
	var pixels: PackedByteArray = PackedByteArray()
	pixels.resize(width * height)
	return {
		"pixels": pixels, "width": width, "height": height, "cell": cell, "decoded": 0,
	}


## The same as [method _decode_into] for a pic the cartridge stores at an
## address rather than behind a pointer, which is what `GetTrainerBackpic`'s
## three `ld hl, ChrisBackpic` are.
func _decode_lz_into(
	rom: RomFile, start: int, columns: int, rows: int, atlas: Dictionary, slot: int
) -> bool:
	if columns <= 0 or rows <= 0 or not rom.in_bounds(start):
		return false
	var raw: PackedByteArray = _lz.decompress(rom.bytes(), start)
	if _lz.failed or raw.size() < columns * rows * Gen2Tiles.TILE_BYTES:
		return false
	_blit_pic(raw, columns, rows, atlas, slot)
	return true


## [param skip_tiles] takes the run past the picture instead of the picture:
## `GetAnimatedEnemyFrontpic` reads `wDecompressEnemyFrontpic + w * h tiles` for
## the animation's own frames, which are the same LZ run's tail.
func _decode_into(
	rom: RomFile,
	layout: Dictionary,
	pointer_offset: int,
	columns: int,
	rows: int,
	atlas: Dictionary,
	slot: int,
	skip_tiles: int = 0
) -> bool:
	if columns <= 0 or rows <= 0:
		return false

	var pointer: Dictionary = rom.far_pointer(pointer_offset)
	var bank: int = RomLayout.fix_pic_bank(layout, pointer["bank"])
	var start: int = RomFile.linear(bank, pointer["address"])
	if not rom.in_bounds(start):
		return false

	var raw: PackedByteArray = _lz.decompress(rom.bytes(), start)
	if _lz.failed or raw.size() < (skip_tiles + columns * rows) * Gen2Tiles.TILE_BYTES:
		# The animation's tail is as long as the picture only when every frame
		# tile is distinct: `front.animated.2bpp` deduplicates them, and
		# `GetAnimatedEnemyFrontpic` copies `w * h` whatever is there, so the
		# short ones end in tiles no frame names. Pad rather than refuse.
		if skip_tiles <= 0 or raw.size() <= skip_tiles * Gen2Tiles.TILE_BYTES:
			return false
		raw.resize((skip_tiles + columns * rows) * Gen2Tiles.TILE_BYTES)

	_blit_pic(raw, columns, rows, atlas, slot, skip_tiles)
	return true


## One decompressed pic into its cell of an atlas.
func _blit_pic(
	raw: PackedByteArray, columns: int, rows: int, atlas: Dictionary, slot: int,
	skip_tiles: int = 0
) -> void:
	var pixels: PackedByteArray = Gen2Tiles.decode_pic(
		raw.slice(skip_tiles * Gen2Tiles.TILE_BYTES) if skip_tiles > 0 else raw, columns, rows
	)
	var cell: int = atlas["cell"]
	Gen2Tiles.blit(
		pixels, columns * Gen2Tiles.TILE_WIDTH,
		atlas["pixels"], atlas["width"],
		(slot % ATLAS_COLUMNS) * cell, floori(float(slot) / float(ATLAS_COLUMNS)) * cell
	)
	atlas["decoded"] = int(atlas["decoded"]) + 1


## `AnimateFrontpic`'s tables: one record per species and one per Unown letter,
## each carrying the two scripts and the frames they name. Empty for a cartridge
## with no `pic_anim` pins, which is Gold and Silver: neither ships
## `pic_animation.asm` and both send-outs reach `PlayStereoCry` directly.
##
## A frame is stored as its bitmask followed by its tile numbers, which is what
## `PokeAnim_GetFrame` reads in that order, so one byte run holds a frame and
## the bitmask table's own deduplication is resolved here rather than at every
## draw.
func _import_pic_anims(rom: RomFile, layout: Dictionary, species: Array) -> Dictionary:
	var pins: Dictionary = RomLayout.pic_anim(layout)
	if pins.is_empty():
		return {}

	var heights: Dictionary = {}
	for entry: Dictionary in species:
		heights[int(entry["number"])] = int((entry["front_tiles"] as Array)[1])

	var out: Dictionary = {"species": {}, "unown": []}
	for number: int in range(1, RomLayout.SPECIES_COUNT + 1):
		var record: Dictionary = _read_pic_anim(
			rom, int(heights.get(number, 0)), int(pins["script_bank"]),
			int(pins["scripts"]) + (number - 1) * 2,
			int(pins["idle_scripts"]) + (number - 1) * 2,
			int(pins["bitmask_pointers"]) + (number - 1) * 2, int(pins["bitmask_bank"]),
			int(pins["frame_pointers"]) + (number - 1) * 2,
			int(pins["kanto_frame_bank"]) if number < RomLayout.JOHTO_SPECIES \
				else int(pins["johto_frame_bank"])
		)
		if record.is_empty():
			return {}
		out["species"][str(number)] = record

	# Unown is one placeholder in the species tables and 26 letters here, the
	# split `PokeAnim_GetSpeciesOrUnown` makes.
	var unown_height: int = int(heights.get(RomLayout.UNOWN_SPECIES, 0))
	for form: int in RomLayout.UNOWN_FORMS:
		var record: Dictionary = _read_pic_anim(
			rom, unown_height, int(pins["script_bank"]),
			int(pins["unown_scripts"]) + form * 2,
			int(pins["unown_idle_scripts"]) + form * 2,
			int(pins["unown_bitmask_pointers"]) + form * 2, int(pins["bitmask_bank"]),
			int(pins["unown_frame_pointers"]) + form * 2, int(pins["unown_frame_bank"])
		)
		if record.is_empty():
			return {}
		(out["unown"] as Array).append(record)
	return out


## One species' or letter's record. Every pointer here is a plain in-bank word:
## a script and a bitmask are read in their table's own bank, and a frame in the
## bank its data lives in rather than its pointer table's.
func _read_pic_anim(
	rom: RomFile,
	height: int,
	script_bank: int,
	script_pointer: int,
	idle_pointer: int,
	bitmask_pointer: int,
	bitmask_bank: int,
	frame_pointer: int,
	frame_bank: int
) -> Dictionary:
	var mask_bytes: int = RomLayout.pic_anim_bitmask_bytes(height)
	if mask_bytes <= 0:
		return {}
	var script: PackedByteArray = _read_pic_anim_script(rom, script_bank, script_pointer)
	var idle: PackedByteArray = _read_pic_anim_script(rom, script_bank, idle_pointer)
	if script.is_empty() or idle.is_empty():
		return {}

	# How many frames the two scripts between them name. Nothing bounds the
	# table on the cartridge: `PokeAnim_GetBitmaskIndex` indexes it with
	# `command - 1` and the highest command used is the last entry there is.
	var count: int = 0
	for run: PackedByteArray in [script, idle]:
		for at: int in range(0, run.size(), 2):
			if run[at] < PIC_ANIM_DOREPEAT:
				count = maxi(count, int(run[at]))
	var table: int = RomFile.linear(frame_bank, rom.u16le(frame_pointer))
	var masks: int = RomFile.linear(bitmask_bank, rom.u16le(bitmask_pointer))
	if not rom.in_bounds(table, count * 2):
		return {}

	var frames: Array = []
	for index: int in count:
		var frame: int = RomFile.linear(frame_bank, rom.u16le(table + index * 2))
		if not rom.in_bounds(frame):
			return {}
		var mask_at: int = masks + rom.u8(frame) * mask_bytes
		if not rom.in_bounds(mask_at, mask_bytes):
			return {}
		var mask: PackedByteArray = rom.slice(mask_at, mask_bytes)
		var tiles: int = 0
		for byte: int in mask:
			for bit: int in 8:
				tiles += (byte >> bit) & 1
		if not rom.in_bounds(frame + 1, tiles):
			return {}
		frames.append({"bytes": Array(mask + rom.slice(frame + 1, tiles))})

	return {
		"height": height,
		"script": {"bytes": Array(script)},
		"idle": {"bytes": Array(idle)},
		"frames": frames,
	}


## `frame`, `setrepeat` and `dorepeat` are all two bytes wide and `endanim` is
## one, but `PokeAnim_GetPointer` reads a word at every step, so the run is a
## table of pairs whose terminator's second byte is never looked at.
const PIC_ANIM_ENDANIM: int = 0xFF
const PIC_ANIM_SETREPEAT: int = 0xFE
const PIC_ANIM_DOREPEAT: int = 0xFD
## `wPokeAnimFrame` is a byte, so a script cannot honestly be longer than this.
const PIC_ANIM_MAX_COMMANDS: int = 256


func _read_pic_anim_script(rom: RomFile, bank: int, pointer: int) -> PackedByteArray:
	if not rom.in_bounds(pointer, 2):
		return PackedByteArray()
	var at: int = RomFile.linear(bank, rom.u16le(pointer))
	for index: int in PIC_ANIM_MAX_COMMANDS:
		if not rom.in_bounds(at + index * 2, 2):
			return PackedByteArray()
		if rom.u8(at + index * 2) == PIC_ANIM_ENDANIM:
			# The terminator is kept: an interpreter that walks the run needs an
			# end to reach, and its second byte is the cartridge's own.
			return rom.slice(at, (index + 1) * 2)
	return PackedByteArray()
