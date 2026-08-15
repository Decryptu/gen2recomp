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


## `ApplyMusicEffectOnEncounterRate` then `ApplyCleanseTagEffectOnEncounterRate`,
## both `sla b`/`srl b` on the rate byte: a rate of 200 doubled is 144, not 255.
func test_the_rate_is_shifted_by_the_map_music_and_by_a_cleanse_tag() -> void:
	var slots: Array = []
	for _slot: int in RomLayout.WILD_GRASS_SLOT_COUNT:
		slots.append({"level": 4, "species": 16})
	var record: Dictionary = {"rates": [200, 200, 200], "slots": [slots, slots, slots]}
	var cases: Array = [
		[0, false, 200],
		[Gen2WorldEncounter.MUSIC_POKEMON_MARCH, false, 144],
		[Gen2WorldEncounter.MUSIC_RUINS_OF_ALPH_RADIO, false, 144],
		[Gen2WorldEncounter.MUSIC_POKEMON_LULLABY, false, 100],
		[0, true, 100],
		[Gen2WorldEncounter.MUSIC_POKEMON_LULLABY, true, 50],
	]
	for case: Array in cases:
		var result: Dictionary = Gen2WorldEncounter.resolve(
			record, Gen2WorldEncounter.METHOD_GRASS, Gen2WorldPalette.TIME_DAY,
			RandomNumberGenerator.new(), true,
			{"map_music": case[0], "cleanse_tag": case[1]}
		)
		assert_eq(result["rate"], case[2], "music %d cleanse %s" % [case[0], case[1]])


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


## The treemon tables (data/wild/treemon_maps.asm, treemons.asm), read through
## a synthetic cartridge carrying the real Crystal anchor rows at the real
## offsets. The whole-cartridge fixture read_world_encounters() would need is
## impractical, so read_treemons() is driven directly; the real caches are
## covered by tools/checks/headbutt.gd.
const TREEMON_SET_CANYON: int = 1
const TREEMON_SET_FOREST: int = 6
const TREEMON_SET_ROCK: int = 7


func test_layout_exposes_verified_treemon_tables() -> void:
	var gold: Dictionary = RomLayout.for_id(RomRegistry.GOLD)
	var crystal: Dictionary = RomLayout.for_id(RomRegistry.CRYSTAL)
	assert_eq(crystal["wild_encounters"]["tree_maps"], 0xB825E)
	assert_eq(crystal["wild_encounters"]["rock_maps"], 0xB82C5)
	assert_eq(crystal["wild_encounters"]["treemon_sets"], 0xB82E8)
	assert_eq(crystal["wild_encounters"]["treemon_set_count"], 9)
	assert_eq(gold["wild_encounters"]["tree_maps"], 0xBA3E6)
	assert_eq(gold["wild_encounters"]["rock_maps"], 0xBA44D)
	assert_eq(gold["wild_encounters"]["treemon_sets"], 0xBA470)
	assert_eq(gold["wild_encounters"]["treemon_set_count"], 6)
	# CheckSleepingTreeMon is Crystal only, so Gold and Silver name no lists.
	assert_true((gold["wild_encounters"]["asleep_treemons"] as Dictionary).is_empty())
	assert_eq(crystal["wild_encounters"]["asleep_treemons"]["nite"], 0x3EB5D)


