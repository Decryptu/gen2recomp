class_name Gen2SaveData
extends RefCounted

## One project save slot, independent of scenes and battle state.
##
## The game and ROM identifiers prevent a save from silently being opened with
## the wrong cartridge cache. The schema is versioned so a future save shape
## can be refused or migrated deliberately instead of being guessed at.

const FORMAT_VERSION: int = 6
const LEGACY_FORMAT_VERSION: int = 1
const MAX_PARTY: int = Gen2Party.MAX_SIZE
const MAX_PLAYER_NAME: int = 10
## The player's own name for the slot, which the cartridge had no concept of:
## it held one save and named it after the player. Empty means fall back to
## [member player_name], so a slot always has something to show.
const MAX_LABEL: int = 24
const BOX_COUNT: int = 14
const BOX_CAPACITY: int = Gen2SaveBox.CAPACITY

## `constants/wram_constants.asm`: `PLAYERGENDER_FEMALE_F` is bit 0 of
## wPlayerGender, so the whole byte is 0 for Chris and 1 for Kris.
const GENDER_MALE: int = 0
const GENDER_FEMALE: int = 1

var format_version: int = FORMAT_VERSION
var game_id: StringName = &""
var rom_sha1: String = ""
var slot: int = -1
var player_name: String = ""
## wPlayerID, the two bytes wPlayerData opens with in both pins. Rolled once
## when a game starts and never changed after; GetTreeScore is the first thing
## in this project to read it.
var player_id: int = 0
## wPlayerGender, whose bit 0 is `PLAYERGENDER_FEMALE_F`. Crystal only: pokegold
## ships no wPlayerGender and no KrisStateSprites, so a Gold or Silver player is
## always male and nothing reads this there.
var gender: int = GENDER_MALE
## wGameTimeHours .. wGameTimeFrames, the play timer the trainer card prints.
var game_time: Gen2GameTime = null
var label: String = ""
var party: Array = []
var boxes: Array = []
var world: Gen2WorldSnapshot = null
## Per-slot, per-mod JSON objects. This namespace travels with the save.
var mods: Dictionary = {}
## What names the run beside the state it produced: the seed the world's
## generators are built from and the mods that were loaded when the slot was
## last written (`Gen2ModHost.loaded_mods`). Zero and empty read as "not
## recorded", which is what every slot written before this existed says.
var run_seed: int = 0
var run_mods: Array = []
## The registered mod settings this run was created with, keyed by mod id and
## option key. The installation-wide options file is only the template for a
## new run; once a slot exists its effective settings live here so reopening it
## cannot silently change the state that produced the save.
var run_options: Dictionary = {}
## The divergence flags and difficulty this run is played under. Its own field
## rather than a mod's, because it changes what the engine does: a run recorded
## under one set of rules did not produce the state a different set would.
## Null reads as "not recorded", which every slot written before it says, and
## adopts the installation's once.
var run_rules: Gen2Rules = null
var boxes_shape_valid: bool = true


func _init() -> void:
	game_time = Gen2GameTime.new()
	for _box_index: int in BOX_COUNT:
		boxes.append(Gen2SaveBox.new())


func to_dict() -> Dictionary:
	var saved_party: Array = []
	for mon: Gen2SaveMon in party:
		saved_party.append(mon.to_dict() if mon != null else {})
	var saved_boxes: Array = []
	for box: Gen2SaveBox in boxes:
		saved_boxes.append(box.to_dict() if box != null else [])
	return {
		"format_version": FORMAT_VERSION,
		"game_id": String(game_id),
		"rom_sha1": rom_sha1,
		"slot": slot,
		"player_name": player_name,
		"player_id": player_id,
		"gender": gender,
		"game_time": game_time.to_dict() if game_time != null else Gen2GameTime.new().to_dict(),
		"label": label,
		"party": saved_party,
		"boxes": saved_boxes,
		"world": world.to_dict() if world != null else {},
		"mods": mods.duplicate(true),
		"run": {
			"seed": run_seed,
			"mods": run_mods.duplicate(true),
			"mod_options": run_options.duplicate(true),
			"rules": run_rules.to_dict() if run_rules != null else {},
		},
	}


