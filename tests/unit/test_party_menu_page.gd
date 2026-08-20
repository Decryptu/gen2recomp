extends GutTest

## `WritePartyMenuTilemap`'s `PARTYMENUACTION_SWITCH` columns and
## `PlacePartyMenuText`'s box (`engine/pokemon/party_menu.asm`), checked by where
## the ink lands rather than by eye.
##
## Every sheet in the cache is filled with one index, so a glyph is a solid tile
## and a column that drew something can be told from one that did not. That is
## the whole claim here: the page is geometry, and the drawing under it is
## [Gen2Font]'s and [Gen2BattleHud]'s own.
##
## The battle-extra strip is filled with a different index from the rest, since
## the bars come off it and are the one thing on the page drawn through a palette
## that is not black on white. The icons are the other: one fixture shape whose
## two frames carry different indices, so which pass is on screen and where it
## landed can both be read off the picture.

## The fixture's one icon shape and the species that names it, plus the two
## colours its frames are drawn in.
const FIXTURE_ICON: int = 3
const FIXTURE_SPECIES: int = 25
const ICON_FIRST_PACKED: int = 0x03E0
const ICON_SECOND_PACKED: int = 0x001F
## The four tiles of the shape's first frame, which is half the strip.
const HALF_ICON_COLUMNS: int = 4 * Gen2Tiles.TILE_WIDTH

var _directory: String = ""


func before_each() -> void:
	_directory = RomCache.directory_for(&"partypagetest", "0123456789abcdef")
	RomCache.clear(_directory)
	RomCache.prepare(_directory)
	_write_cache()


func after_each() -> void:
	RomCache.clear(_directory)
	Gen2ModHost.reset()


func _write_cache() -> void:
	var sheets: Dictionary = {}
	var written: Dictionary = {
		"exp_bar": RomLayout.EXP_BAR_TILES,
		"battle_font": RomLayout.BATTLE_FONT_TILES,
		"enemy_hud": RomLayout.ENEMY_HUD_TILES,
		"player_hud": RomLayout.PLAYER_HUD_TILES,
		"font": RomLayout.FONT_TILES,
		"frames": RomLayout.FRAME_COUNT * RomLayout.FRAME_TILES,
		## Only the stats and move screens read this one, and both are drawn from
		## the same cache the party menu is.
		"stats_tiles": RomLayout.STATS_TILES,
	}
	var first_codes: Dictionary = {
		"font": RomLayout.FONT_FIRST_CODE, "frames": RomLayout.FRAME_FIRST_CODE,
	}
	for name: String in written:
		var tiles: int = written[name]
		var indices: PackedByteArray = PackedByteArray()
		indices.resize(tiles * Gen2Tiles.TILE_WIDTH * Gen2Tiles.TILE_HEIGHT)
		indices.fill(2 if name == "battle_font" else 3)
		RomCache.write_indices(RomCache.tile_path(_directory, name), indices)
		sheets[name] = {
			"width": tiles * Gen2Tiles.TILE_WIDTH,
			"height": Gen2Tiles.TILE_HEIGHT,
			"tiles": tiles,
			"first_code": int(first_codes.get(name, 0)),
			"bits": 1,
		}

	_write_icons()

	RomCache.write_json(RomCache.manifest_path(_directory), {
		"format_version": RomCache.FORMAT_VERSION,
		"game_id": "partypagetest",
		"sha1": "0123456789abcdef",
		"tiles": sheets,
		"bar_palettes": {
			"hp_green": [0x02E0, 0x02E0],
			"hp_yellow": [0x02BF, 0x02BF],
			"hp_red": [0x001F, 0x001F],
			"exp": [0x7E24, 0x7E24],
		},
		"complete": true,
	})


