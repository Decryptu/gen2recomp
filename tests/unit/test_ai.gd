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


## `AI_Smart_MeanLook`: a healthy user with a bench wants the trap against a
## costly target state, while a low-health user or a lone user dismisses it.
func test_smart_mean_look_reads_health_bench_and_target_state() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.MEAN_LOOK, Fixture.TACKLE])
	var charmander: Gen2BattleMon = _mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE])

	var lone: Array = [20, 20, 20, 20]
	Gen2BattleAI._apply_smart(
		lone, pikachu, charmander, _data, _rng, 0, 0, Gen2Weather.NONE,
		Gen2Screens.NONE, Gen2Screens.NONE, false, Gen2AISwitch.BASE_SCORE
	)
	assert_eq(int(lone[0]), 30, "a lone user cannot leave behind a Mean Look")

	pikachu.hp = pikachu.max_hp() / 4
	var hurt: Array = [20, 20, 20, 20]
	Gen2BattleAI._apply_smart(
		hurt, pikachu, charmander, _data, _rng, 0, 0, Gen2Weather.NONE,
		Gen2Screens.NONE, Gen2Screens.NONE, true, Gen2AISwitch.BASE_SCORE
	)
	assert_eq(int(hurt[0]), 30, "a user below half health should not trap")

	pikachu.hp = pikachu.max_hp()
	charmander.substatus |= Gen2Substatus.IDENTIFIED
	var wanted: Dictionary = {}
	for seed_value: int in 60:
		_rng.seed = seed_value
		var scores: Array = [20, 20, 20, 20]
		Gen2BattleAI._apply_smart(
			scores, pikachu, charmander, _data, _rng, 0, 0, Gen2Weather.NONE,
			Gen2Screens.NONE, Gen2Screens.NONE, true, Gen2AISwitch.BASE_SCORE - 1
		)
		wanted[int(scores[0])] = true
	assert_true(wanted.has(17), "an identified target reaches Mean Look's strong branch")


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


## `AI_Smart_Heal`, which the three time-based heals are labels on too: the AI
## reads its own health, and a healthy AI would rather attack.
func test_smart_heal_is_discouraged_while_the_ai_is_healthy() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.RECOVER, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	for seed: int in 10:
		_rng.seed = seed
		var slot: int = Gen2BattleAI.choose_slot(
			pikachu, geodude, _data, RomLayout.AI_SMART, _rng
		)
		assert_eq(slot, 1, "healing a full bar is wasted")


## Below a quarter it is greatly encouraged nine times in ten, which is enough
## to win against a plain attack on most seeds.
func test_smart_heal_is_encouraged_once_the_ai_is_nearly_out() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.MORNING_SUN, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	var chose_heal: int = 0
	for seed: int in 20:
		_rng.seed = seed
		pikachu.hp = 1
		if Gen2BattleAI.choose_slot(pikachu, geodude, _data, RomLayout.AI_SMART, _rng) == 0:
			chose_heal += 1
	assert_gt(chose_heal, 10, "the 90% branch should dominate twenty seeds")


## `AI_Redundant.PerishSong` reads `wPlayerSubStatus1`, the target's own: a song
## over a target already counting down restarts nothing, so it is a wasted turn.
func test_basic_treats_a_second_perish_song_as_redundant() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.PERISH_SONG, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	geodude.substatus |= Gen2Substatus.PERISH

	for seed: int in 10:
		_rng.seed = seed
		var slot: int = Gen2BattleAI.choose_slot(
			pikachu, geodude, _data, RomLayout.AI_BASIC, _rng
		)
		assert_eq(slot, 1, "singing over a running count is the redundant move")


## `.no`: with nobody left to send in, the song kills the AI too. Five points
## against, and the only branch of the handler that rolls nothing.
func test_smart_discourages_perish_song_with_nobody_on_the_bench() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.PERISH_SONG, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])

	for seed: int in 10:
		_rng.seed = seed
		var slot: int = Gen2BattleAI.choose_slot(
			pikachu, geodude, _data, RomLayout.AI_SMART, _rng
		)
		assert_eq(slot, 1, "a lone Pokémon has no reason to start a clock on itself")


