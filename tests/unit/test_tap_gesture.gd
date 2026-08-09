extends GutTest

## The three taps that bring hidden on-screen controls back.
##
## The clock is passed in, so nothing here waits half a second three times.


func _gesture() -> Gen2TapGesture:
	return Gen2TapGesture.new()


func test_three_quick_taps_in_one_place_complete_it() -> void:
	var gesture: Gen2TapGesture = _gesture()
	assert_false(gesture.tap(Vector2(100, 100), 0.0))
	assert_false(gesture.tap(Vector2(104, 96), 0.2))
	assert_true(gesture.tap(Vector2(98, 102), 0.4))


## Completing resets, or every tap after the third would fire again and the
## setting would flap.
func test_completing_starts_the_next_one_over() -> void:
	var gesture: Gen2TapGesture = _gesture()
	gesture.tap(Vector2.ZERO, 0.0)
	gesture.tap(Vector2.ZERO, 0.1)
	assert_true(gesture.tap(Vector2.ZERO, 0.2))
	assert_eq(gesture.count(), 0)
	assert_false(gesture.tap(Vector2.ZERO, 0.3))


func test_a_slow_tap_starts_a_new_gesture() -> void:
	var gesture: Gen2TapGesture = _gesture()
	gesture.tap(Vector2.ZERO, 0.0)
	gesture.tap(Vector2.ZERO, 0.1)
	assert_false(gesture.tap(Vector2.ZERO, 0.1 + Gen2TapGesture.WINDOW + 0.01))
	assert_eq(gesture.count(), 1)


func test_a_tap_somewhere_else_starts_a_new_gesture() -> void:
	var gesture: Gen2TapGesture = _gesture()
	gesture.tap(Vector2.ZERO, 0.0)
	gesture.tap(Vector2.ZERO, 0.1)
	assert_false(gesture.tap(Vector2(Gen2TapGesture.RADIUS + 1.0, 0.0), 0.2))
	assert_eq(gesture.count(), 1)


func test_a_tap_at_the_edge_of_the_radius_still_counts() -> void:
	var gesture: Gen2TapGesture = _gesture()
	gesture.tap(Vector2.ZERO, 0.0)
	gesture.tap(Vector2(Gen2TapGesture.RADIUS, 0.0), 0.1)
	assert_eq(gesture.count(), 2)


func test_reset_forgets_everything() -> void:
	var gesture: Gen2TapGesture = _gesture()
	gesture.tap(Vector2.ZERO, 0.0)
	gesture.tap(Vector2.ZERO, 0.1)
	gesture.reset()
	assert_eq(gesture.count(), 0)
	assert_false(gesture.tap(Vector2.ZERO, 0.2))
