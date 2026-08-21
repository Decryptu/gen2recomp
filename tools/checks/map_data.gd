extends RefCounted

var _r: RefCounted = null

## The imported map corpus against the pins' own copies of the same bytes.
##
##   Godot --headless --path . -s res://tools/validate.gd -- map_data
##
## pret assembles to a bit-identical ROM, so `maps/*.blk`,
## `data/tilesets/*_metatiles.bin`, `data/tilesets/*_collision.asm` and
## `gfx/tilesets/*_palette_map.asm` are the cartridge's own bytes read a second
## way. Agreement proves the importer's addressing, stride and fold, which is
## where an offset or a stride read one row out hides; it proves nothing about
## what the bytes mean. `drawn_blocks` and `side_walls` are the semantic half.
##
## Gold and Silver both run against `pokegold`, and every identity here comes
## from the pin's own tables rather than from a number: a map is found by
## walking `constants/map_constants.asm` in order, and a tileset's files by
## following `TilesetXMeta` through `gfx/tilesets.asm`, because `Tileset0` and
## `TilesetJohto` are the same record under two labels.
##
## The checkouts are local-only, so a missing one skips rather than fails.

const PINS: Dictionary = {
	&"gold": "pokegold", &"silver": "pokegold", &"crystal": "pokecrystal",
}

## `constants/tileset_constants.asm`'s `PAL_BG_*` order.
const BG_PALETTES: Array[String] = [
	"GRAY", "RED", "GREEN", "WATER", "YELLOW", "BROWN", "ROOF", "TEXT",
]

## `constants/hardware.inc`: `OAM_BANK1 equ 1 << B_OAM_BANK1`.
const OAM_BANK1: int = 1 << 3

var _pins: Dictionary = {}
var _root: String = ""
var _failures: int = 0


func run(r: RefCounted) -> void:
	_r = r
	_root = _reference_root()
	_r.each_game(_check_game)
	if _failures > 0:
		_r.fail("%d layers disagreed with the pinned sources." % _failures)


func _check_game() -> void:
	var pin: String = _root.path_join(String(PINS[_r.game_id]))
	if not DirAccess.dir_exists_absolute(pin):
		_r.note("%s is not checked out, so nothing was compared." % pin.get_file())
		return
	_check_blocks(pin)
	_check_tilesets(pin)


# --- Map block arrays -------------------------------------------------------


func _check_blocks(pin: String) -> void:
	var attributes: Dictionary = _attributes(pin)
	var blockdata: Dictionary = _blockdata(pin)
	var compared: int = 0
	var highest: int = -1
	for entry: Dictionary in _map_ids(pin):
		var id: String = entry["id"]
		var map: Gen2WorldMap = _r.data.world_map(entry["group"], entry["number"])
		if map == null:
			_report("map %d/%d (%s) is not in the cache." % [entry["group"], entry["number"], id])
			continue
		if map.width_blocks != entry["width"] or map.height_blocks != entry["height"]:
			_report("%s is %dx%d blocks, the pin says %dx%d." % [
				id, map.width_blocks, map.height_blocks, entry["width"], entry["height"]
			])
			continue
		var attribute: Dictionary = attributes.get(id, {})
		if attribute.is_empty():
			_report("%s has no `map_attributes` row in the pin." % id)
			continue
		if map.border_block != attribute["border"]:
			_report("%s border block is $%02X, the pin says $%02X." % [
				id, map.border_block, attribute["border"]
			])
		var relative: String = blockdata.get("%s_Blocks" % attribute["label"], "")
		var pinned: PackedByteArray = _bytes(pin.path_join(relative))
		if pinned.is_empty():
			# Every map on both pins has a `.blk` of its own, so a map that
			# reaches none is a broken identity rather than shared blockdata.
			_report("%s reaches no blockdata file in the pin." % id)
			continue
		compared += 1
		_compare(
			"%s blocks" % id, map.blocks, pinned,
			map.width_blocks * map.height_blocks
		)
		highest = maxi(highest, _check_block_reach(id, map))
	_r.note("blocks: %d maps compared against their own `.blk`, highest block named %d" % [
		compared, highest
	])
	if compared == 0:
		_report("no map's blocks were compared, so the layer proved nothing.")


