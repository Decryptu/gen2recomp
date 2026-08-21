extends GutTest

## `StepVectors`' normal row (`engine/overworld/map_objects.asm`): two pixels a
## pass for eight passes, which is one cell.
##
## A pass is not a frame. `HandleMap` ends every iteration in
## `NextOverworldFrame`, whose `MaxOverworldDelay` is 2, so the whole overworld
## runs once per two hardware frames and an ordinary walk step takes sixteen.
## Measured on a real cartridge, `.claude/oracle/overworld/trace_walk.py` on
## Route 29: `wPlayerStepDuration` counts 7 down to 0 over frames 19 to 34 while
## `wPlayerSpriteX` walks 208 to 224 two pixels at a time, and a hook on
## `HandleMapObjects` fires on every other frame and no other.
##
## The constant on its own is not the question; the pacing around it is. A step
## that costs nine passes because the pass the last one ended on is spent
## starting the next reads as sluggish, and no constant would be wrong. In the
## source it costs eight: `HandleObjectStep`'s `.one` calls
## `StepFunction_FromMovement`, and when that starts a step the step type is no
## longer STEP_TYPE_FROM_MOVEMENT, so the `ret z` is skipped and `.ok3` runs the
## new step function on the same frame. `StepFunction_PlayerWalk`'s `.init`
## falls into `.step`, which moves.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

## Longer than the turn, the step and the fade behind them: the helper below
## drives to a state rather than spending a count.
const WALK_FRAME_CAP: int = 40

var _world: Gen2WorldAPI = null
var _data: GameData = null
var _screen: Gen2WorldScreen = null


func before_each() -> void:
	Fixture.build()
	_data = GameData.open_directory(Fixture.directory())
	_world = Gen2WorldAPI.open(
		_data, Fixture.MAP_GROUP, Fixture.MAP_NUMBER, Vector2i(2, 2)
	)


func after_each() -> void:
	if is_instance_valid(_screen):
		_screen.free()
		_screen = null
	RomCache.clear(Fixture.directory())


func _walk_frames() -> int:
	return Gen2WorldAPI.STEP_PASSES_WALK


## The screen's own frames for a count of overworld passes. `HandleMap` runs one
## pass per `NextOverworldFrame`, and `MaxOverworldDelay` is 2, so a duration
## read off `InitStep` or off `wLandmarkSignTimer` costs twice its number of
## frames. Measured on a real cartridge with
## `.claude/oracle/overworld/trace_walk.py`.
func _screen_frames(passes: int) -> int:
	return passes * Gen2WorldAPI.FRAMES_PER_OVERWORLD_PASS


func _walk_screen_frames() -> int:
	return _screen_frames(Gen2WorldAPI.STEP_PASSES_WALK)


func _turn_screen_frames() -> int:
	return _screen_frames(Gen2WorldAPI.STEP_PASSES_TURN)


## `MaxOverworldDelay`, which is what makes every row below a pass rather than a
## frame.
func test_the_overworld_runs_one_pass_per_two_hardware_frames() -> void:
	assert_eq(Gen2WorldAPI.FRAMES_PER_OVERWORLD_PASS, 2)


## The cartridge's own sixteen, measured between two landings so the count does
## not depend on which frame the press arrived on: a direction held through the
## pump walks a cell every FRAMES_PER_OVERWORLD_PASS * STEP_PASSES_WALK frames.
## This is the case the pinned trace is for, and the one that fails on a port
## that spends a pass per frame.
func test_a_held_walk_covers_a_cell_every_sixteen_hardware_frames() -> void:
	## Three cells clear of any warp or wall, walked west across the fixture.
	_screen = await _screen_at(Fixture.WARP_CELL + Vector2i.DOWN)
	var landings: Array[int] = []
	var cell: Vector2i = _screen._world.player_cell
	for frame: int in _walk_screen_frames() * 4:
		## `move_player` refuses while a step is in flight, so pressing every
		## frame is the held direction `_advance_held_direction` polls.
		_screen.move_left()
		_screen.advance_frame()
		if _screen._world.player_cell != cell:
			cell = _screen._world.player_cell
			landings.append(frame)
		if landings.size() >= 3:
			break
	assert_eq(landings.size(), 3, "three cells walked")
	assert_eq(
		landings[1] - landings[0], _walk_screen_frames(),
		"one cell per sixteen hardware frames"
	)
	assert_eq(landings[2] - landings[1], _walk_screen_frames())