## `.yes`: a player held by Mean Look or Spider Web cannot escape the count, so
## the song is encouraged half the time.
func test_smart_encourages_perish_song_against_a_player_that_cannot_run() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.PERISH_SONG])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	geodude.substatus |= Gen2Substatus.CANT_RUN

	var encouraged: bool = false
	var left_alone: bool = false
	for seed: int in 100:
		_rng.seed = seed
		var scores: Array = [20, 20, 20, 20]
		Gen2BattleAI._apply_smart(
			scores, pikachu, geodude, _data, _rng, 0, 0, Gen2Weather.NONE,
			Gen2Screens.NONE, Gen2Screens.NONE, true, Gen2AISwitch.BASE_SCORE
		)
		if int(scores[0]) < 20:
			encouraged = true
		elif int(scores[0]) == 20:
			left_alone = true
	assert_true(encouraged, "half the time a trapped player is worth singing at")
	assert_true(left_alone, "and half the time the coin says nothing")


## The last branch, and the one that reads backwards: a matchup the AI is losing
## (`CheckPlayerMoveTypeMatchups` under `BASE_AI_SWITCH_SCORE`) leaves the score
## alone, while one it is winning is discouraged half the time.
func test_smart_discourages_perish_song_only_while_the_matchup_holds() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.PERISH_SONG])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])

	for seed: int in 100:
		_rng.seed = seed
		var losing: Array = [20, 20, 20, 20]
		Gen2BattleAI._apply_smart(
			losing, pikachu, geodude, _data, _rng, 0, 0, Gen2Weather.NONE,
			Gen2Screens.NONE, Gen2Screens.NONE, true, Gen2AISwitch.BASE_SCORE - 1
		)
		assert_eq(int(losing[0]), 20, "a losing matchup neither rolls nor nudges")

	var discouraged: bool = false
	var left_alone: bool = false
	for seed: int in 100:
		_rng.seed = seed
		var scores: Array = [20, 20, 20, 20]
		Gen2BattleAI._apply_smart(
			scores, pikachu, geodude, _data, _rng, 0, 0, Gen2Weather.NONE,
			Gen2Screens.NONE, Gen2Screens.NONE, true, Gen2AISwitch.BASE_SCORE
		)
		if int(scores[0]) > 20:
			discouraged = true
		elif int(scores[0]) == 20:
			left_alone = true
	assert_true(discouraged, "a matchup worth keeping is worth not ending")
	assert_true(left_alone)


## `AI_Redundant.Substitute` reads `wEnemySubStatus4`, the AI's own: a second doll
## while the first is standing is the wasted turn.
func test_basic_treats_a_second_substitute_as_redundant() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.SUBSTITUTE, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	pikachu.substatus |= Gen2Substatus.SUBSTITUTE

	for seed: int in 10:
		_rng.seed = seed
		assert_eq(
			Gen2BattleAI.choose_slot(pikachu, geodude, _data, RomLayout.AI_BASIC, _rng), 1
		)


## `.LeechSeed` reads the target's own flag, since that is where the seed sits.
func test_basic_treats_a_second_leech_seed_as_redundant() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.LEECH_SEED, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	geodude.substatus |= Gen2Substatus.LEECH_SEED

	for seed: int in 10:
		_rng.seed = seed
		assert_eq(
			Gen2BattleAI.choose_slot(pikachu, geodude, _data, RomLayout.AI_BASIC, _rng), 1
		)


## `.Spikes` reads `wPlayerScreens`, the side the spikes would land on.
func test_basic_treats_a_second_spikes_as_redundant() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.SPIKES, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])

	for seed: int in 10:
		_rng.seed = seed
		assert_eq(
			Gen2BattleAI.choose_slot(
				pikachu, geodude, _data, RomLayout.AI_BASIC, _rng, 0, 0,
				Gen2Weather.NONE, Gen2Screens.NONE, Gen2Screens.SPIKES
			),
			1
		)


