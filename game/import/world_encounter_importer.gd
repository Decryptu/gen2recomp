class_name Gen2WorldEncounterImporter
extends RefCounted

## Imports the four normal Generation 2 wild encounter tables. The cartridge
## stores map group and map number in every fixed-size record, so the cache is
## keyed by that same pair rather than by the map header's fishing group.
## Swarm tables are separate data selected by event state and remain outside
## this first normal encounter slice.

const _TABLES: Array[String] = [
	"grass_johto", "water_johto", "grass_kanto", "water_kanto",
]

const _ANCHORS: Dictionary = {
	"gold": {
		"grass_johto": {"first": [3, 2], "last": [19, 2]},
		"water_johto": {"first": [3, 22], "last": [15, 1]},
		"grass_kanto": {"first": [3, 75], "last": [19, 1]},
		"water_kanto": {"first": [7, 12], "last": [15, 2]},
	},
	"silver": {
		"grass_johto": {"first": [3, 2], "last": [19, 2]},
		"water_johto": {"first": [3, 22], "last": [15, 1]},
		"grass_kanto": {"first": [3, 75], "last": [19, 1]},
		"water_kanto": {"first": [7, 12], "last": [15, 2]},
	},
	"crystal": {
		"grass_johto": {"first": [3, 2], "last": [19, 2]},
		"water_johto": {"first": [3, 22], "last": [19, 2]},
		"grass_kanto": {"first": [3, 84], "last": [19, 1]},
		"water_kanto": {"first": [3, 83], "last": [6, 8]},
	},
}


static func verify_layout(rom: RomFile) -> Dictionary:
	var result: Dictionary = read_world_encounters(rom, RomLayout.for_id(rom.id))
	if not bool(result.get("ok", false)):
		return {"ok": false, "message": String(result.get("message", "Wild encounter data failed validation."))}
	return {"ok": true, "message": ""}


static func import_to_cache(
	rom: RomFile, layout: Dictionary, directory: String
) -> Dictionary:
	var result: Dictionary = read_world_encounters(rom, layout)
	if not bool(result.get("ok", false)):
		return result
	if not RomCache.write_json(RomCache.world_encounters_path(directory), result["encounters"]):
		return {"ok": false, "message": "Could not write wild encounter data."}
	return {
		"ok": true,
		"grass": int(result["counts"]["grass"]),
		"water": int(result["counts"]["water"]),
	}


static func read_world_encounters(rom: RomFile, layout: Dictionary) -> Dictionary:
	if layout.is_empty():
		return {"ok": false, "message": "No wild encounter layout for %s." % rom.id}
	var configured: Variant = layout.get("wild_encounters", null)
	if not configured is Dictionary:
		return {"ok": false, "message": "Wild encounter offsets are missing for %s." % rom.id}

	var grass: Dictionary = {}
	var water: Dictionary = {}
	for table_name: String in _TABLES:
		var table_result: Dictionary = _read_table(rom, layout, table_name)
		if not bool(table_result.get("ok", false)):
			return table_result
		var destination: Dictionary = grass if table_name.begins_with("grass") else water
		for map_key: String in table_result["rows"]:
			if destination.has(map_key):
				return _error("Duplicate %s encounter map %s." % [table_name, map_key])
			destination[map_key] = table_result["rows"][map_key]

	return {
		"ok": true,
		"encounters": {
			"grass": grass,
			"water": water,
			"probabilities": {
				"grass": RomLayout.WILD_GRASS_PROBABILITIES,
				"water": RomLayout.WILD_WATER_PROBABILITIES,
			},
		},
		"counts": {"grass": grass.size(), "water": water.size()},
	}