## `StepVectors`' own three rows, which is where every duration in
## [Gen2WorldAPI] comes from.
func test_the_step_durations_are_the_source_rows() -> void:
	assert_eq(Gen2WorldAPI.STEP_PASSES_NPC_WALK, 16, "the slow row")
	assert_eq(Gen2WorldAPI.STEP_PASSES_WALK, 8, "the normal row")
	assert_eq(Gen2WorldAPI.STEP_PASSES_FAST, 4, "the fast row")
	# `StepFunction_Turn` is two frames standing and two on the new facing.
	assert_eq(Gen2WorldAPI.STEP_PASSES_TURN, 4)


## Eight passes, no more: the eighth is the one that ends it.
func test_a_walk_step_costs_exactly_eight_passes() -> void:
	_world._start_player_step(Vector2i(1, 0), _walk_frames())
	for _frame: int in _walk_frames() - 1:
		_world.advance_player_step_pass()
		assert_true(_world.player_step_in_progress(), "still walking")
	_world.advance_player_step_pass()
	assert_false(_world.player_step_in_progress(), "the eighth pass ends it")


## A step queued behind the one running takes over on the pass the first ends,
## so a walk of several cells is eight passes a cell rather than nine.
func test_a_queued_step_starts_on_the_frame_the_last_one_ends() -> void:
	_world._start_player_step(Vector2i(1, 0), _walk_frames())
	_world._queue_player_step(Vector2i(1, 0), _walk_frames())
	for _frame: int in _walk_frames():
		_world.advance_player_step_pass()
	assert_true(_world.player_step_in_progress(), "the second step took over")
	for _frame: int in _walk_frames() - 1:
		_world.advance_player_step_pass()
		assert_true(_world.player_step_in_progress())
	_world.advance_player_step_pass()
	assert_false(_world.player_step_in_progress(), "and cost the same eight")


## The offset the renderer draws the player at closes over the step's own eight
## passes, which is `StepVectors`' two pixels a pass reaching sixteen.
func test_the_offset_covers_one_cell() -> void:
	_world._start_player_step(Vector2i(1, 0), _walk_frames())
	for _frame: int in _walk_frames() - 1:
		_world.advance_player_step_pass()
	assert_ne(
		_world.player_step_offset_cells(), Vector2.ZERO,
		"the pic is still short of the cell"
	)
	_world.advance_player_step_pass()
	assert_eq(_world.player_step_offset_cells(), Vector2.ZERO, "and lands on it")


## The production screen on the fixture's map, walked up onto the door and
## stopped on the frame `WarpToNewMapScript` starts, which is the frame the step
## onto the warp tile landed on and no fade frame has been spent yet. Its own clock is taken away, so every frame after
## that is spent by hand.
func _walk_onto_the_door() -> Gen2WorldScreen:
	var screen: Gen2WorldScreen = await _screen_below_the_door()
	for _frame: int in WALK_FRAME_CAP:
		## One press turns and the next steps, and a press inside the fade is
		## swallowed, so the same call drives all three.
		screen.move_up()
		screen.advance_frame()
		if not screen.map_fade().is_empty():
			break
	return screen


func _screen_below_the_door() -> Gen2WorldScreen:
	return await _screen_at(Fixture.WARP_CELL + Vector2i.DOWN)


func _screen_at(start: Vector2i) -> Gen2WorldScreen:
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	var screen: Gen2WorldScreen = packed.instantiate() as Gen2WorldScreen
	screen.map_group = Fixture.MAP_GROUP
	screen.map_number = Fixture.MAP_NUMBER
	screen.start_cell = start
	screen.encounter_seed = 1
	screen.set_data(_data)
	add_child(screen)
	await get_tree().process_frame
	screen.set_process(false)
	screen._frame_elapsed = 0.0
	return screen


