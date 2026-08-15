extends GutTest

## Object state tests use the same signed hour and time-of-day conventions as
## the cartridge event loader, without requiring a scene or imported cache.


func _object(movement: int = Gen2WorldObject.MOVEMENT_STILL) -> Gen2WorldObject:
	return Gen2WorldObject.from_event(2, {
		"sprite": 1, "x": 5, "y": 6, "movement": movement,
		"x_radius": 2, "y_radius": 1,
		"hour_1": 6, "hour_2": 18, "palette": 8,
	})


func test_time_of_day_mask_uses_the_source_bits() -> void:
	var object: Gen2WorldObject = Gen2WorldObject.from_event(0, {
		"hour_1": -1, "hour_2": 2,
	})
	assert_false(object.visible_at(6, Gen2WorldPalette.TIME_MORNING))
	assert_true(object.visible_at(12, Gen2WorldPalette.TIME_DAY))
	assert_false(object.visible_at(22, Gen2WorldPalette.TIME_NIGHT))


func test_ff_event_flag_is_the_source_always_visible_sentinel() -> void:
	var object: Gen2WorldObject = Gen2WorldObject.from_event(0, {
		"event_flag": 0xFFFF,
	})
	var state := Gen2WorldState.new({65535: true})
	assert_eq(object.event_flag, -1)
	assert_true(object.visible_with_state(6, Gen2WorldPalette.TIME_MORNING, state))


func test_hour_ranges_include_endpoints_and_wrap_midnight() -> void:
	var object: Gen2WorldObject = _object()
	assert_true(object.visible_at(6, Gen2WorldPalette.TIME_MORNING))
	assert_true(object.visible_at(18, Gen2WorldPalette.TIME_NIGHT))
	assert_false(object.visible_at(5, Gen2WorldPalette.TIME_MORNING))

	object.hour_1 = 22
	object.hour_2 = 2
	assert_true(object.visible_at(23, Gen2WorldPalette.TIME_NIGHT))
	assert_true(object.visible_at(2, Gen2WorldPalette.TIME_NIGHT))
	assert_false(object.visible_at(12, Gen2WorldPalette.TIME_DAY))


func test_movement_template_initial_facing_and_bounds_are_data_driven() -> void:
	var object: Gen2WorldObject = _object(Gen2WorldObject.MOVEMENT_FIXED_LEFT)
	assert_eq(object.facing, Gen2WorldSprite.FACING_LEFT)
	assert_true(object.can_leave_to(Vector2i(3, 5)))
	assert_false(object.can_leave_to(Vector2i(2, 5)))


func test_random_wander_stays_cardinal() -> void:
	var object: Gen2WorldObject = _object(Gen2WorldObject.MOVEMENT_WANDER)
	var random := RandomNumberGenerator.new()
	random.seed = 1234
	var direction: Vector2i = object.next_direction(random)
	assert_eq(abs(direction.x) + abs(direction.y), 1)


func test_step_offset_starts_a_full_cell_behind_and_reaches_zero() -> void:
	var object: Gen2WorldObject = _object()
	assert_false(object.is_stepping())
	assert_eq(object.step_offset(16), Vector2i.ZERO)

	object.start_step(Vector2i.RIGHT, 8)
	assert_true(object.is_stepping())
	# A step's destination cell is already committed; the offset starts a
	# full cell behind it and eases toward zero, never overshooting.
	assert_eq(object.step_offset(16), Vector2i(-16, 0))

	for _frame: int in 8:
		assert_true(object.tick_step())
	assert_eq(object.step_offset(16), Vector2i.ZERO)
	assert_false(object.is_stepping())
	assert_false(object.tick_step())


func test_a_queued_stream_is_drawn_a_step_at_a_time_in_stream_order() -> void:
	var object: Gen2WorldObject = _object()
	object.queue_step(Vector2i.RIGHT, 8)
	object.queue_step(Vector2i.DOWN, 8)
	assert_true(object.scripted_steps)
	# Both cells committed when the stream applied, so the drawing starts two
	# steps behind, and it walks them in the order the stream named them.
	assert_eq(object.step_offset_cells(), Vector2(-1.0, -1.0))

	for _frame: int in 8:
		assert_true(object.tick_step())
	assert_eq(object.step_offset_cells(), Vector2(0.0, -1.0), "the right step is drawn")

	for _frame: int in 4:
		assert_true(object.tick_step())
	assert_eq(object.step_offset_cells(), Vector2(0.0, -0.5))

	for _frame: int in 4:
		assert_true(object.tick_step())
	assert_eq(object.step_offset_cells(), Vector2.ZERO)
	assert_false(object.scripted_steps)
	assert_false(object.tick_step())


## An ordinary step supersedes a trail rather than joining it: the two never
## overlap on the cartridge either, since a scripted movement owns the object
## until its stream ends.
func test_an_ordinary_step_replaces_a_queued_stream() -> void:
	var object: Gen2WorldObject = _object()
	object.queue_step(Vector2i.RIGHT, 8)
	object.queue_step(Vector2i.RIGHT, 8)
	object.start_step(Vector2i.LEFT, 8)
	assert_false(object.scripted_steps)
	assert_eq(object.step_offset_cells(), Vector2(1.0, 0.0))


