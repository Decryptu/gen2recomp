class_name Gen2WorldEncounter
extends RefCounted

## Resolves Generation 2 encounter records into the battle request shape used
## by Gen2WorldBattleAdapter. The roll order follows the source routines:
## encounter rate, roaming selection on land, slot selection, surf level
## variance, then the repel level check.

const METHOD_GRASS: StringName = &"grass"
const METHOD_SURF: StringName = &"surf"
const METHOD_OLD_ROD: StringName = &"old_rod"
const METHOD_GOOD_ROD: StringName = &"good_rod"
const METHOD_SUPER_ROD: StringName = &"super_rod"
## TreeMonEncounter's own method. Unlike the five above it reads no rate, no
## slot table and no repel step, so nothing in resolve() handles it: it is a
## name for the request a headbutt produces.
const METHOD_HEADBUTT: StringName = &"headbutt"
## RockMonEncounter's own method, which reads no rate and no slot table either.
const METHOD_ROCK_SMASH: StringName = &"rock_smash"

## `FindNest` calls `.RoamMon1` and `.RoamMon2` and nothing after them, so Gold
## and Silver's third roamer has no nest.
const ROAM_NEST_MONS: int = 2

const SOURCE_NORMAL: StringName = &"normal"
const SOURCE_SWARM: StringName = &"swarm"
const SOURCE_ROAMING: StringName = &"roaming"
const SOURCE_FISHING: StringName = &"fishing"
const SOURCE_TREE: StringName = &"tree"
const SOURCE_ROCK: StringName = &"rock"


static func resolve(
	record: Dictionary,
	method: StringName,
	time_of_day: int,
	random: RandomNumberGenerator = null,
	force_encounter: bool = false,
	options: Dictionary = {},
) -> Dictionary:
	if record.is_empty() or method not in [METHOD_GRASS, METHOD_SURF]:
		return {}
	var generator := random if random != null else RandomNumberGenerator.new()
	if random == null:
		generator.randomize()

	var rate: int = _rate(record, method, time_of_day)
	rate = apply_music_effect(rate, int(options.get("map_music", 0)))
	if bool(options.get("cleanse_tag", false)):
		rate >>= 1
	if rate <= 0:
		return {}
	var encounter_roll: int = -1
	if not force_encounter:
		encounter_roll = generator.randi_range(0, 255)
		if encounter_roll >= rate:
			return {}

	var roaming_roll: int = -1
	var roaming_index: int = -1
	if method == METHOD_GRASS and options.has("roaming_mons"):
		var roaming: Dictionary = _resolve_roaming(
			options.get("roaming_mons", []),
			int(options.get("map_group", -1)), int(options.get("map_number", -1)),
			generator
		)
		roaming_roll = int(roaming.get("roll", -1))
		roaming_index = int(roaming.get("index", -1))
		if roaming.has("species") and roaming.has("level"):
			var roaming_level: int = int(roaming["level"])
			if _blocked_by_repel(roaming_level, options):
				return {}
			return _wild_result(
				method, SOURCE_ROAMING, -1, int(roaming["species"]), roaming_level,
				rate, encounter_roll, -1, force_encounter, roaming_roll, roaming_index
			)

	var slots: Array = _slots(record, method, time_of_day)
	var slot: int = _choose_slot(generator, method)
	if slot < 0 or slot >= slots.size():
		return {}
	var selected: Variant = slots[slot]
	if not selected is Dictionary:
		return {}
	var species: int = int((selected as Dictionary).get("species", 0))
	var level: int = int((selected as Dictionary).get("level", 0))
	if species < 1 or species > RomLayout.SPECIES_COUNT or level < 1 or level > RomLayout.MAX_LEVEL:
		return {}

	var level_roll: int = -1
	if method == METHOD_SURF:
		level_roll = generator.randi_range(0, 255)
		level += _surf_level_bonus(level_roll)
		level = mini(level, RomLayout.MAX_LEVEL)
	if _blocked_by_repel(level, options):
		return {}
	var source: StringName = StringName(options.get("source", SOURCE_NORMAL))
	return _wild_result(
		method, source, slot, species, level, rate, encounter_roll, level_roll,
		force_encounter, roaming_roll, roaming_index
	)