## `CheckPlayerState` turns `wMapEventStatus` on where the step function set
## `PLAYERSTEP_STOP_F`, so `PlayerEvents` and everything under it, the warp, the
## coord events and the wild roll, run on the frame the step lands rather than on
## the frame the button was read.
func test_a_warp_waits_for_the_step_onto_its_tile_to_land() -> void:
	_screen = await _screen_below_the_door()
	_screen.move_up()   # `.CheckTurning`: the first press only turns.
	for _frame: int in _turn_screen_frames():
		_screen.advance_frame()
	_screen.move_up()
	assert_true(_screen._world.player_step_in_progress(), "the step onto the door started")
	## Driven to the landing rather than counted: which of the two frames of a
	## pass the press arrived on decides whether the step's first pass is this
	## frame or the next, and neither is the thing under test.
	var frames: int = 0
	while _screen._world.player_step_in_progress() and frames < WALK_FRAME_CAP:
		assert_true(
			_screen.map_fade().is_empty(),
			"no warp while the player is still between the two cells",
		)
		_screen.advance_frame()
		frames += 1
	assert_false(_screen._world.player_step_in_progress(), "the step landed")
	assert_gt(frames, _walk_screen_frames() - Gen2WorldAPI.FRAMES_PER_OVERWORLD_PASS,
		"and cost a pass short of sixteen frames at worst")
	assert_false(_screen.map_fade().is_empty(), "and the warp is taken on that frame")


## `WarpToNewMapScript` is `warpsound` and `newloadmap MAPSETUP_DOOR`, and that
## setup script spends frames before the map is loaded and after: four palette
## orders of `FadeOutToWhite`, two frames each, then the load, then the four of
## `FadeInFromWhite`. A warp that swapped the map on the frame the step landed
## on is what puts the same input on a different frame from the cartridge's.
func test_a_warp_spends_the_setup_script_own_fade() -> void:
	_screen = await _walk_onto_the_door()
	assert_eq(_screen._world.player_cell, Fixture.WARP_CELL, "the step landed on it")
	assert_eq(
		_screen._world.map_id(), Vector2i(Fixture.MAP_GROUP, Fixture.MAP_NUMBER),
		"and the map has not swapped: `FadeOutToWhite` runs first"
	)
	assert_eq(StringName(_screen.map_fade().get("stage", &"")), &"out")
	var fade_frames: int = Gen2WorldPalette.FADE_OUT_ORDERS.size() \
		* Gen2WorldPalette.FADE_STEP_FRAMES
	## `PlayerEvents` runs after the frame's own map background, so the frame the
	## step landed on starts the script and spends none of its fade.
	var out_frames: int = 0
	while StringName(_screen.map_fade().get("stage", &"")) == &"out" \
		and out_frames < WALK_FRAME_CAP:
		_screen.advance_frame()
		out_frames += 1
	assert_eq(out_frames, fade_frames, "`FadeOutToWhite` is four orders of two frames")
	assert_eq(
		_screen._world.map_id(),
		Vector2i(Gen2WorldSpawn.NEW_BARK_GROUP, Gen2WorldSpawn.PLAYERS_HOUSE_2F),
		"the map is loaded when the fade out lands"
	)
	assert_eq(
		StringName(_screen.map_fade().get("stage", &"")), &"in",
		"and `FadeInFromWhite` is what the new map arrives behind"
	)
	var in_frames: int = 0
	while not _screen.map_fade().is_empty() and in_frames < WALK_FRAME_CAP:
		_screen.advance_frame()
		in_frames += 1
	assert_eq(in_frames, fade_frames, "and the way back in is the same four")


## `RunMapSetupScript` runs with the joypad unread, so nothing the player does
## inside those sixteen frames moves anything.
func test_no_input_is_taken_while_the_warp_fade_runs() -> void:
	_screen = await _walk_onto_the_door()
	assert_false(_screen.map_fade().is_empty(), "the fade is up")
	var cell: Vector2i = _screen._world.player_cell
	assert_false(_screen.move_player(Vector2i.DOWN), "no step is taken")
	assert_true(_screen.press_button(Gen2Button.A), "and A is swallowed rather than used")
	assert_eq(_screen._world.player_cell, cell)


## `InitMapNameSign` sits inside the same setup script: the warp crosses from the
## map's own landmark into the house's, so a sign is raised, and
## `PlaceMapNameSign` counts `wLandmarkSignTimer`'s sixty passes down behind it.
func test_a_warp_into_another_landmark_raises_the_map_name_sign() -> void:
	_screen = await _walk_onto_the_door()
	assert_eq(_screen.map_name_sign_passes(), 0, "nothing is up while the fade runs")
	for _frame: int in WALK_FRAME_CAP:
		_screen.advance_frame()
		if _screen.map_name_sign_passes() > 0:
			break
	assert_eq(
		_screen.map_name_sign_passes(), Gen2WorldAPI.MAP_NAME_SIGN_PASSES,
		"the sign is raised once the map is loaded, with all sixty passes to spend"
	)
	for _frame: int in _screen_frames(Gen2WorldAPI.MAP_NAME_SIGN_PASSES) - 1:
		_screen.advance_frame()
	assert_eq(_screen.map_name_sign_passes(), 1, "still up on its last pass")
	_screen.advance_frame()
	assert_eq(_screen.map_name_sign_passes(), 0, "and gone on the sixtieth")