## The highest block [param map] names, and a failure when that is past its
## tileset's own table. A metatile run's length is only the distance to the next
## label, so `RomLayout.tileset_block_counts` is the one number here the pins
## state nowhere: this is what says the imported length covers the corpus, and
## `TilesetForest`'s 40 is why it is checked rather than assumed.
func _check_block_reach(id: String, map: Gen2WorldMap) -> int:
	var tileset: Gen2WorldTileset = _r.data.world_tileset(map.tileset)
	if tileset == null:
		_report("%s runs on tileset %d, which is not in the cache." % [id, map.tileset])
		return -1
	var highest: int = -1
	for block: int in map.blocks:
		highest = maxi(highest, block)
	if highest >= tileset.block_count:
		_report("%s names block %d of tileset %d, which holds %d." % [
			id, highest, map.tileset, tileset.block_count
		])
	return highest


# --- Metatiles, collision and palette maps ----------------------------------


func _check_tilesets(pin: String) -> void:
	var collisions: Dictionary = _collision_values(pin)
	var paths: Dictionary = _label_paths(pin, "gfx/tilesets.asm")
	paths.merge(_label_paths(pin, "gfx/tileset_palette_maps.asm"))
	var names: PackedStringArray = _tileset_labels(pin)
	if names.is_empty():
		_report("no tileset rows were read from the pin's `Tilesets::`.")
		return
	var compared: int = 0
	var overread: int = 0
	for number: int in names.size():
		var tileset: Gen2WorldTileset = _r.data.world_tileset(number)
		if tileset == null:
			# Crystal's table is longer than Gold's; a number the cache does not
			# carry is one the importer skipped, and the count line below says so.
			continue
		var label: String = names[number]
		compared += 1
		var meta: PackedByteArray = _bytes(pin.path_join(paths.get("%sMeta" % label, "")))
		if meta.is_empty():
			_report("tileset %d (%s) has no metatile file in the pin." % [number, label])
		else:
			_compare("tileset %d meta" % number, tileset.meta, meta, tileset.meta.size())
		var collision: PackedByteArray = _collision_bytes(
			pin.path_join(paths.get("%sColl" % label, "")), collisions
		)
		if collision.is_empty():
			_report("tileset %d (%s) has no collision file in the pin." % [number, label])
		else:
			_compare(
				"tileset %d collision" % number, tileset.collision, collision,
				tileset.collision.size()
			)
		# `_LoadOverworldAttrmapPals` indexes `wTilesetPalettes` with the raw tile
		# number and nothing bounds the read, so a palette map is only as long as
		# the distance to the next one: Crystal's is 112 bytes, the two graphics
		# blocks with the sixteen `$ff` the unusable $60..$7F range costs between
		# them, and Gold and Silver's is 48, the first block alone. The importer
		# reads RomLayout.WORLD_PALETTE_MAP_BYTES for both, which is the overread
		# the cartridge performs, so the pin's length is the comparable span and
		# `_check_palette_reach` is what says the rest is reachable.
		var palettes: PackedByteArray = _palette_map_bytes(
			pin.path_join(paths.get("%sPalMap" % label, ""))
		)
		if palettes.is_empty():
			_report("tileset %d (%s) has no palette map in the pin." % [number, label])
		else:
			_compare(
				"tileset %d palette map" % number, tileset.palette_map, palettes,
				palettes.size()
			)
			overread += tileset.palette_map.size() - palettes.size()
		_check_palette_reach(number, tileset)
	_r.note("tilesets: %d of the pin's %d compared over three layers, %d palette bytes read past the pinned record" % [
		compared, names.size(), overread
	])
	if compared == 0:
		_report("no tileset was compared, so three layers proved nothing.")


