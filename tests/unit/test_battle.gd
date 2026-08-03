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


## Two Pokémon a side, which is what everything below is about.
func _party_battle(player: Array, enemy: Array) -> Gen2Battle:
	return Gen2Battle.create_parties(
		_data, Gen2Party.create(player), Gen2Party.create(enemy), _rng
	)


func _faint(mon: Gen2BattleMon) -> void:
	mon.take_damage(mon.max_hp())


func test_a_battle_is_not_over_while_a_party_still_has_somebody() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 20, [Fixture.TACKLE])],
		[_mon(Fixture.CHARMANDER, 20, [Fixture.TACKLE])]
	)
	_faint(battle.player)
	assert_false(battle.is_over(), "one down is a replacement, not a defeat")
	assert_true(battle.must_replace(Gen2Battle.PLAYER))
	assert_false(battle.must_replace(Gen2Battle.ENEMY))


func test_nothing_happens_while_a_replacement_is_owed() -> void:
	# The cartridge's order: the field is settled before the next turn is taken.
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 20, [Fixture.TACKLE])],
		[_mon(Fixture.CHARMANDER, 20, [Fixture.TACKLE])]
	)
	_faint(battle.player)
	assert_eq(battle.take_turn(0, 0), [])


func test_sending_one_out_after_a_faint_calls_nobody_back() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 20, [Fixture.TACKLE])],
		[_mon(Fixture.CHARMANDER, 20, [Fixture.TACKLE])]
	)
	_faint(battle.player)
	var events: Array = battle.send_out(Gen2Battle.PLAYER, 1)
	assert_eq(_of_type(events, Gen2Battle.WITHDREW).size(), 0, "there was nobody to call back")
	assert_eq(_first(events, Gen2Battle.SENT_OUT)["index"], 1)
	assert_eq(battle.player.species, Fixture.GEODUDE)
	assert_false(battle.must_replace(Gen2Battle.PLAYER))


func test_a_switch_between_turns_calls_one_back_and_sends_one_out() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 20, [Fixture.TACKLE])],
		[_mon(Fixture.CHARMANDER, 20, [Fixture.TACKLE])]
	)
	var events: Array = battle.send_out(Gen2Battle.PLAYER, 1)
	assert_eq(events.size(), 2)
	assert_eq(events[0]["type"], Gen2Battle.WITHDREW)
	assert_eq(int(events[0]["index"]), 0)
	assert_eq(events[1]["type"], Gen2Battle.SENT_OUT)


func test_a_battle_is_over_when_a_whole_party_is_down() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 20, [Fixture.TACKLE])],
		[_mon(Fixture.CHARMANDER, 20, [Fixture.TACKLE])]
	)
	_faint(battle.party(Gen2Battle.PLAYER).at(0))
	_faint(battle.party(Gen2Battle.PLAYER).at(1))
	assert_true(battle.is_over())
	assert_eq(battle.winner(), Gen2Battle.ENEMY)


func test_a_switch_goes_before_a_move_however_slow_the_switcher_is() -> void:
	# Not a very fast move: the cartridge settles a switch before it looks at
	# priority at all, which is why a switching side takes the incoming Pokémon's
	# hit rather than trading with the outgoing one.
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE]), _mon(Fixture.MAGCARGO, 50, [Fixture.TACKLE])],
		[_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])]
	)
	var events: Array = battle.take_actions(Gen2Battle.switch_to(1), Gen2Battle.use_move(0))
	assert_eq(events[0]["type"], Gen2Battle.WITHDREW)
	assert_eq(events[1]["type"], Gen2Battle.SENT_OUT)
	assert_eq(_first(events, Gen2Battle.USED_MOVE)["side"], Gen2Battle.ENEMY)
	assert_eq(_first(events, Gen2Battle.HIT)["target"], Gen2Battle.PLAYER)


func test_the_pokemon_that_came_in_is_the_one_that_gets_hit() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE]), _mon(Fixture.MAGCARGO, 50, [Fixture.TACKLE])],
		[_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])]
	)
	var incoming: Gen2BattleMon = battle.party(Gen2Battle.PLAYER).at(1)
	var outgoing: Gen2BattleMon = battle.party(Gen2Battle.PLAYER).at(0)
	battle.take_actions(Gen2Battle.switch_to(1), Gen2Battle.use_move(0))
	assert_lt(incoming.hp, incoming.max_hp())
	assert_eq(outgoing.hp, outgoing.max_hp(), "the one that left is untouched")


func test_a_switch_that_cannot_be_made_is_refused_rather_than_approximated() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])],
		[_mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE])]
	)
	_faint(battle.party(Gen2Battle.PLAYER).at(1))
	var events: Array = battle.take_actions(Gen2Battle.switch_to(1), Gen2Battle.use_move(0))
	assert_eq(_of_type(events, Gen2Battle.SENT_OUT).size(), 0)
	assert_eq(battle.player.species, Fixture.PIKACHU)


