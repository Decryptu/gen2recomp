class_name Gen2PCBoxPage
extends RefCounted

## Bill's PC on the tile grid the hardware uses (`engine/pokemon/bills_pc.asm`).
##
## `Gen2BoxScreen` owns the party, the boxes and what a row may do; this is the
## picture, the way [Gen2PackPage] is the pack's. Every position is the source's
## own: `BillsPC_BoxName`'s header box, `BillsPC_RefreshTextboxes`' listing,
## `PCMonInfo`'s left column and `BillsPC_PlaceString`'s bottom box.
##
## Node-free: it writes indices into a buffer, so a page can be drawn and read
## back headless. The selected Pokemon's pic is not in that buffer and neither is
## the cursor, since both are drawn through palettes of their own; the screen
## composes them over the page from [method pic_position] and
## [method cursor_sprites].

const TILE: int = Gen2Font.TILE
const COLUMNS: int = 20
const ROWS: int = 18

## `hlcoord 8, 0 / lb bc, 1, 10`, so a one-row interior is a three-row frame,
## and the name is printed two columns in.
const NAME_BOX: Rect2i = Rect2i(8, 0, 12, 3)
const NAME_AT: Vector2i = Vector2i(10, 1)

## `hlcoord 8, 2 / lb bc, 10, 10`, whose top corners are then overwritten with
## `└` and `┘` so the listing joins the header box above it rather than closing
## against it.
const LIST_BOX: Rect2i = Rect2i(8, 2, 12, 12)
const LIST_AT: Vector2i = Vector2i(9, 4)
## `ld a, $5 / ld [wBillsPC_NumMonsOnScreen], a`, and the two rows a nickname
## steps by.
const LIST_HEIGHT: int = 5
const ROW_SPACING: int = 2
## `.CancelString`, the row `CopyBoxmonSpecies` terminates every list with.
const CANCEL: String = "CANCEL"

## `BillsPC_PlaceString`: `hlcoord 0, 15 / lb bc, 1, 18` and its own line.
const PROMPT_BOX: Rect2i = Rect2i(0, 15, 20, 3)
const PROMPT_AT: Vector2i = Vector2i(1, 16)

## `PCMonInfo`'s own column. The pic is seven tiles square at `hlcoord 1, 4`,
## laid down column by column (`ld [hli], a / add 7`), which is the order
## `GetMonFrontpic` decompresses into.
const PIC_AT: Vector2i = Vector2i(1, 4)
const PIC_TILES: int = 7
const LEVEL_AT: Vector2i = Vector2i(1, 12)
const GENDER_AT: Vector2i = Vector2i(5, 12)
const ITEM_AT: Vector2i = Vector2i(7, 12)
const SPECIES_AT: Vector2i = Vector2i(1, 14)

## `PrintLevel`'s `<LV>`, and the two markers `BillsPC_InitGFX` copies
## `PCMailGFX` over: `$5c` for a held mail and `$5d` for any other held item.
## Everything on the page is printed with the battle-extra strip loaded, which
## `BillsPC_InitGFX` does before it copies `PCMailGFX` over two of its tiles.
const FONT: StringName = Gen2Text.FONT_BATTLE_EXTRA
const CODE_LEVEL: int = 0x6E
const MAIL_CODE: int = 0x5C
const ITEM_CODE: int = 0x5D

