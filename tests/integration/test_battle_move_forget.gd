extends GutTest

## Scene integration for LearnMove's full-slot branch inside a battle.
##
## The cache is synthetic, but the battle screen, its text box and [Gen2Battle]
## are the production paths. The setup is the one
## `test_a_full_moveset_is_offered_a_new_move_rather_than_taught_it` uses in
## tests/unit/test_battle.gd: a level 5 Geodude with three moves beats a level 33
## Magcargo, Growl fills the fourth slot at level 6, and level 11's Slash finds
## every slot taken.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")
const BattleFixture := preload("res://tests/unit/battle_fixture.gd")

## SURF, HM03, which ForgetMove's .hmmove branch refuses to give up.
const MOVE_SURF: int = 0x39

var _data: GameData = null
var _screen: Gen2BattleScreen = null
var _rng := RandomNumberGenerator.new()


func before_each() -> void:
	Gen2ModHost.reset()
	_data = Fixture.build()
	_data = GameData.open_directory(Fixture.directory())
	_rng.seed = 11


func after_each() -> void:
	if is_instance_valid(_screen):
		_screen.free()
		_screen = null
	RomCache.clear(Fixture.directory())
	Gen2ModHost.reset()


## Opens the screen, then puts the crafted battle on it. show_matchup() builds
## its parties from the learnset, which cannot produce a full moveset at level
## 5, so the battle itself is assembled the way the unit tests assemble one.
func _open_with_full_moveset(third_move: int = BattleFixture.THUNDERBOLT) -> void:
	var packed: PackedScene = load("res://game/battle/battle_screen.tscn")
	_screen = packed.instantiate() as Gen2BattleScreen
	_screen.set_data(_data)
	add_child(_screen)
	await get_tree().process_frame
	_screen.show_matchup(BattleFixture.MAGCARGO, BattleFixture.GEODUDE, 33, 5)

	var player: Gen2BattleMon = Gen2BattleMon.create(
		_data, BattleFixture.GEODUDE, 5,
		[BattleFixture.TACKLE, BattleFixture.EMBER, third_move]
	)
	var enemy: Gen2BattleMon = Gen2BattleMon.create(
		_data, BattleFixture.MAGCARGO, 33, [BattleFixture.TACKLE]
	)
	var battle: Gen2Battle = Gen2Battle.create(_data, player, enemy, _rng)
	battle.enemy.hp = 1
	_screen.set("_battle", battle)
	_screen.set("_pending", battle.take_turn(0, 0))
	await get_tree().process_frame


## Presses through every queued event until the offer opens, which is what a
## player pressing A does.
## A draining HP bar swallows a press, the way `AnimateHPBar`'s own loop does,
## and so does the opening slide, so both are walked to their end before the
## next press. In play the screen's frames do this; a test that pressed without
## it would stall on the intro and then on the first hit.
func _settle_bars() -> void:
	var guard: int = 4000
	while _screen.frames_running() and guard > 0:
		_screen.advance_frame()
		guard -= 1


func _advance_to_offer(limit: int = 40) -> void:
	for _press: int in limit:
		if String(_screen.get("_forget_stage")) != "":
			return
		_settle_bars()
		_screen.finish()
		_screen.advance()
		await get_tree().process_frame


func _stage() -> String:
	return String(_screen.get("_forget_stage"))


## AskForgetMoveText is three paragraphs, so a confirm press pages the box
## before it answers anything. Reading it to the end first is what a player
## does; the paging itself is covered by
## test_a_confirm_pages_the_prompt_before_answering_it.
func _drain_box() -> void:
	var box: Gen2TextBox = _screen.get("_box")
	if box == null:
		return
	# A press cannot finish a printing page any more than it can on the
	# cartridge, so reading to the end is frames first and then the page turn.
	while true:
		if box.is_revealing():
			box.advance_frame()
			continue
		if not box.advance():
			return


func _press(button: int) -> void:
	_settle_bars()
	await _drain_box()
	_screen._answer_forget(button)
	await get_tree().process_frame


## The offer used to be declined automatically because no menu existed. It now
## stops and asks, and the battle does not go on behind it.
func test_a_full_moveset_opens_the_ask_instead_of_declining() -> void:
	await _open_with_full_moveset()
	var battle: Gen2Battle = _screen.get("_battle")
	assert_true(battle.must_learn_move(Gen2Battle.PLAYER))

	await _advance_to_offer()
	assert_eq(_stage(), "ask")
	assert_true(
		_screen.battle_snapshot()["message"].contains("can't learn more than four moves"),
		String(_screen.battle_snapshot()["message"])
	)

	## take_turn is reachable straight from a key press, so it has its own guard.
	_screen.take_turn()
	assert_true(battle.must_learn_move(Gen2Battle.PLAYER), "the offer still stands")
	assert_eq(_stage(), "ask")


