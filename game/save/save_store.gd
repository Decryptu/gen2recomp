class_name Gen2SaveStore
extends RefCounted

## User-owned save slots. This is separate from [RomCache], which contains only
## cartridge-derived data and has a different lifecycle.

const ROOT: String = "user://save_slots"

## Where slots are actually read and written, which is [constant ROOT] unless a
## tool moved it. The seam exists because a tool that drives a real battle to its
## end writes the slot it was played from, and a check must never be able to
## overwrite the owner's own save; see [method use_root] and
## `tools/replay_world.gd`.
static var _root: String = ROOT


static func root() -> String:
	return _root


## Points every slot path at [param path]. An empty one restores
## [constant ROOT], which is what a tool does when it is finished.
static func use_root(path: String) -> void:
	_root = ROOT if path.is_empty() else path
## Slots are created on demand rather than preallocated, so this is only a
## ceiling: it keeps a slot number a bounded, validatable thing and stops a
## runaway caller filling the directory. Slot files are still `slot_N.json`,
## so the three slots written before this stay exactly where they were.
const MAX_SLOTS: int = 99
const SLOT_PREFIX: String = "slot_"
const SLOT_SUFFIX: String = ".json"
const BACKUP_SUFFIX: String = ".bak"
const CONTAINER_PREFIX: String = "#gen2save"
const CONTAINER_VERSION: int = 1
# Canonical Crystal Elm's Lab gift records. These values describe the imported
# story choices and are not inserted into a new save before the lab handoff.
const STARTER_LEVEL: int = 5
const STARTER_SPECIES: Array[int] = [152, 155, 158]
const STARTER_ITEM: int = 0xAD
## The development save's wPlayerID. Any fixed value would do; this one is not
## a multiple of ten, so GetTreeScore's OTID half is not degenerate.
const DEVELOPMENT_PLAYER_ID: int = 0x1A2B


static func directory_for(game_id: StringName, rom_sha1: String) -> String:
	return "%s/%s_%s" % [root(), String(game_id), rom_sha1.substr(0, 8)]


static func path_for(game_id: StringName, rom_sha1: String, slot: int) -> String:
	return "%s/%s%d%s" % [
		directory_for(game_id, rom_sha1), SLOT_PREFIX, slot, SLOT_SUFFIX
	]


static func backup_path_for(game_id: StringName, rom_sha1: String, slot: int) -> String:
	return "%s%s" % [path_for(game_id, rom_sha1, slot), BACKUP_SUFFIX]


static func exists(game_id: StringName, rom_sha1: String, slot: int) -> bool:
	if not _valid_slot(slot):
		return false
	return FileAccess.file_exists(path_for(game_id, rom_sha1, slot)) \
		or FileAccess.file_exists(backup_path_for(game_id, rom_sha1, slot))


## Writes the primary copy, then the backup, in `_SaveGameData`'s
## complete-then-copy order. Neither copy relies on rename atomicity, so a crash
## during either write leaves the other one readable.
static func save(save_data: Gen2SaveData, data: GameData) -> Dictionary:
	var validation: Dictionary = Gen2SaveValidator.validate(save_data, data)
	if not validation["ok"]:
		return validation
	var path: String = path_for(save_data.game_id, save_data.rom_sha1, save_data.slot)
	var directory: String = path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return _failure("could not create the save directory")

	var document: String = _wrap(JSON.stringify(save_data.to_dict(), "\t"))
	var primary: Dictionary = _write_file(path, document)
	if not primary["ok"]:
		return primary
	var backup: Dictionary = _write_file(
		backup_path_for(save_data.game_id, save_data.rom_sha1, save_data.slot), document
	)
	if not backup["ok"]:
		return _failure("could not write the backup save")
	return {"ok": true, "message": ""}


