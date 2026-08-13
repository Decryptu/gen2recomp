extends GutTest

## What `GameFreakPresents` draws: a cleared background, the two `PlaceString`s
## on it, and the object layer over the top. The fixture's sheets are flat fills,
## so what is checked is where each tile lands and which palette it is read
## through, not the picture.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")
const Presents := preload("res://game/world/game_freak_presents.gd")

## PREDEFPAL_GAMEFREAK_LOGO_BG's first colour, which the cleared map is drawn in.
const BACKGROUND := Color(0, 0, 0, 1)


func after_each() -> void:
	RomCache.clear(Fixture.directory())
	RomCache.clear(Fixture.directory(RomRegistry.CRYSTAL))


func _page(game_id: StringName) -> Gen2GameFreakPresentsPage:
	return Gen2GameFreakPresentsPage.from_data(Fixture.build(game_id))


func _run(game_id: StringName, frames: int) -> Gen2GameFreakPresents:
	var phase := Presents.new()
	phase.start(game_id)
	for _frame: int in frames:
		phase.advance_frame()
	return phase


## `ClearTilemap` runs before anything else and the words are placed onto it, so
## the screen opens black and stays black everywhere the two strings are not.
func test_the_screen_opens_cleared_and_the_words_land_on_their_own_rows() -> void:
	var page: Gen2GameFreakPresentsPage = _page(&"gold")
	assert_not_null(page)
	var blank: Image = page.draw(_run(&"gold", 0))
	assert_eq(blank.get_size(), Vector2i(Gen2Screen.WIDTH, Gen2Screen.HEIGHT))
	for at: Vector2i in [Vector2i(0, 0), Vector2i(44, 100), Vector2i(159, 143)]:
		assert_eq(blank.get_pixelv(at), BACKGROUND, "cleared at %v" % at)

	# Gold places "GAME FREAK" at (5,12) and "PRESENTS" at (7,13).
	var both: Image = page.draw(_run(&"gold", 196))
	var rows: Array[Vector2i] = Presents.WORD_AT_GOLD
	assert_ne(both.get_pixelv(rows[0] * Gen2Tiles.TILE_WIDTH), BACKGROUND, "GAME FREAK")
	assert_ne(both.get_pixelv(rows[1] * Gen2Tiles.TILE_WIDTH), BACKGROUND, "PRESENTS")
	assert_eq(
		both.get_pixelv(Vector2i(rows[0].x - 1, rows[0].y) * Gen2Tiles.TILE_WIDTH),
		BACKGROUND, "and nothing in front of them"
	)


## The sprite is drawn where its shadow-OAM coordinate puts it, which is eight
## less across and sixteen less down. Crystal's Ditto is off screen on its first
## frame, and on the ground it covers the cell `depixel 10, 11, 4, 0` names.
func test_the_ditto_is_drawn_where_its_oam_coordinate_puts_it() -> void:
	var page: Gen2GameFreakPresentsPage = _page(RomRegistry.CRYSTAL)
	assert_not_null(page)
	var hidden: Image = page.draw(_run(RomRegistry.CRYSTAL, 1))
	assert_true(_is_blank(hidden), "OAM_YCOORD_HIDDEN")

	# `.OAMData_GameFreakLogo1_3` runs from (-12, -16) to (12, 8) of the
	# coordinate, so the block's own corner is drawn and the pixel outside it is
	# not.
	var landed: Image = page.draw(_run(RomRegistry.CRYSTAL, 18))
	var origin: Vector2i = Presents.SPRITE_AT - Gen2GameFreakPresentsPage.OAM_ORIGIN
	assert_ne(landed.get_pixelv(origin + Vector2i(-12, -16)), BACKGROUND)
	assert_ne(landed.get_pixelv(origin + Vector2i(11, 7)), BACKGROUND)
	assert_eq(landed.get_pixelv(origin + Vector2i(-13, -16)), BACKGROUND)
	assert_eq(landed.get_pixelv(origin + Vector2i(-12, -17)), BACKGROUND)


## `GameFreakLogo_Transform` fades the Ditto's third colour, which is the one the
## sprite's own pixels are drawn in, so the picture changes colour without the
## graphic changing at all.
func test_the_transform_changes_the_colour_the_ditto_is_drawn_in() -> void:
	var page: Gen2GameFreakPresentsPage = _page(RomRegistry.CRYSTAL)
	var before: Image = page.draw(_run(RomRegistry.CRYSTAL, 85))
	var after: Image = page.draw(_run(RomRegistry.CRYSTAL, 145))
	assert_ne(_first_drawn(before), BACKGROUND)
	assert_ne(_first_drawn(before), _first_drawn(after))


## Gold's cache carries no Ditto and Crystal's no star sheet, and each page reads
## only the one its profile ships.
func test_each_profile_draws_out_of_its_own_sheets() -> void:
	var gold: Image = _page(&"gold").draw(_run(&"gold", 30))
	assert_false(_is_blank(gold), "the star is up")
	var crystal: Image = _page(RomRegistry.CRYSTAL).draw(_run(RomRegistry.CRYSTAL, 145))
	assert_false(_is_blank(crystal), "the Ditto is up")


## A cache imported before the splash art was carries no sheet, which is the
## host's cue to skip the phase rather than to draw an empty one.
func test_a_cache_without_the_art_does_not_open() -> void:
	assert_null(Gen2GameFreakPresentsPage.from_data(null))


func _is_blank(image: Image) -> bool:
	return _first_drawn(image) == BACKGROUND


func _first_drawn(image: Image) -> Color:
	for y: int in image.get_height():
		for x: int in image.get_width():
			var color: Color = image.get_pixel(x, y)
			if color != BACKGROUND:
				return color
	return BACKGROUND