func test_a_pokemon_knocked_out_before_it_moves_does_not_move() -> void:
	# Most of what speed is for, and the reason a faint ends the turn where it is.
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 50, [Fixture.THUNDERBOLT])],
		[_mon(Fixture.CHARMANDER, 5, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 5, [Fixture.TACKLE])]
	)
	var events: Array = battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0))
	assert_eq(_of_type(events, Gen2Battle.USED_MOVE).size(), 1)
	assert_eq(_of_type(events, Gen2Battle.FAINTED).size(), 1)
	assert_false(battle.is_over(), "there is another one behind it")
	assert_true(battle.must_replace(Gen2Battle.ENEMY))


func test_a_burn_halves_what_a_pokemon_hits_with() -> void:
	# Through the stat rather than through the stored one: a Pokémon cured of a
	# burn has its Attack back with nothing recalculated.
	var mon: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])
	var healthy: int = mon.stat("attack")
	mon.status = Gen2Status.BURN
	assert_eq(mon.stat("attack"), Gen2Status.apply_burn(healthy))
	assert_eq(mon.unmodified_stat("attack"), healthy, "a critical hit is free of it")


func test_paralysis_quarters_what_a_pokemon_moves_at() -> void:
	var mon: Gen2BattleMon = _mon(Fixture.PIKACHU, 50, [Fixture.TACKLE])
	var healthy: int = mon.stat("speed")
	mon.status = Gen2Status.PARALYSIS
	assert_eq(mon.stat("speed"), Gen2Status.apply_paralysis(healthy))


func test_a_paralysed_pokemon_loses_the_turn_order_it_had() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE])
	)
	assert_eq(_first(battle.take_turn(0, 0), Gen2Battle.USED_MOVE)["side"], Gen2Battle.PLAYER)

	battle.player.status = Gen2Status.PARALYSIS
	assert_eq(
		_first(battle.take_turn(0, 0), Gen2Battle.USED_MOVE)["side"], Gen2Battle.ENEMY,
		"110 Speed quartered is under Charmander's 65"
	)


func test_a_sleeping_pokemon_does_not_move() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	battle.player.status = 3
	var events: Array = battle.take_turn(0, 0)
	var stopped: Dictionary = _first(events, Gen2Battle.CANNOT_MOVE)
	assert_eq(int(stopped["side"]), Gen2Battle.PLAYER)
	assert_eq(stopped["reason"], &"sleep")
	assert_eq(_of_type(events, Gen2Battle.USED_MOVE).size(), 1, "only the enemy moved")


func test_waking_up_does_not_cost_the_turn() -> void:
	# Generation 2's rule and not Generation 1's: the counter runs out, the
	# Pokémon is told it woke, and it attacks in the same breath.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	battle.player.status = 1
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(events, Gen2Battle.WOKE_UP).size(), 1)
	assert_eq(_of_type(events, Gen2Battle.CANNOT_MOVE).size(), 0)
	assert_eq(_of_type(events, Gen2Battle.USED_MOVE).size(), 2, "both of them moved")
	assert_eq(battle.player.status, Gen2Status.NONE)


func test_a_frozen_pokemon_does_not_move() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	battle.player.status = Gen2Status.FREEZE
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_first(events, Gen2Battle.CANNOT_MOVE)["reason"], &"freeze")
	assert_eq(battle.player.status, Gen2Status.FREEZE, "and stays frozen")


func test_flame_wheel_is_used_through_a_freeze_and_thaws_it() -> void:
	# The only two moves in the game that do, and the reason they are named by
	# number rather than by effect: nothing about their effect says it.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.FLAME_WHEEL]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	battle.player.status = Gen2Status.FREEZE
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(events, Gen2Battle.THAWED).size(), 1)
	assert_eq(_of_type(events, Gen2Battle.CANNOT_MOVE).size(), 0)
	assert_eq(battle.player.status, Gen2Status.NONE)


func test_a_burn_takes_an_eighth_at_the_end_of_the_turn() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	battle.player.status = Gen2Status.BURN
	var before: int = battle.player.hp
	var hurt: Dictionary = _first(battle.take_turn(0, 0), Gen2Battle.HURT_BY_STATUS)
	assert_eq(hurt["name"], &"burn")
	assert_eq(int(hurt["amount"]), Gen2Status.residual_damage(battle.player.max_hp()))
	assert_lt(battle.player.hp, before)


func test_a_poison_can_be_the_thing_that_faints_a_pokemon() -> void:
	# The enemy growls rather than attacking, so that the only thing that can put
	# the player down is the poison.
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])],
		[_mon(Fixture.MAGCARGO, 50, [Fixture.GROWL])]
	)
	battle.player.status = Gen2Status.POISON
	battle.player.hp = 1
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(events, Gen2Battle.HURT_BY_STATUS).size(), 1)
	assert_true(battle.player.is_fainted())
	assert_eq(_of_type(events, Gen2Battle.FAINTED).size(), 1)
	assert_true(battle.must_replace(Gen2Battle.PLAYER))


