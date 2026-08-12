extends GutTest

func test_player_slide_reaches_the_source_destination_after_eight_frames() -> void:
	var motion := Gen2IntroPresentation.new()
	motion.start_slide(48, 104)
	assert_eq(motion.position(), 48)
	for _frame: int in 8:
		assert_true(motion.advance_frame())
	assert_true(motion.finished())
	assert_eq(motion.position(), 104)
	assert_false(motion.advance_frame())


func test_wipe_window_counts_down_from_the_source_hwx_value_in_eights() -> void:
	assert_eq(Gen2IntroPresentation.wipe_window_x(0), 0x77)
	assert_eq(Gen2IntroPresentation.wipe_window_x(1), 0x6F)
	assert_eq(Gen2IntroPresentation.wipe_window_x(14), 7)
	assert_eq(Gen2IntroPresentation.wipe_window_x(15), 0)
	assert_eq(Gen2IntroPresentation.wipe_window_x(99), 0)


func test_palette_rotation_is_cyclic_and_profile_neutral() -> void:
	var row := PackedColorArray([Color.RED, Color.GREEN, Color.BLUE, Color.WHITE])
	assert_eq(Gen2IntroPresentation.rotate_palette(row, true), PackedColorArray([
		Color.WHITE, Color.RED, Color.GREEN, Color.BLUE,
	]))
	assert_eq(Gen2IntroPresentation.rotate_palette(row, false), PackedColorArray([
		Color.GREEN, Color.BLUE, Color.WHITE, Color.RED,
	]))