## Takes the primary copy and falls back to the backup on any failure, following
## `TryLoadSaveFile`. Unlike the source this never repairs the weak copy, because
## `slots_for()` loads every slot just to draw the menu and a read must not
## write; the next save rewrites both copies.
static func load_result(game_id: StringName, rom_sha1: String, slot: int, data: GameData) -> Dictionary:
	if not _valid_slot(slot):
		return _failure("save slot %d is out of range" % slot)
	var path: String = path_for(game_id, rom_sha1, slot)
	var backup: String = backup_path_for(game_id, rom_sha1, slot)
	var has_primary: bool = FileAccess.file_exists(path)
	var has_backup: bool = FileAccess.file_exists(backup)
	if not has_primary and not has_backup:
		return _failure("save slot %d is empty" % (slot + 1))

	var primary_result: Dictionary = {}
	if has_primary:
		primary_result = _load_copy(path, slot, data)
		if primary_result["ok"]:
			primary_result["recovered"] = false
			return primary_result
	if has_backup:
		var backup_result: Dictionary = _load_copy(backup, slot, data)
		if backup_result["ok"]:
			backup_result["recovered"] = true
			return backup_result
		if not has_primary:
			return backup_result
	return primary_result


## The slots that exist, in slot order. Unlike the fixed-count version this
## returns nothing for a game with no saves, so a caller draws what is there
## and offers to create the rest.
static func slots_for(game_id: StringName, rom_sha1: String, data: GameData) -> Array:
	var out: Array = []
	for slot: int in occupied_slots(game_id, rom_sha1):
		var row: Dictionary = {
			"slot": slot,
			"exists": true,
			"valid": false,
			"label": "",
			"player_name": "",
			"message": "Empty",
		}
		var result: Dictionary = load_result(game_id, rom_sha1, slot, data)
		row["valid"] = bool(result["ok"])
		row["message"] = "Ready" if result["ok"] else String(result["message"])
		if result["ok"]:
			var loaded: Gen2SaveData = result["save"]
			row["label"] = loaded.label
			row["player_name"] = loaded.player_name
		out.append(row)
	return out


## The same row shape [method slots_for] returns, for a slot number with nothing
## on disk. [method slots_for] answers only what exists, so this is what a caller
## targeting a free slot describes it with, and it is the one row whose
## [code]exists[/code] is false.
static func empty_slot_row(slot: int) -> Dictionary:
	return {
		"slot": slot,
		"exists": false,
		"valid": false,
		"label": "",
		"player_name": "",
		"message": "Empty",
	}


## Slot numbers with a primary or backup copy on disk, ascending. Reads the
## directory rather than probing every number, so an empty game costs one
## listing instead of MAX_SLOTS existence checks.
static func occupied_slots(game_id: StringName, rom_sha1: String) -> Array[int]:
	var found: Array[int] = []
	var directory: String = directory_for(game_id, rom_sha1)
	if not DirAccess.dir_exists_absolute(directory):
		return found
	for file_name: String in DirAccess.get_files_at(directory):
		var slot: int = _slot_from_file_name(file_name)
		if slot >= 0 and not found.has(slot):
			found.append(slot)
	found.sort()
	return found


## Accepts the backup copy too, so a slot whose primary was lost still counts
## as occupied, matching [method exists].
static func _slot_from_file_name(file_name: String) -> int:
	var name: String = file_name
	if name.ends_with(BACKUP_SUFFIX):
		name = name.substr(0, name.length() - BACKUP_SUFFIX.length())
	if not name.begins_with(SLOT_PREFIX) or not name.ends_with(SLOT_SUFFIX):
		return -1
	var digits: String = name.substr(
		SLOT_PREFIX.length(), name.length() - SLOT_PREFIX.length() - SLOT_SUFFIX.length()
	)
	if not digits.is_valid_int():
		return -1
	var slot: int = int(digits)
	return slot if _valid_slot(slot) else -1