static func resolve_fishing(
	record: Dictionary,
	rod: StringName,
	time_of_day: int,
	time_groups: Array,
	random: RandomNumberGenerator = null,
	force_encounter: bool = false,
) -> Dictionary:
	if record.is_empty() or rod not in [METHOD_OLD_ROD, METHOD_GOOD_ROD, METHOD_SUPER_ROD]:
		return {}
	var generator := random if random != null else RandomNumberGenerator.new()
	if random == null:
		generator.randomize()
	var chance: int = int(record.get("chance", 0))
	if chance <= 0:
		return {}
	var encounter_roll: int = -1
	if not force_encounter:
		encounter_roll = generator.randi_range(0, 255)
		if encounter_roll >= chance:
			return {}
	var rods: Variant = record.get("rods", [])
	var rod_index: int = _rod_index(rod)
	if not rods is Array or rod_index < 0 or rod_index >= (rods as Array).size():
		return {}
	var entries: Variant = (rods as Array)[rod_index]
	if not entries is Array or (entries as Array).is_empty():
		return {}
	var slot_roll: int = generator.randi_range(0, 255)
	var selected: Dictionary = {}
	var slot: int = -1
	for index: int in (entries as Array).size():
		var entry: Variant = (entries as Array)[index]
		if not entry is Dictionary:
			continue
		if slot_roll <= int((entry as Dictionary).get("threshold", -1)):
			selected = (entry as Dictionary).duplicate(true)
			slot = index
			break
	if selected.is_empty():
		return {}

	var time_group: int = -1
	var species: int = int(selected.get("species", 0))
	var level: int = int(selected.get("level", 0))
	if selected.has("time_group"):
		time_group = int(selected["time_group"])
		if time_group < 0 or time_group >= time_groups.size():
			return {}
		var time_entry: Variant = time_groups[time_group]
		if not time_entry is Dictionary:
			return {}
		var time_key: String = "night" if time_of_day >= Gen2WorldPalette.TIME_NIGHT else "day"
		var chosen: Variant = (time_entry as Dictionary).get(time_key, {})
		if not chosen is Dictionary:
			return {}
		species = int((chosen as Dictionary).get("species", 0))
		level = int((chosen as Dictionary).get("level", 0))
	if species < 1 or species > RomLayout.SPECIES_COUNT or level < 1 or level > RomLayout.MAX_LEVEL:
		return {}
	return {
		"kind": &"wild_encounter_requested",
		"method": rod,
		"source": SOURCE_FISHING,
		"slot": slot,
		"pokemon": species,
		"level": level,
		"rate": chance,
		"encounter_roll": encounter_roll,
		"slot_roll": slot_roll,
		"time_group": time_group,
		"forced": force_encounter,
		"values": {"kind": &"wild", "pokemon": species, "level": level},
	}


static func _wild_result(
	method: StringName,
	source: StringName,
	slot: int,
	species: int,
	level: int,
	rate: int,
	encounter_roll: int,
	level_roll: int,
	forced: bool,
	roaming_roll: int,
	roaming_index: int,
) -> Dictionary:
	return {
		"kind": &"wild_encounter_requested",
		"method": method,
		"source": source,
		"slot": slot,
		"pokemon": species,
		"level": level,
		"rate": rate,
		"encounter_roll": encounter_roll,
		"level_roll": level_roll,
		"roaming_roll": roaming_roll,
		"roaming_index": roaming_index,
		"forced": forced,
		"values": {"kind": &"wild", "pokemon": species, "level": level},
	}


## `FindNest`: every landmark one region holds [param species] at, in the order
## its own tables name them and each landmark once. [param region] is the cache's
## name for `FindNest`'s `e`, and [param roaming_mons] the live
## [method Gen2WorldState.roaming_mons].
##
## Neither swarm table is read. Only the Johto walk reads the roamers, and only
## `wRoamMon1` and `wRoamMon2`, so Gold and Silver's third never appears.
static func nests(
	data: GameData, species: int, region: String, roaming_mons: Array = []
) -> Array:
	var out: Array = []
	if data == null or species < 1:
		return out
	for method: StringName in [METHOD_GRASS, &"water"]:
		for row: Dictionary in data.world_encounter_region_rows(method, region):
			if _holds_species(row, species):
				_append_nest(out, data, String(row.get("map", "")))
	if region == Gen2TownMap.region_name(Gen2TownMap.REGION_JOHTO):
		for index: int in mini(ROAM_NEST_MONS, roaming_mons.size()):
			var mon: Dictionary = roaming_mons[index]
			if int(mon.get("species", 0)) != species:
				continue
			_append_nest(out, data, "%d:%d" % [
				int(mon.get("map_group", 0)), int(mon.get("map_number", 0)),
			])
	return out


## `.SearchMapForMon` over every slot the record carries: `NUM_GRASSMON * 3`
## walks the three times of day as one run, and water's own three follow.
static func _holds_species(row: Dictionary, species: int) -> bool:
	var slots: Variant = row.get("slots", [])
	if not slots is Array:
		return false
	for entry: Variant in slots as Array:
		if entry is Array:
			for slot: Variant in entry as Array:
				if slot is Dictionary and int((slot as Dictionary).get("species", 0)) == species:
					return true
		elif entry is Dictionary and int((entry as Dictionary).get("species", 0)) == species:
			return true
	return false


