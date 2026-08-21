class_name Gen2StatsScreenPage
extends RefCounted

## The stats screen (`engine/pokemon/stats_screen.asm`), on the tile grid the
## hardware uses.
##
## `StatsScreen_InitUpperHalf` draws the top seven rows once and each of
## `LoadPinkPage`, `LoadGreenPage` and `LoadBluePage` fills the ten rows under
## the divider, so the page number picks the lower half and nothing else. An egg
## replaces the whole screen with `EggStatsScreen` instead.
##
## `StatsScreen_LoadFont` is `_LoadFontsBattleExtra` plus the bar borders and
## `LoadStatsScreenPageTilesGFX`, so every glyph here is the battle-extra strip's
## (`<LV>`, `<ID>`, `№`, `◀`) and the dividers, the page indicators, the exp
## bar's end caps and `⁂` are tiles off [method Gen2BattleTiles.stats_page].
##
## Node-free: it writes indices into a buffer, so a page can be drawn and read
## back headless. The Pokémon's own pic is not in that buffer; it has its own
## palette and is composed over the page by the screen.

const TILE: int = Gen2Font.TILE
const COLUMNS: int = 20
const ROWS: int = 18

## `stats_screen.asm`'s own page constants.
const PINK_PAGE: int = 1
const GREEN_PAGE: int = 2
const BLUE_PAGE: int = 3
## The cartridge's three. A mod adds its own after the blue page; see
## [method page_count].
const NUM_PAGES: int = 3
## The most pages the upper half can indicate. The run of 2x2 blocks is centred
## against the right arrow and the left arrow moves with it, so a sixth block
## would stand on the front pic's own cell.
const MAX_PAGES: int = 5

## Everything on this screen prints with the battle-extra strip loaded.
const FONT: StringName = Gen2Text.FONT_BATTLE_EXTRA

## Codes the source places as bytes rather than printing as a string.
const CODE_NUMERO: int = 0x74
const CODE_ID: int = 0x73
const CODE_LEVEL: int = 0x6E
const CODE_DOT: int = 0xF2
const CODE_SLASH: int = 0xF3
const CODE_LEFT_ARROW: int = 0x71
const CODE_RIGHT_ARROW: int = 0xED
const CODE_MALE: int = 0xEF
const CODE_FEMALE: int = 0xF5

## `StatsScreen_InitUpperHalf`, every position its own `hlcoord`.
const DEX_LABEL: Vector2i = Vector2i(8, 0)
const DEX_NUMBER: Vector2i = Vector2i(10, 0)
const DEX_DIGITS: int = 3
const HEADER_LEVEL: Vector2i = Vector2i(14, 0)
const GENDER: Vector2i = Vector2i(18, 0)
const SHINY: Vector2i = Vector2i(19, 0)
const NICKNAME: Vector2i = Vector2i(8, 2)
const SPECIES_SLASH: Vector2i = Vector2i(9, 4)
const DIVIDER_ROW: int = 7
const PAGE_RIGHT_ARROW: Vector2i = Vector2i(19, 6)
const PAGE_ARROW_ROW: int = 6

## `StatsScreen_LoadPageIndicators`: three 2x2 blocks, one per page, the last
## ending against the right arrow. See [method page_indicators], which is where
## a fourth or fifth goes.
const PAGE_INDICATORS: Array[Vector2i] = [
	Vector2i(13, 5), Vector2i(15, 5), Vector2i(17, 5),
]
const PAGE_INDICATOR_ROW: int = 5
const PAGE_INDICATOR_STEP: int = 2
## The rightmost block's column, which the source's third indicator sits on and
## every page count keeps.
const PAGE_INDICATOR_LAST_COLUMN: int = 17

## `hlcoord 0, 0`, and `PrepMonFrontpic` centres a seven-tile cell there.
const PIC_AT: Vector2i = Vector2i(0, 0)
const PIC_TILES: int = 7