static func _read_table(rom: RomFile, layout: Dictionary, table_name: String) -> Dictionary:
	var configured: Dictionary = layout["wild_encounters"]
	var offset: int = int(configured.get(table_name, -1))
	var expected_count: int = int(configured.get("%s_count" % table_name, -1))
	var is_grass: bool = table_name.begins_with("grass")
	var record_size: int = (
		RomLayout.WILD_GRASS_RECORD_SIZE if is_grass else RomLayout.WILD_WATER_RECORD_SIZE
	)
	if offset < 0 or expected_count < 0:
		return _error("Wild encounter layout is incomplete for %s." % table_name)

	var rows: Dictionary = {}
	var at: int = offset
	while true:
		if not rom.in_bounds(at):
			return _error("Wild encounter table %s has no sentinel." % table_name)
		if rom.u8(at) == RomLayout.WILD_TABLE_END:
			break
		if rows.size() >= expected_count:
			return _error("Wild encounter table %s exceeds its verified count." % table_name)
		if not rom.in_bounds(at, record_size):
			return _error("Wild encounter record %s is outside the ROM." % table_name)

		var group: int = rom.u8(at)
		var number: int = rom.u8(at + 1)
		var map_check: Dictionary = _validate_map(layout, group, number, table_name)
		if not bool(map_check.get("ok", false)):
			return map_check
		var map_key: String = "%d:%d" % [group, number]
		if rows.has(map_key):
			return _error("Wild encounter table %s repeats map %s." % [table_name, map_key])

		var row: Dictionary = _read_record(rom, at, is_grass, table_name, map_key)
		if not bool(row.get("ok", false)):
			return row
		row.erase("ok")
		rows[map_key] = row
		at += record_size

	if rows.size() != expected_count:
		return _error("Wild encounter table %s has %d records, expected %d." % [
		table_name, rows.size(), expected_count,
	])

	var anchor_check: Dictionary = _validate_anchor(rom.id, table_name, rows)
	if not bool(anchor_check.get("ok", false)):
		return anchor_check
	return {"ok": true, "rows": rows}


static func _read_record(
	rom: RomFile, at: int, is_grass: bool, table_name: String, map_key: String
) -> Dictionary:
	var rate: int = rom.u8(at + 2)
	var row: Dictionary = {"map": map_key, "rate": rate}
	if is_grass:
		var rates: Array[int] = []
		for time_of_day: int in RomLayout.WILD_TIME_COUNT:
			rates.append(rom.u8(at + 2 + time_of_day))
		row["rates"] = rates
		var slots: Array = []
		for time_of_day: int in RomLayout.WILD_TIME_COUNT:
			var day_slots: Array = []
			var slot_base: int = at + 5 + time_of_day * RomLayout.WILD_GRASS_SLOT_COUNT * 2
			for slot: int in RomLayout.WILD_GRASS_SLOT_COUNT:
				var entry: Dictionary = _slot(rom.u8(slot_base + slot * 2), rom.u8(slot_base + slot * 2 + 1))
				if not bool(entry.get("ok", false)):
					return _error("Invalid %s slot %d on map %s." % [table_name, slot, map_key])
				entry.erase("ok")
				day_slots.append(entry)
			slots.append(day_slots)
		row["slots"] = slots
	else:
		var slots: Array = []
		for slot: int in RomLayout.WILD_WATER_SLOT_COUNT:
			var entry: Dictionary = _slot(rom.u8(at + 3 + slot * 2), rom.u8(at + 3 + slot * 2 + 1))
			if not bool(entry.get("ok", false)):
				return _error("Invalid %s slot %d on map %s." % [table_name, slot, map_key])
			entry.erase("ok")
			slots.append(entry)
		row["slots"] = slots
	row["ok"] = true
	return row


static func _slot(level: int, species: int) -> Dictionary:
	if level < 1 or level > RomLayout.MAX_LEVEL:
		return {"ok": false, "reason": "level"}
	if species < 1 or species > RomLayout.SPECIES_COUNT:
		return {"ok": false, "reason": "species"}
	return {"ok": true, "level": level, "species": species}


static func _validate_map(layout: Dictionary, group: int, number: int, table_name: String) -> Dictionary:
	var max_number: int = RomLayout.map_group_count(layout, group)
	if group < 1 or group > RomLayout.MAP_GROUP_COUNT or max_number <= 0 or number < 1 or number > max_number:
		return _error("Wild encounter table %s names invalid map %d/%d." % [table_name, group, number])
	return {"ok": true}


static func _validate_anchor(game_id: StringName, table_name: String, rows: Dictionary) -> Dictionary:
	var game_anchors: Variant = _ANCHORS.get(String(game_id), {})
	if not game_anchors is Dictionary:
		return _error("No wild encounter anchors for %s." % game_id)
	var anchor: Variant = (game_anchors as Dictionary).get(table_name, {})
	if not anchor is Dictionary or rows.is_empty():
		return _error("Wild encounter anchor is missing for %s." % table_name)
	var keys: Array = rows.keys()
	var first: Array = _map_key_to_pair(String(keys[0]))
	var last: Array = _map_key_to_pair(String(keys[-1]))
	if first != anchor["first"] or last != anchor["last"]:
		return _error("Wild encounter table %s has unexpected map anchors." % table_name)
	return {"ok": true}


static func _map_key_to_pair(key: String) -> Array:
	var parts: PackedStringArray = key.split(":")
	return [int(parts[0]), int(parts[1])] if parts.size() == 2 else []


static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}
