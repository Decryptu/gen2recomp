extends GutTest

## Scene integration for `special UnownPuzzle`, which is the whole line from the
## chamber's script to the `iftrue` it branches on.
##
## `UnownPuzzle` is `FadeToMenu`, the board, and then
## `ld a, [wSolvedUnownPuzzle] / ld [wScriptVar], a`, so the two things a unit
## test cannot see are covered here: the board owns the screen while it is up,
## and what it answers reaches the script. [Gen2UnownPuzzle]'s own rules are
## `tests/unit/test_unown_puzzle.gd` and the art is
## `tools/checks/unown_puzzle.gd`.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

const PLAYER_CELL: Vector2i = Vector2i(2, 2)
const TALK_CELL: Vector2i = Vector2i(4, 5)

## `UNOWNPUZZLE_AERODACTYL`, so the picture is not the first the table holds.
const PUZZLE: int = 2

var _data: GameData = null
var _world_screen: Gen2WorldScreen = null


func before_each() -> void:
	Fixture.build()
	_write_puzzle_script()
	_data = GameData.open_directory(Fixture.directory())
	Gen2OptionsStore.use_test_path()
	DirAccess.remove_absolute(Gen2OptionsStore.path())


func after_each() -> void:
	await get_tree().process_frame
	if is_instance_valid(_world_screen):
		_world_screen.free()
		_world_screen = null
	RomCache.clear(Fixture.directory())


## `RuinsOfAlphKabutoChamberPuzzle`'s own shape: `setval`, the special, and an
## `iftrue` whose branch is the only thing that says what the board answered.
## The branch sets an event, which is what the chamber does with it.
const SOLVED_SCRIPT: int = 0x6190
const SOLVED_EVENT: int = 0x123


func _write_puzzle_script() -> void:
	var directory: String = Fixture.directory()
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(directory))
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, Fixture.TUTORIAL_SCRIPT)] = [
		Gen2WorldScript.SETVAL, PUZZLE,
		Gen2WorldScript.SPECIAL, Gen2WorldScriptRunner.SPECIAL_UNOWN_PUZZLE, 0x00,
		Gen2WorldScript.IFTRUE, SOLVED_SCRIPT & 0xFF, SOLVED_SCRIPT >> 8,
		Gen2WorldScript.END,
	]
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, SOLVED_SCRIPT)] = [
		Gen2WorldScript.SETEVENT, SOLVED_EVENT & 0xFF, SOLVED_EVENT >> 8,
		Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(directory), scripts)


func _open_world() -> void:
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_world_screen = packed.instantiate() as Gen2WorldScreen
	_world_screen.map_group = Fixture.MAP_GROUP
	_world_screen.map_number = Fixture.MAP_NUMBER
	_world_screen.start_cell = PLAYER_CELL
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		_data, Fixture.MAP_GROUP, Fixture.MAP_NUMBER, PLAYER_CELL, Gen2WorldState.new()
	)
	var save: Gen2SaveData = Gen2SaveStore.create_development_save(_data, 0)
	save.world = world.snapshot()
	_world_screen.set_data(_data)
	_world_screen.set_save(save)
	add_child(_world_screen)
	await get_tree().process_frame
	## The board counts hardware frames, so the ones this test spends have to be
	## the ones it asks for.
	_world_screen.set_process(false)


func _run_script() -> void:
	_world_screen._show_script_results(
		_world_screen._world.dispatch_script_events(TALK_CELL)
	)


func _host() -> Gen2UnownPuzzleScreen:
	return _world_screen._unown_puzzle_host


func test_the_special_opens_the_board_and_holds_the_world() -> void:
	await _open_world()
	_run_script()
	assert_not_null(_host(), "the special must open the board")
	assert_true(_host().visible)
	assert_false(_world_screen.move_player(Vector2i.RIGHT))
	assert_false(_world_screen.interact())


## The `setval` in front of the special is which picture, and nothing else picks
## one: a board opened for Aerodactyl draws Aerodactyl's own tiles.
func test_the_setval_in_front_of_it_picks_the_picture() -> void:
	await _open_world()
	_run_script()
	var page: Gen2UnownPuzzlePage = _host().page()
	assert_not_null(page)
	var wanted: PackedByteArray = _data.unown_puzzle_indices(
		RomLayout.UNOWN_PUZZLE_PICTURES[PUZZLE]
	)
	## The fixture fills each picture with its own index, so the doubled bank's
	## first pixel says which strip it was built from. The border is ORed onto
	## that tile, so the centre of a piece is what carries the strip alone.
	var centre: PackedByteArray = page.tile_indices(
		Gen2UnownPuzzlePage.piece_corner_tile(1) + 0x0D
	)
	assert_eq(int(centre[0]), int(wanted[0]))


## START is `UnownPuzzle_Quit`, which leaves `wSolvedUnownPuzzle` at the zero
## `_UnownPuzzle` cleared it to, so the script's own `iftrue` does not branch.
func test_start_closes_the_board_and_answers_the_script_zero() -> void:
	await _open_world()
	_run_script()
	_world_screen.press_button(Gen2Button.START)
	assert_null(_host(), "START must close the board")
	assert_false(
		_world_screen._world.state.is_event_flag_active(SOLVED_EVENT),
		"an unsolved board must not take the `iftrue`"
	)


## The world takes its own presses back once the board has gone.
func test_the_world_moves_again_once_the_board_closes() -> void:
	await _open_world()
	_run_script()
	_world_screen.press_button(Gen2Button.START)
	assert_true(_world_screen.move_player(Vector2i.RIGHT))
