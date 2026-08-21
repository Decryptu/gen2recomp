extends GutTest

## `TitleScreenScene` (`engine/menus/intro_menu.asm`) and the two animations
## that run under it, frame by frame.
##
## Scene-free: [Gen2TitleScene] owns the frames and answers with the source's
## own `wTitleScreenSelectedOption`, so every case here is a count or a chord
## rather than a picture.


func _scene(profile: StringName) -> Gen2TitleScene:
	return Gen2TitleScene.create(profile)


## `BattleAnimSineWave`, hand-built rather than imported: `sine_table 32` is
## `sin(x * pi / 32) * $100`.
func _sine() -> Gen2BattleAnimData:
	var bytes := PackedByteArray()
	for index: int in 0x20:
		var value: int = int(round(sin(float(index) * PI / 32.0) * 256.0))
		bytes.append(value & 0xFF)
		bytes.append((value >> 8) & 0xFF)
	return Gen2BattleAnimData.create({}, [], bytes, &"gold")


## Every trail on screen this frame, oldest first, as the shadow-OAM positions
## [Gen2TitlePage] draws them at.
func _trails(scene: Gen2TitleScene) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for sprite: Dictionary in scene.sprites():
		if StringName(sprite["kind"]) == Gen2TitleScene.SPRITE_TRAIL:
			out.append(sprite["at"])
	return out


func _spend(scene: Gen2TitleScene, frames: int, held: Array = []) -> void:
	for _frame: int in frames:
		scene.advance_frame(held)


## Crystal opens on `TitleScreenEntrance` and Gold and Silver's `.scenes` table
## has no entrance in it at all.
func test_only_crystal_opens_on_an_entrance() -> void:
	assert_eq(_scene(RomRegistry.CRYSTAL).scene(), Gen2TitleScene.SCENE_ENTRANCE)
	assert_eq(_scene(RomRegistry.GOLD).scene(), Gen2TitleScene.SCENE_TIMER)
	assert_eq(_scene(RomRegistry.SILVER).scene(), Gen2TitleScene.SCENE_TIMER)


## `hSCX` starts at 112 and comes off four a frame, so the entrance is
## twenty-eight frames and the crystal's own fall is the same twenty-eight.
func test_the_entrance_walks_the_scroll_in_over_twenty_eight_frames() -> void:
	var scene: Gen2TitleScene = _scene(RomRegistry.CRYSTAL)
	assert_eq(scene.scroll_x(), Gen2TitleScene.ENTRANCE_SCX)

	_spend(scene, 14)
	assert_eq(scene.scroll_x(), Gen2TitleScene.ENTRANCE_SCX / 2)
	assert_eq(scene.scene(), Gen2TitleScene.SCENE_ENTRANCE)

	_spend(scene, 14)
	assert_eq(scene.scroll_x(), 0)
	## The frame that lands on zero is still the entrance; the next one is what
	## `.done` runs on.
	_spend(scene, 1)
	assert_eq(scene.scene(), Gen2TitleScene.SCENE_TIMER)


## `wLYOverrides` over the logo's eighty lines, the odd ones negated, which is
## what pulls the two halves together. The buffer is read by the LCD interrupt
## where it stands rather than copied at VBlank, so it is a pass ahead of
## `hSCX`; everything below the logo stands still, because `_TitleScreen` zeroed
## the rest of the buffer and nothing rewrites it.
func test_the_entrance_is_interlaced() -> void:
	var scene: Gen2TitleScene = _scene(RomRegistry.CRYSTAL)
	_spend(scene, 4)
	var lines: PackedInt32Array = scene.line_offsets()
	assert_eq(lines.size(), Gen2Screen.HEIGHT)
	var ahead: int = scene.scroll_x() - Gen2TitleScene.ENTRANCE_SCX_STEP
	assert_eq(lines[0], ahead)
	assert_eq(lines[1], -ahead)
	assert_eq(lines[Gen2TitleScene.ENTRANCE_LINES], 0, "the strip below is not moved")

	_spend(scene, 40)
	assert_eq(scene.line_offsets().size(), 0, "and nothing overrides after it")


