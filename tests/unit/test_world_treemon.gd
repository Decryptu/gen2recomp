extends GutTest

## GetTreeScore, GetTreeMon and SelectTreeMon (engine/events/treemons.asm),
## against hand-built tables rather than a cache: every number here is
## arithmetic the source fixes, so a fixture would only hide it.

## A two-row common table and a two-row rare one, so which table a score
## reaches is visible in the species that comes back.
const COMMON: Array = [
	{"percent": 50, "species": 21, "level": 10},
	{"percent": 50, "species": 22, "level": 10},
]
const RARE: Array = [
	{"percent": 100, "species": 214, "level": 10},
]
const SET: Dictionary = {"common": COMMON, "rare": RARE}


## GetTreeMons refuses TREEMON_SET_NONE before anything else, and refuses any
## set at or past the profile's limit. pokegold's limit is two lower than
## Crystal's, which is what makes its CITY maps barren.
func test_set_usability_follows_each_profiles_own_limit() -> void:
	assert_eq(Gen2WorldTreemon.set_limit(true), 8)
	assert_eq(Gen2WorldTreemon.set_limit(false), 4)
	assert_false(Gen2WorldTreemon.set_is_usable(0, true), "TREEMON_SET_NONE")
	assert_false(Gen2WorldTreemon.set_is_usable(0, false), "TREEMON_SET_NONE")
	for index: int in range(1, 8):
		assert_true(Gen2WorldTreemon.set_is_usable(index, true), "crystal set %d" % index)
	assert_false(Gen2WorldTreemon.set_is_usable(8, true), "crystal past NUM_TREEMON_SETS")
	for index: int in range(1, 4):
		assert_true(Gen2WorldTreemon.set_is_usable(index, false), "gold set %d" % index)
	# TREEMON_SET_UNUSED and TREEMON_SET_CITY, the two pokegold's own
	# `cp NUM_TREEMON_SETS - 2` refuses.
	assert_false(Gen2WorldTreemon.set_is_usable(4, false), "TREEMON_SET_UNUSED")
	assert_false(Gen2WorldTreemon.set_is_usable(5, false), "TREEMON_SET_CITY")


## .CoordScore is `floor((y * (x + 1) + x) / 5) % 10` over the coordinates
## GetFacingTileCoord returns, which carry the four-cell border
## CheckCurrentMapCoordEvents subtracts back off.
func test_coord_score_uses_the_bordered_coordinates() -> void:
	# Walk cell (0,0) is wPlayerMapX/Y (4,4): 4 * 5 + 4 = 24, 24 / 5 = 4.
	assert_eq(Gen2WorldTreemon.coord_score(Vector2i(0, 0)), 4)
	# Walk cell (6,3) is (10,7): 7 * 11 + 10 = 87, 87 / 5 = 17, 17 % 10 = 7.
	assert_eq(Gen2WorldTreemon.coord_score(Vector2i(6, 3)), 7)
	# Walk cell (1,1) is (5,5): 5 * 6 + 5 = 35, 35 / 5 = 7.
	assert_eq(Gen2WorldTreemon.coord_score(Vector2i(1, 1)), 7)
	# The same arithmetic without the border would answer 0, 3 and 0, so this
	# is the assertion that catches the offset going missing.
	assert_ne(Gen2WorldTreemon.coord_score(Vector2i(0, 0)), 0)


func test_otid_score_is_the_trainer_id_mod_ten() -> void:
	assert_eq(Gen2WorldTreemon.otid_score(0), 0)
	assert_eq(Gen2WorldTreemon.otid_score(7), 7)
	assert_eq(Gen2WorldTreemon.otid_score(0x1A2B), 0x1A2B % 10)
	assert_eq(Gen2WorldTreemon.otid_score(65535), 5)


