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


func _write_cache() -> void:
	var sheets: Dictionary = {}
	var written: Dictionary = {
		"exp_bar": RomLayout.EXP_BAR_TILES,
		"battle_font": RomLayout.BATTLE_FONT_TILES,
		"enemy_hud": RomLayout.ENEMY_HUD_TILES,
		"player_hud": RomLayout.PLAYER_HUD_TILES,
		"font": RomLayout.FONT_TILES,
		"frames": RomLayout.FRAME_COUNT * RomLayout.FRAME_TILES,
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
