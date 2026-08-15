class_name Gen2TownMapPage
extends RefCounted

## The region map (`_TownMap` and `InitPokegearTilemap.Map`) and the Pokegear's
## other three cards, on the tile grid the hardware uses.
##
## Like the trainer card this is a tilemap screen: `FillTownMap` writes one tile
## number per cell of the whole screen out of `JohtoMap` or `KantoMap`, the frame
## overwrites a few of them and only the landmark's name is printed text. So the
## page builds a map of tile numbers, colours it through `TownMapPals` and then
## resolves each number to pixels.
##
## `Pokegear_LoadGFX`'s VRAM window:
##
## | Tiles | Contents |
## |---|---|
## | $00-$2f | `TownMapGFX`, which is every tile a region map names |
## | $30-$5d | `PokegearGFX`, the card frame and its icons |
## | $60+ | the font, so printed text addresses glyphs as usual |
##
## The other three cards are the same window with one of the RLE tilemaps over
## it instead of a region map, so they are built here rather than in a page of
## their own; `Pokegear_FinishTilemap`'s icon row runs on all four.

const TILE: int = Gen2Font.TILE
const COLUMNS: int = 20
const ROWS: int = 18

const TOWN_MAP_FIRST_TILE: int = RomLayout.TOWN_MAP_FIRST_TILE
const POKEGEAR_FIRST_TILE: int = RomLayout.POKEGEAR_FIRST_TILE
const BLANK_TILE: int = 0x7F

## `_TownMap.InitTilemap`'s corner box: a lid across the top left, a wall down
## its right and a bar along row 2. The region map shows through the rest.
const TOWN_MAP_FRAME_LEFT_TILE: int = 0x06
const TOWN_MAP_FRAME_TOP_TILE: int = 0x07
const TOWN_MAP_FRAME_RIGHT_TILE: int = 0x17
const TOWN_MAP_FRAME_WALL_TILE: int = 0x16
const TOWN_MAP_FRAME_JOINT_TILE: int = 0x26
const TOWN_MAP_FRAME_TOP_WIDTH: int = 6
const TOWN_MAP_FRAME_CORNER: Vector2i = Vector2i(7, 0)
## `ld bc, NAME_LENGTH` for the bar right of the joint.
const TOWN_MAP_FRAME_BAR_AT: Vector2i = Vector2i(8, 2)
const TOWN_MAP_FRAME_BAR_WIDTH: int = 11

## `InitPokegearTilemap.Map`'s single bar under the card icons.
const CARD_BAR_ROW: int = 2

## `Pokedex_GetArea.PlaceString_MonsNest`: the top row blanked, the same bar one
## row down and the header printed from column 2.
const NEST_BAR_ROW: int = 1
const NEST_HEADER_AT: Vector2i = Vector2i(2, 0)

## `Pokegear_FinishTilemap`. The eight cells left of the name box are blanked
## with the Pokegear sheet's own blank, then one 2x2 icon is stamped per owned
## card and the Pokegear's own icon over the corner.
const CARD_BLANK_TILE: int = 0x4F
const CARD_BLANK_WIDTH: int = 8
const CARD_ICONS: Array[Dictionary] = [
	{"card": &"map", "at": Vector2i(2, 0), "tile": 0x40},
	{"card": &"phone", "at": Vector2i(4, 0), "tile": 0x44},
	{"card": &"radio", "at": Vector2i(6, 0), "tile": 0x42},
]
const CARD_POKEGEAR_ICON_AT: Vector2i = Vector2i(0, 0)
const CARD_POKEGEAR_ICON_TILE: int = 0x46
## `.PlacePokegearCardIcon`'s `add $f` after two `inc a`, which is what puts the
## lower half of an icon sixteen tiles along rather than two.
const CARD_ICON_ROW_STRIDE: int = 16