## `LoadPinkPage`. `DrawPlayerHP` lays "HP:", six bar tiles and a cap at (0,9)
## and the numbers a row under it; the page then writes $41 over the cap.
const HP_BAR: Vector2i = Vector2i(0, 9)
const HP_NUMBERS: Vector2i = Vector2i(1, 10)
const HP_DIGITS: int = 3
const POKERUS_DOT: Vector2i = Vector2i(8, 8)
const STATUS_LABEL: Vector2i = Vector2i(0, 12)
const TYPE_LABEL: Vector2i = Vector2i(0, 14)
const STATUS_AT: Vector2i = Vector2i(6, 13)
const POKERUS_AT: Vector2i = Vector2i(1, 13)
const TYPES_AT: Vector2i = Vector2i(1, 15)
const PINK_DIVIDER_COLUMN: int = 9
const LOWER_FIRST_ROW: int = 8
const LOWER_ROWS: int = 10
const EXP_POINTS_LABEL: Vector2i = Vector2i(10, 9)
const EXP_POINTS_AT: Vector2i = Vector2i(13, 10)
const EXP_DIGITS: int = 7
const LEVEL_UP_LABEL: Vector2i = Vector2i(10, 12)
const EXP_TO_NEXT_AT: Vector2i = Vector2i(13, 13)
const TO_LABEL: Vector2i = Vector2i(14, 14)
const NEXT_LEVEL_AT: Vector2i = Vector2i(17, 14)
const EXP_BAR_AT: Vector2i = Vector2i(11, 16)
const EXP_BAR_LEFT_CAP: Vector2i = Vector2i(10, 16)
const EXP_BAR_RIGHT_CAP: Vector2i = Vector2i(19, 16)

const STATUS_TYPE_TOP: String = "STATUS/"
const STATUS_TYPE_BOTTOM: String = "TYPE/"
const OK_STRING: String = "OK "
const EXP_POINT_STRING: String = "EXP POINTS"
const LEVEL_UP_STRING: String = "LEVEL UP"
const TO_STRING: String = "TO"
const POKERUS_STRING: String = "#RUS"

## `PlaceNonFaintStatus`' own strings and the FNT `PlaceStatusString` reaches
## before it ever reads the byte, which is [Gen2PartyMenuPage]'s set as well.
const STATUS_STRINGS: Dictionary = Gen2PartyMenuPage.STATUS_STRINGS
const FAINTED_STRING: String = Gen2PartyMenuPage.FAINTED_STRING

## `LoadGreenPage`.
const ITEM_LABEL: Vector2i = Vector2i(0, 8)
const ITEM_AT: Vector2i = Vector2i(8, 8)
const MOVE_LABEL: Vector2i = Vector2i(0, 10)
const MOVES_AT: Vector2i = Vector2i(8, 10)
const MOVE_PP_AT: Vector2i = Vector2i(12, 11)
const ITEM_STRING: String = "ITEM"
const MOVE_STRING: String = "MOVE"
const THREE_DASHES: String = "---"

## `wListMovesLineSpacing` is `SCREEN_WIDTH * 2` on both screens that list moves,
## so a row is two tiles below the one above it.
const MOVE_ROW_STEP: int = 2
const MAX_MOVES: int = 4
## `ListMovePP`: two digits either side of the slash, and "PP" is two copies of
## the stats sheet's own P.
const PP_DIGITS: int = 2
const PP_LABEL_TILE: int = 0x3E

## `LoadBluePage`.
const ID_LABEL: Vector2i = Vector2i(0, 9)
const OT_LABEL: Vector2i = Vector2i(0, 12)
const ID_NUMBER_AT: Vector2i = Vector2i(2, 10)
const ID_DIGITS: int = 5
const OT_NAME_AT: Vector2i = Vector2i(2, 13)
const CAUGHT_GENDER_AT: Vector2i = Vector2i(9, 13)
## `constants/pokemon_data_constants.asm`' CAUGHT_GENDER_MASK, read off the whole
## caught-data byte the way `.PlaceOTInfo` reads it.
const CAUGHT_GENDER_MASK: int = 0x80
const BLUE_DIVIDER_COLUMN: int = 10
const STAT_NAMES_AT: Vector2i = Vector2i(11, 8)
const OT_STRING: String = "OT/"

