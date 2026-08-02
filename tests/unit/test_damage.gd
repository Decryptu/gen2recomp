extends GutTest

## The damage formula, with both rolls pinned.
##
## Every figure here was worked out by hand, step by step, in the order the
## hardware works it out. That is the only way to test a formula whose answer
## depends on where the truncations fall: a test that recomputes the formula the
## same way the code does would agree with a wrong implementation.

const Fixture := preload("res://tests/unit/battle_fixture.gd")

var _directory: String = ""
var _data: GameData = null


func before_each() -> void:
	_directory = RomCache.directory_for(&"battletest", "0123456789abcdef")
	_data = Fixture.build(_directory)


func after_each() -> void:
	RomCache.clear(_directory)


func _mon(species: int, level: int = 50) -> Gen2BattleMon:
	return Gen2BattleMon.create(_data, species, level)


## A hit at its maximum: no critical, and the spread rolled as high as it goes.
func _hit(
	attacker: Gen2BattleMon, defender: Gen2BattleMon, move: int, critical: bool = false
) -> Dictionary:
	return Gen2Damage.calculate_with(
		attacker, defender, _data.move(move), critical, Gen2Damage.MAX_VARIATION
	)


func test_a_special_move_against_a_resistance() -> void:
	# Pikachu's Thunderbolt on Bulbasaur, both level 50 with perfect DVs and
	# nothing trained. 22 * 95 * 70 / 85 / 50 = 34, +2, x1.5 for STAB = 54,
	# halved by Grass = 27. Poison does not resist Electric, so the second type
	# changes nothing.
	var hit: Dictionary = _hit(_mon(Fixture.PIKACHU), _mon(Fixture.BULBASAUR), Fixture.THUNDERBOLT)
	assert_eq(hit["damage"], 27)
	assert_true(hit["stab"])
	assert_eq(hit["effectiveness"], 5)


func test_the_spread_takes_it_down_to_eighty_five_percent() -> void:
	var attacker: Gen2BattleMon = _mon(Fixture.PIKACHU)
	var defender: Gen2BattleMon = _mon(Fixture.BULBASAUR)
	var lowest: Dictionary = Gen2Damage.calculate_with(
		attacker, defender, _data.move(Fixture.THUNDERBOLT), false, Gen2Damage.MIN_VARIATION
	)
	# 27 * 217 / 255 = 22, truncated from 22.97.
	assert_eq(lowest["damage"], 22)


func test_a_critical_doubles_before_the_minimum_is_added_not_after() -> void:
	# 34 doubled is 68, then +2 is 70, then STAB and the resistance. Adding the
	# minimum first would give 72 and a different answer at the end.
	var hit: Dictionary = _hit(
		_mon(Fixture.PIKACHU), _mon(Fixture.BULBASAUR), Fixture.THUNDERBOLT, true
	)
	assert_eq(hit["damage"], 52)
	assert_true(hit["critical"])


func test_an_immunity_is_treated_as_a_miss() -> void:
	# Geodude is Rock and Ground. Rock does not resist Electric, so the immunity
	# is the second type, which is what makes this worth asserting: the loop has
	# to keep going after a matchup that changed nothing.
	var hit: Dictionary = _hit(_mon(Fixture.PIKACHU), _mon(Fixture.GEODUDE), Fixture.THUNDERBOLT)
	assert_eq(hit["damage"], 0)
	assert_true(hit["immune"])
	assert_eq(hit["effectiveness"], 0)


func test_two_resistances_truncate_on_the_damage_not_on_the_multiplier() -> void:
	# The whole reason the damage does not go through type_effectiveness. Ember
	# on Magcargo is resisted by Fire and again by Rock. Applied to the damage,
	# 24 becomes 12 and then 6. Applied as the announced multiplier of 2/10, it
	# would be 4. The cartridge deals 6 and says "not very effective" on the
	# strength of the 2.
	var hit: Dictionary = _hit(_mon(Fixture.CHARMANDER), _mon(Fixture.MAGCARGO), Fixture.EMBER)
	assert_eq(hit["damage"], 6)
	assert_eq(hit["effectiveness"], 2, "the announced multiplier truncates further")


func test_a_move_with_no_power_deals_nothing_but_still_has_a_matchup() -> void:
	# Growl is not a failed attack. The battle still works out the matchup,
	# because it announces one either way.
	var hit: Dictionary = _hit(_mon(Fixture.PIKACHU), _mon(Fixture.BULBASAUR), Fixture.GROWL)
	assert_eq(hit["damage"], 0)
	assert_false(hit["immune"])
	assert_eq(hit["effectiveness"], RomLayout.MATCHUP_EFFECTIVE)