## `InitPokegearTilemap`'s other three cards, which are the same VRAM window and
## the same palettes: the screen is filled with the Pokegear sheet's own blank,
## one of `ClockTilemapRLE`, `PhoneTilemapRLE` and `RadioTilemapRLE` covers the
## top twelve rows, and `Textbox` draws the four below it.
const CARD_TEXTBOX_AT: Vector2i = Vector2i(0, 12)
const CARD_TEXTBOX_COLUMNS: int = 20
const CARD_TEXTBOX_ROWS: int = 6
## Where `PrintText` puts a line inside that box, which is one tile in and every
## second row, the way every text box on the hardware is written.
const CARD_TEXT_AT: Vector2i = Vector2i(1, 14)
const CARD_TEXT_SPACING: int = 2

## `.Clock`'s own string, and `Pokegear_UpdateClock`: a 14x5 box cleared at
## (3,5), `_GearTodayText`'s weekday at (6,6) and `PrintHoursMins` at (6,8).
const CLOCK_SWITCH_TEXT: String = " SWITCH▶"
const CLOCK_SWITCH_AT: Vector2i = Vector2i(12, 1)
const CLOCK_CLEAR_AT: Vector2i = Vector2i(3, 5)
const CLOCK_CLEAR_COLUMNS: int = 14
const CLOCK_CLEAR_ROWS: int = 5
const CLOCK_DAY_AT: Vector2i = Vector2i(6, 6)
const CLOCK_TIME_AT: Vector2i = Vector2i(6, 8)

## `UpdateRadioStation.returnafterstation`, which places the tuned station's own
## name and is the only thing the radio card prints. A dial between stations
## reaches `NoRadioStation` instead, which prints nothing.
const RADIO_STATION_AT: Vector2i = Vector2i(2, 9)

## `.PlacePhoneBars`: three fixed tiles of the signal meter, and a fourth only
## where `GetMapPhoneService` answers that there is service.
const PHONE_BARS_AT: Vector2i = Vector2i(17, 1)
const PHONE_BARS_TILE: int = 0x3C
const PHONE_SERVICE_AT: Vector2i = Vector2i(18, 2)
const PHONE_SERVICE_TILE: int = 0x3F

## `PokegearPhone_UpdateDisplayList` and `PokegearPhone_UpdateCursor`: the list
## is cleared from (1,3) and each of the four rows is two tall, the caller's own
## name at column 2 and a trainer's class under it at column 5.
const PHONE_DISPLAY_HEIGHT: int = 4
const PHONE_CLEAR_AT: Vector2i = Vector2i(1, 3)
const PHONE_CLEAR_COLUMNS: int = COLUMNS - 2
const PHONE_FIRST_ROW: int = 4
const PHONE_ROW_SPACING: int = 2
const PHONE_NAME_COLUMN: int = 2
const PHONE_CLASS_COLUMN: int = 5
const PHONE_CURSOR_COLUMN: int = 1
const PHONE_CURSOR_CODE: int = 0xED

## `PokegearPhoneContactSubmenu`, which is hand-built rather than a
## `menu_coords` menu: its box is eight tiles wide inside and as tall as the
## options are rows, its cursor sits in the column the strings' own `dwcoord`
## names, and `.UpdateCursor`'s caller places the text one tile right of it. The
## last row is always at 10, so a two-option box opens two rows lower.
const PHONE_SUBMENU_LAST_ROW: int = 10
const PHONE_SUBMENU_COLUMNS: int = 8
const PHONE_SUBMENU_CURSOR_COLUMN: int = 10

## `YesNoBox`'s own `lb bc, SCREEN_WIDTH - 6, 7`, which `_YesNoBox` turns into a
## five-by-four border from that corner.
const YES_NO_BOX: Array[int] = [14, 7, 19, 11]
const YES_NO_OPTIONS: Array[String] = ["YES", "NO"]