## The lowest unused slot number, or -1 when the ceiling is reached. Reusing a
## freed number rather than always counting up keeps a player who deletes and
## recreates from drifting towards the cap.
static func next_free_slot(game_id: StringName, rom_sha1: String) -> int:
	var used: Array[int] = occupied_slots(game_id, rom_sha1)
	for slot: int in MAX_SLOTS:
		if not used.has(slot):
			return slot
	return -1


## Renames a slot in place. The label lives in the save itself rather than a
## sidecar, so an exported file carries its own name.
static func rename_slot(
	game_id: StringName, rom_sha1: String, slot: int, new_label: String, data: GameData
) -> Dictionary:
	var trimmed: String = new_label.strip_edges()
	if trimmed.length() > Gen2SaveData.MAX_LABEL:
		return _failure("a slot name is at most %d characters" % Gen2SaveData.MAX_LABEL)
	var result: Dictionary = load_result(game_id, rom_sha1, slot, data)
	if not result["ok"]:
		return result
	var loaded: Gen2SaveData = result["save"]
	loaded.label = trimmed
	return save(loaded, data)


## Copies the primary slot file to a player-chosen path. The container header
## goes with it, so an exported file is exactly what [method import_slot]
## expects back and is checksum-checked on the way in.
static func export_slot(
	game_id: StringName, rom_sha1: String, slot: int, target_path: String
) -> Dictionary:
	if not exists(game_id, rom_sha1, slot):
		return _failure("save slot %d is empty" % (slot + 1))
	var source: String = path_for(game_id, rom_sha1, slot)
	if not FileAccess.file_exists(source):
		source = backup_path_for(game_id, rom_sha1, slot)
	var reader: FileAccess = FileAccess.open(source, FileAccess.READ)
	if reader == null:
		return _failure("the save could not be read for export")
	var document: String = reader.get_as_text()
	reader.close()
	var written: Dictionary = _write_file(target_path, document)
	if not written["ok"]:
		return _failure("the save could not be written to %s" % target_path)
	return {"ok": true, "message": "", "path": target_path}


## Reads an exported file into the next free slot. The file is validated
## against the selected cache before anything is written, and its recorded
## game and cartridge must match, so one cartridge's save cannot land under
## another's.
static func import_slot(source_path: String, data: GameData) -> Dictionary:
	if data == null:
		return _failure("no cartridge cache is selected")
	var reader: FileAccess = FileAccess.open(source_path, FileAccess.READ)
	if reader == null:
		return _failure("that file could not be read")
	var text: String = reader.get_as_text()
	reader.close()
	var container: Dictionary = _unwrap(text)
	if not container["ok"]:
		return _failure(String(container["message"]))
	var parser := JSON.new()
	if parser.parse(String(container["payload"])) != OK:
		return _failure("that file is not valid save data")
	var candidate: Gen2SaveData = Gen2SaveData.from_dict(parser.data)
	if candidate == null:
		return _failure("that file is not valid save data")
	if candidate.game_id != data.id or candidate.rom_sha1 != data.sha1:
		return _failure("that save belongs to a different cartridge")
	var slot: int = next_free_slot(data.id, data.sha1)
	if slot < 0:
		return _failure("every save slot is in use")
	candidate.slot = slot
	var result: Dictionary = save(candidate, data)
	if not result["ok"]:
		return result
	return {"ok": true, "message": "", "slot": slot, "save": candidate}


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
	var development: Gen2SaveData = Gen2SaveBattleAdapter.from_battle_party(
		data.id, data.sha1, slot, Gen2Party.create(members), "PLAYER"
	)
	if development != null:
		## Fixed rather than rolled, so a preview or a test that reads
		## GetTreeScore through this save reproduces itself.
		development.player_id = DEVELOPMENT_PLAYER_ID
	return development


