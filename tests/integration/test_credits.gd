extends GutTest

## `Credits` and `ParseCredits` (`engine/movie/credits.asm`) over a fixture
## cache, and [Gen2CreditsPage] over the same one.
##
## The model is scene-free but data-driven: the script, the strings, the palettes
## and `.Frames` all come out of a cache, so the fixture is what makes a case
## here say anything.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

## The fixture script's waits, as ticks: STAFF then 2, the music beat 1 and 1,
## the two names 2, the copyright 1, The End 1.
const FIRST_WAIT: int = 2

var _data: GameData = null


func before_each() -> void:
	Fixture.build()
	_data = GameData.open_directory(Fixture.directory())


func after_each() -> void:
	RomCache.clear(Fixture.directory())


func _gold() -> GameData:
	Fixture.build(RomRegistry.GOLD)
	return GameData.open_directory(Fixture.directory(RomRegistry.GOLD))


func _spend(credits: Gen2Credits, frames: int, held: Array = []) -> Array:
	var events: Array = []
	for _frame: int in frames:
		events.append_array(credits.advance_frame(held))
	return events


func _cell(map: PackedInt32Array, column: int, row: int) -> int:
	return map[row * Gen2Credits.COLUMNS + column]


## `ConstructCreditsTilemap`: the banner is five copies of one 4x4 cell, so the
## tile at a column is its position within that cell.
func test_the_banner_is_five_copies_of_one_four_by_four_cell() -> void:
	var credits: Gen2Credits = Gen2Credits.create(_data)
	var map: PackedInt32Array = credits.bg_map()
	for row: int in Gen2Credits.BANNER_ROWS:
		for column: int in Gen2Credits.COLUMNS:
			assert_eq(
				_cell(map, column, row),
				row * Gen2Credits.BANNER_COLUMNS + column % Gen2Credits.BANNER_COLUMNS
			)


## `DrawCreditsBorder`'s two bases, and the row each band sits on, which is where
## the two profiles part: Crystal gives the text four more rows and Gold and
## Silver a second banner.
func test_the_two_border_bands_sit_where_the_profile_puts_them() -> void:
	var crystal: PackedInt32Array = Gen2Credits.create(_data).bg_map()
	assert_eq(
		_cell(crystal, 5, Gen2Credits.BORDER_TOP_ROW),
		Gen2Credits.BORDER_TOP_TILE + 1
	)
	assert_eq(
		_cell(crystal, 0, Gen2Credits.BORDER_BOTTOM_ROW), Gen2Credits.BORDER_BOTTOM_TILE
	)

	var gold: PackedInt32Array = Gen2Credits.create(_gold()).bg_map()
	assert_eq(
		_cell(gold, 0, Gen2Credits.BORDER_BOTTOM_ROW_GOLD_SILVER),
		Gen2Credits.BORDER_BOTTOM_TILE
	)
	assert_eq(
		_cell(gold, 0, Gen2Credits.BORDER_BOTTOM_ROW_GOLD_SILVER + 1), 0,
		"and the second banner starts under it"
	)


## `wAttrmap`: the banner, the two bands and the text region. Gold and Silver
## give the bands and the text one slot and both banners the other.
func test_the_attribute_map_is_the_three_slots_the_profile_uses() -> void:
	var crystal: PackedInt32Array = Gen2Credits.create(_data).attributes()
	assert_eq(_cell(crystal, 0, 0), Gen2Credits.PALETTE_BANNER)
	assert_eq(_cell(crystal, 0, Gen2Credits.BORDER_TOP_ROW), Gen2Credits.PALETTE_BORDER)
	assert_eq(_cell(crystal, 0, Gen2Credits.TEXT_TOP_ROW), Gen2Credits.PALETTE_TEXT)
	assert_eq(_cell(crystal, 0, Gen2Credits.BORDER_BOTTOM_ROW), Gen2Credits.PALETTE_BORDER)

	var gold: PackedInt32Array = Gen2Credits.create(_gold()).attributes()
	assert_eq(_cell(gold, 0, 0), Gen2Credits.PALETTE_BANNER)
	assert_eq(_cell(gold, 0, Gen2Credits.TEXT_TOP_ROW), Gen2Credits.PALETTE_BORDER)
	assert_eq(
		_cell(gold, 0, Gen2Credits.BORDER_BOTTOM_ROW_GOLD_SILVER + 1),
		Gen2Credits.PALETTE_BANNER
	)


