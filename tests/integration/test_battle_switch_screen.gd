extends GutTest

## Scene integration for the two questions a battle asks about switching:
## `OfferSwitch`'s yes/no, which SHIFT is the whole point of, and the forced
## party list Baton Pass opens (`engine/battle/core.asm`).
##
## The cache is synthetic; the battle screen, its text box, the two menus and
## [Gen2Battle] are the production paths. Both used to be answered by the screen
## because there was nothing to answer them with.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")
const BattleFixture := preload("res://tests/unit/battle_fixture.gd")

var _data: GameData = null
var _screen: Gen2BattleScreen = null
var _rng := RandomNumberGenerator.new()


func before_each() -> void:
	Gen2ModHost.reset()
	Fixture.build()
	_data = GameData.open_directory(Fixture.directory())
	_rng.seed = 5


func after_each() -> void:
	if is_instance_valid(_screen):
		_screen.free()
		_screen = null
	RomCache.clear(Fixture.directory())
	Gen2ModHost.reset()


func _mon(species: int, moves: Array) -> Gen2BattleMon:
	return Gen2BattleMon.create(_data, species, 20, moves)


func _open(battle: Gen2Battle, actions: Array) -> void:
	var packed: PackedScene = load("res://game/battle/battle_screen.tscn")
	_screen = packed.instantiate() as Gen2BattleScreen
	_screen.set_data(_data)
	add_child(_screen)
	await get_tree().process_frame
	_screen.show_matchup(BattleFixture.GEODUDE, BattleFixture.PIKACHU, 20, 20)
	_screen.set("_battle", battle)
	_screen.set("_pending", battle.take_actions(actions[0], actions[1]))
	await get_tree().process_frame


## A trainer battle with a bench on both sides, which is what
## `CheckWhetherToAskSwitch` needs before it asks anything.
func _trainer_battle(shift: bool) -> Gen2Battle:
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data,
		Gen2Party.create([
			_mon(BattleFixture.PIKACHU, [BattleFixture.TACKLE]),
			_mon(BattleFixture.BULBASAUR, [BattleFixture.TACKLE]),
		]),
		Gen2Party.create([
			_mon(BattleFixture.GEODUDE, [BattleFixture.TACKLE]),
			_mon(BattleFixture.CHARMANDER, [BattleFixture.TACKLE]),
		]),
		_rng, true
	)
	battle.battle_style_set = not shift
	return battle


func _settle_bars() -> void:
	var guard: int = 4000
	while _screen.frames_running() and guard > 0:
		_screen.advance_frame()
		guard -= 1


func _stage() -> String:
	return String(_screen.battle_snapshot()["switch_stage"])


func _cursor() -> int:
	return int(_screen.battle_snapshot()["switch_cursor"])


func _layer() -> TextureRect:
	return _screen.get("_menu_layer")


func _advance_to(stage: String, limit: int = 40) -> void:
	for _press: int in limit:
		if _stage() == stage:
			return
		_settle_bars()
		_screen.finish()
		_screen.advance()
		await get_tree().process_frame


## Reads the question to its last page without advancing off it, which is what a
## player does before a yes/no box is up to answer.
func _read_question() -> void:
	var box: Gen2TextBox = _screen.get("_box")
	while box != null and (box.is_revealing() or box.has_pages_left()):
		box.finish()
		if box.has_pages_left():
			box.advance()
	_screen._refresh_menu_layer()
	await get_tree().process_frame


func _press(button: int) -> void:
	_settle_bars()
	_screen._handle_button(button)
	await get_tree().process_frame


## `OfferSwitch` prints the question and only then places the box, so the two
## paragraphs cannot be answered before they have been read.
func test_shift_puts_the_question_up_before_its_yes_no_box() -> void:
	var battle: Gen2Battle = _trainer_battle(true)
	await _open(battle, [Gen2Battle.use_move(0), Gen2Battle.switch_to(1)])
	await _advance_to("offer")

	assert_eq(_stage(), "offer")
	assert_true(
		String(_screen.battle_snapshot()["message"]).contains("change PKMN"),
		String(_screen.battle_snapshot()["message"])
	)
	assert_false(_layer().visible, "the box is not up while the question is printing")

	await _read_question()
	assert_true(_layer().visible, "and is once it has been read")
	assert_eq(_cursor(), 0, "YesNoMenuHeader opens on YES")