## Creates the source-shaped Crystal new-game save. Crystal initializes an
## empty party before the player reaches Elm's Lab; the imported GIVEPOKE
## script creates the first party member later. The optional fourth argument
## remains accepted for callers from the earlier development launcher, but it
## is deliberately ignored so a new save cannot skip the story handoff.
##
## [param random] rolls wPlayerID. It is the one roll in this project that is
## an identity rather than a game event, so an absent generator randomizes here
## instead of being refused; pass one when a run has to reproduce itself, since
## GetTreeScore reads the result.
static func create_new_game(
	data: GameData, slot: int, player_name: String, _starter_species: int = -1,
	random: RandomNumberGenerator = null
) -> Gen2SaveData:
	if data == null or not _valid_slot(slot):
		return null
	if player_name.is_empty() or Gen2Text.encoded_length(player_name) > Gen2SaveData.MAX_PLAYER_NAME:
		return null
	var generator := random if random != null else RandomNumberGenerator.new()
	if random == null:
		generator.randomize()
	var new_save := Gen2SaveData.new()
	new_save.game_id = data.id
	new_save.rom_sha1 = data.sha1
	new_save.slot = slot
	new_save.player_name = player_name
	new_save.player_id = generator.randi_range(0, 0xFFFF)
	# Rolled beside wPlayerID and never changed after, so a run is reproducible
	# from its first frame. Zero would read as "unseeded", so it is rerolled.
	while new_save.run_seed == 0:
		new_save.run_seed = generator.randi()
	new_save.run_mods = Gen2ModHost.instance().loaded_mods()
	new_save.world = Gen2WorldSpawn.new_game_snapshot(data)
	if new_save.world != null:
		new_save.world.random_seed = new_save.run_seed
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
	var removed: bool = false
	for path: String in [
		path_for(game_id, rom_sha1, slot), backup_path_for(game_id, rom_sha1, slot)
	]:
		if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) == OK:
			removed = true
	return removed


static func _write_file(target: String, document: String) -> Dictionary:
	var temporary: String = "%s.tmp" % target
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _failure("could not open the save for writing")
	file.store_string(document)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK or DirAccess.rename_absolute(temporary, target) != OK:
		DirAccess.remove_absolute(temporary)
		return _failure("could not finish writing the save")
	return {"ok": true, "message": ""}


static func _load_copy(path: String, slot: int, data: GameData) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("save slot %d could not be opened" % (slot + 1))
	var text: String = file.get_as_text()
	file.close()
	var container: Dictionary = _unwrap(text)
	if not container["ok"]:
		return _failure("save slot %d: %s" % [slot + 1, container["message"]])
	var parser := JSON.new()
	var parse_error: Error = parser.parse(String(container["payload"]))
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


static func _wrap(payload: String) -> String:
	return "%s %d %d\n%s" % [CONTAINER_PREFIX, CONTAINER_VERSION, _checksum(payload), payload]


## Returns the payload of a slot file. A file without the header line predates
## the container and is accepted unchecked.
static func _unwrap(text: String) -> Dictionary:
	if not text.begins_with("%s " % CONTAINER_PREFIX):
		return {"ok": true, "payload": text, "message": ""}
	var break_index: int = text.find("\n")
	if break_index < 0:
		return {"ok": false, "payload": "", "message": "the save header is incomplete"}
	var header: PackedStringArray = text.substr(0, break_index).split(" ", false)
	var payload: String = text.substr(break_index + 1)
	if header.size() != 3 or not header[2].is_valid_int() or int(header[1]) != CONTAINER_VERSION:
		return {"ok": false, "payload": "", "message": "unsupported save container"}
	if int(header[2]) != _checksum(payload):
		return {"ok": false, "payload": "", "message": "the save data failed its checksum"}
	return {"ok": true, "payload": payload, "message": ""}


## `Checksum` in engine/menus/save.asm: a wrapping 16-bit sum of every byte.
static func _checksum(payload: String) -> int:
	var sum: int = 0
	for byte: int in payload.to_utf8_buffer():
		sum = (sum + byte) & 0xFFFF
	return sum


static func _valid_slot(slot: int) -> bool:
	return slot >= 0 and slot < MAX_SLOTS


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