## One icon shape whose first frame is index 1 and second index 2, the held item
## marker in index 3, and the two palettes `InitPartyMenuOBPals` copies.
func _write_icons() -> void:
	var strip: PackedByteArray = PackedByteArray()
	strip.resize(RomLayout.MON_ICON_TILES * Gen2Tiles.TILE_PIXELS)
	var width: int = RomLayout.MON_ICON_TILES * Gen2Tiles.TILE_WIDTH
	for row: int in Gen2Tiles.TILE_HEIGHT:
		for column: int in width:
			strip[row * width + column] = 1 if column < HALF_ICON_COLUMNS else 2
	RomCache.write_indices(RomCache.overworld_icon_path(_directory, FIXTURE_ICON), strip)

	var held: PackedByteArray = PackedByteArray()
	held.resize(RomLayout.HELD_ITEM_ICON_TILES * Gen2Tiles.TILE_PIXELS)
	held.fill(3)
	RomCache.write_indices(RomCache.held_item_icon_path(_directory), held)

	var species: PackedByteArray = PackedByteArray()
	species.resize(RomLayout.SPECIES_COUNT)
	species[FIXTURE_SPECIES - 1] = FIXTURE_ICON
	RomCache.write_indices(RomCache.mon_menu_icons_path(_directory), species)

	RomCache.write_json(RomCache.party_menu_icon_palettes_path(_directory), [
		[0x7FFF, ICON_FIRST_PACKED, ICON_SECOND_PACKED, 0x0000],
		[0x7FFF, ICON_FIRST_PACKED, 0x0000, 0x0000],
	])


func _page() -> Gen2PartyMenuPage:
	return Gen2PartyMenuPage.from_data(GameData.open_directory(_directory))


func _rows(count: int = 2) -> Array:
	var out: Array = []
	for index: int in count:
		out.append({
			"index": index, "species": FIXTURE_SPECIES, "item": 0,
			"name": "PIKACHU", "level": 20,
			"hp": 18, "max_hp": 20, "status": 0, "fainted": false,
		})
	return out


## The page after [param passes] passes of `PlaySpriteAnimations`, which is what
## [Gen2BattleScreen] spends one of a hardware frame.
func _animated(rows: Array, cursor: int, passes: int) -> Image:
	var page: Gen2PartyMenuPage = _page()
	page.reset(rows)
	for _pass: int in passes:
		page.advance(rows, cursor)
	return page.render(rows, cursor, Gen2BattleSwitchMenu.prompt_text())


func _render(rows: Array, cursor: int = 0) -> Image:
	return _page().render(rows, cursor, Gen2BattleSwitchMenu.prompt_text())


## Anything that is not the white the page is cleared to.
func _ink_in_tile(image: Image, column: int, row: int) -> int:
	var out: int = 0
	for y: int in Gen2Font.TILE:
		for x: int in Gen2Font.TILE:
			if image.get_pixel(column * Gen2Font.TILE + x, row * Gen2Font.TILE + y) != Color.WHITE:
				out += 1
	return out


func test_the_page_needs_a_cache_it_can_draw_from() -> void:
	RomCache.clear(_directory)
	RomCache.prepare(_directory)
	RomCache.write_json(RomCache.manifest_path(_directory), {
		"format_version": RomCache.FORMAT_VERSION,
		"game_id": "partypagetest", "sha1": "0123456789abcdef", "complete": true,
	})
	assert_null(Gen2PartyMenuPage.from_data(GameData.open_directory(_directory)))


func test_the_page_is_the_whole_screen() -> void:
	var image: Image = _render(_rows())
	assert_eq(image.get_size(), Vector2i(Gen2Screen.WIDTH, Gen2Screen.HEIGHT))


## `hlcoord 3, 1` for the nicknames, stepping `2 * SCREEN_WIDTH` a member, with
## columns 0 to 2 left for the icons, which are sprites rather than tilemap.
func test_each_member_prints_two_rows_below_the_last() -> void:
	var image: Image = _render(_rows())
	assert_ne(_ink_in_tile(image, Gen2PartyMenuPage.NICKNAME.x, 1), 0, "the first nickname")
	assert_ne(_ink_in_tile(image, Gen2PartyMenuPage.NICKNAME.x, 3), 0, "the second")
	assert_eq(_ink_in_tile(image, Gen2PartyMenuPage.NICKNAME.x - 1, 1), 0, "the icon column")