## `.Nightmare` calls a target with *no* status the redundant case and stops
## there, so a target with any status at all is left encouraged even when it is
## awake and cannot have one. The source names that as a bug of its own and this
## reproduces it rather than fixing it.
func test_basic_reproduces_the_nightmare_redundancy_bug() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.NIGHTMARE, Fixture.TACKLE])
	var awake: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])

	for seed: int in 10:
		_rng.seed = seed
		assert_eq(
			Gen2BattleAI.choose_slot(pikachu, awake, _data, RomLayout.AI_BASIC, _rng), 1,
			"an unstatused target really is the redundant case"
		)

	var burned: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	burned.status = Gen2Status.BURN
	var kept: int = 0
	for seed: int in 20:
		_rng.seed = seed
		if Gen2BattleAI.choose_slot(pikachu, burned, _data, RomLayout.AI_BASIC, _rng) == 0:
			kept += 1
	assert_gt(kept, 0, "a burn is not sleep, and the AI is not discouraged anyway")

	var dreaming: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	dreaming.status = Gen2Status.BURN
	dreaming.substatus |= Gen2Substatus.NIGHTMARE
	for seed: int in 10:
		_rng.seed = seed
		assert_eq(
			Gen2BattleAI.choose_slot(pikachu, dreaming, _data, RomLayout.AI_BASIC, _rng), 1,
			"a target already dreaming is redundant on the second clause"
		)


## `AI_Smart_Protect` and `AI_Smart_Endure`, both of which open on
## `wEnemyProtectCount` and both of which are called directly, since every branch
## of either is behind a roll.
func _smart_scores(
	attacker: Gen2BattleMon, defender: Gen2BattleMon, seed_value: int
) -> Array:
	_rng.seed = seed_value
	var scores: Array = [20, 20, 20, 20]
	Gen2BattleAI._apply_smart(
		scores, attacker, defender, _data, _rng, 0, 0, Gen2Weather.NONE,
		Gen2Screens.NONE, Gen2Screens.NONE, false, Gen2AISwitch.BASE_SCORE
	)
	return scores


## How often the first slot was nudged each way over a hundred seeds, as
## [encouraged, discouraged, untouched].
func _smart_spread(attacker: Gen2BattleMon, defender: Gen2BattleMon) -> Array:
	var out: Array = [0, 0, 0]
	for seed_value: int in 100:
		var score: int = int(_smart_scores(attacker, defender, seed_value)[0])
		if score < 20:
			out[0] += 1
		elif score > 20:
			out[1] += 1
		else:
			out[2] += 1
	return out


## `.greatly_discourage`: a Protect already used is worth three points against,
## which only the 8% skip inside `.discourage` can soften to one.
func test_smart_greatly_discourages_a_second_protect() -> void:
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.PROTECT, Fixture.TACKLE])
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])
	geodude.protect_count = 1

	var spread: Array = _smart_spread(geodude, pikachu)
	assert_eq(int(spread[0]), 0, "nothing here can encourage it")
	assert_gt(int(spread[1]), 80, "and it is nearly always penalised")
	assert_eq(
		int(_smart_scores(geodude, pikachu, 0)[1]), 20,
		"the Tackle beside it is untouched"
	)


## The four states that reach `.encourage`, each on its own: a boosted Fury
## Cutter, a charged two-turn move, and a player already losing health to Toxic,
## Leech Seed or a Curse.
func test_smart_encourages_protect_against_something_worth_sitting_out() -> void:
	var states: Array[Callable] = [
		func(mon: Gen2BattleMon) -> void: mon.fury_cutter_count = 3,
		func(mon: Gen2BattleMon) -> void: mon.substatus |= Gen2Substatus.CHARGING,
		func(mon: Gen2BattleMon) -> void: mon.toxic_counter = 1,
		func(mon: Gen2BattleMon) -> void: mon.substatus |= Gen2Substatus.LEECH_SEED,
		func(mon: Gen2BattleMon) -> void: mon.substatus |= Gen2Substatus.CURSE,
	]

	for index: int in states.size():
		var geodude: Gen2BattleMon = _mon(
			Fixture.GEODUDE, 50, [Fixture.PROTECT, Fixture.TACKLE]
		)
		var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])
		states[index].call(pikachu)

		var spread: Array = _smart_spread(geodude, pikachu)
		assert_gt(int(spread[0]), 60, "state %d encourages roughly four times in five" % index)
		assert_eq(int(spread[1]), 0, "and never penalises")


