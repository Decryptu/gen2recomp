extends GutTest


func test_source_packed_screen_shake_uses_duration_and_amplitude_bits() -> void:
	var effects := Gen2WorldEffects.new()
	var started: Dictionary = effects.start_screen_shake(0x54)
	assert_true(started["active"])
	assert_eq(started["duration"], 20)
	assert_eq(started["amplitude"], 2)
	assert_eq(started["offset"], Vector2(-2, 0))

	for _frame: int in 19:
		assert_true(effects.advance_frame())
	assert_true(effects.active())
	assert_true(effects.advance_frame())
	assert_false(effects.active())
	assert_false(effects.advance_frame(), "a spent effect costs no more frames")
	assert_eq(effects.offset(), Vector2.ZERO)


func test_the_headbutt_tree_runs_its_frameset_for_thirty_two_frames() -> void:
	var effects := Gen2WorldEffects.new()
	effects.start_headbutt_tree(Vector2i(4, 7))
	var sprite: Dictionary = effects.sprites()[0]
	assert_eq(sprite["kind"], Gen2WorldEffects.SPRITE_HEADBUTT_TREE)
	assert_eq(sprite["cell"], Vector2i(4, 7))
	assert_eq(effects.hidden_tree_cells(), [Vector2i(4, 7)])
	## Each oamframe lasts three frames: tiles 0-3, tiles 4-7, tiles 0-3, then
	## tiles 4-7 flipped, and then the frameset restarts.
	var bases: Array = []
	var flips: Array = []
	for frame: int in 12:
		var tiles: Array = (effects.sprites()[0] as Dictionary)["tiles"]
		bases.append(int((tiles[0] as Dictionary)["tile"]))
		flips.append(bool((tiles[0] as Dictionary)["flip_x"]))
		effects.advance_frame()
	assert_eq(bases, [0, 0, 0, 4, 4, 4, 0, 0, 0, 4, 4, 4])
	assert_eq(flips.slice(9), [true, true, true])
	assert_eq(int((effects.sprites()[0] as Dictionary)["tiles"][0]["tile"]), 0,
		"oamrestart takes the frameset back to its first entry")

	for _frame: int in 19:
		effects.advance_frame()
	assert_true(effects.sprites_active())
	effects.advance_frame()
	assert_false(effects.sprites_active(), "wFrameCounter is 32")
	assert_eq(effects.hidden_tree_cells(), [])


func test_a_grass_rustle_swaps_its_two_facings_every_four_frames() -> void:
	var effects := Gen2WorldEffects.new()
	effects.start_grass_rustle(-1, Vector2i(2, 2), 7)
	var first: Array = (effects.sprites()[0] as Dictionary)["tiles"]
	assert_eq(first.size(), 2)
	assert_eq((first[0] as Dictionary)["offset"], Vector2i(0, 8))
	assert_true(bool((first[1] as Dictionary)["flip_x"]), "FacingGrass1 mirrors its right tile")
	for _frame: int in 4:
		effects.advance_frame()
	assert_eq(
		((effects.sprites()[0] as Dictionary)["tiles"][0] as Dictionary)["offset"],
		Vector2i(-1, 9),
	)
	for _frame: int in 3:
		effects.advance_frame()
	assert_false(effects.sprites_active(), "a rustle is one frame shorter than its step")


func test_boulder_dust_takes_its_offset_from_the_push_direction() -> void:
	var effects := Gen2WorldEffects.new()
	effects.start_boulder_dust(2, Vector2i(5, 5), Vector2i.LEFT, 16)
	var sprite: Dictionary = effects.sprites()[0]
	assert_eq(sprite["object_index"], 2)
	assert_eq((sprite["tiles"][0] as Dictionary)["offset"], Vector2i(6, 2))
	assert_eq(sprite["tiles"].size(), 4, "one tile drawn four times in a 16x16 square")
	## `SetFacingBoulderDust` swaps the two tiles on bit 1 of the frame counter.
	effects.advance_frame()
	assert_eq(int((effects.sprites()[0] as Dictionary)["tiles"][0]["tile"]), 0)
	effects.advance_frame()
	assert_eq(int((effects.sprites()[0] as Dictionary)["tiles"][0]["tile"]), 1)
	## (step duration + 1) * 2 frames, so the dust outlives the push.
	for _frame: int in 31:
		effects.advance_frame()
	assert_true(effects.sprites_active())
	effects.advance_frame()
	assert_false(effects.sprites_active())
