class_name GameData
extends RefCounted

## A decoded cartridge, read back out of the cache.
##
## The importer's counterpart and the only way the engine sees cartridge content:
## nothing downstream opens a ROM, and nothing here knows what a ROM is.
## [RefCounted] and scene-free, so a battle or menu can run in a test.
##
## JSON has one number type, so every cached number returns as a float and every
## comparison against an int quietly fails. Coercion happens here, once.
##
## Index buffers load on first use and are kept: a pic atlas is about a megabyte
## of indices. World sections load the same way for a blunter reason, that
## scripts, text and audio are almost all of a cache and the launcher, pic viewer
## and battle never read them; reading them at open() made listing three games
## cost more than entering one and put the whole cache in phone memory.

var id: StringName = &""
var sha1: String = ""
var directory: String = ""

## Mod content, consulted ahead of the cached tables by [method _content]. Null
## for a [GameData] built by hand, which is what a fixture does.
var _overlay: Gen2ContentOverlay = null

var _species: Array = []
var _moves: Array = []
## TMHMMoves in TMNUM order, restored to integers because JSON reads them back
## as floats.
var _tmhm_moves: Array[int] = []
var _name_input_chars: Array = []
## StringBufferPointers as WRAM addresses, in `text_buffer` argument order.
var _string_buffer_pointers: Array[int] = []
var _intro_text: Dictionary = {}
## The two cached dex orderings, by the key each mode reads, restored to
## integers because JSON reads them back as floats.
var _dex_orders: Dictionary = {}
var _items: Array = []
var _world_trades: Array = []
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
var _card_palettes: Dictionary = {}
var _gender_screen_palette: Array = []
var _copyright_string: Array = []
var _copyright_palette: Array = []
var _text_bg_palette: Array = []
var _presents_palettes: Dictionary = {}
var _title: Dictionary = {}
var _menu_text: Dictionary = {}
var _battle_object_palettes: Dictionary = {}
var _indices: Dictionary = {}
var _world_maps: Array = []
## Group and number to the map's position in [member _world_maps]. Warps,
## connections and every script warp validation ask for a map by its cartridge
## identity, and walking 388 records to answer costs more than the lookup it is
## part of.
var _world_map_index: Dictionary = {}
var _world_scripts: Dictionary = {}
var _world_standard_scripts: Dictionary = {}
var _world_text: Dictionary = {}
var _world_movements: Dictionary = {}
var _world_command_queues: Dictionary = {}
var _world_tilesets: Dictionary = {}
var _world_encounters: Dictionary = {}
var _world_palettes: Array = []
var _decoded_palettes: Dictionary = {}
var _world_animation_assets: Dictionary = {}
var _overworld_sprites: Array = []
var _overworld_sprite_palettes: Array = []
var _world_menus: Dictionary = {}
var _world_marts: Dictionary = {}
var _world_phone: Dictionary = {}
var _world_fruit_trees: Array = []
var _world_audio: Dictionary = {}
var _battle_anims_section: Dictionary = {}
## Which of the sections above have been read. A section that is genuinely empty
## is indistinguishable from one that has not been read yet, so the answer is
## recorded rather than inferred from the value.
var _sections: Dictionary = {}


## Opens the cache for a registry game, or null if it has not been imported.
static func open(game_id: StringName) -> GameData:
	var rom_hash: String = RomRegistry.sha1_for(game_id)
	if rom_hash.is_empty():
		return null
	return open_directory(RomCache.directory_for(game_id, rom_hash))


## Opens a cache directory, or null if it is missing, incomplete, or was written
## by an importer whose format this build does not read.
static func open_directory(path: String) -> GameData:
	if not RomCache.is_usable(path):
		return null

	var manifest: Dictionary = RomCache.read_manifest(path)
	var data := GameData.new()
	data._overlay = Gen2ContentOverlay.shared()
	data.directory = path
	data.id = StringName(manifest.get("game_id", ""))
	data.sha1 = String(manifest.get("sha1", ""))
	data._atlases = manifest.get("atlases", {})
	data._tiles = manifest.get("tiles", {})
	data._bar_palettes = manifest.get("bar_palettes", {})
	data._card_palettes = manifest.get("card_palettes", {})
	var gender_palette: Variant = manifest.get("gender_screen_palette", [])
	data._gender_screen_palette = gender_palette if gender_palette is Array else []
	var copyright_string: Variant = manifest.get("copyright_string", [])
	data._copyright_string = copyright_string if copyright_string is Array else []
	var copyright_palette: Variant = manifest.get("copyright_palette", [])
	data._copyright_palette = copyright_palette if copyright_palette is Array else []
	var text_palette: Variant = manifest.get("text_bg_palette", [])
	data._text_bg_palette = text_palette if text_palette is Array else []
	data._battle_object_palettes = manifest.get("battle_object_palettes", {})
	var presents_palettes: Variant = manifest.get("presents_palettes", {})
	data._presents_palettes = presents_palettes if presents_palettes is Dictionary else {}
	var title: Variant = manifest.get("title", {})
	data._title = title if title is Dictionary else {}
	var menu_text: Variant = manifest.get("menu_text", {})
	data._menu_text = menu_text if menu_text is Dictionary else {}
	data._species = data._read_array(RomCache.species_path(path))
	data._moves = data._read_array(RomCache.moves_path(path))
	data._tmhm_moves = data._read_int_array(RomCache.tmhm_moves_path(path))
	data._name_input_chars = data._read_array(RomCache.name_input_chars_path(path))
	data._string_buffer_pointers = data._read_int_array(RomCache.text_buffers_path(path))
	var intro: Variant = RomCache.read_json(RomCache.intro_text_path(path))
	data._intro_text = intro if intro is Dictionary else {}
	data._load_dex_orders(RomCache.dex_orders_path(path))
	data._items = data._read_array(RomCache.items_path(path))
	data._world_trades = data._read_array(RomCache.world_trades_path(path))
	data._types = data._read_array(RomCache.types_path(path))
	data._trainers = data._read_array(RomCache.trainers_path(path))
	data._build_matchups(data._read_array(RomCache.matchups_path(path)))
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