## `PrintTempMonStats`' own five names and the spacing the two callers pass:
## the stats screen 6 and the battle's level-up box 4, which is the column the
## numbers land in relative to the names.
const STAT_NAMES: Array[String] = [
	"ATTACK", "DEFENSE", "SPCL.ATK", "SPCL.DEF", "SPEED",
]
const STAT_KEYS: Array[String] = [
	"attack", "defense", "sp_attack", "sp_defense", "speed",
]
const STAT_ROW_STEP: int = 2
const STAT_DIGITS: int = 3
const STATS_SPACING: int = 6

## `EggStatsScreen`.
const EGG_LABEL: Vector2i = Vector2i(8, 1)
const EGG_ID_LABEL: Vector2i = Vector2i(8, 3)
const EGG_OT_LABEL: Vector2i = Vector2i(8, 5)
const EGG_ID_MARKS: Vector2i = Vector2i(11, 3)
const EGG_OT_MARKS: Vector2i = Vector2i(11, 5)
const EGG_TEXT_AT: Vector2i = Vector2i(1, 9)
const EGG_STRING: String = "EGG"
const FIVE_QUESTION_MARKS: String = "?????"

## The four hatch hints and the `wTempMonHappiness` each is chosen under, which
## is the egg's remaining step counter rather than a happiness value.
const EGG_SOON_STEPS: int = 6
const EGG_CLOSE_STEPS: int = 11
const EGG_MORE_TIME_STEPS: int = 41
const EGG_MESSAGES: Array[String] = [
	"It's making sounds\ninside. It's going\nto hatch soon!",
	"It moves around\ninside sometimes.\nIt must be close\nto hatching.",
	"Wonder what's\ninside? It needs\nmore time, though.",
	"This EGG needs a\nlot more time to\nhatch.",
]

var font: Gen2Font = null
var tiles: Gen2BattleTiles = null
var hud: Gen2BattleHud = null


static func from_data(data: GameData) -> Gen2StatsScreenPage:
	var glyphs: Gen2Font = Gen2Font.from_data(data)
	var page_tiles: Gen2BattleTiles = Gen2BattleTiles.stats_page(data)
	var panels: Gen2BattleHud = Gen2BattleHud.from_data(data)
	if glyphs == null or page_tiles == null or panels == null:
		return null
	var out := Gen2StatsScreenPage.new()
	out.font = glyphs
	out.tiles = page_tiles
	out.hud = panels
	return out


## Where the screen puts the front pic, in pixels, and how wide the cell is.
static func pic_position() -> Vector2i:
	return PIC_AT * TILE


static func pic_size() -> int:
	return PIC_TILES * TILE


## How many pages the screen turns between: the cartridge's three plus whatever
## mods have registered, capped at [constant MAX_PAGES]. Every page number in
## this screen is one-based off [constant PINK_PAGE], so the last is this.
static func page_count() -> int:
	return mini(NUM_PAGES + Gen2ModHost.instance().stats_pages().size(), MAX_PAGES)


