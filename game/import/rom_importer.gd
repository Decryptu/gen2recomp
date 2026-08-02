class_name RomImporter
extends RefCounted

## Decodes a verified cartridge into the cache under [code]user://[/code].
##
## The ROM is an asset database, read once and released. Nothing downstream of
## the cache holds a reference to it, and nothing in the engine reads cartridge
## bytes at play time.
##
## Order of business, and it matters: verify the hash, then verify the layout,
## then decode. [method verify_layout] exists because an offset table is a claim
## that can rot: a wrong constant produces plausible-looking garbage rather
## than an error, and garbage that reaches the cache is indistinguishable from
## real data later on. Checking a handful of values whose correct answers are
## known independently turns that class of mistake into an immediate failure.

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
		for i: int in Gen2Palette.ENTRY_BYTES / Gen2Palette.COLOR_BYTES:
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

	# The first and last type, either side of the padding run in the middle.
	var first_type: String = type_name(rom, layout, 0)
	if first_type != "NORMAL":
		return {"ok": false, "message": "Type table: expected NORMAL, read %s." % first_type}
	var last_type: String = type_name(rom, layout, RomLayout.TYPE_COUNT - 1)
	if last_type != "DARK":
		return {"ok": false, "message": "Type table: expected DARK, read %s." % last_type}

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

	return {"ok": true, "message": "Layout verified."}


## The font carries no name and no number, so it is checked against the one
## thing that is known about it independently: the charmap.
##
## The font is indexed by character code, so the letters and digits [Gen2Text]
## claims are there must have ink, and the runs of codes it has no character for
## must be blank. Those runs sit between the alphabets, so an offset out by a
## single tile drags a blank onto "z" and a glyph onto a code that has none, and
## the check fails in both directions at once.
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

	return {"ok": true, "message": ""}


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
## in the section does: they count.
##
## A bar's fill levels are consecutive tiles, each lighting one more column than
## the last, so the ink in that run climbs by exactly two pixels a step. Neither
## bar has a name or a number in the cartridge, but a run that counts up like
## that is not something a wrong offset lands on. The two HUD borders have
## neither content nor a progression, so they are checked the way the text box
## frames are: every tile has ink, and no two tiles are the same.
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
## They are checked together because they are three views of one numbering, and
## a mistake in any of them shows up as the three disagreeing: the names say what
## a class is, the palette table has one entry more than the pic table because
## the player owns the first one, and the pic table's entries have to decompress
## into pics of the one size every trainer is drawn at.
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
		"trainers": 0,
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

	var tiles: Dictionary = _import_tiles(rom, layout, on_progress)
	if tiles.is_empty():
		result["message"] = "Could not write the font."
		return result

	var moves: Array = _import_moves(rom, layout, on_progress)
	var items: Array = _import_items(rom, layout, on_progress)
	var types: Array = _import_types(rom, layout, on_progress)
	var trainers: Array = _import_trainers(rom, layout, on_progress)

	if not RomCache.write_json(RomCache.species_path(directory), species):
		result["message"] = "Could not write species data."
		return result
	if not RomCache.write_json(RomCache.moves_path(directory), moves):
		result["message"] = "Could not write move data."
		return result
	if not RomCache.write_json(RomCache.items_path(directory), items):
		result["message"] = "Could not write item data."
		return result
	if not RomCache.write_json(RomCache.types_path(directory), types):
		result["message"] = "Could not write type data."
		return result
	if not RomCache.write_json(RomCache.trainers_path(directory), trainers):
		result["message"] = "Could not write trainer data."
		return result

	var manifest: Dictionary = {
		"format_version": RomCache.FORMAT_VERSION,
		"game_id": String(rom.id),
		"sha1": rom.sha1,
		"species_count": species.size(),
		"move_count": moves.size(),
		"item_count": items.size(),
		"type_count": types.size(),
		"trainer_count": trainers.size(),
		"bar_palettes": _import_bar_palettes(rom, layout),
		"atlases": pics,
		"tiles": tiles,
		"complete": true,
	}
	if not RomCache.write_json(RomCache.manifest_path(directory), manifest):
		result["message"] = "Could not write manifest."
		return result

	result["ok"] = true
	result["species"] = species.size()
	result["moves"] = moves.size()
	result["items"] = items.size()
	result["types"] = types.size()
	result["trainers"] = trainers.size()
	result["elapsed_ms"] = Time.get_ticks_msec() - started
	result["message"] = "Imported %d species, %d moves, %d items and %d trainer classes in %d ms." % [
		species.size(), moves.size(), items.size(), trainers.size(), result["elapsed_ms"],
	]
	return result


