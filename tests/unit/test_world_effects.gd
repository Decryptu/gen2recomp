extends GutTest


func test_source_packed_screen_shake_uses_duration_and_amplitude_bits() -> void:
	var effects := Gen2WorldEffects.new()
	var started: Dictionary = effects.start_screen_shake(0x54)
	assert_true(started["active"])
	assert_eq(started["duration"], 20)
	assert_eq(started["amplitude"], 2)
	assert_eq(started["offset"], Vector2(-2, 0))

	for _frame: int in 19:
		effects.advance(Gen2WorldEffects.FRAME_SECONDS)
	assert_true(effects.active())
	effects.advance(Gen2WorldEffects.FRAME_SECONDS)
	assert_false(effects.active())
	assert_eq(effects.offset(), Vector2.ZERO)


func test_tree_shake_is_a_short_source_timed_effect() -> void:
	var effects := Gen2WorldEffects.new()
	effects.start_tree_shake({"object_index": 3})
	assert_eq(effects.snapshot()["kind"], &"tree_shake")
	assert_eq(effects.snapshot()["duration"], 32)
	effects.advance(Gen2WorldEffects.FRAME_SECONDS * 2.0)
	assert_eq(effects.snapshot()["frame"], 2)
	assert_true(effects.snapshot()["source"].has("object_index"))