## How many species the cartridge carried, which is not how many exist: mod
## content is numbered above the cartridge's range and enumerated through
## [method Gen2ContentOverlay.defined_numbers]. Callers here wrap and iterate
## over the cartridge's own run, and a mod number is not part of it.
func species_count() -> int:
	return _species.size()


func map_count() -> int:
	return _maps().size()


## One map by its stable cartridge group and number, or null when it is absent.
func world_map(group: int, number: int) -> Gen2WorldMap:
	var maps: Array = _maps()
	var at: int = int(_world_map_index.get(Vector2i(group, number), -1))
	return maps[at] if at >= 0 and at < maps.size() else null


func world_maps() -> Array:
	return _maps().duplicate()


## Raw bounded script bytes indexed by the cartridge's bank and CPU address.
## Runtime never opens a ROM; these bytes come from the user cache only.
func world_script(bank: int, address: int) -> PackedByteArray:
	return _payload_bytes(
		_scripts().get(Gen2WorldScript.pointer_key(bank, address), []), _blob("scripts")
	)


## One imported menu header referenced by an overworld script.
func world_menu(bank: int, address: int) -> Dictionary:
	var value: Variant = _menus().get(Gen2WorldScript.pointer_key(bank, address), {})
	return _coerce_service_dictionary(value)


func world_menu_count() -> int:
	return _menus().size()


## One mart item list by the source MART_* index, or the default list when the
## cartridge requested an index outside the static table.
func world_mart(index: int) -> Dictionary:
	var rows: Variant = _marts().get("marts", [])
	if rows is Array and index >= 0 and index < (rows as Array).size():
		return _coerce_service_dictionary((rows as Array)[index])
	var default_value: Variant = _marts().get("default", {})
	return _coerce_service_dictionary(default_value)


## `GetFruitTreeItem`: the item a tree bears, by the `fruittree` command's own
## one-based tree id. Zero for an id no cartridge tree carries.
func world_fruit_tree_item(tree_id: int) -> int:
	var rows: Array = _fruit_trees()
	if tree_id < 1 or tree_id > rows.size():
		return 0
	return int(rows[tree_id - 1])


## One imported priced or special mart list. The source keeps these lists apart
## from the indexed standard mart table because their prices and availability
## are handled by a different shop routine.
func world_mart_special(variant: StringName) -> Dictionary:
	var special: Variant = _marts().get("special", {})
	if not special is Dictionary:
		return {}
	var items: Variant = (special as Dictionary).get(String(variant), [])
	if not items is Array:
		return {}
	return {"variant": variant, "items": _coerce_service_value(items, PackedByteArray())}


func world_mart_count() -> int:
	var rows: Variant = _marts().get("marts", [])
	return (rows as Array).size() if rows is Array else 0


func world_phone_contact(index: int) -> Dictionary:
	return _service_row(_phone().get("contacts", []), index)


func world_special_phone_call(index: int) -> Dictionary:
	return _service_row(_phone().get("special_calls", []), index)


func world_phone_contact_count() -> int:
	return _service_rows_count(_phone().get("contacts", []))


func world_phone_metadata() -> Dictionary:
	return _coerce_service_dictionary(_phone().get("metadata", {}))


func world_phone_script(kind: StringName) -> Dictionary:
	var metadata: Dictionary = world_phone_metadata()
	var key: String = "just_talk_script" if kind == &"just_talk" else "out_of_area_script"
	return _coerce_service_dictionary(metadata.get(key, {}))


func world_audio(kind: StringName, index: int) -> Dictionary:
	return _service_row(_audio().get(String(kind), []), index, _blob("audio"))


func world_audio_pointer(kind: StringName, bank: int, address: int) -> Dictionary:
	var rows: Variant = _audio().get(String(kind), [])
	if not rows is Array:
		return {}
	for value: Dictionary in rows as Array:
		if int(value.get("bank", -1)) == bank and int(value.get("address", -1)) == address:
			return _coerce_service_dictionary(value, _blob("audio"))
	return {}


## `PokemonCries`' row for one species: which cry stream it plays and the
## `wCryPitch`/`wCryLength` it plays it at. An empty answer is a species outside
## the table, which is what a mod's own number is.
func mon_cry(species: int) -> Dictionary:
	var rows: Variant = _audio().get("mon_cries", [])
	if not rows is Array or species < 1 or species > (rows as Array).size():
		return {}
	var row: Variant = (rows as Array)[species - 1]
	if not row is Dictionary:
		return {}
	return {
		"index": int((row as Dictionary).get("index", 0)),
		"pitch": int((row as Dictionary).get("pitch", 0)),
		"length": int((row as Dictionary).get("length", 0)),
	}


## The cry one species plays, which is `PlayCry`'s own two steps: the
## `PokemonCries` row, then the stream it names, with the row's pitch and length
## carried on the record so `_PlayCry`'s modulation reaches the decoder.
func species_cry(species: int) -> Dictionary:
	var row: Dictionary = mon_cry(species)
	if row.is_empty():
		return {}
	var record: Dictionary = world_audio(&"cries", int(row["index"]))
	if record.is_empty():
		return {}
	record["cry_pitch"] = int(row["pitch"])
	record["cry_length"] = int(row["length"])
	return record


func world_audio_asset(kind: StringName) -> Dictionary:
	var value: Variant = _audio().get(String(kind), {})
	return _coerce_service_dictionary(value, _blob("audio"))


func world_audio_asset_bytes(kind: StringName) -> PackedByteArray:
	return _payload_bytes(world_audio_asset(kind).get("bytes", []), _blob("audio"))


func world_service_counts() -> Dictionary:
	return {
		"menus": _menus().size(),
		"marts": world_mart_count(),
		"phone_contacts": world_phone_contact_count(),
		"music": _service_rows_count(_audio().get("music", [])),
		"sfx": _service_rows_count(_audio().get("sfx", [])),
		"cries": _service_rows_count(_audio().get("cries", [])),
	}