## `.Jumptable` is thirteen entries and `ParseCredits` is the first, so one
## `CREDITS_WAIT` tick costs thirteen frames.
func test_a_wait_tick_is_a_whole_jumptable_cycle() -> void:
	var credits: Gen2Credits = Gen2Credits.create(_data)
	_spend(credits, 1)
	assert_eq(credits.timer(), FIRST_WAIT)

	_spend(credits, Gen2Credits.CYCLE_FRAMES - 1)
	assert_eq(credits.timer(), FIRST_WAIT, "and nothing else in the cycle spends one")

	_spend(credits, 1)
	assert_eq(credits.timer(), FIRST_WAIT - 1)


## `.print`: the string's line operand is two rows per step from row 6, and
## `NextLineChar` drops two more at the string's own starting column.
func test_a_string_prints_two_rows_a_line_and_wraps_at_its_own_column() -> void:
	var credits: Gen2Credits = Gen2Credits.create(_data)
	_spend(credits, Gen2Credits.CYCLE_FRAMES * (FIRST_WAIT + 1))
	var map: PackedInt32Array = credits.bg_map()
	## `db CREDITS_STAFF, 1`, whose string is "#", a letter, `<NEXT>`, a letter.
	var row: int = Gen2Credits.TEXT_TOP_ROW + Gen2Credits.TEXT_LINE_SPACING
	var poke: PackedByteArray = Gen2Text.encode(Gen2Credits.POKE_TEXT)
	for index: int in poke.size():
		assert_eq(_cell(map, index, row), poke[index], "# is a string, not a tile")
	assert_eq(_cell(map, poke.size(), row), 0x85)
	assert_eq(_cell(map, 0, row + Gen2Credits.TEXT_LINE_SPACING), 0x86)


## `.copyright`'s own `hlcoord 2, 6`, the one string that does not start at
## column 0.
func test_the_copyright_string_starts_two_columns_in() -> void:
	var credits: Gen2Credits = Gen2Credits.create(_data)
	## Past the staff wait, the music beat's two waits and the two names' wait.
	_spend(credits, Gen2Credits.CYCLE_FRAMES * 11)
	var map: PackedInt32Array = credits.bg_map()
	var row: int = Gen2Credits.TEXT_TOP_ROW + Gen2Credits.TEXT_LINE_SPACING
	assert_eq(
		_cell(map, Gen2Credits.COPYRIGHT_COLUMN, row), RomLayout.COPYRIGHT_FIRST_CODE
	)
	assert_eq(
		_cell(map, Gen2Credits.COPYRIGHT_COLUMN, row + Gen2Credits.TEXT_LINE_SPACING),
		RomLayout.COPYRIGHT_FIRST_CODE + 2,
		"and its <NEXT> keeps that column"
	)


## `CREDITS_WAIT2` leaves `hBGMapMode` off, so the batch it closes is written to
## the tilemap and never copied to the BG map.
func test_a_wait2_batch_is_written_and_never_shown() -> void:
	var credits: Gen2Credits = Gen2Credits.create(_data)
	## The staff batch, then the one holding `CREDITS_MUSIC` and `CREDITS_WAIT2`.
	_spend(credits, Gen2Credits.CYCLE_FRAMES * (FIRST_WAIT + 1) + 1)
	var row: int = Gen2Credits.TEXT_TOP_ROW + Gen2Credits.TEXT_LINE_SPACING
	assert_eq(
		_cell(credits.tilemap(), 0, row), Gen2Credits.BLANK_TILE,
		"the tilemap has been cleared"
	)
	assert_ne(
		_cell(credits.bg_map(), 0, row), Gen2Credits.BLANK_TILE,
		"and the staff batch is still on screen"
	)