## NO is `.said_no`: the trainer's Pokémon comes in and the player's stays,
## which is what SET would have done without asking.
func test_no_sends_the_trainer_out_and_leaves_the_player_standing() -> void:
	var battle: Gen2Battle = _trainer_battle(true)
	await _open(battle, [Gen2Battle.use_move(0), Gen2Battle.switch_to(1)])
	await _advance_to("offer")
	await _read_question()

	await _press(Gen2Button.DOWN)
	assert_eq(_cursor(), 1)
	await _press(Gen2Button.A)

	assert_eq(_stage(), "", "the question is answered")
	assert_eq(battle.awaiting_switch_offer(), -1)
	assert_eq(battle.party(Gen2Battle.ENEMY).active, 1)
	assert_eq(battle.party(Gen2Battle.PLAYER).active, 0)
	assert_false(_layer().visible)


## `InterpretTwoOptionMenu` returns carry on B, which `OfferSwitch` reads as no.
func test_b_is_the_same_answer_as_no() -> void:
	var battle: Gen2Battle = _trainer_battle(true)
	await _open(battle, [Gen2Battle.use_move(0), Gen2Battle.switch_to(1)])
	await _advance_to("offer")
	await _read_question()

	await _press(Gen2Button.B)
	assert_eq(_stage(), "")
	assert_eq(battle.party(Gen2Battle.PLAYER).active, 0)


## YES is `SetUpBattlePartyMenu` and `PickSwitchMonInBattle`: the party list, and
## the row chosen there is the switch.
func test_yes_opens_the_party_list_and_the_chosen_row_switches() -> void:
	var battle: Gen2Battle = _trainer_battle(true)
	await _open(battle, [Gen2Battle.use_move(0), Gen2Battle.switch_to(1)])
	await _advance_to("offer")
	await _read_question()

	await _press(Gen2Button.A)
	assert_eq(_stage(), "pick")
	assert_true(_layer().visible)
	assert_eq(_layer().position, Vector2.ZERO, "the list is the whole screen")
	assert_false((_screen.get("_box") as Gen2TextBox).visible, "and the battle's box is not")

	await _press(Gen2Button.DOWN)
	assert_eq(_cursor(), 1)
	await _press(Gen2Button.A)

	assert_eq(_stage(), "")
	assert_eq(battle.party(Gen2Battle.PLAYER).active, 1, "the player switched too")
	assert_eq(battle.party(Gen2Battle.ENEMY).active, 1)
	assert_true((_screen.get("_box") as Gen2TextBox).visible)


## `SwitchMonAlreadyOut` is `jr c, .pick`: the line is printed over the list and
## the list comes back rather than the question being answered.
func test_the_one_already_out_is_refused_and_the_list_comes_back() -> void:
	var battle: Gen2Battle = _trainer_battle(true)
	await _open(battle, [Gen2Battle.use_move(0), Gen2Battle.switch_to(1)])
	await _advance_to("offer")
	await _read_question()
	await _press(Gen2Button.A)

	await _press(Gen2Button.A)
	assert_eq(_stage(), "refused")
	assert_true(
		String(_screen.battle_snapshot()["message"]).contains("is already out"),
		String(_screen.battle_snapshot()["message"])
	)
	assert_eq(battle.awaiting_switch_offer(), 1, "and nothing was answered")

	## The first press finishes the line the box is still revealing, as it does
	## anywhere else; the second is the one `StdBattleTextbox` was waiting for.
	await _press(Gen2Button.A)
	assert_eq(_stage(), "refused")
	await _press(Gen2Button.A)
	assert_eq(_stage(), "pick", "the list is redrawn")
	assert_true(_layer().visible)


## CANCEL is `OfferSwitch.canceled_switch`, which falls into `.said_no`.
func test_cancelling_the_list_is_the_same_answer_as_no() -> void:
	var battle: Gen2Battle = _trainer_battle(true)
	await _open(battle, [Gen2Battle.use_move(0), Gen2Battle.switch_to(1)])
	await _advance_to("offer")
	await _read_question()
	await _press(Gen2Button.A)

	await _press(Gen2Button.B)
	assert_eq(_stage(), "")
	assert_eq(battle.party(Gen2Battle.PLAYER).active, 0)
	assert_eq(battle.party(Gen2Battle.ENEMY).active, 1)


## SET is the whole of `CheckWhetherToAskSwitch`'s third refusal, so no menu is
## ever opened and the turn runs on.
func test_set_never_opens_a_menu() -> void:
	var battle: Gen2Battle = _trainer_battle(false)
	await _open(battle, [Gen2Battle.use_move(0), Gen2Battle.switch_to(1)])
	await _advance_to("offer", 20)
	assert_eq(_stage(), "")
	assert_eq(battle.party(Gen2Battle.ENEMY).active, 1)