## The 2x2 indicator blocks for [param count] pages. The run ends against the
## right arrow on [constant PAGE_INDICATOR_LAST_COLUMN] whatever the count, so
## the source's own three are unmoved and extra blocks grow leftward.
static func page_indicators(count: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var first: int = PAGE_INDICATOR_LAST_COLUMN - (count - 1) * PAGE_INDICATOR_STEP
	for index: int in count:
		out.append(Vector2i(first + index * PAGE_INDICATOR_STEP, PAGE_INDICATOR_ROW))
	return out


## The left arrow, one column left of the first indicator, which is where the
## source's own sits for three pages.
static func page_left_arrow(count: int) -> Vector2i:
	return Vector2i(page_indicators(count)[0].x - 1, PAGE_ARROW_ROW)


## The `build` Callables of the pages past the blue one, in the order they are
## turned to.
static func extra_page_builders() -> Array:
	var out: Array = []
	for entry: Dictionary in Gen2ModHost.instance().stats_pages():
		out.append(entry["build"])
	return out


## The hatch hint `EggStatsScreen` picks for a step counter.
static func egg_message(steps: int) -> String:
	if steps < EGG_SOON_STEPS:
		return EGG_MESSAGES[0]
	if steps < EGG_CLOSE_STEPS:
		return EGG_MESSAGES[1]
	if steps < EGG_MORE_TIME_STEPS:
		return EGG_MESSAGES[2]
	return EGG_MESSAGES[3]


## The whole 160x144 screen as palette indices. [param page] is
## [method Gen2StatsScreen.snapshot].
func draw(page: Dictionary) -> PackedByteArray:
	var indices := PackedByteArray()
	indices.resize(COLUMNS * TILE * ROWS * TILE)
	if font == null:
		return indices
	if bool(page.get("egg", false)):
		_draw_egg(page, indices)
		return indices
	_draw_upper(page, indices)
	match int(page.get("page", PINK_PAGE)):
		GREEN_PAGE:
			_draw_green(page, indices)
		BLUE_PAGE:
			_draw_blue(page, indices)
		var number when number > BLUE_PAGE:
			_draw_registered(page, indices, number - BLUE_PAGE - 1)
		_:
			_draw_pink(page, indices)
	return indices


## `_CGB_StatsScreenHPPals`' attrmap, as (x, y, width, height, palette) boxes
## over the zeroes `WipeAttrmap` leaves: the upper half on the mon's own palette,
## the exp bar's ten cells on the exp palette, and one palette per 2x2 page
## indicator from slot [constant FIRST_PAGE_SLOT] on. The source's three blocks
## are three `FillBoxCGB` calls at fixed columns; here they follow
## [method page_indicators], so a registered page's block is coloured like the
## cartridge's are.
const MON_ROWS: int = 8
const EXP_ATTR_AT: Vector2i = Vector2i(10, 16)
const EXP_ATTR_WIDTH: int = 10
const MON_SLOT: int = 1
const EXP_SLOT: int = 2
const FIRST_PAGE_SLOT: int = 3


static func attributes(count: int = NUM_PAGES) -> PackedInt32Array:
	var boxes: Array = [
		[0, 0, COLUMNS, MON_ROWS, MON_SLOT],
		[EXP_ATTR_AT.x, EXP_ATTR_AT.y, EXP_ATTR_WIDTH, 1, EXP_SLOT],
	]
	var indicators: Array[Vector2i] = page_indicators(count)
	for index: int in indicators.size():
		boxes.append([
			indicators[index].x, indicators[index].y, PAGE_INDICATOR_STEP,
			PAGE_INDICATOR_STEP, FIRST_PAGE_SLOT + index,
		])
	return Gen2PicImage.attribute_boxes(boxes, COLUMNS, ROWS)


## The page as pixels. The hardware gives every tile a palette and one index
## buffer carries one, so the HP bar, the exp bar, the front pic's own square and
## the three page indicators are the attrmap rather than four blended layers.
## Slot 0 is the HP palette, which is what `WipeAttrmap` leaves every other cell on.
##
## `LoadStatsScreenPals` writes the open page's colour over colour 0 of the HP
## and exp palettes, which is what tints the lower screen pink, green or blue.
## An egg never reaches it: `EggStatsInit` jumps past `StatsScreen_LoadPage`, so
## its screen keeps the white both palettes came in with.
func render(page: Dictionary, data: GameData) -> Image:
	var indices: PackedByteArray = draw(page)
	var width: int = COLUMNS * TILE
	if data == null:
		return Gen2PicImage.from_indices(
			indices, width, ROWS * TILE,
			Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))
		)

	var egg: bool = bool(page.get("egg", false))
	var number: int = int(page.get("page", PINK_PAGE))
	var hp: int = int(page.get("hp", 0))
	var lit: int = Gen2BattleHud.bar_pixels(
		hp, int(page.get("max_hp", 0)), Gen2BattleHud.HP_BAR_TILES * TILE
	)
	var tint: Color = Color.WHITE if egg else data.stats_page_tint(number)
	var palettes: Array = [
		_tinted(data.bar_palette(GameData.hp_bar_palette_name(lit)), tint),
		data.egg_palette() if egg \
			else data.palette(int(page.get("species", 0)), bool(page.get("shiny", false))),
		_tinted(data.bar_palette(GameData.EXP_BAR_PALETTE), tint),
	]
	var count: int = page_count()
	for index: int in count:
		palettes.append(data.stats_page_palette(PINK_PAGE + index))
	return Gen2PicImage.from_attributes(
		indices, width, ROWS * TILE, attributes(count), COLUMNS, palettes
	)


