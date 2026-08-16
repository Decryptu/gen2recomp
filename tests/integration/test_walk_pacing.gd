extends GutTest

## `StepVectors`' normal row (`engine/overworld/map_objects.asm`): two pixels a
## frame for eight frames, which is one cell.
##
## The constant on its own is not the question; the pacing around it is. A step
## that costs nine frames because the frame the last one ended on is spent
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
	return Gen2WorldAPI.STEP_FRAMES_WALK


## `StepVectors`' own three rows, which is where every duration in
## [Gen2WorldAPI] comes from.
func test_the_step_durations_are_the_source_rows() -> void:
	assert_eq(Gen2WorldAPI.STEP_FRAMES_NPC_WALK, 16, "the slow row")
	assert_eq(Gen2WorldAPI.STEP_FRAMES_WALK, 8, "the normal row")
	assert_eq(Gen2WorldAPI.STEP_FRAMES_FAST, 4, "the fast row")
	# `StepFunction_Turn` is two frames standing and two on the new facing.
	assert_eq(Gen2WorldAPI.STEP_FRAMES_TURN, 4)


## Eight frames, no more: the eighth is the one that ends it.
func test_a_walk_step_costs_exactly_eight_frames() -> void:
	_world._start_player_step(Vector2i(1, 0), _walk_frames())
	for _frame: int in _walk_frames() - 1:
		_world.advance_player_step_frame()
		assert_true(_world.player_step_in_progress(), "still walking")
	_world.advance_player_step_frame()
	assert_false(_world.player_step_in_progress(), "the eighth frame ends it")


## A step queued behind the one running takes over on the frame the first ends,
## so a walk of several cells is eight frames a cell rather than nine.
func test_a_queued_step_starts_on_the_frame_the_last_one_ends() -> void:
	_world._start_player_step(Vector2i(1, 0), _walk_frames())
	_world._queue_player_step(Vector2i(1, 0), _walk_frames())
	for _frame: int in _walk_frames():
		_world.advance_player_step_frame()
	assert_true(_world.player_step_in_progress(), "the second step took over")
	for _frame: int in _walk_frames() - 1:
		_world.advance_player_step_frame()
		assert_true(_world.player_step_in_progress())
	_world.advance_player_step_frame()
	assert_false(_world.player_step_in_progress(), "and cost the same eight")


## The offset the renderer draws the player at closes over the step's own eight
## frames, which is `StepVectors`' two pixels a frame reaching sixteen.
func test_the_offset_covers_one_cell() -> void:
	_world._start_player_step(Vector2i(1, 0), _walk_frames())
	for _frame: int in _walk_frames() - 1:
		_world.advance_player_step_frame()
	assert_ne(
		_world.player_step_offset_cells(), Vector2.ZERO,
		"the pic is still short of the cell"
	)
	_world.advance_player_step_frame()
	assert_eq(_world.player_step_offset_cells(), Vector2.ZERO, "and lands on it")


## The production screen on the fixture's map, walked up onto the door and
## stopped on the frame `WarpToNewMapScript` starts, which is the frame the step
## onto the warp tile landed on and no fade frame has been spent yet. Its own clock is taken away, so every frame after
## that is spent by hand.
func _walk_onto_the_door() -> Gen2WorldScreen:
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	var screen: Gen2WorldScreen = packed.instantiate() as Gen2WorldScreen
	screen.map_group = Fixture.MAP_GROUP
	screen.map_number = Fixture.MAP_NUMBER
	screen.start_cell = Fixture.WARP_CELL + Vector2i.DOWN
	screen.encounter_seed = 1
	screen.set_data(_data)
	add_child(screen)
	await get_tree().process_frame
	screen.set_process(false)
	screen._frame_elapsed = 0.0
	for _frame: int in WALK_FRAME_CAP:
		## One press turns and the next steps, and a press inside the fade is
		## swallowed, so the same call drives all three.
		screen.move_up()
		screen.advance_frame()
		if not screen.map_fade().is_empty():
			break
	return screen


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
	## One of the fade out's own frames is the frame the step landed on, which is
	## the one the fade was started in.
	var out_frames: int = 1
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
## `PlaceMapNameSign` counts `wLandmarkSignTimer`'s sixty frames down behind it.
func test_a_warp_into_another_landmark_raises_the_map_name_sign() -> void:
	_screen = await _walk_onto_the_door()
	assert_eq(_screen.map_name_sign_frames(), 0, "nothing is up while the fade runs")
	for _frame: int in WALK_FRAME_CAP:
		_screen.advance_frame()
		if _screen.map_name_sign_frames() > 0:
			break
	assert_eq(
		_screen.map_name_sign_frames(), Gen2WorldAPI.MAP_NAME_SIGN_FRAMES,
		"the sign is raised once the map is loaded, with all sixty frames to spend"
	)
	for _frame: int in Gen2WorldAPI.MAP_NAME_SIGN_FRAMES - 1:
		_screen.advance_frame()
	assert_eq(_screen.map_name_sign_frames(), 1, "still up on its last frame")
	_screen.advance_frame()
	assert_eq(_screen.map_name_sign_frames(), 0, "and gone on the sixtieth")


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
