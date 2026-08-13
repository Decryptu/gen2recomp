extends GutTest

## `TitleScreenScene` (`engine/menus/intro_menu.asm`) and the two animations
## that run under it, frame by frame.
##
## Scene-free: [Gen2TitleScene] owns the frames and answers with the source's
## own `wTitleScreenSelectedOption`, so every case here is a count or a chord
## rather than a picture.


func _scene(profile: StringName) -> Gen2TitleScene:
	return Gen2TitleScene.create(profile)


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
## what pulls the two halves together.
func test_the_entrance_is_interlaced() -> void:
	var scene: Gen2TitleScene = _scene(RomRegistry.CRYSTAL)
	_spend(scene, 4)
	var lines: PackedInt32Array = scene.line_offsets()
	assert_eq(lines.size(), Gen2TitleScene.ENTRANCE_LINES)
	assert_eq(lines[0], scene.scroll_x())
	assert_eq(lines[1], -scene.scroll_x())

	_spend(scene, 40)
	assert_eq(scene.line_offsets().size(), 0, "and nothing overrides after it")


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
	var seen: Array[int] = []
	for step: int in 4:
		seen.append(scene.suicune_base())
		_spend(scene, 8)
	## `.Frames`' four bases are $80, $88, $00 and $08, which are tiles 0, 8, 128
	## and 136 of the strip: the sheet starts at VRAM tile $80 and the last two
	## numbers have wrapped a byte.
	assert_eq(seen, [0x00, 0x08, 0x80, 0x88] as Array[int])
	assert_eq(scene.suicune_base(), 0x00, "and then it comes round again")
	assert_eq(_scene(RomRegistry.GOLD).suicune_base(), -1, "Gold has no Suicune")


## `LoadSuicuneFrame` writes six rows of eight from the base it is handed.
func test_the_suicune_strip_is_six_rows_of_eight() -> void:
	var placed: Array[Vector3i] = _scene(RomRegistry.CRYSTAL).suicune_tiles()
	assert_eq(placed.size(), Gen2TitleScene.SUICUNE_ROWS * Gen2TitleScene.SUICUNE_COLUMNS)
	assert_eq(placed[0], Vector3i(6, 12, 0x00))
	assert_eq(placed[8], Vector3i(6, 13, 0x08), "the next row is eight tiles on")


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
	assert_eq(scene.bird_frame(), 0)
	_spend(scene, 11)
	assert_eq(scene.bird_frame(), 1, "the first entry lasts its own eleven frames")
	var total: int = 0
	for entry: Vector2i in Gen2TitleScene.BIRD_FRAMESET_GOLD:
		total += entry.y
	_spend(scene, total - 11)
	assert_eq(scene.bird_frame(), 0, "and the sequence restarts")


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
	assert_lte(trails.size(), Gen2TitleScene.MAX_SPRITE_STRUCTS)
	## `cp $a4 / jr nc, .delete` runs before the move, so the frame a particle
	## lands on the edge is still drawn and the next one takes it away.
	for trail: Dictionary in trails:
		assert_lte((trail["at"] as Vector2i).x, Gen2TitleScene.TRAIL_X_END)

	## Crystal has no bird and so no trail at all.
	var crystal: Gen2TitleScene = _scene(RomRegistry.CRYSTAL)
	_spend(crystal, 40)
	for sprite: Dictionary in crystal.sprites():
		assert_eq(StringName(sprite["kind"]), Gen2TitleScene.SPRITE_CRYSTAL)


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
