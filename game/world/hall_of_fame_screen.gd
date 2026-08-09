class_name Gen2HallOfFameScreen
extends Control

## The screen behind `halloffame`, embedded in the overworld the way the PC and
## the mart overlays are.
##
## `engine/events/halloffame.asm`'s HallOfFame saves, walks the party one panel
## at a time and then shows the player's own, and finally runs the credits. What
## is here is that walk: one page per non-egg party member, then the player's,
## advanced by A. The credits, ProfOaksPCRating, the backpic and frontpic slides
## and the palette rotations are not, and neither is the persisted Hall of Fame
## record, which has no save field to go in.
##
## The source pauses 60 frames per panel and moves on by itself. This waits for
## a key instead: there is no animation to watch yet, so a timer would only be a
## delay.

signal closed()

const BACKDROP: Color = Color.WHITE

var _data: GameData = null
var _pages: Array = []
var _index: int = 0
var _page_renderer: Gen2HallOfFamePage = null
var _background: TextureRect = null
var _pic: TextureRect = null


## [param pages] is [method Gen2HallOfFame.pages]. An empty list closes at once
## rather than showing a blank screen.
func set_context(data: GameData, pages: Array) -> void:
	_data = data
	_pages = pages
	_page_renderer = Gen2HallOfFamePage.from_data(data)
	_index = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	if _page_renderer == null or _pages.is_empty():
		closed.emit()
		return
	_build()
	_refresh()


## How many pages are left, including the one on screen. Drives the scene tests
## and the screenshot tool without reaching into the array.
func remaining() -> int:
	return maxi(_pages.size() - _index, 0)


func current_page() -> Dictionary:
	if _index < 0 or _index >= _pages.size():
		return {}
	return _pages[_index]


## A moves on, matching every other text pause in the overworld. There is no way
## back: the cartridge's panels do not rewind either.
func handle_button(button: int) -> bool:
	if button != Gen2Button.A:
		return false
	advance()
	return true


func advance() -> void:
	_index += 1
	if _index >= _pages.size():
		closed.emit()
		return
	_refresh()


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = BACKDROP
	backdrop.size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	## The pic sits under the page so the bottom box's border stays drawn over
	## it, the way the hardware's window does.
	_pic = TextureRect.new()
	_pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pic)

	_background = TextureRect.new()
	_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)


func _refresh() -> void:
	var page: Dictionary = current_page()
	if page.is_empty() or _background == null:
		return
	var indices: PackedByteArray = _page_renderer.draw(page)
	var image: Image = Gen2PicImage.from_indices(
		indices, Gen2Screen.WIDTH, Gen2Screen.HEIGHT,
		Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK])),
		true
	)
	_background.texture = ImageTexture.create_from_image(image)
	_background.size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	_refresh_pic(page)


func _refresh_pic(page: Dictionary) -> void:
	if _pic == null:
		return
	_pic.texture = null
	if _data == null or StringName(page.get("kind", &"")) != Gen2HallOfFame.PAGE_MON:
		return
	var species: int = int(page.get("species", 0))
	var pic: Dictionary = _data.species_pic(species)
	if pic.is_empty():
		return
	var image: Image = Gen2PicImage.from_atlas(
		_data.atlas_indices(pic["atlas"]), _data.atlas(pic["atlas"]), pic,
		_data.palette(species)
	)
	_pic.texture = ImageTexture.create_from_image(image)
	_pic.size = Vector2(image.get_size())
	## The source centres a seven-tile cell on (6,5); a pic smaller than that
	## cell is drawn at its bottom, the way _PrepMonFrontpic places it.
	var cell: int = Gen2HallOfFamePage.pic_size()
	var at: Vector2i = Gen2HallOfFamePage.pic_position()
	_pic.position = Vector2(
		at.x + (cell - image.get_width()) / 2.0,
		at.y + cell - image.get_height()
	)