## `PokegearMap_UpdateLandmarkName`: a 2x12 box cleared at (8,0), the name placed
## at (9,0) and the sheet's own marker left in the corner it opened.
const NAME_BOX_AT: Vector2i = Vector2i(8, 0)
const NAME_BOX_ROWS: int = 2
const NAME_BOX_COLUMNS: int = 12
const NAME_MARKER_TILE: int = 0x34
const NAME_AT: Vector2i = Vector2i(9, 0)
## `TownMap_ConvertLineBreakCharacters` rewrites the first of these as `<LF>`,
## which `LineFeedChar` answers by dropping one row at the string's own column.
const NAME_BREAK_CODES: Array[int] = [0x1F, 0x25]

## `PAL_TOWNMAP_CITY`, the one slot `FemalePokegearPals` changes.
const CITY_PALETTE: int = 3

var font: Gen2Font = null
## Which text-box border the player chose, for the box a card draws under itself.
## The region map screens have no box and never read it.
var frame_style: int = 0
## The VRAM window, as one indices strip per tile number.
var _tiles: Dictionary = {}
## The three card tilemaps, by the names the cache keys them with.
var _cards: Dictionary = {}


## [param data] supplies the glyphs and both graphics sheets; a cache without
## them answers null rather than drawing a screen of blanks.
static func from_data(data: GameData) -> Gen2TownMapPage:
	var glyphs: Gen2Font = Gen2Font.from_data(data)
	if glyphs == null or data == null:
		return null
	var out := Gen2TownMapPage.new()
	out.font = glyphs
	out.frame_style = Gen2OptionsStore.current().textbox_frame
	out._load_sheet(data, "town_map", TOWN_MAP_FIRST_TILE, RomLayout.TOWN_MAP_TILES)
	out._load_sheet(data, "pokegear", POKEGEAR_FIRST_TILE, RomLayout.POKEGEAR_TILES)
	for card: String in RomLayout.POKEGEAR_CARD_ORDER:
		var cells: PackedByteArray = data.pokegear_card(StringName(card))
		if cells.size() == RomLayout.POKEGEAR_CARD_CELLS:
			out._cards[card] = cells
	return out


func ready() -> bool:
	return font != null and _tiles.size() >= RomLayout.TOWN_MAP_TILES + RomLayout.POKEGEAR_TILES


func _load_sheet(data: GameData, name: String, first_tile: int, count: int) -> void:
	var indices: PackedByteArray = data.tile_indices(name)
	if indices.is_empty():
		return
	var width: int = indices.size() / TILE
	for tile: int in count:
		if (tile + 1) * TILE > width:
			break
		var cell := PackedByteArray()
		cell.resize(TILE * TILE)
		for y: int in TILE:
			for x: int in TILE:
				cell[y * TILE + x] = indices[y * width + tile * TILE + x]
		_tiles[first_tile + tile] = cell


## The whole screen as tile numbers, in the order the source writes them: the
## region map over everything, then the screen's own frame, then the name.
##
## [param cards] is `wPokegearFlags`, as the card names `Pokegear_FinishTilemap`
## tests; it is read only by the Pokegear card's frame. [param name_codes] is the
## landmark's name, or the dex area's whole `<MON>'S NEST` header.
func tilemap(
	region: PackedByteArray,
	name_codes: PackedByteArray,
	screen: StringName = Gen2TownMap.SCREEN_TOWN_MAP,
	cards: Array = [],
) -> PackedInt32Array:
	var map := PackedInt32Array()
	map.resize(COLUMNS * ROWS)
	map.fill(BLANK_TILE)
	for cell: int in mini(region.size(), map.size()):
		map[cell] = region[cell]
	match screen:
		Gen2TownMap.SCREEN_POKEGEAR_CARD:
			_draw_bar(map, CARD_BAR_ROW)
			_draw_name(map, name_codes)
			_draw_card_icons(map, cards)
		Gen2TownMap.SCREEN_DEX_AREA:
			_draw_nest_header(map, name_codes)
		_:
			_draw_town_map_frame(map)
			_draw_name(map, name_codes)
	return map