## One standard-script entry by its source table index. The pointer is retained
## for diagnostics, while the bounded bytes keep the runtime independent of ROMs.
func world_standard_script(index: int) -> Dictionary:
	var value: Variant = _standard_scripts().get(str(index), {})
	if not value is Dictionary:
		return {}
	var entry: Dictionary = (value as Dictionary).duplicate(true)
	entry["bank"] = int(entry.get("bank", -1))
	entry["address"] = int(entry.get("address", -1))
	entry["data"] = _payload_bytes(entry, _blob("standard_scripts")) if entry.has("payload") \
		else _payload_bytes(entry.get("bytes", []), _blob("standard_scripts"))
	return entry


## Raw bounded text bytes indexed by the cartridge's bank and CPU address.
func world_text(bank: int, address: int) -> PackedByteArray:
	return _payload_bytes(
		_text().get(Gen2WorldScript.pointer_key(bank, address), []), _blob("text")
	)


## Raw bounded movement bytes indexed by the script bank and movement pointer.
func world_movement(bank: int, address: int) -> PackedByteArray:
	return _payload_bytes(
		_movements().get(Gen2WorldScript.pointer_key(bank, address), []), _blob("movements")
	)


## The decoded `cmdqueue` a `writecmdqueue` at this pointer writes. Empty when
## the cartridge has none there, which is every map but two.
func world_command_queue(bank: int, address: int) -> Dictionary:
	var value: Variant = _command_queues().get(
		Gen2WorldScript.pointer_key(bank, address), {}
	)
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


## One decoded tileset's metatile and collision tables, or null if absent.
func world_tileset(number: int) -> Gen2WorldTileset:
	return _tilesets().get(number, null)


func world_tileset_count() -> int:
	return _tilesets().size()


## One normal encounter record by method and map group/number. The runtime
## names the water method "surf" while the cache keeps the cartridge table's
## "water" name.
func world_encounter(method: StringName, group: int, number: int) -> Dictionary:
	var table_name: String = "water" if method == &"surf" else String(method)
	var table: Variant = _encounters().get(table_name, {})
	if not table is Dictionary:
		return {}
	var value: Variant = (table as Dictionary).get("%d:%d" % [group, number], {})
	return value.duplicate(true) if value is Dictionary else {}


## One imported fishing group, indexed by the source map-header value. Group
## zero is the cartridge's no-fishing sentinel.
func world_fishing_group(group: int) -> Dictionary:
	if group < 1:
		return {}
	var fishing: Variant = _encounters().get("fishing", {})
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
	var fishing: Variant = _encounters().get("fishing", {})
	if not fishing is Dictionary:
		return []
	var groups: Variant = (fishing as Dictionary).get("time_groups", [])
	return groups.duplicate(true) if groups is Array else []


func world_roaming_maps() -> Array:
	var roaming: Variant = _encounters().get("roaming", {})
	if not roaming is Dictionary:
		return []
	var maps: Variant = (roaming as Dictionary).get("maps", [])
	return maps.duplicate(true) if maps is Array else []


func world_roaming_mons() -> Array:
	var roaming: Variant = _encounters().get("roaming", {})
	if not roaming is Dictionary:
		return []
	var mons: Variant = (roaming as Dictionary).get("mons", [])
	return mons.duplicate(true) if mons is Array else []


## GetTreeMonSet against TreeMonMaps or RockMonMaps: the treemon set number for
## a map, or 0 for a map neither table names. Set 0 is TREEMON_SET_NONE, which
## GetTreeMons refuses anyway, so a miss and a NONE row answer alike.
func treemon_set_for_map(group: int, number: int, rock: bool = false) -> int:
	var treemons: Variant = _encounters().get("treemons", {})
	if not treemons is Dictionary:
		return 0
	var rows: Variant = (treemons as Dictionary).get("rock_maps" if rock else "tree_maps", [])
	if not rows is Array:
		return 0
	for row: Variant in rows as Array:
		if not row is Dictionary:
			continue
		if int((row as Dictionary).get("map_group", 0)) == group \
			and int((row as Dictionary).get("map_number", 0)) == number:
			return int((row as Dictionary).get("set", 0))
	return 0


## GetTreeMons: one set's common and rare tables by set number. The caller
## applies the profile's own set limit first; this answers the raw table.
func treemon_set(index: int) -> Dictionary:
	var treemons: Variant = _encounters().get("treemons", {})
	if not treemons is Dictionary:
		return {}
	var sets: Variant = (treemons as Dictionary).get("sets", [])
	if not sets is Array or index < 0 or index >= (sets as Array).size():
		return {}
	var value: Variant = (sets as Array)[index]
	return value.duplicate(true) if value is Dictionary else {}


## CheckSleepingTreeMon's list for one time of day. Empty on Gold and Silver,
## which import no such lists because pokegold ships none.
func asleep_treemons(time_of_day: int) -> Array:
	var treemons: Variant = _encounters().get("treemons", {})
	if not treemons is Dictionary:
		return []
	var asleep: Variant = (treemons as Dictionary).get("asleep", {})
	if not asleep is Dictionary:
		return []
	var key: String = Gen2WorldTreemon.asleep_list_key(time_of_day)
	var value: Variant = (asleep as Dictionary).get(key, [])
	if not value is Array:
		return []
	# Restored to integers because JSON reads them back as floats, and this is
	# the one treemon list a caller searches by value rather than by index.
	var species: Array[int] = []
	for entry: Variant in value as Array:
		species.append(int(entry))
	return species


func world_encounter_count(method: StringName) -> int:
	var table_name: String = "water" if method == &"surf" else String(method)
	var table: Variant = _encounters().get(table_name, {})
	return (table as Dictionary).size() if table is Dictionary else 0