## `LoadStatsScreenPals`' two writes, which replace colour 0 and nothing else.
func _tinted(palette: PackedColorArray, colour: Color) -> PackedColorArray:
	if palette.is_empty():
		return palette
	var out: PackedColorArray = palette.duplicate()
	out[0] = colour
	return out


## `PrintTempMonStats`: the five names down one column and the five numbers down
## another, both stepping two rows. Shared with the battle's own level-up box,
## which passes a spacing of four instead of six.
func draw_stats(
	into: PackedByteArray, width: int, at: Vector2i, stats: Dictionary,
	spacing: int = STATS_SPACING
) -> void:
	for placement: Dictionary in stats_placements(at, stats, spacing):
		_text(into, width, String(placement["text"]), placement["at"])


## The same ten strings as `PlaceString` calls, for a caller that draws them
## through [method Gen2MenuPage.draw]'s extras rather than into a page: the
## battle's level-up box is a plain `Textbox`, not a stats screen.
static func stats_placements(
	at: Vector2i, stats: Dictionary, spacing: int = STATS_SPACING
) -> Array:
	var out: Array = []
	for index: int in STAT_NAMES.size():
		out.append({
			"text": STAT_NAMES[index], "at": at + Vector2i(0, index * STAT_ROW_STEP),
		})
	var numbers: Vector2i = at + Vector2i(spacing, 1)
	for index: int in STAT_KEYS.size():
		out.append({
			"text": str(int(stats.get(STAT_KEYS[index], 0))).lpad(STAT_DIGITS),
			"at": numbers + Vector2i(0, index * STAT_ROW_STEP),
		})
	return out


## `StatsScreen_InitUpperHalf` plus `StatsScreen_LoadPageIndicators`, which
## `.ClearBox` runs for whichever page is being loaded.
func _draw_upper(page: Dictionary, into: PackedByteArray) -> void:
	var width: int = COLUMNS * TILE
	_code(into, width, CODE_NUMERO, DEX_LABEL)
	_code(into, width, CODE_DOT, DEX_LABEL + Vector2i(1, 0))
	## PRINTNUM_LEADINGZEROS, so a two-digit dex number keeps its column.
	_text(into, width, "%0*d" % [DEX_DIGITS, int(page.get("dex_number", 0))], DEX_NUMBER)
	draw_level(into, width, HEADER_LEVEL, int(page.get("level", 0)))
	_text(into, width, String(page.get("nickname", "")), NICKNAME)
	_gender(into, width, GENDER, StringName(page.get("gender", &"")))
	if bool(page.get("shiny", false)):
		tiles.draw(Gen2BattleTiles.SHINY, into, width, SHINY.x * TILE, SHINY.y * TILE)
	_code(into, width, CODE_SLASH, SPECIES_SLASH)
	_text(into, width, String(page.get("species_name", "")), SPECIES_SLASH + Vector2i(1, 0))

	## `StatsScreen_PlaceHorizontalDivider` writes the empty bar tile across the
	## whole width, which is why the divider is the same tile as an empty bar.
	tiles.draw_run(
		Gen2BattleTiles.HP_BAR_EMPTY, COLUMNS, into, width, 0, DIVIDER_ROW * TILE
	)
	var count: int = page_count()
	_code(into, width, CODE_LEFT_ARROW, page_left_arrow(count))
	_code(into, width, CODE_RIGHT_ARROW, PAGE_RIGHT_ARROW)
	_page_indicators(into, width, int(page.get("page", PINK_PAGE)), count)


