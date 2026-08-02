extends GutTest

## The turn loop: who goes first, what connects, and when it is over.
##
## The rolls are made by a seeded [RandomNumberGenerator], so a test that has to
## be sure of an outcome arranges one that cannot go the other way (a move that
## always hits, a Pokémon that cannot survive) rather than leaning on a seed.

const Fixture := preload("res://tests/unit/battle_fixture.gd")

var _directory: String = ""
var _data: GameData = null
var _rng: RandomNumberGenerator = null


func before_each() -> void:
	_directory = RomCache.directory_for(&"battletest", "0123456789abcdef")
	_data = Fixture.build(_directory)
	_rng = RandomNumberGenerator.new()
	_rng.seed = 12345


func after_each() -> void:
	RomCache.clear(_directory)


func _mon(species: int, level: int, moves: Array) -> Gen2BattleMon:
	return Gen2BattleMon.create(_data, species, level, moves)


func _battle(player: Gen2BattleMon, enemy: Gen2BattleMon) -> Gen2Battle:
	return Gen2Battle.create(_data, player, enemy, _rng)


func _of_type(events: Array, type: StringName) -> Array:
	return events.filter(func(event: Dictionary) -> bool: return event["type"] == type)


func _first(events: Array, type: StringName) -> Dictionary:
	var found: Array = _of_type(events, type)
	return found[0] if not found.is_empty() else {}


func test_the_faster_pokemon_moves_first() -> void:
	# Pikachu at 50 has 110 Speed and Geodude has 30, so nothing about the roll
	# can change this.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_first(events, Gen2Battle.USED_MOVE)["side"], Gen2Battle.PLAYER)


func test_the_slower_pokemon_moves_first_when_it_is_the_other_way_round() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE]),
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])
	)
	assert_eq(
		_first(battle.take_turn(0, 0), Gen2Battle.USED_MOVE)["side"], Gen2Battle.ENEMY
	)


func test_speed_is_read_with_its_stage_applied() -> void:
	# Geodude is far slower until it is not. A stage is a lens on a stat, and
	# turn order is the first thing that has to look through it.
	var slow: Gen2BattleMon = _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	slow.change_stage("speed", 6)
	var battle: Gen2Battle = _battle(slow, _mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]))
	assert_eq(
		_first(battle.take_turn(0, 0), Gen2Battle.USED_MOVE)["side"], Gen2Battle.PLAYER
	)


func test_priority_beats_speed() -> void:
	# The effect byte carries it, and the cache already has the effect byte.
	assert_eq(Gen2Battle.priority_of({"number": 1, "effect": 0}), Gen2Battle.BASE_PRIORITY)
	assert_eq(Gen2Battle.priority_of({"number": 1, "effect": 0x67}), 2, "Quick Attack")
	assert_eq(Gen2Battle.priority_of({"number": 1, "effect": 0x6F}), 3, "Protect")
	assert_eq(Gen2Battle.priority_of({"number": 1, "effect": 0x59}), 0, "Counter")


func test_vital_throw_says_it_is_last_in_the_move_and_not_in_the_effect() -> void:
	# The one move the effect table cannot answer for.
	assert_eq(Gen2Battle.priority_of({"number": Gen2Battle.VITAL_THROW, "effect": 17}), 0)


func test_a_move_costs_a_pp() -> void:
	var attacker: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.THUNDERBOLT])
	var battle: Gen2Battle = _battle(attacker, _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE]))
	battle.take_turn(0, 0)
	assert_eq(attacker.pp_left(0), 14)


func test_a_pokemon_with_nothing_left_struggles_and_it_costs_nothing() -> void:
	var attacker: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.THUNDERBOLT])
	for _spend: int in 15:
		attacker.spend_pp(0)

	var battle: Gen2Battle = _battle(attacker, _mon(Fixture.BULBASAUR, 50, [Fixture.TACKLE]))
	var used: Array = _of_type(battle.take_turn(0, 0), Gen2Battle.USED_MOVE)
	assert_eq(int(used[0]["move"]), Gen2Damage.STRUGGLE)
	assert_eq(attacker.pp_left(0), 0, "there was nothing to spend")