## Yes opens ForgetMove's list, and a chosen slot is the answer.
func test_choosing_a_slot_forgets_that_move_and_learns_the_offered_one() -> void:
	await _open_with_full_moveset()
	var battle: Gen2Battle = _screen.get("_battle")
	await _advance_to_offer()

	await _press(Gen2Button.A)
	assert_eq(_stage(), "list")
	assert_eq((_screen.get("_forget_moves") as Array).size(), 4)

	## Slot 1 is Ember, an ordinary move.
	await _press(Gen2Button.DOWN)
	await _press(Gen2Button.A)
	assert_eq(_stage(), "", "the offer is answered")
	assert_false(battle.must_learn_move(Gen2Battle.PLAYER))
	assert_eq(battle.player.moves[1], BattleFixture.SLASH)
	assert_false(battle.player.moves.has(BattleFixture.EMBER))


## .hmmove prints MoveCantForgetHMText and is `jr .loop`: the list stays open
## and the offer is still unanswered.
func test_an_hm_row_is_refused_and_the_list_stays_open() -> void:
	await _open_with_full_moveset(MOVE_SURF)
	var battle: Gen2Battle = _screen.get("_battle")
	await _advance_to_offer()
	await _press(Gen2Button.A)
	assert_eq(_stage(), "list")

	## Slot 2 is SURF.
	await _press(Gen2Button.DOWN)
	await _press(Gen2Button.DOWN)
	await _press(Gen2Button.A)

	assert_eq(_stage(), "list", "the list stays open")
	assert_true(battle.must_learn_move(Gen2Battle.PLAYER))
	assert_eq(battle.player.moves[2], MOVE_SURF)
	assert_true(
		_screen.battle_snapshot()["message"].contains("HM moves can't be forgotten"),
		String(_screen.battle_snapshot()["message"])
	)


## No at the ask is LearnMove.cancel: the stop-learning yes/no, whose yes ends
## the offer with DidNotLearnMoveText and keeps the four moves.
func test_refusing_reaches_stop_learning_and_declines_the_move() -> void:
	await _open_with_full_moveset()
	var battle: Gen2Battle = _screen.get("_battle")
	await _advance_to_offer()
	var before: Array = battle.player.moves.duplicate()

	await _press(Gen2Button.RIGHT)
	await _press(Gen2Button.A)
	assert_eq(_stage(), "stop")

	await _press(Gen2Button.A)
	assert_eq(_stage(), "")
	assert_false(battle.must_learn_move(Gen2Battle.PLAYER))
	assert_eq(battle.player.moves, before, "nothing was forgotten")


## No to "Stop learning?" is `jp .loop`, back to ForgetMove's ask.
func test_declining_to_stop_returns_to_the_ask() -> void:
	await _open_with_full_moveset()
	var battle: Gen2Battle = _screen.get("_battle")
	await _advance_to_offer()

	await _press(Gen2Button.RIGHT)
	await _press(Gen2Button.A)
	assert_eq(_stage(), "stop")

	await _press(Gen2Button.RIGHT)
	await _press(Gen2Button.A)
	assert_eq(_stage(), "ask")
	assert_true(battle.must_learn_move(Gen2Battle.PLAYER))
	assert_eq(_screen.get("_forget_confirm_cursor"), 0, "YesNoBox reopens on YES")


## A confirm reveals and pages before it answers, so the three paragraphs of
## AskForgetMoveText cannot be skipped past by the press that opens them.
func test_a_confirm_pages_the_prompt_before_answering_it() -> void:
	await _open_with_full_moveset()
	await _advance_to_offer()
	assert_eq(_stage(), "ask")

	var box: Gen2TextBox = _screen.get("_box")
	assert_true(box.advance(), "the prompt still has pages to turn")
	_screen._answer_forget(Gen2Button.A)
	await get_tree().process_frame
	assert_eq(_stage(), "ask", "the press turned a page rather than answering")


## B in the list is ForgetMove's own .cancel, the same carry the ask's no sets.
func test_backing_out_of_the_list_reaches_stop_learning() -> void:
	await _open_with_full_moveset()
	await _advance_to_offer()
	await _press(Gen2Button.A)
	assert_eq(_stage(), "list")

	await _press(Gen2Button.B)
	assert_eq(_stage(), "stop")