## `InitPartyMenuGFX` spawns a struct per member and `UpdateAnimFrame` writes
## shadow OAM on the pass after, so a page that has not been stepped yet has no
## icons on it at all.
func test_no_icon_is_drawn_before_the_first_sprite_pass() -> void:
	var page: Gen2PartyMenuPage = _page()
	page.reset(_rows(1))
	var image: Image = page.render(_rows(1), -1, "")
	assert_eq(_ink_in_tile(image, 0, 1), 0, "nothing under the first member")


## `InitPartyMenuIcon`'s `ld e, $10` less a tile and shadow OAM's own origin,
## which puts an unselected icon over columns 0 and 1; the cursor's own row is
## `SpriteAnimFunc_PartyMonSwitch`'s `8 * 3`, a column further right, which is
## what leaves column 0 for the arrow.
func test_the_chosen_row_moves_its_icon_out_of_the_cursor_column() -> void:
	var rows: Array = _rows(2)
	## Column 2 of the second member's own rows, which only a shifted icon
	## reaches. The fixture's glyphs are solid tiles, so the picture is read
	## where nothing else is drawn rather than where the arrow is.
	var right := Vector2i(2 * Gen2Font.TILE + 1, 3 * Gen2Font.TILE + 2)
	assert_eq(
		_animated(rows, -1, 1).get_pixelv(right), Color.WHITE,
		"an unselected icon stops at column 1"
	)
	assert_eq(
		_animated(rows, 1, 1).get_pixelv(right), Gen2Palette.from_packed(ICON_FIRST_PACKED),
		"and the chosen row's reaches column 2"
	)


## `.Frameset_PartyMon` is two OAM sets of eight, so the first entry is up for
## nine passes and the second for the nine after it.
func test_the_icon_steps_to_its_second_frame_after_nine_passes() -> void:
	var rows: Array = _rows(1)
	var at := Vector2i(Gen2Font.TILE, 1 * Gen2Font.TILE)
	assert_eq(
		_animated(rows, -1, 9).get_pixelv(at), Gen2Palette.from_packed(ICON_FIRST_PACKED),
		"the first frame lasts nine passes"
	)
	assert_eq(
		_animated(rows, -1, 10).get_pixelv(at), Gen2Palette.from_packed(ICON_SECOND_PACKED),
		"and the second follows it"
	)


## `SpriteAnimFunc_PartyMonSwitch` moves YOFFSET on every sixteenth pass, and
## `.speeds` picks how far by the bar's own colour: two pixels on a green one.
func test_the_chosen_icon_bobs_on_its_own_counter() -> void:
	var rows: Array = _rows(1)
	## Two pixels above where the first icon rests, which nothing else draws on.
	var above := Vector2i(2 * Gen2Font.TILE, 2)
	assert_eq(
		_animated(rows, 0, 16).get_pixelv(above), Color.WHITE, "the icon rests where it spawned"
	)
	assert_ne(
		_animated(rows, 0, 17).get_pixelv(above), Color.WHITE,
		"and stands two pixels higher once the counter passes sixteen"
	)


## `.SpawnItemIcon`: a member holding anything wears `HeldItemIcons`' second
## tile in place of the icon's own bottom-left one.
func test_a_held_item_replaces_the_icons_bottom_left_tile() -> void:
	var rows: Array = _rows(1)
	var quadrant := Vector2i(0, 1 * Gen2Font.TILE + 4)
	var bare: Color = _animated(rows, -1, 1).get_pixelv(quadrant)
	rows[0]["item"] = 1
	var held: Color = _animated(rows, -1, 1).get_pixelv(quadrant)
	assert_eq(bare, Gen2Palette.from_packed(ICON_FIRST_PACKED), "the icon's own tile")
	assert_eq(held, Color.BLACK, "and the marker's, which the fixture fills with index 3")


