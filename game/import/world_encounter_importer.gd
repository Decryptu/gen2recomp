class_name Gen2WorldEncounterImporter
extends RefCounted

## Imports the normal, swarm, fishing and roaming Generation 2 encounter data.
## Normal and swarm land/water rows are fixed-size map records. Fishing uses a
## pointer table in one ROM bank, while roaming stores a small map graph beside
## the wild encounter routines.

const _NORMAL_TABLES: Array[String] = [
	"grass_johto", "water_johto", "grass_kanto", "water_kanto",
]
const _SWARM_TABLES: Array[String] = ["swarm_grass", "swarm_water"]

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

const _SWARM_ANCHORS: Dictionary = {
	"gold": {
		"swarm_grass": {"first": [10, 2], "last": [3, 49]},
		"swarm_water": {"first": [3, 49], "last": [3, 49]},
	},
	"silver": {
		"swarm_grass": {"first": [10, 2], "last": [3, 49]},
		"swarm_water": {"first": [3, 49], "last": [3, 49]},
	},
	"crystal": {
		"swarm_grass": {"first": [3, 78], "last": [10, 2]},
	},
}

const _ROAM_ANCHORS: Dictionary = {
	"first": [24, 3],
	"last": [5, 9],
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
		"swarm_grass": int(result["counts"]["swarm_grass"]),
		"swarm_water": int(result["counts"]["swarm_water"]),
		"fish_groups": int(result["counts"]["fish_groups"]),
		"roam_maps": int(result["counts"]["roam_maps"]),
	}


static func read_world_encounters(rom: RomFile, layout: Dictionary) -> Dictionary:
	if layout.is_empty():
		return {"ok": false, "message": "No wild encounter layout for %s." % rom.id}
	var configured: Variant = layout.get("wild_encounters", null)
	if not configured is Dictionary:
		return {"ok": false, "message": "Wild encounter offsets are missing for %s." % rom.id}
	var wild_layout: Dictionary = configured

	var grass: Dictionary = {}
	var water: Dictionary = {}
	var swarm_grass: Dictionary = {}
	var swarm_water: Dictionary = {}
	for table_name: String in _NORMAL_TABLES + _SWARM_TABLES:
		var table_result: Dictionary = _read_map_table(rom, layout, wild_layout, table_name)
		if not bool(table_result.get("ok", false)):
			return table_result
		var destination: Dictionary
		match table_name:
			"grass_johto", "grass_kanto":
				destination = grass
			"water_johto", "water_kanto":
				destination = water
			"swarm_grass":
				destination = swarm_grass
			"swarm_water":
				destination = swarm_water
		for map_key: String in table_result["rows"]:
			if destination.has(map_key):
				return _error("Duplicate %s encounter map %s." % [table_name, map_key])
			destination[map_key] = table_result["rows"][map_key]

	var fish_result: Dictionary = _read_fishing_groups(rom, layout, wild_layout)
	if not bool(fish_result.get("ok", false)):
		return fish_result
	var roam_result: Dictionary = _read_roaming_maps(rom, layout, wild_layout)
	if not bool(roam_result.get("ok", false)):
		return roam_result

	return {
		"ok": true,
		"encounters": {
			"grass": grass,
			"water": water,
			"swarm_grass": swarm_grass,
			"swarm_water": swarm_water,
			"fishing": fish_result["fishing"],
			"roaming": roam_result["roaming"],
			"probabilities": {
				"grass": RomLayout.WILD_GRASS_PROBABILITIES,
				"water": RomLayout.WILD_WATER_PROBABILITIES,
			},
		},
		"counts": {
			"grass": grass.size(),
			"water": water.size(),
			"swarm_grass": swarm_grass.size(),
			"swarm_water": swarm_water.size(),
			"fish_groups": int(fish_result["count"]),
			"roam_maps": int(roam_result["count"]),
		},
	}


