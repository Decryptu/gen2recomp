extends GutTest

## The induction sequence and the panel it draws, against a synthetic cache.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

const TILE: int = Gen2Font.TILE

## `Rate`'s two texts, one box each at the fixture's short lengths.
const RATING_PAGES: int = 2

var _data: GameData = null


func before_each() -> void:
	Fixture.build()
	_data = GameData.open_directory(Fixture.directory())


func after_each() -> void:
	RomCache.clear(Fixture.directory())


func _save(species_list: Array, eggs: Array = []) -> Gen2SaveData:
	var save := Gen2SaveData.new()
	save.player_name = "ASH"
	for index: int in species_list.size():
		var mon := Gen2SaveMon.new()
		mon.species = int(species_list[index])
		mon.level = 10 + index
		mon.ot_id = 1234
		mon.is_egg = index in eggs
		save.party.append(mon)
	return save


func test_pages_follow_the_party_and_end_with_the_player() -> void:
	var pages: Array = Gen2HallOfFame.pages(_data, _save([1, 4]))
	assert_eq(pages.size(), 2 + RATING_PAGES)
	assert_eq(StringName(pages[0]["kind"]), Gen2HallOfFame.PAGE_MON)
	assert_eq(int(pages[0]["species"]), 1)
	assert_eq(int(pages[0]["dex_number"]), 1)
	assert_eq(int(pages[1]["species"]), 4)
	assert_eq(StringName(pages[2]["kind"]), Gen2HallOfFame.PAGE_PLAYER)
	assert_eq(String(pages[2]["player_name"]), "ASH")


## `HOF_AnimatePlayerPic` ends on `farcall ProfOaksPCRating`, so the player's
## panel is answered once per box its two texts fill, and the sound the rating
## picked plays on the last of them.
func test_the_player_panel_carries_the_oak_rating() -> void:
	var pages: Array = Gen2HallOfFame.pages(_data, _save([1]))
	var counts: Dictionary = pages[1]
	var rating: Dictionary = pages[2]
	assert_eq(StringName(counts["kind"]), Gen2HallOfFame.PAGE_PLAYER)
	assert_eq(StringName(rating["kind"]), Gen2HallOfFame.PAGE_PLAYER)
	assert_string_contains(String((counts["lines"] as Array)[0]), "SEEN")
	assert_eq(String((rating["lines"] as Array)[0]), "RATING01", "nothing caught")
	assert_false(counts.has("sfx"), "the sound is on the rating, not the counts")
	assert_eq(int(rating["sfx"]), Fixture.OAK_FIRST_SFX)


## A cache with no rating table leaves the panel the source never stops on.
func test_a_cache_without_the_ratings_shows_the_bare_panel() -> void:
	var manifest: Dictionary = RomCache.read_manifest(Fixture.directory())
	manifest.erase("oak_ratings")
	RomCache.write_json(RomCache.manifest_path(Fixture.directory()), manifest)
	var data: GameData = GameData.open_directory(Fixture.directory())
	var pages: Array = Gen2HallOfFame.pages(data, _save([1]))
	assert_eq(pages.size(), 2)
	assert_false(pages[1].has("lines"))


## GetHallOfFameParty skips EGG without consuming a slot, so the egg is neither
## inducted nor counted against the six.
func test_an_egg_is_skipped_and_the_player_page_still_follows() -> void:
	var pages: Array = Gen2HallOfFame.pages(_data, _save([1, 4, 7], [1]))
	assert_eq(pages.size(), 2 + RATING_PAGES)
	assert_eq(int(pages[0]["species"]), 1)
	assert_eq(int(pages[1]["species"]), 7)
	assert_eq(StringName(pages[2]["kind"]), Gen2HallOfFame.PAGE_PLAYER)


## LoadHOFTeam's carry falls straight through to HOF_AnimatePlayerPic, so a
## party with nothing to induct still reaches the player's own panel.
func test_a_party_of_only_eggs_answers_the_player_page_alone() -> void:
	var pages: Array = Gen2HallOfFame.pages(_data, _save([1, 4], [0, 1]))
	assert_eq(pages.size(), RATING_PAGES)
	assert_eq(StringName(pages[0]["kind"]), Gen2HallOfFame.PAGE_PLAYER)


## DisplayHOFMon prints the species name and the nickname in two places, so a
## mon that was never renamed shows the same word twice rather than a blank.
func test_an_unnamed_mon_takes_its_species_name_as_its_nickname() -> void:
	var pages: Array = Gen2HallOfFame.pages(_data, _save([1]))
	assert_eq(String(pages[0]["nickname"]), String(pages[0]["species_name"]))
	assert_false(String(pages[0]["species_name"]).is_empty())


func test_a_nickname_is_kept() -> void:
	var save: Gen2SaveData = _save([1])
	(save.party[0] as Gen2SaveMon).nickname = "SPARKY"
	var pages: Array = Gen2HallOfFame.pages(_data, save)
	assert_eq(String(pages[0]["nickname"]), "SPARKY")


func test_pages_stop_at_a_full_party() -> void:
	var pages: Array = Gen2HallOfFame.pages(_data, _save([1, 2, 3, 4, 5, 6, 7]))
	assert_eq(pages.size(), Gen2HallOfFame.MAX_MONS + RATING_PAGES)


func test_a_missing_cache_or_save_answers_nothing() -> void:
	assert_eq(Gen2HallOfFame.pages(null, _save([1])).size(), 0)
	assert_eq(Gen2HallOfFame.pages(_data, null).size(), 0)


