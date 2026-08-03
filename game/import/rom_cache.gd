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
const TYPES: String = "types.json"
const MATCHUPS: String = "matchups.json"
const TRAINERS: String = "trainers.json"
const PICS_DIR: String = "pics"
const TILES_DIR: String = "tiles"

## Bumped whenever the on-disk shape changes. A cache written by an older
## importer is discarded rather than migrated.
const FORMAT_VERSION: int = 7


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


static func types_path(directory: String) -> String:
	return "%s/%s" % [directory, TYPES]


## The type matchup chart, kept apart from the type names because the two are
## different questions: a name is asked for by type number, and a matchup by a
## pair of them.
static func matchups_path(directory: String) -> String:
	return "%s/%s" % [directory, MATCHUPS]


static func trainers_path(directory: String) -> String:
	return "%s/%s" % [directory, TRAINERS]


static func pic_path(directory: String, name: String) -> String:
	return "%s/%s/%s.idx" % [directory, PICS_DIR, name]


## Fixed tile sheets: the font, the text box borders and the battle HUD's
## graphics. Kept apart from the pics because they are addressed by a tile number
## rather than by species, and because a sheet has no palette of its own, so the
## two never want the same accessor.
static func tile_path(directory: String, name: String) -> String:
	return "%s/%s/%s.idx" % [directory, TILES_DIR, name]


static func prepare(directory: String) -> bool:
	for sub: String in [PICS_DIR, TILES_DIR]:
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
