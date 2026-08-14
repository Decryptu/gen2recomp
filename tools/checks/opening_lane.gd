extends RefCounted

var _r: RefCounted = null

## Validates the cache records required by the first playable lane. This is a
## read-only cache audit: it never opens a ROM and never treats a missing
## opening record as a presentation fallback.
##
##   Godot --headless --path . -s res://tools/validate.gd -- opening_lane

const REQUIRED_SECTIONS: Dictionary = {
	"maps": RomCache.WORLD_MAPS,
	"tilesets": RomCache.WORLD_TILESETS,
	"scripts": RomCache.WORLD_SCRIPTS,
	"text": RomCache.WORLD_TEXT,
	"movements": RomCache.WORLD_MOVEMENTS,
	"sprites": RomCache.OVERWORLD_SPRITES,
	"audio": RomCache.WORLD_AUDIO,
}


func run(r: RefCounted) -> void:
	_r = r
	for game_id: StringName in _r.GAME_IDS:
		if not _validate(game_id):
			_r.fail("%s: the opening lane's cache records are incomplete." % game_id)


func _validate(game_id: StringName) -> bool:
	var data: GameData = GameData.open(game_id)
	if data == null:
		print("FAIL %s: cache is not usable" % game_id)
		return false
	var failures: Array[String] = []
	if data.id != game_id:
		failures.append("source_profile_mismatch:%s" % data.id)
	var counts: Dictionary = {}
	for section: String in REQUIRED_SECTIONS:
		var path: String = "%s/%s" % [data.directory, REQUIRED_SECTIONS[section]]
		var value: Variant = RomCache.read_json(path)
		if (value is Dictionary and (value as Dictionary).is_empty()) \
			or (value is Array and (value as Array).is_empty()) \
			or value == null:
			failures.append("missing_%s" % section)
		else:
			counts[section] = value.size()

	var home: Gen2WorldMap = data.world_map(24, Gen2WorldSpawn.PLAYERS_HOUSE_2F)
	var town: Gen2WorldMap = data.world_map(24, 4)
	if home == null:
		failures.append("missing_bedroom_map:24:7")
	if town == null:
		failures.append("missing_new_bark_map:24:4")
	for map: Gen2WorldMap in [home, town]:
		if map == null:
			continue
		var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
		if tileset == null or tileset.meta.is_empty() or tileset.collision.is_empty():
			failures.append("missing_graphics_or_collision:map_%d_%d" % [map.group, map.number])
		if map.blocks.is_empty() or map.collision.is_empty():
			failures.append("missing_map_payload:map_%d_%d" % [map.group, map.number])

	for table: int in 4:
		if data.name_input_chars(table).is_empty():
			failures.append("missing_name_keyboard:%d" % table)
	for key: String in ["oak_1", "oak_2", "oak_4", "oak_5", "oak_6", "oak_7"]:
		if data.intro_text(key).is_empty():
			failures.append("missing_intro_text:%s" % key)
	if game_id == &"crystal" and data.intro_text("gender").is_empty():
		failures.append("missing_crystal_gender_text")

	var audio_counts: Dictionary = data.world_service_counts()
	for kind: String in ["music", "sfx", "cries"]:
		if int(audio_counts.get(kind, 0)) <= 0:
			failures.append("missing_audio:%s" % kind)
	for asset: StringName in [&"wave_samples", &"drumkits"]:
		if data.world_audio_asset_bytes(asset).is_empty():
			failures.append("missing_audio_payload:%s" % asset)

	if counts.get("movements", 0) == 0:
		failures.append("missing_movement_data")
	for kind: StringName in [&"music", &"sfx", &"cries"]:
		var kind_count: int = int(audio_counts.get(String(kind), 0))
		for index: int in kind_count:
			var record: Dictionary = data.world_audio(kind, index)
			if record.is_empty():
				failures.append("missing_audio_record:%s:%d" % [kind, index])
			elif record.get("bytes", PackedByteArray()).is_empty():
				failures.append("missing_audio_record_payload:%s:%d" % [kind, index])

	var script_audit: Dictionary = _audit_scripts(data, game_id == &"crystal")
	for reason: String in script_audit["failures"]:
		failures.append(reason)
	# Unknown commands are reported as coverage debt, not cache corruption: the
	# shared runner intentionally exposes source commands it does not yet model.
	# Empty payloads and malformed pointers remain hard failures above.
	if int(script_audit["malformed_pointers"]) > 0:
		failures.append("malformed_script_pointers:%d" % int(script_audit["malformed_pointers"]))
	print("%s: maps=%d scripts=%d text=%d movements=%d music=%d sfx=%d cries=%d" % [
		game_id, data.map_count(), int(counts.get("scripts", 0)), int(counts.get("text", 0)),
		int(counts.get("movements", 0)), int(audio_counts.get("music", 0)),
		int(audio_counts.get("sfx", 0)), int(audio_counts.get("cries", 0)),
	])
	print("  unknown_commands=%d malformed_pointers=%d" % [
		int(script_audit["unknown_commands"]), int(script_audit["malformed_pointers"]),
	])
	if failures.is_empty():
		print("  opening_lane=valid")
		return true
	print("  opening_lane=invalid failures=%s" % JSON.stringify(failures))
	return false


func _audit_scripts(data: GameData, crystal: bool) -> Dictionary:
	var raw: Variant = RomCache.read_json(RomCache.world_scripts_path(data.directory))
	var failures: Array[String] = []
	var unknown_commands: int = 0
	var malformed_pointers: int = 0
	if not raw is Dictionary:
		return {"failures": ["missing_script_index"], "unknown_commands": 0, "malformed_pointers": 0}
	for key: String in (raw as Dictionary):
		var parts: PackedStringArray = key.split(":")
		if parts.size() != 2:
			malformed_pointers += 1
			continue
		var bank: int = int(parts[0])
		var address: int = ("0x%s" % parts[1]).hex_to_int()
		var bytes: PackedByteArray = data.world_script(bank, address)
		if bytes.is_empty():
			malformed_pointers += 1
			continue
		var at: int = 0
		for _step: int in Gen2WorldScript.MAX_COMMANDS:
			var command: Dictionary = Gen2WorldScript.command_at(bytes, at, crystal)
			if not bool(command.get("ok", false)):
				unknown_commands += 1
				break
			at += int(command.get("width", 1))
			if Gen2WorldScript.is_terminal(int(command.get("opcode", 0)), crystal):
				break
	return {
		"failures": failures,
		"unknown_commands": unknown_commands,
		"malformed_pointers": malformed_pointers,
	}