## `PlacePartyNicknames.end` steps two columns back from the row below the last
## nickname, which is the row CANCEL prints on.
func test_cancel_prints_below_the_last_member() -> void:
	for count: int in [1, 2, 3]:
		var image: Image = _render(_rows(count))
		var row: int = Gen2PartyMenuPage.NICKNAME.y + count * Gen2PartyMenuPage.ROW_STEP
		assert_ne(
			_ink_in_tile(image, Gen2PartyMenuPage.CANCEL_COLUMN, row), 0,
			"CANCEL under %d members" % count
		)


## `SwitchPartyMons` reopens through `InitPartyMenuNoCancel` and writes `▷` over
## `hlcoord 0, 1` plus two rows per held member.
func test_a_held_row_wears_its_marker_and_the_switch_list_has_no_cancel() -> void:
	var rows: Array = _rows(2)
	var image: Image = _page().render(
		rows, 1, Gen2BattleSwitchMenu.prompt_text(), false, 0
	)
	assert_eq(
		_ink_in_tile(image, Gen2PartyMenuPage.CANCEL_COLUMN, 5), 0,
		"InitPartyMenuNoCancel prints no CANCEL"
	)
	assert_ne(_ink_in_tile(image, Gen2PartyMenuPage.CURSOR_COLUMN, 1), 0, "the marker")
	assert_ne(_ink_in_tile(image, Gen2PartyMenuPage.CURSOR_COLUMN, 3), 0, "the cursor")
	## Without a member held, column 0 of that row is the blank it always was:
	## the fixture's glyphs are solid tiles, so which glyph landed cannot be read
	## off the picture, only that one did.
	assert_eq(
		_ink_in_tile(
			_page().render(rows, 1, Gen2BattleSwitchMenu.prompt_text(), false, -1),
			Gen2PartyMenuPage.CURSOR_COLUMN, 1
		), 0, "and nothing is written there otherwise"
	)


## The four qualities `.Default` asks for, each in its own column on the row
## under the nickname, except the HP numbers which share the nickname's.
func test_every_quality_lands_in_its_own_column() -> void:
	var image: Image = _render(_rows(1))
	## `PrintNum`'s three digits are right-aligned and space-padded, so 18 out of
	## 20 leaves the first of them blank.
	assert_eq(_ink_in_tile(image, Gen2PartyMenuPage.HP_DIGITS.x, 1), 0, "the padding")
	assert_ne(_ink_in_tile(image, Gen2PartyMenuPage.HP_DIGITS.x + 1, 1), 0, "the HP numbers")
	assert_ne(_ink_in_tile(image, Gen2PartyMenuPage.LEVEL.x, 2), 0, "the level symbol")
	assert_ne(_ink_in_tile(image, Gen2PartyMenuPage.HP_BAR.x, 2), 0, "HP: and the bar")
	assert_eq(_ink_in_tile(image, Gen2PartyMenuPage.STATUS.x, 2), 0, "a healthy status is blank")


## `PlaceStatusString` checks the health before it looks at the byte, so FNT wins
## over anything on it.
func test_a_status_prints_and_fainting_wins_over_it() -> void:
	var rows: Array = _rows(1)
	rows[0]["status"] = Gen2Status.POISON
	assert_ne(
		_ink_in_tile(_render(rows), Gen2PartyMenuPage.STATUS.x, 2), 0, "PSN is drawn"
	)
	rows[0]["hp"] = 0
	rows[0]["fainted"] = true
	assert_ne(
		_ink_in_tile(_render(rows), Gen2PartyMenuPage.STATUS.x, 2), 0, "FNT is drawn"
	)


## The bar is the one thing on the page that is not black on white, so it is
## blended in its own colour rather than drawn as ink.
func test_the_bar_is_drawn_in_the_colour_its_fill_earns() -> void:
	var rows: Array = _rows(1)
	var fill_at := Vector2i(
		(Gen2PartyMenuPage.HP_BAR.x + 2) * Gen2Font.TILE,
		Gen2PartyMenuPage.HP_BAR.y * Gen2Font.TILE + 4
	)
	var green: Color = _render(rows).get_pixelv(fill_at)
	rows[0]["hp"] = 1
	var red: Color = _render(rows).get_pixelv(fill_at)
	assert_ne(green, Color.WHITE, "a full bar is lit")
	assert_ne(green, Color.BLACK, "and not in the page's own ink")
	assert_ne(green, red, "a bar about to empty is a different colour")
	rows[0]["hp"] = 0
	rows[0]["fainted"] = true
	assert_eq(
		_render(rows).get_pixelv(fill_at), Color.BLACK,
		"and a fainted one has no fill over the empty bar at all"
	)


