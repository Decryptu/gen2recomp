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
var _trainers: Array = []
## The matchup chart, folded into a lookup on load: attacker * TYPE_COUNT +
## defender to the multiplier in tenths. The chart is 110 rows of exceptions, so
## a linear search would be a hundred comparisons per hit, twice a turn.
var _matchups: Dictionary = {}
var _foresight_matchups: Dictionary = {}
var _atlases: Dictionary = {}
var _tiles: Dictionary = {}
var _bar_palettes: Dictionary = {}
var _indices: Dictionary = {}
var _world_maps: Array = []
var _world_scripts: Dictionary = {}
var _world_standard_scripts: Dictionary = {}
var _world_text: Dictionary = {}
var _world_movements: Dictionary = {}
var _world_tilesets: Dictionary = {}
var _world_encounters: Dictionary = {}
var _world_palettes: Array = []
var _world_animation_assets: Dictionary = {}
var _overworld_sprites: Array = []
var _overworld_sprite_palettes: Array = []


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
	data._tiles = manifest.get("tiles", {})
	data._bar_palettes = manifest.get("bar_palettes", {})
	data._species = data._read_array(RomCache.species_path(path))
	data._moves = data._read_array(RomCache.moves_path(path))
	data._items = data._read_array(RomCache.items_path(path))
	data._types = data._read_array(RomCache.types_path(path))
	data._trainers = data._read_array(RomCache.trainers_path(path))
	data._build_matchups(data._read_array(RomCache.matchups_path(path)))
	data._load_world(path)
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


func map_count() -> int:
	return _world_maps.size()


## One map by its stable cartridge group and number, or null when it is absent.
func world_map(group: int, number: int) -> Gen2WorldMap:
	for value: Gen2WorldMap in _world_maps:
		if value.group == group and value.number == number:
			return value
	return null


func world_maps() -> Array:
	return _world_maps.duplicate()


## Raw bounded script bytes indexed by the cartridge's bank and CPU address.
## Runtime never opens a ROM; these bytes come from the user cache only.
func world_script(bank: int, address: int) -> PackedByteArray:
	return _cached_bytes(_world_scripts.get(Gen2WorldScript.pointer_key(bank, address), []))


## One standard-script entry by its source table index. The pointer is retained
## for diagnostics, while the bounded bytes keep the runtime independent of ROMs.
func world_standard_script(index: int) -> Dictionary:
	var value: Variant = _world_standard_scripts.get(str(index), {})
	if not value is Dictionary:
		return {}
	var entry: Dictionary = (value as Dictionary).duplicate(true)
	entry["bank"] = int(entry.get("bank", -1))
	entry["address"] = int(entry.get("address", -1))
	entry["data"] = _cached_bytes(entry.get("bytes", []))
	return entry


## Raw bounded text bytes indexed by the cartridge's bank and CPU address.
func world_text(bank: int, address: int) -> PackedByteArray:
	return _cached_bytes(_world_text.get(Gen2WorldScript.pointer_key(bank, address), []))


## Raw bounded movement bytes indexed by the script bank and movement pointer.
func world_movement(bank: int, address: int) -> PackedByteArray:
	return _cached_bytes(_world_movements.get(Gen2WorldScript.pointer_key(bank, address), []))


## One decoded tileset's metatile and collision tables, or null if absent.
func world_tileset(number: int) -> Gen2WorldTileset:
	return _world_tilesets.get(number, null)


func world_tileset_count() -> int:
	return _world_tilesets.size()


## One normal encounter record by method and map group/number. The runtime
## names the water method "surf" while the cache keeps the cartridge table's
## "water" name.
func world_encounter(method: StringName, group: int, number: int) -> Dictionary:
	var table_name: String = "water" if method == &"surf" else String(method)
	var table: Variant = _world_encounters.get(table_name, {})
	if not table is Dictionary:
		return {}
	var value: Variant = (table as Dictionary).get("%d:%d" % [group, number], {})
	return value.duplicate(true) if value is Dictionary else {}


## One imported fishing group, indexed by the source map-header value. Group
## zero is the cartridge's no-fishing sentinel.
func world_fishing_group(group: int) -> Dictionary:
	if group < 1:
		return {}
	var fishing: Variant = _world_encounters.get("fishing", {})
	if not fishing is Dictionary:
		return {}
	var groups: Variant = (fishing as Dictionary).get("groups", [])
	if not groups is Array or group > (groups as Array).size():
		return {}
	var value: Variant = (groups as Array)[group - 1]
	return value.duplicate(true) if value is Dictionary else {}