## The fall-through is two refusals in one: a player not rolling at all is
## discouraged, and so is one whose Rollout has not built up yet.
func test_smart_discourages_protect_against_an_unboosted_rollout() -> void:
	for count: int in [0, 2]:
		var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.PROTECT, Fixture.TACKLE])
		var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])
		if count > 0:
			pikachu.substatus |= Gen2Substatus.ROLLOUT
			pikachu.rollout_count = count

		var spread: Array = _smart_spread(geodude, pikachu)
		assert_eq(int(spread[0]), 0, "rollout count %d is not worth sitting out" % count)
		assert_gt(int(spread[1]), 80)


func test_smart_encourages_protect_against_a_boosted_rollout() -> void:
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.PROTECT, Fixture.TACKLE])
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])
	pikachu.substatus |= Gen2Substatus.ROLLOUT
	pikachu.rollout_count = 3

	var spread: Array = _smart_spread(geodude, pikachu)
	assert_gt(int(spread[0]), 60, "three hits in is worth one turn of Protect")
	assert_eq(int(spread[1]), 0)


## `AI_Smart_Endure`: full health and a spent Protect chain are both two points
## against, and anything above a quarter is one.
func test_smart_discourages_endure_at_health_it_does_not_need_it() -> void:
	var full: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.ENDURE, Fixture.TACKLE])
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])
	assert_eq(int(_smart_scores(full, pikachu, 0)[0]), 22, "full health is greatly discouraged")

	var spent: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.ENDURE, Fixture.TACKLE])
	spent.hp = spent.max_hp() / 8
	spent.protect_count = 1
	assert_eq(int(_smart_scores(spent, pikachu, 0)[0]), 22, "so is a spent chain")

	var half: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.ENDURE, Fixture.TACKLE])
	half.hp = half.max_hp() / 2
	assert_eq(int(_smart_scores(half, pikachu, 0)[0]), 21, "above a quarter is one point")


## Under a quarter with nothing to spend the survival on, the handler does
## nothing at all: its last branch reads a lock-on this engine has no flag for.
func test_smart_leaves_endure_alone_under_a_quarter_with_no_reversal() -> void:
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.ENDURE, Fixture.TACKLE])
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])
	geodude.hp = geodude.max_hp() / 8

	var spread: Array = _smart_spread(geodude, pikachu)
	assert_eq(int(spread[2]), 100, "untouched on every seed")


## `AIHasMoveEffect` for `EFFECT_REVERSAL`: three points on, which is the
## strongest single nudge either handler makes.
func test_smart_greatly_encourages_endure_with_reversal_in_the_set() -> void:
	var geodude: Gen2BattleMon = _mon(
		Fixture.GEODUDE, 50, [Fixture.ENDURE, Fixture.REVERSAL]
	)
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])
	geodude.hp = geodude.max_hp() / 8

	var encouraged: int = 0
	for seed_value: int in 100:
		if int(_smart_scores(geodude, pikachu, seed_value)[0]) == 17:
			encouraged += 1
	assert_gt(encouraged, 60, "three points off, roughly four times in five")


## `AI_Smart_DestinyBond` shares `AI_Smart_SkullBash`'s body, and so does
## `AI_Smart_Reversal`: one point against while there is health to spare.
func test_smart_discourages_destiny_bond_and_reversal_above_a_quarter() -> void:
	for move_number: int in [Fixture.DESTINY_BOND, Fixture.REVERSAL]:
		var healthy: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [move_number, Fixture.TACKLE])
		var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])
		assert_eq(
			int(_smart_scores(healthy, pikachu, 0)[0]), 21,
			"move %d is discouraged with health to spare" % move_number
		)

		var hurt: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [move_number, Fixture.TACKLE])
		hurt.hp = hurt.max_hp() / 8
		assert_eq(
			int(_smart_scores(hurt, pikachu, 0)[0]), 20,
			"and left alone under a quarter"
		)


