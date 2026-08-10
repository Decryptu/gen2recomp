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


func test_selfdestruct_halves_defense_before_the_formula() -> void:
	var attacker: Gen2BattleMon = _mon(Fixture.PIKACHU)
	var defender: Gen2BattleMon = _mon(Fixture.BULBASAUR)
	var move: Dictionary = _data.move(Fixture.SELFDESTRUCT)
	var ordinary: Dictionary = Gen2Damage.calculate_with(
		attacker, defender, move, false, Gen2Damage.MAX_VARIATION, false
	)
	var halved: Dictionary = Gen2Damage.calculate_with(
		attacker, defender, move, false, Gen2Damage.MAX_VARIATION, true
	)
	assert_gt(int(halved["damage"]), int(ordinary["damage"]))


## `DoWeatherModifiers` runs at the top of `BattleCommand_Stab`, ahead of both
## STAB and the matchup, so its tenths compound with everything after it rather
## than scaling the finished figure.
##
## Charmander's Ember on Bulbasaur, both level 50 with perfect DVs: 80 Sp.Atk
## against 85 Sp.Def, so 22 * 40 * 80 / 85 / 50 = 16, +2 = 18. Sun
## takes that to 27 before STAB makes it 40 and Grass doubles it to 80; rain
## takes it to 9, then 13 and 26. Without weather it is 18, 27 and 54.
func test_the_weather_multiplies_before_stab_and_the_matchup() -> void:
	var attacker: Gen2BattleMon = _mon(Fixture.CHARMANDER)
	var defender: Gen2BattleMon = _mon(Fixture.BULBASAUR)
	for pair: Array in [
		[Gen2Weather.NONE, 54], [Gen2Weather.SUN, 80], [Gen2Weather.RAIN, 26],
		[Gen2Weather.SANDSTORM, 54],
	]:
		var hit: Dictionary = Gen2Damage.calculate_with(
			attacker, defender, _data.move(Fixture.EMBER), false, Gen2Damage.MAX_VARIATION,
			false, int(pair[0])
		)
		assert_eq(int(hit["damage"]), int(pair[1]), "weather %d" % int(pair[0]))


## The type table answers first and the effect table only when it did not, which
## is how Solarbeam's Grass row and its own effect row stay out of each other's
## way.
func test_the_weather_reads_the_type_table_before_the_move_table() -> void:
	assert_eq(
		Gen2Weather.damage_modifier(
			Gen2Weather.RAIN, RomLayout.TYPE_WATER, Gen2MoveEffect.SOLARBEAM
		),
		Gen2Weather.BOOSTED,
		"a Water Solarbeam does not exist, but the type row still wins"
	)
	assert_eq(
		Gen2Weather.damage_modifier(Gen2Weather.RAIN, 22, Gen2MoveEffect.SOLARBEAM),
		Gen2Weather.WEAKENED
	)
	assert_eq(
		Gen2Weather.damage_modifier(Gen2Weather.SUN, 22, Gen2MoveEffect.SOLARBEAM),
		Gen2Weather.UNCHANGED,
		"the move table has no sun row"
	)


## `.Update` floors a modified hit at one and answers `$FFFF` past two bytes.
func test_a_weakened_hit_never_rounds_away_to_nothing() -> void:
	assert_eq(Gen2Weather.apply_damage_modifier(1, Gen2Weather.WEAKENED), 1)
	assert_eq(
		Gen2Weather.apply_damage_modifier(0xFFFF, Gen2Weather.BOOSTED), Gen2Weather.MAX_DAMAGE
	)


## Struggle leaves `BattleCommand_Stab` on its first two instructions, so the
## weather never reaches it any more than STAB or the chart does.
func test_struggle_is_outside_the_weather_as_well() -> void:
	var attacker: Gen2BattleMon = _mon(Fixture.CHARMANDER)
	var defender: Gen2BattleMon = _mon(Fixture.BULBASAUR)
	var plain: Dictionary = Gen2Damage.calculate_with(
		attacker, defender, _data.move(Fixture.STRUGGLE), false, Gen2Damage.MAX_VARIATION
	)
	var sunny: Dictionary = Gen2Damage.calculate_with(
		attacker, defender, _data.move(Fixture.STRUGGLE), false, Gen2Damage.MAX_VARIATION,
		false, Gen2Weather.SUN
	)
	assert_eq(int(sunny["damage"]), int(plain["damage"]))