func test_treemon_tables_parse_maps_sets_and_the_asleep_lists() -> void:
	var result: Dictionary = Gen2WorldEncounterImporter.read_treemons(
		_treemon_rom(), RomLayout.for_id(RomRegistry.CRYSTAL),
		RomLayout.for_id(RomRegistry.CRYSTAL)["wild_encounters"]
	)
	assert_true(bool(result.get("ok", false)), String(result.get("message", "")))
	assert_eq(int(result["tree_maps"]), 34)
	assert_eq(int(result["rock_maps"]), 4)
	assert_eq(int(result["sets"]), 9)
	var treemons: Dictionary = result["treemons"]
	var first: Dictionary = (treemons["tree_maps"] as Array)[0]
	assert_eq([int(first["map_group"]), int(first["map_number"]), int(first["set"])], [24, 1, 4])
	var last: Dictionary = (treemons["tree_maps"] as Array)[-1]
	assert_eq([int(last["map_group"]), int(last["map_number"]), int(last["set"])], [3, 52, 6])
	# The three lists are Nite, Day then Morn in file order, and Day and Morn
	# are byte identical in the source.
	assert_eq((treemons["asleep"] as Dictionary)["nite"], [10, 11, 12] as Array)
	assert_eq((treemons["asleep"] as Dictionary)["day"], [48, 163] as Array)
	assert_eq((treemons["asleep"] as Dictionary)["morn"], [48, 163] as Array)


## Aliased pointers are the source's own shape, not corruption: Crystal's NONE
## and its trailing unused entry both point at CANYON's bytes.
func test_aliased_set_pointers_read_as_the_same_table() -> void:
	var treemons: Dictionary = Gen2WorldEncounterImporter.read_treemons(
		_treemon_rom(), RomLayout.for_id(RomRegistry.CRYSTAL),
		RomLayout.for_id(RomRegistry.CRYSTAL)["wild_encounters"]
	)["treemons"]
	var sets: Array = treemons["sets"]
	assert_eq(sets[0], sets[1], "NONE aliases CANYON")
	assert_eq(sets[0], sets[8], "the trailing unused entry aliases it too")


## TreeMonSet_Rock ships a common table and no rare one, and is followed by
## unrelated bytes. A set is never sized by assumption, so the rare half comes
## back empty rather than as garbage.
func test_a_set_with_no_rare_table_reads_an_empty_rare_half() -> void:
	var treemons: Dictionary = Gen2WorldEncounterImporter.read_treemons(
		_treemon_rom(), RomLayout.for_id(RomRegistry.CRYSTAL),
		RomLayout.for_id(RomRegistry.CRYSTAL)["wild_encounters"]
	)["treemons"]
	var rock: Dictionary = (treemons["sets"] as Array)[TREEMON_SET_ROCK]
	assert_eq((rock["common"] as Array).size(), 2)
	assert_eq((rock["rare"] as Array).size(), 0)
	assert_eq(int((rock["common"] as Array)[0]["species"]), 98, "KRABBY at 90 percent")
	var canyon: Dictionary = (treemons["sets"] as Array)[TREEMON_SET_CANYON]
	assert_eq((canyon["common"] as Array).size(), 2)
	assert_eq((canyon["rare"] as Array).size(), 2)


func test_a_treemon_map_table_without_its_sentinel_is_refused() -> void:
	var rom: RomFile = _treemon_rom(false)
	var result: Dictionary = Gen2WorldEncounterImporter.read_treemons(
		rom, RomLayout.for_id(RomRegistry.CRYSTAL),
		RomLayout.for_id(RomRegistry.CRYSTAL)["wild_encounters"]
	)
	assert_false(bool(result.get("ok", false)))
	assert_string_contains(String(result["message"]), "exceeds its verified count")