## `AI_Smart_ForceSwitch`: blowing the player away is worth a point against while
## the pairing is going well, and left alone once `CheckPlayerMoveTypeMatchups`
## says it is not.
func test_smart_discourages_a_force_switch_while_the_matchup_is_holding() -> void:
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.WHIRLWIND, Fixture.TACKLE])
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])

	var scores: Array = [20, 20, 20, 20]
	Gen2BattleAI._apply_smart(
		scores, geodude, pikachu, _data, _rng, 0, 0, Gen2Weather.NONE,
		Gen2Screens.NONE, Gen2Screens.NONE, true, Gen2AISwitch.BASE_SCORE
	)
	assert_eq(int(scores[0]), 21, "a neutral pairing is no reason to blow it away")

	var losing: Array = [20, 20, 20, 20]
	Gen2BattleAI._apply_smart(
		losing, geodude, pikachu, _data, _rng, 0, 0, Gen2Weather.NONE,
		Gen2Screens.NONE, Gen2Screens.NONE, true, Gen2AISwitch.BASE_SCORE - 1
	)
	assert_eq(int(losing[0]), 20, "a pairing going badly is left alone")


## `AI_Redundant`'s `.Foresight`: identifying an already-identified target is a
## wasted turn.
func test_basic_discourages_foresight_against_an_identified_target() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.FORESIGHT, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	geodude.substatus = Gen2Substatus.IDENTIFIED
	for seed_value: int in 10:
		_rng.seed = seed_value
		assert_eq(
			Gen2BattleAI.choose_slot(pikachu, geodude, _data, RomLayout.AI_BASIC, _rng),
			1, "a second Foresight identifies nothing"
		)


## `.Teleport` is a label on `.Redundant` itself, so a trainer never throws it.
func test_basic_always_discourages_teleport() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.TELEPORT, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	for seed_value: int in 10:
		_rng.seed = seed_value
		assert_eq(
			Gen2BattleAI.choose_slot(pikachu, geodude, _data, RomLayout.AI_BASIC, _rng),
			1, "there is nowhere to teleport away from a trainer"
		)


## `AI_Types` sets `hBattleTurn` to the enemy before `BattleCheckTypeMatchup`, so
## the flag it reads is the target's: an identified Ghost stops being immune and
## the Normal move stops being dismissed.
func test_types_reads_the_targets_foresight_flag() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.TACKLE, Fixture.THUNDERBOLT])
	var gastly: Gen2BattleMon = _mon(Fixture.GASTLY, 50, [Fixture.TACKLE])
	for seed_value: int in 10:
		_rng.seed = seed_value
		assert_eq(
			Gen2BattleAI.choose_slot(pikachu, gastly, _data, RomLayout.AI_TYPES, _rng),
			1, "Normal cannot touch a Ghost, so the Electric move wins"
		)

	gastly.substatus = Gen2Substatus.IDENTIFIED
	var identified: Array = _scores(pikachu, gastly, RomLayout.AI_TYPES)
	assert_eq(int(identified[0]), Gen2BattleAI.DEFAULT_SCORE,
		"identified, the Normal move is not dismissed any more"
	)


## `AI_Smart_Thief`: `add $1e` and nothing else, which puts it past every other
## move on the list.
func test_smart_puts_thief_thirty_points_behind() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.THIEF, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	var scores: Array = _scores(pikachu, geodude, RomLayout.AI_SMART)
	assert_eq(int(scores[0]), Gen2BattleAI.DEFAULT_SCORE + Gen2BattleAI.THIEF_PENALTY)
	assert_eq(int(scores[1]), Gen2BattleAI.DEFAULT_SCORE)


## `AI_Smart_PainSplit`: pointless while the user is the healthier of the two,
## which is `enemy hp * 2 > player hp` rather than a comparison of fractions.
func test_smart_discourages_pain_split_while_the_user_is_healthier() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.PAIN_SPLIT, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])

	var healthier: Array = _scores(pikachu, geodude, RomLayout.AI_SMART)
	assert_eq(int(healthier[0]), Gen2BattleAI.DEFAULT_SCORE + 1)

	pikachu.hp = 1
	var hurt: Array = _scores(pikachu, geodude, RomLayout.AI_SMART)
	assert_eq(int(hurt[0]), Gen2BattleAI.DEFAULT_SCORE, "worth it once the user is behind")