## The twenty-two day/night fishing substitutions used by entries whose
## species byte is zero in the cartridge stream.
func world_fishing_time_groups() -> Array:
	var fishing: Variant = _world_encounters.get("fishing", {})
	if not fishing is Dictionary:
		return []
	var groups: Variant = (fishing as Dictionary).get("time_groups", [])
	return groups.duplicate(true) if groups is Array else []


func world_roaming_maps() -> Array:
	var roaming: Variant = _world_encounters.get("roaming", {})
	if not roaming is Dictionary:
		return []
	var maps: Variant = (roaming as Dictionary).get("maps", [])
	return maps.duplicate(true) if maps is Array else []


func world_roaming_mons() -> Array:
	var roaming: Variant = _world_encounters.get("roaming", {})
	if not roaming is Dictionary:
		return []
	var mons: Variant = (roaming as Dictionary).get("mons", [])
	return mons.duplicate(true) if mons is Array else []


func world_encounter_count(method: StringName) -> int:
	var table_name: String = "water" if method == &"surf" else String(method)
	var table: Variant = _world_encounters.get(table_name, {})
	return (table as Dictionary).size() if table is Dictionary else 0


## Metadata for one cartridge overworld sprite, indexed by the source sprite
## number. Sprite number zero is reserved for no sprite by the cartridge.
func overworld_sprite(number: int) -> Gen2WorldSprite:
	var row: Dictionary = _entry(_overworld_sprites, number - 1)
	return Gen2WorldSprite.from_cache(row) if not row.is_empty() else null


func overworld_sprite_count() -> int:
	return _overworld_sprites.size()


## Indexed pixels for one raw overworld sprite tile strip, loaded on demand.
func overworld_sprite_indices(number: int) -> PackedByteArray:
	var key: String = "overworld_sprites/%d" % number
	if _indices.has(key):
		return _indices[key]
	var data: PackedByteArray = RomCache.read_indices(
		RomCache.overworld_sprite_path(directory, number)
	)
	_indices[key] = data
	return data


## One of the eight overworld object palette kinds for a time-of-day group.
## The source's palette override bit selects the same eight rows while marking
## that the object event, rather than the sprite table, supplied the choice.
func overworld_sprite_palette(palette: int, time_of_day: int) -> PackedColorArray:
	var group: int = clampi(time_of_day, 0, 3) * RomLayout.OVERWORLD_SPRITE_PALETTE_COUNT \
		+ (palette & (RomLayout.OVERWORLD_SPRITE_PALETTE_COUNT - 1))
	if group < 0 or group >= _overworld_sprite_palettes.size():
		return PackedColorArray()
	var raw: Variant = _overworld_sprite_palettes[group]
	if not raw is Array:
		return PackedColorArray()
	var out := PackedColorArray()
	for packed: Variant in raw as Array:
		out.append(Gen2Palette.from_packed(int(packed)))
	return out


## One of the cartridge's four-colour background palette groups.
func world_palette(number: int) -> PackedColorArray:
	if number < 0 or number >= _world_palettes.size():
		return PackedColorArray()
	var raw: Variant = _world_palettes[number]
	if not raw is Array:
		return PackedColorArray()
	var out := PackedColorArray()
	for packed: Variant in raw as Array:
		out.append(Gen2Palette.from_packed(int(packed)))
	return out


## Raw 2bpp frames embedded in the cartridge's animation routines.
func world_animation_asset(name: String) -> PackedByteArray:
	var raw: Variant = _world_animation_assets.get(name, [])
	if not raw is Array:
		return PackedByteArray()
	var out := PackedByteArray()
	out.resize((raw as Array).size())
	for index: int in out.size():
		out[index] = int((raw as Array)[index])
	return out


## Indexed 2bpp pixels for one tileset's 96 overworld tiles, loaded on demand.
func world_tileset_indices(number: int) -> PackedByteArray:
	var key: String = "world_tiles/%d" % number
	if _indices.has(key):
		return _indices[key]
	var data: PackedByteArray = RomCache.read_indices(RomCache.world_tile_path(directory, number))
	_indices[key] = data
	return data


## One species by Pokédex number, or an empty Dictionary if there is no such
## number. Out of range is a question, not a crash: a mod may well ask.
func species(number: int) -> Dictionary:
	return _entry(_species, number - 1)


