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
## The budget [method _advance_to_a_standing_wait] searches, which is the whole
## script: a wait it can use turns up well before the end of one.
const SEARCH_FRAMES: int = WHOLE_SCRIPT_FRAMES
## One tick for `Credits_HandleBButton` to take and one left standing, so the
## release half measures a wait rather than an empty one.
const STANDING_WAIT: int = 2

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


## [Gen2CreditsScreen] counts hardware frames off wall-clock delta in `_process`,
## which a test that also drives frames by hand cannot account for: one long
## frame on a loaded machine spends an unknown part of the wait the case is about
## to measure. `open_credits` and `_show_script_results` both build the host
## synchronously, so this takes its processing away before the first frame
## passes and the test owns every frame from there.
func _stop_self_advancing() -> void:
	if _host() != null:
		_host().set_process(false)


## Drives frames until the credits sit where the two halves below can each be
## read on their own:
##
## - past the header, which is the only place `Credits_HandleBButton` skips;
## - on a wait deep enough to still be standing after B has taken one, so the
##   release half measures a wait rather than an empty one;
## - and two frames short of the next `STEP_PARSE`, because that step spends a
##   tick of its own and would be indistinguishable from the button.
func _advance_to_a_standing_wait() -> bool:
	for _frame: int in SEARCH_FRAMES:
		if _host() == null or _host().credits() == null:
			return false
		var credits: Gen2Credits = _host().credits()
		if credits.position() >= Gen2Credits.SKIP_FROM_POSITION \
				and credits.timer() >= STANDING_WAIT \
				and not credits.step() in [
					Gen2Credits.STEP_PARSE, Gen2Credits.CYCLE_FRAMES - 1
				]:
			return true
		_host().advance_frames(1)
	return false


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
	_stop_self_advancing()
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
	_stop_self_advancing()
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
	# The overlay advances itself on wall-clock delta, so the test takes every
	# frame off it before the first one passes; see [method _stop_self_advancing].
	_stop_self_advancing()
	await get_tree().process_frame
	assert_true(_advance_to_a_standing_wait(), "the credits reach a skippable wait")

	_world_screen.press_button(Gen2Button.B)
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
