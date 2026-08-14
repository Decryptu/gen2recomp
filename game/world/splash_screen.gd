class_name Gen2SplashScreen
extends Control

## `SplashScreen` (`engine/movie/splash.asm`), as far as this project has the art
## for it.
##
## The source runs four things before a new game: the copyright screen, the
## GameFreak logo animation, on Crystal the intro movie, and the title screen.
## [Gen2BootCinema] is started with the phases this cache has art for; a phase it
## has none for is skipped rather than held on a blank screen for the frames it
## would have taken, which is what Gold and Silver's `GoldSilverIntro` still is.
##
## The pacing is the source's throughout. The copyright half is ten frames of
## blank and the screen for a hundred, with no button read at all, since
## `DelayFrames` does not look at the joypad; the GameFreak half is
## `GameFreakPresentsScene` and its sprite, which do read one, and a press there
## ends the animation early through [method Gen2BootCinema.skip_presents]. The
## title screen reads a held button rather than a press, because every branch of
## `TitleScreenMain` is `hJoyDown`.

## Emitted once the last phase this host can draw has finished.
signal closed()

const FRAME_RATE: float = Gen2BootCinema.FRAME_RATE

var _cinema: Gen2BootCinema = null
var _data: GameData = null
var _page: Gen2CopyrightPage = null
var _presents_page: Gen2GameFreakPresentsPage = null
var _movie_page: Gen2IntroMoviePage = null
var _title_page: Gen2TitlePage = null
## What `hJoyDown` holds this frame. `TitleScreenMain` reads the held state, and
## its two chords cannot be expressed as presses.
var _held: Array[int] = []
var _background: TextureRect = null
var _audio: Gen2AudioPlayer = null
var _image: Image = null
var _visible_id: StringName = &""
var _accumulator: float = 0.0
var _closed: bool = false


## Answers false on a cache with no imported splash art at all, which is the
## caller's cue to go straight on rather than to run an empty boot.
func open(data: GameData) -> bool:
	_data = data
	_page = Gen2CopyrightPage.from_data(data)
	if _page == null:
		return false
	_image = Gen2PicImage.from_indices(
		_page.draw(), Gen2Screen.WIDTH, Gen2Screen.HEIGHT, _palette()
	)
	_presents_page = Gen2GameFreakPresentsPage.from_data(data)
	_movie_page = Gen2IntroMoviePage.from_data(data)
	_title_page = Gen2TitlePage.from_data(data)
	var phases: Array[StringName] = [Gen2BootCinema.PHASE_COPYRIGHT]
	if _presents_page != null:
		phases.append(Gen2BootCinema.PHASE_PRESENTS)
	if _movie_page != null:
		phases.append(Gen2BootCinema.PHASE_INTRO_MOVIE)
	if _title_page != null:
		phases.append(Gen2BootCinema.PHASE_TITLE)
	_cinema = Gen2BootCinema.new()
	_cinema.start(
		data.id if data != null else &"gold", data, phases, _sine_table(data)
	)
	if is_inside_tree():
		_refresh()
	return true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	_background = TextureRect.new()
	_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)
	_audio = Gen2AudioPlayer.new()
	add_child(_audio)
	if _cinema != null:
		_refresh()


func _process(delta: float) -> void:
	_accumulator += delta * FRAME_RATE
	var frames: int = int(_accumulator)
	_accumulator -= float(frames)
	advance_frames(frames)


## Runs [param count] source frames. Public so a test or a preview tool can
## spend the cartridge's own `DelayFrames` without a clock.
func advance_frames(count: int) -> void:
	if _cinema == null:
		return
	for _frame: int in count:
		if _closed or _cinema.phase() == Gen2BootCinema.PHASE_FINISHED:
			_finish()
			return
		_apply(_cinema.advance_frame(_held))


## `.joy_loop`'s `and PAD_BUTTONS`: only the GameFreak animation reads one, and
## a press there still spends `GameFreakPresentsEnd`'s sixteen frames.
func handle_button(button: int) -> bool:
	if _cinema == null:
		return true
	if _cinema.phase() == Gen2BootCinema.PHASE_TITLE:
		# The title screen has no press of its own: a chord is a held state, so a
		# press only adds a button and the release below takes it away.
		if not _held.has(button):
			_held.append(button)
		return true
	if button in [
		Gen2Button.UP, Gen2Button.DOWN, Gen2Button.LEFT, Gen2Button.RIGHT
	]:
		return true
	if _cinema.phase() == Gen2BootCinema.PHASE_INTRO_MOVIE:
		# `.ShutOffMusic`: any of A, B, START or SELECT ends the whole movie and
		# stops the music with it.
		var movie: Gen2IntroMovie = _cinema.movie()
		if movie != null:
			movie.cancel()
		return true
	_cinema.skip_presents()
	return true


