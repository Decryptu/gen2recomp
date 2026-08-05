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
