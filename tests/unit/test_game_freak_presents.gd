extends GutTest

## `GameFreakPresentsScene` and its sprite (`engine/movie/splash.asm`), which is
## the half of `SplashScreen` after the copyright screen. Two cartridges, two
## sequences, so nearly every case here runs both.

const Presents := preload("res://game/world/game_freak_presents.gd")

## What each profile's loop spends, counted out of the source: Crystal is one
## frame of `GameFreakLogo_Init`, fifty of `_Bounce`, thirty-three of `_Ditto`,
## sixty-five of `_Transform`, then thirty-three, sixty-five and a hundred and
## twenty-nine of `GameFreakPresentsScene`, the frame that reads the exit bit,
## and `GameFreakPresentsEnd`'s sixteen. Gold is one frame of `_Star`, sixty-five
## waiting for it, two runs of a hundred and twenty-nine either side of
## `_PlacePresents`, the frame that sets the flag, the frame that reads it, and
## the same sixteen.
const CRYSTAL_FRAMES: int = 392
const GOLD_FRAMES: int = 342


func _run(profile: StringName, frames: int = 0) -> Gen2GameFreakPresents:
	var phase := Presents.new()
	phase.start(profile, _sine())
	var limit: int = frames if frames > 0 else CRYSTAL_FRAMES + GOLD_FRAMES
	for _frame: int in limit:
		if not phase.advance_frame():
			break
	return phase


## `BattleAnimSineWave`, hand-built rather than imported: `sine_table 32` is
## `sin(x * pi / 32) * $100`, and entry 16 is $0100 because rgbasm rounds it up.
func _sine() -> Gen2BattleAnimData:
	var bytes := PackedByteArray()
	for index: int in 0x20:
		var value: int = int(round(sin(float(index) * PI / 32.0) * 256.0))
		bytes.append(value & 0xFF)
		bytes.append((value >> 8) & 0xFF)
	return Gen2BattleAnimData.create({}, [], bytes, &"crystal")


func test_each_profile_spends_its_own_frames() -> void:
	var crystal: Gen2GameFreakPresents = _run(RomRegistry.CRYSTAL)
	assert_true(crystal.finished())
	assert_eq(crystal.frame(), CRYSTAL_FRAMES)

	var gold: Gen2GameFreakPresents = _run(&"gold")
	assert_true(gold.finished())
	assert_eq(gold.frame(), GOLD_FRAMES)


## `GameFreakPresents_PlaceGameFreak` and `_PlacePresents`. On Crystal the first
## is thirty-three frames after the Ditto has finished transforming and the
## second sixty-five after that; on Gold the first lands when the sparkle timer
## passes sixty-three and the second when it runs out.
func test_the_two_words_go_up_on_the_source_frames() -> void:
	var frames: Dictionary = {
		RomRegistry.CRYSTAL: [182, 247], &"gold": [132, 196],
	}
	for profile: StringName in frames:
		var at: Array = frames[profile]
		var phase: Gen2GameFreakPresents = _run(profile, int(at[0]) - 1)
		assert_eq(phase.words(), 0, "%s: nothing is up yet" % profile)
		phase.advance_frame()
		assert_eq(phase.words(), 1, "%s: GAME FREAK" % profile)

		phase = _run(profile, int(at[1]) - 1)
		assert_eq(phase.words(), 1)
		phase.advance_frame()
		assert_eq(phase.words(), 2, "%s: PRESENTS" % profile)


## Crystal writes them at (5,10) and (7,11) with `CopyBytes`; Gold places them a
## row lower. Both spell "GAME FREAK" with one tile past the word strip, which is
## the blank first tile of the logo graphic.
func test_the_words_sit_where_their_profile_puts_them() -> void:
	assert_eq(_run(RomRegistry.CRYSTAL, 1).word_positions(), Presents.WORD_AT_CRYSTAL)
	assert_eq(_run(&"silver", 1).word_positions(), Presents.WORD_AT_GOLD)
	assert_eq(Presents.WORD_GAME_FREAK[4], RomLayout.PRESENTS_WORD_TILES)
	assert_eq(Presents.WORD_GAME_FREAK[3], Presents.WORD_GAME_FREAK[7], "both E's")
	assert_eq(Presents.WORD_GAME_FREAK[1], Presents.WORD_GAME_FREAK[8], "both A's")


