class_name Gen2SaveStore
extends RefCounted

## User-owned save slots. This is separate from [RomCache], which contains only
## cartridge-derived data and has a different lifecycle.

const ROOT: String = "user://save_slots"
const SLOT_COUNT: int = 3
# Canonical Crystal Elm's Lab gift records. These values describe the imported
# story choices and are not inserted into a new save before the lab handoff.
const STARTER_LEVEL: int = 5
const STARTER_SPECIES: Array[int] = [152, 155, 158]
const STARTER_ITEM: int = 0xAD


static func path_for(game_id: StringName, rom_sha1: String, slot: int) -> String:
	return "%s/%s_%s/slot_%d.json" % [ROOT, String(game_id), rom_sha1.substr(0, 8), slot]


static func exists(game_id: StringName, rom_sha1: String, slot: int) -> bool:
	return _valid_slot(slot) and FileAccess.file_exists(path_for(game_id, rom_sha1, slot))


static func save(save_data: Gen2SaveData, data: GameData) -> Dictionary:
	var validation: Dictionary = Gen2SaveValidator.validate(save_data, data)
	if not validation["ok"]:
		return validation
	var path: String = path_for(save_data.game_id, save_data.rom_sha1, save_data.slot)
	var directory: String = path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return _failure("could not create the save directory")

	var temporary: String = "%s.tmp" % path
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _failure("could not open the save for writing")
	file.store_string(JSON.stringify(save_data.to_dict(), "\t"))
	file.flush()
	file.close()
	if DirAccess.rename_absolute(temporary, path) != OK:
		DirAccess.remove_absolute(temporary)
		return _failure("could not finish writing the save")
	return {"ok": true, "message": ""}


static func load_result(game_id: StringName, rom_sha1: String, slot: int, data: GameData) -> Dictionary:
	if not _valid_slot(slot):
		return _failure("save slot %d is out of range" % slot)
	var path: String = path_for(game_id, rom_sha1, slot)
	if not FileAccess.file_exists(path):
		return _failure("save slot %d is empty" % (slot + 1))
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("save slot %d could not be opened" % (slot + 1))
	var parser := JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		return _failure("save slot %d is not valid JSON data" % (slot + 1))
	var raw: Variant = parser.data
	var migration: Dictionary = Gen2SaveData.migrate_dict(raw)
	if not bool(migration.get("ok", false)):
		return _failure("save slot %d: %s" % [slot + 1, migration.get("message", "unsupported save format")])
	var loaded_save: Gen2SaveData = Gen2SaveData.from_dict(migration["data"])
	if loaded_save == null:
		return _failure("save slot %d is not valid JSON data" % (slot + 1))
	var validation: Dictionary = Gen2SaveValidator.validate(loaded_save, data)
	if not validation["ok"]:
		return _failure("save slot %d: %s" % [slot + 1, validation["message"]])
	return {
		"ok": true, "message": "", "save": loaded_save,
		"migrated": bool(migration.get("migrated", false)),
	}


static func slots_for(game_id: StringName, rom_sha1: String, data: GameData) -> Array:
	var out: Array = []
	for slot: int in SLOT_COUNT:
		var row: Dictionary = {
			"slot": slot,
			"exists": exists(game_id, rom_sha1, slot),
			"valid": false,
			"message": "Empty",
		}
		if row["exists"]:
			var result: Dictionary = load_result(game_id, rom_sha1, slot, data)
			row["valid"] = bool(result["ok"])
			row["message"] = "Ready" if result["ok"] else String(result["message"])
		out.append(row)
	return out


## Creates the same deterministic development party the old battle screen used,
## but puts it into a real save slot so the screen no longer owns that state.
static func create_development_save(data: GameData, slot: int) -> Gen2SaveData:
	if data == null or not _valid_slot(slot):
		return null
	var members: Array = []
	for species: int in [155, 156]:
		var mon: Gen2BattleMon = Gen2BattleMon.create(
			data, species, 5, data.moves_at_level(species, 5)
		)
		if mon == null:
			return null
		members.append(mon)
	return Gen2SaveBattleAdapter.from_battle_party(
		data.id, data.sha1, slot, Gen2Party.create(members), "PLAYER"
	)


## Creates the source-shaped Crystal new-game save. Crystal initializes an
## empty party before the player reaches Elm's Lab; the imported GIVEPOKE
## script creates the first party member later. The optional fourth argument
## remains accepted for callers from the earlier development launcher, but it
## is deliberately ignored so a new save cannot skip the story handoff.
static func create_new_game(
	data: GameData, slot: int, player_name: String, _starter_species: int = -1
) -> Gen2SaveData:
	if data == null or not _valid_slot(slot):
		return null
	if player_name.is_empty() or Gen2Text.encoded_length(player_name) > Gen2SaveData.MAX_PLAYER_NAME:
		return null
	var new_save := Gen2SaveData.new()
	new_save.game_id = data.id
	new_save.rom_sha1 = data.sha1
	new_save.slot = slot
	new_save.player_name = player_name
	new_save.world = Gen2WorldSpawn.new_game_snapshot(data)
	return new_save


static func ensure_development_save(data: GameData, slot: int = 0) -> Dictionary:
	if data == null or not _valid_slot(slot):
		return _failure("cannot create a development save without a cartridge cache")
	if exists(data.id, data.sha1, slot):
		return load_result(data.id, data.sha1, slot, data)
	var created: Gen2SaveData = create_development_save(data, slot)
	if created == null:
		return _failure("the cache cannot create the development party")
	var result: Dictionary = save(created, data)
	if not result["ok"]:
		return result
	result["save"] = created
	return result


static func delete_slot(game_id: StringName, rom_sha1: String, slot: int) -> bool:
	if not exists(game_id, rom_sha1, slot):
		return false
	return DirAccess.remove_absolute(path_for(game_id, rom_sha1, slot)) == OK


static func _valid_slot(slot: int) -> bool:
	return slot >= 0 and slot < SLOT_COUNT


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