## `TypeBoostItems`: the item boost lands on the finished base damage, before
## the critical multiplier and so before the cap, the weather, STAB and the
## matchup, which is where `PlayerAttackDamage` applies it.
##
## Pikachu's Thunderbolt on Bulbasaur is 27 without one. A Magnet takes the base
## 34 to 37 before the +2, so 39, then STAB 58, then halved by Grass to 29.
func test_a_type_boosting_item_lifts_a_move_of_its_own_type() -> void:
	var attacker: Gen2BattleMon = _mon(Fixture.PIKACHU)
	var defender: Gen2BattleMon = _mon(Fixture.BULBASAUR)
	assert_eq(int(_hit(attacker, defender, Fixture.THUNDERBOLT)["damage"]), 27)

	attacker.item = Fixture.MAGNET

	assert_eq(int(_hit(attacker, defender, Fixture.THUNDERBOLT)["damage"]), 29)


## The row has to match the type as well as the effect, so a Magnet does nothing
## for a Normal move.
func test_a_type_boosting_item_does_nothing_for_another_type() -> void:
	var attacker: Gen2BattleMon = _mon(Fixture.PIKACHU)
	var defender: Gen2BattleMon = _mon(Fixture.BULBASAUR)
	var plain: int = int(_hit(attacker, defender, Fixture.TACKLE)["damage"])

	attacker.item = Fixture.MAGNET

	assert_eq(int(_hit(attacker, defender, Fixture.TACKLE)["damage"]), plain)


## `LightBallBoost` sits on the special branch and `ThickClubBoost` on the
## physical one, so each doubles the stat its own branch had already chosen and
## neither touches the other.
func test_light_ball_doubles_pikachus_special_attack_and_nothing_else() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU)
	var defender: Gen2BattleMon = _mon(Fixture.BULBASAUR)
	var special: int = int(_hit(pikachu, defender, Fixture.THUNDERBOLT)["damage"])
	var physical: int = int(_hit(pikachu, defender, Fixture.TACKLE)["damage"])

	pikachu.item = Fixture.LIGHT_BALL

	assert_gt(int(_hit(pikachu, defender, Fixture.THUNDERBOLT)["damage"]), special)
	assert_eq(int(_hit(pikachu, defender, Fixture.TACKLE)["damage"]), physical)

	# And nothing at all on anybody else.
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE)
	var others: int = int(_hit(geodude, defender, Fixture.THUNDERBOLT)["damage"])
	geodude.item = Fixture.LIGHT_BALL
	assert_eq(int(_hit(geodude, defender, Fixture.THUNDERBOLT)["damage"]), others)


## `SpeciesItemBoost` answers for two species, not one: Thick Club works on
## Marowak as well as Cubone, and only on a physical move.
func test_thick_club_doubles_attack_for_cubone_and_marowak_only() -> void:
	var defender: Gen2BattleMon = _mon(Fixture.BULBASAUR)
	for pair: Array in [
		[Fixture.CUBONE, true], [Fixture.MAROWAK, true], [Fixture.GEODUDE, false]
	]:
		var attacker: Gen2BattleMon = _mon(int(pair[0]))
		var plain: int = int(_hit(attacker, defender, Fixture.TACKLE)["damage"])
		attacker.item = Fixture.THICK_CLUB
		var held: int = int(_hit(attacker, defender, Fixture.TACKLE)["damage"])
		if bool(pair[1]):
			assert_gt(held, plain, "species %d" % int(pair[0]))
		else:
			assert_eq(held, plain, "species %d" % int(pair[0]))


## `DittoMetalPowder` is half again on whichever defence the hit was read
## against, and only for a Ditto holding it.
func test_metal_powder_is_half_again_on_a_dittos_defence() -> void:
	var attacker: Gen2BattleMon = _mon(Fixture.PIKACHU)
	var ditto: Gen2BattleMon = _mon(Fixture.DITTO)
	var plain: int = int(_hit(attacker, ditto, Fixture.TACKLE)["damage"])

	ditto.item = Fixture.METAL_POWDER

	assert_lt(int(_hit(attacker, ditto, Fixture.TACKLE)["damage"]), plain)

	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE)
	var others: int = int(_hit(attacker, geodude, Fixture.TACKLE)["damage"])
	geodude.item = Fixture.METAL_POWDER
	assert_eq(int(_hit(attacker, geodude, Fixture.TACKLE)["damage"]), others)


## The Scope Lens is one more critical level, added after the move's own two and
## Focus Energy's one, in `BattleCommand_Critical`'s own order.
func test_the_scope_lens_is_one_more_critical_level() -> void:
	assert_eq(Gen2Damage.critical_level(Fixture.TACKLE, false, true), 1)
	assert_eq(Gen2Damage.critical_level(Fixture.TACKLE, true, true), 2)
	assert_eq(
		Gen2Damage.critical_level(Fixture.SLASH, true, true), 4,
		"a high-critical move is two of its own"
	)


