class_name Gen2HallOfFamePage
extends RefCounted

## One Hall of Fame induction panel, on the tile grid the hardware uses.
##
## Positions are `engine/events/halloffame.asm`'s own: DisplayHOFMon's two text
## boxes, its frontpic at (6,5) and every field row it prints, and
## HOF_AnimatePlayerPic's name box for the player's page.
##
## `halloffame.asm:298` calls `LoadFontsBattleExtra` before any of this, so the
## panel prints with `gfx/font/font_battle_extra.png` over $60 to $78 and `№`,
## `<ID>` and `<LV>` are real tiles. Every glyph and column here is the
## cartridge's; see [constant Gen2Text.FONT_BATTLE_EXTRA].
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

## `ld a, '№' / ld [hli], a / ld [hl], '<DOT>'` at `hlcoord 1, 13`, then
## `hlcoord 3, 13` for three digits, leaving column 6 blank before the name.
const DEX_LABEL: Vector2i = Vector2i(1, 13)
const DEX_NUMBER: Vector2i = Vector2i(3, 13)
const DEX_DIGITS: int = 3
const SPECIES_NAME: Vector2i = Vector2i(7, 13)
const GENDER: Vector2i = Vector2i(18, 13)
const NICKNAME_SLASH: Vector2i = Vector2i(8, 14)
## `PrintLevel` writes `<LV>` and then the number left-aligned beside it. Its
## three-digit branch backs over the `<LV>`, which no level in these games
## reaches: 100 is the cap and the branch is `cp 100` on a byte.
const LEVEL: Vector2i = Vector2i(1, 16)
## `<ID>`, `№`, `/` at `hlcoord 7, 16`, then five digits at `hlcoord 10, 16`.
const OT_LABEL: Vector2i = Vector2i(7, 16)
const OT_NUMBER: Vector2i = Vector2i(10, 16)
const OT_DIGITS: int = 5

## The codes the panel places directly, the way the source does: `ld [hl], '№'`
## puts a byte down, it does not print a string, and a bracketed marker is not
## something [method Gen2Text.encode] will produce.
const CODE_NUMERO: int = 0x74
const CODE_DOT: int = 0xF2
const CODE_ID: int = 0x73
const CODE_LEVEL: int = 0x6E
const CODE_SLASH: int = 0xF3

## Everything on a panel is printed with the battle-extra strip loaded.
const FONT: StringName = Gen2Text.FONT_BATTLE_EXTRA

## HOF_AnimatePlayerPic's `Textbox` at (0,2) with a 9x8 interior.
const PLAYER_BOX: Rect2i = Rect2i(0, 2, 11, 10)
const PLAYER_NAME: Vector2i = Vector2i(2, 4)

## `Textbox` draws with wTextboxFrame, which the in-game OPTION menu's FRAME row
## and the launcher's settings both write, so the panel is drawn in whichever
## frame the player chose rather than always the first.
var frame_style: int = 0

var font: Gen2Font = null


static func from_data(data: GameData) -> Gen2HallOfFamePage:
	var glyphs: Gen2Font = Gen2Font.from_data(data)
	if glyphs == null:
		return null
	var out := Gen2HallOfFamePage.new()
	out.font = glyphs
	out.frame_style = Gen2OptionsStore.current().textbox_frame
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

	_code(indices, width, CODE_NUMERO, DEX_LABEL)
	_code(indices, width, CODE_DOT, DEX_LABEL + Vector2i(1, 0))
	## PRINTNUM_LEADINGZEROS, so a two-digit dex number keeps its column.
	_text(indices, width, "%0*d" % [DEX_DIGITS, int(page.get("dex_number", 0))], DEX_NUMBER)
	_text(indices, width, String(page.get("species_name", "")), SPECIES_NAME)
	_text(indices, width, _gender_glyph(StringName(page.get("gender", &""))), GENDER)

	_code(indices, width, CODE_SLASH, NICKNAME_SLASH)
	_text(indices, width, String(page.get("nickname", "")), NICKNAME_SLASH + Vector2i(1, 0))

	_code(indices, width, CODE_LEVEL, LEVEL)
	## PRINTNUM_LEFTALIGN, so the digits start against the symbol rather than
	## being padded out to the field's width.
	_text(indices, width, str(int(page.get("level", 0))), LEVEL + Vector2i(1, 0))

	_code(indices, width, CODE_ID, OT_LABEL)
	_code(indices, width, CODE_NUMERO, OT_LABEL + Vector2i(1, 0))
	_code(indices, width, CODE_SLASH, OT_LABEL + Vector2i(2, 0))
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
		frame_style, indices, width,
		box.position.x * TILE, box.position.y * TILE, box.size.x, box.size.y
	)


func _text(indices: PackedByteArray, width: int, text: String, at: Vector2i) -> void:
	font.draw_text(text, indices, width, at.x * TILE, at.y * TILE, FONT)


## One glyph placed by its code, which is what `ld [hl], '№'` does.
func _code(indices: PackedByteArray, width: int, code: int, at: Vector2i) -> void:
	font.draw_code(code, indices, width, at.x * TILE, at.y * TILE, FONT)
