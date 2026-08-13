extends GutTest

## `CheckWhetherToAskSwitch` and `OfferSwitch` (`engine/battle/core.asm`), which
## is what the OPTION screen's SET/SHIFT row decides. On SHIFT a trainer's own
## switch offers the player one; on SET it does not, and neither does a wild.

const Fixture := preload("res://tests/unit/battle_fixture.gd")

var _directory: String = ""
var _data: GameData = null
var _rng: RandomNumberGenerator = null


func before_each() -> void:
	_directory = RomCache.directory_for(&"battlestyletest", "0123456789abcdef")
	_data = Fixture.build(_directory)
	_rng = RandomNumberGenerator.new()
	_rng.seed = 7


func after_each() -> void:
	RomCache.clear(_directory)


func _mon(species: int, level: int, moves: Array) -> Gen2BattleMon:
	return Gen2BattleMon.create(_data, species, level, moves)


## Two a side, so both the trainer and the player have somebody to switch to.
func _battle(trainer: bool, set_style: bool) -> Gen2Battle:
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data,
		Gen2Party.create([
			_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE]),
			_mon(Fixture.BULBASAUR, 20, [Fixture.TACKLE]),
		]),
		Gen2Party.create([
			_mon(Fixture.BULBASAUR, 5, [Fixture.TACKLE]),
			_mon(Fixture.PIKACHU, 5, [Fixture.TACKLE]),
		]),
		_rng, trainer
	)
	battle.battle_style_set = set_style
	return battle


func _switch_turn(battle: Gen2Battle) -> Array:
	return battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.switch_to(1))


## SHIFT: the question comes up before the incoming Pokémon is on the field,
## which is why `OfferSwitch` runs in front of `ShowSetEnemyMonAndSendOutAnimation`.
func test_shift_offers_the_player_a_switch_when_the_trainer_takes_one() -> void:
	var battle: Gen2Battle = _battle(true, false)
	var events: Array = _switch_turn(battle)
	assert_eq(battle.awaiting_switch_offer(), 1)
	assert_eq(battle.party(Gen2Battle.ENEMY).active, 0, "and it is not out yet")
	var offer: Dictionary = _first(events, Gen2Battle.SWITCH_OFFERED)
	assert_eq(offer["side"], Gen2Battle.PLAYER)
	assert_eq(offer["index"], 1)
	assert_eq(offer["species"], Fixture.PIKACHU)


func test_answering_no_sends_the_trainer_out_and_finishes_the_turn() -> void:
	var battle: Gen2Battle = _battle(true, false)
	_switch_turn(battle)
	var after: Array = battle.answer_switch_offer(-1)
	assert_eq(battle.awaiting_switch_offer(), -1)
	assert_eq(battle.party(Gen2Battle.ENEMY).active, 1)
	assert_eq(battle.party(Gen2Battle.PLAYER).active, 0, "the player stayed")
	assert_false(after.is_empty(), "the rest of the turn ran")


func test_answering_yes_switches_the_player_as_well() -> void:
	var battle: Gen2Battle = _battle(true, false)
	_switch_turn(battle)
	battle.answer_switch_offer(1)
	assert_eq(battle.awaiting_switch_offer(), -1)
	assert_eq(battle.party(Gen2Battle.ENEMY).active, 1)
	assert_eq(battle.party(Gen2Battle.PLAYER).active, 1)


## `PickSwitchMonInBattle` redisplays its list rather than accepting a Pokémon
## that cannot come in, so a refused slot leaves the question standing.
func test_a_slot_the_party_refuses_leaves_the_question_up() -> void:
	var battle: Gen2Battle = _battle(true, false)
	_switch_turn(battle)
	assert_eq(battle.answer_switch_offer(0), [], "the one already out")
	assert_eq(battle.answer_switch_offer(5), [], "past the party")
	assert_eq(battle.awaiting_switch_offer(), 1)


## The turn cannot be restarted while the question stands, the same refusal a
## pending Baton Pass gets.
func test_no_new_turn_starts_while_the_question_stands() -> void:
	var battle: Gen2Battle = _battle(true, false)
	_switch_turn(battle)
	assert_eq(
		battle.take_actions(Gen2Battle.use_move(0), Gen2Battle.use_move(0)), []
	)
	assert_eq(battle.awaiting_switch_offer(), 1)


## SET is `bit BATTLE_SHIFT` returning nonzero, which is the whole of
## `CheckWhetherToAskSwitch`'s third refusal.
func test_set_never_asks() -> void:
	var battle: Gen2Battle = _battle(true, true)
	_switch_turn(battle)
	assert_eq(battle.awaiting_switch_offer(), -1)
	assert_eq(battle.party(Gen2Battle.ENEMY).active, 1, "it just switched")


## The other two refusals: a wild has no trainer to switch, and a player with
## nobody else has nothing to be asked about.
func test_a_wild_battle_and_a_lone_player_are_never_asked() -> void:
	var wild: Gen2Battle = _battle(false, false)
	assert_false(wild.should_offer_switch())

	var alone: Gen2Battle = Gen2Battle.create_parties(
		_data, Gen2Party.of(_mon(Fixture.PIKACHU, 20, [Fixture.TACKLE])),
		Gen2Party.create([
			_mon(Fixture.BULBASAUR, 5, [Fixture.TACKLE]),
			_mon(Fixture.PIKACHU, 5, [Fixture.TACKLE]),
		]),
		_rng, true
	)
	alone.battle_style_set = false
	assert_false(alone.should_offer_switch())


## `CheckCurPartyMonFainted`'s carry: a player whose own Pokémon is down is
## replacing rather than choosing, so the offer does not apply.
func test_a_fainted_player_mon_is_not_asked() -> void:
	var battle: Gen2Battle = _battle(true, false)
	battle.mon(Gen2Battle.PLAYER).take_damage(battle.player.max_hp())
	assert_false(battle.should_offer_switch())


func _first(events: Array, type: StringName) -> Dictionary:
	for event: Dictionary in events:
		if StringName(event.get("type", &"")) == type:
			return event
	return {}
