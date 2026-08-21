class_name Gen2MoveScreenPage
extends RefCounted

## The move screen (`MoveScreenLoop` in `engine/pokemon/mon_menu.asm`), on the
## tile grid the hardware uses.
##
## `SetUpMoveScreenBG` draws the two boxes, the nickname and the two arrows once;
## `SetUpMoveList` fills the list; `PlaceMoveData` fills the bottom box with
## whichever row the cursor is on. Swapping replaces that box with `Where?`
## instead, which is `.moving_move`.
##
## It loads `LoadStatsScreenPageTilesGFX` and nothing else the stats screen does
## not, so the two share [method Gen2BattleTiles.stats_page] and the move-list
## rows are drawn by [Gen2StatsScreenPage], whose green page lists the same four.
##
## Node-free: it writes indices into a buffer. The mon icon is not in that
## buffer; it is an object with a palette of its own, composed over the page by
## the screen.

const TILE: int = Gen2Font.TILE
const COLUMNS: int = 20
const ROWS: int = 18

## `SetUpMoveScreenBG`'s two `Textbox` calls, which take an interior: `b, c` of
## 9 by 18 at (0,1) and 5 by 18 at (0,11).
const TOP_BOX: Rect2i = Rect2i(0, 1, 20, 11)
const BOTTOM_BOX: Rect2i = Rect2i(0, 11, 20, 7)

## `GetNickname` at (5,1), and `PrintLevel` one column past whatever it printed,
## which is where `PlaceString` leaves `bc`.
const NICKNAME: Vector2i = Vector2i(5, 1)

## `PlaceMoveScreenLeftArrow` and `PlaceMoveScreenRightArrow`, each drawn only
## when there is another Pokémon that way that is neither an egg nor a hole.
const LEFT_ARROW: Vector2i = Vector2i(16, 0)
const RIGHT_ARROW: Vector2i = Vector2i(18, 0)

## `MoveList_InitAnimatedMonIcon`'s `depixel 3, 4, 2, 4`, less shadow OAM's own
## origin and the tile the four-tile icon hangs above and left of.
const ICON_AT: Vector2i = Vector2i(20, 2)

## `SetUpMoveList`: `ListMoves` at (2,3) and `ListMovePP` at (10,4), both with
## `wListMovesLineSpacing` of two rows.
const MOVES_AT: Vector2i = Vector2i(2, 3)
const MOVE_PP_AT: Vector2i = Vector2i(10, 4)

## `MoveScreen2DMenuData`'s `db 3, 1` start and `dn 2, 0` offset.
const CURSOR_COLUMN: int = 1
const CURSOR_FIRST_ROW: int = 3
const CURSOR_ROW_STEP: int = 2

## `PlaceMoveData`'s own strings and columns.
const TYPE_BOX_TOP: Vector2i = Vector2i(0, 10)
const TYPE_BOX_BOTTOM: Vector2i = Vector2i(0, 11)
## `String_MoveType_Top` and `String_MoveType_Bottom` are printed as characters,
## so the corners come off whichever textbox frame is chosen rather than off the
## font: seven columns of `┌ ───── ┐` over `│ TYPE/ └`.
const TYPE_BOX_WIDTH: int = 7
const TYPE_LABEL_STRING: String = "TYPE/"
## `constants/charmap.asm`'s box-drawing codes, which print from whichever frame
## is loaded at $79.
const CODE_BOX_TOP_LEFT: int = 0x79
const CODE_BOX_HORIZONTAL: int = 0x7A
const CODE_BOX_TOP_RIGHT: int = 0x7B
const CODE_BOX_VERTICAL: int = 0x7C
const CODE_BOX_BOTTOM_LEFT: int = 0x7D
const TYPE_AT: Vector2i = Vector2i(2, 12)
const ATTACK_LABEL: Vector2i = Vector2i(12, 12)
const ATTACK_LABEL_STRING: String = "ATK/"
const POWER_AT: Vector2i = Vector2i(16, 12)
const POWER_DIGITS: int = 3
const NO_POWER_STRING: String = "---"
## `cp 2`: a power of 0 or 1 is a move with none, and 1 is what every status move
## in `data/moves/moves.asm` carries.
const MIN_PRINTED_POWER: int = 2
const DESCRIPTION_AT: Vector2i = Vector2i(1, 14)
const DESCRIPTION_LINE_STEP: int = 2

## `.moving_move`'s `String_MoveWhere`, which replaces the move's data.
const WHERE_AT: Vector2i = Vector2i(1, 12)
const WHERE_STRING: String = "Where?"