## Parses the serialized shape without claiming that the data is usable. The
## selected cartridge cache is needed for species, move, item and HP checks.
static func from_dict(raw: Variant) -> Gen2SaveData:
	if not raw is Dictionary:
		return null
	var migration: Dictionary = migrate_dict(raw)
	if not bool(migration.get("ok", false)):
		return null
	var source: Dictionary = migration["data"]
	var out := Gen2SaveData.new()
	out.format_version = FORMAT_VERSION
	out.game_id = StringName(source.get("game_id", ""))
	out.rom_sha1 = String(source.get("rom_sha1", ""))
	out.slot = int(source.get("slot", -1))
	out.player_name = String(source.get("player_name", ""))
	out.player_id = int(source.get("player_id", 0)) & 0xFFFF
	out.gender = GENDER_FEMALE if int(source.get("gender", GENDER_MALE)) & 1 else GENDER_MALE
	out.game_time = Gen2GameTime.parse(source.get("game_time", {}))
	out.label = String(source.get("label", ""))
	var raw_party: Variant = source.get("party", [])
	if raw_party is Array:
		for raw_mon: Variant in raw_party as Array:
			out.party.append(Gen2SaveMon.from_dict(raw_mon))
	var raw_boxes: Variant = source.get("boxes", null)
	out.boxes_shape_valid = raw_boxes is Array and (raw_boxes as Array).size() == BOX_COUNT
	if raw_boxes is Array:
		var boxes_source: Array = raw_boxes as Array
		for box_index: int in BOX_COUNT:
			var box: Gen2SaveBox = Gen2SaveBox.from_dict(
				boxes_source[box_index] if box_index < boxes_source.size() else null
			)
			if box == null:
				out.boxes_shape_valid = false
				out.boxes[box_index] = Gen2SaveBox.new()
			else:
				out.boxes[box_index] = box
	else:
		out.boxes_shape_valid = false
	var raw_world: Variant = source.get("world", {})
	if raw_world is Dictionary and not (raw_world as Dictionary).is_empty():
		out.world = Gen2WorldSnapshot.from_dict(raw_world)
	var raw_mods: Variant = source.get("mods", {})
	if raw_mods is Dictionary:
		for raw_id: Variant in raw_mods:
			var id: String = String(raw_id)
			var value: Variant = raw_mods[raw_id]
			if _valid_mod_id(id) and value is Dictionary:
				out.mods[StringName(id)] = (value as Dictionary).duplicate(true)
	var raw_run: Variant = source.get("run", {})
	if raw_run is Dictionary:
		out.run_seed = int((raw_run as Dictionary).get("seed", 0))
		var raw_run_mods: Variant = (raw_run as Dictionary).get("mods", [])
		if raw_run_mods is Array:
			for entry: Variant in raw_run_mods as Array:
				if entry is Dictionary and _valid_mod_id(String((entry as Dictionary).get("id", ""))):
					out.run_mods.append({
						"id": String((entry as Dictionary).get("id", "")),
						"version": String((entry as Dictionary).get("version", "")),
					})
		var raw_rules: Variant = (raw_run as Dictionary).get("rules", {})
		if raw_rules is Dictionary and not (raw_rules as Dictionary).is_empty():
			out.run_rules = Gen2Rules.parse(raw_rules)
		var raw_run_options: Variant = (raw_run as Dictionary).get("mod_options", {})
		if raw_run_options is Dictionary:
			for raw_id: Variant in raw_run_options:
				var id: String = String(raw_id)
				var options: Variant = (raw_run_options as Dictionary)[raw_id]
				if _valid_mod_id(id) and options is Dictionary:
					out.run_options[StringName(id)] = (options as Dictionary).duplicate(true)
	return out