## `Place2DMenuCursor`'s column, on the member's own row.
func test_the_cursor_sits_left_of_the_row_it_is_on() -> void:
	var image: Image = _render(_rows(), 1)
	assert_eq(_ink_in_tile(image, Gen2PartyMenuPage.CURSOR_COLUMN, 1), 0)
	assert_ne(_ink_in_tile(image, Gen2PartyMenuPage.CURSOR_COLUMN, 3), 0)


## `hlcoord 0, 14` with `lb bc, 2, 18`, and the string at `hlcoord 1, 16`.
func test_the_prompt_box_covers_the_bottom_four_rows() -> void:
	var image: Image = _render(_rows())
	assert_ne(_ink_in_tile(image, 0, Gen2PartyMenuPage.TEXTBOX.y), 0, "the frame's corner")
	assert_ne(
		_ink_in_tile(image, 19, Gen2PartyMenuPage.TEXTBOX.y + Gen2PartyMenuPage.TEXTBOX_ROWS - 1),
		0, "and the far one"
	)
	assert_ne(_ink_in_tile(image, Gen2PartyMenuPage.PROMPT.x, Gen2PartyMenuPage.PROMPT.y), 0)
	assert_eq(_ink_in_tile(image, 0, Gen2PartyMenuPage.TEXTBOX.y - 1), 0, "nothing above it")


## `PartyMenuCheckEgg` opens every quality's loop below the nicknames, so an egg
## is a name and nothing else. Reachable from the overworld menu alone.
func test_an_egg_row_draws_its_nickname_and_no_other_quality() -> void:
	var rows: Array = _rows(1)
	rows[0]["egg"] = true
	rows[0]["name"] = "EGG"
	var image: Image = _render(rows)
	assert_ne(_ink_in_tile(image, Gen2PartyMenuPage.NICKNAME.x, 1), 0, "the nickname")
	assert_eq(_ink_in_tile(image, Gen2PartyMenuPage.HP_DIGITS.x + 1, 1), 0, "no HP numbers")
	assert_eq(_ink_in_tile(image, Gen2PartyMenuPage.LEVEL.x, 2), 0, "no level")
	assert_eq(_ink_in_tile(image, Gen2PartyMenuPage.HP_BAR.x, 2), 0, "no bar")
	assert_eq(_ink_in_tile(image, Gen2PartyMenuPage.STATUS.x, 2), 0, "no status")


## `ReadMonMenuIcon`'s `cp EGG`: the icon is the one no species row names.
func test_an_egg_takes_the_egg_icon_rather_than_its_species_own() -> void:
	var data: GameData = GameData.open_directory(_directory)
	assert_eq(data.mon_menu_icon(FIXTURE_SPECIES), FIXTURE_ICON)
	assert_eq(data.mon_menu_icon(FIXTURE_SPECIES, true), RomLayout.ICON_EGG)


## `StatsScreen_LoadFont`'s page, which the stats and move screens share: the
## same tiles as a battle's plus `LoadStatsScreenPageTilesGFX`' seventeen at $31,
## and the player HUD's border scattered rather than copied whole, which leaves
## $73 to $75 as the battle-extra font's own.
func test_the_stats_page_reaches_further_down_than_a_battles() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var tiles: Gen2BattleTiles = Gen2BattleTiles.stats_page(data)
	assert_not_null(tiles)
	var buffer: PackedByteArray = PackedByteArray()
	buffer.resize(Gen2Screen.WIDTH * Gen2Screen.HEIGHT)
	for tile: int in [
		Gen2BattleTiles.STATS_DIVIDER, Gen2BattleTiles.SHINY,
		Gen2BattleTiles.EXP_BAR_LEFT_CAP, Gen2BattleTiles.HP_BAR_EMPTY,
	]:
		buffer.fill(0)
		tiles.draw(tile, buffer, Gen2Screen.WIDTH, 0, 0)
		assert_ne(buffer[0], 0, "tile $%02X is on the page" % tile)
	## A battle's own page starts at $55, so the stats sheet is out of its reach.
	buffer.fill(0)
	Gen2BattleTiles.from_data(data).draw(
		Gen2BattleTiles.STATS_DIVIDER, buffer, Gen2Screen.WIDTH, 0, 0
	)
	assert_eq(buffer[0], 0, "and off a battle's")