## `GameFreakLogo_Bounce`. The jump height starts at 96 and loses 48 every whole
## turn of the sine offset, so the Ditto lands twice and each landing plays
## `SFX_DITTO_BOUNCE`; the pop-up follows on the frame the height reaches zero.
func test_the_ditto_bounces_twice_and_then_pops_up() -> void:
	var phase := Presents.new()
	phase.start(RomRegistry.CRYSTAL, _sine())
	var sounds: Dictionary = {}
	for _frame: int in 100:
		phase.advance_frame()
		for event: Dictionary in phase.drain_events():
			if event["type"] != &"play_sfx":
				continue
			var sfx: int = int(event["sfx"])
			if not sounds.has(sfx):
				sounds[sfx] = []
			(sounds[sfx] as Array).append(int(event["frame"]))
	assert_eq(sounds.get(Presents.SFX_DITTO_BOUNCE, []), [18, 50])
	assert_eq(sounds.get(Presents.SFX_DITTO_POP_UP, []), [51])
	assert_eq(sounds.get(Presents.SFX_DITTO_TRANSFORM, []), [84])


## The offset `BattleAnim_Sine_e` writes is a byte and stays one: the first jump
## is 96 pixels against a 84-pixel coordinate, so the top of the arc wraps past
## the bottom of the screen and the Ditto is simply not drawn there.
func test_the_dittos_first_jump_leaves_the_screen_rather_than_clamping() -> void:
	var phase := Presents.new()
	phase.start(RomRegistry.CRYSTAL, _sine())
	var lowest: int = 0
	for _frame: int in 20:
		phase.advance_frame()
		var sprites: Array[Dictionary] = phase.sprites()
		lowest = maxi(lowest, (sprites[0]["at"] as Vector2i).y)
	assert_gt(lowest, Gen2Screen.HEIGHT, "the arc wraps rather than clamping")

	# It comes back down onto the coordinate `depixel 10, 11, 4, 0` names.
	var landed: Gen2GameFreakPresents = _run(RomRegistry.CRYSTAL, 18)
	assert_eq((landed.sprites()[0]["at"] as Vector2i).y, Presents.SPRITE_AT.y)


## `GameFreakLogo_Transform`: sixty-four frames, one `GameFreakDittoPaletteFade`
## colour every four, and the words waiting on its last frame.
func test_the_transform_walks_every_fade_colour_and_then_starts_the_words() -> void:
	var phase := Presents.new()
	phase.start(RomRegistry.CRYSTAL, _sine())
	var steps: Array[int] = []
	while not phase.finished() and phase.scene() == 0:
		phase.advance_frame()
		var step: int = phase.fade_step()
		if step >= 0 and (steps.is_empty() or steps[steps.size() - 1] != step):
			steps.append(step)
	var wanted: Array[int] = []
	for index: int in RomLayout.PRESENTS_DITTO_FADE_COLORS:
		wanted.append(index)
	assert_eq(steps, wanted)
	assert_eq(phase.scene(), 1, "the sprite is what moves the scene on")


## Gold's `GameFreakPresents_PlaceLogo` waits on `wIntroSceneFrameCounter`, which
## only `AnimSeq_GSGameFreakLogoStar` sets, so the two are joined through the
## sprite layer rather than by a count: the star is gone on exactly the frame the
## logo arrives.
func test_the_gold_logo_arrives_when_the_star_does_not_and_not_before() -> void:
	var before: Gen2GameFreakPresents = _run(&"gold", 65)
	assert_eq(_kinds(before), [Presents.SPRITE_STAR])

	var after: Gen2GameFreakPresents = _run(&"gold", 66)
	assert_eq(_kinds(after), [Presents.SPRITE_LOGO])