## One battle animation region: the cached bytes plus the bank and address the
## cartridge holds them at, so an in-bank pointer resolves by subtraction.
##
## [param name] is `scripts`, `objects`, `framesets` or `oam_sets`. Answers
## [code]{ bank, address, count, data }[/code], empty when the section is absent
## or the name is not one of the four.
func battle_anim_region(name: StringName) -> Dictionary:
	var value: Variant = _battle_anims().get(String(name), null)
	if not value is Dictionary:
		return {}
	var region: Dictionary = value
	return {
		"bank": int(region.get("bank", -1)),
		"address": int(region.get("address", -1)),
		"count": int(region.get("count", 0)),
		"data": _payload_bytes(region, _blob("battle_anims")),
	}


## Where one animation's script starts, as the cartridge addresses it, or -1
## when the index is outside `BattleAnimations`.
##
## The table is the first bytes of the scripts region, so this reads it rather
## than a copy: index 0 is `BattleAnim_Dummy` and the rest are move numbers.
func battle_anim_address(index: int) -> int:
	var region: Dictionary = battle_anim_region(&"scripts")
	if region.is_empty() or index < 0 or index >= int(region["count"]):
		return -1
	var data: PackedByteArray = region["data"]
	var at: int = index * 2
	if at + 2 > data.size():
		return -1
	return data[at] | (data[at + 1] << 8)


## `BattleAnimSineWave` as its own 64 cartridge bytes, or empty when the section
## is absent. Thirty-two little-endian words, read rather than computed.
func battle_anim_sine() -> PackedByteArray:
	var value: Variant = _battle_anims().get("sine", null)
	if not value is Dictionary:
		return PackedByteArray()
	return _payload_bytes(value, _blob("battle_anims"))


## One `battleanimobj` row as
## [code]{ flags, y_fix, frameset, function, palette, gfx }[/code], empty when
## the index is outside `BattleAnimObjects`.
func battle_anim_object(index: int) -> Dictionary:
	var region: Dictionary = battle_anim_region(&"objects")
	if region.is_empty() or index < 0 or index >= int(region["count"]):
		return {}
	var data: PackedByteArray = region["data"]
	var at: int = index * RomLayout.BATTLE_ANIM_OBJECT_SIZE
	if at + RomLayout.BATTLE_ANIM_OBJECT_SIZE > data.size():
		return {}
	return {
		"flags": data[at + Gen2BattleAnimImporter.OBJECT_FLAGS],
		"y_fix": data[at + Gen2BattleAnimImporter.OBJECT_Y_FIX],
		"frameset": data[at + Gen2BattleAnimImporter.OBJECT_FRAMESET],
		"function": data[at + Gen2BattleAnimImporter.OBJECT_FUNCTION],
		"palette": data[at + Gen2BattleAnimImporter.OBJECT_PALETTE],
		"gfx": data[at + Gen2BattleAnimImporter.OBJECT_GFX],
	}


## One `AnimObjGFX` row as [code]{ tiles, bank, address, sheet }[/code]. `sheet`
## is false for the three rows that name no graphics: index 0, which no
## `anim_*gfx` reaches, and the two `NULL` rows the battler-graphics commands
## fill in from the battler's own pic.
func battle_anim_gfx(index: int) -> Dictionary:
	var rows: Variant = _battle_anims().get("object_gfx", [])
	if not rows is Array or index < 0 or index >= (rows as Array).size():
		return {}
	var row: Variant = (rows as Array)[index]
	if not row is Dictionary:
		return {}
	return {
		"tiles": int((row as Dictionary).get("tiles", 0)),
		"bank": int((row as Dictionary).get("bank", 0)),
		"address": int((row as Dictionary).get("address", 0)),
		"sheet": bool((row as Dictionary).get("sheet", false)),
	}


func battle_anim_gfx_count() -> int:
	var rows: Variant = _battle_anims().get("object_gfx", [])
	return (rows as Array).size() if rows is Array else 0


## Indexed pixels for one decompressed `AnimObjGFX` sheet, loaded on demand.
func battle_anim_gfx_indices(index: int) -> PackedByteArray:
	var key: String = "battle_anim_gfx/%d" % index
	if _indices.has(key):
		return _indices[key]
	var data: PackedByteArray = RomCache.read_indices(
		RomCache.battle_anim_gfx_path(directory, index)
	)
	_indices[key] = data
	return data


## Metadata for one cartridge overworld sprite, indexed by the source sprite
## number. Sprite number zero is reserved for no sprite by the cartridge.
func overworld_sprite(number: int) -> Gen2WorldSprite:
	var row: Dictionary = _entry(_sprites(), number - 1)
	return Gen2WorldSprite.from_cache(row) if not row.is_empty() else null


func overworld_sprite_count() -> int:
	return _sprites().size()


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


## The reusable icon strip indexed by constants/icon_constants.asm.
func overworld_icon(icon_number: int) -> Gen2WorldSprite:
	if icon_number <= 0 or icon_number > RomLayout.MON_ICON_COUNT:
		return null
	return Gen2WorldSprite.from_mon_icon(icon_number)


func overworld_icon_indices(icon_number: int) -> PackedByteArray:
	var key: String = "overworld_icons/%d" % icon_number
	if _indices.has(key):
		return _indices[key]
	var data: PackedByteArray = RomCache.read_indices(
		RomCache.overworld_icon_path(directory, icon_number)
	)
	_indices[key] = data
	return data


## One of the eight overworld object palette kinds for a time-of-day group.
## The source's palette override bit selects the same eight rows while marking
## that the object event, rather than the sprite table, supplied the choice.
func overworld_sprite_palette(palette_index: int, time_of_day: int) -> PackedColorArray:
	var group: int = clampi(time_of_day, 0, 3) * RomLayout.OVERWORLD_SPRITE_PALETTE_COUNT \
		+ (palette_index & (RomLayout.OVERWORLD_SPRITE_PALETTE_COUNT - 1))
	if group < 0 or group >= _sprite_palettes().size():
		return PackedColorArray()
	var raw: Variant = _sprite_palettes()[group]
	if not raw is Array:
		return PackedColorArray()
	var out := PackedColorArray()
	for packed: Variant in raw as Array:
		out.append(Gen2Palette.from_packed(int(packed)))
	return out