## The other half of `hJoyDown`, which a press-only host has no way to say.
func release_button(button: int) -> void:
	_held.erase(button)


## How many frames the splash still owes, so a driver can settle it with a loop
## rather than a clock. The GameFreak half is a sequence rather than a budget, so
## it answers one until that sequence says it has finished.
func frames_left() -> int:
	if _cinema == null or _cinema.phase() == Gen2BootCinema.PHASE_FINISHED:
		return 0
	if _cinema.phase() == Gen2BootCinema.PHASE_TITLE:
		# `TitleScreenMain` waits on a button or on its own timer, so what is
		# left is however much of that timer is still standing.
		var title: Gen2TitleScene = _cinema.title()
		return maxi(title.timer(), 1) if title != null else 1
	if _cinema.phase() != Gen2BootCinema.PHASE_COPYRIGHT:
		return 1
	return Gen2BootCinema.COPYRIGHT_PRELUDE_FRAMES \
		+ Gen2BootCinema.COPYRIGHT_HOLD_FRAMES - _cinema.phase_frame()


## Which image the coordinator has up, empty while the screen is blank.
func visible_image() -> StringName:
	return _visible_id


func image() -> Image:
	return _image


func _apply(events: Array[Dictionary]) -> void:
	for event: Dictionary in events:
		match StringName(event.get("type", &"")):
			&"show_image":
				_visible_id = StringName(event.get("id", &""))
			&"hide_image":
				if StringName(event.get("id", &"")) == _visible_id:
					_visible_id = &""
			&"open_title":
				_visible_id = &"title"
			&"restart_opening":
				# `TitleScreenEnd` jumps back to `IntroSequence`, which clears
				# the screen before the copyright's own ten blank frames.
				_visible_id = &""
			&"title_menu":
				# `Intro_MainMenu` is the launcher and the save screen here, so
				# the answer this project has for the screen is New Game.
				_cinema.select_title(&"new_game")
			&"open_new_game":
				# `NewGame` is the screen behind this one, so the opening is over
				# and nothing else here spends a frame: without this the
				# coordinator sits in its new-game phase and never finishes.
				_cinema.finish_new_game()
				_visible_id = &""
				_refresh()
				_finish()
				return
			&"play_sfx":
				_play_sfx(int(event.get("sfx", 0)))
			&"finish_intro":
				_refresh()
				_finish()
				return
	_refresh()


func _finish() -> void:
	if _closed:
		return
	_closed = true
	set_process(false)
	closed.emit()


func _refresh() -> void:
	if _background == null:
		return
	_background.texture = ImageTexture.create_from_image(_frame_image())
	_background.size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)


## What the current phase draws: the copyright graphic, one frame of the
## GameFreak animation, or the cleared screen either of them starts and ends on.
func _frame_image() -> Image:
	if _visible_id == &"copyright":
		return _image
	if _visible_id == &"game_freak_presents" and _presents_page != null:
		return _presents_page.draw(_cinema.presents())
	if _visible_id == &"intro_movie" and _movie_page != null:
		return _movie_page.draw(_cinema.movie())
	if _visible_id == &"title" and _title_page != null:
		return _title_page.draw(_cinema.title())
	return _blank()


## `PlaySFX`, which the GameFreak animation calls five times on Crystal and once
## on Gold and Silver. A screen built outside the tree has no player, which is
## what a frame-count test is, so the frames are spent either way.
func _play_sfx(sfx: int) -> void:
	if _audio == null or _data == null or sfx <= 0:
		return
	_audio.play_record(_data.world_audio(&"sfx", sfx), &"sfx", {
		"wave_samples": _data.world_audio_asset(&"wave_samples"),
		"drumkits": _data.world_audio_asset(&"drumkits"),
	})


## `ClearTilemap` leaves the blank tile everywhere, which through this palette
## is a black screen.
func _blank() -> Image:
	var indices := PackedByteArray()
	indices.resize(Gen2Screen.WIDTH * Gen2Screen.HEIGHT)
	indices.fill(Gen2CopyrightPage.BLANK_INDEX)
	return Gen2PicImage.from_indices(
		indices, Gen2Screen.WIDTH, Gen2Screen.HEIGHT, _palette()
	)


## A cache imported before the palette was falls back to the black-on-white
## every other page here uses rather than refusing to draw.
func _palette() -> PackedColorArray:
	if _page == null or _page.palette.size() < RomLayout.COPYRIGHT_PALETTE_COLORS:
		return Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))
	return _page.palette


## `BattleAnimSineWave`, which is the only part of the animation layer the
## splash reads. Built without the graphics regions, since nothing here draws a
## battle animation.
static func _sine_table(data: GameData) -> Gen2BattleAnimData:
	if data == null:
		return null
	var sine: PackedByteArray = data.battle_anim_sine()
	if sine.is_empty():
		return null
	return Gen2BattleAnimData.create({}, [], sine, data.id)