func _baton_pass_battle() -> Gen2Battle:
	return Gen2Battle.create_parties(
		_data,
		Gen2Party.create([
			_mon(BattleFixture.PIKACHU, [BattleFixture.BATON_PASS]),
			_mon(BattleFixture.BULBASAUR, [BattleFixture.TACKLE]),
		]),
		Gen2Party.of(_mon(BattleFixture.GEODUDE, [BattleFixture.TACKLE])),
		_rng, false
	)


## `ForcePickSwitchMonInBattle` cannot be backed out of: neither B nor the CANCEL
## row leaves the list, and the turn stays standing behind it.
func test_baton_pass_opens_a_list_that_cannot_be_backed_out_of() -> void:
	var battle: Gen2Battle = _baton_pass_battle()
	await _open(battle, [Gen2Battle.use_move(0), Gen2Battle.use_move(0)])
	await _advance_to("pick")

	assert_eq(_stage(), "pick")
	assert_true(bool(_screen.battle_snapshot()["switch_forced"]))
	assert_eq(battle.awaiting_baton_pass(), Gen2Battle.PLAYER)

	await _press(Gen2Button.B)
	assert_eq(_stage(), "pick", "B is swallowed")
	assert_eq(battle.awaiting_baton_pass(), Gen2Battle.PLAYER)

	## Two rows and CANCEL, so two presses down reach it.
	await _press(Gen2Button.DOWN)
	await _press(Gen2Button.DOWN)
	assert_eq(_cursor(), 2)
	await _press(Gen2Button.A)
	assert_eq(_stage(), "pick", "and so is the CANCEL row")

	await _press(Gen2Button.UP)
	await _press(Gen2Button.A)
	assert_eq(_stage(), "")
	assert_eq(battle.awaiting_baton_pass(), -1)
	assert_eq(battle.party(Gen2Battle.PLAYER).active, 1, "the pass landed on the row chosen")


## The enemy's own Baton Pass is `FindMonInOTPartyToSwitchIntoBattle`, the AI's
## pick, and opens no menu at all.
func test_the_enemys_baton_pass_is_answered_by_its_own_ai() -> void:
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data,
		Gen2Party.of(_mon(BattleFixture.PIKACHU, [BattleFixture.TACKLE])),
		Gen2Party.create([
			_mon(BattleFixture.GEODUDE, [BattleFixture.BATON_PASS]),
			_mon(BattleFixture.CHARMANDER, [BattleFixture.TACKLE]),
		]),
		_rng, true
	)
	await _open(battle, [Gen2Battle.use_move(0), Gen2Battle.use_move(0)])
	await _advance_to("pick", 20)

	assert_eq(_stage(), "", "no menu was opened for the other side")
	assert_eq(battle.awaiting_baton_pass(), -1)
	assert_eq(battle.party(Gen2Battle.ENEMY).active, 1)


## A faint with somebody behind it, arranged so the turn cannot go the other way:
## Swift never rolls accuracy and one hit point cannot survive it.
func _faint_battle(trainer: bool, faint_player: bool) -> Gen2Battle:
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data,
		Gen2Party.create([
			_mon(BattleFixture.PIKACHU, [BattleFixture.SWIFT]),
			_mon(BattleFixture.BULBASAUR, [BattleFixture.TACKLE]),
		]),
		Gen2Party.create([
			_mon(BattleFixture.GEODUDE, [BattleFixture.SWIFT]),
			_mon(BattleFixture.CHARMANDER, [BattleFixture.TACKLE]),
		]),
		_rng, trainer
	)
	battle.battle_style_set = false
	if faint_player:
		battle.player.hp = 1
	else:
		battle.enemy.hp = 1
	return battle


## `AskUseNextPokemon`: the question, then the same `lb bc, 1, 7` box
## `OfferSwitch` uses, and a YES that falls straight into the party list.
func test_a_wild_faint_asks_whether_to_use_the_next_pokemon() -> void:
	var battle: Gen2Battle = _faint_battle(false, true)
	await _open(battle, [Gen2Battle.use_move(0), Gen2Battle.use_move(0)])
	await _advance_to("use_next")

	assert_eq(_stage(), "use_next")
	assert_true(
		String(_screen.battle_snapshot()["message"]).contains("Use next"),
		String(_screen.battle_snapshot()["message"])
	)
	await _read_question()
	assert_true(_layer().visible)
	assert_eq(_cursor(), 0, "YesNoMenuHeader opens on YES")

	await _press(Gen2Button.A)
	assert_eq(_stage(), "pick", "ForcePlayerMonChoice, with no press in between")
	assert_eq(String(_screen.battle_snapshot()["switch_reason"]), "replace")
	assert_true(bool(_screen.battle_snapshot()["switch_forced"]))


