extends GutTest

## Scene integration for `special SlotMachine`, which is the whole line from the
## Game Corner's script to the coins the machine leaves behind.
##
## `SlotMachine` writes `wCoins` itself rather than answering `wScriptVar`, so
## the two things a unit test cannot see are covered here: the machine owns the
## screen while it is up, and the balance it walked reaches the world's own
## state. [Gen2SlotMachine]'s rules are `tests/unit/test_slot_machine.gd` and
## the art is `tools/checks/slots.gd`.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

const PLAYER_CELL: Vector2i = Vector2i(2, 2)
const TALK_CELL: Vector2i = Vector2i(4, 5)
## What the coin case holds when the player sits down.
const COINS: int = 200

var _data: GameData = null
var _world_screen: Gen2WorldScreen = null


func before_each() -> void:
	Fixture.build()
	_write_slots_script()
	_data = GameData.open_directory(Fixture.directory())
	Gen2OptionsStore.use_test_path()
	DirAccess.remove_absolute(Gen2OptionsStore.path())


func after_each() -> void:
	await get_tree().process_frame
	if is_instance_valid(_world_screen):
		_world_screen.free()
		_world_screen = null
	RomCache.clear(Fixture.directory())


## `GoldenrodGameCornerSlotsMachineScript`'s own shape: the `setval` that picks
## the machine, the special, and the `closetext` behind it.
func _write_slots_script() -> void:
	var directory: String = Fixture.directory()
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(directory))
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, Fixture.TUTORIAL_SCRIPT)] = [
		Gen2WorldScript.SETVAL, 0x00,
		Gen2WorldScript.SPECIAL, Gen2WorldScriptRunner.SPECIAL_SLOT_MACHINE, 0x00,
		Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(directory), scripts)


func _open_world() -> void:
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_world_screen = packed.instantiate() as Gen2WorldScreen
	_world_screen.map_group = Fixture.MAP_GROUP
	_world_screen.map_number = Fixture.MAP_NUMBER
	_world_screen.start_cell = PLAYER_CELL
	## `wCoins` is set where the state is built: nothing writes it outside a
	## world transaction, which is the boundary the machine's own result goes
	## through when it closes.
	var state := Gen2WorldState.new({}, {}, {}, {}, COINS)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		_data, Fixture.MAP_GROUP, Fixture.MAP_NUMBER, PLAYER_CELL, state
	)
	var save: Gen2SaveData = Gen2SaveStore.create_development_save(_data, 0)
	save.world = world.snapshot()
	_world_screen.set_data(_data)
	_world_screen.set_save(save)
	add_child(_world_screen)
	await get_tree().process_frame
	## The machine counts hardware frames, so the ones this test spends have to
	## be the ones it asks for.
	_world_screen.set_process(false)


func _run_script() -> void:
	_world_screen._show_script_results(
		_world_screen._world.dispatch_script_events(TALK_CELL)
	)


func _host() -> Gen2SlotMachineScreen:
	return _world_screen._slot_machine_host


## Spends frames until the machine asks for something, which is the bet menu on
## the second pass of `SlotsLoop`.
func _drive_to_prompt(prompt: int, frames: int = 2400) -> bool:
	for _frame: int in frames:
		if _host() == null:
			return false
		if _host().prompt() == prompt:
			return true
		if _host().machine() != null and _host().machine().waiting_for_sfx():
			_host().machine().sfx_finished()
		_host().advance_frame()
		if _host() != null and _host().machine() != null \
			and _host().machine().jumptable_index() in [
				Gen2SlotMachine.SLOTS_WAIT_REEL1, Gen2SlotMachine.SLOTS_WAIT_REEL2,
				Gen2SlotMachine.SLOTS_WAIT_REEL3,
			]:
			_world_screen.press_button(Gen2Button.A)
	return false


func test_the_special_opens_the_machine_and_holds_the_world() -> void:
	await _open_world()
	_run_script()
	assert_not_null(_host(), "the special must open the machine")
	assert_true(_host().visible)
	assert_false(_world_screen.move_player(Vector2i.RIGHT))
	assert_false(_world_screen.interact())


## The bet menu is the machine's, not the world's: a press reaches it and the
## balance it takes is the world's own coins.
func test_the_bet_is_taken_out_of_the_coin_case() -> void:
	await _open_world()
	_run_script()
	assert_true(_drive_to_prompt(Gen2SlotMachine.Prompt.BET), "the menu must open")
	_world_screen.press_button(Gen2Button.A)
	assert_eq(_host().machine().coins(), COINS - 3, "the machine takes three coins")


## B on the bet menu is the quit entry, and what the machine leaves behind is
## what the world's state holds afterwards.
func test_cancelling_closes_the_machine_and_writes_the_coins_back() -> void:
	await _open_world()
	_run_script()
	assert_true(_drive_to_prompt(Gen2SlotMachine.Prompt.BET))
	_world_screen.press_button(Gen2Button.A)
	var spent: int = _host().machine().coins()
	assert_true(_drive_to_prompt(Gen2SlotMachine.Prompt.PRESS), "the spin must end")
	_world_screen.press_button(Gen2Button.A)
	_world_screen.press_button(Gen2Button.B)
	for _frame: int in 240:
		if _host() == null:
			break
		if _host().machine() != null and _host().machine().waiting_for_sfx():
			_host().machine().sfx_finished()
		_host().advance_frame()
	assert_null(_host(), "saying no must close the machine")
	assert_true(
		_world_screen._world.state.coins() >= spent,
		"the balance the machine left must reach the world"
	)


## The world takes its own presses back once the machine has gone.
func test_the_world_moves_again_once_the_machine_closes() -> void:
	await _open_world()
	_run_script()
	assert_true(_drive_to_prompt(Gen2SlotMachine.Prompt.BET))
	_world_screen.press_button(Gen2Button.B)
	for _frame: int in 240:
		if _host() == null:
			break
		if _host().machine() != null and _host().machine().waiting_for_sfx():
			_host().machine().sfx_finished()
		_host().advance_frame()
	assert_null(_host(), "cancelling the bet must close the machine")
	assert_true(_world_screen.move_player(Vector2i.RIGHT))