## `PlayerEvents` zeroes `wLandmarkSignTimer` behind `DoPlayerEvent`, so only a
## dispatched player event takes the sign down. A map's own callbacks are
## `RunMapCallback`'s work inside map setup and reach `PlayerEvents` never: one
## sitting on the queue used to take down the sign that same map load raised,
## which is every connection crossing into a map that has one.
func test_a_queued_map_callback_does_not_take_the_sign_down() -> void:
	_screen = await _walk_onto_the_door()
	for _frame: int in WALK_FRAME_CAP:
		_screen.advance_frame()
		if _screen.map_name_sign_passes() > 0:
			break
	assert_eq(_screen.map_name_sign_passes(), Gen2WorldAPI.MAP_NAME_SIGN_PASSES)
	## The fixture's house has no callback of its own, so one stands on the
	## queue directly: what is under test is that a waiting script is not what
	## takes the sign down, whatever put it there.
	_screen._world._script_queue.append({})
	assert_true(_screen._world.script_busy(), "a callback is waiting to run")
	for _frame: int in Gen2WorldAPI.FRAMES_PER_OVERWORLD_PASS:
		_screen.advance_frame()
	assert_eq(
		_screen.map_name_sign_passes(), Gen2WorldAPI.MAP_NAME_SIGN_PASSES - 1,
		"and the sign spent that pass rather than being taken down"
	)


## And a callback that has actually run does not take it down either, which is
## the other half: `RunMapCallback` is map setup, and `RunSceneScript` answers
## `PlayerEvents` with carry only when its scene script set RUN_DEFERRED_SCRIPT.
## Route 29's two scene scripts are bare `end`s, so crossing New Bark's west edge
## used to lose the sign seven frames in.
func test_only_a_player_event_result_takes_the_sign_down() -> void:
	_screen = await _walk_onto_the_door()
	for _frame: int in WALK_FRAME_CAP:
		_screen.advance_frame()
		if _screen.map_name_sign_passes() > 0:
			break
	var raised: int = _screen.map_name_sign_passes()
	assert_eq(raised, Gen2WorldAPI.MAP_NAME_SIGN_PASSES)

	_screen._zero_map_name_sign_for([{"source": {"kind": &"callback"}}])
	assert_eq(_screen.map_name_sign_passes(), raised, "a map callback raises no event")

	_screen._zero_map_name_sign_for([{"source": {"kind": &"scene"}, "deferred": false}])
	assert_eq(_screen.map_name_sign_passes(), raised, "and nor does a scene of bare ends")

	_screen._zero_map_name_sign_for([{"source": {"kind": &"scene"}, "deferred": true}])
	assert_eq(_screen.map_name_sign_passes(), 0, "an `sdefer` is the carry that does")


## `.CheckMovingWithinLandmark`: the map the world opens on is `wPrevLandmark`,
## so walking back into the landmark just left raises nothing.
func test_a_warp_back_into_the_same_landmark_raises_no_sign() -> void:
	assert_eq(_world.map_name_sign_pending(), -1, "opening a world raises none")
	var home: Gen2WorldMap = _data.world_map(
		Gen2WorldSpawn.NEW_BARK_GROUP, Gen2WorldSpawn.PLAYERS_HOUSE_2F
	)
	_world._apply_map(
		_data.world_map(Fixture.MAP_GROUP, Fixture.MAP_NUMBER),
		_world.current_tileset, Vector2i(2, 2)
	)
	assert_eq(_world.map_name_sign_pending(), -1, "the same landmark, so no sign")
	_world._apply_map(home, _data.world_tileset(home.tileset), Vector2i(1, 1))
	assert_eq(
		_world.map_name_sign_pending(), Fixture.HOME_MAP_LANDMARK,
		"and the house's own landmark is what the sign names"
	)