## GetTreeScore answers RARE on a true equality, before the wrap; a negative
## difference gains ten and can only land in 1..9, so it never reads as RARE.
func test_score_tiers_follow_the_difference_and_its_wrap() -> void:
	# Walk cell (1,1) scores 7. An ID scoring 7 is the equal case.
	assert_eq(Gen2WorldTreemon.score(Vector2i(1, 1), 7), Gen2WorldTreemon.SCORE_RARE)
	# Difference 1, 4 and 5: GOOD, GOOD, then BAD at the boundary.
	assert_eq(Gen2WorldTreemon.score(Vector2i(1, 1), 6), Gen2WorldTreemon.SCORE_GOOD)
	assert_eq(Gen2WorldTreemon.score(Vector2i(1, 1), 3), Gen2WorldTreemon.SCORE_GOOD)
	assert_eq(Gen2WorldTreemon.score(Vector2i(1, 1), 2), Gen2WorldTreemon.SCORE_BAD)
	# A negative difference wraps: 7 - 9 is -2, which becomes 8, so BAD.
	assert_eq(Gen2WorldTreemon.score(Vector2i(1, 1), 9), Gen2WorldTreemon.SCORE_BAD)
	# 7 - 8 is -1, which becomes 9, still BAD; the wrap never produces GOOD
	# from a difference of one below.
	assert_eq(Gen2WorldTreemon.score(Vector2i(1, 1), 8), Gen2WorldTreemon.SCORE_BAD)


## SelectTreeMon subtracts each row's percentage from RandomRange(100) and
## takes the row the subtraction borrows on, so the boundary belongs to the
## later row.
func test_select_walks_the_percentages_and_the_boundary_belongs_to_the_next_row() -> void:
	var picks: Dictionary = {}
	for roll: int in 100:
		var chosen: Dictionary = Gen2WorldTreemon.select_at(COMMON, roll)
		picks[int(chosen["species"])] = int(picks.get(int(chosen["species"]), 0)) + 1
	assert_eq(picks[21], 50, "first row takes rolls 0..49")
	assert_eq(picks[22], 50, "second row takes rolls 50..99")
	assert_eq(int(Gen2WorldTreemon.select_at(COMMON, 49)["species"]), 21)
	assert_eq(int(Gen2WorldTreemon.select_at(COMMON, 50)["species"]), 22)


## Running off the end of a table is the source's $ff row, which is NoTreeMon.
func test_select_answers_nothing_when_the_percentages_do_not_reach_the_roll() -> void:
	var short_table: Array = [{"percent": 10, "species": 21, "level": 10}]
	assert_true(Gen2WorldTreemon.select_at(short_table, 50).is_empty())
	assert_false(Gen2WorldTreemon.select_at(short_table, 9).is_empty())


## GetTreeMon's three RandomRange(10) thresholds: 10 percent on BAD, 50 on
## GOOD, 80 on RARE, each asserted at both sides of its own boundary.
func test_each_tier_has_its_own_encounter_threshold() -> void:
	var thresholds: Dictionary = {
		Gen2WorldTreemon.SCORE_BAD: 1,
		Gen2WorldTreemon.SCORE_GOOD: 5,
		Gen2WorldTreemon.SCORE_RARE: 8,
	}
	for tier: int in thresholds:
		var threshold: int = int(thresholds[tier])
		assert_true(
			Gen2WorldTreemon.encounter_allowed(tier, threshold - 1),
			"tier %d allows a roll of %d" % [tier, threshold - 1]
		)
		assert_false(
			Gen2WorldTreemon.encounter_allowed(tier, threshold),
			"tier %d refuses a roll of %d" % [tier, threshold]
		)


## Only the RARE branch walks past the common table's terminator, which is
## visible here as the species that comes back.
func test_a_rare_score_reads_the_rare_table_and_the_others_the_common_one() -> void:
	# (1,1) scores 7, so an ID of 7 is RARE, 6 is GOOD and 2 is BAD.
	var rare: Dictionary = _resolve_with_rolls(SET, 7, 0, 0)
	assert_eq(int(rare["species"]), 214, "RARE reads the rare table")
	assert_eq(int(rare["score"]), Gen2WorldTreemon.SCORE_RARE)
	var good: Dictionary = _resolve_with_rolls(SET, 6, 0, 0)
	assert_eq(int(good["species"]), 21, "GOOD reads the common table")
	assert_eq(int(good["score"]), Gen2WorldTreemon.SCORE_GOOD)
	var bad: Dictionary = _resolve_with_rolls(SET, 2, 0, 0)
	assert_eq(int(bad["species"]), 21, "BAD reads the common table")
	assert_eq(int(bad["score"]), Gen2WorldTreemon.SCORE_BAD)
	# The rolls each answer carries are the ones that produced it, so a caller
	# reporting a headbutt can say why it went the way it did.
	assert_eq(int(rare["encounter_roll"]), 0)
	assert_eq(int(rare["slot_roll"]), 0)


