class_name Gen2NamingScreenScreen
extends Control

## The naming screen (`engine/menus/naming_screen.asm`), embedded the way the
## trainer card and the Hall of Fame are.
##
## [Gen2NamingScreen] owns the walk and [Gen2NamingScreenPage] the tiles; this
## is the node between them. Input is the eight hardware buttons and nothing
## else, so a test presses a button rather than a key.

## Carries the stored entry. `NamingScreen_StoreEntry` runs on END and on
## nothing else, so a caller that never sees this signal has no name to take.
signal closed(name: String)

var _screen: Gen2NamingScreen = null
var _page: Gen2NamingScreenPage = null
var _prompt: String = ""
var _background: TextureRect = null


## `.PlayerNameString`'s "YOUR NAME?" is the caller's, since the same screen
## names a Pokemon, the rival and Mom under its own prompt. Answers false when
## the cache carried no keyboards, which the caller reports rather than opening
## a screen with nothing on it.
func open(data: GameData, prompt: String, box: bool = false) -> bool:
	_prompt = prompt
	_page = Gen2NamingScreenPage.from_data(data)
	if _page == null or not _page.ready():
		return false
	_screen = Gen2NamingScreen.for_box(data) if box else Gen2NamingScreen.for_player(data)
	if _screen.rows().is_empty():
		return false
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
	if _screen != null:
		_refresh()


## The live model, so a driver can read the entry without going through a redraw.
func model() -> Gen2NamingScreen:
	return _screen


## `NamingScreenJoypadLoop`'s `.ReadButtons`, in its own order: A, then B, then
## START, then SELECT. The d-pad is `NamingScreen_AnimateCursor`'s own read and
## is not in that list, so it never ends the screen.
func handle_button(button: int) -> bool:
	if _screen == null:
		return false
	match button:
		Gen2Button.A:
			if _screen.press_a() == Gen2NamingScreen.RESULT_END:
				closed.emit(_screen.stored_name())
				return true
		Gen2Button.B:
			_screen.press_b()
		Gen2Button.START:
			_screen.press_start()
		Gen2Button.SELECT:
			_screen.press_select()
		_:
			if not Gen2Button.is_direction(button):
				return false
			_screen.move(Gen2Button.vector(button))
	_refresh()
	return true


func _refresh() -> void:
	if _background == null or _page == null or _screen == null:
		return
	var indices: PackedByteArray = _page.draw(_screen, _prompt)
	# `.SetUpNamingScreen` reaches SCGB_DIPLOMA, which is two colours here the
	# way every other 1bpp screen in this project is.
	_background.texture = ImageTexture.create_from_image(Gen2PicImage.from_indices(
		indices, Gen2Screen.WIDTH, Gen2Screen.HEIGHT,
		Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))
	))
	_background.size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