## `_TitleScreen`'s own `ld a, 8 / ldh [hSCY]`, and the copyright window
## `TitleScreenEntrance.done` brings up behind it.
func test_only_crystal_scrolls_down_and_shows_a_copyright_window() -> void:
	var scene: Gen2TitleScene = _scene(RomRegistry.CRYSTAL)
	assert_eq(scene.scroll_y(), Gen2TitleScene.CRYSTAL_SCY)
	assert_eq(scene.window_y(), Gen2TitleScene.WINDOW_OFF_Y, "parked off the bottom")
	_spend(scene, Gen2TitleScene.ENTRANCE_SCX / Gen2TitleScene.ENTRANCE_SCX_STEP + 1)
	assert_eq(scene.scene(), Gen2TitleScene.SCENE_TIMER)
	assert_eq(scene.window_y(), Gen2TitleScene.WINDOW_Y)
	var gold: Gen2TitleScene = _scene(RomRegistry.GOLD)
	assert_eq(gold.scroll_y(), 0)
	assert_eq(gold.window_y(), Gen2TitleScene.WINDOW_OFF_Y, "and never draws one")


## `TitleScreenTimer`'s own `ld de`, which is the one value Gold does not share.
func test_each_profile_arms_its_own_timer() -> void:
	for row: Array in [
		[RomRegistry.GOLD, Gen2TitleScene.TIMER_GOLD],
		[RomRegistry.SILVER, Gen2TitleScene.TIMER_DEFAULT],
	]:
		var scene: Gen2TitleScene = _scene(row[0])
		_spend(scene, 1)
		assert_eq(scene.scene(), Gen2TitleScene.SCENE_MAIN)
		assert_eq(scene.timer(), int(row[1]), String(row[0]))


## `PAD_START | PAD_A`, and nothing else on its own.
func test_start_or_a_answers_the_main_menu() -> void:
	for button: int in [Gen2Button.START, Gen2Button.A]:
		var scene: Gen2TitleScene = _scene(RomRegistry.GOLD)
		_spend(scene, 4)
		assert_false(scene.finished())
		scene.advance_frame([button])
		assert_true(scene.finished())
		assert_eq(scene.selected_option(), Gen2TitleScene.OPTION_MAIN_MENU)

	var ignored: Gen2TitleScene = _scene(RomRegistry.GOLD)
	_spend(ignored, 8, [Gen2Button.LEFT])
	assert_false(ignored.finished())


## The two chords, which are held states rather than presses: three buttons at
## once, and a partial one answers nothing.
func test_the_two_chords_are_answered_whole() -> void:
	var deleting: Gen2TitleScene = _scene(RomRegistry.GOLD)
	_spend(deleting, 2)
	deleting.advance_frame([Gen2Button.UP, Gen2Button.B, Gen2Button.SELECT])
	assert_eq(deleting.selected_option(), Gen2TitleScene.OPTION_DELETE_SAVE_DATA)

	var clock: Gen2TitleScene = _scene(RomRegistry.GOLD)
	_spend(clock, 2)
	clock.advance_frame([Gen2Button.DOWN, Gen2Button.B, Gen2Button.SELECT])
	assert_eq(clock.selected_option(), Gen2TitleScene.OPTION_RESET_CLOCK)

	var partial: Gen2TitleScene = _scene(RomRegistry.GOLD)
	_spend(partial, 4, [Gen2Button.UP, Gen2Button.B])
	assert_false(partial.finished(), "two of the three is not the chord")