## A species' level-up moves, in the cartridge's own order, as
## { level, move } with both coerced back to int.
##
## The order is not sorted and must not be: it decides which four moves a fresh
## Pokémon ends up with, and one species' list genuinely is out of order. See
## [Gen2Learnset], which is what turns this into an answer.
func learnset(number: int) -> Array:
	return _rows(species(number), "learnset", ["level", "move"])


## How a species evolves, as { method, parameter, condition, target }. Empty for
## the ones that do not.
##
## [code]method[/code] is one of the [code]RomLayout.EVOLVE_*[/code] constants and
## decides what [code]parameter[/code] means: a level, an item, a held item or a
## time of day. [code]condition[/code] is only ever set by
## [constant RomLayout.EVOLVE_STAT].
func evolutions(number: int) -> Array:
	return _rows(species(number), "evolutions", ["method", "parameter", "condition", "target"])


## The moves a Pokémon of this species is created knowing at [param level].
func moves_at_level(number: int, level: int) -> Array:
	return Gen2Learnset.moves_at_level(learnset(number), level)


## The moves a Pokémon of this species is offered on reaching exactly
## [param level] by levelling up, which is not [method moves_at_level]'s
## question asked again: see [Gen2Learnset] for why Muk's own list answers the
## two differently.
func moves_learned_at(number: int, level: int) -> Array:
	return Gen2Learnset.moves_learned_at(learnset(number), level)


## One of the per-species lists, with every named field coerced out of JSON's
## single number type.
func _rows(entry: Dictionary, key: String, fields: Array) -> Array:
	var value: Variant = entry.get(key, [])
	if not value is Array:
		return []

	var out: Array = []
	for row: Dictionary in value as Array:
		var coerced: Dictionary = {}
		for field: String in fields:
			coerced[field] = int(row.get(field, 0))
		out.append(coerced)
	return out


func move(number: int) -> Dictionary:
	return _entry(_moves, number - 1)


func item(number: int) -> Dictionary:
	return _entry(_items, number - 1)


func item_name(number: int) -> String:
	return String(item(number).get("name", ""))


## Type names are indexed from zero, unlike everything else here.
func type_name(number: int) -> String:
	return String(_entry(_types, number).get("name", ""))


## How effective [param attacking] is against [param defending], in tenths: 0 for
## an immunity, 5 for a resistance, 20 for a weakness and 10 for everything else.
##
## Tenths rather than a float because that is what the cartridge stores and what
## the damage formula divides by, and because the games truncate after applying
## each of a defender's two types. A float would agree most of the time and
## disagree exactly where it matters.
##
## The chart lists only the exceptions, so an absent pair is neutral, and a type
## number that is not in the chart at all (the padding run, which is where Curse
## lives) is neutral against everything by the same rule.
##
## [param foresight] is whether the defender has been identified, which cancels
## the Ghost immunities and nothing else.
func type_matchup(attacking: int, defending: int, foresight: bool = false) -> int:
	var key: int = attacking * RomLayout.TYPE_COUNT + defending
	if foresight and _foresight_matchups.has(key):
		return RomLayout.MATCHUP_EFFECTIVE
	return int(_matchups.get(key, RomLayout.MATCHUP_EFFECTIVE))


## How effective [param attacking] is against a defender of one or two types,
## in tenths, accumulated the way the cartridge accumulates it: start at ten,
## multiply by each matching type in turn, and truncate after each.
##
## This is the number a battle announces, not the number it deals damage with.
## The two are computed separately on the hardware and do not always agree: the
## accumulator truncates in tenths, so a move resisted by both halves of a dual
## type reports 2 rather than 2.5, while the damage is worked out by multiplying
## the damage itself once per type. Use this for the message and
## [method type_matchup] per type for the damage.
##
## A single-type Pokémon carries its type in both slots. The cartridge applies a
## row at most once, matching either slot, so a repeat is skipped here for the
## same reason.
func type_effectiveness(attacking: int, defending: Array, foresight: bool = false) -> int:
	var out: int = RomLayout.MATCHUP_EFFECTIVE
	var applied: Array = []
	for defending_type: int in defending:
		if applied.has(defending_type):
			continue
		applied.append(defending_type)
		@warning_ignore("integer_division")
		out = out * type_matchup(attacking, defending_type, foresight) \
			/ RomLayout.MATCHUP_EFFECTIVE
	return out


