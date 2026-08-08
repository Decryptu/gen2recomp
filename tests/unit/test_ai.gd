extends GutTest

## The battle AI: which move a trainer class's own flag word ends up preferring.
##
## Most assertions pick a scenario a layer's own logic settles without the
## tie-break: a discouraged move starts ten points behind, which chance does not
## erase. The genuinely probabilistic layers (Setup, Opportunist) are called
## directly across many seeds to check both outcomes are reachable, which is what
## "50% chance" and "90% chance" claim.

const Fixture := preload("res://tests/unit/battle_fixture.gd")

var _directory: String = ""
var _data: GameData = null
var _rng: RandomNumberGenerator = null


func before_each() -> void:
	_directory = RomCache.directory_for(&"aitest", "0123456789abcdef")
	_data = Fixture.build(_directory)
	_rng = RandomNumberGenerator.new()
	_rng.seed = 42


func after_each() -> void:
	RomCache.clear(_directory)


func _mon(species: int, level: int, moves: Array) -> Gen2BattleMon:
	return Gen2BattleMon.create(_data, species, level, moves)


func test_types_discourages_a_move_the_defender_is_immune_to() -> void:
	# Geodude is Rock/Ground, and this fixture's chart has Electric against
	# Ground at x0: Thunderbolt does nothing, so Types has to prefer Tackle
	# every time, tie-break or no.
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.THUNDERBOLT, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	for seed: int in 10:
		_rng.seed = seed
		var slot: int = Gen2BattleAI.choose_slot(
			pikachu, geodude, _data, RomLayout.AI_TYPES, _rng
		)
		assert_eq(slot, 1, "Thunderbolt is immune; Tackle has to win")


func test_offensive_discourages_a_move_with_no_power() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.HAZE, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	for seed: int in 10:
		_rng.seed = seed
		var slot: int = Gen2BattleAI.choose_slot(
			pikachu, geodude, _data, RomLayout.AI_OFFENSIVE, _rng
		)
		assert_eq(slot, 1, "a class built to attack should never pick the status move")


func test_status_dismisses_a_status_move_the_defender_is_immune_to() -> void:
	# Thunder Wave is Electric with no power; Geodude's Ground typing shrugs off
	# every Electric move in this fixture's chart, paralysis included.
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.THUNDER_WAVE, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	for seed: int in 10:
		_rng.seed = seed
		var slot: int = Gen2BattleAI.choose_slot(
			pikachu, geodude, _data, RomLayout.AI_STATUS, _rng
		)
		assert_eq(slot, 1, "a paralysis move against an immune type has to be dismissed")


func test_basic_discourages_confuse_against_an_already_confused_target() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.SUPERSONIC, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	geodude.substatus = Gen2Substatus.CONFUSED
	for seed: int in 10:
		_rng.seed = seed
		var slot: int = Gen2BattleAI.choose_slot(
			pikachu, geodude, _data, RomLayout.AI_BASIC, _rng
		)
		assert_eq(slot, 1, "confusing an already-confused target does nothing on the cartridge")


func test_basic_discourages_a_status_move_against_an_already_statused_target() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.THUNDER_WAVE, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	geodude.status = Gen2Status.POISON
	for seed: int in 10:
		_rng.seed = seed
		var slot: int = Gen2BattleAI.choose_slot(
			pikachu, geodude, _data, RomLayout.AI_BASIC, _rng
		)
		assert_eq(slot, 1, "a second status never lands, so it should never be preferred")


func test_smart_toxic_is_discouraged_against_a_target_already_hurt() -> void:
	# Toxic's damage ramps over several turns, so it is wasted on a target that
	# might not be around long enough to see the ramp: the real routine
	# discourages it once the target is already below half HP, not a healthy one.
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.TOXIC, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	geodude.hp = 1
	for seed: int in 10:
		_rng.seed = seed
		var slot: int = Gen2BattleAI.choose_slot(
			pikachu, geodude, _data, RomLayout.AI_SMART, _rng
		)
		assert_eq(slot, 1, "Toxic against a nearly-fainted target is discouraged deterministically")


func test_smart_belly_drum_is_discouraged_once_attack_is_already_maxed_out() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.BELLY_DRUM, Fixture.TACKLE])
	pikachu.stages["attack"] = 3
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	for seed: int in 10:
		_rng.seed = seed
		var slot: int = Gen2BattleAI.choose_slot(
			pikachu, geodude, _data, RomLayout.AI_SMART, _rng
		)
		assert_eq(slot, 1, "raising an already-maxed Attack five points further is a bad trade")