## `BillsPC_UpdateSelectionCursor`'s OAM, as (x, y, tile, x flip, y flip) in
## screen pixels: `dbsprite` is x tile, y tile, x pixel, y pixel, and a shadow
## OAM position carries the hardware's own 8 and 16 pixel bias, which is taken
## off here. The whole set moves down sixteen pixels per cursor row
## (`and $7 / swap a`), so only the row inside the listing is stored.
##
## The two profiles draw different rings out of different sheets, the way
## `.Frameset_GSTitleTrail` does: Crystal's twenty-four objects are two tiles
## flipped into four edges, and Gold and Silver's twenty are six tiles with no
## flip in them at all. Reading either set out of the other's sheet draws the
## side pieces along the top.
const CURSOR_STEP: int = 16
const CURSOR_SPRITES: Array = [
	[72, 22, 0, false, false], [80, 22, 0, false, false],
	[88, 22, 0, false, false], [96, 22, 0, false, false],
	[104, 22, 0, false, false], [112, 22, 0, false, false],
	[120, 22, 0, false, false], [128, 22, 0, false, false],
	[136, 22, 0, false, false], [143, 22, 0, false, false],
	[72, 46, 0, false, true], [80, 46, 0, false, true],
	[88, 46, 0, false, true], [96, 46, 0, false, true],
	[104, 46, 0, false, true], [112, 46, 0, false, true],
	[120, 46, 0, false, true], [128, 46, 0, false, true],
	[136, 46, 0, false, true], [143, 46, 0, false, true],
	[70, 30, 1, false, false], [70, 33, 1, false, true],
	[145, 30, 1, true, false], [145, 33, 1, true, true],
]
const CURSOR_SPRITES_GOLD: Array = [
	[71, 25, 0, false, false], [79, 25, 1, false, false],
	[87, 25, 1, false, false], [95, 25, 1, false, false],
	[103, 25, 1, false, false], [111, 25, 1, false, false],
	[119, 25, 1, false, false], [127, 25, 1, false, false],
	[135, 25, 1, false, false], [143, 25, 2, false, false],
	[71, 33, 3, false, false], [79, 33, 4, false, false],
	[87, 33, 4, false, false], [95, 33, 4, false, false],
	[103, 33, 4, false, false], [111, 33, 4, false, false],
	[119, 33, 4, false, false], [127, 33, 4, false, false],
	[135, 33, 4, false, false], [143, 33, 5, false, false],
]

## Whichever text box border the player chose, the way every other screen's
## boxes are drawn.
var frame_style: int = 0
var font: Gen2Font = null
## Which cartridge's cursor set the screen draws.
var _profile: StringName = RomRegistry.CRYSTAL
## `PCMailGFX`, the two markers a held item is printed as.
var _mail: PackedByteArray = PackedByteArray()


static func from_data(data: GameData) -> Gen2PCBoxPage:
	if data == null:
		return null
	var glyphs: Gen2Font = Gen2Font.from_data(data)
	if glyphs == null:
		return null
	var out := Gen2PCBoxPage.new()
	out.font = glyphs
	out.frame_style = Gen2OptionsStore.current().textbox_frame
	out._profile = data.id
	out._mail = data.tile_indices("pc_mail")
	return out


## The whole 160x144 page as palette indices.
##
## [param state] is the screen's own: `box_name`, the visible `rows` of at most
## [constant LIST_HEIGHT] nicknames with `cancel` on the last one, `prompt` for
## the line the bottom box carries, and `mon` for whatever `PCMonInfo` prints
## about the row the cursor stands on.
func draw(state: Dictionary) -> PackedByteArray:
	var indices := PackedByteArray()
	indices.resize(COLUMNS * TILE * ROWS * TILE)
	if font == null:
		return indices
	var width: int = COLUMNS * TILE
	_box(indices, width, NAME_BOX)
	_text(indices, width, String(state.get("box_name", "")), NAME_AT)
	_box(indices, width, LIST_BOX)
	## The two corners `BillsPC_RefreshTextboxes` writes over the frame it has
	## just drawn, which is what joins the two boxes into one.
	_frame_code(indices, width, RomLayout.FRAME_BOTTOM_LEFT, LIST_BOX.position)
	_frame_code(
		indices, width, RomLayout.FRAME_BOTTOM_RIGHT,
		Vector2i(LIST_BOX.position.x + LIST_BOX.size.x - 1, LIST_BOX.position.y)
	)
	var rows: Array = state.get("rows", [])
	for index: int in mini(rows.size(), LIST_HEIGHT):
		var row: Dictionary = rows[index]
		var at: Vector2i = LIST_AT + Vector2i(0, index * ROW_SPACING)
		_text(
			indices, width,
			CANCEL if bool(row.get("cancel", false)) else String(row.get("name", "")),
			at
		)
	_box(indices, width, PROMPT_BOX)
	_text(indices, width, String(state.get("prompt", "")), PROMPT_AT)
	_draw_mon(indices, width, state.get("mon", {}))
	return indices