## `PlaceHollowCursor`, the outlined arrow a held row wears.
const HOLLOW_CURSOR_CODE: int = 0xEC

## `SPRITE_ANIM_OBJ_PARTY_MON`'s frameset, which still steps here even though
## `MoveList_InitAnimatedMonIcon` nulls the sequence: two sets of four tiles,
## eight passes each, and no speed byte added because no HP bar chose one.
const ICON_FRAMES: int = Gen2PartyMenuPage.ICON_FRAMES
const ICON_FRAME_TILES: int = Gen2PartyMenuPage.ICON_FRAME_TILES
const ICON_FRAME_DURATION: int = Gen2PartyMenuPage.ICON_FRAME_DURATION

var font: Gen2Font = null
var tiles: Gen2BattleTiles = null
var stats: Gen2StatsScreenPage = null
## `Textbox` draws with wTextboxFrame, so both boxes wear whichever frame the
## player chose.
var frame_style: int = 0

## `GetSpriteAnimFrame`'s own two: FRAME opens at -1 and DURATION at zero, so
## the first pass shows the first entry and shadow OAM holds nothing before it.
var _frame: int = -1
var _duration: int = 0


static func from_data(data: GameData) -> Gen2MoveScreenPage:
	var glyphs: Gen2Font = Gen2Font.from_data(data)
	var page_tiles: Gen2BattleTiles = Gen2BattleTiles.stats_page(data)
	var rows: Gen2StatsScreenPage = Gen2StatsScreenPage.from_data(data)
	if glyphs == null or page_tiles == null or rows == null:
		return null
	var out := Gen2MoveScreenPage.new()
	out.font = glyphs
	out.tiles = page_tiles
	out.stats = rows
	out.frame_style = Gen2OptionsStore.current().textbox_frame
	return out


## Where the screen puts the mon icon, in pixels.
static func icon_position() -> Vector2i:
	return ICON_AT


## One pass of `PlaySpriteAnimations` over the one struct this screen spawns.
func advance() -> void:
	if _duration > 0:
		_duration -= 1
		return
	_frame = (_frame + 1) % ICON_FRAMES
	_duration = ICON_FRAME_DURATION


## The page as pixels with the icon composed on top: it is an object, so colour
## 0 is transparent and it is blended rather than written into the buffer.
func render(page: Dictionary, data: GameData) -> Image:
	var image: Image = _background(page, data)
	if data == null or _frame < 0:
		return image
	var colors: PackedColorArray = data.party_menu_icon_palette()
	var strip: PackedByteArray = data.species_icon_indices(int(page.get("species", 0)))
	if strip.is_empty() or colors.size() != Gen2Palette.COLORS_PER_PIC:
		return image
	var first: int = _frame * ICON_FRAME_TILES
	for quadrant: int in ICON_FRAME_TILES:
		Gen2PartyMenuPage.blend_tile(
			image, strip, first + quadrant, colors,
			ICON_AT + Vector2i((quadrant & 1) * TILE, (quadrant >> 1) * TILE)
		)
	return image


## `_CGB_MoveList`: `PREDEFPAL_GOLDENROD` over the whole screen, and one
## `FillBoxCGB` putting the Pokémon's own HP palette on the nine cells beside the
## nickname. Its `SetHPPal` reads `wPlayerHPPal`, so the colour follows how much
## of the HP bar the party menu behind it was lighting.
const HP_ATTRIBUTE: Array = [11, 1, 9, 2, 1]


static func attributes() -> PackedInt32Array:
	return Gen2PicImage.attribute_boxes([HP_ATTRIBUTE], COLUMNS, ROWS)


func _background(page: Dictionary, data: GameData) -> Image:
	var indices: PackedByteArray = draw(page)
	if data == null:
		return Gen2PicImage.from_indices(
			indices, COLUMNS * TILE, ROWS * TILE,
			Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))
		)
	var lit: int = Gen2BattleHud.bar_pixels(
		int(page.get("hp", 0)), int(page.get("max_hp", 0)),
		Gen2BattleHud.HP_BAR_TILES * TILE
	)
	return Gen2PicImage.from_attributes(
		indices, COLUMNS * TILE, ROWS * TILE, attributes(), COLUMNS,
		[data.move_screen_palette(), data.bar_palette(GameData.hp_bar_palette_name(lit))]
	)