func test_the_scope_lens_makes_criticals_more_common() -> void:
	var rng := RandomNumberGenerator.new()
	var plain: int = 0
	var lensed: int = 0
	for seed: int in 2000:
		rng.seed = seed
		if Gen2Damage.roll_critical(_data.move(Fixture.TACKLE), rng):
			plain += 1
		rng.seed = seed
		if Gen2Damage.roll_critical(_data.move(Fixture.TACKLE), rng, false, true):
			lensed += 1
	assert_gt(lensed, plain * 3 / 2, "level 1 is 32 in 256 against level 0's 17")


## The screen doubles the defending stat inside the formula rather than halving
## the finished damage, so it lands before the divide and before STAB.
##
## Pikachu's Thunderbolt on Bulbasaur is 22 * 95 * 70 / 85 / 50 = 34 without
## one; with Reflect the defence is 170, giving 17, then +2 = 19, x1.5 STAB = 28
## and halved by Grass = 14. Reflect is the physical screen, so a special move
## reads Light Screen and nothing else.
func test_light_screen_doubles_the_special_defence_a_special_move_divides_by() -> void:
	var attacker: Gen2BattleMon = _mon(Fixture.PIKACHU)
	var defender: Gen2BattleMon = _mon(Fixture.BULBASAUR)
	var move: Dictionary = _data.move(Fixture.THUNDERBOLT)

	var bare: Dictionary = Gen2Damage.calculate_with(
		attacker, defender, move, false, Gen2Damage.MAX_VARIATION
	)
	var screened: Dictionary = Gen2Damage.calculate_with(
		attacker, defender, move, false, Gen2Damage.MAX_VARIATION,
		false, Gen2Weather.NONE, Gen2Screens.LIGHT_SCREEN
	)
	var wrong_screen: Dictionary = Gen2Damage.calculate_with(
		attacker, defender, move, false, Gen2Damage.MAX_VARIATION,
		false, Gen2Weather.NONE, Gen2Screens.REFLECT
	)

	assert_eq(bare["damage"], 27)
	assert_eq(screened["damage"], 14)
	assert_eq(wrong_screen["damage"], 27, "the physical screen guards nothing special")


func test_reflect_is_the_physical_screen_and_light_screen_guards_nothing_physical() -> void:
	var attacker: Gen2BattleMon = _mon(Fixture.GEODUDE)
	var defender: Gen2BattleMon = _mon(Fixture.CHARMANDER)
	var move: Dictionary = _data.move(Fixture.TACKLE)

	var bare: int = int(Gen2Damage.calculate_with(
		attacker, defender, move, false, Gen2Damage.MAX_VARIATION
	)["damage"])
	var reflected: int = int(Gen2Damage.calculate_with(
		attacker, defender, move, false, Gen2Damage.MAX_VARIATION,
		false, Gen2Weather.NONE, Gen2Screens.REFLECT
	)["damage"])
	var light: int = int(Gen2Damage.calculate_with(
		attacker, defender, move, false, Gen2Damage.MAX_VARIATION,
		false, Gen2Weather.NONE, Gen2Screens.LIGHT_SCREEN
	)["damage"])

	assert_lt(reflected, bare)
	assert_eq(light, bare)


## `PlayerAttackDamage` doubles the pair before `CheckDamageStatsCritical`, and
## the no-carry branch reloads the unmodified stat over it, so the same critical
## that ignores the defender's stages ignores its screen with them. A critical
## against a defender whose stages are no better than the attacker's keeps both.
func test_a_critical_that_ignores_the_stages_ignores_the_screen_with_them() -> void:
	var attacker: Gen2BattleMon = _mon(Fixture.PIKACHU)
	var defender: Gen2BattleMon = _mon(Fixture.BULBASAUR)
	var move: Dictionary = _data.move(Fixture.THUNDERBOLT)

	# Nothing has moved, so the two stages are equal and the critical takes the
	# `.specialcrit` branch that discards the screen.
	var critical_bare: int = int(Gen2Damage.calculate_with(
		attacker, defender, move, true, Gen2Damage.MAX_VARIATION
	)["damage"])
	var critical_screened: int = int(Gen2Damage.calculate_with(
		attacker, defender, move, true, Gen2Damage.MAX_VARIATION,
		false, Gen2Weather.NONE, Gen2Screens.LIGHT_SCREEN
	)["damage"])

	assert_eq(critical_screened, critical_bare, "the critical went through the screen")

	# Raise the attacker's own stage so `CheckDamageStatsCritical` carries and
	# keeps the loaded pair, screen included.
	attacker.change_stage("sp_attack", 2)
	var kept_bare: int = int(Gen2Damage.calculate_with(
		attacker, defender, move, true, Gen2Damage.MAX_VARIATION
	)["damage"])
	var kept_screened: int = int(Gen2Damage.calculate_with(
		attacker, defender, move, true, Gen2Damage.MAX_VARIATION,
		false, Gen2Weather.NONE, Gen2Screens.LIGHT_SCREEN
	)["damage"])

	assert_lt(kept_screened, kept_bare, "this critical kept the screen")


