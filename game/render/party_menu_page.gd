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
## only, and node-free, so the page can be read back headless. The one thing it
## owns itself is `InitPartyMenuGFX`'s icons, because the sprite anim structs
## behind them are per-frame state and nothing else here holds it: [method
## advance] is one pass of `PlaySpriteAnimations` over them.
##
## A row carrying `egg` is `PartyMenuCheckEgg`'s: its nickname and its icon are
## drawn and every other quality is stepped past. Only the overworld menu can
## show one; a battle party cannot hold an egg.

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

## Shadow OAM's own origin, which every sprite here is placed through.
const OAM_ORIGIN := Vector2i(8, 16)

## `InitPartyMenuIcon`'s spawn: `add $1c` over the slot number shifted four, and
## `ld e, $10`. The icon is the four `.OAMData_RedWalk` tiles at (-8,-8) from
## there, so its top-left corner is the coordinate less a tile and the origin.
const ICON_FIRST_Y: int = 0x1C
const ICON_ROW_STEP: int = 16
const ICON_TILE: int = Gen2Font.TILE

## `SpriteAnimFunc_PartyMon`'s two columns: `8 * 2` for a row the cursor is not
## on and `8 * 3` for the one it is, which is what frees column 0 for the arrow.
const ICON_X: int = 8 * 2
const ICON_SELECTED_X: int = 8 * 3

## `.Frameset_PartyMon`: two OAM sets of eight, which is nine passes each
## (`GetSpriteAnimFrame` returns the entry on the pass that loads the duration
## too), then `oamrestart`. The second set is the same four tiles four on.
const ICON_FRAME_DURATION: int = 8
const ICON_FRAMES: int = 2
const ICON_FRAME_TILES: int = 4

## `SetPartyMonIconAnimSpeed`'s `.speeds`, added to every frame's duration, and
## the same byte rotated twice into VAR2. A hurt Pokémon's icon steps and bobs
## more slowly; a red one does neither.
const ICON_SPEEDS: Array[int] = [0x00, 0x40, 0x80]
const ICON_BOBS: Array[int] = [-2, -1, 0]

## `.SpawnItemIcon`'s marker, `HeldItemIcons`' second tile, over the icon's own
## bottom-left one. Its mail sibling is unreachable here (see
## [constant RomLayout.HELD_ITEM_ICON_MAIL]).
const ICON_ITEM_TILE: int = RomLayout.HELD_ITEM_ICON_ITEM
const ICON_ITEM_QUADRANT: int = 2

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

## One sprite anim struct per member, in party order:
## `{icon, item, speed, frame, duration, var1, x, y_offset}`. Empty until
## [method advance] has been given rows to build it from.
var _icons: Array = []

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
	_blend_icons(image, rows.size())
	return image


## One pass of `PlaySpriteAnimations` over `InitPartyMenuGFX`'s structs: the
## sequence first and then the frameset, which is the order
## `DoNextFrameForAllSprites` calls them in. Called once per hardware frame by
## whoever owns the screen; the structs are rebuilt when the party behind them
## changes, the way a reopened menu respawns them.
func advance(rows: Array, cursor: int) -> void:
	if _icons.size() != rows.size():
		reset(rows)
	for index: int in _icons.size():
		var icon: Dictionary = _icons[index]
		_step_icon_sequence(icon, index == cursor)
		_step_icon_frame(icon)


## `InitPartyMenuGFX`: one struct per member, spawned in party order. FRAME
## opens at -1 and DURATION at zero, so the first pass shows the first entry.
func reset(rows: Array) -> void:
	_icons = []
	for row: Variant in rows:
		var member: Dictionary = row as Dictionary
		var speed: int = GameData.hp_bar_palette_index(Gen2BattleHud.bar_pixels(
			int(member.get("hp", 0)), int(member.get("max_hp", 0)),
			Gen2BattleHud.HP_BAR_TILES * TILE
		))
		## `PlacePartyMenuHPBar` never runs for an egg, so the speed byte behind
		## its icon is whatever the last party left in `wHPPals`. Zero here, the
		## green one, rather than a stale byte no save can reproduce.
		if bool(member.get("egg", false)):
			speed = 0
		_icons.append({
			## The strip is asked for by species rather than by icon number, so a
			## mod species drawing indices of its own animates with the rest.
			"strip": data.species_icon_indices(
				int(member.get("species", 0)), bool(member.get("egg", false))
			) if data != null else PackedByteArray(),
			"item": int(member.get("item", 0)) != 0,
			"speed": speed,
			"frame": -1,
			"duration": 0,
			"var1": 0,
			"x": ICON_X,
			"y_offset": 0,
		})


## What the icons would draw right now, so a host caching its layer knows when
## the picture behind that cache has moved.
func animation_signature() -> String:
	var parts: PackedStringArray = []
	for icon: Dictionary in _icons:
		parts.append("%d:%d:%d" % [int(icon["frame"]), int(icon["x"]), int(icon["y_offset"])])
	return ",".join(parts)


