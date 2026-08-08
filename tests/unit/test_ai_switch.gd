extends GutTest

## Whether a trainer pulls its Pokémon out, and who it reaches for.
##
## The fixture's type chart is what makes these readable: Electric does nothing
## to Geodude's Ground half, Fire is doubled against Bulbasaur's Grass half, and
## Normal is neutral against nearly everything, so a party of three can be
## arranged into any of the branches.

const Fixture := preload("res://tests/unit/battle_fixture.gd")

const OFTEN: int = RomLayout.SWITCH_OFTEN
const RARELY: int = RomLayout.SWITCH_RARELY
const SOMETIMES: int = RomLayout.SWITCH_SOMETIMES

var _directory: String = ""
var _data: GameData = null
var _rng: RandomNumberGenerator = null


func before_each() -> void:
	_directory = RomCache.directory_for(&"aiswitchtest", "0123456789abcdef")
	_data = Fixture.build(_directory)
	_rng = RandomNumberGenerator.new()
	_rng.seed = 3


func after_each() -> void:
	RomCache.clear(_directory)


func _mon(species: int, moves: Array, level: int = 50) -> Gen2BattleMon:
	return Gen2BattleMon.create(_data, species, level, moves)


func _battle(player: Gen2BattleMon, enemy_party: Array) -> Gen2Battle:
	return Gen2Battle.create_parties(
		_data, Gen2Party.of(player), Gen2Party.create(enemy_party), _rng, true
	)


## The enemy is a Geodude the player's Electric cannot touch, and its own Tackle
## lands: it has no reason to go anywhere.
func _comfortable() -> Gen2Battle:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, [Fixture.THUNDERBOLT]),
		[_mon(Fixture.GEODUDE, [Fixture.TACKLE]), _mon(Fixture.CHARMANDER, [Fixture.TACKLE])]
	)
	battle.player_used_moves = [Fixture.THUNDERBOLT] as Array[int]
	battle.player.last_move_used = Fixture.THUNDERBOLT
	return battle


## The enemy is a Charmander with nothing that hurts a Pikachu. Of the two behind
## it only the Geodude is outright immune to the Thunderbolt that has been
## landing: the Bulbasaur merely resists it, so the two bench slots tell the
## immunity branch apart from the one below it.
func _wants_out() -> Gen2Battle:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, [Fixture.THUNDERBOLT]),
		[
			_mon(Fixture.CHARMANDER, [Fixture.GROWL]),
			_mon(Fixture.BULBASAUR, [Fixture.TACKLE]),
			_mon(Fixture.GEODUDE, [Fixture.TACKLE]),
		]
	)
	battle.player_used_moves = [Fixture.THUNDERBOLT] as Array[int]
	battle.player.last_move_used = Fixture.THUNDERBOLT
	return battle


func test_a_pokemon_that_is_winning_stays_in() -> void:
	var battle: Gen2Battle = _comfortable()

	assert_gt(Gen2AISwitch.matchup_score(battle), Gen2AISwitch.BASE_SCORE)
	assert_eq(int(Gen2AISwitch.evaluate(battle)["tier"]), 0)


## `.CheckEnemyMoveMatchups` takes two off for a Pokémon whose own moves do
## nothing at all, which is what makes a Growl-only Charmander want out.
func test_a_pokemon_with_nothing_to_hit_back_with_scores_low() -> void:
	var battle: Gen2Battle = _wants_out()

	assert_lt(Gen2AISwitch.matchup_score(battle), Gen2AISwitch.BASE_SCORE)


## A move that has already landed super effectively is worth a point off; one
## the enemy is immune to leaves the walk with nothing found, worth two on.
func test_the_score_reads_what_the_player_has_actually_thrown() -> void:
	var burning: Gen2Battle = _battle(
		_mon(Fixture.CHARMANDER, [Fixture.EMBER]),
		[_mon(Fixture.BULBASAUR, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, [Fixture.TACKLE])]
	)
	burning.player_used_moves = [Fixture.EMBER] as Array[int]

	var immune: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, [Fixture.THUNDERBOLT]),
		[_mon(Fixture.GEODUDE, [Fixture.TACKLE]), _mon(Fixture.CHARMANDER, [Fixture.TACKLE])]
	)
	immune.player_used_moves = [Fixture.THUNDERBOLT] as Array[int]

	# Both enemies answer with a neutral Tackle, so the two scores differ only in
	# what the player has shown: Ember doubled is one off, Thunderbolt into a
	# Ground type is two on.
	assert_eq(Gen2AISwitch.matchup_score(burning), Gen2AISwitch.BASE_SCORE - 1)
	assert_eq(Gen2AISwitch.matchup_score(immune), Gen2AISwitch.BASE_SCORE + 2)