func test_smart_skull_bash_is_discouraged_above_a_quarter_hp() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.SKULL_BASH, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	for seed: int in 10:
		_rng.seed = seed
		var slot: int = Gen2BattleAI.choose_slot(
			pikachu, geodude, _data, RomLayout.AI_SMART, _rng
		)
		assert_eq(slot, 1, "a two-turn move is discouraged while there is no urgency")


func test_aggressive_prefers_whichever_move_deals_more_damage() -> void:
	var charmander: Gen2BattleMon = _mon(Fixture.CHARMANDER, 50, [Fixture.EMBER, Fixture.SLASH])
	var bulbasaur: Gen2BattleMon = _mon(Fixture.BULBASAUR, 50, [Fixture.TACKLE])

	var ember_damage: int = int(Gen2Damage.calculate_with(
		charmander, bulbasaur, _data.move(Fixture.EMBER), false, Gen2Damage.MAX_VARIATION
	)["damage"])
	var slash_damage: int = int(Gen2Damage.calculate_with(
		charmander, bulbasaur, _data.move(Fixture.SLASH), false, Gen2Damage.MAX_VARIATION
	)["damage"])
	assert_ne(ember_damage, slash_damage, "the scenario needs the two moves to actually differ")
	var stronger_slot: int = 0 if ember_damage > slash_damage else 1

	for seed: int in 10:
		_rng.seed = seed
		var slot: int = Gen2BattleAI.choose_slot(
			charmander, bulbasaur, _data, RomLayout.AI_AGGRESSIVE, _rng
		)
		assert_eq(slot, stronger_slot, "the harder-hitting move should win every time")


func test_risky_encourages_whichever_move_would_actually_ko() -> void:
	var charmander: Gen2BattleMon = _mon(Fixture.CHARMANDER, 50, [Fixture.EMBER, Fixture.SLASH])
	var bulbasaur: Gen2BattleMon = _mon(Fixture.BULBASAUR, 50, [Fixture.TACKLE])

	var ember_damage: int = int(Gen2Damage.calculate_with(
		charmander, bulbasaur, _data.move(Fixture.EMBER), false, Gen2Damage.MAX_VARIATION
	)["damage"])
	var slash_damage: int = int(Gen2Damage.calculate_with(
		charmander, bulbasaur, _data.move(Fixture.SLASH), false, Gen2Damage.MAX_VARIATION
	)["damage"])
	assert_gt(ember_damage, slash_damage, "the scenario needs Ember to hit harder here")

	# Set HP strictly between the two: Ember KOs, Slash does not.
	bulbasaur.hp = slash_damage + 1
	for seed: int in 10:
		_rng.seed = seed
		var slot: int = Gen2BattleAI.choose_slot(
			charmander, bulbasaur, _data, RomLayout.AI_RISKY, _rng
		)
		assert_eq(slot, 0, "only Ember finishes the target off")


func test_choosing_when_nothing_is_usable_stays_in_range() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])
	pikachu.pp[0] = 0
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	var slot: int = Gen2BattleAI.choose_slot(pikachu, geodude, _data, RomLayout.AI_BASIC, _rng)
	assert_between(slot, 0, Gen2BattleMon.MAX_MOVES - 1)


func test_setup_only_ever_encourages_a_stat_up_move_on_the_first_turn() -> void:
	# Called directly rather than through choose_slot: "50% chance" is a claim
	# about the layer itself, and a hundred seeds is enough to see both halves
	# of a coin without the test being able to fail on an unlucky one.
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.SWORDS_DANCE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])

	var encouraged: bool = false
	var left_alone: bool = false
	for seed: int in 100:
		_rng.seed = seed
		var scores: Array = [20, 20, 20, 20]
		Gen2BattleAI._apply_setup(scores, pikachu, geodude, _data, _rng, 0, 5, Gen2Weather.NONE)
		if scores[0] < 20:
			encouraged = true
		elif scores[0] == 20:
			left_alone = true
	assert_true(encouraged, "half the time a first-turn stat-up move should be favoured")
	assert_true(left_alone, "and half the time left exactly where it started")

	# Past the first turn, the same move should never be encouraged, only ever
	# discouraged or left alone.
	var discouraged_late: bool = false
	for seed: int in 100:
		_rng.seed = seed
		var scores: Array = [20, 20, 20, 20]
		Gen2BattleAI._apply_setup(scores, pikachu, geodude, _data, _rng, 3, 5, Gen2Weather.NONE)
		assert_true(scores[0] >= 20, "a stat-up move past turn one is never encouraged")
		if scores[0] > 20:
			discouraged_late = true
	assert_true(discouraged_late, "and it is discouraged most of the time")