func test_a_pokemon_that_has_already_fainted_is_not_burned_further() -> void:
	var battle: Gen2Battle = _party_battle(
		[_mon(Fixture.PIKACHU, 5, [Fixture.TACKLE]), _mon(Fixture.GEODUDE, 5, [Fixture.TACKLE])],
		[_mon(Fixture.MAGCARGO, 50, [Fixture.SLASH])]
	)
	battle.player.status = Gen2Status.BURN
	battle.player.hp = 1
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(events, Gen2Battle.HURT_BY_STATUS).size(), 0)


func test_a_status_move_puts_its_status_on() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.SLEEP_POWDER]),
		_mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE])
	)
	var inflicted: Dictionary = _first(battle.take_turn(0, 0), Gen2Battle.STATUS_INFLICTED)
	assert_eq(inflicted["name"], &"sleep")
	assert_true(Gen2Status.is_asleep(battle.enemy.status))


func test_one_status_at_a_time() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.SLEEP_POWDER]),
		_mon(Fixture.CHARMANDER, 50, [Fixture.TACKLE])
	)
	battle.enemy.status = Gen2Status.BURN
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(events, Gen2Battle.STATUS_INFLICTED).size(), 0)
	assert_eq(battle.enemy.status, Gen2Status.BURN, "the burn is not replaced")


func test_a_type_that_cannot_be_touched_cannot_be_paralysed_either() -> void:
	# Thunder Wave against a Ground type. A status move is stopped by an immunity
	# exactly as an attack is, and it says so rather than saying it missed.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.THUNDER_WAVE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(events, Gen2Battle.NO_EFFECT).size(), 1)
	assert_eq(_of_type(events, Gen2Battle.STATUS_INFLICTED).size(), 0)
	assert_eq(battle.enemy.status, Gen2Status.NONE)


func test_a_secondary_effect_that_comes_up_leaves_its_status_behind() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.EMBER_BURNS]),
		_mon(Fixture.BULBASAUR, 50, [Fixture.TACKLE])
	)
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(events, Gen2Battle.HIT).size(), 2, "both of them attacked")
	assert_true(Gen2Status.has(battle.enemy.status, Gen2Status.BURN))


func test_a_secondary_effect_that_does_not_come_up_still_does_its_damage() -> void:
	# The roll sits between the hit and the status, so a failed one costs the
	# status and nothing else.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.NEVER_BURNS]),
		_mon(Fixture.BULBASAUR, 50, [Fixture.TACKLE])
	)
	var events: Array = battle.take_turn(0, 0)
	assert_gt(int(_first(events, Gen2Battle.HIT)["amount"]), 0)
	assert_eq(battle.enemy.status, Gen2Status.NONE)


func test_a_stat_drop_actually_bends_the_stat_the_damage_formula_reads() -> void:
	# Not just an event: the stage has to reach Gen2BattleMon.stat() itself, which
	# is what a battle asserted only on the event log would miss.
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.TACKLE]),
		_mon(Fixture.GEODUDE, 50, [Fixture.GROWL])
	)
	var before: int = battle.player.stat("attack")
	battle.take_turn(0, 0)
	assert_lt(battle.player.stat("attack"), before)


func test_ancientpower_raises_the_users_stats_as_one_event() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.ANCIENTPOWER]),
		_mon(Fixture.GEODUDE, 50, [Fixture.TACKLE])
	)
	var events: Array = battle.take_turn(0, 0)
	assert_eq(battle.player.stage("attack"), 1)
	assert_eq(battle.player.stage("speed"), 1)
	assert_eq(_of_type(events, Gen2Battle.STAT_CHANGED).size(), 1, "one event for all five")


func test_a_secondary_stat_drop_that_never_rolls_still_deals_its_damage() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.PSYCHIC_NEVER]),
		_mon(Fixture.BULBASAUR, 50, [Fixture.TACKLE])
	)
	var events: Array = battle.take_turn(0, 0)
	assert_gt(int(_first(events, Gen2Battle.HIT)["amount"]), 0)
	assert_eq(battle.enemy.stage("sp_defense"), 0)


func test_a_status_move_that_cannot_rise_further_says_so() -> void:
	var battle: Gen2Battle = _battle(
		_mon(Fixture.PIKACHU, 50, [Fixture.SWORDS_DANCE]),
		_mon(Fixture.MAGCARGO, 50, [Fixture.TACKLE])
	)
	battle.player.change_stage("attack", Gen2Stats.MAX_STAGE)
	var events: Array = battle.take_turn(0, 0)
	assert_eq(_of_type(events, Gen2Battle.STAT_CHANGED).size(), 0)
	assert_eq(_of_type(events, Gen2Battle.STAT_CHANGE_FAILED).size(), 1)
