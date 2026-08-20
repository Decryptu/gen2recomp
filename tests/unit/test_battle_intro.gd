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


## `SlideBattlePicOut`, the other half of what the opening display does with the
## two squares: the pics slide in, and each of them slides out again when its
## own side sends something out.
func test_a_pic_slides_off_its_own_side_of_the_screen() -> void:
	for player_side: bool in [true, false]:
		var map: PackedByteArray = Gen2BattleScreenMap.seeded()
		var at: Vector2i = Gen2BattleScreenMap.PLAYER_AT if player_side \
			else Gen2BattleScreenMap.ENEMY_AT
		var head: int = at.y * Gen2BattleScreenMap.COLUMNS + at.x
		var base: int = Gen2BattleScreenMap.PLAYER_BASE_TILE if player_side \
			else Gen2BattleScreenMap.ENEMY_BASE_TILE
		assert_eq(int(map[head]), base, "the square starts with its own picture")

		# One step moves the picture one column towards the edge it leaves by,
		# which is left for the player and right for the enemy.
		Gen2BattleScreenMap.slide_step(map, player_side)
		var moved: int = head - 1 if player_side else head + 1
		assert_eq(int(map[moved]), base, "one column over after one step")

		for _step: int in int(Gen2BattleScreenMap.SLIDE_STEPS[player_side]):
			Gen2BattleScreenMap.slide_step(map, player_side)
		var side: int = Gen2BattleScreenMap.PLAYER_SIDE if player_side \
			else Gen2BattleScreenMap.ENEMY_SIDE
		for row: int in side:
			for column: int in side:
				var cell: int = (at.y + row) * Gen2BattleScreenMap.COLUMNS + at.x + column
				assert_eq(
					int(map[cell]), Gen2BattleScreenMap.BLANK_TILE,
					"the whole square is empty once the walk has run"
				)


## The other square is not touched: `hlcoord 1, 5` and `hlcoord 18, 0` are seven
## rows each and neither reaches the other picture.
func test_a_slide_leaves_the_other_square_alone() -> void:
	var map: PackedByteArray = Gen2BattleScreenMap.seeded()
	for _step: int in int(Gen2BattleScreenMap.SLIDE_STEPS[true]):
		Gen2BattleScreenMap.slide_step(map, true)
	var enemy: PackedByteArray = Gen2BattleScreenMap.seeded()
	for row: int in Gen2BattleScreenMap.ENEMY_SIDE:
		for column: int in Gen2BattleScreenMap.ENEMY_SIDE:
			var cell: int = (Gen2BattleScreenMap.ENEMY_AT.y + row) * Gen2BattleScreenMap.COLUMNS \
				+ Gen2BattleScreenMap.ENEMY_AT.x + column
			assert_eq(int(map[cell]), int(enemy[cell]))


## `DoBattleTransition`, which is the other half of how a battle opens: the
## overworld's own last two hundred frames, before the pics slide in at all.
func _run_transition(
	stronger: bool, cave: bool, trainer: bool, darkness: bool = false
) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var transition: Gen2BattleTransition = Gen2BattleTransition.create(
		stronger, cave, trainer, darkness, rng, _sine_table()
	)
	var frames: int = 0
	var orders: Array[int] = []
	var squares: int = 0
	while transition.advance_frame() and frames < 4000:
		frames += 1
		if not orders.has(transition.palette_order()):
			orders.append(transition.palette_order())
		squares = maxi(squares, _count(transition.cells(), Gen2BattleTransition.CELL_SQUARE))
	return {
		"frames": frames, "orders": orders, "squares": squares,
		"black": _count(transition.cells(), Gen2BattleTransition.CELL_BLACK),
	}


## `sine_table 32` as the cartridge stores it, which is what the wavy outro
## reads out of the cache. Built here rather than imported: this file has no
## cartridge, and the table is the assembler's own arithmetic.
func _sine_table() -> PackedByteArray:
	var out := PackedByteArray()
	for index: int in 32:
		var value: int = int(round(sin(index * PI / 32.0) * 256.0))
		out.append(value & 0xFF)
		out.append((value >> 8) & 0xFF)
	return out


func _count(cells: PackedByteArray, value: int) -> int:
	var out: int = 0
	for cell: int in cells:
		out += 1 if cell == value else 0
	return out