func test_opportunist_only_discourages_stall_moves_once_hp_is_low() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.SWORDS_DANCE, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])

	# Full HP: Opportunist has nothing to say.
	var scores: Array = [20, 20, 20, 20]
	Gen2BattleAI._apply_opportunist(
		scores, pikachu, geodude, _data, _rng, 0, 0, Gen2Weather.NONE
	)
	assert_eq(scores, [20, 20, 20, 20], "a healthy mon has no reason to stop stalling")

	# Well below a quarter: Swords Dance (a stall move by number) is
	# discouraged without a roll involved.
	pikachu.hp = 1
	scores = [20, 20, 20, 20]
	Gen2BattleAI._apply_opportunist(
		scores, pikachu, geodude, _data, _rng, 0, 0, Gen2Weather.NONE
	)
	assert_eq(scores[0], 21)
	assert_eq(scores[1], 20, "Tackle is not a stall move and is left alone")


func test_basic_discourages_disable_against_an_already_disabled_target() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.DISABLE_MOVE, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	geodude.disabled_slot = 0
	for seed: int in 10:
		_rng.seed = seed
		var slot: int = Gen2BattleAI.choose_slot(
			pikachu, geodude, _data, RomLayout.AI_BASIC, _rng
		)
		assert_eq(slot, 1, "disabling an already-disabled target does nothing on the cartridge")


func test_basic_discourages_encore_against_an_already_encored_target() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.ENCORE_MOVE, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	geodude.encored_slot = 0
	for seed: int in 10:
		_rng.seed = seed
		var slot: int = Gen2BattleAI.choose_slot(
			pikachu, geodude, _data, RomLayout.AI_BASIC, _rng
		)
		assert_eq(slot, 1, "encoring an already-encored target does nothing on the cartridge")


func test_basic_discourages_attract_between_the_same_gender() -> void:
	# Same DVs on the same species read the same gender, so Attract can never
	# land between them.
	var attacker: Gen2BattleMon = Gen2BattleMon.create(
		_data, Fixture.BULBASAUR, 50, [Fixture.ATTRACT_MOVE, Fixture.TACKLE],
		Gen2Stats.pack_dvs(0, 0, 0, 0)
	)
	var defender: Gen2BattleMon = Gen2BattleMon.create(
		_data, Fixture.BULBASAUR, 50, [Fixture.TACKLE], Gen2Stats.pack_dvs(0, 0, 0, 0)
	)
	for seed: int in 10:
		_rng.seed = seed
		var slot: int = Gen2BattleAI.choose_slot(attacker, defender, _data, RomLayout.AI_BASIC, _rng)
		assert_eq(slot, 1, "the same gender can never fall for Attract")


func test_basic_discourages_attract_against_a_genderless_target() -> void:
	var attacker: Gen2BattleMon = Gen2BattleMon.create(
		_data, Fixture.BULBASAUR, 50, [Fixture.ATTRACT_MOVE, Fixture.TACKLE]
	)
	# Species 6 is not named in the fixture, so it reads genderless.
	var defender: Gen2BattleMon = Gen2BattleMon.create(_data, 6, 50, [Fixture.TACKLE])
	for seed: int in 10:
		_rng.seed = seed
		var slot: int = Gen2BattleAI.choose_slot(attacker, defender, _data, RomLayout.AI_BASIC, _rng)
		assert_eq(slot, 1, "a genderless target can never fall for Attract")


func test_basic_discourages_mist_and_focus_energy_used_a_second_time() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.MIST_MOVE, Fixture.TACKLE])
	pikachu.substatus |= Gen2Substatus.MIST
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	for seed: int in 10:
		_rng.seed = seed
		var slot: int = Gen2BattleAI.choose_slot(
			pikachu, geodude, _data, RomLayout.AI_BASIC, _rng
		)
		assert_eq(slot, 1, "a second Mist fails without re-applying")

	var pikachu2: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.FOCUS_ENERGY_MOVE, Fixture.TACKLE])
	pikachu2.substatus |= Gen2Substatus.FOCUS_ENERGY
	for seed: int in 10:
		_rng.seed = seed
		var slot: int = Gen2BattleAI.choose_slot(
			pikachu2, geodude, _data, RomLayout.AI_BASIC, _rng
		)
		assert_eq(slot, 1, "a second Focus Energy fails without re-applying")


