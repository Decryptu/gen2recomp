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


func test_fishing_uses_the_rod_table_and_time_group() -> void:
	var record: Dictionary = {
		"chance": 255,
		"rods": [
			[{
				"threshold": 255,
				"time_group": 0,
			}],
			[], [],
		],
	}
	var time_groups: Array = [{
		"day": {"species": 0xDE, "level": 20},
		"night": {"species": 0x78, "level": 20},
	}]
	var result: Dictionary = Gen2WorldEncounter.resolve_fishing(
		record, Gen2WorldEncounter.METHOD_OLD_ROD, Gen2WorldPalette.TIME_NIGHT,
		time_groups, RandomNumberGenerator.new(), true
	)
	assert_eq(result["source"], Gen2WorldEncounter.SOURCE_FISHING)
	assert_eq(result["method"], Gen2WorldEncounter.METHOD_OLD_ROD)
	assert_eq(result["pokemon"], 0x78)
	assert_eq(result["level"], 20)


func test_fishing_can_fail_before_selecting_a_slot() -> void:
	var result: Dictionary = Gen2WorldEncounter.resolve_fishing(
		{"chance": 0, "rods": []}, Gen2WorldEncounter.METHOD_GOOD_ROD,
		Gen2WorldPalette.TIME_DAY, [], RandomNumberGenerator.new(), true
	)
	assert_true(result.is_empty())


func test_swarm_source_and_repel_are_resolved_after_the_candidate_roll() -> void:
	var morning: Array = []
	var day: Array = []
	var night: Array = []
	for _slot: int in RomLayout.WILD_GRASS_SLOT_COUNT:
		morning.append({"level": 4, "species": 16})
		day.append({"level": 4, "species": 16})
		night.append({"level": 4, "species": 16})
	var record: Dictionary = {
		"rates": [255, 255, 255],
		"slots": [morning, day, night],
	}
	var blocked: Dictionary = Gen2WorldEncounter.resolve(
		record, Gen2WorldEncounter.METHOD_GRASS, Gen2WorldPalette.TIME_DAY,
		RandomNumberGenerator.new(), true, {
			"source": Gen2WorldEncounter.SOURCE_SWARM,
			"repel_steps": 1,
			"lead_level": 5,
		}
	)
	assert_true(blocked.is_empty())
	var allowed: Dictionary = Gen2WorldEncounter.resolve(
		record, Gen2WorldEncounter.METHOD_GRASS, Gen2WorldPalette.TIME_DAY,
		RandomNumberGenerator.new(), true, {
			"source": Gen2WorldEncounter.SOURCE_SWARM,
			"repel_steps": 1,
			"lead_level": 4,
		}
	)
	assert_eq(allowed["source"], Gen2WorldEncounter.SOURCE_SWARM)


func test_roaming_selection_uses_the_land_roll_before_normal_slots() -> void:
	var slots: Array = []
	for _time_of_day: int in RomLayout.WILD_TIME_COUNT:
		var day_slots: Array = []
		for _slot: int in RomLayout.WILD_GRASS_SLOT_COUNT:
			day_slots.append({"level": 5, "species": 16})
		slots.append(day_slots)
	var record: Dictionary = {
		"rates": [255, 255, 255],
		"slots": slots,
	}
	var found: Dictionary = {}
	for seed: int in range(1, 512):
		var random := RandomNumberGenerator.new()
		random.seed = seed
		found = Gen2WorldEncounter.resolve(
			record, Gen2WorldEncounter.METHOD_GRASS, Gen2WorldPalette.TIME_DAY,
			random, true, {
				"map_group": 1,
				"map_number": 1,
				"roaming_mons": [{"species": 0xF3, "level": 40, "map_group": 1, "map_number": 1}],
			}
		)
		if found.get("source", &"") == Gen2WorldEncounter.SOURCE_ROAMING:
			break
	assert_eq(found["source"], Gen2WorldEncounter.SOURCE_ROAMING)
	assert_eq(found["pokemon"], 0xF3)
	assert_eq(found["level"], 40)


func test_layout_exposes_swarm_fishing_and_roaming_tables() -> void:
	var gold: Dictionary = RomLayout.for_id(RomRegistry.GOLD)
	var crystal: Dictionary = RomLayout.for_id(RomRegistry.CRYSTAL)
	assert_eq(gold["wild_encounters"]["swarm_grass_count"], 4)
	assert_eq(gold["wild_encounters"]["swarm_water_count"], 1)
	assert_eq(gold["wild_encounters"]["fish_groups"], 0x929F7)
	assert_eq(crystal["wild_encounters"]["swarm_grass"], 0x2B8D0)
	assert_eq(crystal["wild_encounters"]["swarm_water_count"], 0)
	assert_eq(crystal["wild_encounters"]["roam_maps"], 0x2A40F)


func test_layout_exposes_verified_normal_encounter_tables() -> void:
	var gold: Dictionary = RomLayout.for_id(RomRegistry.GOLD)
	var crystal: Dictionary = RomLayout.for_id(RomRegistry.CRYSTAL)
	assert_eq(gold["wild_encounters"]["grass_johto"], 0x2AB35)
	assert_eq(gold["wild_encounters"]["water_kanto_count"], 24)
	assert_eq(crystal["wild_encounters"]["grass_johto"], 0x2A5E9)
	assert_eq(crystal["wild_encounters"]["water_kanto"], 0x2B7F7)
