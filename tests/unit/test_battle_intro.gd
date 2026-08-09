extends GutTest

## `BattleIntroSlidingPics` (engine/battle/sliding_intro.asm), the one part of
## the battle presentation the two games do not share.


func _frame(intro: Gen2BattleIntro, index: int) -> PackedInt32Array:
	for step: int in index:
		intro.advance_frame()
	return intro.offsets()


func _settle(intro: Gen2BattleIntro, limit: int = 400) -> int:
	var frames: int = 0
	while not intro.finished() and frames < limit:
		intro.advance_frame()
		frames += 1
	return frames


## Crystal's `.subfunction5` writes 62 rows of `d`, 34 of `e` and 48 of zero,
## which is the screen's own height. Gold and Silver rewrite `rSCX` at `rLY` 64
## and 96 instead, so their bands are 64, 32 and 48.
func test_each_game_has_its_own_bands() -> void:
	var crystal: PackedInt32Array = Gen2BattleIntro.create(true).offsets()
	assert_eq(crystal.size(), Gen2Screen.HEIGHT)
	assert_eq(crystal[61], Gen2BattleIntro.CRYSTAL_TOP_START)
	assert_eq(crystal[62], Gen2BattleIntro.CRYSTAL_MIDDLE_START, "the middle band starts at 62")
	assert_eq(crystal[95], Gen2BattleIntro.CRYSTAL_MIDDLE_START)
	assert_eq(crystal[96], 0, "and the bottom of the screen never moves")
	assert_eq(crystal[Gen2Screen.HEIGHT - 1], 0)

	# Gold and Silver's own first frame is the lead one, before any band exists.
	var gold: PackedInt32Array = _frame(Gen2BattleIntro.create(false), 1)
	assert_eq(gold[63], Gen2BattleIntro.GOLD_TOP_START)
	assert_eq(gold[64], Gen2BattleIntro.GOLD_MIDDLE_START, "the middle band starts at 64")
	assert_eq(gold[95], Gen2BattleIntro.GOLD_MIDDLE_START)
	assert_eq(gold[96], 0)


## `ld a, c` / `ldh [hSCX], a` / `call DelayFrame` before `.loop1` is a frame of
## the whole screen at the starting offset, bottom band included. Crystal
## delays nowhere before its own loop and so has no such frame.
func test_only_gold_and_silver_lead_with_a_whole_screen_frame() -> void:
	var gold: PackedInt32Array = Gen2BattleIntro.create(false).offsets()
	assert_eq(gold[0], Gen2BattleIntro.GOLD_TOP_START)
	assert_eq(gold[80], Gen2BattleIntro.GOLD_TOP_START, "the middle band is not written yet")
	assert_eq(gold[Gen2Screen.HEIGHT - 1], Gen2BattleIntro.GOLD_TOP_START, "nor the bottom")

	var crystal: PackedInt32Array = Gen2BattleIntro.create(true).offsets()
	assert_eq(crystal[Gen2Screen.HEIGHT - 1], 0, "Crystal's bottom band is there from the start")


## `dec d` twice against `inc e` twice: the two bands walk in opposite
## directions, which is what makes the top and the middle of the screen come in
## from opposite sides.
func test_the_two_bands_walk_in_opposite_directions() -> void:
	var intro := Gen2BattleIntro.create(true)
	var first: PackedInt32Array = intro.offsets()
	var second: PackedInt32Array = _frame(intro, 1)
	assert_eq(second[0], first[0] - Gen2BattleIntro.STEP)
	assert_eq(second[70], first[70] + Gen2BattleIntro.STEP)