func test_every_transition_ends_with_the_screen_black() -> void:
	for stronger: bool in [false, true]:
		for cave: bool in [false, true]:
			var ran: Dictionary = _run_transition(stronger, cave, false)
			assert_eq(
				int(ran["black"]),
				Gen2BattleTransition.COLUMNS * Gen2BattleTransition.ROWS,
				"DoBattleTransition.done fills every palette with zero"
			)
			assert_gt(int(ran["frames"]), 100, "the lead, three flashes and an outro")


## `.DoFlashAnimation` walks its thirteen `dc` bytes two frames at a time, and
## the thirteenth is the `cp %00000001` that ends the pass rather than a palette.
func test_the_flash_walks_its_own_palette_list_three_times() -> void:
	var ran: Dictionary = _run_transition(false, false, false)
	for order: int in Gen2BattleTransition.FLASH_PALETTES:
		if order == Gen2BattleTransition.FLASH_TERMINATOR:
			continue
		assert_true(
			(ran["orders"] as Array).has(order),
			"$%02X is one of the orders the flash draws with" % order
		)


## `wTimeOfDayPalset`'s `DARKNESS_PALSET` is the one thing that skips it, and it
## skips the whole pass rather than one palette.
func test_darkness_spends_no_frames_on_the_flash() -> void:
	var lit: Dictionary = _run_transition(false, false, false)
	var dark: Dictionary = _run_transition(false, false, false, true)
	assert_eq(Array(dark["orders"]), [Gen2BattleTransition.IDENTITY])
	assert_lt(int(dark["frames"]), int(lit["frames"]))


## `StartTrainerBattle_LoadPokeBallGraphics` returns at once for a wild battle:
## the ball is what says a person is on the other side of it.
func test_only_a_trainer_transition_draws_the_poke_ball() -> void:
	assert_eq(int(_run_transition(false, false, false)["squares"]), 0)
	var trainer: Dictionary = _run_transition(false, false, true)
	var lit: int = 0
	for row: int in Gen2BattleTransition.POKE_BALL:
		for bit: int in Gen2BattleTransition.BALL_SIDE:
			lit += 1 if (row & (1 << bit)) != 0 else 0
	assert_eq(int(trainer["squares"]), lit, "one cell per set bit of the overlay")


## The two counts a real cartridge was measured at, which are what the flash and
## the outros are paced by: `StartTrainerBattle_Flash` is called 25 times before
## it hands on, three times over, and `..._SpinToBlack` spends three frames a
## wedge over twenty of them.
func test_the_flash_and_the_spin_take_the_cartridge_count() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var transition: Gen2BattleTransition = Gen2BattleTransition.create(
		false, false, true, false, rng, _sine_table()
	)
	var spent: Dictionary = {}
	var frames: int = 0
	while frames < 4000:
		## Read before the step, so a frame is counted against the scene that
		## ran on it rather than against whatever it handed on to.
		var scene: StringName = transition.scene()
		if not transition.advance_frame():
			break
		frames += 1
		spent[scene] = int(spent.get(scene, 0)) + 1
	## The whole animation, against a real Route 30 trainer, where every one of
	## these is a frame the oracle timed a routine on: `DoBattleTransition` 793,
	## `..._DetermineWhichAnimation` 812, `..._LoadPokeBallGraphics` 813,
	## `..._SetUpBGMap` 817, the first `..._Flash` 818, `..._SetUpForSpinOutro`
	## 894, `..._Finish` 959, and the screen fully black on 962.
	assert_eq(frames, 170, "`DoBattleTransition` on 793 and the screen black on 962")
	assert_eq(int(spent.get(&"flash", 0)), 75, "three passes of 25")
	assert_eq(
		int(spent.get(&"spin", 0)),
		Gen2BattleTransition.SPIN_QUADRANTS.size() * 3 + 1,
		"three frames a wedge, and the call that finds the list out"
	)
	assert_eq(
		int(spent.get(&"init", 0)), Gen2BattleTransition.LEAD_FRAMES + 1,
		"`.InitGFX` in front of the jumptable"
	)
	assert_eq(
		int(spent.get(&"ball", 0)), Gen2BattleTransition.BALL_FRAMES + 1,
		"LoadPokeBallGraphics and the three frames behind it"
	)