## `.AppendNest`: `GetWorldMapLocation` for the map, appended unless the list
## already holds it. `LANDMARK_SPECIAL` is zero and the list it searches is
## zero-filled, so a map with no landmark of its own always reports a hit and is
## never appended.
static func _append_nest(out: Array, data: GameData, map_key: String) -> void:
	var parts: PackedStringArray = map_key.split(":")
	if parts.size() != 2:
		return
	var map: Gen2WorldMap = data.world_map(int(parts[0]), int(parts[1]))
	if map == null or map.location == Gen2WorldRadio.LANDMARK_SPECIAL:
		return
	if not out.has(map.location):
		out.append(map.location)


static func _rate(record: Dictionary, method: StringName, time_of_day: int) -> int:
	if method == METHOD_SURF:
		return int(record.get("rate", 0))
	var rates: Variant = record.get("rates", [])
	if not rates is Array or (rates as Array).is_empty():
		return 0
	var index: int = mini(2, maxi(0, time_of_day))
	return int((rates as Array)[index]) if index < (rates as Array).size() else 0


## `ApplyMusicEffectOnEncounterRate`: the two radio-shaped tracks double the rate
## and Pokemon Lullaby halves it. Both shifts are on the byte the source holds
## the rate in, so a doubled rate above 127 wraps rather than saturating.
const MUSIC_RUINS_OF_ALPH_RADIO: int = 0x4B
const MUSIC_POKEMON_LULLABY: int = 0x50
const MUSIC_POKEMON_MARCH: int = 0x51


static func apply_music_effect(rate: int, map_music: int) -> int:
	if map_music == MUSIC_POKEMON_MARCH or map_music == MUSIC_RUINS_OF_ALPH_RADIO:
		return (rate << 1) & 0xFF
	if map_music == MUSIC_POKEMON_LULLABY:
		return rate >> 1
	return rate


static func _slots(record: Dictionary, method: StringName, time_of_day: int) -> Array:
	var value: Variant = record.get("slots", [])
	if not value is Array:
		return []
	if method == METHOD_SURF:
		return value as Array
	var index: int = mini(2, maxi(0, time_of_day))
	return (value as Array)[index] if index < (value as Array).size() and (value as Array)[index] is Array else []


static func _choose_slot(random: RandomNumberGenerator, method: StringName) -> int:
	var probabilities: Array[int] = (
		RomLayout.WILD_WATER_PROBABILITIES if method == METHOD_SURF
		else RomLayout.WILD_GRASS_PROBABILITIES
	)
	for _attempt: int in 128:
		var roll: int = random.randi_range(0, 255)
		if roll >= 100:
			continue
		var one_based: int = roll + 1
		for slot: int in probabilities.size():
			if one_based <= probabilities[slot]:
				return slot
	return -1


static func _resolve_roaming(
	mons: Variant, map_group: int, map_number: int, random: RandomNumberGenerator
) -> Dictionary:
	var roll: int = random.randi_range(0, 255)
	var result: Dictionary = {"roll": roll}
	if roll >= 100:
		return result
	var selected_index: int = roll & 0x03
	if selected_index == 0:
		return result
	selected_index -= 1
	if not mons is Array or selected_index >= (mons as Array).size():
		return result
	var mon: Variant = (mons as Array)[selected_index]
	if not mon is Dictionary:
		return result
	if int((mon as Dictionary).get("map_group", -1)) != map_group \
		or int((mon as Dictionary).get("map_number", -1)) != map_number:
		return result
	result["index"] = selected_index
	result["species"] = int((mon as Dictionary).get("species", 0))
	result["level"] = int((mon as Dictionary).get("level", 0))
	return result


static func _blocked_by_repel(level: int, options: Dictionary) -> bool:
	var steps: int = int(options.get("repel_steps", 0))
	var lead_level: int = int(options.get("lead_level", -1))
	return steps > 0 and lead_level > 0 and level < lead_level


static func _rod_index(rod: StringName) -> int:
	match rod:
		METHOD_OLD_ROD:
			return 0
		METHOD_GOOD_ROD:
			return 1
		METHOD_SUPER_ROD:
			return 2
	return -1


static func _surf_level_bonus(roll: int) -> int:
	for bonus: int in RomLayout.WILD_SURF_LEVEL_THRESHOLDS.size():
		if roll < RomLayout.WILD_SURF_LEVEL_THRESHOLDS[bonus]:
			return bonus
	return RomLayout.WILD_SURF_LEVEL_THRESHOLDS.size()
