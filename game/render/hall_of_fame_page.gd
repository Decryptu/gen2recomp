class_name Gen2HallOfFamePage
extends RefCounted

## One Hall of Fame induction panel, on the tile grid the hardware uses.
##
## Positions are `engine/events/halloffame.asm`'s own: DisplayHOFMon's two text
## boxes, its frontpic at (6,5) and every field row it prints, and
## HOF_AnimatePlayerPic's name box for the player's page.
##
## Three of the source's glyphs are not drawn, because the project imports no
## strip that has them. The font cache is 128 tiles from $80
## ([constant RomLayout.FONT_FIRST_CODE]), while `№` is $74, `<ID>` is $73 and
## `<LV>` is $6e, all in `gfx/font/font_battle_extra.png`. Plain words stand in
## rather than invented artwork, which shifts the two number columns one tile
## right of the cartridge's.
##
## Node-free: it writes indices into a buffer, so a page can be drawn and read
## back headless. The Pokémon's own pic is not in that buffer; it has its own
## palette and is composed over the page by the screen.

const TILE: int = Gen2Font.TILE
const COLUMNS: int = 20
const ROWS: int = 18

## DisplayHOFMon: `Textbox` takes the interior, so 18x3 at (0,0) draws 20x5.
const MON_TOP_BOX: Rect2i = Rect2i(0, 0, 20, 5)
const MON_BOTTOM_BOX: Rect2i = Rect2i(0, 12, 20, 6)
const CAPTION: Vector2i = Vector2i(1, 2)
const CAPTION_TEXT: String = "New Hall of Famer!"

## `hlcoord 6, 5`, and the pic is seven tiles square.
const PIC_AT: Vector2i = Vector2i(6, 5)
const PIC_TILES: int = 7

## The source prints `№` then `<DOT>` in two tiles and the three digits in the
## next three, leaving column 6 blank before the name. "No." fills three tiles,
## so the number and the name each move one column right and the blank stays.
const DEX_LABEL: Vector2i = Vector2i(1, 13)
const DEX_NUMBER: Vector2i = Vector2i(4, 13)
const DEX_DIGITS: int = 3
const SPECIES_NAME: Vector2i = Vector2i(8, 13)
const GENDER: Vector2i = Vector2i(18, 13)
const NICKNAME_SLASH: Vector2i = Vector2i(8, 14)
const LEVEL: Vector2i = Vector2i(1, 16)
## `<ID>№/` is three tiles at (7,16); "ID" plus the slash is three as well.
const OT_LABEL: Vector2i = Vector2i(7, 16)
const OT_NUMBER: Vector2i = Vector2i(10, 16)
const OT_DIGITS: int = 5

## HOF_AnimatePlayerPic's `Textbox` at (0,2) with a 9x8 interior.
const PLAYER_BOX: Rect2i = Rect2i(0, 2, 11, 10)
const PLAYER_NAME: Vector2i = Vector2i(2, 4)

## `Textbox` draws with wTextboxFrame, whose new-game value is the first frame.
## The options screen that lets a player change it does not exist yet.
const FRAME_STYLE: int = 0

var font: Gen2Font = null


static func from_data(data: GameData) -> Gen2HallOfFamePage:
	var glyphs: Gen2Font = Gen2Font.from_data(data)
	if glyphs == null:
		return null
	var out := Gen2HallOfFamePage.new()
	out.font = glyphs
	return out


## The whole 160x144 page as palette indices. [param page] is one row of
## [method Gen2HallOfFame.pages].
func draw(page: Dictionary) -> PackedByteArray:
	var indices := PackedByteArray()
	indices.resize(COLUMNS * TILE * ROWS * TILE)
	if font == null:
		return indices
	if StringName(page.get("kind", &"")) == Gen2HallOfFame.PAGE_PLAYER:
		_draw_player(page, indices)
	else:
		_draw_mon(page, indices)
	return indices


## Where the screen puts the front pic, in pixels.
static func pic_position() -> Vector2i:
	return PIC_AT * TILE


static func pic_size() -> int:
	return PIC_TILES * TILE


func _draw_mon(page: Dictionary, indices: PackedByteArray) -> void:
	var width: int = COLUMNS * TILE
	_box(indices, width, MON_TOP_BOX)
	_box(indices, width, MON_BOTTOM_BOX)
	_text(indices, width, CAPTION_TEXT, CAPTION)

	_text(indices, width, "No.", DEX_LABEL)
	## PRINTNUM_LEADINGZEROS, so a two-digit dex number keeps its column.
	_text(indices, width, "%0*d" % [DEX_DIGITS, int(page.get("dex_number", 0))], DEX_NUMBER)
	_text(indices, width, String(page.get("species_name", "")), SPECIES_NAME)
	_text(indices, width, _gender_glyph(StringName(page.get("gender", &""))), GENDER)

	_text(indices, width, "/", NICKNAME_SLASH)
	_text(indices, width, String(page.get("nickname", "")), NICKNAME_SLASH + Vector2i(1, 0))
	_text(indices, width, "Lv%d" % int(page.get("level", 0)), LEVEL)
	_text(indices, width, "ID/", OT_LABEL)
	_text(indices, width, "%0*d" % [OT_DIGITS, int(page.get("ot_id", 0))], OT_NUMBER)


## The player's page is the name box alone. The source also slides in the
## player's own pic and prints the trainer ID and PLAY TIME beneath the name;
## the project imports no player pic and its save model carries neither number,
## so nothing stands in for them.
func _draw_player(page: Dictionary, indices: PackedByteArray) -> void:
	var width: int = COLUMNS * TILE
	_box(indices, width, PLAYER_BOX)
	_text(indices, width, String(page.get("player_name", "")), PLAYER_NAME)


## GetGender answers one of three, and the source prints a space for a
## genderless Pokémon rather than a symbol.
func _gender_glyph(gender: StringName) -> String:
	if gender == Gen2BattleMon.GENDER_MALE:
		return "♂"
	if gender == Gen2BattleMon.GENDER_FEMALE:
		return "♀"
	return " "


func _box(indices: PackedByteArray, width: int, box: Rect2i) -> void:
	font.draw_box(
		FRAME_STYLE, indices, width,
		box.position.x * TILE, box.position.y * TILE, box.size.x, box.size.y
	)


func _text(indices: PackedByteArray, width: int, text: String, at: Vector2i) -> void:
	font.draw_text(text, indices, width, at.x * TILE, at.y * TILE)