## `TitleScreenEnd` answers RESTART, which `.dw` sends back to `IntroSequence`.
func test_the_timer_running_out_answers_restart() -> void:
	var scene: Gen2TitleScene = _scene(RomRegistry.SILVER)
	_spend(scene, Gen2TitleScene.TIMER_DEFAULT + 1)
	assert_false(scene.finished(), "the last frame of the count is still answerable")
	_spend(scene, 1)
	assert_true(scene.finished())
	assert_eq(scene.selected_option(), Gen2TitleScene.OPTION_RESTART)


## `SuicuneFrameIterator` moves on every eighth frame and walks four bases, the
## last two of which are a sheet on from the first two.
func test_the_suicune_frame_changes_every_eighth_frame() -> void:
	var scene: Gen2TitleScene = _scene(RomRegistry.CRYSTAL)
	# `_TitleScreen`'s own `ld d, $0`, before the iterator has re-pointed the
	# strip once.
	assert_eq(scene.suicune_base(), 0x80, "the base the screen is built with")
	var seen: Array[int] = []
	for step: int in 4:
		_spend(scene, 8)
		seen.append(scene.suicune_base())
	## `.Frames`' four bases are $80, $88, $00 and $08, which are tiles 0, 8, 128
	## and 136 of the strip: the sheet starts at VRAM tile $80 and the last two
	## numbers have wrapped a byte.
	assert_eq(seen, [0x00, 0x08, 0x80, 0x88] as Array[int])
	_spend(scene, 8)
	assert_eq(scene.suicune_base(), 0x00, "and then it comes round again")
	assert_eq(_scene(RomRegistry.GOLD).suicune_base(), -1, "Gold has no Suicune")


## `LoadSuicuneFrame` writes six rows of eight from the base it is handed, and
## its `d` takes eight more at the end of each row than the eight it stepped
## across, so the sheet it reads is sixteen wide and only its left half is drawn.
## Measured against a cartridge: at a stride of eight the strip is torn, tiles
## from one row of the sheet landing in the next.
func test_the_suicune_strip_is_six_rows_of_eight() -> void:
	var scene: Gen2TitleScene = _scene(RomRegistry.CRYSTAL)
	_spend(scene, 1)
	var placed: Array[Vector3i] = scene.suicune_tiles()
	assert_eq(placed.size(), Gen2TitleScene.SUICUNE_ROWS * Gen2TitleScene.SUICUNE_COLUMNS)
	assert_eq(placed[0], Vector3i(6, 12, 0x00))
	assert_eq(placed[7], Vector3i(13, 12, 0x07), "eight across")
	assert_eq(placed[8], Vector3i(6, 13, 0x10), "and sixteen on to the next row")


## `InitializeBackground`: thirty 8x16 objects, five rows of six, all behind the
## background's own colours.
func test_the_crystal_is_thirty_objects_behind_the_logo() -> void:
	var sprites: Array[Dictionary] = _scene(RomRegistry.CRYSTAL).sprites()
	assert_eq(sprites.size(), 30)
	assert_true(bool(sprites[0]["behind"]))
	assert_eq(sprites[0]["at"], Vector2i(0x40, Gen2TitleScene.CRYSTAL_START_Y & 0xFF))
	assert_eq(sprites[1]["at"].x, 0x48, "the next is eight across")
	assert_eq(sprites[6]["at"].y, (Gen2TitleScene.CRYSTAL_START_Y + 0x10) & 0xFF)
	assert_eq(int(sprites[1]["tile"]), 2, "and two tiles on, because they are 8x16")


## `AnimateTitleCrystal` stops at `6 + 2 * TILE_WIDTH` rather than running on.
func test_the_crystal_falls_to_its_own_stop() -> void:
	var scene: Gen2TitleScene = _scene(RomRegistry.CRYSTAL)
	_spend(scene, 28)
	assert_eq(
		(scene.sprites()[0]["at"] as Vector2i).y, Gen2TitleScene.CRYSTAL_END_Y
	)
	_spend(scene, 60)
	assert_eq(
		(scene.sprites()[0]["at"] as Vector2i).y, Gen2TitleScene.CRYSTAL_END_Y,
		"and stays there"
	)


