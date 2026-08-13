class_name Gen2PartyMenuPage
extends RefCounted

## The party menu as the hardware draws it: `WritePartyMenuTilemap`'s
## `PARTYMENUACTION_SWITCH` quality set plus `PlacePartyMenuText`
## (`engine/pokemon/party_menu.asm`).
##
## `SetUpBattlePartyMenu` clears the battle off the screen and puts this in its
## place, so the page is the whole 160x144 rather than a box over the field.
## Every column below is `hlcoord`'s own, and each quality steps two rows per
## member because `PartyMenu2DMenuData`'s cursor offset is `dn 2, 0`.
##
## [Gen2BattleSwitchMenu] owns the rows and the cursor; this is presentation
## only, and node-free, so the page can be read back headless.
##
## Not drawn: `InitPartyMenuGFX`'s menu mon icons, which are sprite animations
## over columns 1 and 2 and need `gfx/icons`, and the eggs `PartyMenuCheckEgg`
## skips every quality for, which a battle party cannot contain.

const TILE: int = Gen2Font.TILE

## `hlcoord` columns and the first row of each quality, from
## `PlacePartyNicknames`, `PlacePartyHPBar`, `PlacePartyMenuHPDigits`,
## `PlacePartyMonLevel` and `PlacePartyMonStatus`.
const NICKNAME: Vector2i = Vector2i(3, 1)
const HP_BAR: Vector2i = Vector2i(11, 2)
const HP_DIGITS: Vector2i = Vector2i(13, 1)
const LEVEL: Vector2i = Vector2i(8, 2)
const STATUS: Vector2i = Vector2i(5, 2)

## `PlacePartyNicknames.end` steps back two columns from the row below the last
## nickname, which is where CANCEL prints.
const CANCEL_COLUMN: int = NICKNAME.x - 2

## `Place2DMenuCursor`'s column, `PartyMenu2DMenuData`'s `db 1, 0`.
const CURSOR_COLUMN: int = 0

## Rows per member, `dn 2, 0`.
const ROW_STEP: int = 2

## `PlacePartyMenuText`: `hlcoord 0, 14` with `lb bc, 2, 18`, so the frame spans
## the full width and four rows, and the string prints at `hlcoord 1, 16`.
const TEXTBOX: Vector2i = Vector2i(0, 14)
const TEXTBOX_COLUMNS: int = 20
const TEXTBOX_ROWS: int = 4
const PROMPT: Vector2i = Vector2i(1, 16)

## Both HP numbers print through `PrintNum` three digits wide, space padded.
const HP_NUMBER_DIGITS: int = 3

## `PlaceStatusString`'s three-letter strings, in the order
## `PlaceNonFaintStatus` tests them. FNT comes first because
## `PlaceStatusString` checks the health before it ever looks at the byte.
const STATUS_STRINGS: Dictionary = {
	&"poison": "PSN", &"burn": "BRN", &"freeze": "FRZ",
	&"paralysis": "PAR", &"sleep": "SLP",
}
const FAINTED_STRING: String = "FNT"

var font: Gen2Font = null
var hud: Gen2BattleHud = null
var data: GameData = null

## `Textbox` draws with wTextboxFrame, so the bottom box wears whichever frame
## the player chose, as every other box here does.
var frame_style: int = 0


static func from_data(source: GameData) -> Gen2PartyMenuPage:
	var glyphs: Gen2Font = Gen2Font.from_data(source)
	var panels: Gen2BattleHud = Gen2BattleHud.from_data(source)
	if glyphs == null or panels == null:
		return null
	var out := Gen2PartyMenuPage.new()
	out.font = glyphs
	out.hud = panels
	out.data = source
	out.frame_style = Gen2OptionsStore.current().textbox_frame
	return out