## `SpriteAnimFunc_PartyMon`, which hands the cursor's own row to
## `SpriteAnimFunc_PartyMonSwitch`. VAR1 counts only while a row is the chosen
## one, and the offset it picks changes every sixteenth pass.
func _step_icon_sequence(icon: Dictionary, selected: bool) -> void:
	if not selected:
		icon["x"] = ICON_X
		icon["y_offset"] = 0
		return
	icon["x"] = ICON_SELECTED_X
	var counter: int = int(icon["var1"])
	icon["var1"] = (counter + 1) & 0xFF
	if counter & 0x0F != 0:
		return
	icon["y_offset"] = ICON_BOBS[int(icon["speed"])] if counter & 0x10 != 0 else 0


## `GetSpriteAnimFrame` over `.Frameset_PartyMon`: count the duration down, and
## on the pass it runs out step to the next entry and load its own.
func _step_icon_frame(icon: Dictionary) -> void:
	if int(icon["duration"]) > 0:
		icon["duration"] = int(icon["duration"]) - 1
		return
	icon["frame"] = (int(icon["frame"]) + 1) % ICON_FRAMES
	icon["duration"] = (ICON_FRAME_DURATION + ICON_SPEEDS[int(icon["speed"])]) & 0xFF


## The icons over the page, in the one palette `InitPartyMenuOBPals` gives them.
## They are objects rather than tiles, so colour 0 is transparent and they are
## blended on top rather than written into the index buffer.
func _blend_icons(image: Image, count: int) -> void:
	if data == null or _icons.is_empty():
		return
	var colors: PackedColorArray = data.party_menu_icon_palette()
	if colors.size() != Gen2Palette.COLORS_PER_PIC:
		return
	var held: PackedByteArray = data.held_item_icon_indices()
	for index: int in mini(count, _icons.size()):
		var icon: Dictionary = _icons[index]
		## Shadow OAM holds nothing for a struct `UpdateAnimFrame` has not
		## reached yet, which is why FRAME opens at -1 rather than at zero.
		if int(icon["frame"]) < 0:
			continue
		var strip: PackedByteArray = icon["strip"]
		if strip.is_empty():
			continue
		var at := Vector2i(
			int(icon["x"]) - ICON_TILE - OAM_ORIGIN.x,
			ICON_FIRST_Y + index * ICON_ROW_STEP + int(icon["y_offset"])
				- ICON_TILE - OAM_ORIGIN.y
		)
		var first: int = int(icon["frame"]) * ICON_FRAME_TILES
		for quadrant: int in ICON_FRAME_TILES:
			var source: PackedByteArray = strip
			var tile: int = first + quadrant
			if quadrant == ICON_ITEM_QUADRANT and bool(icon["item"]) and not held.is_empty():
				source = held
				tile = ICON_ITEM_TILE
			_blend_tile(
				image, source, tile, colors,
				at + Vector2i((quadrant & 1) * ICON_TILE, (quadrant >> 1) * ICON_TILE)
			)


## One 8x8 tile of an index strip, clipped to the screen.
func _blend_tile(
	image: Image, strip: PackedByteArray, tile: int, colors: PackedColorArray, at: Vector2i
) -> void:
	@warning_ignore("integer_division")
	var width: int = strip.size() / Gen2Tiles.TILE_HEIGHT
	var left: int = tile * Gen2Tiles.TILE_WIDTH
	if left + Gen2Tiles.TILE_WIDTH > width:
		return
	for row: int in Gen2Tiles.TILE_HEIGHT:
		var y: int = at.y + row
		if y < 0 or y >= Gen2Screen.HEIGHT:
			continue
		for column: int in Gen2Tiles.TILE_WIDTH:
			var x: int = at.x + column
			if x < 0 or x >= Gen2Screen.WIDTH:
				continue
			var index: int = strip[row * width + left + column]
			if index == 0:
				continue
			image.set_pixel(x, y, colors[index])


func _draw_member(page: PackedByteArray, width: int, index: int, row: Dictionary) -> void:
	var step: int = index * ROW_STEP
	var hp: int = int(row.get("hp", 0))
	var max_hp: int = int(row.get("max_hp", 0))

	font.draw_text(
		String(row.get("name", "")), page, width,
		NICKNAME.x * TILE, (NICKNAME.y + step) * TILE
	)
	## Every quality below `PlacePartyNicknames` opens its loop with
	## `PartyMenuCheckEgg` and steps past the row, so an egg is a nickname and
	## an icon and nothing else. Reachable from the overworld menu only: a battle
	## party cannot hold one.
	if bool(row.get("egg", false)):
		return
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
	if bool(row.get("egg", false)):
		return
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