## The panel is drawn as indices on the hardware's own grid, so the whole page
## is one 160x144 buffer and the two text boxes are really in it.
func test_a_mon_panel_draws_both_boxes_on_a_full_screen_buffer() -> void:
	var page_renderer: Gen2HallOfFamePage = Gen2HallOfFamePage.from_data(_data)
	assert_not_null(page_renderer)
	var pages: Array = Gen2HallOfFame.pages(_data, _save([1]))
	var indices: PackedByteArray = page_renderer.draw(pages[0])
	assert_eq(indices.size(), Gen2Screen.WIDTH * Gen2Screen.HEIGHT)
	assert_true(_has_ink(indices, Gen2HallOfFamePage.MON_TOP_BOX))
	assert_true(_has_ink(indices, Gen2HallOfFamePage.MON_BOTTOM_BOX))


## `HOF_AnimatePlayerPic` opens the bottom box empty for the rating to print
## into, so the player's panel draws both.
func test_the_player_panel_draws_its_name_box_and_the_rating_box() -> void:
	var page_renderer: Gen2HallOfFamePage = Gen2HallOfFamePage.from_data(_data)
	var pages: Array = Gen2HallOfFame.pages(_data, _save([1]))
	var indices: PackedByteArray = page_renderer.draw(pages[1])
	assert_eq(indices.size(), Gen2Screen.WIDTH * Gen2Screen.HEIGHT)
	assert_true(_has_ink(indices, Gen2HallOfFamePage.PLAYER_BOX))
	assert_true(_has_ink(indices, Gen2HallOfFamePage.MON_BOTTOM_BOX))


## Any non-zero palette index inside a tile rectangle. Index 0 is the page's
## own background, so ink means something was drawn there.
func _has_ink(indices: PackedByteArray, box: Rect2i) -> bool:
	for row: int in box.size.y * TILE:
		var y: int = box.position.y * TILE + row
		for column: int in box.size.x * TILE:
			var at: int = y * Gen2Screen.WIDTH + box.position.x * TILE + column
			if at < indices.size() and indices[at] != 0:
				return true
	return false


## The panel's columns are DisplayHOFMon's own. They were one tile right of it
## while plain words stood in for the glyphs the battle-extra strip carries, so
## the positions are pinned rather than left to the next reader to notice.
func test_the_panel_sits_on_the_source_columns() -> void:
	assert_eq(Gen2HallOfFamePage.DEX_LABEL, Vector2i(1, 13), "hlcoord 1, 13")
	assert_eq(Gen2HallOfFamePage.DEX_NUMBER, Vector2i(3, 13), "hlcoord 3, 13")
	assert_eq(Gen2HallOfFamePage.SPECIES_NAME, Vector2i(7, 13), "hlcoord 7, 13")
	assert_eq(Gen2HallOfFamePage.GENDER, Vector2i(18, 13), "hlcoord 18, 13")
	assert_eq(Gen2HallOfFamePage.NICKNAME_SLASH, Vector2i(8, 14), "hlcoord 8, 14")
	assert_eq(Gen2HallOfFamePage.LEVEL, Vector2i(1, 16), "hlcoord 1, 16")
	assert_eq(Gen2HallOfFamePage.OT_LABEL, Vector2i(7, 16), "hlcoord 7, 16")
	assert_eq(Gen2HallOfFamePage.OT_NUMBER, Vector2i(10, 16), "hlcoord 10, 16")
	# And the glyphs it places are the charmap's, read under the strip
	# halloffame.asm loads before printing any of this.
	assert_eq(Gen2HallOfFamePage.FONT, Gen2Text.FONT_BATTLE_EXTRA)
	assert_eq(
		Gen2Text.character(Gen2HallOfFamePage.CODE_NUMERO, Gen2HallOfFamePage.FONT), "№"
	)
	assert_eq(Gen2Text.character(Gen2HallOfFamePage.CODE_ID, Gen2HallOfFamePage.FONT), "<ID>")
	assert_eq(Gen2Text.character(Gen2HallOfFamePage.CODE_LEVEL, Gen2HallOfFamePage.FONT), "<LV>")
	assert_eq(Gen2Text.character(Gen2HallOfFamePage.CODE_DOT), ".")
	assert_eq(Gen2Text.character(Gen2HallOfFamePage.CODE_SLASH), "/")


## The three glyphs stood in as words before, so the columns they occupy are
## what proves they are drawn now: the dex label is two tiles, not three, and
## column 6 is the blank the source leaves before the name.
func test_the_dex_row_draws_two_label_tiles_and_leaves_column_six_blank() -> void:
	var page_renderer: Gen2HallOfFamePage = Gen2HallOfFamePage.from_data(_data)
	assert_not_null(page_renderer)
	var pages: Array = Gen2HallOfFame.pages(_data, _save([1]))
	var indices: PackedByteArray = page_renderer.draw(pages[0])
	# The fixture fills each sheet with an index of its own, so a drawn pixel
	# says which strip it came from: 1 is battle_font, 3 is the main font.
	assert_eq(_index_at(indices, Vector2i(1, 13)), 1, "№ comes off the battle strip")
	assert_eq(_index_at(indices, Vector2i(2, 13)), 3, "the dot is a main-font code")
	assert_eq(_index_at(indices, Vector2i(6, 13)), 0, "the blank before the name")
	assert_eq(_index_at(indices, Vector2i(7, 13)), 3, "the name starts at 7")
	assert_eq(_index_at(indices, Vector2i(1, 16)), 1, "the level symbol")
	assert_eq(_index_at(indices, Vector2i(7, 16)), 1, "<ID>")
	assert_eq(_index_at(indices, Vector2i(8, 16)), 1, "№")


## The palette index of a tile's top-left pixel.
func _index_at(indices: PackedByteArray, tile: Vector2i) -> int:
	var at: int = tile.y * TILE * Gen2Screen.WIDTH + tile.x * TILE
	return indices[at] if at < indices.size() else -1