## NO is the run, and Pikachu in the first party slot is faster than the Geodude
## chasing it, so it gets away on speed alone.
func test_no_runs_from_the_wild_battle_instead_of_replacing() -> void:
	var battle: Gen2Battle = _faint_battle(false, true)
	await _open(battle, [Gen2Battle.use_move(0), Gen2Battle.use_move(0)])
	await _advance_to("use_next")
	await _read_question()

	await _press(Gen2Button.B)
	assert_eq(_stage(), "")
	assert_true(battle.has_fled())
	assert_true(bool(_screen.battle_snapshot()["battle_over"]))


## `ForcePickPartyMonInBattle` cannot be backed out of, and the row chosen is
## what comes in. A trainer battle never asks the question above it.
func test_a_trainer_faint_opens_a_replacement_list_with_no_way_out() -> void:
	var battle: Gen2Battle = _faint_battle(true, true)
	await _open(battle, [Gen2Battle.use_move(0), Gen2Battle.use_move(0)])
	await _advance_to("pick")

	assert_eq(String(_screen.battle_snapshot()["switch_reason"]), "replace")
	await _press(Gen2Button.B)
	assert_eq(_stage(), "pick", "B is swallowed")

	## Two rows and CANCEL, so two presses down reach a row that refuses too.
	await _press(Gen2Button.DOWN)
	await _press(Gen2Button.DOWN)
	assert_eq(_cursor(), 2)
	await _press(Gen2Button.A)
	assert_eq(_stage(), "pick")

	await _press(Gen2Button.UP)
	await _press(Gen2Button.A)
	assert_eq(_stage(), "")
	assert_eq(battle.party(Gen2Battle.PLAYER).active, 1)
	assert_false(battle.awaiting_replacement())


## The one that just fainted is refused by `CheckIfCurPartyMonIsFitToFight`, and
## the list comes back rather than the question being answered.
func test_the_fainted_row_is_refused_and_the_list_comes_back() -> void:
	var battle: Gen2Battle = _faint_battle(true, true)
	await _open(battle, [Gen2Battle.use_move(0), Gen2Battle.use_move(0)])
	await _advance_to("pick")

	await _press(Gen2Button.A)
	assert_eq(_stage(), "refused")
	assert_true(
		String(_screen.battle_snapshot()["message"]).contains("no will to battle"),
		String(_screen.battle_snapshot()["message"])
	)
	assert_true(battle.must_replace(Gen2Battle.PLAYER), "and nothing was answered")

	await _press(Gen2Button.A)
	await _press(Gen2Button.A)
	assert_eq(_stage(), "pick", "the list is redrawn")
	assert_true(bool(_screen.battle_snapshot()["switch_forced"]), "still with no way out")


## A trainer replacing its own faint reaches `EnemySwitch`, so SHIFT asks about a
## switch here as well, before that Pokémon is on the field.
func test_shift_offers_a_switch_when_the_trainer_replaces_its_own_faint() -> void:
	var battle: Gen2Battle = _faint_battle(true, false)
	await _open(battle, [Gen2Battle.use_move(0), Gen2Battle.use_move(0)])
	await _advance_to("offer")

	assert_eq(_stage(), "offer")
	assert_eq(battle.awaiting_switch_offer(), 1)
	assert_eq(battle.party(Gen2Battle.ENEMY).active, 0, "nobody is out yet")

	await _read_question()
	await _press(Gen2Button.DOWN)
	await _press(Gen2Button.A)
	assert_eq(_stage(), "")
	assert_eq(battle.party(Gen2Battle.ENEMY).active, 1)
	assert_eq(battle.party(Gen2Battle.PLAYER).active, 0, "and the player stayed")


## A mod's renderer is offered the leftovers only while the screen is not asking
## a question of its own, the way it is for the forget prompt and ball selection.
func test_a_renderer_is_not_offered_input_while_a_menu_is_up() -> void:
	var battle: Gen2Battle = _trainer_battle(true)
	await _open(battle, [Gen2Battle.use_move(0), Gen2Battle.switch_to(1)])
	assert_true(_screen._renderer_input_free())
	await _advance_to("offer")
	assert_false(_screen._renderer_input_free())
	await _read_question()
	await _press(Gen2Button.B)
	assert_true(_screen._renderer_input_free())