static func _read_map_table(
	rom: RomFile, layout: Dictionary, configured: Dictionary, table_name: String
) -> Dictionary:
	var offset: int = int(configured.get(table_name, -1))
	var expected_count: int = int(configured.get("%s_count" % table_name, -1))
	var is_grass: bool = table_name in ["grass_johto", "grass_kanto", "swarm_grass"]
	var record_size: int = (
		RomLayout.WILD_GRASS_RECORD_SIZE if is_grass else RomLayout.WILD_WATER_RECORD_SIZE
	)
	if expected_count == 0:
		if offset >= 0 and (not rom.in_bounds(offset) or rom.u8(offset) != RomLayout.WILD_TABLE_END):
			return _error("Empty wild encounter table %s is not terminated." % table_name)
		return {"ok": true, "rows": {}}
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
	var anchor_check: Dictionary = _validate_anchor(
		rom.id, table_name, rows, _SWARM_ANCHORS if table_name in _SWARM_TABLES else _ANCHORS
	)
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
				var entry: Dictionary = _slot(
					rom.u8(slot_base + slot * 2), rom.u8(slot_base + slot * 2 + 1)
				)
				if not bool(entry.get("ok", false)):
					return _error("Invalid %s slot %d on map %s." % [table_name, slot, map_key])
				entry.erase("ok")
				day_slots.append(entry)
			slots.append(day_slots)
		row["slots"] = slots
	else:
		var slots: Array = []
		for slot: int in RomLayout.WILD_WATER_SLOT_COUNT:
			var entry: Dictionary = _slot(
				rom.u8(at + 3 + slot * 2), rom.u8(at + 3 + slot * 2 + 1)
			)
			if not bool(entry.get("ok", false)):
				return _error("Invalid %s slot %d on map %s." % [table_name, slot, map_key])
			entry.erase("ok")
			slots.append(entry)
		row["slots"] = slots
	row["ok"] = true
	return row


static func _read_fishing_groups(
	rom: RomFile, layout: Dictionary, configured: Dictionary
) -> Dictionary:
	var offset: int = int(configured.get("fish_groups", -1))
	var expected_count: int = int(configured.get("fish_group_count", -1))
	if offset < 0 or expected_count != RomLayout.FISH_GROUP_COUNT:
		return _error("Fishing group layout is incomplete.")
	var bank: int = offset / RomFile.BANK_SIZE
	var groups: Array = []
	var data_end: int = offset + expected_count * RomLayout.FISH_GROUP_RECORD_SIZE
	for group: int in expected_count:
		var at: int = offset + group * RomLayout.FISH_GROUP_RECORD_SIZE
		if not rom.in_bounds(at, RomLayout.FISH_GROUP_RECORD_SIZE):
			return _error("Fishing group %d is outside the ROM." % group)
		var chance: int = rom.u8(at)
		if chance <= 0 or chance > 255:
			return _error("Fishing group %d has an invalid chance." % group)
		var rods: Array = []
		for rod: int in RomLayout.FISH_ROD_COUNT:
			var pointer: int = rom.u16le(at + 1 + rod * 2)
			if pointer < 0x4000 or pointer > 0x7FFF:
				return _error("Fishing group %d has an invalid rod pointer." % group)
			var table: Dictionary = _read_fish_table(rom, bank, pointer, group, rod)
			if not bool(table.get("ok", false)):
				return table
			rods.append(table["entries"])
			data_end = maxi(data_end, int(table["end"]))
		groups.append({"chance": chance, "rods": rods})

	if not rom.in_bounds(data_end, RomLayout.FISH_TIME_GROUP_COUNT * RomLayout.FISH_TIME_GROUP_SIZE):
		return _error("Fishing time-group data is outside the ROM.")
	var time_groups: Array = []
	for group: int in RomLayout.FISH_TIME_GROUP_COUNT:
		var at: int = data_end + group * RomLayout.FISH_TIME_GROUP_SIZE
		var day: Dictionary = _slot(rom.u8(at + 1), rom.u8(at))
		var night: Dictionary = _slot(rom.u8(at + 3), rom.u8(at + 2))
		if not bool(day.get("ok", false)) or not bool(night.get("ok", false)):
			return _error("Fishing time group %d has an invalid slot." % group)
		day.erase("ok")
		night.erase("ok")
		time_groups.append({"day": day, "night": night})

	var anchor_check: Dictionary = _validate_fishing_anchors(groups, time_groups)
	if not bool(anchor_check.get("ok", false)):
		return anchor_check
	return {
		"ok": true,
		"count": groups.size(),
		"fishing": {"groups": groups, "time_groups": time_groups},
	}