## Three 2x2 blocks, the open page's drawn from the large square instead of the
## small one. The source writes the four tiles in the order top-left, top-right,
## bottom-left, bottom-right off one incrementing tile number.
func _page_indicators(
	into: PackedByteArray, width: int, open_page: int, count: int
) -> void:
	var blocks: Array[Vector2i] = page_indicators(count)
	for index: int in blocks.size():
		var first: int = Gen2BattleTiles.PAGE_SQUARE_LARGE \
			if index + PINK_PAGE == open_page else Gen2BattleTiles.PAGE_SQUARE_SMALL
		var at: Vector2i = blocks[index]
		for quadrant: int in 4:
			@warning_ignore("integer_division")
			var offset := Vector2i(quadrant % 2, quadrant / 2)
			tiles.draw(
				first + quadrant, into, width,
				(at.x + offset.x) * TILE, (at.y + offset.y) * TILE
			)


func _draw_pink(page: Dictionary, into: PackedByteArray) -> void:
	var width: int = COLUMNS * TILE
	var hp: int = int(page.get("hp", 0))
	var max_hp: int = int(page.get("max_hp", 0))
	hud.draw_bar_frame(into, width, HP_BAR, Gen2BattleTiles.HP_BAR_END)
	hud.draw_hp_bar(into, width, HP_BAR, hp, max_hp)
	## The page writes its own cap over `DrawBattleHPBar`'s, which is the one
	## piece of the bar that comes off the stats sheet rather than the HUD's.
	tiles.draw(
		Gen2BattleTiles.EXP_BAR_RIGHT_CAP, into, width,
		(HP_BAR.x + 8) * TILE, HP_BAR.y * TILE
	)
	_text(
		into, width, "%s/%s" % [str(hp).lpad(HP_DIGITS), str(max_hp).lpad(HP_DIGITS)],
		HP_NUMBERS
	)

	_text(into, width, STATUS_TYPE_TOP, STATUS_LABEL)
	_text(into, width, STATUS_TYPE_BOTTOM, TYPE_LABEL)
	## `wTempMonPokerusStatus`: the low nibble is the days left and the high one
	## the strain, so a mon that has had it and recovered is a dot and one that
	## still has it prints `#RUS` where the status would go.
	var pokerus: int = int(page.get("pokerus", 0))
	if pokerus & 0x0F != 0:
		_text(into, width, POKERUS_STRING, POKERUS_AT)
	else:
		if pokerus & 0xF0 != 0:
			_code(into, width, CODE_DOT, POKERUS_DOT)
		_text(into, width, _status_string(page), STATUS_AT)

	var types: Array = page.get("types", [])
	for index: int in types.size():
		_text(into, width, String(types[index]), TYPES_AT + Vector2i(0, index))

	tiles.draw_run_down(
		Gen2BattleTiles.STATS_DIVIDER, LOWER_ROWS, into, width,
		PINK_DIVIDER_COLUMN * TILE, LOWER_FIRST_ROW * TILE
	)
	_text(into, width, EXP_POINT_STRING, EXP_POINTS_LABEL)
	_text(into, width, LEVEL_UP_STRING, LEVEL_UP_LABEL)
	_text(into, width, TO_STRING, TO_LABEL)
	draw_level(into, width, NEXT_LEVEL_AT, int(page.get("next_level", 0)))
	_text(into, width, str(int(page.get("exp", 0))).lpad(EXP_DIGITS), EXP_POINTS_AT)
	_text(
		into, width, str(int(page.get("exp_to_next", 0))).lpad(EXP_DIGITS), EXP_TO_NEXT_AT
	)
	hud.draw_exp_bar(into, width, int(page.get("exp_pixels", 0)), EXP_BAR_AT)
	tiles.draw(
		Gen2BattleTiles.EXP_BAR_LEFT_CAP, into, width,
		EXP_BAR_LEFT_CAP.x * TILE, EXP_BAR_LEFT_CAP.y * TILE
	)
	tiles.draw(
		Gen2BattleTiles.EXP_BAR_RIGHT_CAP, into, width,
		EXP_BAR_RIGHT_CAP.x * TILE, EXP_BAR_RIGHT_CAP.y * TILE
	)