## `AI_Redundant`'s `.RainDance`, `.SunnyDay` and `.Sandstorm`: a move that would
## set weather already up is a wasted turn and starts ten points behind.
func test_basic_discourages_setting_weather_that_is_already_up() -> void:
	for pair: Array in [
		[Fixture.RAIN_DANCE, Gen2Weather.RAIN],
		[Fixture.SUNNY_DAY, Gen2Weather.SUN],
		[Fixture.SANDSTORM, Gen2Weather.SANDSTORM],
	]:
		var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [int(pair[0]), Fixture.TACKLE])
		var charmander: Gen2BattleMon = _mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE])
		for seed: int in 5:
			_rng.seed = seed
			var slot: int = Gen2BattleAI.choose_slot(
				pikachu, charmander, _data, RomLayout.AI_BASIC, _rng, 0, 0, int(pair[1])
			)
			assert_eq(slot, 1, "move %d under its own weather" % int(pair[0]))


## `.MeanLook` reads the user's own `SUBSTATUS_CANT_RUN`, so it is the enemy
## having already used it that makes a second one redundant.
func test_basic_discourages_a_second_mean_look_from_the_same_pokemon() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.MEAN_LOOK, Fixture.TACKLE])
	var charmander: Gen2BattleMon = _mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE])
	pikachu.substatus |= Gen2Substatus.CANT_RUN
	for seed: int in 5:
		_rng.seed = seed
		assert_eq(
			Gen2BattleAI.choose_slot(pikachu, charmander, _data, RomLayout.AI_BASIC, _rng), 1
		)


## `AI_Smart_Solarbeam`: greatly encouraged in sun, greatly discouraged in rain.
## Both are chances, so the check is that each outcome is reachable and that the
## other one is not.
func test_smart_reads_the_weather_for_solarbeam() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.SOLARBEAM, Fixture.TACKLE])
	var charmander: Gen2BattleMon = _mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE])

	var sunny: Array = []
	var rainy: Array = []
	for seed: int in 40:
		_rng.seed = seed
		sunny.append(Gen2BattleAI.choose_slot(
			pikachu, charmander, _data, RomLayout.AI_SMART, _rng, 0, 0, Gen2Weather.SUN
		))
		_rng.seed = seed
		rainy.append(Gen2BattleAI.choose_slot(
			pikachu, charmander, _data, RomLayout.AI_SMART, _rng, 0, 0, Gen2Weather.RAIN
		))

	assert_gt(sunny.count(0), rainy.count(0), "sun has to prefer Solarbeam more often than rain")
	assert_gt(sunny.count(0), 0)
	assert_gt(rainy.count(1), 0)


## `AI_Smart_Thunder`: 90% to discourage it in sun, where its accuracy halves,
## and nothing at all in rain, where the accuracy step has already answered.
func test_smart_discourages_thunder_in_sun_only() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.THUNDER, Fixture.TACKLE])
	var charmander: Gen2BattleMon = _mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE])

	var discouraged: int = 0
	for seed: int in 40:
		_rng.seed = seed
		if Gen2BattleAI.choose_slot(
			pikachu, charmander, _data, RomLayout.AI_SMART, _rng, 0, 0, Gen2Weather.SUN
		) == 1:
			discouraged += 1

	assert_gt(discouraged, 20, "sun has to push Thunder aside most of the time")

	for seed: int in 10:
		_rng.seed = seed
		var scores: Array = [Gen2BattleAI.DEFAULT_SCORE, Gen2BattleAI.DEFAULT_SCORE]
		Gen2BattleAI._apply_smart(
			scores, pikachu, charmander, _data, _rng, 0, 0, Gen2Weather.RAIN
		)
		assert_eq(int(scores[0]), Gen2BattleAI.DEFAULT_SCORE, "rain says nothing about Thunder")


## `AI_Smart_Sandstorm` greatly discourages it against a target the sand cannot
## reach, which is the same three types the damage itself exempts.
func test_smart_will_not_raise_a_sandstorm_against_a_rock_type() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.SANDSTORM, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	for seed: int in 10:
		_rng.seed = seed
		var scores: Array = [Gen2BattleAI.DEFAULT_SCORE, Gen2BattleAI.DEFAULT_SCORE]
		Gen2BattleAI._apply_smart(scores, pikachu, geodude, _data, _rng, 0, 0, Gen2Weather.NONE)
		assert_eq(int(scores[0]), Gen2BattleAI.DEFAULT_SCORE + 2)