## The whole 160x144 screen as palette indices. [param page] is
## [method Gen2MoveScreen.snapshot].
func draw(page: Dictionary) -> PackedByteArray:
	var indices := PackedByteArray()
	indices.resize(COLUMNS * TILE * ROWS * TILE)
	if font == null:
		return indices
	var width: int = COLUMNS * TILE
	_box(indices, width, TOP_BOX)
	_box(indices, width, BOTTOM_BOX)

	var name: String = String(page.get("nickname", ""))
	_text(indices, width, name, NICKNAME)
	stats.draw_level(
		indices, width, NICKNAME + Vector2i(name.length() + 1, 0),
		int(page.get("level", 0))
	)
	if bool(page.get("previous", false)):
		_code(indices, width, Gen2StatsScreenPage.CODE_LEFT_ARROW, LEFT_ARROW)
	if bool(page.get("next", false)):
		_code(indices, width, Gen2StatsScreenPage.CODE_RIGHT_ARROW, RIGHT_ARROW)

	stats.draw_move_list(indices, width, page.get("moves", []), MOVES_AT, MOVE_PP_AT)
	var cursor: int = int(page.get("cursor", 0))
	_code(
		indices, width, Gen2MenuPage.CURSOR_CODE,
		Vector2i(CURSOR_COLUMN, CURSOR_FIRST_ROW + cursor * CURSOR_ROW_STEP)
	)
	var held: int = int(page.get("held", -1))
	if held >= 0:
		_code(
			indices, width, HOLLOW_CURSOR_CODE,
			Vector2i(CURSOR_COLUMN, CURSOR_FIRST_ROW + held * CURSOR_ROW_STEP)
		)
		_text(indices, width, WHERE_STRING, WHERE_AT)
		return indices
	_draw_move_data(page, indices, width)
	return indices


## `PlaceMoveData`: the type box, the attack power and the description, all for
## the row the cursor is on. A list with no moves on it has none of this.
func _draw_move_data(page: Dictionary, into: PackedByteArray, width: int) -> void:
	var moves: Array = page.get("moves", [])
	var cursor: int = int(page.get("cursor", 0))
	if cursor < 0 or cursor >= moves.size():
		return
	var move: Dictionary = moves[cursor]
	_type_box(into, width)
	_text(into, width, String(move.get("type_name", "")), TYPE_AT)
	_text(into, width, ATTACK_LABEL_STRING, ATTACK_LABEL)
	var power: int = int(move.get("power", 0))
	_text(
		into, width,
		str(power).lpad(POWER_DIGITS) if power >= MIN_PRINTED_POWER else NO_POWER_STRING,
		POWER_AT
	)
	var lines: PackedStringArray = String(move.get("description", "")).split("\n")
	for index: int in lines.size():
		_text(
			into, width, lines[index],
			DESCRIPTION_AT + Vector2i(0, index * DESCRIPTION_LINE_STEP)
		)


## The half-open box `String_MoveType_Top` and its sibling draw around TYPE/: a
## closed top row and a bottom row that is open to the right, which is what the
## `└` at the end of the second string is.
func _type_box(into: PackedByteArray, width: int) -> void:
	_frame_tile(into, width, CODE_BOX_TOP_LEFT, TYPE_BOX_TOP)
	for column: int in range(1, TYPE_BOX_WIDTH - 1):
		_frame_tile(into, width, CODE_BOX_HORIZONTAL, TYPE_BOX_TOP + Vector2i(column, 0))
	_frame_tile(into, width, CODE_BOX_TOP_RIGHT, TYPE_BOX_TOP + Vector2i(TYPE_BOX_WIDTH - 1, 0))
	_frame_tile(into, width, CODE_BOX_VERTICAL, TYPE_BOX_BOTTOM)
	_text(into, width, TYPE_LABEL_STRING, TYPE_BOX_BOTTOM + Vector2i(1, 0))
	_frame_tile(
		into, width, CODE_BOX_BOTTOM_LEFT,
		TYPE_BOX_BOTTOM + Vector2i(TYPE_BOX_WIDTH - 1, 0)
	)


func _frame_tile(into: PackedByteArray, width: int, code: int, at: Vector2i) -> void:
	font.draw_frame_code(frame_style, code, into, width, at.x * TILE, at.y * TILE)


func _box(into: PackedByteArray, width: int, box: Rect2i) -> void:
	font.draw_box(
		frame_style, into, width,
		box.position.x * TILE, box.position.y * TILE, box.size.x, box.size.y
	)


func _text(into: PackedByteArray, width: int, text: String, at: Vector2i) -> void:
	font.draw_text(text, into, width, at.x * TILE, at.y * TILE, Gen2StatsScreenPage.FONT)


func _code(into: PackedByteArray, width: int, code: int, at: Vector2i) -> void:
	font.draw_code(code, into, width, at.x * TILE, at.y * TILE, Gen2StatsScreenPage.FONT)