## One of the cartridge's four-colour background palette groups.
##
## Decoded once and kept: there are forty-two groups, they never change, and the
## overworld asks for them again every time an animated tile redraws the atlas.
func world_palette(number: int) -> PackedColorArray:
	if _decoded_palettes.has(number):
		return _decoded_palettes[number]
	var out := PackedColorArray()
	if number < 0 or number >= _palettes().size():
		return out
	var raw: Variant = _palettes()[number]
	if not raw is Array:
		return out
	for packed: Variant in raw as Array:
		out.append(Gen2Palette.from_packed(int(packed)))
	_decoded_palettes[number] = out
	return out


## Raw 2bpp frames embedded in the cartridge's animation routines.
func world_animation_asset(name: String) -> PackedByteArray:
	var raw: Variant = _animation_assets().get(name, [])
	if not raw is Array:
		return PackedByteArray()
	var out := PackedByteArray()
	out.resize((raw as Array).size())
	for index: int in out.size():
		out[index] = int((raw as Array)[index])
	return out


## Indexed 2bpp pixels for one tileset's overworld tiles, loaded on demand.
##
## The strip is [constant RomLayout.TILESET_TILE_COUNT] tiles wide and is indexed
## by the metatile byte itself, so both graphics blocks are addressable; see that
## constant for what sits where.
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
	return _content(Gen2ContentOverlay.KIND_SPECIES, _species, number)


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


## A species' Pokedex entry as { category, height, weight, pages }, or an empty
## Dictionary if there is no such number.
##
## [code]height[/code] and [code]weight[/code] are the cartridge's own numbers,
## not measurements: see [method RomImporter.read_dex_entry]. [code]pages[/code]
## is the two description pages, in order. It goes through [method species] so a
## mod that replaces a species replaces its dex entry with it.
func dex_entry(number: int) -> Dictionary:
	var entry: Variant = species(number).get("dex", {})
	if not entry is Dictionary or (entry as Dictionary).is_empty():
		return {}
	var dex: Dictionary = entry
	var pages: PackedStringArray = PackedStringArray()
	for page: Variant in dex.get("pages", []):
		pages.append(String(page))
	return {
		"category": String(dex.get("category", "")),
		"height": int(dex.get("height", 0)),
		"weight": int(dex.get("weight", 0)),
		"pages": pages,
	}


## data/pokemon/dex_order_new.asm, the order DEXMODE_NEW lists species in.
func dex_order_new() -> PackedInt32Array:
	return _dex_orders.get("new", PackedInt32Array())


## data/pokemon/dex_order_alpha.asm, the order DEXMODE_ABC filters down to the
## species that have been seen.
func dex_order_alpha() -> PackedInt32Array:
	return _dex_orders.get("alpha", PackedInt32Array())


## Both order tables, coerced out of JSON's single number type once on open. A
## table that is missing or the wrong length is dropped rather than half-kept:
## an order with a hole in it would list a species number of zero, which
## `.PrintEntry` treats as the end of the list.
func _load_dex_orders(path: String) -> void:
	var raw: Variant = RomCache.read_json(path)
	if not raw is Dictionary:
		return
	for key: String in ["new", "alpha"]:
		var value: Variant = (raw as Dictionary).get(key, [])
		if not value is Array or (value as Array).size() != RomLayout.SPECIES_COUNT:
			continue
		var order: PackedInt32Array = PackedInt32Array()
		for number: Variant in value as Array:
			order.append(int(number))
		_dex_orders[key] = order


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
	return _content(Gen2ContentOverlay.KIND_MOVE, _moves, number)


## Every TM/HM/tutor move in TMNUM order, so index n-1 is TM/HM number n.
func tmhm_moves() -> Array[int]:
	return _tmhm_moves.duplicate()


## GetTMHMMove: the move one TM/HM number teaches, or 0 when the number is not
## one this cartridge carries.
func tmhm_move(number: int) -> int:
	if number < 1 or number > _tmhm_moves.size():
		return 0
	return _tmhm_moves[number - 1]


## CanLearnTMHMMove's own scan of TMHMMoves for wPutativeTMHMMove: the one-based
## number that teaches [param move], or 0. The source takes the first match, so
## this does too.
func tmhm_number_for_move(move_number: int) -> int:
	if move_number <= 0:
		return 0
	var found: int = _tmhm_moves.find(move_number)
	return found + 1 if found >= 0 else 0


## One of data/text/name_input_chars.asm's four keyboards as rows of raw
## cartridge codes, in block order: NameInputLower, BoxNameInputLower,
## NameInputUpper, BoxNameInputUpper. Empty when the table is missing, which the
## caller reports rather than drawing a blank grid.
func name_input_chars(table: int) -> Array:
	if table < 0 or table >= _name_input_chars.size():
		return []
	var out: Array = []
	for row: Variant in _name_input_chars[table]:
		var codes: Array[int] = []
		for code: Variant in row:
			codes.append(int(code))
		out.append(codes)
	return out


## Which `text_buffer` argument a `TX_RAM` address names, or -1 for an address
## this cartridge does not use as a string buffer.
##
## `TextCommand_RAM` prints from a raw WRAM pointer while `getstring` and
## `verbosegiveitem` fill buffers by number, so a runner that only knows the
## numbers cannot answer a `text_ram`. StringBufferPointers is the way across.
func string_buffer_for_address(address: int) -> int:
	return _string_buffer_pointers.find(address)


## StringBufferPointers as read from this dump, in `text_buffer` argument order.
func string_buffer_addresses() -> Array[int]:
	return _string_buffer_pointers.duplicate()


## One of the intro's own texts by its `data/text/common_2.asm` label, in the
## keys [constant RomImporter.INTRO_TEXT_OPENINGS] names: `oak_1`, `oak_2`,
## `oak_4` to `oak_7` and `gender`. Empty when this cartridge does not ship it,
## which for `gender` means Gold or Silver.
func intro_text(key: String) -> String:
	return String(_intro_text.get(key, ""))


func item(number: int) -> Dictionary:
	return _content(Gen2ContentOverlay.KIND_ITEM, _items, number)