## Whether the three card tilemaps are in the cache this page was built from.
func cards_ready() -> bool:
	return _cards.size() == RomLayout.POKEGEAR_CARD_ORDER.size()


## `.Clock`: the card, its own SWITCH label, the cleared face, the weekday and
## `PrintHoursMins`' twelve-hour reading. [param minute] and [param hour] are the
## world clock's; [param text] is `PokegearPressButtonText`.
func clock_tilemap(
	owned: Array, weekday: int, hour: int, minute: int, text: String
) -> PackedInt32Array:
	var map: PackedInt32Array = _card_base(&"clock", text)
	_draw_string(map, CLOCK_SWITCH_AT, CLOCK_SWITCH_TEXT)
	for row: int in CLOCK_CLEAR_ROWS:
		for column: int in CLOCK_CLEAR_COLUMNS:
			_put(map, CLOCK_CLEAR_AT + Vector2i(column, row), BLANK_TILE)
	_draw_string(map, CLOCK_DAY_AT, Gen2TextStream.weekday_name(weekday) + "DAY")
	_draw_string(map, CLOCK_TIME_AT, _clock_reading(hour, minute))
	_draw_card_icons(map, owned)
	return map


## `PrintHoursMins`: the hour space-padded to two tiles, the minute with its
## leading zero, and AM or PM one tile past it. Midnight and noon are both
## printed as twelve, which is what its two branches do with a zero hour.
static func _clock_reading(hour: int, minute: int) -> String:
	var hour24: int = posmod(hour, 24)
	var reading: int = hour24 % 12
	if reading == 0:
		reading = 12
	return "%2d:%02d %s" % [reading, posmod(minute, 60), "AM" if hour24 < 12 else "PM"]


## `.Radio`, whose card prints nothing but the tuned station's own name.
func radio_tilemap(owned: Array, station: String) -> PackedInt32Array:
	var map: PackedInt32Array = _card_base(&"radio", "")
	if not station.is_empty():
		_draw_string(map, RADIO_STATION_AT, station)
	_draw_card_icons(map, owned)
	return map


## `.Phone` and `PokegearPhone_UpdateDisplayList`. [param rows] is the window of
## contacts on screen, each `{ name, class }`, [param cursor] the row the arrow
## is on and [param service] `GetMapPhoneService`'s answer.
func phone_tilemap(
	owned: Array, rows: Array, cursor: int, service: bool, text: String
) -> PackedInt32Array:
	var map: PackedInt32Array = _card_base(&"phone", text)
	_put(map, PHONE_BARS_AT, PHONE_BARS_TILE)
	_put(map, PHONE_BARS_AT + Vector2i(1, 0), PHONE_BARS_TILE + 1)
	_put(map, PHONE_BARS_AT + Vector2i(0, 1), PHONE_BARS_TILE + 2)
	if service:
		_put(map, PHONE_SERVICE_AT, PHONE_SERVICE_TILE)
	for row: int in PHONE_DISPLAY_HEIGHT * 2 + 1:
		for column: int in PHONE_CLEAR_COLUMNS:
			_put(map, PHONE_CLEAR_AT + Vector2i(column, row), BLANK_TILE)
	for index: int in mini(rows.size(), PHONE_DISPLAY_HEIGHT):
		var entry: Dictionary = rows[index]
		var top: int = PHONE_FIRST_ROW + index * PHONE_ROW_SPACING
		var caller: String = String(entry.get("name", ""))
		var class_name_text: String = String(entry.get("class", ""))
		# `GetCallerName`: a trainer's own name carries a colon and their class
		# goes on the line below; every other caller is one line.
		_draw_string(
			map, Vector2i(PHONE_NAME_COLUMN, top),
			caller + ":" if not class_name_text.is_empty() else caller
		)
		if not class_name_text.is_empty():
			_draw_string(map, Vector2i(PHONE_CLASS_COLUMN, top + 1), class_name_text)
	if cursor >= 0 and cursor < PHONE_DISPLAY_HEIGHT:
		_put(
			map,
			Vector2i(PHONE_CURSOR_COLUMN, PHONE_FIRST_ROW + cursor * PHONE_ROW_SPACING),
			PHONE_CURSOR_CODE
		)
	_draw_card_icons(map, owned)
	return map