## `AI_Smart_Pursuit`: two points off against a target nearly down, and discouraged
## against one with health left. Both branches roll, so both are sampled.
func test_smart_pursuit_prefers_a_target_that_is_nearly_down() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.PURSUIT, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	geodude.hp = 1

	var encouraged: Dictionary = _score_spread(pikachu, geodude, RomLayout.AI_SMART, 0)
	assert_true(encouraged.has(Gen2BattleAI.DEFAULT_SCORE - 2), "the 50% that encourages")
	assert_true(encouraged.has(Gen2BattleAI.DEFAULT_SCORE), "and the half that does not")

	geodude.hp = geodude.max_hp()
	var discouraged: Dictionary = _score_spread(pikachu, geodude, RomLayout.AI_SMART, 0)
	assert_true(discouraged.has(Gen2BattleAI.DEFAULT_SCORE + 1), "the 20% that discourages")
	assert_true(discouraged.has(Gen2BattleAI.DEFAULT_SCORE))


## `AI_Smart_Foresight`: worth it against a Ghost, which is the only target the
## flag opens a matchup against, and almost always discouraged otherwise.
func test_smart_foresight_wants_a_ghost() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.FORESIGHT, Fixture.TACKLE])
	var gastly: Gen2BattleMon = _mon(Fixture.GASTLY, 50, [Fixture.TACKLE])
	var against_ghost: Dictionary = _score_spread(pikachu, gastly, RomLayout.AI_SMART, 0)
	assert_true(against_ghost.has(Gen2BattleAI.DEFAULT_SCORE - 2))

	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	var against_rock: Dictionary = _score_spread(pikachu, geodude, RomLayout.AI_SMART, 0)
	assert_false(against_rock.has(Gen2BattleAI.DEFAULT_SCORE - 2),
		"nothing to open, so it is never encouraged"
	)
	assert_true(against_rock.has(Gen2BattleAI.DEFAULT_SCORE + 1), "the 92% that discourages")

	# A sharply raised evasion is the other way in.
	geodude.stages["evasion"] = 3
	var against_evasion: Dictionary = _score_spread(pikachu, geodude, RomLayout.AI_SMART, 0)
	assert_true(against_evasion.has(Gen2BattleAI.DEFAULT_SCORE - 2))


## `AI_Smart_Spite`: below six PP is worth draining, fifteen or more is not, and a
## target that has not moved yet is judged on speed instead.
func test_smart_spite_reads_the_pp_of_the_move_it_would_drain() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.SPITE, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	geodude.last_counter_move = Fixture.TACKLE

	geodude.pp[0] = 5
	var nearly_out: Dictionary = _score_spread(pikachu, geodude, RomLayout.AI_SMART, 0)
	assert_true(nearly_out.has(Gen2BattleAI.DEFAULT_SCORE - 2))

	geodude.pp[0] = 20
	var plenty: Dictionary = _score_spread(pikachu, geodude, RomLayout.AI_SMART, 0)
	assert_eq(plenty.keys(), [Gen2BattleAI.DEFAULT_SCORE + 1],
		"fifteen or more discourages without a roll"
	)


## A target that has not moved is judged on speed: the faster user dismisses it
## outright, since it would never see a move to drain.
func test_smart_spite_dismisses_itself_when_the_user_is_faster() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.SPITE, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	var scores: Array = _scores(pikachu, geodude, RomLayout.AI_SMART)
	assert_eq(
		int(scores[0]),
		Gen2BattleAI.DEFAULT_SCORE + Gen2BattleAI.DISCOURAGE_MOVE
	)


## `AI_Smart_LockOn`'s `.player_locked_on`: with the target already aimed at,
## every inaccurate move is encouraged and Lock On itself is dismissed.
func test_smart_lock_on_dismisses_itself_once_the_target_is_aimed_at() -> void:
	var pikachu: Gen2BattleMon = _mon(
		Fixture.PIKACHU, 50, [Fixture.LOCK_ON, Fixture.DISABLE_MOVE, Fixture.SCREECH]
	)
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	geodude.substatus = Gen2Substatus.LOCK_ON
	var scores: Array = _scores(pikachu, geodude, RomLayout.AI_SMART)

	assert_eq(
		int(scores[0]),
		Gen2BattleAI.DEFAULT_SCORE + Gen2BattleAI.DISCOURAGE_MOVE,
		"aiming again is wasted"
	)
	assert_eq(int(scores[1]), Gen2BattleAI.DEFAULT_SCORE - 2,
		"Disable stores 140, under the 180 the threshold compares against"
	)
	assert_eq(int(scores[2]), Gen2BattleAI.DEFAULT_SCORE,
		"Screech stores 216 and never needed the help"
	)