func test_struggle_costs_the_attacker_a_quarter_of_what_it_dealt() -> void:
	var attacker: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [])
	var battle: Gen2Battle = _battle(attacker, _mon(Fixture.BULBASAUR, 50, [Fixture.TACKLE]))
	var events: Array = battle.take_turn(0, 0)

	var hit: Dictionary = _first(events, Gen2Battle.HIT)
	var recoil: Dictionary = _first(events, Gen2Battle.RECOIL)
	assert_false(recoil.is_empty(), "Struggle recoils")
	assert_eq(int(recoil["amount"]), maxi(int(hit["amount"]) / 4, 1))
	# Against the health the event carries, not against the Pokémon: Bulbasaur
	# gets its own turn afterwards and takes more off.
	assert_eq(int(recoil["hp"]), attacker.max_hp() - int(recoil["amount"]))


func test_an_immunity_is_reported_rather_than_a_hit_for_nothing() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.THUNDERBOLT]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(events, Gen2Battle.NO_EFFECT).size(), 1)
	assert_true(_of_type(events, Gen2Battle.HIT).filter(
		func(event: Dictionary) -> bool: return event["side"] == Gen2Battle.PLAYER
	).is_empty(), "no hit event for a move that does not affect it")
	assert_eq(battle.enemy.hp, battle.enemy.max_hp())


func test_a_hit_carries_the_numbers_the_screen_needs() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.THUNDERBOLT]),
		_mon(Fixture.BULBASAUR, 50, [Fixture.TACKLE])
	)
	var hit: Dictionary = _first(battle.take_turn(0, 0), Gen2Battle.HIT)
	assert_eq(hit["side"], Gen2Battle.PLAYER)
	assert_eq(hit["target"], Gen2Battle.ENEMY)
	assert_eq(int(hit["effectiveness"]), 5, "Grass resists Electric")
	assert_between(int(hit["amount"]), 22, 52)
	assert_eq(int(hit["hp"]), battle.enemy.hp)
	assert_eq(int(hit["max_hp"]), battle.enemy.max_hp())


func test_a_faint_ends_the_turn_before_the_other_side_answers() -> void:
	# A level 5 Bulbasaur cannot survive a level 100 Pikachu, and a Pokémon that
	# has fainted does not get its turn.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 100, [Fixture.THUNDERBOLT]),
		_mon(Fixture.BULBASAUR, 5, [Fixture.TACKLE])
	)
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(events, Gen2Battle.USED_MOVE).size(), 1, "only the first side acted")
	assert_eq(_first(events, Gen2Battle.FAINTED)["side"], Gen2Battle.ENEMY)
	assert_true(battle.is_over())
	assert_eq(battle.winner(), Gen2Battle.PLAYER)


func test_a_battle_that_is_over_does_not_take_another_turn() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 100, [Fixture.THUNDERBOLT]),
		_mon(Fixture.BULBASAUR, 5, [Fixture.TACKLE])
	)
	battle.take_turn(0, 0)
	assert_eq(battle.take_turn(0, 0), [])


func test_the_last_event_of_a_finished_battle_says_who_won() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 100, [Fixture.THUNDERBOLT]),
		_mon(Fixture.BULBASAUR, 5, [Fixture.TACKLE])
	)
	var events: Array = battle.take_turn(0, 0)
	assert_eq(events[events.size() - 1]["type"], Gen2Battle.OVER)
	assert_eq(events[events.size() - 1]["winner"], Gen2Battle.PLAYER)


func test_a_battle_runs_to_an_end_rather_than_going_round_forever() -> void:
	# The one thing a turn loop has to do. Two Pokémon that will run out of PP
	# long before they run out of health, so this only terminates if Struggle and
	# its recoil both work.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 20, [Fixture.THUNDERBOLT]),
		_mon(Fixture.PIKACHU, 20, [Fixture.THUNDERBOLT])
	)
	var turns: int = 0
	while not battle.is_over() and turns < 500:
		battle.take_turn(0, 0)
		turns += 1
	assert_true(battle.is_over(), "still going after %d turns" % turns)
	assert_lt(turns, 500)


func test_an_unusable_slot_answers_struggle_rather_than_nothing() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.THUNDERBOLT]),
		_mon(Fixture.BULBASAUR, 50, [Fixture.TACKLE])
	)
	assert_eq(battle.move_for(Gen2Battle.PLAYER, 0), Fixture.THUNDERBOLT)
	assert_eq(battle.move_for(Gen2Battle.PLAYER, 3), Gen2Damage.STRUGGLE)


func test_a_battle_needs_both_sides() -> void:
	assert_null(Gen2Battle.create(_data, null, _mon(Fixture.PIKACHU, 5, []), _rng))
	assert_null(Gen2Battle.create(null, _mon(Fixture.PIKACHU, 5, []), _mon(
		Fixture.PIKACHU, 5, []
	), _rng))