## A synthetic Crystal cartridge carrying only the treemon tables, at the real
## offsets, with the real anchor rows. Set contents are shortened: the reader
## is terminator-driven, so a two-row table proves the same walk a six-row one
## would.
func _treemon_rom(terminate_maps: bool = true) -> RomFile:
	var layout: Dictionary = RomLayout.for_id(RomRegistry.CRYSTAL)["wild_encounters"]
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(0xC0000)
	var tree_rows: Array = [[24, 1, 4]]
	for _filler: int in 32:
		tree_rows.append([19, 1, TREEMON_SET_CANYON])
	tree_rows.append([3, 52, TREEMON_SET_FOREST])
	var at: int = int(layout["tree_maps"])
	for row: Array in tree_rows:
		for value: int in row:
			bytes[at] = value
			at += 1
	bytes[at] = 0xFF if terminate_maps else 24
	at = int(layout["rock_maps"])
	for row: Array in [[22, 3, 7], [22, 1, 7], [3, 78, 7], [3, 40, 7]]:
		for value: int in row:
			bytes[at] = value
			at += 1
	bytes[at] = 0xFF

	# Two set bodies: a normal one with both tables, and the Rock shape with a
	# common table followed by bytes no table can parse.
	var canyon_at: int = 0xB8400
	var rock_at: int = 0xB8440
	_write_treemon_table(bytes, canyon_at, [[50, 21, 10], [50, 190, 10]])
	_write_treemon_table(bytes, canyon_at + 7, [[50, 21, 10], [50, 214, 10]])
	_write_treemon_table(bytes, rock_at, [[90, 98, 15], [10, 213, 15]])
	# 229 is past 100, which is what stops the Rock set reading a rare table.
	bytes[rock_at + 7] = 229
	bytes[rock_at + 8] = 205
	bytes[rock_at + 9] = 67

	at = int(layout["treemon_sets"])
	for index: int in int(layout["treemon_set_count"]):
		var target: int = rock_at if index == TREEMON_SET_ROCK else canyon_at
		var pointer: int = 0x4000 + (target & 0x3FFF)
		bytes[at + index * 2] = pointer & 0xFF
		bytes[at + index * 2 + 1] = (pointer >> 8) & 0xFF

	var asleep: Dictionary = layout["asleep_treemons"]
	_write_species_list(bytes, int(asleep["nite"]), [10, 11, 12])
	_write_species_list(bytes, int(asleep["day"]), [48, 163])
	_write_species_list(bytes, int(asleep["morn"]), [48, 163])
	return RomFile.from_bytes(bytes, RomRegistry.CRYSTAL)


func _write_treemon_table(bytes: PackedByteArray, at: int, rows: Array) -> void:
	var cursor: int = at
	for row: Array in rows:
		for value: int in row:
			bytes[cursor] = value
			cursor += 1
	bytes[cursor] = 0xFF


func _write_species_list(bytes: PackedByteArray, at: int, species: Array) -> void:
	var cursor: int = at
	for value: int in species:
		bytes[cursor] = value
		cursor += 1
	bytes[cursor] = 0xFF


## `FindNest` walks one region's own grass and water tables, appends each
## landmark once, and reads the roamers in Johto only.
class TestNests:
	extends GutTest

	const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

	var _data: GameData = null

	func before_each() -> void:
		_data = Fixture.build()

	func after_each() -> void:
		RomCache.clear(Fixture.directory())

	func test_a_species_nests_on_the_landmark_of_every_map_holding_it() -> void:
		assert_eq(
			Gen2WorldEncounter.nests(_data, Fixture.TRAINER_SPECIES, "johto"),
			[Fixture.MAP_LANDMARK]
		)
		assert_eq(
			Gen2WorldEncounter.nests(_data, Fixture.TRAINER_SPECIES, "kanto"),
			[Fixture.HOME_MAP_LANDMARK],
			"the water row is in the other region"
		)

	func test_a_species_in_no_table_nests_nowhere() -> void:
		assert_eq(Gen2WorldEncounter.nests(_data, Fixture.TRAINER_SPECIES + 1, "johto"), [])

	## `.RoamMon1` and `.RoamMon2` put a roamer wherever it is standing, and the
	## Kanto walk calls neither. The third roamer Gold and Silver ship has no
	## branch of its own.
	func test_only_the_first_two_roamers_nest_and_only_in_johto() -> void:
		var roaming: Array = []
		for index: int in 3:
			roaming.append({
				"species": 240 + index,
				"map_group": Fixture.MAP_GROUP,
				"map_number": Fixture.MAP_NUMBER,
			})
		for index: int in 2:
			assert_eq(
				Gen2WorldEncounter.nests(_data, 240 + index, "johto", roaming),
				[Fixture.MAP_LANDMARK]
			)
			assert_eq(Gen2WorldEncounter.nests(_data, 240 + index, "kanto", roaming), [])
		assert_eq(Gen2WorldEncounter.nests(_data, 242, "johto", roaming), [])

	## `.AppendNest` searches a zero-filled buffer, so a map whose landmark is
	## `LANDMARK_SPECIAL` always reports a hit and is never appended.
	func test_a_roamer_on_a_map_with_no_landmark_nests_nowhere() -> void:
		assert_eq(
			Gen2WorldEncounter.nests(_data, 240, "johto", [{
				"species": 240, "map_group": 99, "map_number": 99,
			}]),
			[]
		)