## With nothing thrown yet, `.unknown_moves` assumes the player will attack with
## its own types and takes one off per type that is super effective.
func test_an_unused_moveset_falls_back_to_the_players_own_types() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.CHARMANDER, [Fixture.EMBER]),
		[_mon(Fixture.BULBASAUR, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, [Fixture.TACKLE])]
	)
	assert_true(battle.player_used_moves.is_empty())

	# Charmander is Fire/Fire, counted once, and Fire is doubled against
	# Bulbasaur's Grass half.
	assert_eq(Gen2AISwitch.matchup_score(battle), Gen2AISwitch.BASE_SCORE - 1)


## `FindEnemyMonsImmuneToLastCounterMove`: the Pokémon that takes nothing at all
## from what has been landing is the one reached for.
func test_the_bench_pokemon_immune_to_the_last_move_is_the_one_chosen() -> void:
	var battle: Gen2Battle = _wants_out()

	var choice: Dictionary = Gen2AISwitch.evaluate(battle)

	assert_eq(int(choice["index"]), 2, "the Geodude, not the Bulbasaur that merely resists")
	assert_eq(int(choice["tier"]), Gen2AISwitch.TIER_LOW)


## A class carrying none of the three switch bits is the `DontSwitch`
## fallthrough: it never leaves, however badly the matchup is going.
func test_a_class_with_no_switch_bit_never_leaves() -> void:
	var battle: Gen2Battle = _wants_out()

	for seed: int in 32:
		_rng.seed = seed
		assert_false(bool(Gen2AISwitch.decide(battle, 0, _rng)["switch"]))


## The three frequencies act on the same decision at their own rates, which is
## the whole of what separates them.
func test_the_three_frequencies_act_at_their_own_rates() -> void:
	var battle: Gen2Battle = _wants_out()
	var rates: Dictionary = {}
	for frequency: int in [OFTEN, SOMETIMES, RARELY]:
		var switched: int = 0
		for seed: int in 128:
			_rng.seed = seed
			if bool(Gen2AISwitch.decide(battle, frequency, _rng)["switch"]):
				switched += 1
		rates[frequency] = switched

	# The decision is TIER_LOW, whose chances are 128, 50 and 20 out of 256.
	assert_gt(int(rates[OFTEN]), int(rates[SOMETIMES]))
	assert_gt(int(rates[SOMETIMES]), int(rates[RARELY]))
	assert_between(int(rates[OFTEN]), 44, 84)
	assert_between(int(rates[RARELY]), 2, 24)


## `AI_TrySwitch` needs two of the party standing, so the last Pokémon never
## leaves however much it would like to.
func test_the_last_pokemon_standing_cannot_leave() -> void:
	var battle: Gen2Battle = _wants_out()
	battle.party(Gen2Battle.ENEMY).at(1).hp = 0
	battle.party(Gen2Battle.ENEMY).at(2).hp = 0

	assert_eq(int(Gen2AISwitch.evaluate(battle)["tier"]), 0, "nobody to switch to")
	for seed: int in 32:
		_rng.seed = seed
		assert_false(bool(Gen2AISwitch.decide(battle, OFTEN, _rng)["switch"]))


## `AI_SwitchOrTryItem`'s own gates, which stop the switch without stopping the
## bag: a Mean Look on the player, and a wrap on the enemy.
func test_a_trapped_or_mean_looked_enemy_does_not_switch() -> void:
	for setup: StringName in [&"wrapped", &"mean_looked"]:
		var battle: Gen2Battle = _wants_out()
		if setup == &"wrapped":
			battle.enemy.trapped_turns = 3
		else:
			battle.player.substatus |= Gen2Substatus.CANT_RUN

		for seed: int in 16:
			_rng.seed = seed
			var action: Dictionary = Gen2BattleAI.choose_action(battle, OFTEN, 0, _rng)
			assert_ne(
				StringName(action["type"]), Gen2Battle.ACTION_SWITCH, String(setup)
			)


## `CheckEnemyLockedIn` returns out of the whole routine, so a charging Pokémon
## neither switches nor is handed an item.
func test_a_locked_in_enemy_neither_switches_nor_uses_an_item() -> void:
	var battle: Gen2Battle = _wants_out()
	battle.enemy_items = [Gen2AIItems.X_ATTACK]
	battle.enemy.substatus |= Gen2Substatus.CHARGING

	for seed: int in 16:
		_rng.seed = seed
		var action: Dictionary = Gen2BattleAI.choose_action(battle, OFTEN, 0, _rng)
		assert_eq(StringName(action["type"]), Gen2Battle.ACTION_MOVE)


## A wild battle has no trainer behind it, so neither half of the routine runs.
func test_a_wild_battle_never_switches_or_uses_an_item() -> void:
	var battle: Gen2Battle = Gen2Battle.create(
		_data, _mon(Fixture.PIKACHU, [Fixture.THUNDERBOLT]),
		_mon(Fixture.GEODUDE, [Fixture.TACKLE]), _rng
	)
	battle.enemy_items = [Gen2AIItems.FULL_RESTORE]
	battle.enemy.hp = 1

	var action: Dictionary = Gen2BattleAI.choose_action(battle, OFTEN, 0, _rng)

	assert_eq(StringName(action["type"]), Gen2Battle.ACTION_MOVE)