## `GameFreakPresents_UpdateLogoPal` rotates `rOBP1` two bits right every
## sixteenth frame of the timer and stops at `%10010000`, which is the order that
## puts PREDEFPAL_GAMEFREAK_LOGO_OB's yellow on a 1bpp graphic's only colour.
func test_the_gold_logo_rotates_its_palette_three_times_and_then_holds() -> void:
	var phase := Presents.new()
	phase.start(&"gold", _sine())
	var orders: Array[int] = []
	for _frame: int in 200:
		phase.advance_frame()
		if orders.is_empty() or orders[orders.size() - 1] != phase.logo_palette():
			orders.append(phase.logo_palette())
	assert_eq(
		orders, [Presents.OBJECT_PALETTE_ORDER, 0x09, 0x42, Presents.LOGO_REGISTER_LAST]
	)


## `GameFreakPresents_Sparkle` runs on every second frame of the sparkle timer,
## so a hundred and twenty-eight frames produce sixty-four sparks, each living
## its own vector's distance times sixteen frames.
func test_gold_sprays_a_sparkle_every_other_frame_and_each_expires() -> void:
	var phase := Presents.new()
	phase.start(&"gold", _sine())
	var spawned: int = 0
	var most: int = 0
	while not phase.finished():
		var before: int = _kinds(phase).count(Presents.SPRITE_SPARKLE)
		phase.advance_frame()
		var now: int = _kinds(phase).count(Presents.SPRITE_SPARKLE)
		spawned += maxi(now - before, 0)
		most = maxi(most, now)
	assert_eq(spawned, 64)
	assert_gt(most, 0)
	assert_eq(_kinds(phase), [], "and none outlives the phase")


## `.joy_loop`'s `and PAD_BUTTONS`. The press does not end the phase where it is
## read: the exit bit is checked at the top of the next frame, and
## `GameFreakPresentsEnd` still spends its sixteen.
func test_a_button_cancels_it_and_still_spends_the_cleanup_frames() -> void:
	for profile: StringName in [RomRegistry.CRYSTAL, &"gold"]:
		var phase: Gen2GameFreakPresents = _run(profile, 40)
		assert_true(phase.cancel())
		assert_false(phase.cancel(), "the bit is already set")
		assert_false(phase.finished())
		for _frame: int in Presents.CLEANUP_FRAMES - 1:
			phase.advance_frame()
		assert_false(phase.finished(), "%s" % profile)
		phase.advance_frame()
		assert_true(phase.finished())
		assert_eq(phase.frame(), 40 + Presents.CLEANUP_FRAMES)
		assert_eq(phase.words(), 0, "ClearTilemap")
		assert_eq(_kinds(phase), [], "ClearSpriteAnims")


## The last sixteen frames are spent with the screen already cleared, which is
## `GameFreakPresentsEnd`'s own order: clear, then `DelayFrames`.
func test_the_screen_is_cleared_before_the_last_sixteen_frames() -> void:
	var phase: Gen2GameFreakPresents = _run(
		RomRegistry.CRYSTAL, CRYSTAL_FRAMES - Presents.CLEANUP_FRAMES + 1
	)
	assert_false(phase.finished())
	assert_eq(phase.words(), 0)
	assert_eq(_kinds(phase), [])


## Without an imported sine table the phase still spends the cartridge's frames;
## only the motion is missing. That is what lets a caller with no animation layer
## run the boot rather than skip it.
func test_it_spends_the_same_frames_without_a_sine_table() -> void:
	var phase := Presents.new()
	phase.start(RomRegistry.CRYSTAL)
	var frames: int = 0
	while phase.advance_frame():
		frames += 1
	assert_eq(frames, CRYSTAL_FRAMES)


func _kinds(phase: Gen2GameFreakPresents) -> Array[StringName]:
	var out: Array[StringName] = []
	for sprite: Dictionary in phase.sprites():
		out.append(StringName(sprite["kind"]))
	return out