func _stats_page() -> Gen2StatsScreenPage:
	return Gen2StatsScreenPage.from_data(GameData.open_directory(_directory))


func _stats_image(page: Dictionary) -> Image:
	return Gen2PicImage.from_indices(
		_stats_page().draw(page), Gen2Screen.WIDTH, Gen2Screen.HEIGHT,
		Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))
	)


func _stats_snapshot(page: int) -> Dictionary:
	return {
		"egg": false, "page": page, "species": FIXTURE_SPECIES, "dex_number": 25,
		"species_name": "PIKACHU", "nickname": "SPARKY", "level": 20,
		"gender": Gen2BattleMon.GENDER_MALE, "shiny": false,
		"hp": 18, "max_hp": 20, "status": 0, "fainted": false, "pokerus": 0,
		"types": ["ELECTRIC"], "item_name": "---",
		"moves": [{"name": "TACKLE", "pp": 35, "max_pp": 35}],
		"ot_id": 1234, "ot_name": "RED", "caught_gender": 0,
		"stats": {"attack": 30, "defense": 20, "sp_attack": 25, "sp_defense": 25, "speed": 40},
		"exp": 8000, "next_level": 21, "exp_to_next": 200, "exp_pixels": 32,
	}


## `StatsScreen_InitUpperHalf` draws the same seven rows whichever page is open,
## and `StatsScreen_PlaceHorizontalDivider` closes them with a full-width run.
func test_the_stats_upper_half_is_the_same_on_every_page() -> void:
	for page: int in [
		Gen2StatsScreenPage.PINK_PAGE, Gen2StatsScreenPage.GREEN_PAGE,
		Gen2StatsScreenPage.BLUE_PAGE,
	]:
		var image: Image = _stats_image(_stats_snapshot(page))
		assert_ne(
			_ink_in_tile(image, Gen2StatsScreenPage.NICKNAME.x, Gen2StatsScreenPage.NICKNAME.y),
			0, "the nickname on page %d" % page
		)
		for column: int in [0, 19]:
			assert_ne(
				_ink_in_tile(image, column, Gen2StatsScreenPage.DIVIDER_ROW), 0,
				"the divider spans column %d" % column
			)


## `StatsScreen_LoadPageIndicators`: three 2x2 blocks at (13,5), (15,5) and
## (17,5), whichever page is open. Which of the two squares each block is drawn
## from is a tile number rather than a shape, and every sheet in this fixture is
## filled with one index, so only where they land is readable here.
func test_every_page_indicator_is_a_two_by_two_block() -> void:
	var image: Image = _stats_image(_stats_snapshot(Gen2StatsScreenPage.PINK_PAGE))
	for at: Vector2i in Gen2StatsScreenPage.PAGE_INDICATORS:
		for quadrant: int in 4:
			@warning_ignore("integer_division")
			assert_ne(
				_ink_in_tile(image, at.x + quadrant % 2, at.y + quadrant / 2), 0,
				"the block at %s" % at
			)
	assert_eq(
		_ink_in_tile(image, Gen2StatsScreenPage.PAGE_INDICATORS[0].x - 1, 5), 0,
		"and nothing beside the first of them"
	)


