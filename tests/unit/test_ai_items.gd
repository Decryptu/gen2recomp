extends GutTest

## What a trainer reaches into its bag for: `AI_TryItem`'s gates, and the
## `EnemyUsed*` effects behind them.
##
## The gates are rolls against a class's own flag word, so most of these drive a
## range of seeds and count rather than pinning one outcome. The effects are
## exact.

const Fixture := preload("res://tests/unit/battle_fixture.gd")

## Enough of a class word to drive each branch. The three switch bits are
## irrelevant to every item decision and are left out.
const NO_FLAGS: int = 0
const ALWAYS: int = RomLayout.ALWAYS_USE
const CONTEXT: int = RomLayout.CONTEXT_USE
const UNKNOWN: int = RomLayout.UNKNOWN_USE

var _directory: String = ""
var _data: GameData = null
var _rng: RandomNumberGenerator = null


func before_each() -> void:
	_directory = RomCache.directory_for(&"aiitemtest", "0123456789abcdef")
	_data = Fixture.build(_directory)
	_rng = RandomNumberGenerator.new()
	_rng.seed = 7


func after_each() -> void:
	RomCache.clear(_directory)


func _mon(level: int = 50) -> Gen2BattleMon:
	return Gen2BattleMon.create(_data, Fixture.PIKACHU, level, [Fixture.TACKLE])


## How often [param item] is reached for over a spread of seeds, so a branch that
## is a coin flip reads as one rather than as whichever way seed 7 fell.
func _use_rate(
	item: int, mon: Gen2BattleMon, flags: int, turns_taken: int, seeds: int = 64
) -> int:
	var used: int = 0
	for seed: int in seeds:
		_rng.seed = seed
		if Gen2AIItems.choose(mon, [item], flags, turns_taken, _rng) == item:
			used += 1
	return used


func test_nothing_is_spent_on_a_pokemon_above_half_health() -> void:
	var mon: Gen2BattleMon = _mon()

	for flags: int in [NO_FLAGS, ALWAYS, CONTEXT, UNKNOWN]:
		assert_eq(
			_use_rate(Gen2AIItems.POTION, mon, flags, 1), 0,
			"every branch of .HealItem refuses above half"
		)


func test_a_potion_is_certain_below_a_quarter_and_a_coin_flip_above_it() -> void:
	var mon: Gen2BattleMon = _mon()
	mon.hp = 1

	assert_eq(_use_rate(Gen2AIItems.POTION, mon, NO_FLAGS, 1), 64, "always, under a quarter")

	# Between a quarter and a half: `.HealItem`'s own 50 percent + 1.
	mon.hp = int(mon.max_hp() * 0.4)
	assert_between(_use_rate(Gen2AIItems.POTION, mon, NO_FLAGS, 1), 20, 44)


## `.CheckQuarterHP` is the one branch that refuses while still above a quarter,
## which makes an UNKNOWN_USE class strictly stingier than a plain one.
func test_the_unknown_use_branch_refuses_between_a_quarter_and_a_half() -> void:
	var mon: Gen2BattleMon = _mon()
	mon.hp = int(mon.max_hp() * 0.4)

	assert_eq(_use_rate(Gen2AIItems.POTION, mon, UNKNOWN, 1), 0)

	mon.hp = 1
	# Below a quarter it uses unless the 20-percent roll comes up.
	assert_between(_use_rate(Gen2AIItems.POTION, mon, UNKNOWN, 1), 40, 62)


func test_a_full_heal_needs_a_status_to_cure() -> void:
	var mon: Gen2BattleMon = _mon()

	assert_eq(_use_rate(Gen2AIItems.FULL_HEAL, mon, ALWAYS, 1), 0, "nothing to cure")

	mon.status = Gen2Status.BURN
	assert_eq(_use_rate(Gen2AIItems.FULL_HEAL, mon, ALWAYS, 1), 64)