## What every card opens with: `InitPokegearTilemap`'s screen-wide fill with the
## Pokegear sheet's blank, the card's own twelve rows, and the text box each of
## the three draws under them.
func _card_base(card: StringName, text: String) -> PackedInt32Array:
	var map := PackedInt32Array()
	map.resize(COLUMNS * ROWS)
	map.fill(CARD_BLANK_TILE)
	var cells: PackedByteArray = _cards.get(String(card), PackedByteArray())
	for cell: int in mini(cells.size(), map.size()):
		map[cell] = cells[cell]
	_draw_textbox(map, text)
	return map


## `Textbox`: the chosen frame's own six tiles around a cleared interior, with
## the text printed a tile in and on every second row.
func _draw_textbox(map: PackedInt32Array, text: String) -> void:
	_draw_box(map, CARD_TEXTBOX_AT, Vector2i(CARD_TEXTBOX_COLUMNS, CARD_TEXTBOX_ROWS))
	var line: int = 0
	for row_text: String in text.split("\n", false):
		_draw_string(map, CARD_TEXT_AT + Vector2i(0, line * CARD_TEXT_SPACING), row_text)
		line += 1


## `PokegearPhoneContactSubmenu`, over whichever card is up. [param options] is
## the two- or three-row list `CheckCanDeletePhoneNumber` picks between.
func draw_phone_submenu(
	map: PackedInt32Array, options: Array, cursor: int
) -> void:
	var top: int = PHONE_SUBMENU_LAST_ROW - options.size() * 2
	_draw_box(
		map, Vector2i(PHONE_SUBMENU_CURSOR_COLUMN - 1, top),
		Vector2i(PHONE_SUBMENU_COLUMNS + 2, options.size() * 2 + 2)
	)
	for index: int in options.size():
		var at := Vector2i(PHONE_SUBMENU_CURSOR_COLUMN, top + 2 + index * 2)
		_draw_string(map, at + Vector2i(1, 0), String(options[index]))
		if index == cursor:
			_put(map, at, PHONE_CURSOR_CODE)


## `YesNoBox`, which the DELETE row opens over the card.
func draw_yes_no(map: PackedInt32Array, cursor: int) -> void:
	var box: Gen2MenuBox = Gen2MenuBox.from_coords(
		YES_NO_BOX[0], YES_NO_BOX[1], YES_NO_BOX[2], YES_NO_BOX[3],
		Gen2MenuBox.STATICMENU_CURSOR | Gen2MenuBox.STATICMENU_NO_TOP_SPACING
	)
	_draw_box(map, box.border_position(), box.border_size())
	for index: int in YES_NO_OPTIONS.size():
		_draw_string(map, box.item_position(index), YES_NO_OPTIONS[index])
		if index == cursor:
			_put(map, box.cursor_position(index), PHONE_CURSOR_CODE)


## `Textbox`'s border and its cleared interior, as the tile numbers
## `TextBoxBorder` writes: [param size] counts the border in.
func _draw_box(map: PackedInt32Array, at: Vector2i, size: Vector2i) -> void:
	var first: int = RomLayout.FRAME_FIRST_CODE
	var right: int = at.x + size.x - 1
	var bottom: int = at.y + size.y - 1
	for column: int in range(at.x + 1, right):
		_put(map, Vector2i(column, at.y), first + RomLayout.FRAME_HORIZONTAL)
		_put(map, Vector2i(column, bottom), first + RomLayout.FRAME_HORIZONTAL)
	for row: int in range(at.y + 1, bottom):
		_put(map, Vector2i(at.x, row), first + RomLayout.FRAME_VERTICAL)
		_put(map, Vector2i(right, row), first + RomLayout.FRAME_VERTICAL)
		for column: int in range(at.x + 1, right):
			_put(map, Vector2i(column, row), BLANK_TILE)
	_put(map, at, first + RomLayout.FRAME_TOP_LEFT)
	_put(map, Vector2i(right, at.y), first + RomLayout.FRAME_TOP_RIGHT)
	_put(map, Vector2i(at.x, bottom), first + RomLayout.FRAME_BOTTOM_LEFT)
	_put(map, Vector2i(right, bottom), first + RomLayout.FRAME_BOTTOM_RIGHT)