## A fourth page's block has nowhere to go beside the source's three, so the run
## is centred against the right arrow instead and the left arrow moves to meet
## it. Rows 5 and 6 are clear from column 8 out and the front pic ends at column
## 6, so nothing on the upper half moves and five pages is the ceiling.
func test_a_fourth_page_grows_the_indicator_run_leftward_and_moves_the_arrow() -> void:
	assert_true(bool(Gen2ModHost.instance().register_stats_page(
		&"testmod", {"build": func(_page: Dictionary) -> Array: return []}
	)["ok"]))
	assert_eq(
		Gen2StatsScreenPage.page_indicators(4),
		[Vector2i(11, 5), Vector2i(13, 5), Vector2i(15, 5), Vector2i(17, 5)] as Array[Vector2i]
	)
	assert_eq(Gen2StatsScreenPage.page_left_arrow(4), Vector2i(10, 6))
	assert_eq(
		Gen2StatsScreenPage.page_indicators(Gen2StatsScreenPage.NUM_PAGES),
		Gen2StatsScreenPage.PAGE_INDICATORS, "and three is where the source put them"
	)
	var image: Image = _stats_image(_stats_snapshot(Gen2StatsScreenPage.PINK_PAGE))
	for quadrant: int in 4:
		@warning_ignore("integer_division")
		assert_ne(
			_ink_in_tile(image, 11 + quadrant % 2, 5 + quadrant / 2), 0,
			"the fourth block"
		)
	assert_ne(_ink_in_tile(image, 10, 6), 0, "the arrow beside it")
	assert_eq(_ink_in_tile(image, 9, 6), 0, "and nothing left of it")
	## The fifth is the last that fits: its own arrow lands on column 8, one clear
	## of the front pic's seven-tile cell.
	assert_eq(
		Gen2StatsScreenPage.page_left_arrow(Gen2StatsScreenPage.MAX_PAGES).x,
		Gen2StatsScreenPage.PIC_TILES + 1
	)


## A registered page draws with the screen's own font and divider, and only into
## the ten rows under the divider: a placement above it is dropped rather than
## reaching the name, the level or the front pic.
func test_a_registered_page_draws_its_placements_and_only_the_lower_half() -> void:
	assert_true(bool(Gen2ModHost.instance().register_stats_page(&"testmod", {
		"build": func(page: Dictionary) -> Array:
			return [
				{"divider": 10},
				{"text": str(int(page.get("level", 0))), "at": Vector2i(0, 9)},
				{"text": "OFF", "at": Vector2i(0, 3)},
				{"text": "OFF", "at": Vector2i(0, 18)},
			],
	})["ok"]))
	var image: Image = _stats_image(
		_stats_snapshot(Gen2StatsScreenPage.BLUE_PAGE + 1)
	)
	assert_ne(_ink_in_tile(image, 0, 9), 0, "the page's own row, off the snapshot")
	for row: int in [
		Gen2StatsScreenPage.LOWER_FIRST_ROW, Gen2StatsScreenPage.ROWS - 1,
	]:
		assert_ne(_ink_in_tile(image, 10, row), 0, "the divider down column 10")
	assert_eq(_ink_in_tile(image, 0, 3), 0, "and nothing above the divider")


## Each page fills the ten rows under the divider and nothing above it, which is
## `.ClearBox`'s `hlcoord 0, 8` with `lb bc, 10, 20`.
func test_each_page_writes_its_own_lower_half() -> void:
	var pink: Image = _stats_image(_stats_snapshot(Gen2StatsScreenPage.PINK_PAGE))
	assert_ne(
		_ink_in_tile(pink, Gen2StatsScreenPage.HP_BAR.x, Gen2StatsScreenPage.HP_BAR.y), 0,
		"the pink page's HP bar"
	)
	assert_ne(
		_ink_in_tile(pink, Gen2StatsScreenPage.PINK_DIVIDER_COLUMN, 17), 0,
		"and its divider reaches the last row"
	)
	assert_ne(
		_ink_in_tile(pink, Gen2StatsScreenPage.TYPE_LABEL.x, Gen2StatsScreenPage.TYPE_LABEL.y),
		0, "and its TYPE/ label"
	)
	var blue: Image = _stats_image(_stats_snapshot(Gen2StatsScreenPage.BLUE_PAGE))
	assert_eq(
		_ink_in_tile(blue, Gen2StatsScreenPage.TYPE_LABEL.x, Gen2StatsScreenPage.TYPE_LABEL.y),
		0, "which the blue page does not draw"
	)
	## `PrintTempMonStats` at (11,8) with a spacing of six: five names down one
	## column and five numbers three columns from the right-hand edge.
	assert_ne(
		_ink_in_tile(blue, Gen2StatsScreenPage.STAT_NAMES_AT.x, 16), 0, "SPEED"
	)
	## `PrintNum`'s three digits are space padded and a space draws nothing, so a
	## two-digit stat leaves the first of the three columns blank.
	assert_eq(_ink_in_tile(blue, 17, 17), 0, "the number's own padding")
	assert_ne(_ink_in_tile(blue, 18, 17), 0, "and the number beside it")