func item_name(number: int) -> String:
	return String(item(number).get("name", ""))


## One imported NPC trade record, or an empty dictionary when this cartridge
## does not contain the requested row.
func world_trade(index: int) -> Dictionary:
	return _entry(_world_trades, index)


func world_trade_count() -> int:
	return _world_trades.size()


## Type names are indexed from zero, unlike everything else here.
func type_name(number: int) -> String:
	return String(_entry(_types, number).get("name", ""))


## How effective [param attacking] is against [param defending], in tenths: 0 for
## an immunity, 5 for a resistance, 20 for a weakness and 10 for everything else.
##
## Tenths rather than a float, because that is what the cartridge stores and what
## the damage formula divides by, and the games truncate after each of a
## defender's two types. A float would disagree exactly where it matters.
##
## Only exceptions are listed, so an absent pair is neutral, as is a type number
## missing from the chart entirely (the padding run, where Curse lives).
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
## The number a battle announces, not the one it deals damage with. The hardware
## computes them separately and they disagree: this accumulator truncates in
## tenths, so a move resisted by both halves of a dual type reports 2 rather than
## 2.5, while damage multiplies the damage itself once per type. Use this for the
## message and [method type_matchup] per type for damage.
##
## A single-type Pokémon carries its type in both slots, and the cartridge
## applies a row at most once, so a repeat is skipped here too.
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


## One of `_CGB_TrainerCard`'s eight background palettes, expanded the way
## `LoadPalette_White_Col1_Col2_Black` expands a trainer class pair.
func card_palette(slot: int) -> PackedColorArray:
	var stored: Variant = _card_palettes.get("background", [])
	if not stored is Array or slot < 0 or slot >= (stored as Array).size():
		return Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))
	var pair: Array = (stored as Array)[slot]
	return Gen2Palette.pic_palette(PackedColorArray([
		Gen2Palette.from_packed(int(pair[0])),
		Gen2Palette.from_packed(int(pair[1])),
	]))


## One of the eight `PAL_BATTLE_OB_*` object palettes an animation object is
## drawn with, whole.
##
## Slots 0 and 1 are the two battlers' own and are not in the table:
## `_CGB_BattleScreenLayout` fills them from whoever is on the field, so a caller
## passes those two in as [param enemy] and [param player] pairs. Everything from
## `PAL_BATTLE_OB_GRAY` on is `BattleObjectPals`, four colours each.
func battle_object_palette(
	slot: int, enemy: Array = [], player: Array = []
) -> PackedColorArray:
	if slot < 0 or slot >= RomLayout.BATTLE_OBJECT_PALETTE_COUNT:
		return Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))
	if slot < RomLayout.BATTLE_OBJECT_PALETTE_FIRST_STORED:
		# `LoadPalette_White_Col1_Col2_Black` over the battler's own pair.
		var pair: Array = enemy if slot == 0 else player
		if pair.size() < 2:
			return Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))
		return Gen2Palette.pic_palette(PackedColorArray([
			Gen2Palette.from_packed(int(pair[0])),
			Gen2Palette.from_packed(int(pair[1])),
		]))
	var name: String = RomLayout.BATTLE_OBJECT_PALETTE_NAMES[
		slot - RomLayout.BATTLE_OBJECT_PALETTE_FIRST_STORED
	]
	var stored: Variant = _battle_object_palettes.get(name, null)
	if not stored is Array \
			or (stored as Array).size() < RomLayout.BATTLE_OBJECT_PALETTE_COLORS:
		return Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))
	var colors := PackedColorArray()
	for packed: Variant in stored as Array:
		colors.append(Gen2Palette.from_packed(int(packed)))
	return colors


## `Palette_TextBG7`, the four colours a text box is drawn through. Empty on a
## cartridge that ships none, which leaves a caller on its own black-on-white.
func text_bg_palette() -> PackedColorArray:
	if _text_bg_palette.size() < RomLayout.TEXT_BG_PALETTE_COLORS:
		return PackedColorArray()
	var colors := PackedColorArray()
	for packed: Variant in _text_bg_palette:
		colors.append(Gen2Palette.from_packed(int(packed)))
	return colors


## `LoadGenderScreenPal`'s four colours, whole. Empty on a cartridge with no
## gender screen, which is the caller's cue that the screen is not asked for.
func gender_screen_palette() -> PackedColorArray:
	if _gender_screen_palette.size() < RomLayout.GENDER_SCREEN_PALETTE_COLORS:
		return PackedColorArray()
	var colors := PackedColorArray()
	for packed: Variant in _gender_screen_palette:
		colors.append(Gen2Palette.from_packed(int(packed)))
	return colors


## `CopyrightString`'s tile codes, in source order and including the `next`
## that separates its rows. Empty on a cache that has no copyright screen, which
## is the caller's cue not to draw one.
func copyright_string() -> PackedByteArray:
	var out := PackedByteArray()
	for code: Variant in _copyright_string:
		out.append(int(code) & 0xFF)
	return out


## PREDEFPAL_GAMEFREAK_LOGO_BG, the copyright screen's own four colours. Empty
## on a cache imported before they were.
func copyright_palette() -> PackedColorArray:
	if _copyright_palette.size() < RomLayout.COPYRIGHT_PALETTE_COLORS:
		return PackedColorArray()
	var colors := PackedColorArray()
	for packed: Variant in _copyright_palette:
		colors.append(Gen2Palette.from_packed(int(packed)))
	return colors


## One of the pack's five texts (`oak_no_time`, `no_mon`, `toss_ask`,
## `toss_ask_quantity`, `toss_threw`), still carrying [Gen2TextStream]'s markers
## for the quantity and the item name. Empty on a cache imported before them,
## which is the caller's cue to use its own wording.
func menu_text(key: String) -> String:
	return String(_menu_text.get(key, ""))


## `.MenuDesc`'s line for one start-menu item, by the item's own kind. Empty for
## an item the cartridge has no description for, and for every item on a cache
## imported before the run was.
func menu_description(kind: StringName) -> String:
	var descriptions: Variant = _menu_text.get("descriptions", {})
	if not descriptions is Dictionary:
		return ""
	return String((descriptions as Dictionary).get(String(kind), ""))