## The Bug Catching Contest's own encounter, score and judging
## (engine/events/bug_contest/, engine/overworld/events.asm). The tables are the
## cartridge's; these are built by hand the way every other case here is.
const CONTEST_MONS: Array[Dictionary] = [
	{"percent": 20, "species": 10, "min_level": 7, "max_level": 18},
	{"percent": 20, "species": 13, "min_level": 7, "max_level": 18},
	{"percent": 10, "species": 11, "min_level": 9, "max_level": 18},
	{"percent": 10, "species": 14, "min_level": 9, "max_level": 18},
	{"percent": 5, "species": 12, "min_level": 12, "max_level": 15},
	{"percent": 5, "species": 15, "min_level": 12, "max_level": 15},
	{"percent": 10, "species": 48, "min_level": 10, "max_level": 16},
	{"percent": 10, "species": 46, "min_level": 10, "max_level": 17},
	{"percent": 5, "species": 123, "min_level": 13, "max_level": 14},
	{"percent": 5, "species": 127, "min_level": 13, "max_level": 14},
	{"percent": 0xFF, "species": 49, "min_level": 30, "max_level": 40},
]


## `TryWildEncounter_BugContest`: `40 percent` in the long grass and
## `20 percent` on anything else, which are $ff/100 scaled rather than 40 and 20.
func test_the_contest_rate_is_the_two_percent_macros() -> void:
	assert_eq(Gen2WorldBugContest.RATE_LONG_GRASS, 102)
	assert_eq(Gen2WorldBugContest.RATE_ELSEWHERE, 51)
	var random := RandomNumberGenerator.new()
	random.seed = 3
	var forced: Dictionary = Gen2WorldBugContest.resolve(
		CONTEST_MONS, true, random, true
	)
	assert_eq(forced["rate"], Gen2WorldBugContest.RATE_LONG_GRASS)
	assert_eq(forced["source"], Gen2WorldBugContest.SOURCE_CONTEST)
	assert_eq(forced["battle_type"], Gen2WorldBugContest.BATTLE_TYPE)


## `ChooseWildEncounter_BugContest` walks the percentages with a roll halved into
## 0-99, so every draw lands on a row of the table and inside its own levels.
func test_every_contest_draw_is_a_table_row_at_its_own_level() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 11
	var seen: Dictionary = {}
	for _draw: int in 400:
		var result: Dictionary = Gen2WorldBugContest.resolve(
			CONTEST_MONS, false, random, true
		)
		assert_false(result.is_empty())
		var row: Dictionary = {}
		for candidate: Dictionary in CONTEST_MONS:
			if int(candidate["species"]) == int(result["pokemon"]):
				row = candidate
				break
		assert_false(row.is_empty(), "species %d is not in the table" % int(result["pokemon"]))
		assert_between(int(result["level"]), int(row["min_level"]), int(row["max_level"]))
		seen[int(result["pokemon"])] = true
	## Venomoth's row is the `db -1` terminator, which the walk can never reach.
	assert_false(seen.has(49), "the -1 row is the sentinel, not a draw")
	assert_true(seen.size() >= 8, "the common rows all come up")


