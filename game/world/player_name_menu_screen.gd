class_name Gen2PlayerNameMenuScreen
extends Control

## `ShowPlayerNamingChoices`: the source menu before the naming keyboard.

signal closed(name: String)

const FLAGS: int = (
	Gen2MenuBox.STATICMENU_CURSOR | Gen2MenuBox.STATICMENU_PLACE_TITLE
	| Gen2MenuBox.STATICMENU_DISABLE_B
)

var _menu: Gen2WorldMenu = null
var _page: Gen2MenuPage = null
var _options: Array[String] = []
var _background: TextureRect = null

## The four colours the screen is drawn through, index 0 the field and 3 the
## ink. Empty is the ordinary black-on-white; the intro sets it because
## `RotateThreePalettesRight` fades this screen out before `ClearTilemap`.
var palette: PackedColorArray = PackedColorArray():
	set(value):
		palette = value
		_refresh()



func open(data: GameData, gender: int) -> bool:
	_options = Gen2PlayerNameChoices.options(data, gender)
	_page = Gen2MenuPage.from_data(data)
	if _page == null or _options.size() != 5:
		return false
	_menu = Gen2WorldMenu.from_input({
		"options": _options,
		"header": {"kind": &"vertical", "data_flags": FLAGS, "default": 1},
	})
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
	_refresh()


func menu() -> Gen2WorldMenu:
	return _menu


func image() -> Image:
	if _background == null or _background.texture == null:
		return null
	return _background.texture.get_image()


func handle_button(button: int) -> bool:
	if _menu == null:
		return false
	if button == Gen2Button.A:
		closed.emit(String(_menu.selected_value()) if _menu.selected_index() > 0 else "")
		return true
	if not Gen2Button.is_direction(button):
		return false
	if _menu.move(Gen2Button.vector(button)):
		_refresh()
	return true


func _refresh() -> void:
	if _background == null or _page == null or _menu == null:
		return
	var indices := PackedByteArray()
	indices.resize(Gen2Screen.WIDTH * Gen2Screen.HEIGHT)
	var box := Gen2MenuBox.from_coords(0, 0, 10, Gen2TextBox.STANDARD_TOP - 1, FLAGS)
	_page.draw(box, _options, _menu.selected_index(), indices, Gen2Screen.WIDTH, "NAME", 2)
	# Index 0 stays transparent: `MENU_BACKUP_TILES` draws this over the left of
	# a screen the player pic is still standing on the right of.
	_background.texture = ImageTexture.create_from_image(Gen2PicImage.from_indices(
		indices, Gen2Screen.WIDTH, Gen2Screen.HEIGHT, _colors(), true
	))
	_background.size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)


## The menu's own two colours unless a caller has handed a faded palette in.
func _colors() -> PackedColorArray:
	return palette if palette.size() == 4 else Gen2Palette.pic_palette(
		PackedColorArray([Color.WHITE, Color.BLACK])
	)