## `.StatusCheckContext`: a class that reads the context spends a cure on sleep
## and freeze, the two statuses that cost whole turns, and ignores a burn.
func test_a_context_class_cures_only_what_is_worth_curing() -> void:
	var mon: Gen2BattleMon = _mon()

	mon.status = Gen2Status.BURN
	assert_eq(_use_rate(Gen2AIItems.FULL_HEAL, mon, CONTEXT, 1), 0)

	mon.status = Gen2Status.FREEZE
	assert_eq(_use_rate(Gen2AIItems.FULL_HEAL, mon, CONTEXT, 1), 64)

	mon.status = Gen2Status.MIN_SLEEP
	assert_eq(_use_rate(Gen2AIItems.FULL_HEAL, mon, CONTEXT, 1), 64)


## A Toxic that has been ramping for four turns is worth a cure on a coin flip
## even though a plain poison is not.
func test_a_context_class_cures_a_ramped_toxic_but_not_a_fresh_one() -> void:
	var mon: Gen2BattleMon = _mon()
	mon.status = Gen2Status.POISON
	mon.toxic_counter = 1

	assert_eq(_use_rate(Gen2AIItems.FULL_HEAL, mon, CONTEXT, 1), 0, "too early to bother")

	mon.toxic_counter = Gen2AIItems.TOXIC_PATIENCE
	assert_between(_use_rate(Gen2AIItems.FULL_HEAL, mon, CONTEXT, 1), 20, 44)


## An X item is a first-turn play. After that only an ALWAYS_USE class reaches
## for one, and rarely.
func test_an_x_item_is_almost_only_used_on_the_turn_it_comes_out() -> void:
	var mon: Gen2BattleMon = _mon()

	assert_eq(_use_rate(Gen2AIItems.X_ATTACK, mon, ALWAYS, 0), 64, "always, first turn out")
	assert_eq(_use_rate(Gen2AIItems.X_ATTACK, mon, NO_FLAGS, 1), 0, "never, once it has acted")
	assert_between(
		_use_rate(Gen2AIItems.X_ATTACK, mon, ALWAYS, 1), 4, 26,
		"an ALWAYS_USE class still tries, on the 20 percent roll"
	)


## The table's order decides which of two items is reached for, not the order
## the trainer carries them in.
func test_the_table_order_decides_between_two_items() -> void:
	var mon: Gen2BattleMon = _mon()
	mon.hp = 1

	# Full Restore is the first row and Potion the fifth, so the order the
	# trainer holds them in changes nothing.
	assert_eq(
		Gen2AIItems.choose(mon, [Gen2AIItems.POTION, Gen2AIItems.FULL_RESTORE], ALWAYS, 1, _rng),
		Gen2AIItems.FULL_RESTORE
	)
	assert_eq(
		Gen2AIItems.choose(mon, [Gen2AIItems.FULL_RESTORE, Gen2AIItems.POTION], ALWAYS, 1, _rng),
		Gen2AIItems.FULL_RESTORE
	)


func test_a_trainer_with_nothing_left_reaches_for_nothing() -> void:
	var mon: Gen2BattleMon = _mon()
	mon.hp = 1
	assert_eq(Gen2AIItems.choose(mon, [], ALWAYS, 1, _rng), 0)


## `.IsHighestLevel`: a trainer leading with its weakest does not open the bag.
func test_the_bag_stays_shut_for_a_lead_that_is_not_the_highest_level() -> void:
	var lead: Gen2BattleMon = _mon(20)
	var bench: Gen2BattleMon = _mon(30)
	assert_false(Gen2AIItems.is_highest_level(Gen2Party.create([lead, bench])))
	assert_true(Gen2AIItems.is_highest_level(Gen2Party.create([bench, lead])))
	# Level-tied counts as highest: the check is "not lower", not "strictly above".
	assert_true(Gen2AIItems.is_highest_level(Gen2Party.create([_mon(20), _mon(20)])))


