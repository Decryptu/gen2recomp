extends GutTest

## Scene integration for the credits: the overlay `credits` opens, the input it
## blocks while it runs, the two held buttons it reads and the induction that
## ends into it. Driven through the production world screen.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

const PLAYER_CELL: Vector2i = Vector2i(2, 2)
## `Script_credits` is Crystal $a2, one past `halloffame`.
const CREDITS_COMMAND: int = 0xA2
const SCRIPT_ADDRESS: int = 0x7000
## Long enough for the fixture script to reach `CREDITS_END`.
const WHOLE_SCRIPT_FRAMES: int = Gen2Credits.CYCLE_FRAMES * 40

var _data: GameData = null
var _world_screen: Gen2WorldScreen = null


func before_each() -> void:
	Fixture.build()
	_data = GameData.open_directory(Fixture.directory())


func after_each() -> void:
	if is_instance_valid(_world_screen):
		_world_screen.free()
		_world_screen = null
	RomCache.clear(Fixture.directory())


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


func _host() -> Gen2CreditsScreen:
	return _world_screen._credits_host


## `Script_credits` farcalls `RedCredits` and falls into `Script_endall`, so the
## overlay opens off the drained results the way `halloffame`'s does.
func test_the_credits_command_opens_the_overlay() -> void:
	await _open_world()
	var directory: String = Fixture.directory()
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(directory))
	scripts["%d:7000" % Fixture.BANK] = [CREDITS_COMMAND, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(directory), scripts)
	_data = GameData.open_directory(directory)

	var world: Gen2WorldAPI = _world_screen._world
	world.data = _data
	world.current_map.events["coord_events"][0]["script"] = SCRIPT_ADDRESS
	world.player_cell = Vector2i(
		int(world.current_map.events["coord_events"][0]["x"]),
		int(world.current_map.events["coord_events"][0]["y"])
	)
	_world_screen._show_script_results(world.dispatch_script_events())
	await get_tree().process_frame

	assert_not_null(_host())
	assert_false(_host().credits().finished())


## The overlay hides the map, so the overworld must not move under it.
func test_the_overworld_does_not_move_while_the_credits_run() -> void:
	await _open_world()
	_world_screen.open_credits()
	await get_tree().process_frame
	var before: Vector2i = _world_screen._world.player_cell
	assert_false(_world_screen.move_player(Vector2i.DOWN))
	assert_false(_world_screen.interact())
	assert_eq(_world_screen._world.player_cell, before)


## `Credits_HandleAButton` tests JUMPTABLE_EXIT_F first, so A is swallowed until
## the script has run out and then leaves.
func test_a_leaves_only_once_the_script_has_run_out() -> void:
	await _open_world()
	_world_screen.open_credits()
	await get_tree().process_frame
	_world_screen.press_button(Gen2Button.A)
	assert_not_null(_host(), "and the press is still swallowed rather than refused")
	_world_screen._credits_host.release_button(Gen2Button.A)

	_host().advance_frames(WHOLE_SCRIPT_FRAMES)
	assert_true(_host().credits().finished())
	_world_screen.press_button(Gen2Button.A)
	await get_tree().process_frame
	assert_null(_host())
	assert_true(_world_screen.move_player(Vector2i.DOWN))


## Both of `.execution_loop`'s buttons are held states, so the world screen has
## to hand the overlay the release as well as the press.
func test_a_release_reaches_the_overlay() -> void:
	await _open_world()
	_world_screen.open_credits(true)
	await get_tree().process_frame
	_world_screen.press_button(Gen2Button.B)
	## Past the header, which is the only place `Credits_HandleBButton` skips.
	_host().advance_frames(Gen2Credits.CYCLE_FRAMES * 8)
	var skipped: int = _host().credits().timer()
	_host().advance_frames(1)
	assert_lt(_host().credits().timer(), skipped, "B is burning the wait down")

	_host().release_button(Gen2Button.B)
	var standing: int = _host().credits().timer()
	_host().advance_frames(1)
	assert_eq(_host().credits().timer(), standing, "and letting go stops it")


## `HallOfFame` calls `AnimateHallOfFame` and then `farcall Credits`, so the
## induction ends into them; it pushes `wStatusFlags` before setting the Hall of
## Fame bit, so that pair is never skippable.
func test_the_hall_of_fame_runs_into_unskippable_credits() -> void:
	await _open_world()
	_world_screen.open_hall_of_fame()
	await get_tree().process_frame
	while _world_screen._hall_of_fame_host != null:
		_world_screen._hall_of_fame_host.handle_button(Gen2Button.A)
	await get_tree().process_frame
	assert_not_null(_host())
	assert_false(_host().credits().skippable())