## One of the splash's object palettes: `object` is
## PREDEFPAL_GAMEFREAK_LOGO_OB, `ditto` is `gfx/splash/ditto.pal` and
## `ditto_fade` is the sixteen-step transform. Empty for a palette this profile
## does not ship, which is how Gold and Silver say they have no Ditto.
func presents_palette(name: String) -> PackedColorArray:
	var stored: Variant = _presents_palettes.get(name, [])
	if not stored is Array:
		return PackedColorArray()
	var colors := PackedColorArray()
	for packed: Variant in stored as Array:
		colors.append(Gen2Palette.from_packed(int(packed)))
	return colors


## One of the title screen's palette runs, four colours to a palette:
## [code]palettes[/code] is Crystal's sixteen, and [code]bg_palettes[/code] and
## [code]ob_palettes[/code] are Gold and Silver's five and two. Empty for a run
## this profile does not ship, which is how the two screens are told apart.
func title_palettes(name: String) -> Array[PackedColorArray]:
	var stored: Variant = _title.get(name, [])
	var out: Array[PackedColorArray] = []
	if not stored is Array:
		return out
	var packed: Array = stored
	for first: int in range(0, packed.size(), RomLayout.TITLE_PALETTE_COLORS):
		var colors := PackedColorArray()
		for index: int in RomLayout.TITLE_PALETTE_COLORS:
			colors.append(Gen2Palette.from_packed(int(packed[first + index])))
		out.append(colors)
	return out


## `TitleScreenTilemap`, the `$FF`-terminated run `LoadTitleScreenTilemap` writes
## straight into the BG map. Empty on Crystal, which draws its title screen with
## `DrawTitleGraphic` instead of a stored map.
func title_tilemap() -> PackedByteArray:
	var stored: Variant = _title.get("tilemap", [])
	var out := PackedByteArray()
	if not stored is Array:
		return out
	for code: Variant in stored as Array:
		out.append(int(code))
	return out


## `PREDEFPAL_CGB_BADGE`, stored whole rather than as a pair.
func card_badge_palette() -> PackedColorArray:
	var stored: Variant = _card_palettes.get("badge", [])
	if not stored is Array or (stored as Array).size() < RomLayout.CARD_BADGE_PALETTE_COLORS:
		return Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))
	var colors := PackedColorArray()
	for packed: Variant in stored as Array:
		colors.append(Gen2Palette.from_packed(int(packed)))
	return colors


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
	return _content(Gen2ContentOverlay.KIND_TRAINER, _trainers, number)


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
		for move_number: Variant in (mon.get("moves", []) as Array):
			moves.append(int(move_number))
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


## True once [param section] has been read, marking it read on the first ask.
## The caller fills the matching member; a section is only ever read once.
func _claim_section(section: String) -> bool:
	if _sections.has(section):
		return false
	_sections[section] = true
	return true


## One cached world file, as an Array or a Dictionary. A file that is missing or
## the wrong shape answers empty, which is the same answer an unimported section
## gave before these became lazy.
func _read_section(path: String, as_array: bool) -> Variant:
	var value: Variant = RomCache.read_json(path)
	if as_array:
		return value if value is Array else []
	return value if value is Dictionary else {}


## The binary blob a section's byte spans address, read once and kept. It is a
## [PackedByteArray], so it costs one byte per cartridge byte rather than the
## twenty-odd a Variant in an Array costs.
func _blob(section: String) -> PackedByteArray:
	var key: String = "blob/%s" % section
	if _indices.has(key):
		return _indices[key]
	var data: PackedByteArray = RomCache.read_blob(
		RomCache.blob_path(_section_json_path(section))
	)
	_indices[key] = data
	return data


func _section_json_path(section: String) -> String:
	match section:
		"scripts":
			return RomCache.world_scripts_path(directory)
		"standard_scripts":
			return RomCache.world_standard_scripts_path(directory)
		"text":
			return RomCache.world_text_path(directory)
		"movements":
			return RomCache.world_movements_path(directory)
		"command_queues":
			return RomCache.world_command_queues_path(directory)
		"audio":
			return RomCache.world_audio_path(directory)
		"battle_anims":
			return RomCache.battle_anims_path(directory)
	return ""


func _maps() -> Array:
	if _claim_section("maps"):
		for value: Dictionary in _read_section(RomCache.world_maps_path(directory), true):
			var map: Gen2WorldMap = Gen2WorldMap.from_cache(value)
			# The first record of a duplicated identity wins, matching the scan
			# this replaced.
			var key := Vector2i(map.group, map.number)
			if not _world_map_index.has(key):
				_world_map_index[key] = _world_maps.size()
			_world_maps.append(map)
	return _world_maps


func _scripts() -> Dictionary:
	if _claim_section("scripts"):
		_world_scripts = _read_section(RomCache.world_scripts_path(directory), false)
	return _world_scripts


func _standard_scripts() -> Dictionary:
	if _claim_section("standard_scripts"):
		_world_standard_scripts = _read_section(
			RomCache.world_standard_scripts_path(directory), false
		)
	return _world_standard_scripts


func _text() -> Dictionary:
	if _claim_section("text"):
		_world_text = _read_section(RomCache.world_text_path(directory), false)
	return _world_text


func _movements() -> Dictionary:
	if _claim_section("movements"):
		_world_movements = _read_section(RomCache.world_movements_path(directory), false)
	return _world_movements


func _command_queues() -> Dictionary:
	if _claim_section("command_queues"):
		_world_command_queues = _read_section(
			RomCache.world_command_queues_path(directory), false
		)
	return _world_command_queues


func _tilesets() -> Dictionary:
	if _claim_section("tilesets"):
		for value: Dictionary in _read_section(RomCache.world_tilesets_path(directory), true):
			var tileset: Gen2WorldTileset = Gen2WorldTileset.from_cache(value)
			_world_tilesets[tileset.number] = tileset
	return _world_tilesets


