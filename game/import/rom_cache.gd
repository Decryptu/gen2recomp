class_name RomCache
extends RefCounted

## Where decoded cartridge data lives between runs.
##
## Under [code]user://[/code], never inside the project: the cache is derived
## from a commercial cartridge, so it must not be committed and must not end up
## in an export. Keeping it here is the runtime half of the rule the .gitignore
## and the pre-commit hook enforce at build time.
##
## One directory per dump, named by game and hash, so two revisions of the same
## game never share a cache and a re-import cannot half-overwrite the last one.
##
## Pixel data is stored as raw colour indices rather than as images. It is what
## the renderer wants (palettes are applied per species and per shiny state at
## draw time), and it avoids a decode round-trip whose exactness would have to
## be trusted.

const ROOT: String = "user://rom_cache"
const MANIFEST: String = "manifest.json"
const SPECIES: String = "species.json"
const MOVES: String = "moves.json"
const ITEMS: String = "items.json"
const WORLD_TRADES: String = "world_trades.json"
const TYPES: String = "types.json"
const MATCHUPS: String = "matchups.json"
const TRAINERS: String = "trainers.json"
const PICS_DIR: String = "pics"
const TILES_DIR: String = "tiles"
const WORLD_MAPS: String = "world_maps.json"
const WORLD_SCRIPTS: String = "world_scripts.json"
const WORLD_STANDARD_SCRIPTS: String = "world_standard_scripts.json"
const WORLD_TEXT: String = "world_text.json"
const WORLD_MOVEMENTS: String = "world_movements.json"
const WORLD_TILESETS: String = "world_tilesets.json"
const WORLD_ENCOUNTERS: String = "world_encounters.json"
const WORLD_PALETTES: String = "world_palettes.json"
const WORLD_ANIMATION_ASSETS: String = "world_animation_assets.json"
const WORLD_TILES_DIR: String = "world_tiles"
const OVERWORLD_SPRITES: String = "overworld_sprites.json"
const OVERWORLD_SPRITE_PALETTES: String = "overworld_sprite_palettes.json"
const OVERWORLD_SPRITES_DIR: String = "overworld_sprites"
const WORLD_MENUS: String = "world_menus.json"
const WORLD_MARTS: String = "world_marts.json"
const WORLD_PHONE: String = "world_phone.json"
const WORLD_AUDIO: String = "world_audio.json"

## The key a payload span is stored under, and how many numbers it holds. A
## cartridge byte run written inline as JSON decimals costs about four bytes on
## disk and about twenty-six resident once parsed into an Array of Variants.
## Scripts, text and audio are almost entirely such runs, so they live in a
## binary blob beside the JSON and the JSON keeps only [offset, length].
const PAYLOAD_KEY: String = "payload"
const PAYLOAD_SPAN: int = 2
const BYTES_KEY: String = "bytes"

## Bumped whenever the on-disk shape changes. A cache written by an older
## importer is discarded rather than migrated.
const FORMAT_VERSION: int = 22


static func directory_for(id: StringName, sha1: String) -> String:
	return "%s/%s_%s" % [ROOT, id, sha1.substr(0, 8)]


static func manifest_path(directory: String) -> String:
	return "%s/%s" % [directory, MANIFEST]


static func species_path(directory: String) -> String:
	return "%s/%s" % [directory, SPECIES]


static func moves_path(directory: String) -> String:
	return "%s/%s" % [directory, MOVES]


static func items_path(directory: String) -> String:
	return "%s/%s" % [directory, ITEMS]


static func world_trades_path(directory: String) -> String:
	return "%s/%s" % [directory, WORLD_TRADES]


static func types_path(directory: String) -> String:
	return "%s/%s" % [directory, TYPES]


## The type matchup chart, kept apart from the type names because the two are
## different questions: a name is asked for by type number, and a matchup by a
## pair of them.
static func matchups_path(directory: String) -> String:
	return "%s/%s" % [directory, MATCHUPS]