## SetFacingStepAction increments OBJECT_STEP_FRAME once per frame of a step and
## the drawing is its two high bits, so it changes every four frames and frames
## 1 and 3 are the two walking pictures.
func test_the_walk_frame_changes_every_four_frames_of_a_step() -> void:
	var object: Gen2WorldObject = _object()
	assert_eq(object.walk_frame(), 0)
	object.start_step(Vector2i.RIGHT, 16)

	for _frame: int in 4:
		object.tick_step()
	assert_eq(object.walk_frame(), 1)
	assert_eq(object.frame, 1, "and the drawn frame follows the counter")

	for _frame: int in 4:
		object.tick_step()
	assert_eq(object.walk_frame(), 2)

	for _frame: int in 8:
		object.tick_step()
	# Sixteen frames is one full cycle, so a slow step both starts and ends on
	# the standing picture without anything having to clear the counter.
	assert_eq(object.walk_frame(), 0)


func test_step_offset_direction_matches_the_committed_movement() -> void:
	var object: Gen2WorldObject = _object()
	object.start_step(Vector2i.UP, 16)
	object.tick_step()
	# One of sixteen slow-step frames consumed: 15/16 of a cell remains
	# behind the committed cell, in the direction moved away from.
	assert_eq(object.step_offset(16), Vector2i(0, 15))

	object.start_step(Vector2i.LEFT, 4)
	assert_eq(object.step_offset(4), Vector2i(4, 0))


func test_fractional_step_offset_matches_the_pixel_offset() -> void:
	var object: Gen2WorldObject = _object()
	assert_eq(object.step_offset_cells(), Vector2.ZERO)

	object.start_step(Vector2i.RIGHT, 16)
	assert_eq(object.step_offset_cells(), Vector2(-1.0, 0.0))
	# A renderer working in cells and one working in pixels must place the
	# same sprite in the same place at every frame of the step.
	for frame: int in 16:
		var cells: Vector2 = object.step_offset_cells()
		assert_eq(object.step_offset(16), Vector2i(roundi(cells.x * 16.0), roundi(cells.y * 16.0)))
		assert_true(object.tick_step(), "frame %d should still be in flight" % frame)
	assert_eq(object.step_offset_cells(), Vector2.ZERO)


func test_idle_frames_are_consumed_one_at_a_time() -> void:
	var object: Gen2WorldObject = _object(Gen2WorldObject.MOVEMENT_WANDER)
	assert_false(object.is_idle())
	assert_false(object.tick_idle())

	object.start_idle(3)
	assert_true(object.is_idle())
	for _frame: int in 3:
		assert_true(object.tick_idle())
	assert_false(object.is_idle())
	assert_false(object.tick_idle())


func test_only_deciding_templates_advance_on_their_own() -> void:
	# The standing and fixed-facing rows resolve once in the source, so a
	# per-frame driver must not keep asking them for a decision.
	for movement: int in [
		Gen2WorldObject.MOVEMENT_WANDER, Gen2WorldObject.MOVEMENT_WALK_UP_DOWN,
		Gen2WorldObject.MOVEMENT_WALK_LEFT_RIGHT, Gen2WorldObject.MOVEMENT_SWIM_WANDER,
		Gen2WorldObject.MOVEMENT_SPINRANDOM_SLOW, Gen2WorldObject.MOVEMENT_SPINRANDOM_FAST,
	]:
		assert_true(_object(movement).movement_advances(), "movement %d advances" % movement)
	for movement: int in [
		Gen2WorldObject.MOVEMENT_STILL, Gen2WorldObject.MOVEMENT_FIXED_DOWN,
		Gen2WorldObject.MOVEMENT_FIXED_UP, Gen2WorldObject.MOVEMENT_FIXED_LEFT,
		Gen2WorldObject.MOVEMENT_FIXED_RIGHT,
		Gen2WorldObject.MOVEMENT_STRENGTH_BOULDER,
	]:
		assert_false(_object(movement).movement_advances(), "movement %d stands" % movement)


## SPRITEMOVEDATA_STRENGTH_BOULDER is $19, and the constants file's comment
## column is hex: reading it as decimal 19 would collide with
## SPRITEMOVEDATA_FOLLOWING. A boulder reacts to a push and decides nothing on
## its own, so it stays out of both template sets.
func test_strength_boulder_is_a_hex_template_that_never_decides() -> void:
	assert_eq(Gen2WorldObject.MOVEMENT_STRENGTH_BOULDER, 0x19)
	assert_ne(Gen2WorldObject.MOVEMENT_STRENGTH_BOULDER, Gen2WorldObject.MOVEMENT_FOLLOW)
	var boulder: Gen2WorldObject = _object(Gen2WorldObject.MOVEMENT_STRENGTH_BOULDER)
	assert_true(boulder.is_strength_boulder())
	assert_false(boulder.movement_supported())
	assert_false(boulder.movement_advances())
	assert_eq(boulder.next_direction(RandomNumberGenerator.new()), Vector2i.ZERO)
	for movement: int in [
		Gen2WorldObject.MOVEMENT_STILL, Gen2WorldObject.MOVEMENT_FOLLOW,
		Gen2WorldObject.MOVEMENT_WANDER,
	]:
		assert_false(
			_object(movement).is_strength_boulder(), "movement %d is not a boulder" % movement
		)