func test_struggle_gets_neither_stab_nor_the_type_chart() -> void:
	# The cartridge returns out of that step before either is looked at, so a
	# Normal-type Struggle from an Electric Pokémon is exactly its base damage.
	# 22 * 50 * 75 / 69 / 50 = 23, +2 = 25, and nothing after it.
	var hit: Dictionary = _hit(_mon(Fixture.PIKACHU), _mon(Fixture.BULBASAUR), Fixture.STRUGGLE)
	assert_eq(hit["damage"], 25)
	assert_false(hit["stab"])
	assert_eq(hit["effectiveness"], RomLayout.MATCHUP_EFFECTIVE)


func test_the_split_is_by_the_move_type_not_by_the_move() -> void:
	# Every type below Fire is physical and every type from Fire up is special.
	assert_true(Gen2Damage.is_physical(Fixture.NORMAL))
	assert_true(Gen2Damage.is_physical(Fixture.ROCK))
	assert_false(Gen2Damage.is_physical(Fixture.FIRE))
	assert_false(Gen2Damage.is_physical(Fixture.ELECTRIC))


func test_a_raised_attack_stage_is_used() -> void:
	var attacker: Gen2BattleMon = _mon(Fixture.PIKACHU)
	attacker.change_stage("sp_attack", 2)
	# Special Attack doubles from 70 to 140, so the core goes 34 to 68.
	assert_eq(_hit(attacker, _mon(Fixture.BULBASAUR), Fixture.THUNDERBOLT)["damage"], 52)


func test_a_critical_ignores_stages_that_are_working_against_the_attacker() -> void:
	var attacker: Gen2BattleMon = _mon(Fixture.PIKACHU)
	var defender: Gen2BattleMon = _mon(Fixture.BULBASAUR)
	defender.change_stage("sp_defense", 2)

	var ordinary: Dictionary = _hit(attacker, defender, Fixture.THUNDERBOLT)
	assert_eq(ordinary["damage"], 14, "the raised Special Defense counts")

	# On a critical the raised stat is dropped, so this is the unraised figure
	# doubled rather than the raised one.
	assert_eq(_hit(attacker, defender, Fixture.THUNDERBOLT, true)["damage"], 52)


func test_a_critical_keeps_stages_that_are_helping_the_attacker() -> void:
	# The rule is narrower than "a critical ignores stages": the cartridge keeps
	# them when the defender's is the lower of the two.
	var attacker: Gen2BattleMon = _mon(Fixture.PIKACHU)
	attacker.change_stage("sp_attack", 2)
	assert_eq(_hit(attacker, _mon(Fixture.BULBASAUR), Fixture.THUNDERBOLT, true)["damage"], 103)


func test_the_spread_leaves_the_smallest_hits_alone() -> void:
	# There is nothing below one to reduce to, so the cartridge does not try.
	assert_eq(Gen2Damage.apply_variation(1, Gen2Damage.MIN_VARIATION), 1)
	assert_eq(Gen2Damage.apply_variation(0, Gen2Damage.MIN_VARIATION), 0)
	assert_eq(Gen2Damage.apply_variation(2, Gen2Damage.MIN_VARIATION), 1)


func test_a_defense_of_zero_does_not_divide_by_zero() -> void:
	assert_gt(Gen2Damage.base_damage(50, 40, 100, 0), 0)


func test_high_critical_moves_are_worth_two_levels() -> void:
	assert_eq(Gen2Damage.critical_level(Fixture.TACKLE), 0)
	assert_eq(Gen2Damage.critical_level(Fixture.SLASH), 2)
	assert_eq(Gen2Damage.critical_level(Fixture.TACKLE, true), 1, "Focus Energy is worth one")
	assert_eq(Gen2Damage.critical_level(Fixture.SLASH, true), 3)


func test_the_critical_roll_uses_the_chance_for_its_level() -> void:
	# One in fifteen at level zero, which is 17 out of 256, against a roll that
	# has to come in under it.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var criticals: int = 0
	for _try: int in 4000:
		if Gen2Damage.roll_critical(_data.move(Fixture.TACKLE), rng):
			criticals += 1
	assert_between(criticals, 180, 350, "roughly 4000 * 17 / 256")


func test_a_move_with_no_power_never_crits() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for _try: int in 200:
		assert_false(Gen2Damage.roll_critical(_data.move(Fixture.GROWL), rng))
