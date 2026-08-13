class_name Gen2GenderScreen
extends Control

## `engine/menus/init_gender.asm`'s boy-or-girl choice, Crystal only.
##
## `InitGender` prints its question, runs a `VerticalMenu` and writes
## `wMenuCursorY - 1` into `wPlayerGender`, which is bit 0 of the byte
## [Gen2SaveData] already carries. The selection rules are [Gen2WorldMenu]'s and
## the layout [Gen2GenderScreenPage]'s; this is the node between them.
##
## `.MenuData` sets STATICMENU_DISABLE_B, so there is no way out but a choice.
## That is the source's own answer to a screen a new game cannot skip.

## Carries [constant Gen2SaveData.GENDER_MALE] or `GENDER_FEMALE`.
signal closed(gender: int)

var _menu: Gen2WorldMenu = null
var _page: Gen2GenderScreenPage = null
var _question: String = ""
var _background: TextureRect = null


## Answers false on a cartridge that has no gender screen, which is Gold and
## Silver: `pokegold` ships neither `init_gender.asm` nor its text, so the
## caller leaves the save on GENDER_MALE rather than asking a question the
## cartridge never asks.
func open(data: GameData) -> bool:
	if data == null:
		return false
	_question = data.intro_text("gender")
	if _question == "":
		return false
	_page = Gen2GenderScreenPage.from_data(data)
	if _page == null:
		return false
	_menu = Gen2WorldMenu.from_input({
		"options": Gen2GenderScreenPage.OPTIONS.duplicate(),
		"header": {
			"kind": &"vertical",
			"data_flags": Gen2GenderScreenPage.MENU_FLAGS,
			# `.MenuHeader`'s `db 1`, which is one-based.
			"default": 1,
		},
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
	if _menu != null:
		_refresh()


## The live menu, so a driver can read the cursor without going through a redraw.
func menu() -> Gen2WorldMenu:
	return _menu


## `VerticalMenu`'s own joypad read, narrowed by `wMenuJoypadFilter`: A answers
## and B is filtered out by STATICMENU_DISABLE_B, so it does nothing here.
func handle_button(button: int) -> bool:
	if _menu == null:
		return false
	if button == Gen2Button.A:
		closed.emit(
			Gen2SaveData.GENDER_FEMALE if _menu.selected_index() == 1
			else Gen2SaveData.GENDER_MALE
		)
		return true
	if not Gen2Button.is_direction(button):
		return false
	if _menu.move(Gen2Button.vector(button)):
		_refresh()
	return true


func _refresh() -> void:
	if _background == null or _page == null or _menu == null:
		return
	var indices: PackedByteArray = _page.draw(_question, _menu.selected_index())
	_background.texture = ImageTexture.create_from_image(Gen2PicImage.from_indices(
		indices, Gen2Screen.WIDTH, Gen2Screen.HEIGHT, _palette()
	))
	_background.size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)


## `LoadGenderScreenPal`'s four colours. A cache written before they were
## imported has none, and falls back to the black-on-white every other 1bpp page
## here uses rather than refusing to draw.
func _palette() -> PackedColorArray:
	var colors: PackedColorArray = _page.palette
	if colors.size() < RomLayout.GENDER_SCREEN_PALETTE_COLORS:
		return Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))
	return colors