func _encounters() -> Dictionary:
	if _claim_section("encounters"):
		_world_encounters = _read_section(RomCache.world_encounters_path(directory), false)
	return _world_encounters


func _palettes() -> Array:
	if _claim_section("palettes"):
		_world_palettes = _read_section(RomCache.world_palettes_path(directory), true)
	return _world_palettes


func _animation_assets() -> Dictionary:
	if _claim_section("animation_assets"):
		_world_animation_assets = _read_section(
			RomCache.world_animation_assets_path(directory), false
		)
	return _world_animation_assets


func _sprites() -> Array:
	if _claim_section("sprites"):
		_overworld_sprites = _read_section(RomCache.overworld_sprites_path(directory), true)
	return _overworld_sprites


func _sprite_palettes() -> Array:
	if _claim_section("sprite_palettes"):
		_overworld_sprite_palettes = _read_section(
			RomCache.overworld_sprite_palettes_path(directory), true
		)
	return _overworld_sprite_palettes


func _menus() -> Dictionary:
	if _claim_section("menus"):
		_world_menus = _read_section(RomCache.world_menus_path(directory), false)
	return _world_menus


func _marts() -> Dictionary:
	if _claim_section("marts"):
		_world_marts = _read_section(RomCache.world_marts_path(directory), false)
	return _world_marts


func _fruit_trees() -> Array:
	if _claim_section("fruit_trees"):
		_world_fruit_trees = _read_section(
			RomCache.world_fruit_trees_path(directory), true
		)
	return _world_fruit_trees


func _phone() -> Dictionary:
	if _claim_section("phone"):
		_world_phone = _read_section(RomCache.world_phone_path(directory), false)
	return _world_phone


func _audio() -> Dictionary:
	if _claim_section("audio"):
		_world_audio = _read_section(RomCache.world_audio_path(directory), false)
	return _world_audio


func _battle_anims() -> Dictionary:
	if _claim_section("battle_anims"):
		_battle_anims_section = _read_section(RomCache.battle_anims_path(directory), false)
	return _battle_anims_section


func _read_array(path: String) -> Array:
	var value: Variant = RomCache.read_json(path)
	return value if value is Array else []


func _read_int_array(path: String) -> Array[int]:
	var out: Array[int] = []
	for value: Variant in _read_array(path):
		out.append(int(value))
	return out


func _entry(rows: Array, index: int) -> Dictionary:
	if index < 0 or index >= rows.size():
		return {}
	return rows[index]


## One numbered content row, with the mod overlay consulted first.
##
## The chokepoint species, moves, items and trainers all read through, and so the
## one place that has to know a mod may have added or changed one. Everything
## carried on a species row rides along: a defined species has a learnset,
## evolutions and TM flags because [method learnset], [method evolutions] and the
## TM/HM gate all read them back off this row.
##
## Numbering is one-based, the cartridge's own; see [Gen2ContentOverlay].
func _content(kind: StringName, rows: Array, number: int) -> Dictionary:
	var base: Dictionary = _entry(rows, number - 1)
	if _overlay == null or _overlay.is_empty():
		return base
	return _overlay.resolve(kind, number, base)


## Replaces the mod content this cache answers with. For a tool or a test that
## needs content of its own without touching the shared overlay.
func set_content_overlay(overlay: Gen2ContentOverlay) -> void:
	_overlay = overlay


func _service_row(
	value: Variant, index: int, blob: PackedByteArray = PackedByteArray()
) -> Dictionary:
	if not value is Array or index < 0 or index >= (value as Array).size():
		return {}
	return _coerce_service_dictionary((value as Array)[index], blob)


func _service_rows_count(value: Variant) -> int:
	return (value as Array).size() if value is Array else 0


func _coerce_service_dictionary(
	value: Variant, blob: PackedByteArray = PackedByteArray()
) -> Dictionary:
	var coerced: Variant = _coerce_service_value(value, blob)
	return coerced if coerced is Dictionary else {}


func _coerce_service_value(value: Variant, blob: PackedByteArray) -> Variant:
	if value is float:
		return int(value)
	if value is Array:
		var array: Array = []
		for entry: Variant in value as Array:
			array.append(_coerce_service_value(entry, blob))
		return array
	if value is Dictionary:
		var dictionary: Dictionary = {}
		for key: Variant in value:
			# A payload span is handed back under the name the record used to
			# carry inline, so nothing downstream of here has to know that the
			# bytes now live in a blob.
			if String(key) == RomCache.PAYLOAD_KEY:
				dictionary[RomCache.BYTES_KEY] = _span_bytes(value[key], blob)
				continue
			dictionary[key] = _coerce_service_value(value[key], blob)
		return dictionary
	return value


## Resolves one cached byte run, whichever way the cache holds it.
##
## A record carrying a [constant RomCache.PAYLOAD_KEY] is a span into the
## section's blob. A bare Array is read inline, which is what a hand-written test
## fixture holds. The two never have to be told apart by shape: the key says
## which one this is.
func _payload_bytes(value: Variant, blob: PackedByteArray) -> PackedByteArray:
	if value is PackedByteArray:
		return value
	if value is Dictionary and (value as Dictionary).has(RomCache.PAYLOAD_KEY):
		return _span_bytes((value as Dictionary)[RomCache.PAYLOAD_KEY], blob)
	if not value is Array:
		return PackedByteArray()
	var raw: Array = value as Array
	var out := PackedByteArray()
	out.resize(raw.size())
	for index: int in out.size():
		out[index] = int(raw[index]) & 0xFF
	return out


## Reads an [offset, length] span out of a section blob. A span that does not
## address the blob answers empty rather than reading a neighbouring record.
func _span_bytes(span: Variant, blob: PackedByteArray) -> PackedByteArray:
	if not span is Array or (span as Array).size() != RomCache.PAYLOAD_SPAN:
		return PackedByteArray()
	var at: int = int((span as Array)[0])
	var length: int = int((span as Array)[1])
	if at < 0 or length < 0 or at + length > blob.size():
		return PackedByteArray()
	return blob.slice(at, at + length)
