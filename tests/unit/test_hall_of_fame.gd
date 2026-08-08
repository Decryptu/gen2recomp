extends GutTest

## The induction sequence and the panel it draws, against a synthetic cache.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

const TILE: int = Gen2Font.TILE

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
	assert_eq(pages.size(), 3)
	assert_eq(StringName(pages[0]["kind"]), Gen2HallOfFame.PAGE_MON)
	assert_eq(int(pages[0]["species"]), 1)
	assert_eq(int(pages[0]["dex_number"]), 1)
	assert_eq(int(pages[1]["species"]), 4)
	assert_eq(StringName(pages[2]["kind"]), Gen2HallOfFame.PAGE_PLAYER)
	assert_eq(String(pages[2]["player_name"]), "ASH")


## GetHallOfFameParty skips EGG without consuming a slot, so the egg is neither
## inducted nor counted against the six.
func test_an_egg_is_skipped_and_the_player_page_still_follows() -> void:
	var pages: Array = Gen2HallOfFame.pages(_data, _save([1, 4, 7], [1]))
	assert_eq(pages.size(), 3)
	assert_eq(int(pages[0]["species"]), 1)
	assert_eq(int(pages[1]["species"]), 7)
	assert_eq(StringName(pages[2]["kind"]), Gen2HallOfFame.PAGE_PLAYER)


## LoadHOFTeam's carry falls straight through to HOF_AnimatePlayerPic, so a
## party with nothing to induct still reaches the player's own panel.
func test_a_party_of_only_eggs_answers_the_player_page_alone() -> void:
	var pages: Array = Gen2HallOfFame.pages(_data, _save([1, 4], [0, 1]))
	assert_eq(pages.size(), 1)
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
	assert_eq(pages.size(), Gen2HallOfFame.MAX_MONS + 1)


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


## The player's page is the name box alone: nothing is drawn where the mon
## panel's bottom box would be, because the source's fields there have no data.
func test_the_player_panel_draws_its_own_box_only() -> void:
	var page_renderer: Gen2HallOfFamePage = Gen2HallOfFamePage.from_data(_data)
	var pages: Array = Gen2HallOfFame.pages(_data, _save([1]))
	var indices: PackedByteArray = page_renderer.draw(pages[1])
	assert_eq(indices.size(), Gen2Screen.WIDTH * Gen2Screen.HEIGHT)
	assert_true(_has_ink(indices, Gen2HallOfFamePage.PLAYER_BOX))
	assert_false(_has_ink(indices, Gen2HallOfFamePage.MON_BOTTOM_BOX))


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