func test_the_potions_put_back_their_own_numbers() -> void:
	for pair: Array in [
		[Gen2AIItems.POTION, 20], [Gen2AIItems.SUPER_POTION, 50],
		[Gen2AIItems.HYPER_POTION, 200],
	]:
		var mon: Gen2BattleMon = _mon()
		mon.hp = 1
		Gen2AIItems.apply(mon, int(pair[0]))
		assert_eq(mon.hp, mini(1 + int(pair[1]), mon.max_hp()), str(pair[0]))


func test_a_max_potion_fills_the_bar_and_leaves_the_status_alone() -> void:
	var mon: Gen2BattleMon = _mon()
	mon.hp = 1
	mon.status = Gen2Status.BURN

	Gen2AIItems.apply(mon, Gen2AIItems.MAX_POTION)

	assert_eq(mon.hp, mon.max_hp())
	assert_eq(mon.status, Gen2Status.BURN, "a Max Potion is not a cure")


## Full Restore clears the confusion; Full Heal does not, which pret documents
## as a bug rather than a rule and which is kept here for that reason.
func test_a_full_restore_clears_the_confusion_a_full_heal_leaves_behind() -> void:
	var restored: Gen2BattleMon = _mon()
	restored.hp = 1
	restored.status = Gen2Status.BURN
	restored.substatus |= Gen2Substatus.CONFUSED
	restored.confusion_turns = 3

	Gen2AIItems.apply(restored, Gen2AIItems.FULL_RESTORE)

	assert_eq(restored.hp, restored.max_hp())
	assert_eq(restored.status, Gen2Status.NONE)
	assert_false(Gen2Substatus.has(restored.substatus, Gen2Substatus.CONFUSED))

	var healed: Gen2BattleMon = _mon()
	healed.status = Gen2Status.BURN
	healed.substatus |= Gen2Substatus.CONFUSED

	Gen2AIItems.apply(healed, Gen2AIItems.FULL_HEAL)

	assert_eq(healed.status, Gen2Status.NONE)
	assert_true(
		Gen2Substatus.has(healed.substatus, Gen2Substatus.CONFUSED),
		"the confusion survives a Full Heal"
	)


func test_a_cure_clears_the_toxic_ramp_with_the_status() -> void:
	var mon: Gen2BattleMon = _mon()
	mon.status = Gen2Status.POISON
	mon.toxic_counter = 5

	Gen2AIItems.apply(mon, Gen2AIItems.FULL_HEAL)

	assert_eq(mon.status, Gen2Status.NONE)
	assert_eq(mon.toxic_counter, 0)


func test_the_four_x_stats_each_raise_their_own_stage_by_one() -> void:
	for pair: Array in [
		[Gen2AIItems.X_ATTACK, "attack"], [Gen2AIItems.X_DEFEND, "defense"],
		[Gen2AIItems.X_SPEED, "speed"], [Gen2AIItems.X_SPECIAL, "sp_attack"],
	]:
		var mon: Gen2BattleMon = _mon()
		Gen2AIItems.apply(mon, int(pair[0]))
		assert_eq(mon.stage(String(pair[1])), 1, String(pair[1]))
	# X Special is Sp. Attack alone: nothing gives Sp. Defense back.
	var special: Gen2BattleMon = _mon()
	Gen2AIItems.apply(special, Gen2AIItems.X_SPECIAL)
	assert_eq(special.stage("sp_defense"), 0)


func test_the_three_flag_x_items_set_their_own_substatus() -> void:
	for pair: Array in [
		[Gen2AIItems.X_ACCURACY, Gen2Substatus.X_ACCURACY],
		[Gen2AIItems.GUARD_SPEC, Gen2Substatus.MIST],
		[Gen2AIItems.DIRE_HIT, Gen2Substatus.FOCUS_ENERGY],
	]:
		var mon: Gen2BattleMon = _mon()
		Gen2AIItems.apply(mon, int(pair[0]))
		assert_true(Gen2Substatus.has(mon.substatus, int(pair[1])), str(pair[0]))