## Every tile a live block names has to fall inside the imported palette map,
## because a tile past it draws with palette 0 here and with the next record's
## byte on the cartridge. The pinned records stop short of the tile numbers the
## metatiles reach, so this is the half of the palette layer the pin cannot
## answer and the importer's own read length has to.
func _check_palette_reach(number: int, tileset: Gen2WorldTileset) -> void:
	var highest: int = -1
	for block: int in tileset.block_count:
		for tile: int in RomLayout.MAP_BLOCK_TILE_WIDTH * RomLayout.MAP_BLOCK_TILE_WIDTH:
			var at: int = block * RomLayout.TILESET_META_BYTES_PER_BLOCK + tile
			var index: int = tileset.meta[at] if at < tileset.meta.size() else 0
			if index < tileset.tile_count:
				highest = maxi(highest, index)
	if highest >= 0 and (highest >> 1) >= tileset.palette_map.size():
		_report("tileset %d names tile %d, past its %d-byte palette map." % [
			number, highest, tileset.palette_map.size()
		])


# --- Comparison -------------------------------------------------------------


## Reports the first differing byte of [param ours] against [param pinned] over
## [param length] bytes, and a length disagreement as its own failure.
func _compare(
	subject: String, ours: PackedByteArray, pinned: PackedByteArray, length: int
) -> void:
	if ours.size() < length or pinned.size() < length:
		_report("%s: %d bytes here and %d in the pin, %d expected." % [
			subject, ours.size(), pinned.size(), length
		])
		return
	for at: int in length:
		if ours[at] == pinned[at]:
			continue
		_report("%s: byte %d is $%02X, the pin says $%02X." % [
			subject, at, ours[at], pinned[at]
		])
		return


func _report(message: String) -> void:
	_failures += 1
	printerr("%-8s %s" % [_r.game_id, message])


# --- The pinned sources -----------------------------------------------------


## `constants/map_constants.asm` in order: `newgroup` opens a group and each
## `map_const` is the next map in it, so this is the same walk that gives
## `MapGroupPointers` its indices.
func _map_ids(pin: String) -> Array:
	return _parsed(pin, &"map_ids", func() -> Array:
		var out: Array = []
		var group: int = 0
		var number: int = 0
		for line: String in _lines(pin.path_join("constants/map_constants.asm")):
			if line.begins_with("newgroup"):
				group += 1
				number = 0
			elif line.begins_with("map_const"):
				number += 1
				var fields: PackedStringArray = _fields(line)
				if fields.size() < 3:
					continue
				out.append({
					"group": group, "number": number, "id": fields[0],
					"width": int(fields[1]), "height": int(fields[2]),
				})
		return out
	)


## `map_attributes Label, MAP_ID, $border`.
func _attributes(pin: String) -> Dictionary:
	return _parsed(pin, &"attributes", func() -> Dictionary:
		var out: Dictionary = {}
		for line: String in _lines(pin.path_join("data/maps/attributes.asm")):
			if not line.begins_with("map_attributes"):
				continue
			var fields: PackedStringArray = _fields(line)
			if fields.size() < 3:
				continue
			out[fields[1]] = {"label": fields[0], "border": _number(fields[2])}
		return out
	)


## `<Label>_Blocks:` to the `.blk` it includes. Several labels can stand over
## one `INCBIN`, which is how two maps share blockdata.
func _blockdata(pin: String) -> Dictionary:
	return _parsed(pin, &"blockdata", func() -> Dictionary:
		return _includes(pin.path_join("data/maps/blocks.asm"))
	)


## The `Tilesets::` table in order, so the row index is the `TILESET_*` value.
func _tileset_labels(pin: String) -> PackedStringArray:
	return _parsed(pin, &"tilesets", func() -> PackedStringArray:
		var out: PackedStringArray = []
		var open: bool = false
		for line: String in _lines(pin.path_join("data/tilesets.asm")):
			if line.begins_with("Tilesets:"):
				open = true
			elif open and line.begins_with("tileset "):
				out.append(line.substr("tileset ".length()).strip_edges())
		return out
	)


func _label_paths(pin: String, relative: String) -> Dictionary:
	return _parsed(pin, StringName(relative), func() -> Dictionary:
		return _includes(pin.path_join(relative))
	)


## `DEF COLL_WALL EQU $07`.
func _collision_values(pin: String) -> Dictionary:
	return _parsed(pin, &"collision_values", func() -> Dictionary:
		var out: Dictionary = {}
		for line: String in _lines(pin.path_join("constants/collision_constants.asm")):
			if not line.begins_with("DEF COLL_"):
				continue
			var parts: PackedStringArray = line.split(" ", false)
			if parts.size() < 4 or parts[2] != "EQU":
				continue
			out[parts[1].substr("COLL_".length())] = _number(parts[3])
		return out
	)