## `PCMonInfo`'s fields. It returns before any of them for an empty row and
## after the pic for an egg, which is why a state with no `mon` draws neither.
func _draw_mon(indices: PackedByteArray, width: int, mon: Dictionary) -> void:
	if mon.is_empty():
		return
	_code(indices, width, CODE_LEVEL, LEVEL_AT)
	_text(indices, width, str(int(mon.get("level", 0))), LEVEL_AT + Vector2i(1, 0))
	_text(indices, width, String(mon.get("gender", " ")), GENDER_AT)
	_text(indices, width, String(mon.get("species_name", "")), SPECIES_AT)
	var item: int = int(mon.get("item", 0))
	if item > 0:
		_marker(
			indices, width,
			MAIL_CODE if bool(mon.get("mail", false)) else ITEM_CODE, ITEM_AT
		)


## Where the pic goes and how big its cell is, in pixels, for the screen that
## composes it.
static func pic_position() -> Vector2i:
	return PIC_AT * TILE


static func pic_size() -> int:
	return PIC_TILES * TILE


## `BillsPC_UpdateSelectionCursor`'s sprites for [param cursor], as
## { position, tile, flip_x, flip_y }. Empty for a list with nothing in it,
## which is where the source calls `ClearSprites` instead.
func cursor_sprites(cursor: int, rows: int) -> Array:
	if rows <= 0 or cursor < 0:
		return []
	var out: Array = []
	for sprite: Array in cursor_set():
		out.append({
			"position": Vector2i(
				int(sprite[0]), int(sprite[1]) + (cursor & 0x7) * CURSOR_STEP
			),
			"tile": int(sprite[2]),
			"flip_x": bool(sprite[3]),
			"flip_y": bool(sprite[4]),
		})
	return out


## How many objects a host has to keep around for either profile.
static func max_cursor_sprites() -> int:
	return maxi(CURSOR_SPRITES.size(), CURSOR_SPRITES_GOLD.size())


## The profile's own OAM table.
func cursor_set() -> Array:
	return CURSOR_SPRITES if _profile == RomRegistry.CRYSTAL else CURSOR_SPRITES_GOLD


func _box(indices: PackedByteArray, width: int, box: Rect2i) -> void:
	font.draw_box(
		frame_style, indices, width,
		box.position.x * TILE, box.position.y * TILE, box.size.x, box.size.y
	)


func _frame_code(
	indices: PackedByteArray, width: int, within: int, at: Vector2i
) -> void:
	font.draw_frame_code(
		frame_style, RomLayout.FRAME_FIRST_CODE + within, indices, width,
		at.x * TILE, at.y * TILE
	)


func _text(
	indices: PackedByteArray, width: int, text: String, at: Vector2i
) -> void:
	font.draw_text(text, indices, width, at.x * TILE, at.y * TILE, FONT)


func _code(indices: PackedByteArray, width: int, code: int, at: Vector2i) -> void:
	font.draw_code(code, indices, width, at.x * TILE, at.y * TILE, FONT)


## One of `PCMailGFX`'s two tiles, which sit where the battle-extra strip's own
## $5c and $5d would be: the copy is made after `LoadFontsBattleExtra`.
func _marker(
	indices: PackedByteArray, width: int, code: int, at: Vector2i
) -> void:
	if _mail.is_empty():
		return
	Gen2Font.blit_slot(
		_mail, RomLayout.PC_MAIL_TILES * TILE, code - MAIL_CODE,
		indices, width, at.x * TILE, at.y * TILE
	)