func _import_species(rom: RomFile, layout: Dictionary, on_progress: Callable) -> Array:
	var data: PackedByteArray = rom.bytes()
	var out: Array = []

	for species: int in range(1, RomLayout.SPECIES_COUNT + 1):
		var stats: int = RomLayout.base_stats_offset(layout, species)
		var dimensions: int = rom.u8(stats + RomLayout.OFFSET_PIC_SIZE)
		var egg_groups: int = rom.u8(stats + RomLayout.OFFSET_EGG_GROUPS)
		var palette: int = RomLayout.palette_offset(layout, species)

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
			"front_tiles": [dimensions & 0x0F, dimensions >> 4],
			"palette": {
				"normal": [rom.u16le(palette), rom.u16le(palette + 2)],
				"shiny": [rom.u16le(palette + 4), rom.u16le(palette + 6)],
			},
		})

		if on_progress.is_valid():
			on_progress.call("species", species, RomLayout.SPECIES_COUNT)

	return out


func _import_moves(rom: RomFile, layout: Dictionary, on_progress: Callable) -> Array:
	var names: PackedStringArray = Gen2Text.decode_sequence(
		rom.bytes(), int(layout["move_names"]), RomLayout.MOVE_COUNT, RomLayout.MAX_NAME_LENGTH
	)
	var out: Array = []

	for move: int in range(1, RomLayout.MOVE_COUNT + 1):
		var entry: int = RomLayout.move_data_offset(layout, move)
		# The animation byte is dropped: it is the move's own number, and it is
		# already spent proving the table is where the layout says it is.
		out.append({
			"number": move,
			"name": names[move - 1],
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


func _import_items(rom: RomFile, layout: Dictionary, on_progress: Callable) -> Array:
	var names: PackedStringArray = Gen2Text.decode_sequence(
		rom.bytes(), int(layout["item_names"]), RomLayout.ITEM_COUNT, RomLayout.MAX_NAME_LENGTH
	)
	var out: Array = []

	for item: int in range(1, RomLayout.ITEM_COUNT + 1):
		out.append({"number": item, "name": names[item - 1]})
		if on_progress.is_valid():
			on_progress.call("items", item, RomLayout.ITEM_COUNT)

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
## A class has one palette and no shiny counterpart, so the pair is stored flat
## rather than under a key, and the pic is found by class number in the trainer
## atlas the way a species' is in the front one.
func _import_trainers(rom: RomFile, layout: Dictionary, on_progress: Callable) -> Array:
	var count: int = RomLayout.trainer_class_count(layout)
	var names: PackedStringArray = Gen2Text.decode_sequence(
		rom.bytes(), int(layout["trainer_class_names"]), count, RomLayout.MAX_NAME_LENGTH
	)
	var out: Array = []

	for trainer_class: int in range(1, count + 1):
		var palette: int = RomLayout.trainer_palette_offset(layout, trainer_class)
		out.append({
			"number": trainer_class,
			"name": names[trainer_class - 1],
			"palette": [rom.u16le(palette), rom.u16le(palette + Gen2Palette.COLOR_BYTES)],
		})

		if on_progress.is_valid():
			on_progress.call("trainers", trainer_class, count)

	return out


## The four colours a battle draws its bars in. Small enough to live in the
## manifest beside the atlas metadata rather than in a file of its own.
func _import_bar_palettes(rom: RomFile, layout: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for index: int in RomLayout.BAR_PALETTE_NAMES.size():
		var entry: int = RomLayout.bar_palette_offset(layout, index)
		out[RomLayout.BAR_PALETTE_NAMES[index]] = [
			rom.u16le(entry), rom.u16le(entry + Gen2Palette.COLOR_BYTES),
		]
	return out


## Decodes the fixed tile sheets: the font, the eight text box borders and the
## battle HUD's graphics, each as one strip of tiles.
##
## None of them is compressed and none is per-species, so unlike a pic there is
## nothing to look up: each is a fixed run of tiles at a known place. They are
## kept as strips because each is addressed by a number, whether a character code
## or a tile in a bar, and a strip turns that number into a horizontal offset and
## nothing else.
##
## [code]first_code[/code] is the character code a sheet's first tile draws, and
## is zero for the sheets that are graphics rather than characters. [code]bits[/code]
## is how the cartridge stores them: the font and the borders are 1bpp, the
## battle graphics 2bpp.
func _import_tiles(rom: RomFile, layout: Dictionary, on_progress: Callable) -> Dictionary:
	var data: PackedByteArray = rom.bytes()
	var sheets: Dictionary = {
		"font": {
			"offset": RomLayout.font_offset(layout),
			"tiles": RomLayout.FONT_TILES,
			"first_code": RomLayout.FONT_FIRST_CODE,
			"bits": 1,
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
	}

	var written: Dictionary = {}
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
	return Gen2Tiles.decode_2bpp_strip(data, int(sheet["offset"]), int(sheet["tiles"]))


func _import_pics(
	rom: RomFile, layout: Dictionary, species: Array, on_progress: Callable
) -> Dictionary:
	var front: Dictionary = _new_atlas(RomLayout.FRONTPIC_MAX_TILES, RomLayout.SPECIES_COUNT)
	var back: Dictionary = _new_atlas(RomLayout.BACKPIC_TILES, RomLayout.SPECIES_COUNT)
	var unown_front: Dictionary = _new_atlas(RomLayout.FRONTPIC_MAX_TILES, RomLayout.UNOWN_FORMS)
	var unown_back: Dictionary = _new_atlas(RomLayout.BACKPIC_TILES, RomLayout.UNOWN_FORMS)
	var trainer_classes: int = RomLayout.trainer_class_count(layout)
	var trainers: Dictionary = _new_atlas(RomLayout.TRAINER_PIC_TILES, trainer_classes)

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
		"trainers": trainers,
	}
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


func _decode_into(
	rom: RomFile,
	layout: Dictionary,
	pointer_offset: int,
	columns: int,
	rows: int,
	atlas: Dictionary,
	slot: int
) -> bool:
	if columns <= 0 or rows <= 0:
		return false

	var pointer: Dictionary = rom.far_pointer(pointer_offset)
	var bank: int = RomLayout.fix_pic_bank(layout, pointer["bank"])
	var start: int = RomFile.linear(bank, pointer["address"])
	if not rom.in_bounds(start):
		return false

	var raw: PackedByteArray = _lz.decompress(rom.bytes(), start)
	if _lz.failed or raw.size() < columns * rows * Gen2Tiles.TILE_BYTES:
		return false

	var pixels: PackedByteArray = Gen2Tiles.decode_pic(raw, columns, rows)
	var cell: int = atlas["cell"]
	Gen2Tiles.blit(
		pixels, columns * Gen2Tiles.TILE_WIDTH,
		atlas["pixels"], atlas["width"],
		(slot % ATLAS_COLUMNS) * cell, (slot / ATLAS_COLUMNS) * cell
	)
	atlas["decoded"] = int(atlas["decoded"]) + 1
	return true
