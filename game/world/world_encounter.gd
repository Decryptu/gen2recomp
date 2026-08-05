class_name Gen2WorldEncounter
extends RefCounted

## Resolves one normal Generation 2 encounter record into the battle request
## shape already consumed by Gen2WorldBattleAdapter. The roll order matches the
## original routine: encounter rate, slot bracket, then surfing level variance.

const METHOD_GRASS: StringName = &"grass"
const METHOD_SURF: StringName = &"surf"


static func resolve(
	record: Dictionary,
	method: StringName,
	time_of_day: int,
	random: RandomNumberGenerator = null,
	force_encounter: bool = false,
) -> Dictionary:
	if record.is_empty() or method not in [METHOD_GRASS, METHOD_SURF]:
		return {}
	var generator := random if random != null else RandomNumberGenerator.new()
	if random == null:
		generator.randomize()

	var rate: int = _rate(record, method, time_of_day)
	if rate <= 0:
		return {}
	var encounter_roll: int = -1
	if not force_encounter:
		encounter_roll = generator.randi_range(0, 255)
		if encounter_roll >= rate:
			return {}

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
	return {
		"kind": &"wild_encounter_requested",
		"method": method,
		"slot": slot,
		"pokemon": species,
		"level": level,
		"rate": rate,
		"encounter_roll": encounter_roll,
		"level_roll": level_roll,
		"forced": force_encounter,
		"values": {"kind": &"wild", "pokemon": species, "level": level},
	}


static func _rate(record: Dictionary, method: StringName, time_of_day: int) -> int:
	if method == METHOD_SURF:
		return int(record.get("rate", 0))
	var rates: Variant = record.get("rates", [])
	if not rates is Array or (rates as Array).is_empty():
		return 0
	var index: int = mini(2, maxi(0, time_of_day))
	return int((rates as Array)[index]) if index < (rates as Array).size() else 0


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


static func _surf_level_bonus(roll: int) -> int:
	for bonus: int in RomLayout.WILD_SURF_LEVEL_THRESHOLDS.size():
		if roll < RomLayout.WILD_SURF_LEVEL_THRESHOLDS[bonus]:
			return bonus
	return RomLayout.WILD_SURF_LEVEL_THRESHOLDS.size()
