class_name Gen2SplashScreen
extends Control

## `SplashScreen` (`engine/movie/splash.asm`), as far as this project has the art
## for it.
##
## The source runs three things before a new game: the copyright screen, the
## GameFreak logo animation and, on Crystal, the intro movie. Only the copyright
## screen's graphic is imported, so [Gen2BootCinema] is started with that phase
## alone and the rest are skipped rather than held on a blank screen for the
## frames they would have taken. When the missing art arrives, this host names
## the phase and the coordinator runs it in the cartridge's own order.
##
## The pacing is the source's: ten frames of blank, the screen for a hundred, and
## no button reads either. `DelayFrames` does not read the joypad, so the
## copyright cannot be skipped; only the logo animation after it can, which is
## the phase this does not run.

## Emitted once the last phase this host can draw has finished.
signal closed()

const FRAME_RATE: float = Gen2BootCinema.FRAME_RATE

var _cinema: Gen2BootCinema = null
var _page: Gen2CopyrightPage = null
var _background: TextureRect = null
var _image: Image = null
var _visible_id: StringName = &""
var _accumulator: float = 0.0
var _closed: bool = false


## Answers false on a cache with no imported splash art at all, which is the
## caller's cue to go straight on rather than to run an empty boot.
func open(data: GameData) -> bool:
	_page = Gen2CopyrightPage.from_data(data)
	if _page == null:
		return false
	_image = Gen2PicImage.from_indices(
		_page.draw(), Gen2Screen.WIDTH, Gen2Screen.HEIGHT, _palette()
	)
	_cinema = Gen2BootCinema.new()
	_cinema.start(
		data.id if data != null else &"gold", [], [Gen2BootCinema.PHASE_COPYRIGHT]
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
		_apply(_cinema.advance_frame())


## No button reads this screen: `SplashScreen`'s copyright half is two
## `DelayFrames` runs, and neither looks at the joypad.
func handle_button(_button: int) -> bool:
	return true


## How many frames the splash still owes, so a driver can settle it with a loop
## rather than a clock.
func frames_left() -> int:
	if _cinema == null or _cinema.phase() == Gen2BootCinema.PHASE_FINISHED:
		return 0
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
	_background.texture = ImageTexture.create_from_image(
		_image if _visible_id == &"copyright" else _blank()
	)
	_background.size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)


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