## TryRockSmashFromMenu's whole test after GetFacingObject: the faced object's
## MAPOBJECT_MOVEMENT byte against SPRITEMOVEDATA_SMASHABLE_ROCK. The boulder
## is the row directly after it, so the two must not be confused.
func test_a_smashable_rock_is_answered_by_its_movement_byte() -> void:
	assert_eq(Gen2WorldObject.MOVEMENT_SMASHABLE_ROCK, 0x18)
	assert_true(_object(Gen2WorldObject.MOVEMENT_SMASHABLE_ROCK).is_smashable_rock())
	assert_false(_object(Gen2WorldObject.MOVEMENT_STRENGTH_BOULDER).is_smashable_rock())
	assert_false(_object(Gen2WorldObject.MOVEMENT_SMASHABLE_ROCK).is_strength_boulder())
	assert_false(_object().is_smashable_rock())
	# The rock's own row carries no palette flag, so it is none of the three
	# questions the palette bits answer.
	assert_false(_object(Gen2WorldObject.MOVEMENT_SMASHABLE_ROCK).is_big_object())
	assert_false(_object(Gen2WorldObject.MOVEMENT_SMASHABLE_ROCK).is_swimming())


## A rock decides nothing on its own, exactly like the boulder: it is in neither
## template set, so no per-frame driver ever asks it to move.
func test_a_smashable_rock_is_in_neither_movement_set() -> void:
	var rock: Gen2WorldObject = _object(Gen2WorldObject.MOVEMENT_SMASHABLE_ROCK)
	assert_false(rock.movement_supported())
	assert_false(rock.movement_advances())


## The cartridge never rebuilds an object struct: `ApplyObjectFacing` and the
## variable-sprite table write into the one that is already there. This project
## rebuilds a record for both, so the live presentation has to survive it, or a
## `turnobject` between a `showemote` and its `applymovement` takes the emote
## down and empties the trail the script is waiting on.
func test_a_rebuilt_record_keeps_the_emote_and_the_trail_it_replaces() -> void:
	var previous: Gen2WorldObject = _object()
	previous.set_emote(3, true)
	previous.queue_step(Vector2i.RIGHT, 8)
	previous.queue_step(Vector2i.RIGHT, 8)
	previous.tick_step()
	previous.deleted = false

	var rebuilt: Gen2WorldObject = _object()
	rebuilt.carry_presentation_from(previous)

	assert_true(rebuilt.emote_visible)
	assert_eq(rebuilt.emote_id, 3)
	assert_true(rebuilt.scripted_steps)
	assert_true(rebuilt.is_stepping())
	assert_eq(rebuilt.step_offset_cells(), previous.step_offset_cells())
	assert_eq(rebuilt.queued_steps.size(), 1)


## `StepFunction_Sleep` decrements OBJECT_STEP_DURATION before testing it, so a
## zero-length sleep wraps a whole byte rather than ending at once, and a stream
## that asks for one is not a stream with nothing in it.
func test_a_zero_length_sleep_wraps_a_whole_byte() -> void:
	assert_eq(Gen2WorldObject.sleep_frames(0), 0x100)
	assert_eq(Gen2WorldObject.sleep_frames(1), 1)

	var object: Gen2WorldObject = _object()
	object.queue_wait(2)
	assert_true(object.scripted_steps)
	assert_true(object.tick_step())
	assert_eq(object.walk_frame(), 0, "a sleep stands still")
	assert_true(object.tick_step())
	assert_false(object.scripted_steps, "and the stream is done after its own count")


## `Movement_tree_shake` is a 24-frame STEP_TYPE_SLEEP under
## OBJECT_ACTION_WEIRD_TREE: nothing moves, and `SetFacingWeirdTree` takes the
## two high bits of the frame counter, so the drawing changes every four frames
## and the object is stood back up at the end.
func test_a_tree_shake_wobbles_where_it_stands() -> void:
	var object: Gen2WorldObject = _object()
	var cell: Vector2i = object.cell
	object.queue_tree_shake(Gen2WorldAPI.TREE_SHAKE_FRAMES)
	var frames: Array = []
	for _frame: int in Gen2WorldAPI.TREE_SHAKE_FRAMES:
		assert_true(object.tick_step())
		frames.append(object.frame)
	assert_eq(frames.slice(0, 8), [0, 0, 0, 1, 1, 1, 1, 2])
	assert_eq(object.cell, cell, "a shake walks nothing")
	assert_false(object.weird_tree)
	assert_eq(object.frame, 0, "24 frames is not a whole cycle, so it is stood up by hand")
	assert_false(object.tick_step())
