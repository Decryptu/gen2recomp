class_name GameData
extends RefCounted

## A decoded cartridge, read back out of the cache.
##
## The importer's counterpart, and the only way the engine sees cartridge
## content: nothing downstream of here opens a ROM, and nothing here knows what
## a ROM is. It is [RefCounted] and scene-free like the layer that wrote it, so
## a battle or a menu can be exercised in a test with no display.
##
## JSON has one number type, so every number in the cache comes back as a float
## and every comparison against an int quietly fails. Coercion happens here,
## once, rather than at each of the places that would otherwise have to remember.
##
## Index buffers are loaded on first use and kept. A pic atlas is a megabyte or
## so of indices; reading four of them to draw one sprite would be a waste, and
## re-reading one per frame would be worse.

var id: StringName = &""
var sha1: String = ""
var directory: String = ""

var _species: Array = []
var _moves: Array = []
var _items: Array = []
var _types: Array = []
var _atlases: Dictionary = {}
var _indices: Dictionary = {}


## Opens the cache for a registry game, or null if it has not been imported.
static func open(game_id: StringName) -> GameData:
	var hash: String = RomRegistry.sha1_for(game_id)
	if hash.is_empty():
		return null
	return open_directory(RomCache.directory_for(game_id, hash))


## Opens a cache directory, or null if it is missing, incomplete, or was written
## by an importer whose format this build does not read.
static func open_directory(path: String) -> GameData:
	if not RomCache.is_usable(path):
		return null

	var manifest: Dictionary = RomCache.read_manifest(path)
	var data := GameData.new()
	data.directory = path
	data.id = StringName(manifest.get("game_id", ""))
	data.sha1 = String(manifest.get("sha1", ""))
	data._atlases = manifest.get("atlases", {})
	data._species = data._read_array(RomCache.species_path(path))
	data._moves = data._read_array(RomCache.moves_path(path))
	data._items = data._read_array(RomCache.items_path(path))
	data._types = data._read_array(RomCache.types_path(path))
	return data


## The first registry game with a usable cache, or null if none has been
## imported. For development views that just want something to draw.
static func open_any() -> GameData:
	for game_id: StringName in RomRegistry.ORDER:
		var data: GameData = open(game_id)
		if data != null:
			return data
	return null


func title() -> String:
	return RomRegistry.title_for(id)


func species_count() -> int:
	return _species.size()


## One species by Pokédex number, or an empty Dictionary if there is no such
## number. Out of range is a question, not a crash: a mod may well ask.
func species(number: int) -> Dictionary:
	return _entry(_species, number - 1)


func move(number: int) -> Dictionary:
	return _entry(_moves, number - 1)


func item(number: int) -> Dictionary:
	return _entry(_items, number - 1)


func item_name(number: int) -> String:
	return String(item(number).get("name", ""))


## Type names are indexed from zero, unlike everything else here.
func type_name(number: int) -> String:
	return String(_entry(_types, number).get("name", ""))


## The four colours a species is drawn with, in index order. The cache stores
## the cartridge's own 15-bit pair; white and black are implied.
func palette(number: int, shiny: bool = false) -> PackedColorArray:
	var entry: Dictionary = species(number)
	if entry.is_empty():
		return Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))

	var stored: Array = entry["palette"]["shiny" if shiny else "normal"]
	return Gen2Palette.pic_palette(PackedColorArray([
		Gen2Palette.from_packed(int(stored[0])),
		Gen2Palette.from_packed(int(stored[1])),
	]))


## Atlas metadata: width, height, cell, columns, decoded.
func atlas(name: String) -> Dictionary:
	var value: Variant = _atlases.get(name, {})
	if not value is Dictionary:
		return {}

	var out: Dictionary = {}
	for key: String in value:
		out[key] = int(value[key])
	return out


## The index buffer for an atlas, read on first use and kept afterwards.
func atlas_indices(name: String) -> PackedByteArray:
	if _indices.has(name):
		return _indices[name]

	var indices: PackedByteArray = RomCache.read_indices(RomCache.pic_path(directory, name))
	_indices[name] = indices
	return indices


## Where a species sits in its atlas, and how much of that cell it fills.
##
## Cells are the size of the largest pic of their kind so a slot can be found by
## arithmetic; a smaller pic sits in the top-left of its cell and the rest is
## blank. Returns { atlas, slot, width, height } in pixels, or an empty
## Dictionary for a species that is not in the cache.
func species_pic(number: int, back: bool = false) -> Dictionary:
	var entry: Dictionary = species(number)
	if entry.is_empty():
		return {}

	# Unown's main-table slot holds form A. Its other 25 forms are in an atlas
	# of their own and are asked for by form, not by species.
	var name: String = "back" if back else "front"
	var cell: int = int(atlas(name).get("cell", 0))
	if back:
		return {"atlas": name, "slot": number - 1, "width": cell, "height": cell}

	var tiles: Array = entry["front_tiles"]
	return {
		"atlas": name,
		"slot": number - 1,
		"width": int(tiles[0]) * Gen2Tiles.TILE_WIDTH,
		"height": int(tiles[1]) * Gen2Tiles.TILE_HEIGHT,
	}


## One of Unown's 26 letter forms, which live outside the species tables.
func unown_pic(form: int, back: bool = false) -> Dictionary:
	if form < 0 or form >= RomLayout.UNOWN_FORMS:
		return {}

	var pic: Dictionary = species_pic(RomLayout.UNOWN_SPECIES, back)
	if pic.is_empty():
		return {}

	pic["atlas"] = "unown_back" if back else "unown_front"
	pic["slot"] = form
	return pic


func _read_array(path: String) -> Array:
	var value: Variant = RomCache.read_json(path)
	return value if value is Array else []


func _entry(rows: Array, index: int) -> Dictionary:
	if index < 0 or index >= rows.size():
		return {}
	return rows[index]
