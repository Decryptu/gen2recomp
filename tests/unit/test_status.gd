extends GutTest

## The status byte and the arithmetic behind it.
##
## What a status does inside a turn is tested in test_battle.gd, where there is a
## battle to do it to. What is here is the byte itself: one status at a time, a
## sleep counter in the low bits, and the two stats a status bends.

var _rng: RandomNumberGenerator = null


func before_each() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = 4242


func test_a_clean_pokemon_has_nothing_on_it() -> void:
	assert_false(Gen2Status.is_afflicted(Gen2Status.NONE))
	assert_false(Gen2Status.is_asleep(Gen2Status.NONE))
	assert_eq(Gen2Status.name_of(Gen2Status.NONE), &"")


func test_the_flags_do_not_overlap_the_sleep_counter() -> void:
	# One byte holds all of it, so this is worth pinning: a Pokémon asleep for
	# seven turns must not read as poisoned.
	assert_eq(Gen2Status.SLEEP_MASK & Gen2Status.POISON, 0)
	assert_eq(Gen2Status.SLEEP_MASK & Gen2Status.BURN, 0)
	assert_eq(Gen2Status.SLEEP_MASK & Gen2Status.FREEZE, 0)
	assert_eq(Gen2Status.SLEEP_MASK & Gen2Status.PARALYSIS, 0)
	assert_false(Gen2Status.has(Gen2Status.SLEEP_MASK, Gen2Status.POISON))


func test_sleep_counts_down_and_takes_itself_off() -> void:
	var status: int = 2
	assert_true(Gen2Status.is_asleep(status))
	assert_eq(Gen2Status.sleep_turns(status), 2)

	status = Gen2Status.tick_sleep(status)
	assert_true(Gen2Status.is_asleep(status))

	status = Gen2Status.tick_sleep(status)
	assert_false(Gen2Status.is_asleep(status))
	assert_eq(status, Gen2Status.NONE, "waking leaves the byte clean")


func test_ticking_a_pokemon_that_is_not_asleep_changes_nothing() -> void:
	assert_eq(Gen2Status.tick_sleep(Gen2Status.BURN), Gen2Status.BURN)


func test_sleep_is_rolled_between_one_and_six_lost_turns() -> void:
	for _roll: int in 200:
		var turns: int = Gen2Status.roll_sleep(_rng)
		assert_between(turns, Gen2Status.MIN_SLEEP, Gen2Status.MAX_SLEEP)
		assert_true(Gen2Status.is_asleep(turns))


func test_a_burn_halves_the_attack_and_paralysis_quarters_the_speed() -> void:
	assert_eq(Gen2Status.apply_burn(100), 50)
	assert_eq(Gen2Status.apply_burn(101), 50, "a shift, so it truncates")
	assert_eq(Gen2Status.apply_paralysis(100), 25)
	assert_eq(Gen2Status.apply_paralysis(103), 25)


func test_neither_can_take_a_stat_below_one() -> void:
	assert_eq(Gen2Status.apply_burn(1), 1)
	assert_eq(Gen2Status.apply_paralysis(3), 1)


func test_a_burn_or_a_poison_costs_an_eighth_and_never_nothing() -> void:
	assert_eq(Gen2Status.residual_damage(80), 10)
	assert_eq(Gen2Status.residual_damage(87), 10, "truncated, not rounded")
	assert_eq(Gen2Status.residual_damage(4), 1, "a small Pokémon still loses one")


func test_full_paralysis_is_about_a_quarter_of_the_time() -> void:
	var stopped: int = 0
	for _roll: int in 2000:
		if Gen2Status.rolls_full_paralysis(_rng):
			stopped += 1
	assert_between(stopped, 400, 600, "64 in 256, which is a quarter")


func test_the_name_of_a_status_is_what_is_on_it() -> void:
	assert_eq(Gen2Status.name_of(Gen2Status.BURN), &"burn")
	assert_eq(Gen2Status.name_of(Gen2Status.POISON), &"poison")
	assert_eq(Gen2Status.name_of(Gen2Status.FREEZE), &"freeze")
	assert_eq(Gen2Status.name_of(Gen2Status.PARALYSIS), &"paralysis")
	assert_eq(Gen2Status.name_of(3), &"sleep")