## `.end` clears the text region and returns without turning the copy back on,
## which is the whole reason "The End" stays up.
func test_the_end_survives_the_clear_in_front_of_credits_end() -> void:
	var credits: Gen2Credits = Gen2Credits.create(_data)
	_spend(credits, Gen2Credits.CYCLE_FRAMES * 40)
	assert_true(credits.finished())
	assert_eq(
		_cell(credits.bg_map(), Gen2Credits.THE_END_AT.x, Gen2Credits.THE_END_AT.y),
		Gen2Credits.THE_END_TILE
	)
	assert_eq(
		_cell(credits.tilemap(), Gen2Credits.THE_END_AT.x, Gen2Credits.THE_END_AT.y),
		Gen2Credits.BLANK_TILE,
		"and the tilemap under it was cleared"
	)


## `Credits_LoadBorderGFX` draws the frame the counter holds and steps it
## afterwards, and `.init` neither draws nor steps while the banner is cleared.
func test_the_banner_steps_once_per_graphics_request() -> void:
	var credits: Gen2Credits = Gen2Credits.create(_data)
	_spend(credits, Gen2Credits.CYCLE_FRAMES)
	assert_eq(credits.banner_block(), -1, "CREDITS_CLEAR holds it blank")

	## Past the two names' `CREDITS_SCENE, 1`, which is the fixture's own scene.
	_spend(credits, Gen2Credits.CYCLE_FRAMES * 7)
	var blocks: Array = []
	for _cycle: int in 3:
		_spend(credits, Gen2Credits.CYCLE_FRAMES)
		blocks.append(credits.banner_block())
	assert_eq(blocks.size(), 3)
	assert_ne(blocks[0], blocks[1], "and it is a different frame each cycle")


## Crystal requests graphics twice a cycle and Gold and Silver once, so the same
## number of cycles walks the banner twice as far on Crystal.
func test_crystal_steps_the_banner_twice_a_cycle() -> void:
	assert_eq(Gen2Credits.GFX_STEPS.size(), 2)
	assert_eq(Gen2Credits.GFX_STEPS_GOLD_SILVER.size(), 1)


## `Credits_LYOverride`'s `dec a / dec a`, which Gold and Silver replace with
## `inc a / inc a`. It is a byte, so Crystal's first step wraps.
func test_the_border_scroll_walks_two_pixels_a_cycle_each_way() -> void:
	var crystal: Gen2Credits = Gen2Credits.create(_data)
	_spend(crystal, Gen2Credits.CYCLE_FRAMES)
	assert_eq(crystal.scroll(), 0xFE)

	var gold: Gen2Credits = Gen2Credits.create(_gold())
	_spend(gold, Gen2Credits.CYCLE_FRAMES)
	assert_eq(gold.scroll(), 2)


## `.music`'s two `PlayMusic` calls, which the screen hands to the overworld's
## own player, and `.end`'s fade into MUSIC_POST_CREDITS.
func test_the_script_asks_for_its_music_and_fades_into_the_next() -> void:
	var credits: Gen2Credits = Gen2Credits.create(_data)
	var events: Array = _spend(credits, Gen2Credits.CYCLE_FRAMES * 40)
	var kinds: Array = []
	for event: Dictionary in events:
		kinds.append([StringName(event["type"]), int(event["music"])])
	assert_eq(kinds, [
		[&"music_requested", Gen2Credits.MUSIC_CREDITS],
		[&"music_fade_requested", Gen2Credits.MUSIC_POST_CREDITS],
	])