## Converts an older project save shape into the current schema, one version
## step at a time so a version 1 file reaches the current one through every
## step rather than skipping to it. Each step adds only what its version
## lacked; a missing world snapshot stays missing throughout.
##
## Version 1 had no PC-box field. Version 2 had no slot label. Version 3 had no
## player trainer ID; it migrates to zero rather than being invented, since a
## rolled ID would silently change the headbutt encounters of an existing save.
## Version 4 had neither gender nor a play timer; both migrate to the value a
## new game starts with, male and 0:00, since neither can be recovered.
## Version 5 had no per-mod namespace.
##
## The `run` block joined version 6 after it shipped and is not a version of its
## own: it defaults to no seed, mod list, mod-option snapshot or rules, which is
## the truth about a slot written before it existed rather than a value worth
## inventing.
static func migrate_dict(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {"ok": false, "message": "save data is not an object"}
	var source: Dictionary = raw as Dictionary
	var version: int = int(source.get("format_version", -1))
	if version == FORMAT_VERSION:
		return {"ok": true, "data": source.duplicate(true), "migrated": false}
	if version < LEGACY_FORMAT_VERSION or version > FORMAT_VERSION:
		return {"ok": false, "message": "unsupported save format %d" % version}
	var migrated: Dictionary = source.duplicate(true)
	if version < 2 and not migrated.has("boxes"):
		migrated["boxes"] = _empty_boxes()
	if version < 3 and not migrated.has("label"):
		migrated["label"] = ""
	if version < 4 and not migrated.has("player_id"):
		migrated["player_id"] = 0
	if version < 5:
		if not migrated.has("gender"):
			migrated["gender"] = GENDER_MALE
		if not migrated.has("game_time"):
			migrated["game_time"] = Gen2GameTime.new().to_dict()
	if version < 6 and not migrated.has("mods"):
		migrated["mods"] = {}
	migrated["format_version"] = FORMAT_VERSION
	return {"ok": true, "data": migrated, "migrated": true}


static func _empty_boxes() -> Array:
	var empty_boxes: Array = []
	for _box_index: int in BOX_COUNT:
		var empty_slots: Array = []
		for _slot: int in BOX_CAPACITY:
			empty_slots.append(null)
		empty_boxes.append(empty_slots)
	return empty_boxes


func first_empty_box_slot() -> Dictionary:
	for box_index: int in boxes.size():
		var box: Gen2SaveBox = boxes[box_index]
		if box == null:
			continue
		var empty_slot: int = box.first_empty_slot()
		if empty_slot >= 0:
			return {"ok": true, "box": box_index, "slot": empty_slot}
	return {"ok": false, "reason": &"storage_full"}


## `_GetVarAction`'s `.BoxFreeSpace`, which is `MONS_PER_BOX - [sBoxCount]`. The
## save model keeps no current-box pointer, so the box a deposit would land in is
## the one [method first_empty_box_slot] picks; a full storage answers 0, which is
## the same refusal the source's zero gives every script that reads the var.
func box_free_space() -> int:
	var destination: Dictionary = first_empty_box_slot()
	if not bool(destination.get("ok", false)):
		return 0
	var box: Gen2SaveBox = boxes[int(destination["box"])]
	return Gen2SaveBox.CAPACITY - box.occupied_count()


func add_party_or_box(mon: Gen2SaveMon) -> Dictionary:
	if mon == null:
		return {"ok": false, "reason": &"missing_pokemon"}
	if party.size() < MAX_PARTY:
		party.append(mon)
		return {"ok": true, "destination": &"party", "party_index": party.size() - 1}
	var destination: Dictionary = first_empty_box_slot()
	if not bool(destination.get("ok", false)):
		return destination
	var box: Gen2SaveBox = boxes[int(destination["box"])]
	var placed: Dictionary = box.put(mon, int(destination["slot"]))
	if not bool(placed.get("ok", false)):
		return {"ok": false, "reason": placed.get("reason", &"box_insert_failed")}
	return {
		"ok": true,
		"destination": &"box",
		"box": int(destination["box"]),
		"slot": int(destination["slot"]),
	}


## Replaces this shared runtime save with a validated candidate while keeping
## the object identity that GameRuntime and open screens already reference.
func copy_from(source: Gen2SaveData) -> bool:
	if source == null:
		return false
	var copied: Gen2SaveData = Gen2SaveData.from_dict(source.to_dict())
	if copied == null:
		return false
	format_version = copied.format_version
	game_id = copied.game_id
	rom_sha1 = copied.rom_sha1
	slot = copied.slot
	player_name = copied.player_name
	player_id = copied.player_id
	gender = copied.gender
	game_time = copied.game_time
	label = copied.label
	party = copied.party
	boxes = copied.boxes
	world = copied.world
	mods = copied.mods.duplicate(true)
	run_seed = copied.run_seed
	run_mods = copied.run_mods.duplicate(true)
	run_options = copied.run_options.duplicate(true)
	run_rules = copied.run_rules.duplicate_rules() if copied.run_rules != null else null
	boxes_shape_valid = copied.boxes_shape_valid
	return true


func mod_data(id: StringName) -> Dictionary:
	var value: Variant = mods.get(id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func set_mod_data(id: StringName, value: Dictionary) -> Dictionary:
	if not _valid_mod_id(String(id)):
		return {"ok": false, "reason": &"invalid_mod_save_id"}
	var encoded: String = JSON.stringify(value)
	if encoded.to_utf8_buffer().size() > 65536:
		return {"ok": false, "reason": &"mod_save_too_large"}
	if value.is_empty():
		mods.erase(id)
	else:
		mods[id] = value.duplicate(true)
	return {"ok": true, "id": id}


static func _valid_mod_id(id: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[a-z0-9][a-z0-9_-]*$")
	return regex.search(id) != null