static func _read_fish_table(
	rom: RomFile, bank: int, pointer: int, group: int, rod: int
) -> Dictionary:
	var cursor: int = RomFile.linear(bank, pointer)
	var entries: Array = []
	var previous_threshold: int = -1
	for _entry_index: int in RomLayout.FISH_MAX_ENTRIES:
		if not rom.in_bounds(cursor, 3):
			return _error("Fishing group %d rod %d is outside the ROM." % [group, rod])
		var threshold: int = rom.u8(cursor)
		if threshold <= previous_threshold:
			return _error("Fishing group %d rod %d has unsorted thresholds." % [group, rod])
		previous_threshold = threshold
		var species: int = rom.u8(cursor + 1)
		var level: int = rom.u8(cursor + 2)
		if species == 0:
			if level < 0 or level >= RomLayout.FISH_TIME_GROUP_COUNT:
				return _error("Fishing group %d rod %d has an invalid time group." % [group, rod])
			entries.append({"threshold": threshold, "time_group": level})
		else:
			var slot: Dictionary = _slot(level, species)
			if not bool(slot.get("ok", false)):
				return _error("Fishing group %d rod %d has an invalid slot." % [group, rod])
			slot.erase("ok")
			slot["threshold"] = threshold
			entries.append(slot)
		if threshold == RomLayout.FISH_TABLE_END:
			return {"ok": true, "entries": entries, "end": cursor + 3}
		cursor += 3
	return _error("Fishing group %d rod %d has no sentinel." % [group, rod])


static func _read_roaming_maps(
	rom: RomFile, layout: Dictionary, configured: Dictionary
) -> Dictionary:
	var offset: int = int(configured.get("roam_maps", -1))
	var expected_count: int = int(configured.get("roam_map_count", -1))
	if offset < 0 or expected_count != RomLayout.ROAM_MAP_COUNT:
		return _error("Roaming map layout is incomplete.")
	var rows: Array = []
	var at: int = offset
	for _row_index: int in expected_count:
		if not rom.in_bounds(at, 3) or rom.u8(at) == RomLayout.ROAM_TABLE_END:
			return _error("Roaming map table ended before its verified count.")
		var group: int = rom.u8(at)
		var number: int = rom.u8(at + 1)
		var map_check: Dictionary = _validate_map(layout, group, number, "roam_maps")
		if not bool(map_check.get("ok", false)):
			return map_check
		var connection_count: int = rom.u8(at + 2)
		if connection_count < 1 or connection_count > 4:
			return _error("Roaming map %d has an invalid connection count." % _row_index)
		at += 3
		var connections: Array = []
		for _connection_index: int in connection_count:
			if not rom.in_bounds(at, 2):
				return _error("Roaming map %d is outside the ROM." % _row_index)
			var target_group: int = rom.u8(at)
			var target_number: int = rom.u8(at + 1)
			map_check = _validate_map(layout, target_group, target_number, "roam_maps")
			if not bool(map_check.get("ok", false)):
				return map_check
			connections.append({"map_group": target_group, "map_number": target_number})
			at += 2
		if not rom.in_bounds(at) or rom.u8(at) != 0:
			return _error("Roaming map %d has no row terminator." % _row_index)
		at += 1
		rows.append({
			"map_group": group,
			"map_number": number,
			"connections": connections,
		})
	if not rom.in_bounds(at) or rom.u8(at) != RomLayout.ROAM_TABLE_END:
		return _error("Roaming map table has no sentinel.")

	var first: Array = [rows[0]["map_group"], rows[0]["map_number"]]
	var last: Dictionary = rows.back()
	var last_pair: Array = [last["map_group"], last["map_number"]]
	if first != _ROAM_ANCHORS["first"] or last_pair != _ROAM_ANCHORS["last"]:
		return _error("Roaming map table has unexpected anchors.")

	var roaming: Variant = configured.get("roaming", null)
	if not roaming is Array or (roaming as Array).is_empty():
		return _error("Roaming Pokémon definitions are missing.")
	var mons: Array = []
	for raw: Variant in roaming as Array:
		if not raw is Dictionary:
			return _error("Roaming Pokémon definition is malformed.")
		var mon: Dictionary = (raw as Dictionary).duplicate(true)
		var species: int = int(mon.get("species", 0))
		var level: int = int(mon.get("level", 0))
		var group: int = int(mon.get("map_group", 0))
		var number: int = int(mon.get("map_number", 0))
		if species < 1 or species > RomLayout.SPECIES_COUNT or level < 1 or level > RomLayout.MAX_LEVEL:
			return _error("Roaming Pokémon definition has invalid battle values.")
		var map_check: Dictionary = _validate_map(layout, group, number, "roaming")
		if not bool(map_check.get("ok", false)):
			return map_check
		mons.append({
			"species": species,
			"level": level,
			"map_group": group,
			"map_number": number,
		})
	return {"ok": true, "count": rows.size(), "roaming": {"maps": rows, "mons": mons}}