func _draw_string(map: PackedInt32Array, at: Vector2i, text: String) -> void:
	var cell: Vector2i = at
	for code: int in Gen2Text.encode(text):
		_put(map, cell, code)
		cell.x += 1


func _draw_town_map_frame(map: PackedInt32Array) -> void:
	for column: int in TOWN_MAP_FRAME_TOP_WIDTH:
		_put(map, Vector2i(1 + column, 0), TOWN_MAP_FRAME_TOP_TILE)
	_put(map, Vector2i.ZERO, TOWN_MAP_FRAME_LEFT_TILE)
	_put(map, TOWN_MAP_FRAME_CORNER, TOWN_MAP_FRAME_RIGHT_TILE)
	_put(map, TOWN_MAP_FRAME_CORNER + Vector2i(0, 1), TOWN_MAP_FRAME_WALL_TILE)
	_put(map, TOWN_MAP_FRAME_CORNER + Vector2i(0, 2), TOWN_MAP_FRAME_JOINT_TILE)
	for column: int in TOWN_MAP_FRAME_BAR_WIDTH:
		_put(map, TOWN_MAP_FRAME_BAR_AT + Vector2i(column, 0), TOWN_MAP_FRAME_TOP_TILE)
	_put(map, Vector2i(COLUMNS - 1, TOWN_MAP_FRAME_BAR_AT.y), TOWN_MAP_FRAME_RIGHT_TILE)


func _draw_bar(map: PackedInt32Array, row: int) -> void:
	for column: int in range(1, COLUMNS - 1):
		_put(map, Vector2i(column, row), TOWN_MAP_FRAME_TOP_TILE)
	_put(map, Vector2i(0, row), TOWN_MAP_FRAME_LEFT_TILE)
	_put(map, Vector2i(COLUMNS - 1, row), TOWN_MAP_FRAME_RIGHT_TILE)


## `.PlaceString_MonsNest`, which has no name box: the top row is blanked whole
## and the header written over it, so a long name runs to the screen's edge.
func _draw_nest_header(map: PackedInt32Array, header_codes: PackedByteArray) -> void:
	for column: int in COLUMNS:
		_put(map, Vector2i(column, 0), BLANK_TILE)
	_draw_bar(map, NEST_BAR_ROW)
	var at: Vector2i = NEST_HEADER_AT
	for code: int in header_codes:
		_put(map, at, code)
		at.x += 1


## `Pokegear_FinishTilemap`, which runs after the name is placed and so blanks
## only the eight cells left of the name box.
func _draw_card_icons(map: PackedInt32Array, cards: Array) -> void:
	for row: int in 2:
		for column: int in CARD_BLANK_WIDTH:
			_put(map, Vector2i(column, row), CARD_BLANK_TILE)
	for icon: Dictionary in CARD_ICONS:
		if StringName(icon["card"]) in cards:
			_draw_card_icon(map, icon["at"], int(icon["tile"]))
	_draw_card_icon(map, CARD_POKEGEAR_ICON_AT, CARD_POKEGEAR_ICON_TILE)


func _draw_card_icon(map: PackedInt32Array, at: Vector2i, tile: int) -> void:
	_put(map, at, tile)
	_put(map, at + Vector2i(1, 0), tile + 1)
	_put(map, at + Vector2i(0, 1), tile + CARD_ICON_ROW_STRIDE)
	_put(map, at + Vector2i(1, 1), tile + CARD_ICON_ROW_STRIDE + 1)