## `AI_Smart_RainDance` reads the target's types first: Rain Dance would suit a
## Water target, so it is worth three points against it, and it would hurt a
## Fire one, so it is worth two the other way.
func test_smart_weighs_rain_dance_by_the_targets_type() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.RAIN_DANCE, Fixture.TACKLE])
	for pair: Array in [[Fixture.MAGCARGO, -2], [Fixture.BULBASAUR, 3]]:
		var target: Gen2BattleMon = _mon(int(pair[0]), 50, [Fixture.TACKLE])
		var scores: Array = [Gen2BattleAI.DEFAULT_SCORE, Gen2BattleAI.DEFAULT_SCORE]
		Gen2BattleAI._apply_smart(scores, pikachu, target, _data, _rng, 0, 0, Gen2Weather.NONE)
		assert_eq(
			int(scores[0]), Gen2BattleAI.DEFAULT_SCORE + int(pair[1]),
			"species %d" % int(pair[0])
		)


## `AI_Smart_WeatherMove`: with no reason to want the weather, three points
## against, however neutral the target's types are.
func test_smart_will_not_set_weather_it_has_no_move_for() -> void:
	var barren: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.RAIN_DANCE, Fixture.TACKLE])
	var bulbasaur: Gen2BattleMon = _mon(Fixture.BULBASAUR, 50, [Fixture.TACKLE])
	var scores: Array = [Gen2BattleAI.DEFAULT_SCORE, Gen2BattleAI.DEFAULT_SCORE]
	Gen2BattleAI._apply_smart(scores, barren, bulbasaur, _data, _rng, 0, 0, Gen2Weather.NONE)
	assert_eq(int(scores[0]), Gen2BattleAI.DEFAULT_SCORE + 3)

	# Thunder is on `RainDanceMoves`, so the same Pokémon with it in a slot no
	# longer wastes the turn. `AIHasMoveInArray` reads the slot, not its PP.
	var armed: Gen2BattleMon = _mon(
		Fixture.PIKACHU, 50, [Fixture.RAIN_DANCE, Fixture.TACKLE, Fixture.THUNDER]
	)
	armed.pp[2] = 0
	var reasons: Array = [Gen2BattleAI.DEFAULT_SCORE, Gen2BattleAI.DEFAULT_SCORE, 0]
	Gen2BattleAI._apply_smart(reasons, armed, bulbasaur, _data, _rng, 0, 0, Gen2Weather.NONE)
	assert_lt(int(reasons[0]), Gen2BattleAI.DEFAULT_SCORE + 3)


## `AI_Smart_TrapTarget`: 50% against a target already bound, and the encourage
## branch needs the user above a quarter of its own health.
func test_smart_will_not_bind_a_target_twice() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.WRAP, Fixture.TACKLE])
	var charmander: Gen2BattleMon = _mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE])
	charmander.trapped_turns = 3

	var raised: int = 0
	for seed: int in 40:
		_rng.seed = seed
		var scores: Array = [Gen2BattleAI.DEFAULT_SCORE, Gen2BattleAI.DEFAULT_SCORE]
		Gen2BattleAI._apply_smart(scores, pikachu, charmander, _data, _rng, 0, 0, Gen2Weather.NONE)
		assert_gte(int(scores[0]), Gen2BattleAI.DEFAULT_SCORE, "a bound target is never encouraged")
		if int(scores[0]) > Gen2BattleAI.DEFAULT_SCORE:
			raised += 1

	assert_between(raised, 10, 30, "roughly half of forty")


func test_smart_binds_a_fresh_target_but_not_on_its_last_legs() -> void:
	var charmander: Gen2BattleMon = _mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE])

	var healthy: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.WRAP, Fixture.TACKLE])
	var lowered: int = 0
	for seed: int in 40:
		_rng.seed = seed
		var scores: Array = [Gen2BattleAI.DEFAULT_SCORE, Gen2BattleAI.DEFAULT_SCORE]
		Gen2BattleAI._apply_smart(scores, healthy, charmander, _data, _rng, 0, 0, Gen2Weather.NONE)
		if int(scores[0]) < Gen2BattleAI.DEFAULT_SCORE:
			lowered += 1
	assert_gt(lowered, 0, "a fresh target is worth binding")

	# `AICheckEnemyQuarterHP` gates the encouragement on the user's own health.
	var spent: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.WRAP, Fixture.TACKLE])
	spent.hp = 1
	for seed: int in 20:
		_rng.seed = seed
		var scores: Array = [Gen2BattleAI.DEFAULT_SCORE, Gen2BattleAI.DEFAULT_SCORE]
		Gen2BattleAI._apply_smart(scores, spent, charmander, _data, _rng, 0, 0, Gen2Weather.NONE)
		assert_eq(int(scores[0]), Gen2BattleAI.DEFAULT_SCORE, "nothing to hold it there with")