## `ListMoves` and `.nonmove_loop`: a slot with no move draws one dash for the
## name and `.load_loop` writes two where its PP would go.
func test_an_empty_move_slot_draws_dashes_on_the_green_page() -> void:
	var image: Image = _stats_image(_stats_snapshot(Gen2StatsScreenPage.GREEN_PAGE))
	var names: Vector2i = Gen2StatsScreenPage.MOVES_AT
	var pp: Vector2i = Gen2StatsScreenPage.MOVE_PP_AT
	assert_ne(_ink_in_tile(image, names.x, names.y), 0, "the one move it knows")
	assert_ne(_ink_in_tile(image, pp.x, pp.y), 0, "and its PP label")
	assert_ne(_ink_in_tile(image, names.x, names.y + 2), 0, "the dash under it")
	assert_eq(_ink_in_tile(image, names.x + 1, names.y + 2), 0, "which is one tile wide")


## `MoveScreen2DMenuData`'s `db 3, 1` and `dn 2, 0`, and `.moving_move`, which
## replaces the move's own data with `Where?` and hollows the held row's arrow.
func test_the_move_screen_marks_the_row_it_is_holding() -> void:
	var page: Gen2MoveScreenPage = Gen2MoveScreenPage.from_data(
		GameData.open_directory(_directory)
	)
	assert_not_null(page)
	var snapshot: Dictionary = {
		"species": FIXTURE_SPECIES, "nickname": "SPARKY", "level": 20,
		"moves": [
			{"name": "TACKLE", "pp": 35, "max_pp": 35, "power": 35,
			"type_name": "NORMAL", "description": "A charge."},
			{"name": "GROWL", "pp": 40, "max_pp": 40, "power": 0,
			"type_name": "NORMAL", "description": "A growl."},
		],
		"cursor": 1, "held": -1, "previous": false, "next": true,
	}
	var listed: Image = Gen2PicImage.from_indices(
		page.draw(snapshot), Gen2Screen.WIDTH, Gen2Screen.HEIGHT,
		Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))
	)
	var second_row: int = Gen2MoveScreenPage.CURSOR_FIRST_ROW \
		+ Gen2MoveScreenPage.CURSOR_ROW_STEP
	assert_ne(
		_ink_in_tile(listed, Gen2MoveScreenPage.CURSOR_COLUMN, second_row), 0,
		"the cursor sits on the row it is over"
	)
	assert_ne(
		_ink_in_tile(listed, Gen2MoveScreenPage.ATTACK_LABEL.x, Gen2MoveScreenPage.ATTACK_LABEL.y),
		0, "and ATK/ is printed for it"
	)
	snapshot["held"] = 1
	var holding: Image = Gen2PicImage.from_indices(
		page.draw(snapshot), Gen2Screen.WIDTH, Gen2Screen.HEIGHT,
		Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))
	)
	assert_eq(
		_ink_in_tile(
			holding, Gen2MoveScreenPage.ATTACK_LABEL.x, Gen2MoveScreenPage.ATTACK_LABEL.y
		), 0, "which `Where?` replaces while a move is held"
	)
	assert_ne(
		_ink_in_tile(holding, Gen2MoveScreenPage.WHERE_AT.x, Gen2MoveScreenPage.WHERE_AT.y),
		0, "with the prompt in its place"
	)