## The other half: aiming is worth it against a sharply raised evasion and not
## worth a turn while the user is nearly down.
func test_smart_lock_on_reads_health_then_evasion() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.LOCK_ON, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	geodude.stages["evasion"] = 3
	var wanted: Dictionary = _score_spread(pikachu, geodude, RomLayout.AI_SMART, 0)
	assert_true(wanted.has(Gen2BattleAI.DEFAULT_SCORE - 2))

	pikachu.hp = 1
	var nearly_down: Array = _scores(pikachu, geodude, RomLayout.AI_SMART)
	assert_eq(int(nearly_down[0]), Gen2BattleAI.DEFAULT_SCORE + 1,
		"below a quarter it is not worth the turn"
	)


## `AI_Smart_Protect`'s second test: with a guaranteed hit already lined up,
## sitting the turn out wastes it.
func test_smart_protect_is_discouraged_while_the_player_is_locked_on() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.PROTECT, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	geodude.substatus = Gen2Substatus.LOCK_ON
	var spread: Dictionary = _score_spread(pikachu, geodude, RomLayout.AI_SMART, 0)

	assert_true(spread.has(Gen2BattleAI.DEFAULT_SCORE + 2), "the two-point penalty")
	assert_true(spread.has(Gen2BattleAI.DEFAULT_SCORE), "and the 8% that skips it")
	assert_false(spread.has(Gen2BattleAI.DEFAULT_SCORE - 1), "never encouraged")


## `AI_Smart_Endure`'s `.no_reversal`: a guaranteed incoming hit is exactly what
## surviving on one point is for, even with no Reversal to answer with.
func test_smart_endure_wants_to_survive_a_locked_on_hit() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.ENDURE, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	pikachu.hp = 1

	var unaimed: Array = _scores(pikachu, geodude, RomLayout.AI_SMART)
	assert_eq(int(unaimed[0]), Gen2BattleAI.DEFAULT_SCORE, "nothing to survive")

	pikachu.substatus |= Gen2Substatus.LOCK_ON
	var aimed: Dictionary = _score_spread(pikachu, geodude, RomLayout.AI_SMART, 0)
	assert_true(aimed.has(Gen2BattleAI.DEFAULT_SCORE - 2))
	assert_true(aimed.has(Gen2BattleAI.DEFAULT_SCORE), "the half that does nothing")


## `AI_Smart_TrapTarget` encourages on five states, and two of them are the flags
## Foresight and Nightmare leave behind.
func test_smart_trap_target_encourages_on_a_foresight_or_a_nightmare() -> void:
	for flag: int in [Gen2Substatus.IDENTIFIED, Gen2Substatus.NIGHTMARE]:
		var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.WRAP, Fixture.TACKLE])
		var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
		geodude.substatus = flag
		var spread: Dictionary = _score_spread(
			pikachu, geodude, RomLayout.AI_SMART, 0, 1, 1
		)
		assert_true(spread.has(Gen2BattleAI.DEFAULT_SCORE - 2), "flag %d" % flag)


func test_basic_sleep_talk_is_redundant_only_while_awake() -> void:
	var pikachu: Gen2BattleMon = _mon(
		Fixture.PIKACHU, 50, [Fixture.SLEEP_TALK, Fixture.TACKLE]
	)
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	assert_eq(
		int(_scores(pikachu, geodude, RomLayout.AI_BASIC)[0]),
		Gen2BattleAI.DEFAULT_SCORE + Gen2BattleAI.DISCOURAGE_MOVE
	)
	pikachu.status = 3
	assert_eq(
		int(_scores(pikachu, geodude, RomLayout.AI_BASIC)[0]),
		Gen2BattleAI.DEFAULT_SCORE
	)


func test_smart_sleep_talk_reads_the_turn_before_waking() -> void:
	var pikachu: Gen2BattleMon = _mon(
		Fixture.PIKACHU, 50, [Fixture.SLEEP_TALK, Fixture.TACKLE]
	)
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	pikachu.status = 3
	assert_eq(
		int(_scores(pikachu, geodude, RomLayout.AI_SMART)[0]),
		Gen2BattleAI.DEFAULT_SCORE - 3
	)
	pikachu.status = 1
	assert_eq(
		int(_scores(pikachu, geodude, RomLayout.AI_SMART)[0]),
		Gen2BattleAI.DEFAULT_SCORE + 3
	)