## `.Frameset_GSIntroHoOhLugia`, whose `oamframe X, n` lasts n + 1 frames and
## whose `oamrestart` takes it back to the top.
func test_the_birds_frameset_loops() -> void:
	var scene: Gen2TitleScene = _scene(RomRegistry.GOLD)
	## `_TitleScreen` copies ten bytes of a sixteen-byte struct into
	## `wSpriteAnim10`, so the bird's `SPRITEANIMSTRUCT_FRAME` keeps the zero
	## `ClearSpriteAnims` left rather than `_InitSpriteAnimStruct`'s -1, and
	## `GetSpriteAnimFrame`'s `inc [hl]` skips entry 0 on the first pass alone.
	_spend(scene, 1)
	assert_eq(scene.bird_frame(), 1, "the screen opens on the second entry")
	_spend(scene, 9)
	assert_eq(scene.bird_frame(), 1, "which lasts its own duration plus one")
	_spend(scene, 1)
	assert_eq(scene.bird_frame(), 2)

	## `oamrestart` writes -1, so every cycle after the first plays entry 0. The
	## first cycle is the whole frameset less that entry, and the screen is
	## eleven frames into it here.
	var total: int = 0
	for entry: Vector2i in Gen2TitleScene.BIRD_FRAMESET_GOLD:
		total += entry.y + 1
	var first_cycle: int = total - (Gen2TitleScene.BIRD_FRAMESET_GOLD[0].y + 1)
	_spend(scene, first_cycle - 11 + 1)
	assert_eq(scene.bird_frame(), 0, "and the sequence restarts")
	_spend(scene, Gen2TitleScene.BIRD_FRAMESET_GOLD[0].y)
	assert_eq(scene.bird_frame(), 0, "for the entry's own duration plus one")
	_spend(scene, 1)
	assert_eq(scene.bird_frame(), 1)


## `UpdateTitleTrailSprite` spawns on every fourth frame of the timer, and
## `AnimSeq_GSTitleTrail` walks each particle right until it is gone.
func test_trails_are_spawned_behind_the_bird_and_fly_off() -> void:
	var scene: Gen2TitleScene = _scene(RomRegistry.GOLD)
	_spend(scene, 40)
	var trails: Array = scene.sprites().filter(
		func(sprite: Dictionary) -> bool:
			return StringName(sprite["kind"]) == Gen2TitleScene.SPRITE_TRAIL
	)
	assert_gt(trails.size(), 0, "the screen is dropping trails")
	## The bird holds the tenth struct for the whole screen, so nine is the cap.
	assert_lte(trails.size(), Gen2TitleScene.MAX_TRAILS)
	## `cp $a4 / jr nc, .delete` runs before the move, so the frame a particle
	## lands on the edge is still drawn and the next one takes it away.
	for trail: Dictionary in trails:
		assert_lte((trail["at"] as Vector2i).x, Gen2TitleScene.TRAIL_X_END)

	## Crystal has no bird and so no trail at all.
	var crystal: Gen2TitleScene = _scene(RomRegistry.CRYSTAL)
	_spend(crystal, 40)
	for sprite: Dictionary in crystal.sprites():
		assert_eq(StringName(sprite["kind"]), Gen2TitleScene.SPRITE_CRYSTAL)


## `UpdateTitleTrailSprite` reads the timer `TitleScreenScene` has already
## counted down this frame, and `InitSpriteAnimStruct` runs behind
## `PlaySpriteAnimations`, so a struct spawned now is not in shadow OAM until the
## next frame. The timer is armed on frame 1 with its low two bits clear.
func test_a_trail_is_drawn_the_frame_after_it_is_spawned() -> void:
	var scene: Gen2TitleScene = _scene(RomRegistry.SILVER)
	var grew: Array[int] = []
	var count: int = 0
	for frame: int in range(1, 13):
		scene.advance_frame()
		if _trails(scene).size() > count:
			count = _trails(scene).size()
			grew.append(frame)
	assert_eq(grew, [2, 6, 10] as Array[int])