## Folds the cached rows into the lookup the engine asks questions of.
func _build_matchups(rows: Array) -> void:
	_matchups = {}
	_foresight_matchups = {}
	for row: Dictionary in rows:
		var key: int = int(row["attacker"]) * RomLayout.TYPE_COUNT + int(row["defender"])
		_matchups[key] = int(row["multiplier"])
		if bool(row.get("negated_by_foresight", false)):
			_foresight_matchups[key] = true


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


## One of the battle bars' palettes, by the names in
## [constant RomLayout.BAR_PALETTE_NAMES]. An unknown name answers with white and
## black, which draws a bar that is legible and obviously not coloured.
func bar_palette(name: String) -> PackedColorArray:
	var stored: Variant = _bar_palettes.get(name, null)
	if not stored is Array or (stored as Array).size() < 2:
		return Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))

	return Gen2Palette.pic_palette(PackedColorArray([
		Gen2Palette.from_packed(int(stored[0])),
		Gen2Palette.from_packed(int(stored[1])),
	]))


## Which HP bar palette a bar of [param lit] pixels is drawn in. The colour
## follows what is drawn rather than the numbers behind it, which is why a bar
## can turn red on a Pokémon that still has a good few hit points.
static func hp_bar_palette_name(lit: int) -> String:
	if lit >= RomLayout.HP_GREEN_PIXELS:
		return "hp_green"
	if lit >= RomLayout.HP_YELLOW_PIXELS:
		return "hp_yellow"
	return "hp_red"


func trainer_count() -> int:
	return _trainers.size()


## One trainer class by number, counting from Falkner at 1. Class 0 is the
## player, who is a class in the cartridge's tables and has no pic, so the cache
## does not carry an entry for them.
func trainer(number: int) -> Dictionary:
	return _entry(_trainers, number - 1)


func trainer_name(number: int) -> String:
	return String(trainer(number).get("name", ""))


## The four colours a trainer class is drawn with. A class has one palette and
## no shiny counterpart: only a Pokémon can be shiny.
func trainer_palette(number: int) -> PackedColorArray:
	var entry: Dictionary = trainer(number)
	if entry.is_empty():
		return Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))

	var stored: Array = entry["palette"]
	return Gen2Palette.pic_palette(PackedColorArray([
		Gen2Palette.from_packed(int(stored[0])),
		Gen2Palette.from_packed(int(stored[1])),
	]))


## How many individual trainers trainer class [param number] carries. One class
## in every game carries none: see [constant RomLayout.EMPTY_TRAINER_CLASS].
func trainer_party_count(number: int) -> int:
	return (trainer(number).get("trainers", []) as Array).size()


## One of a trainer class's individual trainers, as { name, type, party }, where
## [code]party[/code] is that trainer's Pokémon in the cartridge's own order, each
## { level, species, item, moves }. Empty for a class or an index this class does
## not have.
##
## [code]type[/code] is one of the [code]RomLayout.TRAINER_MON_*[/code]
## constants and decides what a member's own Pokémon means: whether it knows
## what its level teaches it or the moves stored with it, and whether it holds
## an item. See [Gen2TrainerParty], which turns this into battle-ready Pokémon.
func trainer_party(number: int, index: int) -> Dictionary:
	var trainers: Array = trainer(number).get("trainers", [])
	if index < 0 or index >= trainers.size():
		return {}

	var entry: Dictionary = trainers[index]
	var party: Array = []
	for mon: Dictionary in (entry.get("party", []) as Array):
		var moves: Array = []
		for move: Variant in (mon.get("moves", []) as Array):
			moves.append(int(move))
		party.append({
			"level": int(mon.get("level", 0)),
			"species": int(mon.get("species", 0)),
			"item": int(mon.get("item", 0)),
			"moves": moves,
		})

	return {
		"name": String(entry.get("name", "")),
		"type": int(entry.get("type", 0)),
		"party": party,
	}


## A trainer class's own attributes: the two items its trainers may use, the
## base money reward, and the two AI flag words [Gen2BattleAI] scores moves
## against. Empty for a class the cache does not carry.
func trainer_attributes(number: int) -> Dictionary:
	var entry: Dictionary = trainer(number)
	if entry.is_empty():
		return {}

	var attributes: Dictionary = entry.get("attributes", {})
	return {
		"item1": int(attributes.get("item1", 0)),
		"item2": int(attributes.get("item2", 0)),
		"base_reward": int(attributes.get("base_reward", 0)),
		"ai_move_weights": int(attributes.get("ai_move_weights", 0)),
		"ai_item_switch": int(attributes.get("ai_item_switch", 0)),
	}


