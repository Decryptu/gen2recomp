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

## The first and last TreeMonMaps rows and the whole of RockMonMaps, as
## `(group, number, set)`. The set numbers differ between the profiles because
## the TREEMON_SET_* order does: Crystal's ILEX_FOREST is FOREST 6 where
## Gold and Silver's is FOREST 1 (constants/pokemon_data_constants.asm).
const _TREEMON_ANCHORS: Dictionary = {
	"gold": {
		"tree_first": [24, 1, 1], "tree_last": [3, 44, 1],
		"rock": [[22, 3, 3], [22, 1, 3], [3, 70, 3], [3, 32, 3]],
	},
	"silver": {
		"tree_first": [24, 1, 1], "tree_last": [3, 44, 1],
		"rock": [[22, 3, 3], [22, 1, 3], [3, 70, 3], [3, 32, 3]],
	},
	"crystal": {
		"tree_first": [24, 1, 4], "tree_last": [3, 52, 6],
		"rock": [[22, 3, 7], [22, 1, 7], [3, 78, 7], [3, 40, 7]],
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
		"swarm_grass": int(result["counts"]["swarm_grass"]),
		"swarm_water": int(result["counts"]["swarm_water"]),
		"fish_groups": int(result["counts"]["fish_groups"]),
		"roam_maps": int(result["counts"]["roam_maps"]),
		"tree_maps": int(result["counts"]["tree_maps"]),
		"rock_maps": int(result["counts"]["rock_maps"]),
		"treemon_sets": int(result["counts"]["treemon_sets"]),
		"bug_contest_mons": int(result["counts"]["bug_contest_mons"]),
		"bug_contestants": int(result["counts"]["bug_contestants"]),
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
			var row: Dictionary = table_result["rows"][map_key]
			# The two normal tables are merged for lookup by map, but FindNest
			# walks one region's own table, so which one a row came from is kept.
			if table_name in _NORMAL_TABLES:
				row["region"] = table_name.split("_")[1]
			destination[map_key] = row

	var fish_result: Dictionary = _read_fishing_groups(rom, layout, wild_layout)
	if not bool(fish_result.get("ok", false)):
		return fish_result
	var roam_result: Dictionary = _read_roaming_maps(rom, layout, wild_layout)
	if not bool(roam_result.get("ok", false)):
		return roam_result
	var treemon_result: Dictionary = read_treemons(rom, layout, wild_layout)
	if not bool(treemon_result.get("ok", false)):
		return treemon_result
	var contest_result: Dictionary = read_bug_contest(rom, wild_layout)
	if not bool(contest_result.get("ok", false)):
		return contest_result

	return {
		"ok": true,
		"encounters": {
			"grass": grass,
			"water": water,
			"swarm_grass": swarm_grass,
			"swarm_water": swarm_water,
			"fishing": fish_result["fishing"],
			"roaming": roam_result["roaming"],
			"treemons": treemon_result["treemons"],
			"bug_contest": contest_result["bug_contest"],
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
			"tree_maps": int(treemon_result["tree_maps"]),
			"rock_maps": int(treemon_result["rock_maps"]),
			"treemon_sets": int(treemon_result["sets"]),
			"bug_contest_mons": int(contest_result["mon_count"]),
			"bug_contestants": int(contest_result["contestant_count"]),
		},
	}


## `ContestMons` and `BugContestantPointers`, the Bug Catching Contest's own two
## tables. Both ship byte identical on all three cartridges; they are read
## rather than constants because they are cartridge data with a locator, unlike
## `RadioChannelSongs`.
##
## A contestant record is `db class, id` then three `dbw mon, score` placings,
## which `ComputeAIContestantScores` picks one of at random and then perturbs.
## Entry zero of the pointer table is the player's own slot (`BUG_CONTEST_PLAYER`
## is 1), and the source repeats the first real entry there, so the ten that
## follow are what is read.
static func read_bug_contest(rom: RomFile, configured: Dictionary) -> Dictionary:
	var mons_offset: int = int(configured.get("bug_contest_mons", -1))
	var mon_count: int = int(configured.get("bug_contest_mon_count", -1))
	var pointer_offset: int = int(configured.get("bug_contestants", -1))
	var contestant_count: int = int(configured.get("bug_contestant_count", -1))
	if mons_offset < 0 or mon_count <= 0 or pointer_offset < 0 or contestant_count <= 0:
		return _error("Bug Contest layout is incomplete.")

	var mons: Array = []
	for index: int in mon_count:
		var at: int = mons_offset + index * 4
		if not rom.in_bounds(at, 4):
			return _error("ContestMons row %d is outside the ROM." % index)
		var percent: int = rom.u8(at)
		var species: int = rom.u8(at + 1)
		var min_level: int = rom.u8(at + 2)
		var max_level: int = rom.u8(at + 3)
		var last: bool = index == mon_count - 1
		# The last row's percentage is `db -1`, which is what stops
		# ChooseWildEncounter_BugContest's walk however the earlier rows fall.
		if last != (percent == 0xFF):
			return _error("ContestMons row %d ends the table in the wrong place." % index)
		if species < 1 or species > RomLayout.SPECIES_COUNT \
			or min_level < 1 or max_level < min_level or max_level > RomLayout.MAX_LEVEL:
			return _error("ContestMons row %d is out of range." % index)
		mons.append({
			"percent": percent, "species": species,
			"min_level": min_level, "max_level": max_level,
		})

	var bank: int = floori(float(pointer_offset) / float(RomFile.BANK_SIZE))
	var contestants: Array = []
	for index: int in contestant_count:
		# Entry zero is the player's, so the ten AI contestants start at one.
		var entry: int = pointer_offset + (index + 1) * 2
		if not rom.in_bounds(entry, 2):
			return _error("BugContestantPointers entry %d is outside the ROM." % index)
		var pointer: int = rom.u16le(entry)
		if pointer < 0x4000 or pointer > 0x7FFF:
			return _error("BugContestantPointers entry %d is not a banked pointer." % index)
		var at: int = RomFile.linear(bank, pointer)
		if not rom.in_bounds(at, 11):
			return _error("Bug contestant %d is outside the ROM." % index)
		var placings: Array = []
		for placing: int in 3:
			var species: int = rom.u8(at + 2 + placing * 3)
			if species < 1 or species > RomLayout.SPECIES_COUNT:
				return _error("Bug contestant %d placing %d is out of range." % [index, placing])
			placings.append({
				"species": species,
				"score": rom.u16le(at + 3 + placing * 3),
			})
		contestants.append({
			"trainer_class": rom.u8(at),
			"trainer": rom.u8(at + 1),
			"placings": placings,
		})

	var anchor: Dictionary = _validate_bug_contest(mons, contestants)
	if not bool(anchor.get("ok", false)):
		return anchor
	return {
		"ok": true,
		"bug_contest": {"mons": mons, "contestants": contestants},
		"mon_count": mons.size(),
		"contestant_count": contestants.size(),
	}


## The first and last row of each table, which all three cartridges ship the
## same: `db 20, CATERPIE, 7, 18` and `db -1, VENOMOTH, 30, 40`, and
## `BugContestant_BugCatcherDon`'s `dbw KAKUNA, 300` through
## `BugContestant_SchoolboyKipp`'s `dbw KAKUNA, 259`.
const _CONTEST_MON_ANCHORS: Dictionary = {
	"first": {"percent": 20, "species": 10, "min_level": 7, "max_level": 18},
	"last": {"percent": 0xFF, "species": 49, "min_level": 30, "max_level": 40},
}
const _CONTESTANT_ANCHORS: Dictionary = {
	"first": [[14, 300], [11, 285], [10, 226]],
	"last": [[48, 267], [46, 254], [14, 259]],
}


static func _validate_bug_contest(mons: Array, contestants: Array) -> Dictionary:
	for edge: String in _CONTEST_MON_ANCHORS:
		var row: Dictionary = mons[0] if edge == "first" else mons[mons.size() - 1]
		var expected: Dictionary = _CONTEST_MON_ANCHORS[edge]
		for field: String in expected:
			if int(row.get(field, -1)) != int(expected[field]):
				return _error("ContestMons %s row does not match the source." % edge)
	for edge: String in _CONTESTANT_ANCHORS:
		var entry: Dictionary = contestants[0] if edge == "first" \
			else contestants[contestants.size() - 1]
		var placings: Array = entry.get("placings", [])
		var expected_placings: Array = _CONTESTANT_ANCHORS[edge]
		for index: int in expected_placings.size():
			var placing: Dictionary = placings[index]
			if int(placing["species"]) != int(expected_placings[index][0]) \
				or int(placing["score"]) != int(expected_placings[index][1]):
				return _error("Bug contestant %s record does not match the source." % edge)
	return {"ok": true}


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
	rom: RomFile, _layout: Dictionary, configured: Dictionary
) -> Dictionary:
	var offset: int = int(configured.get("fish_groups", -1))
	var expected_count: int = int(configured.get("fish_group_count", -1))
	if offset < 0 or expected_count != RomLayout.FISH_GROUP_COUNT:
		return _error("Fishing group layout is incomplete.")
	var bank: int = floori(float(offset) / float(RomFile.BANK_SIZE))
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


## TreeMonMaps, RockMonMaps and the TreeMons pointer table
## (engine/events/treemons.asm, data/wild/treemon_maps.asm, treemons.asm),
## plus Crystal's AsleepTreeMons* lists. All three tables live in one bank, so
## a set pointer resolves against the pointer table's own bank.
##
## Several pointers alias one address in both profiles: Crystal's NONE and its
## trailing unused entry both point at CANYON's bytes, and pokegold stacks
## NONE, UNUSED and CITY on one label. That is the source's own shape, so
## repeated addresses are kept rather than deduplicated.
## Public because the whole-cartridge fixture the other readers would need to
## be tested through is impractical: the anchors below are real cartridge rows.
static func read_treemons(
	rom: RomFile, layout: Dictionary, configured: Dictionary
) -> Dictionary:
	var pointer_offset: int = int(configured.get("treemon_sets", -1))
	var set_count: int = int(configured.get("treemon_set_count", -1))
	if pointer_offset < 0 or set_count < 1:
		return _error("Treemon set layout is incomplete.")
	var bank: int = RomLayout.bank_of(pointer_offset)

	var tree_maps: Dictionary = _read_treemon_maps(rom, layout, configured, "tree")
	if not bool(tree_maps.get("ok", false)):
		return tree_maps
	var rock_maps: Dictionary = _read_treemon_maps(rom, layout, configured, "rock")
	if not bool(rock_maps.get("ok", false)):
		return rock_maps

	var sets: Array = []
	for index: int in set_count:
		var at: int = pointer_offset + index * 2
		if not rom.in_bounds(at, 2):
			return _error("Treemon set pointer %d is outside the ROM." % index)
		var pointer: int = rom.u16le(at)
		if pointer < 0x4000 or pointer > 0x7FFF:
			return _error("Treemon set %d has an invalid pointer." % index)
		var parsed: Dictionary = _read_treemon_set(rom, RomFile.linear(bank, pointer), index)
		if not bool(parsed.get("ok", false)):
			return parsed
		sets.append({"common": parsed["common"], "rare": parsed["rare"]})

	var anchor_check: Dictionary = _validate_treemon_anchors(
		rom.id, tree_maps["rows"], rock_maps["rows"]
	)
	if not bool(anchor_check.get("ok", false)):
		return anchor_check

	var asleep: Dictionary = _read_asleep_treemons(rom, configured)
	if not bool(asleep.get("ok", false)):
		return asleep

	return {
		"ok": true,
		"tree_maps": (tree_maps["rows"] as Array).size(),
		"rock_maps": (rock_maps["rows"] as Array).size(),
		"sets": sets.size(),
		"treemons": {
			"tree_maps": tree_maps["rows"],
			"rock_maps": rock_maps["rows"],
			"sets": sets,
			"asleep": asleep["lists"],
		},
	}


## GetTreeMonSet's table: `(group, number, set)` triples up to a $FF group byte.
static func _read_treemon_maps(
	rom: RomFile, layout: Dictionary, configured: Dictionary, kind: String
) -> Dictionary:
	var offset: int = int(configured.get("%s_maps" % kind, -1))
	var expected_count: int = int(configured.get("%s_map_count" % kind, -1))
	if offset < 0 or expected_count < 1:
		return _error("Treemon %s map layout is incomplete." % kind)
	var rows: Array = []
	var at: int = offset
	while true:
		if not rom.in_bounds(at):
			return _error("Treemon %s map table has no sentinel." % kind)
		if rom.u8(at) == RomLayout.TREEMON_TABLE_END:
			break
		if rows.size() >= expected_count:
			return _error("Treemon %s map table exceeds its verified count." % kind)
		if not rom.in_bounds(at, RomLayout.TREEMON_MAP_RECORD_SIZE):
			return _error("Treemon %s map record is outside the ROM." % kind)
		var group: int = rom.u8(at)
		var number: int = rom.u8(at + 1)
		var map_check: Dictionary = _validate_map(layout, group, number, "%s_maps" % kind)
		if not bool(map_check.get("ok", false)):
			return map_check
		rows.append({
			"map_group": group,
			"map_number": number,
			"set": rom.u8(at + 2),
		})
		at += RomLayout.TREEMON_MAP_RECORD_SIZE
	if rows.size() != expected_count:
		return _error("Treemon %s map table has %d rows, expected %d." % [
			kind, rows.size(), expected_count,
		])
	return {"ok": true, "rows": rows}


## One set: a common table, then a rare one when the bytes after the common
## terminator parse as one. TreeMonSet_Rock ships no rare table in either pin
## and is followed by unrelated bytes, which fail the percentage and slot
## guards; that set is recorded with an empty rare half rather than refused.
## Only GetTreeMon's RARE branch reads the rare half, and nothing routes ROCK
## through it: RockMonEncounter calls SelectTreeMon directly.
static func _read_treemon_set(rom: RomFile, offset: int, index: int) -> Dictionary:
	var common: Dictionary = _read_treemon_table(rom, offset, index)
	if not bool(common.get("ok", false)):
		return common
	var rare: Dictionary = _read_treemon_table(rom, int(common["end"]), index)
	return {
		"ok": true,
		"common": common["rows"],
		"rare": rare["rows"] if bool(rare.get("ok", false)) else [],
	}


## SelectTreeMon's table: `db %, species, level` rows up to a $FF percentage.
static func _read_treemon_table(rom: RomFile, offset: int, index: int) -> Dictionary:
	var rows: Array = []
	var at: int = offset
	for _row: int in RomLayout.TREEMON_MAX_ROWS:
		if not rom.in_bounds(at):
			return _error("Treemon set %d is outside the ROM." % index)
		if rom.u8(at) == RomLayout.TREEMON_TABLE_END:
			if rows.is_empty():
				return _error("Treemon set %d has an empty table." % index)
			return {"ok": true, "rows": rows, "end": at + 1}
		if not rom.in_bounds(at, 3):
			return _error("Treemon set %d row is outside the ROM." % index)
		var percent: int = rom.u8(at)
		if percent < 1 or percent > 100:
			return _error("Treemon set %d has an invalid percentage." % index)
		var slot: Dictionary = _slot(rom.u8(at + 2), rom.u8(at + 1))
		if not bool(slot.get("ok", false)):
			return _error("Treemon set %d has an invalid slot." % index)
		slot.erase("ok")
		slot["percent"] = percent
		rows.append(slot)
		at += 3
	return _error("Treemon set %d has no sentinel." % index)


## AsleepTreeMonsNite, AsleepTreeMonsDay and AsleepTreeMonsMorn: species lists
## ending in $FF. Only Crystal ships them, so an absent layout entry is the
## Gold and Silver answer rather than a failure.
static func _read_asleep_treemons(rom: RomFile, configured: Dictionary) -> Dictionary:
	var offsets: Variant = configured.get("asleep_treemons", null)
	if not offsets is Dictionary:
		return _error("Asleep treemon layout is missing.")
	var lists: Dictionary = {}
	for key: String in ["morn", "day", "nite"]:
		var offset: int = int((offsets as Dictionary).get(key, -1))
		if offset < 0:
			continue
		var species: Array = []
		var at: int = offset
		for _row: int in RomLayout.ASLEEP_TREEMON_MAX_ROWS:
			if not rom.in_bounds(at):
				return _error("Asleep treemon list %s is outside the ROM." % key)
			var value: int = rom.u8(at)
			if value == RomLayout.ASLEEP_TREEMON_TABLE_END:
				break
			if value < 1 or value > RomLayout.SPECIES_COUNT:
				return _error("Asleep treemon list %s names an invalid species." % key)
			species.append(value)
			at += 1
		if species.is_empty():
			return _error("Asleep treemon list %s is empty." % key)
		lists[key] = species
	return {"ok": true, "lists": lists}


static func _validate_treemon_anchors(
	game_id: StringName, tree_rows: Array, rock_rows: Array
) -> Dictionary:
	var anchors: Variant = _TREEMON_ANCHORS.get(String(game_id), null)
	if not anchors is Dictionary:
		return _error("No treemon anchors for %s." % game_id)
	var expected: Dictionary = anchors
	if _treemon_triple(tree_rows[0]) != expected["tree_first"] \
		or _treemon_triple(tree_rows[-1]) != expected["tree_last"]:
		return _error("Treemon map table has unexpected anchors.")
	var rock: Array = []
	for row: Dictionary in rock_rows:
		rock.append(_treemon_triple(row))
	if rock != expected["rock"]:
		return _error("Rock treemon map table has unexpected anchors.")
	return {"ok": true}


static func _treemon_triple(row: Dictionary) -> Array:
	return [int(row["map_group"]), int(row["map_number"]), int(row["set"])]


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