## `ContestScore`: max HP four times, the five stats, the DV term, an eighth of
## the remaining HP and one for a held item.
func test_the_contest_score_is_the_source_tally() -> void:
	var mon: Dictionary = {
		"species": 10, "max_hp": 30, "hp": 16, "attack": 12, "defense": 13,
		"speed": 14, "special_attack": 15, "special_defense": 16,
		"dvs": 0, "item": 0,
	}
	assert_eq(Gen2WorldBugContest.score(mon), 192)
	mon["dvs"] = 0x2222
	assert_eq(Gen2WorldBugContest.score(mon), 192 + 29, "the DV term")
	mon["item"] = 1
	assert_eq(Gen2WorldBugContest.score(mon), 192 + 29 + 1)
	assert_eq(Gen2WorldBugContest.score({"species": 0}), 0, "nothing caught scores nothing")


## `BugContest_JudgeContestants` scores the AI first and inserts the player last,
## and `DetermineContestWinners` only pushes a place down on a *lower* score, so
## the player takes a place they tie.
func test_the_player_is_judged_last_and_takes_a_tie() -> void:
	var contestants: Array = []
	for index: int in Gen2WorldBugContest.NUM_CONTESTANTS:
		contestants.append({
			"trainer_class": 36, "trainer": index,
			"placings": [
				{"species": 10, "score": 200},
				{"species": 10, "score": 200},
				{"species": 10, "score": 200},
			],
		})
	## One competitor, so the only score to beat is 200 plus its own `and %111`
	## perturbation, which is 0 to 7 whatever the seed.
	var withdrawn: Dictionary = {}
	for index: int in range(1, Gen2WorldBugContest.NUM_CONTESTANTS):
		withdrawn[index] = true
	var random := RandomNumberGenerator.new()
	for seed_value: int in 12:
		random.seed = seed_value
		var won: Dictionary = Gen2WorldBugContest.judge(
			12, 207, contestants, withdrawn, random
		)
		assert_eq(won["placings"].size(), 2, "one contestant and the player")
		assert_eq(int(won["player_place"]), 1, "an equal score still wins")
		random.seed = seed_value
		var lost: Dictionary = Gen2WorldBugContest.judge(
			12, 199, contestants, withdrawn, random
		)
		assert_eq(int(lost["player_place"]), 2, "one under the lowest roll loses")
		assert_eq(
			int((lost["placings"][0] as Dictionary)["id"]), 2,
			"contestant zero is id 2, since the player is 1"
		)


## `SelectRandomBugContestContestants`: five of the ten, each set once.
func test_five_contestants_are_withdrawn_and_no_index_twice() -> void:
	var random := RandomNumberGenerator.new()
	for seed_value: int in 20:
		random.seed = seed_value
		var withdrawn: Dictionary = Gen2WorldBugContest.select_withdrawn(random)
		assert_eq(withdrawn.size(), Gen2WorldBugContest.CONTESTANTS_WITHDRAWN)
		for index: Variant in withdrawn:
			assert_between(int(index), 0, Gen2WorldBugContest.NUM_CONTESTANTS - 1)


## `CheckBugContestTimer` in the minutes the world clock keeps, including the
## midnight the source's own day counter would have caught.
func test_the_contest_timer_counts_the_minutes_down_across_midnight() -> void:
	var started: Dictionary = {"day": 0, "hour": 23, "minute": 55}
	assert_eq(Gen2WorldBugContest.minutes_remaining(started, started), 20)
	assert_eq(Gen2WorldBugContest.minutes_remaining(
		started, {"day": 1, "hour": 0, "minute": 5}
	), 10)
	assert_eq(Gen2WorldBugContest.minutes_remaining(
		started, {"day": 1, "hour": 0, "minute": 15}
	), 0)
	assert_eq(Gen2WorldBugContest.minutes_remaining({}, started), 0)