static func trainers_path(directory: String) -> String:
	return "%s/%s" % [directory, TRAINERS]


static func world_maps_path(directory: String) -> String:
	return "%s/%s" % [directory, WORLD_MAPS]


## The binary blob beside a section's JSON, holding the cartridge byte runs that
## the JSON refers to by span.
static func blob_path(json_path: String) -> String:
	return "%s.bin" % json_path.get_basename()


static func world_scripts_path(directory: String) -> String:
	return "%s/%s" % [directory, WORLD_SCRIPTS]


static func world_standard_scripts_path(directory: String) -> String:
	return "%s/%s" % [directory, WORLD_STANDARD_SCRIPTS]


static func world_text_path(directory: String) -> String:
	return "%s/%s" % [directory, WORLD_TEXT]


static func world_movements_path(directory: String) -> String:
	return "%s/%s" % [directory, WORLD_MOVEMENTS]


static func world_tilesets_path(directory: String) -> String:
	return "%s/%s" % [directory, WORLD_TILESETS]


static func world_encounters_path(directory: String) -> String:
	return "%s/%s" % [directory, WORLD_ENCOUNTERS]


static func world_palettes_path(directory: String) -> String:
	return "%s/%s" % [directory, WORLD_PALETTES]


static func world_animation_assets_path(directory: String) -> String:
	return "%s/%s" % [directory, WORLD_ANIMATION_ASSETS]


static func overworld_sprites_path(directory: String) -> String:
	return "%s/%s" % [directory, OVERWORLD_SPRITES]


static func overworld_sprite_palettes_path(directory: String) -> String:
	return "%s/%s" % [directory, OVERWORLD_SPRITE_PALETTES]


static func world_menus_path(directory: String) -> String:
	return "%s/%s" % [directory, WORLD_MENUS]


static func world_marts_path(directory: String) -> String:
	return "%s/%s" % [directory, WORLD_MARTS]


static func world_phone_path(directory: String) -> String:
	return "%s/%s" % [directory, WORLD_PHONE]


static func world_audio_path(directory: String) -> String:
	return "%s/%s" % [directory, WORLD_AUDIO]


static func pic_path(directory: String, name: String) -> String:
	return "%s/%s/%s.idx" % [directory, PICS_DIR, name]


## Fixed tile sheets: the font, the text box borders and the battle HUD's
## graphics. Kept apart from the pics because they are addressed by a tile number
## rather than by species, and because a sheet has no palette of its own, so the
## two never want the same accessor.
static func tile_path(directory: String, name: String) -> String:
	return "%s/%s/%s.idx" % [directory, TILES_DIR, name]


static func world_tile_path(directory: String, number: int) -> String:
	return "%s/%s/%02d.idx" % [directory, WORLD_TILES_DIR, number]


static func overworld_sprite_path(directory: String, number: int) -> String:
	return "%s/%s/%03d.idx" % [directory, OVERWORLD_SPRITES_DIR, number]


static func prepare(directory: String) -> bool:
	for sub: String in [PICS_DIR, TILES_DIR, WORLD_TILES_DIR, OVERWORLD_SPRITES_DIR]:
		if DirAccess.make_dir_recursive_absolute("%s/%s" % [directory, sub]) != OK:
			return false
	return true


## True when [param directory] holds a complete cache this build can read.
static func is_usable(directory: String) -> bool:
	var manifest: Dictionary = read_manifest(directory)
	if manifest.is_empty():
		return false
	return int(manifest.get("format_version", -1)) == FORMAT_VERSION \
		and bool(manifest.get("complete", false))


static func read_manifest(directory: String) -> Dictionary:
	var value: Variant = read_json(manifest_path(directory))
	return value if value is Dictionary else {}


static func write_json(path: String, value: Variant) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t"))
	file.close()
	return true


static func read_json(path: String) -> Variant:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text: String = file.get_as_text()
	file.close()
	return JSON.parse_string(text)