## `TruncateHL_BC` shifts the attack and the defence together, two bits at a
## time, until both fit in a byte, flooring each at one. A screened defence is
## the common way past a byte.
func test_truncate_stats_shifts_both_until_each_fits_in_a_byte() -> void:
	assert_eq(Gen2Damage.truncate_stats(200, 255), [200, 255], "nothing to do")
	assert_eq(Gen2Damage.truncate_stats(100, 400), [25, 100], "one pass of four")
	assert_eq(Gen2Damage.truncate_stats(999, 999), [249, 249])
	# Three passes: 5000 to 1250 to 312 to 78, and the partner floors at one
	# rather than at zero on the first of them, which is `inc c`.
	assert_eq(Gen2Damage.truncate_stats(3, 5000), [1, 78], "the floor is one, not zero")
	assert_eq(Gen2Damage.truncate_stats(1, 1), [1, 1])


## The single-player fix is Crystal's alone: pokegold has no `wLinkMode` check at
## all, so one pass is all a value gets there and anything still over a byte
## wraps. `docs/bugs_and_glitches.md` calls it "Reflect and Light Screen can make
## (Special) Defense wrap around above 1024".
func test_gold_and_silver_wrap_a_screened_defence_above_1024() -> void:
	# 1200 / 4 is 300, which does not fit; Crystal shifts again to 75, Gold keeps
	# 300 and hands back its low byte, 44.
	assert_eq(Gen2Damage.truncate_stats(100, 1200, true), [6, 75])
	assert_eq(Gen2Damage.truncate_stats(100, 1200, false), [25, 44])
	# Under the threshold the two agree, since one pass is enough for both.
	assert_eq(
		Gen2Damage.truncate_stats(100, 1000, true), Gen2Damage.truncate_stats(100, 1000, false)
	)


## `BattleCommand_Stab`'s matchup walk skips the rows past the `-2` marker unless
## the target has been identified, and those two rows are Ghost's immunities.
func test_foresight_opens_a_ghost_to_normal_damage() -> void:
	var attacker: Gen2BattleMon = _mon(Fixture.PIKACHU)
	var defender: Gen2BattleMon = _mon(Fixture.GASTLY)
	var move: Dictionary = _data.move(Fixture.TACKLE)

	var blocked: Dictionary = Gen2Damage.stab_damage(attacker, defender, move, 40)
	assert_true(blocked["immune"])
	assert_eq(blocked["damage"], 0)

	var opened: Dictionary = Gen2Damage.stab_damage(
		attacker, defender, move, 40, Gen2Weather.NONE, true
	)
	assert_false(opened["immune"])
	assert_eq(opened["damage"], 40, "neutral, so the figure is untouched")
	assert_eq(opened["effectiveness"], RomLayout.MATCHUP_EFFECTIVE)


## Nothing else moves: the flag cancels the two Ghost rows and no other.
func test_foresight_leaves_every_other_matchup_alone() -> void:
	var attacker: Gen2BattleMon = _mon(Fixture.PIKACHU)
	var defender: Gen2BattleMon = _mon(Fixture.GEODUDE)
	var move: Dictionary = _data.move(Fixture.THUNDERBOLT)

	var blocked: Dictionary = Gen2Damage.stab_damage(attacker, defender, move, 40)
	var identified: Dictionary = Gen2Damage.stab_damage(
		attacker, defender, move, 40, Gen2Weather.NONE, true
	)
	assert_true(blocked["immune"])
	assert_true(identified["immune"], "Ground still shrugs off Electric")


## `BattleCommand_BeatUp` hands `damagecalc` a party member's level in `e`, which
## is the one figure the formula does not read off the Pokémon on the field.
func test_damage_calc_takes_a_level_of_its_own() -> void:
	var attacker: Gen2BattleMon = _mon(Fixture.PIKACHU, 50)
	# Beat Up's power of 10 against Gastly's base Defense of 30, from Pikachu's own
	# base Attack of 55. At level 50: 22 * 10 * 55 / 30 / 50 = 8, +2 = 10.
	assert_eq(
		Gen2Damage.damage_calc(attacker, 10, 55, 30, false, Fixture.DARK, false, 50), 10
	)
	# At level 10 the first term is 4 + 2 = 6: 6 * 10 * 55 / 30 / 50 = 2, +2 = 4.
	assert_eq(
		Gen2Damage.damage_calc(attacker, 10, 55, 30, false, Fixture.DARK, false, 10), 4
	)
	# -1 is the attacker's own, which is what every other caller passes.
	assert_eq(
		Gen2Damage.damage_calc(attacker, 10, 55, 30, false, Fixture.DARK, false, -1),
		Gen2Damage.damage_calc(attacker, 10, 55, 30, false, Fixture.DARK, false, 50)
	)