## A set with no rare table is TreeMonSet_Rock's shape. Only the RARE branch
## reads that half, and nothing routes ROCK through GetTreeMon, but a RARE
## score against such a set must still answer nothing rather than fault.
func test_a_set_without_a_rare_table_answers_nothing_on_a_rare_score() -> void:
	var rock: Dictionary = {"common": COMMON, "rare": []}
	assert_true(_resolve_with_rolls(rock, 7, 0, 0).is_empty())
	assert_false(_resolve_with_rolls(rock, 6, 0, 0).is_empty())


## Nothing here rolls on an uninjected generator, unlike advance_roaming().
func test_resolve_refuses_without_a_generator() -> void:
	assert_true(Gen2WorldTreemon.resolve(SET, Vector2i(1, 1), 7, null).is_empty())
	assert_true(Gen2WorldTreemon.resolve({}, Vector2i(1, 1), 7, _seeded()).is_empty())


## CheckSleepingTreeMon picks its list off wTimeOfDay: below DAY_F is morning,
## DAY_F itself is day, anything above is night.
func test_the_asleep_list_key_follows_the_time_of_day_comparison() -> void:
	assert_eq(Gen2WorldTreemon.asleep_list_key(Gen2WorldPalette.TIME_MORNING), "morn")
	assert_eq(Gen2WorldTreemon.asleep_list_key(Gen2WorldPalette.TIME_DAY), "day")
	assert_eq(Gen2WorldTreemon.asleep_list_key(Gen2WorldPalette.TIME_NIGHT), "nite")
	assert_eq(Gen2WorldTreemon.asleep_list_key(Gen2WorldPalette.TIME_DARK), "nite")


func test_starts_asleep_is_membership_and_an_empty_list_never_sleeps() -> void:
	assert_true(Gen2WorldTreemon.starts_asleep(10, [10, 11, 12]))
	assert_false(Gen2WorldTreemon.starts_asleep(13, [10, 11, 12]))
	# Gold and Silver import no lists at all, which is what pokegold shipping
	# neither the routine nor the data means.
	assert_false(Gen2WorldTreemon.starts_asleep(10, []))


func test_sleep_turns_is_the_source_constant() -> void:
	assert_eq(Gen2WorldTreemon.SLEEP_TURNS, 7)
	assert_eq(Gen2WorldTreemon.SLEEP_TURNS & Gen2Status.SLEEP_MASK, 7,
		"TREEMON_SLEEP_TURNS still fits the status byte's low three bits")


## resolve() with both of its rolls pinned. RandomNumberGenerator's methods
## cannot be overridden from GDScript, so the two halves it draws are asserted
## through encounter_allowed() and select_at() and reassembled here.
func _resolve_with_rolls(
	set_record: Dictionary, player_id: int, encounter_roll: int, slot_roll: int
) -> Dictionary:
	var tier: int = Gen2WorldTreemon.score(Vector2i(1, 1), player_id)
	if not Gen2WorldTreemon.encounter_allowed(tier, encounter_roll):
		return {}
	var table: Variant = set_record.get(
		"rare" if tier == Gen2WorldTreemon.SCORE_RARE else "common", []
	)
	if not table is Array or (table as Array).is_empty():
		return {}
	var selected: Dictionary = Gen2WorldTreemon.select_at(table as Array, slot_roll)
	if selected.is_empty():
		return {}
	selected["score"] = tier
	selected["encounter_roll"] = encounter_roll
	return selected


func _seeded() -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = 7
	return generator


## The whole of resolve() against a real generator, which is the only thing the
## split helper above cannot check: that it draws its two rolls in the source's
## order and answers within their bounds.
func test_resolve_draws_both_rolls_and_stays_inside_the_table() -> void:
	var found: Dictionary = {}
	for seed_value: int in 40:
		var generator := RandomNumberGenerator.new()
		generator.seed = seed_value
		var result: Dictionary = Gen2WorldTreemon.resolve(SET, Vector2i(1, 1), 6, generator)
		if result.is_empty():
			continue
		assert_between(int(result["encounter_roll"]), 0, 4, "GOOD only keeps rolls under 5")
		assert_between(int(result["slot_roll"]), 0, 99, "SelectTreeMon rolls RandomRange(100)")
		assert_true(
			int(result["species"]) in [21, 22],
			"a GOOD score stays inside the common table"
		)
		found[int(result["species"])] = true
	assert_gt(found.size(), 0, "forty seeds produce at least one encounter")