## `Credits_HandleBButton`, which refuses until the script has passed its header
## and refuses entirely without STATUSFLAGS_HALL_OF_FAME_F.
func test_b_only_skips_on_a_replay_and_only_past_the_header() -> void:
	var first: Gen2Credits = Gen2Credits.create(_data, false)
	_spend(first, Gen2Credits.CYCLE_FRAMES * 2, [Gen2Button.B])
	assert_eq(first.timer(), FIRST_WAIT - 1, "an unskippable run spends one tick a cycle")

	var replay: Gen2Credits = Gen2Credits.create(_data, true)
	_spend(replay, 1, [Gen2Button.B])
	assert_lt(
		replay.position(), Gen2Credits.SKIP_FROM_POSITION,
		"the header is still under the skip's own position"
	)
	assert_eq(replay.timer(), FIRST_WAIT, "so nothing was burned yet")

	_spend(replay, Gen2Credits.CYCLE_FRAMES * 7, [Gen2Button.B])
	assert_gt(replay.position(), Gen2Credits.SKIP_FROM_POSITION)
	var standing: int = replay.timer()
	_spend(replay, 2, [Gen2Button.B])
	assert_eq(replay.timer(), standing - 2, "and past it a held B burns a tick a frame")


## `Credits_HandleAButton` tests JUMPTABLE_EXIT_F, so A does nothing until the
## script has run out.
func test_a_only_leaves_once_the_script_has_run_out() -> void:
	var credits: Gen2Credits = Gen2Credits.create(_data)
	assert_false(credits.may_finish([Gen2Button.A]))
	_spend(credits, Gen2Credits.CYCLE_FRAMES * 40)
	assert_true(credits.finished())
	assert_false(credits.may_finish([]), "and it is a held button, not a state")
	assert_true(credits.may_finish([Gen2Button.A]))


## The page resolves a banner tile through `.Frames`' block rather than through
## the strip's own position, which is what makes one sheet four animations.
func test_the_page_draws_the_banner_out_of_the_block_the_frame_names() -> void:
	var page: Gen2CreditsPage = Gen2CreditsPage.from_data(_data)
	assert_true(page.ready())
	var credits: Gen2Credits = Gen2Credits.create(_data)
	var map: PackedInt32Array = credits.bg_map()
	for block: int in [0, 1, 2]:
		var indices: PackedByteArray = page.compose(map, block)
		assert_eq(
			indices[0], block % Fixture.CREDITS_BLOCK_INDEXES,
			"block %d draws its own tiles" % block
		)
	assert_eq(
		page.compose(map, -1)[0], Gen2Credits.BLANK_FRAME_INDEX,
		"and a cleared banner is the solid frame, not an empty cell"
	)


## `GetCreditsPalette`'s Gold and Silver branch blacks out the last colour of the
## slot the border and the text share, which is the one the font's ink lands on.
func test_gold_blacks_out_the_text_slots_last_colour() -> void:
	var gold: GameData = _gold()
	var page: Gen2CreditsPage = Gen2CreditsPage.from_data(gold)
	var border: PackedColorArray = page.palette(gold, 0, Gen2Credits.PALETTE_BORDER)
	assert_eq(border[RomLayout.CREDITS_PALETTE_COLORS - 1], Color.BLACK)
	assert_ne(
		page.palette(gold, 0, Gen2Credits.PALETTE_BANNER)[
			RomLayout.CREDITS_PALETTE_COLORS - 1
		],
		Color.BLACK,
		"and the banner keeps its own"
	)

	var crystal_page: Gen2CreditsPage = Gen2CreditsPage.from_data(_data)
	assert_ne(
		crystal_page.palette(_data, 0, Gen2Credits.PALETTE_BORDER)[
			RomLayout.CREDITS_PALETTE_COLORS - 1
		],
		Color.BLACK,
		"and Crystal's three palettes are left alone"
	)


## `hLCDCPointer` is LOW(rSCX) and `Credits_LYOverride` fills only the two border
## bands, so nothing else on the screen moves with it.
func test_only_the_border_rows_are_scrolled() -> void:
	var credits: Gen2Credits = Gen2Credits.create(_data)
	assert_eq(credits.scroll_rows(), [
		Gen2Credits.BORDER_TOP_ROW, Gen2Credits.BORDER_BOTTOM_ROW,
	])
	assert_eq(
		Gen2Credits.create(_gold()).scroll_rows(),
		[Gen2Credits.BORDER_TOP_ROW, Gen2Credits.BORDER_BOTTOM_ROW_GOLD_SILVER]
	)