## A trainer class's own DVs, packed the same way [method Gen2BattleMon.create]
## takes them as [code]dv_word[/code]. [constant Gen2BattleMon.PERFECT_DVS] for
## a class the cache does not carry, which is the same default a caller gets by
## not passing one at all.
func trainer_dvs(number: int) -> int:
	var entry: Dictionary = trainer(number)
	if entry.is_empty():
		return Gen2BattleMon.PERFECT_DVS
	return int(entry.get("dvs", Gen2BattleMon.PERFECT_DVS))


## Where a trainer class sits in the trainer atlas. Every trainer is drawn at the
## same size, so unlike a species pic this one always fills its cell.
func trainer_pic(number: int) -> Dictionary:
	if trainer(number).is_empty():
		return {}

	var cell: int = int(atlas("trainers").get("cell", 0))
	if cell <= 0:
		return {}
	return {"atlas": "trainers", "slot": number - 1, "width": cell, "height": cell}


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


## Metadata for a 1bpp tile strip: width, height, tiles, first_code.
func tile_sheet(name: String) -> Dictionary:
	var value: Variant = _tiles.get(name, {})
	if not value is Dictionary:
		return {}

	var out: Dictionary = {}
	for key: String in value:
		out[key] = int(value[key])
	return out


## The index buffer for a tile strip, read on first use and kept afterwards.
func tile_indices(name: String) -> PackedByteArray:
	var key: String = "tiles/%s" % name
	if _indices.has(key):
		return _indices[key]

	var indices: PackedByteArray = RomCache.read_indices(RomCache.tile_path(directory, name))
	_indices[key] = indices
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


func _load_world(path: String) -> void:
	var map_rows: Variant = RomCache.read_json(RomCache.world_maps_path(path))
	if map_rows is Array:
		for value: Dictionary in map_rows as Array:
			_world_maps.append(Gen2WorldMap.from_cache(value))

	var script_rows: Variant = RomCache.read_json(RomCache.world_scripts_path(path))
	if script_rows is Dictionary:
		_world_scripts = script_rows
	var standard_script_rows: Variant = RomCache.read_json(
		RomCache.world_standard_scripts_path(path)
	)
	if standard_script_rows is Dictionary:
		_world_standard_scripts = standard_script_rows
	var text_rows: Variant = RomCache.read_json(RomCache.world_text_path(path))
	if text_rows is Dictionary:
		_world_text = text_rows
	var movement_rows: Variant = RomCache.read_json(RomCache.world_movements_path(path))
	if movement_rows is Dictionary:
		_world_movements = movement_rows

	var tileset_rows: Variant = RomCache.read_json(RomCache.world_tilesets_path(path))
	if tileset_rows is Array:
		for value: Dictionary in tileset_rows as Array:
			var tileset: Gen2WorldTileset = Gen2WorldTileset.from_cache(value)
			_world_tilesets[tileset.number] = tileset

	var encounter_rows: Variant = RomCache.read_json(RomCache.world_encounters_path(path))
	if encounter_rows is Dictionary:
		_world_encounters = encounter_rows

	var palettes: Variant = RomCache.read_json(RomCache.world_palettes_path(path))
	if palettes is Array:
		_world_palettes = palettes
	var animation_assets: Variant = RomCache.read_json(RomCache.world_animation_assets_path(path))
	if animation_assets is Dictionary:
		_world_animation_assets = animation_assets
	var sprites: Variant = RomCache.read_json(RomCache.overworld_sprites_path(path))
	if sprites is Array:
		_overworld_sprites = sprites
	var sprite_palettes: Variant = RomCache.read_json(
		RomCache.overworld_sprite_palettes_path(path)
	)
	if sprite_palettes is Array:
		_overworld_sprite_palettes = sprite_palettes


func _read_array(path: String) -> Array:
	var value: Variant = RomCache.read_json(path)
	return value if value is Array else []


func _entry(rows: Array, index: int) -> Dictionary:
	if index < 0 or index >= rows.size():
		return {}
	return rows[index]


func _cached_bytes(value: Variant) -> PackedByteArray:
	if not value is Array:
		return PackedByteArray()
	var raw: Array = value as Array
	var out := PackedByteArray()
	out.resize(raw.size())
	for index: int in out.size():
		out[index] = int(raw[index])
	return out
