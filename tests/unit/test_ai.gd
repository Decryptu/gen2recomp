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
		Gen2BattleAI._apply_setup(scores, pikachu, geodude, _data, _rng, 0, 5)
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
		Gen2BattleAI._apply_setup(scores, pikachu, geodude, _data, _rng, 3, 5)
		assert_true(scores[0] >= 20, "a stat-up move past turn one is never encouraged")
		if scores[0] > 20:
			discouraged_late = true
	assert_true(discouraged_late, "and it is discouraged most of the time")


func test_opportunist_only_discourages_stall_moves_once_hp_is_low() -> void:
	var pikachu: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.SWORDS_DANCE, Fixture.TACKLE])
	var geodude: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])

	# Full HP: Opportunist has nothing to say.
	var scores: Array = [20, 20, 20, 20]
	Gen2BattleAI._apply_opportunist(scores, pikachu, geodude, _data, _rng, 0, 0)
	assert_eq(scores, [20, 20, 20, 20], "a healthy mon has no reason to stop stalling")

	# Well below a quarter: Swords Dance (a stall move by number) is
	# discouraged without a roll involved.
	pikachu.hp = 1
	scores = [20, 20, 20, 20]
	Gen2BattleAI._apply_opportunist(scores, pikachu, geodude, _data, _rng, 0, 0)
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