func _draw_green(page: Dictionary, into: PackedByteArray) -> void:
	var width: int = COLUMNS * TILE
	_text(into, width, ITEM_STRING, ITEM_LABEL)
	_text(into, width, String(page.get("item_name", THREE_DASHES)), ITEM_AT)
	_text(into, width, MOVE_STRING, MOVE_LABEL)
	draw_move_list(into, width, page.get("moves", []), MOVES_AT, MOVE_PP_AT)


## `ListMoves` and `ListMovePP` together: four rows two tiles apart, a name in
## each and either its PP or the dashes an empty slot draws. The move screen
## lists the same four from its own two columns.
func draw_move_list(
	into: PackedByteArray, width: int, moves: Array, names_at: Vector2i, pp_at: Vector2i
) -> void:
	for slot: int in MAX_MOVES:
		var row: int = slot * MOVE_ROW_STEP
		if slot >= moves.size():
			## `.nonmove_loop` prints one `-` for the name and `.load_loop`
			## writes two for the PP label.
			_text(into, width, "-", names_at + Vector2i(0, row))
			_text(into, width, "--", pp_at + Vector2i(0, row))
			continue
		var move: Dictionary = moves[slot]
		_text(into, width, String(move.get("name", "")), names_at + Vector2i(0, row))
		for column: int in 2:
			tiles.draw(
				PP_LABEL_TILE, into, width,
				(pp_at.x + column) * TILE, (pp_at.y + row) * TILE
			)
		_text(
			into, width, str(int(move.get("pp", 0))).lpad(PP_DIGITS),
			pp_at + Vector2i(3, row)
		)
		_code(into, width, CODE_SLASH, pp_at + Vector2i(5, row))
		_text(
			into, width, str(int(move.get("max_pp", 0))).lpad(PP_DIGITS),
			pp_at + Vector2i(6, row)
		)


func _draw_blue(page: Dictionary, into: PackedByteArray) -> void:
	var width: int = COLUMNS * TILE
	_id_label(into, width, ID_LABEL)
	_text(into, width, OT_STRING, OT_LABEL)
	_text(into, width, "%0*d" % [ID_DIGITS, int(page.get("ot_id", 0))], ID_NUMBER_AT)
	_text(into, width, String(page.get("ot_name", "")), OT_NAME_AT)
	## `wTempMonCaughtGender`: zero is a mon this save has no caught data for and
	## $7f is a traded one, and neither prints a symbol.
	var caught: int = int(page.get("caught_gender", 0))
	if caught != 0 and caught != 0x7F:
		_code(
			into, width,
			CODE_FEMALE if caught & CAUGHT_GENDER_MASK != 0 else CODE_MALE,
			CAUGHT_GENDER_AT
		)
	tiles.draw_run_down(
		Gen2BattleTiles.STATS_DIVIDER, LOWER_ROWS, into, width,
		BLUE_DIVIDER_COLUMN * TILE, LOWER_FIRST_ROW * TILE
	)
	draw_stats(into, width, STAT_NAMES_AT, page.get("stats", {}))