## The two outros a cave battle takes, which the same oracle measured with
## `wEnvironment` forced to CAVE: the wavy one runs `..._SineWave` sixteen times
## over frames 97 to 138 and the zoom is one `..._ZoomToBlack` call over 96 to
## 132, nine boxes four frames apart.
func test_the_cave_outros_take_the_cartridge_count() -> void:
	var wavy: Dictionary = _scene_frames(false, true)
	assert_eq(int(wavy["sine"]), 42, "97 to 138 inclusive")
	assert_eq(int(wavy["calls"].get(&"sine", 0)), 16, "fifteen waves and the `cp $60`")
	var zoom: Dictionary = _scene_frames(true, true)
	assert_eq(
		int(zoom["zoom"]),
		Gen2BattleTransition.ZOOM_BOXES.size() * Gen2BattleTransition.ZOOM_BOX_FRAMES + 1,
		"96 to 132 inclusive"
	)


## `.DoSineWave` reads the offset before incrementing it, so the counter walks
## the triangular numbers. A real cartridge holds 0, 1, 3, 6, 10, 15, 21, 28, 36,
## 45, 55, 66, 78, 91 and 105, and 105 is what ends the outro.
func test_the_wavy_outro_walks_the_triangular_numbers() -> void:
	var transition: Gen2BattleTransition = Gen2BattleTransition.create(
		false, true, false, false, null, _sine_table()
	)
	var seen: Array[int] = []
	while transition.advance_frame():
		if transition.scene() == &"sine" and not seen.has(transition._sine_amplitude):
			seen.append(transition._sine_amplitude)
	assert_eq(seen, [0, 1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 66, 78, 91])


## Frames and calls per scene, read before each step so a frame is counted
## against the scene that ran on it.
func _scene_frames(stronger: bool, cave: bool) -> Dictionary:
	var transition: Gen2BattleTransition = Gen2BattleTransition.create(
		stronger, cave, false, false, null, _sine_table()
	)
	var spent: Dictionary = {}
	var calls: Dictionary = {}
	var was_delayed: bool = false
	var frames: int = 0
	while frames < 4000:
		var scene: StringName = transition.scene()
		was_delayed = transition._delay > 0
		if not transition.advance_frame():
			break
		frames += 1
		spent[scene] = int(spent.get(scene, 0)) + 1
		if not was_delayed:
			calls[scene] = int(calls.get(scene, 0)) + 1
	spent["calls"] = calls
	return spent


## Nothing in `DoBattleTransition.loop` writes shadow OAM, so the sprites
## `.InitGFX`'s `UpdateSprites` left stand over the wedges. Each outro's own
## setup runs `RespawnPlayerAndOpponent`, which hides every map object but the
## player and `hLastTalked`, and `StartTrainerBattle_Finish` runs `ClearSprites`.
## Measured on a real Route 30 trainer: 14 OAM slots through the whole flash, 8
## from the frame `..._SetUpForSpinOutro` runs, and none from `..._Finish`.
func test_the_sprites_stand_over_the_wedges_until_the_outro_hides_them() -> void:
	for stronger: bool in [false, true]:
		for cave: bool in [false, true]:
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			var transition: Gen2BattleTransition = Gen2BattleTransition.create(
				stronger, cave, true, false, rng, _sine_table()
			)
			var seen: Array[int] = []
			var flash_sprites: Array[int] = []
			var frames: int = 0
			while frames < 4000:
				var scene: StringName = transition.scene()
				if not transition.advance_frame():
					break
				frames += 1
				if not seen.has(transition.sprites()):
					seen.append(transition.sprites())
				if scene in [&"init", &"ball", &"bgmap", &"flash"]:
					flash_sprites.append(transition.sprites())
			assert_eq(
				seen,
				[
					Gen2BattleTransition.SPRITES_ALL,
					Gen2BattleTransition.SPRITES_BATTLERS,
					Gen2BattleTransition.SPRITES_NONE,
				],
				"every object, then the two battlers, then none, in that order"
			)
			for sprites: int in flash_sprites:
				assert_eq(
					sprites, Gen2BattleTransition.SPRITES_ALL,
					"the flash hides nothing: `RespawnPlayerAndOpponent` is the outro's"
				)