## Gold and Silver write their top band through `hSCX`, which is not copied to
## `rSCX` until the frame it was written during has finished, so it trails the
## middle band by a frame: the lead frame and the loop's first frame both show
## the starting offset.
func test_the_gold_top_band_trails_its_middle_one_by_a_frame() -> void:
	var intro := Gen2BattleIntro.create(false)
	assert_eq(_frame(intro, 1)[0], Gen2BattleIntro.GOLD_TOP_START)
	assert_eq(intro.offsets()[80], Gen2BattleIntro.GOLD_MIDDLE_START)

	assert_eq(_frame(intro, 1)[0], Gen2BattleIntro.GOLD_TOP_START, "still, one frame later")
	assert_eq(intro.offsets()[80], Gen2BattleIntro.GOLD_MIDDLE_START + Gen2BattleIntro.STEP)

	assert_eq(
		_frame(intro, 1)[0], Gen2BattleIntro.GOLD_TOP_START - Gen2BattleIntro.STEP,
		"and only then does the top move"
	)


## `$48 + 1` frames for Crystal, and for Gold and Silver the 72 that `dec c`
## twice takes from `$90` to zero, plus their lead frame. The same number, by
## different arithmetic.
func test_both_games_take_the_same_number_of_frames() -> void:
	assert_eq(Gen2BattleIntro.create(true).frames(), Gen2BattleIntro.CRYSTAL_FRAMES)
	assert_eq(Gen2BattleIntro.create(false).frames(), Gen2BattleIntro.CRYSTAL_FRAMES)
	assert_eq(_settle(Gen2BattleIntro.create(true)), Gen2BattleIntro.CRYSTAL_FRAMES)
	assert_eq(_settle(Gen2BattleIntro.create(false)), Gen2BattleIntro.CRYSTAL_FRAMES)


## Neither game's walk lands on zero. Crystal's `e` runs past the end of a byte
## and wraps to 2; Gold's `c` is a frame behind and stops at 4. What settles the
## screen is `InitBattleDisplay`'s own `xor a` / `ldh [hSCX], a` after the call.
func test_the_last_frame_is_short_and_the_settle_is_the_caller_s() -> void:
	var crystal := Gen2BattleIntro.create(true)
	var last: PackedInt32Array = _frame(crystal, Gen2BattleIntro.CRYSTAL_FRAMES - 1)
	assert_eq(last[0], 0, "Crystal's top band does reach home")
	assert_eq(last[70], 2, "its middle one wraps to 2 rather than reaching it")

	var gold := Gen2BattleIntro.create(false)
	var gold_last: PackedInt32Array = _frame(gold, Gen2BattleIntro.CRYSTAL_FRAMES - 1)
	assert_eq(gold_last[0], 4, "Gold's top band is still four out")
	assert_eq(gold_last[80], 254, "and its middle one two, the other way round")

	for intro: Gen2BattleIntro in [crystal, gold]:
		intro.advance_frame()
		assert_true(intro.finished())
		var settled: PackedInt32Array = intro.offsets()
		assert_eq(settled[0], 0)
		assert_eq(settled[80], 0)
		assert_false(intro.advance_frame(), "a finished intro never ticks")


## The offsets are read straight back through [Gen2Raster], so a band edge falls
## where the walk says it does rather than where a layer happens to end.
func test_the_middle_band_cuts_through_the_player_panel() -> void:
	# The player's panel runs from its name row to the bottom of its exp bar.
	var top: int = Gen2BattleHud.PLAYER_NAME.y * Gen2BattleHud.TILE
	var bottom: int = (Gen2BattleHud.PLAYER_EXP.y + 1) * Gen2BattleHud.TILE

	for crystal: bool in [true, false]:
		var edge: int = Gen2BattleIntro.CRYSTAL_TOP_ROWS if crystal \
			else Gen2BattleIntro.GOLD_TOP_ROWS
		assert_between(edge, top + 1, bottom - 1, "the band edge is inside the panel")

		var offsets: PackedInt32Array = _frame(Gen2BattleIntro.create(crystal), 4)
		assert_ne(
			offsets[top], offsets[bottom - 1],
			"so one panel is drawn in two places at once, which is why this is per scanline"
		)