## A registered page's own lower half. The mod answers placements and this writes
## them with the screen's font and the same divider the pink and blue pages
## stand, so a page it draws cannot reach the upper half or the front pic.
## Anything outside the lower ten rows is dropped rather than clipped.
func _draw_registered(page: Dictionary, into: PackedByteArray, index: int) -> void:
	var builders: Array = extra_page_builders()
	if index < 0 or index >= builders.size():
		return
	var width: int = COLUMNS * TILE
	var placements: Variant = (builders[index] as Callable).call(page)
	if not placements is Array:
		return
	for placement: Dictionary in placements as Array:
		if placement.has("divider"):
			var column: int = int(placement["divider"])
			if column < 0 or column >= COLUMNS:
				continue
			tiles.draw_run_down(
				Gen2BattleTiles.STATS_DIVIDER, LOWER_ROWS, into, width,
				column * TILE, LOWER_FIRST_ROW * TILE
			)
			continue
		var at: Vector2i = placement.get("at", Vector2i.ZERO)
		if at.y < LOWER_FIRST_ROW or at.y >= LOWER_FIRST_ROW + LOWER_ROWS \
			or at.x < 0 or at.x >= COLUMNS:
			continue
		_text(into, width, String(placement.get("text", "")), at)


## `EggStatsScreen`, which replaces the whole screen rather than a page of it:
## the divider, four labels beside the pic and the hatch hint under it.
func _draw_egg(page: Dictionary, into: PackedByteArray) -> void:
	var width: int = COLUMNS * TILE
	tiles.draw_run(
		Gen2BattleTiles.HP_BAR_EMPTY, COLUMNS, into, width, 0, DIVIDER_ROW * TILE
	)
	_text(into, width, EGG_STRING, EGG_LABEL)
	_id_label(into, width, EGG_ID_LABEL)
	_text(into, width, OT_STRING, EGG_OT_LABEL)
	_text(into, width, FIVE_QUESTION_MARKS, EGG_ID_MARKS)
	_text(into, width, FIVE_QUESTION_MARKS, EGG_OT_MARKS)
	var lines: PackedStringArray = String(page.get("egg_message", "")).split("\n")
	for index: int in lines.size():
		_text(into, width, lines[index], EGG_TEXT_AT + Vector2i(0, index * MOVE_ROW_STEP))


## `IDNoString`, which is `<ID>`, `№` and a decimal point.
func _id_label(into: PackedByteArray, width: int, at: Vector2i) -> void:
	_code(into, width, CODE_ID, at)
	_code(into, width, CODE_NUMERO, at + Vector2i(1, 0))
	_code(into, width, CODE_DOT, at + Vector2i(2, 0))


## `PlaceStatusString`: the health is tested before the byte, so a fainted mon
## reads FNT whatever else it carries, and anything with no status at all is the
## page's own `OK `.
func _status_string(page: Dictionary) -> String:
	if bool(page.get("fainted", false)):
		return FAINTED_STRING
	var name: StringName = Gen2Status.name_of(int(page.get("status", 0)))
	return String(STATUS_STRINGS.get(name, OK_STRING))


## `PrintLevel`: the `<LV>` tile and then the number left-aligned beside it.
func draw_level(into: PackedByteArray, width: int, at: Vector2i, level: int) -> void:
	_code(into, width, CODE_LEVEL, at)
	_text(into, width, str(level), at + Vector2i(1, 0))


## `.PlaceGenderChar`, which prints nothing at all for a genderless species
## rather than a space.
func _gender(
	into: PackedByteArray, width: int, at: Vector2i, gender: StringName
) -> void:
	if gender == Gen2BattleMon.GENDER_MALE:
		_code(into, width, CODE_MALE, at)
	elif gender == Gen2BattleMon.GENDER_FEMALE:
		_code(into, width, CODE_FEMALE, at)


func _text(into: PackedByteArray, width: int, text: String, at: Vector2i) -> void:
	font.draw_text(text, into, width, at.x * TILE, at.y * TILE, FONT)


func _code(into: PackedByteArray, width: int, code: int, at: Vector2i) -> void:
	font.draw_code(code, into, width, at.x * TILE, at.y * TILE, FONT)