## `tilecoll A, B, C, D` is four permission bytes, one per 2x2 cell.
func _collision_bytes(path: String, values: Dictionary) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	for line: String in _lines(path):
		if not line.begins_with("tilecoll"):
			continue
		for field: String in _fields(line):
			out.append(int(values.get(field, -1)) & 0xFF)
	return out


## `tilepal <bank>, <pal>...` packs two assignments per byte, the first in the
## low nibble: the macro's own `dn (x | PAL_BG_\3), (x | PAL_BG_\2)`. The
## `rept 16 / db $ff` between the two banks is the gap tiles $60..$7F leave and
## is part of the record, so it is assembled here rather than skipped.
func _palette_map_bytes(path: String) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	var repeat: int = 1
	var block: PackedByteArray = PackedByteArray()
	for line: String in _lines(path):
		if line.begins_with("rept "):
			repeat = int(line.substr("rept ".length()))
			block = PackedByteArray()
		elif line.begins_with("endr"):
			for _pass: int in repeat:
				out.append_array(block)
			repeat = 1
			block = PackedByteArray()
		elif line.begins_with("db "):
			block.append(_number(line.substr("db ".length()).strip_edges()) & 0xFF)
		elif line.begins_with("tilepal"):
			var fields: PackedStringArray = _fields(line)
			var bank: int = OAM_BANK1 if int(fields[0]) == 1 else 0
			var at: int = 1
			while at + 1 < fields.size():
				out.append(
					((bank | BG_PALETTES.find(fields[at + 1])) << 4)
					| (bank | BG_PALETTES.find(fields[at]))
				)
				at += 2
	return out


## Every `<Label>:` standing over an `INCBIN`/`INCLUDE`, mapped to its path. A
## `SECTION` ends a run of labels that reached no include.
func _includes(path: String) -> Dictionary:
	var out: Dictionary = {}
	var pending: PackedStringArray = []
	for line: String in _lines(path):
		if line.begins_with("SECTION"):
			pending.clear()
		elif line.begins_with("INCBIN") or line.begins_with("INCLUDE"):
			var quoted: PackedStringArray = line.split("\"")
			if quoted.size() >= 2:
				for label: String in pending:
					out[label] = quoted[1]
			pending.clear()
		elif line.ends_with(":") or line.ends_with("::"):
			pending.append(line.trim_suffix(":").trim_suffix(":"))
	return out


# --- Files ------------------------------------------------------------------


## One pin's parse of [param key], computed once per run. Every table here is
## read for all three cartridges and two of them share a checkout.
func _parsed(pin: String, key: StringName, body: Callable) -> Variant:
	var cache: Dictionary = _pins.get_or_add(pin, {})
	if not cache.has(key):
		cache[key] = body.call()
	return cache[key]


## A source file with its comments and indentation gone, so a caller matches on
## the directive alone.
func _lines(path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return out
	while not file.eof_reached():
		var line: String = file.get_line()
		var comment: int = line.find(";")
		if comment >= 0:
			line = line.substr(0, comment)
		line = line.strip_edges()
		if line != "":
			out.append(line)
	return out


func _bytes(path: String) -> PackedByteArray:
	if path == "" or not FileAccess.file_exists(path):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(path)


## The operands of a one-directive line, trimmed.
func _fields(line: String) -> PackedStringArray:
	var space: int = line.find(" ")
	var out: PackedStringArray = []
	if space < 0:
		return out
	for field: String in line.substr(space).split(","):
		out.append(field.strip_edges())
	return out


func _number(text: String) -> int:
	return text.substr(1).hex_to_int() if text.begins_with("$") else int(text)


## `.references/` by default, the same root `tools/fetch_reference_sources.sh`
## and `docs/REFERENCES.md` use.
func _reference_root() -> String:
	var override: String = OS.get_environment("GEN2_REFERENCE_ROOT")
	if override != "":
		return override
	return ProjectSettings.globalize_path("res://").path_join(".references")
