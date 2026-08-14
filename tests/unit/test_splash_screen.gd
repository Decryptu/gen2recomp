extends GutTest

## `SplashScreen` (engine/movie/splash.asm) as the live screen runs it: ten
## frames of blank, the copyright for a hundred, and then the GameFreak
## animation. What is checked here is the pacing and the handoff, not the
## picture, which tests/unit/test_copyright_page.gd and
## tests/unit/test_game_freak_presents.gd own.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

var _data: GameData = null
var _splash: Gen2SplashScreen = null
var _closed: int = 0


func before_each() -> void:
	_data = Fixture.build()
	_closed = 0
	_splash = Gen2SplashScreen.new()
	_splash.closed.connect(func() -> void: _closed += 1)


func after_each() -> void:
	_splash.free()
	RomCache.clear(Fixture.directory())


func test_the_copyright_appears_and_clears_on_the_source_frames() -> void:
	assert_true(_splash.open(_data))
	assert_eq(_splash.visible_image(), &"")

	_splash.advance_frames(Gen2BootCinema.COPYRIGHT_PRELUDE_FRAMES - 1)
	assert_eq(_splash.visible_image(), &"", "ld c, 10 / DelayFrames comes first")

	_splash.advance_frames(1)
	assert_eq(_splash.visible_image(), &"copyright")

	_splash.advance_frames(Gen2BootCinema.COPYRIGHT_HOLD_FRAMES - 1)
	assert_eq(_splash.visible_image(), &"copyright", "and it is held for a hundred")
	assert_eq(_closed, 0)

	_splash.advance_frames(1)
	assert_eq(
		_splash.visible_image(), &"game_freak_presents",
		"ClearTilemap, and then GameFreakPresentsInit"
	)
	assert_eq(_closed, 0, "the GameFreak animation follows it in the same screen")


func test_it_closes_once_and_owes_no_more_frames() -> void:
	assert_true(_splash.open(_data))
	assert_eq(
		_splash.frames_left(),
		Gen2BootCinema.COPYRIGHT_PRELUDE_FRAMES + Gen2BootCinema.COPYRIGHT_HOLD_FRAMES
	)
	_splash.advance_frames(1000)
	assert_eq(_closed, 1)
	assert_eq(_splash.frames_left(), 0)
	_splash.advance_frames(60)
	assert_eq(_closed, 1, "a driver that keeps spending frames does not reopen it")


## `DelayFrames` reads no joypad, so the copyright cannot be skipped, and the
## button is swallowed rather than passed on, which is what keeps a press meant
## for it out of the screen behind. `.joy_loop` does read one, so the same press
## over the GameFreak animation ends it after
## `GameFreakPresentsEnd`'s sixteen frames.
func test_only_the_gamefreak_half_reads_a_button() -> void:
	assert_true(_splash.open(_data))
	_splash.advance_frames(Gen2BootCinema.COPYRIGHT_PRELUDE_FRAMES)
	assert_true(_splash.handle_button(Gen2Button.A))
	assert_true(_splash.handle_button(Gen2Button.B))
	assert_true(_splash.handle_button(Gen2Button.START))
	assert_eq(_splash.visible_image(), &"copyright")
	assert_eq(_closed, 0)

	_splash.advance_frames(Gen2BootCinema.COPYRIGHT_HOLD_FRAMES + 20)
	assert_eq(_splash.visible_image(), &"game_freak_presents")
	assert_true(_splash.handle_button(Gen2Button.A))
	_splash.advance_frames(
		Gen2GameFreakPresents.CLEAR_TILEMAP_FRAMES
		+ Gen2GameFreakPresents.CLEANUP_FRAMES - 1
	)
	assert_eq(_closed, 0)
	_splash.advance_frames(1)
	assert_eq(_closed, 1)


## A cache with no imported splash art answers false, which is the intro
## screen's cue to go straight to the gender question.
func test_a_cache_without_the_art_does_not_open() -> void:
	assert_false(_splash.open(null))