func test_smart_mirror_move_uses_speed_and_the_useful_move_table() -> void:
	var fast: Gen2BattleMon = _mon(
		Fixture.PIKACHU, 50, [Fixture.MIRROR_MOVE, Fixture.TACKLE]
	)
	var slow: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	assert_eq(
		int(_scores(fast, slow, RomLayout.AI_SMART)[0]),
		Gen2BattleAI.DEFAULT_SCORE + Gen2BattleAI.DISCOURAGE_MOVE,
		"a faster user cannot mirror a move it has not seen"
	)
	slow.last_counter_move = Fixture.THUNDERBOLT
	var useful: Dictionary = _score_spread(fast, slow, RomLayout.AI_SMART, 0)
	assert_true(useful.has(Gen2BattleAI.DEFAULT_SCORE - 1))
	assert_true(useful.has(Gen2BattleAI.DEFAULT_SCORE - 2))
	slow.last_counter_move = Fixture.TACKLE
	assert_eq(
		int(_scores(fast, slow, RomLayout.AI_SMART)[0]),
		Gen2BattleAI.DEFAULT_SCORE,
		"Tackle is not in UsefulMoves"
	)


func test_smart_mimic_waits_for_a_move_then_values_a_useful_one() -> void:
	var fast: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.MIMIC, Fixture.TACKLE])
	var slow: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	assert_eq(
		int(_scores(fast, slow, RomLayout.AI_SMART)[0]),
		Gen2BattleAI.DEFAULT_SCORE + Gen2BattleAI.DISCOURAGE_MOVE
	)
	# Sleep Powder is in UsefulMoves and is super-effective against both of
	# Geodude's types in the fixture, so both source 50% rolls are reachable.
	slow.last_counter_move = Fixture.SLEEP_POWDER
	var useful: Dictionary = _score_spread(fast, slow, RomLayout.AI_SMART, 0)
	assert_true(useful.has(Gen2BattleAI.DEFAULT_SCORE))
	assert_true(useful.has(Gen2BattleAI.DEFAULT_SCORE - 1))
	assert_true(useful.has(Gen2BattleAI.DEFAULT_SCORE - 2))
	fast.hp = 1
	assert_eq(
		int(_scores(fast, slow, RomLayout.AI_SMART)[0]),
		Gen2BattleAI.DEFAULT_SCORE + 1,
		"under half health is discouraged before the copied move is scored"
	)


func test_smart_conversion2_reproduces_the_source_last_move_bug() -> void:
	var pikachu: Gen2BattleMon = _mon(
		Fixture.PIKACHU, 50, [Fixture.CONVERSION_2, Fixture.TACKLE]
	)
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	assert_eq(
		int(_scores(pikachu, geodude, RomLayout.AI_SMART)[0]),
		Gen2BattleAI.DEFAULT_SCORE,
		"with no remembered move the fixture's undefined lookup leaves it alone"
	)
	geodude.last_counter_move = Fixture.TACKLE
	var spread: Dictionary = _score_spread(pikachu, geodude, RomLayout.AI_SMART, 0)
	assert_true(spread.has(Gen2BattleAI.DEFAULT_SCORE + 1), "the 90% discouragement")
	assert_true(spread.has(Gen2BattleAI.DEFAULT_SCORE), "and the 10% that skips it")


## One scoring pass, with the seed left where the test set it.
func _scores(
	attacker: Gen2BattleMon, defender: Gen2BattleMon, flags: int,
	attacker_turns: int = 1, defender_turns: int = 1
) -> Array:
	return Gen2BattleAI.score_slots(
		attacker, defender, _data, flags, _rng, attacker_turns, defender_turns
	)


## The set of scores one slot takes across enough seeds to see both sides of a
## roll, for the handlers whose branches are probabilistic.
func _score_spread(
	attacker: Gen2BattleMon, defender: Gen2BattleMon, flags: int, slot: int,
	attacker_turns: int = 1, defender_turns: int = 1
) -> Dictionary:
	var seen: Dictionary = {}
	for seed_value: int in 60:
		_rng.seed = seed_value
		seen[int(_scores(attacker, defender, flags, attacker_turns, defender_turns)[slot])] = true
	return seen
