class_name Gen2SaveStore
extends RefCounted

## User-owned save slots. This is separate from [RomCache], which contains only
## cartridge-derived data and has a different lifecycle.

const ROOT: String = "user://save_slots"
const SLOT_COUNT: int = 3
const STARTER_LEVEL: int = 5
const STARTER_SPECIES: Array[int] = [152, 155, 158]
const STARTER_ITEM: int = 0xAD


static func path_for(game_id: StringName, rom_sha1: String, slot: int) -> String:
	return "%s/%s_%s/slot_%d.json" % [ROOT, String(game_id), rom_sha1.substr(0, 8), slot]


static func exists(game_id: StringName, rom_sha1: String, slot: int) -> bool:
	return _valid_slot(slot) and FileAccess.file_exists(path_for(game_id, rom_sha1, slot))


static func save(save: Gen2SaveData, data: GameData) -> Dictionary:
	var validation: Dictionary = Gen2SaveValidator.validate(save, data)
	if not validation["ok"]:
		return validation
	var path: String = path_for(save.game_id, save.rom_sha1, save.slot)
	var directory: String = path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return _failure("could not create the save directory")

	var temporary: String = "%s.tmp" % path
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _failure("could not open the save for writing")
	file.store_string(JSON.stringify(save.to_dict(), "\t"))
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
	var save: Gen2SaveData = Gen2SaveData.from_dict(raw)
	if save == null:
		return _failure("save slot %d is not valid JSON data" % (slot + 1))
	var validation: Dictionary = Gen2SaveValidator.validate(save, data)
	if not validation["ok"]:
		return _failure("save slot %d: %s" % [slot + 1, validation["message"]])
	return {"ok": true, "message": "", "save": save}


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


## Creates the party obtained from Professor Elm's three starter balls. The
## project save model does not own the player's trainer ID yet, so the starter
## keeps the canonical zero value for its OT ID until that field exists.
static func create_new_game(
	data: GameData, slot: int, player_name: String, starter_species: int
) -> Gen2SaveData:
	if data == null or not _valid_slot(slot):
		return null
	if player_name.is_empty() or Gen2Text.encoded_length(player_name) > Gen2SaveData.MAX_PLAYER_NAME:
		return null
	if not STARTER_SPECIES.has(starter_species):
		return null
	if data.species(starter_species).is_empty() or data.item(STARTER_ITEM).is_empty():
		return null
	var known_moves: Array = data.moves_at_level(starter_species, STARTER_LEVEL)
	var mon: Gen2BattleMon = Gen2BattleMon.create(
		data, starter_species, STARTER_LEVEL, known_moves, Gen2BattleMon.PERFECT_DVS, {}, STARTER_ITEM
	)
	if mon == null:
		return null
	var save := Gen2SaveData.new()
	save.game_id = data.id
	save.rom_sha1 = data.sha1
	save.slot = slot
	save.player_name = player_name
	var saved_mon: Gen2SaveMon = Gen2SaveBattleAdapter.from_battle_mon(mon)
	saved_mon.nickname = String(data.species(starter_species).get("name", ""))
	saved_mon.original_trainer = player_name
	save.party.append(saved_mon)
	return save


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
