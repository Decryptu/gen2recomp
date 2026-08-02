extends GutTest

## The battle screen's tile page and the arithmetic behind its bars.
##
## Builds its own cache, like `test_game_data.gd`: nothing here opens a
## cartridge, because the point of the drawing layer is that it works on
## indices and a palette and never sees one.

var _directory: String = ""


func before_each() -> void:
	_directory = RomCache.directory_for(&"battletest", "0123456789abcdef")
	RomCache.clear(_directory)
	RomCache.prepare(_directory)


func after_each() -> void:
	RomCache.clear(_directory)


## Four sheets, each filled with one index, so which sheet a tile came from can
## be read off the page.
func _write_cache(with_sheets: bool = true) -> void:
	var sheets: Dictionary = {}
	if with_sheets:
		var written: Dictionary = {
			"exp_bar": [RomLayout.EXP_BAR_TILES, 2],
			"battle_font": [RomLayout.BATTLE_FONT_TILES, 1],
			"enemy_hud": [RomLayout.ENEMY_HUD_TILES, 2],
			"player_hud": [RomLayout.PLAYER_HUD_TILES, 3],
			"font": [RomLayout.FONT_TILES, 3],
			"frames": [RomLayout.FRAME_COUNT * RomLayout.FRAME_TILES, 3],
		}
		for name: String in written:
			var tiles: int = written[name][0]
			var value: int = written[name][1]
			var indices: PackedByteArray = PackedByteArray()
			indices.resize(tiles * Gen2Tiles.TILE_WIDTH * Gen2Tiles.TILE_HEIGHT)
			indices.fill(value)
			RomCache.write_indices(RomCache.tile_path(_directory, name), indices)
			sheets[name] = {
				"width": tiles * Gen2Tiles.TILE_WIDTH,
				"height": Gen2Tiles.TILE_HEIGHT,
				"tiles": tiles,
				"first_code": RomLayout.FONT_FIRST_CODE if name == "font" else 0,
				"bits": 1,
			}

	RomCache.write_json(RomCache.manifest_path(_directory), {
		"format_version": RomCache.FORMAT_VERSION,
		"game_id": "battletest",
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


func _data() -> GameData:
	return GameData.open_directory(_directory)


## The index one tile of the page draws, read back out of a buffer.
func _drawn(page: Gen2BattleTiles, tile: int) -> int:
	var into: PackedByteArray = PackedByteArray()
	into.resize(Gen2Tiles.TILE_WIDTH * Gen2Tiles.TILE_HEIGHT)
	page.draw(tile, into, Gen2Tiles.TILE_WIDTH, 0, 0)
	return into[0]


func test_the_page_needs_every_sheet_it_draws_from() -> void:
	_write_cache(false)
	assert_null(Gen2BattleTiles.from_data(_data()))
	assert_null(Gen2BattleHud.from_data(_data()))


func test_a_later_sheet_wins_the_tiles_it_lands_on() -> void:
	# The battle font is copied in first and the HUD borders over the middle of
	# it, exactly as they are in video memory, so thirteen of its tiles are never
	# seen. Getting this backwards draws a border where a bar should be.
	_write_cache()
	var page: Gen2BattleTiles = Gen2BattleTiles.from_data(_data())
	assert_not_null(page)
	assert_eq(_drawn(page, Gen2BattleTiles.EXP_BAR_AT), 2, "the exp bar keeps its own tiles")
	assert_eq(_drawn(page, Gen2BattleTiles.HP_BAR_EMPTY), 1, "the bar is the battle font's")
	assert_eq(_drawn(page, Gen2BattleTiles.ENEMY_HUD_AT), 2, "the enemy border overwrites")
	assert_eq(_drawn(page, Gen2BattleTiles.PLAYER_HUD_AT), 3, "so does the player's")


func test_a_tile_outside_the_page_draws_nothing() -> void:
	_write_cache()
	var page: Gen2BattleTiles = Gen2BattleTiles.from_data(_data())
	assert_eq(_drawn(page, Gen2BattleTiles.FIRST_TILE - 1), 0)
	assert_eq(_drawn(page, Gen2BattleTiles.LAST_TILE + 1), 0)


func test_a_full_bar_is_full_and_an_empty_one_is_empty() -> void:
	assert_eq(Gen2BattleHud.bar_pixels(20, 20, 48), 48)
	assert_eq(Gen2BattleHud.bar_pixels(0, 20, 48), 0)


func test_a_pokemon_that_is_alive_never_shows_an_empty_bar() -> void:
	# The games round the bar down and then put a pixel back, so that an empty
	# bar means fainted and nothing else.
	assert_eq(Gen2BattleHud.bar_pixels(1, 999, 48), 1)


func test_a_bar_is_as_full_as_the_fraction_behind_it() -> void:
	assert_eq(Gen2BattleHud.bar_pixels(10, 20, 48), 24)
	assert_eq(Gen2BattleHud.bar_pixels(5, 20, 48), 12)


func test_a_bar_with_no_maximum_does_not_divide_by_it() -> void:
	assert_eq(Gen2BattleHud.bar_pixels(5, 0, 48), 0)


func test_the_bar_colour_follows_what_is_drawn_not_the_hit_points() -> void:
	# Half a bar is still green, a fifth of it is yellow, and below that it is
	# red: the rule is about pixels, which is why a bar can turn red on a
	# Pokémon with hit points left.
	assert_eq(GameData.hp_bar_palette_name(48), "hp_green")
	assert_eq(GameData.hp_bar_palette_name(RomLayout.HP_GREEN_PIXELS), "hp_green")
	assert_eq(GameData.hp_bar_palette_name(RomLayout.HP_GREEN_PIXELS - 1), "hp_yellow")
	assert_eq(GameData.hp_bar_palette_name(RomLayout.HP_YELLOW_PIXELS), "hp_yellow")
	assert_eq(GameData.hp_bar_palette_name(RomLayout.HP_YELLOW_PIXELS - 1), "hp_red")


func test_a_bar_palette_comes_back_as_four_colours() -> void:
	_write_cache()
	var data: GameData = _data()
	var palette: PackedColorArray = data.bar_palette("hp_green")
	assert_eq(palette.size(), Gen2Palette.COLORS_PER_PIC)
	assert_eq(palette[0], Color.WHITE)
	assert_eq(palette[3], Color.BLACK)
	assert_ne(palette, data.bar_palette("hp_red"))


func test_an_unknown_bar_palette_is_legible_rather_than_missing() -> void:
	_write_cache()
	assert_eq(_data().bar_palette("nothing"), _data().bar_palette("also nothing"))


func test_the_hud_draws_its_panels_where_the_hardware_puts_them() -> void:
	# The panels sit above and below the pics and must not reach into either.
	_write_cache()
	var hud: Gen2BattleHud = Gen2BattleHud.from_data(_data())
	assert_not_null(hud)

	var screen: PackedByteArray = PackedByteArray()
	screen.resize(Gen2Screen.WIDTH * Gen2Screen.HEIGHT)
	hud.draw_enemy(screen, Gen2Screen.WIDTH, "PIDGEY", 5)
	hud.draw_player(screen, Gen2Screen.WIDTH, "CYNDAQUIL", 5, 18, 18)

	assert_ne(_ink_in_row(screen, Gen2BattleHud.ENEMY_NAME.y), 0, "the enemy's name row")
	assert_ne(_ink_in_row(screen, Gen2BattleHud.PLAYER_BAR.y), 0, "the player's bar row")
	assert_eq(_ink_in_row(screen, Gen2TextBox.STANDARD_TOP), 0, "nothing in the text box")
	assert_eq(_ink_in_row(screen, 5), 0, "nothing between the two panels")


func test_the_hp_bar_fill_is_drawn_apart_from_the_panel() -> void:
	# The fill is the only part of a panel that is not black on white, so it is
	# a layer of its own and the panel must not draw it.
	_write_cache()
	var hud: Gen2BattleHud = Gen2BattleHud.from_data(_data())

	var full: PackedByteArray = PackedByteArray()
	full.resize(Gen2Screen.WIDTH * Gen2Screen.HEIGHT)
	hud.draw_hp_bar(full, Gen2Screen.WIDTH, Gen2BattleHud.ENEMY_BAR, 20, 20)

	var empty: PackedByteArray = PackedByteArray()
	empty.resize(Gen2Screen.WIDTH * Gen2Screen.HEIGHT)
	hud.draw_hp_bar(empty, Gen2Screen.WIDTH, Gen2BattleHud.ENEMY_BAR, 0, 20)

	assert_ne(_ink_in_row(full, Gen2BattleHud.ENEMY_BAR.y), 0)
	assert_eq(_ink_in_row(empty, Gen2BattleHud.ENEMY_BAR.y), 0, "a fainted bar draws nothing")


## Lit pixels in one row of tiles.
func _ink_in_row(screen: PackedByteArray, row: int) -> int:
	var out: int = 0
	for y: int in range(row * Gen2Font.TILE, (row + 1) * Gen2Font.TILE):
		for x: int in Gen2Screen.WIDTH:
			if screen[y * Gen2Screen.WIDTH + x] != 0:
				out += 1
	return out
