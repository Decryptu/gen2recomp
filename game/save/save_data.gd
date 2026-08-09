class_name Gen2SaveData
extends RefCounted

## One project save slot, independent of scenes and battle state.
##
## The game and ROM identifiers prevent a save from silently being opened with
## the wrong cartridge cache. The schema is versioned so a future save shape
## can be refused or migrated deliberately instead of being guessed at.

const FORMAT_VERSION: int = 4
const LEGACY_FORMAT_VERSION: int = 1
const MAX_PARTY: int = Gen2Party.MAX_SIZE
const MAX_PLAYER_NAME: int = 10
## The player's own name for the slot, which the cartridge had no concept of:
## it held one save and named it after the player. Empty means fall back to
## [member player_name], so a slot always has something to show.
const MAX_LABEL: int = 24
const BOX_COUNT: int = 14
const BOX_CAPACITY: int = Gen2SaveBox.CAPACITY

var format_version: int = FORMAT_VERSION
var game_id: StringName = &""
var rom_sha1: String = ""
var slot: int = -1
var player_name: String = ""
## wPlayerID, the two bytes wPlayerData opens with in both pins. Rolled once
## when a game starts and never changed after; GetTreeScore is the first thing
## in this project to read it.
var player_id: int = 0
var label: String = ""
var party: Array = []
var boxes: Array = []
var world: Gen2WorldSnapshot = null
var boxes_shape_valid: bool = true


func _init() -> void:
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
		"label": label,
		"party": saved_party,
		"boxes": saved_boxes,
		"world": world.to_dict() if world != null else {},
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
	return out


## Converts an older project save shape into the current schema, one version
## step at a time so a version 1 file reaches the current one through every
## step rather than skipping to it. Each step adds only what its version
## lacked; a missing world snapshot stays missing throughout.
##
## Version 1 had no PC-box field. Version 2 had no slot label. Version 3 had no
## player trainer ID; it migrates to zero rather than being invented, since a
## rolled ID would silently change the headbutt encounters of an existing save.
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
		var slot: int = box.first_empty_slot()
		if slot >= 0:
			return {"ok": true, "box": box_index, "slot": slot}
	return {"ok": false, "reason": &"storage_full"}


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
	label = copied.label
	party = copied.party
	boxes = copied.boxes
	world = copied.world
	boxes_shape_valid = copied.boxes_shape_valid
	return true