## The whole screen, with the arrow on [param cursor] counting CANCEL as the row
## after the last member. [param rows] is [member Gen2BattleSwitchMenu.rows].
func render(rows: Array, cursor: int, prompt: String) -> Image:
	var width: int = Gen2Screen.WIDTH
	var height: int = Gen2Screen.HEIGHT
	var page: PackedByteArray = PackedByteArray()
	page.resize(width * height)

	for index: int in rows.size():
		_draw_member(page, width, index, rows[index])
	font.draw_text(
		Gen2BattleSwitchMenu.cancel_label(), page, width,
		CANCEL_COLUMN * TILE, (NICKNAME.y + rows.size() * ROW_STEP) * TILE
	)
	_draw_cursor(page, width, cursor)
	_draw_prompt(page, width, prompt)

	var image: Image = Gen2PicImage.from_indices(
		page, width, height, Gen2Palette.pic_palette(
			PackedColorArray([Color.WHITE, Color.BLACK])
		)
	)
	for index: int in rows.size():
		_blend_bar(image, index, rows[index])
	return image


func _draw_member(page: PackedByteArray, width: int, index: int, row: Dictionary) -> void:
	var step: int = index * ROW_STEP
	var hp: int = int(row.get("hp", 0))
	var max_hp: int = int(row.get("max_hp", 0))

	font.draw_text(
		String(row.get("name", "")), page, width,
		NICKNAME.x * TILE, (NICKNAME.y + step) * TILE
	)
	font.draw_text(
		"%s/%s" % [
			str(hp).lpad(HP_NUMBER_DIGITS), str(max_hp).lpad(HP_NUMBER_DIGITS),
		],
		page, width, HP_DIGITS.x * TILE, (HP_DIGITS.y + step) * TILE
	)
	hud.draw_bar_frame(
		page, width, Vector2i(HP_BAR.x, HP_BAR.y + step), Gen2BattleTiles.HP_BAR_END
	)
	hud.draw_level(page, width, Vector2i(LEVEL.x, LEVEL.y + step), int(row.get("level", 0)))
	font.draw_text(
		_status_string(row), page, width, STATUS.x * TILE, (STATUS.y + step) * TILE
	)


## The fill of one bar, blended over the page in its own colour: the hardware
## gives every tile its own palette, and one index buffer carries one.
func _blend_bar(image: Image, index: int, row: Dictionary) -> void:
	var width: int = Gen2Screen.WIDTH
	var buffer: PackedByteArray = PackedByteArray()
	buffer.resize(width * Gen2Screen.HEIGHT)
	var hp: int = int(row.get("hp", 0))
	var max_hp: int = int(row.get("max_hp", 0))
	var top: int = HP_BAR.y + index * ROW_STEP
	hud.draw_hp_bar(buffer, width, Vector2i(HP_BAR.x, top), hp, max_hp)

	var lit: int = Gen2BattleHud.bar_pixels(
		hp, max_hp, Gen2BattleHud.HP_BAR_TILES * TILE
	)
	var fill: Image = Gen2PicImage.from_indices(
		buffer, width, Gen2Screen.HEIGHT,
		data.bar_palette(GameData.hp_bar_palette_name(lit)), true
	)
	var at := Vector2i((HP_BAR.x + 2) * TILE, top * TILE)
	image.blend_rect(
		fill, Rect2i(at, Vector2i(Gen2BattleHud.HP_BAR_TILES * TILE, TILE)), at
	)


## `PlaceStatusString`: FNT for no health left, otherwise the first flag on the
## byte, or nothing at all for a Pokémon with none.
func _status_string(row: Dictionary) -> String:
	if bool(row.get("fainted", false)):
		return FAINTED_STRING
	var name: StringName = Gen2Status.name_of(int(row.get("status", 0)))
	return String(STATUS_STRINGS.get(name, ""))


func _draw_cursor(page: PackedByteArray, width: int, cursor: int) -> void:
	if cursor < 0:
		return
	font.draw_code(
		Gen2MenuPage.CURSOR_CODE, page, width,
		CURSOR_COLUMN * TILE, (NICKNAME.y + cursor * ROW_STEP) * TILE
	)


func _draw_prompt(page: PackedByteArray, width: int, prompt: String) -> void:
	font.draw_box(
		frame_style, page, width, TEXTBOX.x * TILE, TEXTBOX.y * TILE,
		TEXTBOX_COLUMNS, TEXTBOX_ROWS
	)
	font.draw_text(prompt, page, width, PROMPT.x * TILE, PROMPT.y * TILE)