static func _validate_fishing_anchors(groups: Array, time_groups: Array) -> Dictionary:
	if groups.size() != RomLayout.FISH_GROUP_COUNT or time_groups.size() != RomLayout.FISH_TIME_GROUP_COUNT:
		return _error("Fishing table counts are incorrect.")
	var shore_old: Dictionary = groups[0]["rods"][0][0]
	if int(shore_old.get("threshold", 0)) != 179 or int(shore_old.get("species", 0)) != 0x81 \
		or int(shore_old.get("level", 0)) != 10:
		return _error("Fishing table has an unexpected Shore Old anchor.")
	var shore_good: Dictionary = groups[0]["rods"][1][0]
	if int(shore_good.get("threshold", 0)) != 89:
		return _error("Fishing table has an unexpected Shore Good anchor.")
	var time_zero: Dictionary = time_groups[0]
	var day: Dictionary = time_zero["day"]
	var night: Dictionary = time_zero["night"]
	if int(day.get("species", 0)) != 0xDE or int(day.get("level", 0)) != 20 \
		or int(night.get("species", 0)) != 0x78 or int(night.get("level", 0)) != 20:
		return _error("Fishing table has an unexpected time-group anchor.")
	if groups[12]["rods"] != groups[10]["rods"]:
		return _error("Fishing table has an unexpected final group alias.")
	return {"ok": true}


static func _slot(level: int, species: int) -> Dictionary:
	if level < 1 or level > RomLayout.MAX_LEVEL:
		return {"ok": false, "reason": "level"}
	if species < 1 or species > RomLayout.SPECIES_COUNT:
		return {"ok": false, "reason": "species"}
	return {"ok": true, "level": level, "species": species}


static func _validate_map(layout: Dictionary, group: int, number: int, table_name: String) -> Dictionary:
	var max_number: int = RomLayout.map_group_count(layout, group)
	if group < 1 or group > RomLayout.MAP_GROUP_COUNT or max_number <= 0 \
		or number < 1 or number > max_number:
		return _error("Wild encounter table %s names invalid map %d/%d." % [table_name, group, number])
	return {"ok": true}


static func _validate_anchor(
	game_id: StringName, table_name: String, rows: Dictionary, anchors: Dictionary
) -> Dictionary:
	var game_anchors: Variant = anchors.get(String(game_id), {})
	if not game_anchors is Dictionary:
		return _error("No wild encounter anchors for %s." % game_id)
	var anchor: Variant = (game_anchors as Dictionary).get(table_name, {})
	if not anchor is Dictionary:
		return _error("Wild encounter anchor is missing for %s." % table_name)
	if rows.is_empty():
		return _error("Wild encounter table %s is empty." % table_name)
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
