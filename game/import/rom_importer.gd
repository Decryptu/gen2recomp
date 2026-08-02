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
## that can rot — a wrong constant produces plausible-looking garbage rather
## than an error, and garbage that reaches the cache is indistinguishable from
## real data later on. Checking a handful of values whose correct answers are
## known independently turns that class of mistake into an immediate failure.

## Atlas cells are the largest pic of their kind so a renderer can index them
## arithmetically; smaller pics sit in the top-left of their cell and record
## their real size.
const ATLAS_COLUMNS: int = 16

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
	# table self-checks in one pass — and a stride that is off by any amount
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
	# was one whole table too far along still decoded — into sprites that were
	# the correct shapes in the wrong colours, which nothing else would catch.
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

	return {"ok": true, "message": "Layout verified."}


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

	if not RomCache.write_json(RomCache.species_path(directory), species):
		result["message"] = "Could not write species data."
		return result

	var manifest: Dictionary = {
		"format_version": RomCache.FORMAT_VERSION,
		"game_id": String(rom.id),
		"sha1": rom.sha1,
		"species_count": species.size(),
		"atlases": pics,
		"complete": true,
	}
	if not RomCache.write_json(RomCache.manifest_path(directory), manifest):
		result["message"] = "Could not write manifest."
		return result

	result["ok"] = true
	result["species"] = species.size()
	result["elapsed_ms"] = Time.get_ticks_msec() - started
	result["message"] = "Imported %d species in %d ms." % [species.size(), result["elapsed_ms"]]
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


func _import_pics(
	rom: RomFile, layout: Dictionary, species: Array, on_progress: Callable
) -> Dictionary:
	var front: Dictionary = _new_atlas(RomLayout.FRONTPIC_MAX_TILES, RomLayout.SPECIES_COUNT)
	var back: Dictionary = _new_atlas(RomLayout.BACKPIC_TILES, RomLayout.SPECIES_COUNT)
	var unown_front: Dictionary = _new_atlas(RomLayout.FRONTPIC_MAX_TILES, RomLayout.UNOWN_FORMS)
	var unown_back: Dictionary = _new_atlas(RomLayout.BACKPIC_TILES, RomLayout.UNOWN_FORMS)

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

	var directory: String = RomCache.directory_for(rom.id, rom.sha1)
	var atlases: Dictionary = {
		"front": front, "back": back, "unown_front": unown_front, "unown_back": unown_back,
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