## `.Frameset_GSTitleTrail`: Gold alternates the two `spriteanimoam` vtiles and
## `oamrestart`s, so each of the trail's two pictures is up for two frames, and
## Silver holds the first and `oamend`s, which repeats it for as long as the
## sprite is up. Measured against a cartridge, whose trail entries carry tile
## $f8 and $fa on Gold and only $f8 on Silver.
func test_golds_trail_alternates_its_two_pictures_and_silvers_does_not() -> void:
	var gold := Gen2TitleScene.create(RomRegistry.GOLD, _sine())
	var sets: Array[int] = []
	for _frame: int in 20:
		gold.advance_frame()
		for sprite: Dictionary in gold.sprites():
			if StringName(sprite["kind"]) != Gen2TitleScene.SPRITE_TRAIL:
				continue
			var set: int = int(sprite["tile"])
			if sets.is_empty() or sets[sets.size() - 1] != set:
				sets.append(set)
			break
	# Every trail on screen is on the same phase, since they are spawned on a
	# four-frame cadence and the frameset's cycle is four frames long.
	assert_eq(
		sets, [0, 1, 0, 1, 0, 1, 0, 1, 0, 1] as Array[int],
		"two frames each, then oamrestart"
	)

	var silver := Gen2TitleScene.create(RomRegistry.SILVER, _sine())
	var held: Array[int] = []
	for _frame: int in 20:
		silver.advance_frame()
		for sprite: Dictionary in silver.sprites():
			if StringName(sprite["kind"]) == Gen2TitleScene.SPRITE_TRAIL \
					and not held.has(int(sprite["tile"])):
				held.append(int(sprite["tile"]))
	assert_eq(held, [0] as Array[int], "oamend repeats the first")


## `AnimSeq_GSTitleTrail`'s Silver branch is a different routine under the same
## name: no `inc [hl]` on the y coordinate, and no
## `AnimSeqs_IncAnonJumptableIndex`, so `.zero` recomputes the sine every frame
## off `wIntroSceneTimer`, which the union at `wJumptableIndex + 2` gives to
## `LOW(wTitleScreenTimer)`.
func test_silvers_trail_flies_level_on_a_sine_off_the_live_timer() -> void:
	var scene := Gen2TitleScene.create(RomRegistry.SILVER, _sine())
	var seen: Array[int] = []
	var first := Vector2i(0, 0)
	for _frame: int in 10:
		scene.advance_frame()
		var trails: Array[Vector2i] = _trails(scene)
		if trails.is_empty():
			continue
		if seen.is_empty():
			first = trails[0]
		seen.append(trails[0].y)
		assert_eq(trails[0].x, first.x + 4 * (seen.size() - 1), "four pixels a frame")

	## `wIntroSceneTimer & $30` swapped is 0 to 3, so the amplitude is 3 to 6 and
	## the trail stays inside that band of its own spawn row rather than falling.
	var high: int = Gen2TitleScene.TRAIL_AT_SILVER.y + 6
	for y: int in seen:
		assert_between(y, Gen2TitleScene.TRAIL_AT_SILVER.y - 6, high)
	assert_gt(_distinct(seen), 1, "and it is a sine rather than a straight line")

	## Gold's own branch is the one that falls: its y coordinate takes an
	## `inc [hl]` a frame under a sine of two.
	var gold := Gen2TitleScene.create(RomRegistry.GOLD, _sine())
	var gold_seen: Array[int] = []
	for _frame: int in 10:
		gold.advance_frame()
		var trails: Array[Vector2i] = _trails(gold)
		if not trails.is_empty():
			gold_seen.append(trails[0].y)
	assert_gt(gold_seen.size(), 4)
	assert_between(
		gold_seen[-1] - gold_seen[0], gold_seen.size() - 3, gold_seen.size() + 1,
		"a pixel a frame, give or take the sine"
	)


