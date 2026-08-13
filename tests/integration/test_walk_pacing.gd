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

## One source VBlank, which is what the step accumulator counts in.
const FRAME: float = 1.0 / 59.7275

var _world: Gen2WorldAPI = null


func before_each() -> void:
	var data: GameData = Fixture.build()
	data = GameData.open_directory(Fixture.directory())
	_world = Gen2WorldAPI.open(
		data, Fixture.MAP_GROUP, Fixture.MAP_NUMBER, Vector2i(2, 2)
	)


func after_each() -> void:
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
		_world.advance_player_step(FRAME)
		assert_true(_world.player_step_in_progress(), "still walking")
	_world.advance_player_step(FRAME)
	assert_false(_world.player_step_in_progress(), "the eighth frame ends it")


## A step queued behind the one running takes over on the frame the first ends,
## so a walk of several cells is eight frames a cell rather than nine.
func test_a_queued_step_starts_on_the_frame_the_last_one_ends() -> void:
	_world._start_player_step(Vector2i(1, 0), _walk_frames())
	_world._queue_player_step(Vector2i(1, 0), _walk_frames())
	for _frame: int in _walk_frames():
		_world.advance_player_step(FRAME)
	assert_true(_world.player_step_in_progress(), "the second step took over")
	for _frame: int in _walk_frames() - 1:
		_world.advance_player_step(FRAME)
		assert_true(_world.player_step_in_progress())
	_world.advance_player_step(FRAME)
	assert_false(_world.player_step_in_progress(), "and cost the same eight")


## The offset the renderer draws the player at closes over the step's own eight
## frames, which is `StepVectors`' two pixels a frame reaching sixteen.
func test_the_offset_covers_one_cell() -> void:
	_world._start_player_step(Vector2i(1, 0), _walk_frames())
	for _frame: int in _walk_frames() - 1:
		_world.advance_player_step(FRAME)
	assert_ne(
		_world.player_step_offset_cells(), Vector2.ZERO,
		"the pic is still short of the cell"
	)
	_world.advance_player_step(FRAME)
	assert_eq(_world.player_step_offset_cells(), Vector2.ZERO, "and lands on it")
