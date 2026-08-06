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
	]:
		assert_false(_object(movement).movement_advances(), "movement %d stands" % movement)