## `PokegearMap_UpdateLandmarkName` and `TownMap_ConvertLineBreakCharacters`
## together: the box is cleared, the name placed at (9,0) with its one break
## dropping a row, and the marker written into the corner afterwards.
func _draw_name(map: PackedInt32Array, name_codes: PackedByteArray) -> void:
	for row: int in NAME_BOX_ROWS:
		for column: int in NAME_BOX_COLUMNS:
			_put(map, NAME_BOX_AT + Vector2i(column, row), BLANK_TILE)
	var at: Vector2i = NAME_AT
	var broken: bool = false
	for code: int in name_codes:
		if not broken and code in NAME_BREAK_CODES:
			broken = true
			at = Vector2i(NAME_AT.x, NAME_AT.y + 1)
			continue
		_put(map, at, code)
		at.x += 1
	_put(map, NAME_BOX_AT, NAME_MARKER_TILE)


## `TownMapPals`, as one palette slot per tile.
func attributes(data: GameData, map: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(map.size())
	for cell: int in map.size():
		out[cell] = data.town_map_palette_of(map[cell])
	return out


## The whole screen as pixels, each tile coloured through the palette
## `TownMapPals` gave it. [param female] is Kris's own city colours.
##
## This cannot go through [method Gen2PicImage.from_indices] whole: the screen is
## six palettes at once.
func image(data: GameData, map: PackedInt32Array, female: bool = false) -> Image:
	var indices: PackedByteArray = compose(map)
	var slots: PackedInt32Array = attributes(data, map)
	var out := Image.create(Gen2Screen.WIDTH, Gen2Screen.HEIGHT, false, Image.FORMAT_RGBA8)
	var palettes: Array = []
	for slot: int in RomLayout.TOWN_MAP_PALETTES:
		palettes.append(data.town_map_palette(slot, female))
	for row: int in ROWS:
		for column: int in COLUMNS:
			var palette: PackedColorArray = palettes[
				clampi(slots[row * COLUMNS + column], 0, palettes.size() - 1)
			]
			if palette.is_empty():
				continue
			for y: int in TILE:
				for x: int in TILE:
					var at_x: int = column * TILE + x
					var at_y: int = row * TILE + y
					out.set_pixel(at_x, at_y, palette[
						clampi(indices[at_y * Gen2Screen.WIDTH + at_x], 0, palette.size() - 1)
					])
	return out


## Resolves every tile number to pixels: the two graphics sheets out of the VRAM
## window, a card's text box out of the chosen frame, everything else out of the
## font.
func compose(map: PackedInt32Array) -> PackedByteArray:
	var width: int = COLUMNS * TILE
	var indices := PackedByteArray()
	indices.resize(width * ROWS * TILE)
	for row: int in ROWS:
		for column: int in COLUMNS:
			var tile: int = map[row * COLUMNS + column]
			var at := Vector2i(column * TILE, row * TILE)
			if _tiles.has(tile):
				_blit(indices, width, _tiles[tile], at)
			elif tile >= RomLayout.FRAME_FIRST_CODE \
				and tile < RomLayout.FRAME_FIRST_CODE + RomLayout.FRAME_TILES:
				font.draw_frame_code(frame_style, tile, indices, width, at.x, at.y)
			elif tile != BLANK_TILE:
				font.draw_code(tile, indices, width, at.x, at.y, Gen2Text.FONT_MAIN)
	return indices


func _put(map: PackedInt32Array, at: Vector2i, tile: int) -> void:
	if at.x < 0 or at.y < 0 or at.x >= COLUMNS or at.y >= ROWS:
		return
	map[at.y * COLUMNS + at.x] = tile


func _blit(
	indices: PackedByteArray, width: int, cell: PackedByteArray, at: Vector2i
) -> void:
	for y: int in TILE:
		for x: int in TILE:
			indices[(at.y + y) * width + at.x + x] = cell[y * TILE + x]