## One cached grid of cartridge bytes, packed on the way out of JSON.
##
## A JSON number comes back as a float and an Array of them costs about
## twenty-six bytes resident per cartridge byte. The map block, map collision and
## tileset lookup tables are all byte grids that are read once per drawn tile and
## are resident for every map at once, so they are unboxed here rather than at
## each lookup. A value that is not an array answers empty, which the record's
## own bounds checks then report as absent.
static func packed_bytes(value: Variant) -> PackedByteArray:
	if value is PackedByteArray:
		return value
	var out := PackedByteArray()
	if not value is Array:
		return out
	var rows: Array = value as Array
	out.resize(rows.size())
	for index: int in rows.size():
		out[index] = int(rows[index]) & 0xFF
	return out


## Writes a pointer map of raw cartridge byte runs: scripts, text and movements,
## all of which are [code]{ "bank:address": [bytes] }[/code]. Every value is a
## run, so each becomes a [constant PAYLOAD_KEY] span into the blob.
static func write_payload_map(
	json_path: String, payload_blob_path: String, entries: Dictionary
) -> bool:
	var blob := PackedByteArray()
	var stripped: Dictionary = {}
	for key: Variant in entries:
		var value: Variant = entries[key]
		stripped[key] = {PAYLOAD_KEY: _append_payload(value, blob)} if value is Array \
			else value
	if not write_json(json_path, stripped):
		return false
	return write_indices(payload_blob_path, blob)


## Writes a section whose byte runs are named fields rather than whole values,
## as the audio records and the standard-script table are.
##
## Only a [code]bytes[/code] field holding an array is moved. Nothing else is
## touched: plenty of cached arrays are small numbers without being cartridge
## payloads, and a mart list or an encounter rate must stay an array.
static func write_section(json_path: String, payload_blob_path: String, value: Variant) -> bool:
	var blob := PackedByteArray()
	var stripped: Variant = _extract_payloads(value, blob)
	if not write_json(json_path, stripped):
		return false
	return write_indices(payload_blob_path, blob)


## The binary blob for a section, or empty when the section has none. Held as a
## [PackedByteArray], which costs one byte per cartridge byte.
static func read_blob(path: String) -> PackedByteArray:
	return read_indices(path)


## Replaces each [code]bytes[/code] array with a span into [param blob], walking
## lists and records to reach the ones nested inside them.
static func _extract_payloads(value: Variant, blob: PackedByteArray) -> Variant:
	if value is Array:
		var out: Array = []
		for entry: Variant in value as Array:
			out.append(_extract_payloads(entry, blob))
		return out
	if value is Dictionary:
		var out_dictionary: Dictionary = {}
		for key: Variant in value as Dictionary:
			var entry: Variant = (value as Dictionary)[key]
			if String(key) == BYTES_KEY and entry is Array:
				out_dictionary[PAYLOAD_KEY] = _append_payload(entry as Array, blob)
				continue
			out_dictionary[key] = _extract_payloads(entry, blob)
		return out_dictionary
	return value


static func _append_payload(run: Array, blob: PackedByteArray) -> Array:
	var at: int = blob.size()
	blob.resize(at + run.size())
	for index: int in run.size():
		blob[at + index] = int(run[index]) & 0xFF
	return [at, run.size()]


## Index buffers are mostly runs of the same value, so they compress hard,
## roughly ten to one for a pic atlas.
static func write_indices(path: String, data: PackedByteArray) -> bool:
	var file: FileAccess = FileAccess.open_compressed(
		path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD
	)
	if file == null:
		return false
	file.store_buffer(data)
	file.close()
	return true


static func read_indices(path: String) -> PackedByteArray:
	var file: FileAccess = FileAccess.open_compressed(
		path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD
	)
	if file == null:
		return PackedByteArray()
	var data: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	return data


## Deletes a cache directory and everything below it.
static func clear(directory: String) -> void:
	var dir: DirAccess = DirAccess.open(directory)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var full: String = "%s/%s" % [directory, name]
		if dir.current_is_dir():
			clear(full)
		else:
			DirAccess.remove_absolute(full)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(directory)