## Gold's `.zero` seeds VAR1 with `SPRITEANIMSTRUCT_INDEX`, which is
## `wSpriteAnimCount` at the spawn: four consecutive trails open a quarter turn
## apart rather than all on the same phase.
func test_golds_trails_open_on_their_own_phase() -> void:
	var scene := Gen2TitleScene.create(RomRegistry.GOLD, _sine())
	## Every Gold spawn row shares an x, and each trail moves four a frame, so the
	## frame a trail was spawned on names it for as long as it is up.
	var paths: Dictionary = {}
	for frame: int in 40:
		scene.advance_frame()
		for at: Vector2i in _trails(scene):
			var key: int = at.x - Gen2TitleScene.TRAIL_X_STEP * frame
			if not paths.has(key):
				paths[key] = [at.y]
				continue
			(paths[key] as Array).append(at.y - int((paths[key] as Array)[0]))
	var shapes: Array[Array] = []
	for key: int in paths:
		var path: Array = (paths[key] as Array).slice(1, 12)
		if path.size() == 11 and not shapes.has(path):
			shapes.append(path)
	assert_gt(shapes.size(), 1, "consecutive spawns ride the sine from different places")


## `DoNextFrameForAllSprites` calls `UpdateAnimFrame` whatever the animation
## did, so `AnimSeq_GSTitleTrail`'s `.delete` clears the struct's index and the
## sprite is still written to shadow OAM on that same pass, unmoved. The pass
## after it is the one `.loop`'s `and a` skips.
func test_a_trail_is_drawn_once_more_on_the_frame_it_is_deleted() -> void:
	var scene := Gen2TitleScene.create(RomRegistry.GOLD, _sine())
	var last: Vector2i = Vector2i(-1, -1)
	var held: int = 0
	for _frame: int in 200:
		scene.advance_frame()
		for at: Vector2i in _trails(scene):
			if at.x < Gen2TitleScene.TRAIL_X_END - Gen2TitleScene.TRAIL_X_STEP:
				continue
			if at == last:
				held += 1
			last = at
	assert_gt(held, 0, "the struct is drawn a second time where it stands")

	## And it is gone the pass after, rather than riding on past $a4.
	var beyond: Array[Vector2i] = []
	var walk := Gen2TitleScene.create(RomRegistry.GOLD, _sine())
	for _frame: int in 200:
		walk.advance_frame()
		for at: Vector2i in _trails(walk):
			if at.x > Gen2TitleScene.TRAIL_X_END:
				beyond.append(at)
	assert_eq(beyond, [] as Array[Vector2i], "and never past the edge")


func _distinct(values: Array[int]) -> int:
	var seen: Array[int] = []
	for value: int in values:
		if not seen.has(value):
			seen.append(value)
	return seen.size()


## `ScrollTitleScreenClouds`, which Gold runs on every eighth frame and Silver
## on every one.
func test_the_clouds_scroll_at_each_profiles_own_rate() -> void:
	## `wLYOverrides` is bytes and `dec a` wraps in one, which is a left scroll
	## because the map it moves is 256 wide.
	var gold: Gen2TitleScene = _scene(RomRegistry.GOLD)
	_spend(gold, 8)
	assert_eq(gold.line_offsets()[Gen2TitleScene.CLOUD_FIRST_LINE], 0xFF)

	var silver: Gen2TitleScene = _scene(RomRegistry.SILVER)
	_spend(silver, 8)
	assert_eq(silver.line_offsets()[Gen2TitleScene.CLOUD_FIRST_LINE], 0xF8)
	assert_eq(silver.line_offsets()[Gen2TitleScene.CLOUD_FIRST_LINE - 1], 0,
		"and only the band it names moves")
