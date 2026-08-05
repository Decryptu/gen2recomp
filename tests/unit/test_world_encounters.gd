extends GutTest

## Encounter rolls use the source table shape and a caller-owned RNG, so these
## checks do not depend on wall-clock randomness or a display scene.


func test_grass_uses_the_selected_time_of_day_slots() -> void:
	var morning: Array = []
	var day: Array = []
	var night: Array = []
	for _slot: int in RomLayout.WILD_GRASS_SLOT_COUNT:
		morning.append({"level": 3, "species": 16})
		day.append({"level": 7, "species": 19})
		night.append({"level": 9, "species": 25})
	var record: Dictionary = {
		"rates": [0, 255, 0],
		"slots": [morning, day, night],
	}
	var result: Dictionary = Gen2WorldEncounter.resolve(
		record, Gen2WorldEncounter.METHOD_GRASS, Gen2WorldPalette.TIME_DAY,
		RandomNumberGenerator.new(), true
	)
	assert_eq(result["pokemon"], 19)
	assert_eq(result["level"], 7)
	assert_eq(result["values"]["kind"], &"wild")


func test_zero_rate_does_not_resolve_even_when_not_forced() -> void:
	var result: Dictionary = Gen2WorldEncounter.resolve(
		{"rates": [0, 0, 0], "slots": [[{"level": 3, "species": 16}]]},
		Gen2WorldEncounter.METHOD_GRASS, Gen2WorldPalette.TIME_MORNING,
		RandomNumberGenerator.new(), false
	)
	assert_true(result.is_empty())


func test_surf_uses_three_slots_and_source_level_variance_bounds() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 12345
	var result: Dictionary = Gen2WorldEncounter.resolve(
		{"rate": 255, "slots": [
			{"level": 10, "species": 72}, {"level": 10, "species": 72},
			{"level": 10, "species": 72},
		]},
		Gen2WorldEncounter.METHOD_SURF, Gen2WorldPalette.TIME_NIGHT, random, false
	)
	assert_eq(result["pokemon"], 72)
	assert_between(result["level"], 10, 14)
	assert_eq(result["method"], Gen2WorldEncounter.METHOD_SURF)


func test_layout_exposes_verified_normal_encounter_tables() -> void:
	var gold: Dictionary = RomLayout.for_id(RomRegistry.GOLD)
	var crystal: Dictionary = RomLayout.for_id(RomRegistry.CRYSTAL)
	assert_eq(gold["wild_encounters"]["grass_johto"], 0x2AB35)
	assert_eq(gold["wild_encounters"]["water_kanto_count"], 24)
	assert_eq(crystal["wild_encounters"]["grass_johto"], 0x2A5E9)
	assert_eq(crystal["wild_encounters"]["water_kanto"], 0x2B7F7)
