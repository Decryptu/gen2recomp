extends GutTest

## engine/pokedex/pokedex.asm, as the listing order, the cursor walk and the
## entry the screen prints.

const Fixture := preload("res://tests/unit/pokedex_fixture.gd")

const MOD_SPECIES: int = Gen2ContentOverlay.FIRST_MOD_NUMBER

var _data: GameData = null


func before_each() -> void:
	_data = Fixture.build()


func after_each() -> void:
	RomCache.clear(Fixture.directory())


func _state(seen: Array, caught: Array = []) -> Gen2WorldState:
	var seen_map: Dictionary = {}
	for species: int in seen:
		seen_map[species] = true
	var caught_map: Dictionary = {}
	for species: int in caught:
		caught_map[species] = true
	return Gen2WorldState.new(
		{}, {}, {}, {}, 0, {}, 0, Vector2i(-1, -1), 0, [], false, 0,
		Gen2WorldState.PHONE_RECEIVE_DELAYS[0], 0, seen_map, {}, {}, caught_map
	)


func _dex(seen: Array, caught: Array = [], mode: int = RomLayout.DEXMODE_NEW,
	previous: int = 0) -> Gen2Pokedex:
	return Gen2Pokedex.open(_data, _state(seen, caught), mode, previous)


## `.NewMode` copies NewPokedexOrder whole, and `.OldMode` counts from 1.
func test_new_mode_lists_the_new_dex_table_and_old_mode_the_species_range() -> void:
	var new_dex: Gen2Pokedex = _dex([RomLayout.SPECIES_COUNT])
	assert_eq(new_dex.rows()[0]["species"], RomLayout.SPECIES_COUNT)

	var old_dex: Gen2Pokedex = _dex([1], [], RomLayout.DEXMODE_OLD)
	var species: Array = []
	for row: Dictionary in old_dex.rows():
		species.append(int(row["species"]))
	assert_eq(species, [1, 2, 3, 4, 5, 6, 7])


## `Pokedex_ABCMode` keeps only the species that have been seen, and
## `wDexListingEnd` is that count.
func test_abc_mode_lists_only_seen_species_and_zero_fills_the_tail() -> void:
	# 4 and 8 are the first two even numbers in the fixture's alphabetical
	# table, and 3 is the first odd one, so ABC order puts them in that order.
	var dex: Gen2Pokedex = _dex([3, 4, 8], [], RomLayout.DEXMODE_ABC)
	assert_eq(dex.listing_end, 3)
	var rows: Array = dex.rows()
	assert_eq(int(rows[0]["species"]), 4)
	assert_eq(int(rows[1]["species"]), 8)
	assert_eq(int(rows[2]["species"]), 3)
	assert_true(bool(rows[3]["empty"]), "the tail past the seen species is zero")


## `.FindLastSeen` answers the last seen species' position in the order, which
## is not the number of species seen.
func test_listing_end_is_the_last_seen_position_not_a_count() -> void:
	# The fixture's new order runs backwards, so species 251 is at position 1
	# and species 249 at position 3.
	var dex: Gen2Pokedex = _dex([251, 249])
	assert_eq(dex.listing_end, 3)


func test_listing_end_is_zero_when_nothing_has_been_seen() -> void:
	assert_eq(_dex([]).listing_end, 0)


## `.PrintEntry`: an unseen row is the default string and nothing else, a seen
## row carries the name, and only a caught one carries the symbol.
func test_a_row_shows_a_name_only_once_seen_and_a_symbol_only_once_caught() -> void:
	var dex: Gen2Pokedex = _dex([251, 250], [250], RomLayout.DEXMODE_OLD)
	dex.scroll = 249
	var rows: Array = dex.rows()
	assert_eq(String(rows[0]["name"]), Fixture.species_name(250))
	assert_true(bool(rows[0]["caught"]))
	assert_eq(String(rows[1]["name"]), Fixture.species_name(251))
	assert_false(bool(rows[1]["caught"]), "seen but not caught")

	var unseen: Gen2Pokedex = _dex([251], [], RomLayout.DEXMODE_OLD)
	assert_eq(String(unseen.rows()[0]["name"]), Gen2Pokedex.NOT_SEEN_NAME)
	assert_false(bool(unseen.rows()[0]["seen"]))


## `Pokedex_PrintNumberIfOldMode` prints a number in OLD mode only.
func test_only_old_mode_numbers_its_rows() -> void:
	assert_eq(String(_dex([1], [], RomLayout.DEXMODE_OLD).rows()[0]["number"]), "001")
	assert_eq(String(_dex([251]).rows()[0]["number"]), "")


## `Pokedex_ListingMoveCursorDown` moves the cursor inside the visible rows and
## scrolls once it is at the bottom of them, and refuses at the listing's end.
func test_the_cursor_moves_then_scrolls_and_stops_at_the_end() -> void:
	var dex: Gen2Pokedex = _dex([1], [], RomLayout.DEXMODE_OLD)
	dex.listing_end = 10
	for step: int in Gen2Pokedex.LISTING_HEIGHT - 1:
		assert_true(dex.move_listing(Gen2Button.DOWN))
	assert_eq(dex.cursor, Gen2Pokedex.LISTING_HEIGHT - 1)
	assert_eq(dex.scroll, 0)

	assert_true(dex.move_listing(Gen2Button.DOWN))
	assert_eq(dex.cursor, Gen2Pokedex.LISTING_HEIGHT - 1, "the cursor stays at the bottom row")
	assert_eq(dex.scroll, 1)

	assert_true(dex.move_listing(Gen2Button.DOWN))
	assert_eq(dex.scroll, 2)
	assert_true(dex.move_listing(Gen2Button.DOWN))
	assert_eq(dex.scroll, 3, "ten entries over seven rows scroll three times")
	assert_false(dex.move_listing(Gen2Button.DOWN), "the listing ends at 10")


## `Pokedex_ListingMoveCursorUp` scrolls only once the cursor is at the top.
func test_moving_up_empties_the_cursor_before_it_scrolls() -> void:
	var dex: Gen2Pokedex = _dex([1], [], RomLayout.DEXMODE_OLD)
	dex.listing_end = 20
	dex.cursor = 2
	dex.scroll = 5
	assert_true(dex.move_listing(Gen2Button.UP))
	assert_eq(dex.cursor, 1)
	assert_eq(dex.scroll, 5)
	dex.cursor = 0
	assert_true(dex.move_listing(Gen2Button.UP))
	assert_eq(dex.scroll, 4)

	dex.scroll = 0
	assert_false(dex.move_listing(Gen2Button.UP), "nothing above the top")


## `Pokedex_ListingHandleDPadInput` checks the height against the listing end
## before it reads left or right at all.
func test_paging_is_refused_while_the_listing_fits_on_one_screen() -> void:
	var dex: Gen2Pokedex = _dex([1], [], RomLayout.DEXMODE_OLD)
	dex.listing_end = Gen2Pokedex.LISTING_HEIGHT
	assert_false(dex.move_listing(Gen2Button.RIGHT))
	assert_false(dex.move_listing(Gen2Button.LEFT))
	assert_eq(dex.scroll, 0)


## `Pokedex_ListingMoveDownOnePage` and `..._MoveUpOnePage`.
func test_a_page_moves_a_screen_and_clamps_to_either_end() -> void:
	var dex: Gen2Pokedex = _dex([1], [], RomLayout.DEXMODE_OLD)
	dex.listing_end = 30
	assert_true(dex.move_listing(Gen2Button.RIGHT))
	assert_eq(dex.scroll, Gen2Pokedex.LISTING_HEIGHT)

	dex.scroll = 25
	assert_true(dex.move_listing(Gen2Button.RIGHT))
	assert_eq(dex.scroll, 30 - Gen2Pokedex.LISTING_HEIGHT, "clamped to the last page")

	assert_true(dex.move_listing(Gen2Button.LEFT))
	assert_eq(dex.scroll, 30 - Gen2Pokedex.LISTING_HEIGHT * 2)

	dex.scroll = 3
	assert_true(dex.move_listing(Gen2Button.LEFT))
	assert_eq(dex.scroll, 0, "less than a page from the top goes to the top")


## `Pokedex_UpdateMainScreen`'s A refuses a species that has not been seen.
func test_the_entry_screen_opens_only_for_a_seen_species() -> void:
	var dex: Gen2Pokedex = _dex([250], [], RomLayout.DEXMODE_OLD)
	assert_false(dex.can_open_entry(), "species 1 has not been seen")
	dex.scroll = 249
	assert_true(dex.can_open_entry())


## `DisplayDexEntry` prints the name, the category and the number either way,
## and the caught check gates the measurements and the description.
func test_an_uncaught_entry_shows_its_name_and_category_but_no_measurements() -> void:
	var dex: Gen2Pokedex = _dex([1], [], RomLayout.DEXMODE_OLD)
	var entry: Dictionary = dex.entry()
	assert_eq(String(entry["name"]), Fixture.species_name(1))
	assert_eq(String(entry["category"]), "CAT001")
	assert_eq(String(entry["number"]), "001")
	assert_eq(String(entry["height"]), "")
	assert_eq(String(entry["weight"]), "")
	assert_eq(String(entry["text"]), "")


func test_a_caught_entry_carries_its_measurements_and_both_pages() -> void:
	var dex: Gen2Pokedex = _dex([204], [204], RomLayout.DEXMODE_OLD)
	dex.scroll = 203
	var entry: Dictionary = dex.entry()
	assert_eq(String(entry["text"]), "page one 204")
	dex.toggle_page()
	assert_eq(String(dex.entry()["text"]), "page two 204")
	dex.toggle_page()
	assert_eq(String(dex.entry()["text"]), "page one 204", "the page toggles back")


## `.skip_height` and `.skip_weight` leave a zero measurement blank rather than
## printing a zero.
func test_a_zero_measurement_is_left_blank() -> void:
	RomCache.write_json(RomCache.species_path(Fixture.directory()), [{
		"number": 1, "name": "MON001",
		"dex": {"category": "CAT", "height": 0, "weight": 0, "pages": ["a", "b"]},
	}])
	var data: GameData = GameData.open_directory(Fixture.directory())
	var dex: Gen2Pokedex = Gen2Pokedex.open(
		data, _state([1], [1]), RomLayout.DEXMODE_OLD
	)
	var entry: Dictionary = dex.entry()
	assert_eq(String(entry["height"]), "")
	assert_eq(String(entry["weight"]), "")


## `_PrintNum` with the two calls DisplayDexEntry makes: a blanked leading zero
## leaves a space, and the digit in front of the point always prints.
func test_the_measurements_are_punctuated_the_way_print_num_punctuates_them() -> void:
	assert_eq(Gen2Pokedex.height_text(204), " 2'04\"", "Bulbasaur")
	assert_eq(Gen2Pokedex.height_text(3002), "30'02\"", "Steelix")
	assert_eq(Gen2Pokedex.height_text(8), " 0'08\"", "a zero in front of the point still prints")
	assert_eq(Gen2Pokedex.weight_text(150), "  15.0", "Bulbasaur")
	assert_eq(Gen2Pokedex.weight_text(10140), "1014.0", "Snorlax")
	assert_eq(Gen2Pokedex.weight_text(2), "   0.2")


## `Pokedex_NextOrPreviousDexEntry` keeps moving until it reaches a species that
## has been seen, and puts the cursor back when it runs out.
func test_stepping_through_entries_skips_unseen_species() -> void:
	var dex: Gen2Pokedex = _dex([1, 5], [], RomLayout.DEXMODE_OLD)
	dex.open_entry()
	assert_eq(int(dex.entry()["species"]), 1)
	assert_true(dex.step_entry(Gen2Button.DOWN))
	assert_eq(int(dex.entry()["species"]), 5, "2 through 4 have not been seen")

	assert_false(dex.step_entry(Gen2Button.DOWN), "nothing seen below 5")
	assert_eq(int(dex.entry()["species"]), 5, "the cursor is put back")
	assert_eq(dex.cursor, 4)


func test_stepping_to_a_new_entry_returns_to_page_one() -> void:
	var dex: Gen2Pokedex = _dex([1, 2], [1, 2], RomLayout.DEXMODE_OLD)
	dex.open_entry()
	dex.toggle_page()
	assert_eq(dex.page, Gen2Pokedex.PAGE_2)
	assert_true(dex.step_entry(Gen2Button.DOWN))
	assert_eq(dex.page, Gen2Pokedex.PAGE_1)


## `Pokedex_InitCursorPosition` seeks the cursor to wPrevDexEntry.
func test_the_dex_opens_on_the_last_entry_viewed() -> void:
	var seen: Array = []
	for number: int in range(1, 21):
		seen.append(number)
	var dex: Gen2Pokedex = Gen2Pokedex.open(
		_data, _state(seen), RomLayout.DEXMODE_OLD, 12
	)
	assert_eq(dex.selected_species(), 12)


func test_no_previous_entry_opens_at_the_top() -> void:
	var dex: Gen2Pokedex = _dex([1, 2, 3], [], RomLayout.DEXMODE_OLD)
	assert_eq(dex.cursor, 0)
	assert_eq(dex.scroll, 0)


## `Pokedex_DrawOptionScreenBG` hides UNOWN MODE while wUnlockedUnownMode is
## clear, which is what `Pokedex_CheckUnlockedUnownMode` reads the flag for.
func test_the_option_screen_lists_three_modes_without_the_unown_dex() -> void:
	var rows: Array = Gen2Pokedex.mode_rows()
	assert_eq(rows.size(), 3)
	assert_eq(String(rows[0]["label"]), "NEW #DEX MODE")
	assert_eq(String(rows[2]["label"]), "A to Z MODE")
	assert_eq(Gen2Pokedex.mode_rows(true).size(), 4)


## `.ChangeMode` skips a mode that is already current, and reorders and reseeks
## when it is not.
func test_changing_to_the_current_mode_changes_nothing() -> void:
	var dex: Gen2Pokedex = _dex([1], [], RomLayout.DEXMODE_OLD)
	dex.scroll = 3
	assert_false(dex.change_mode(RomLayout.DEXMODE_OLD))
	assert_eq(dex.scroll, 3, "the listing is left alone")


func test_changing_mode_reorders_and_reseeks_the_previous_entry() -> void:
	var seen: Array = []
	for number: int in range(1, 21):
		seen.append(number)
	var dex: Gen2Pokedex = Gen2Pokedex.open(_data, _state(seen), RomLayout.DEXMODE_OLD, 12)
	assert_eq(dex.selected_species(), 12)
	assert_true(dex.change_mode(RomLayout.DEXMODE_ABC))
	assert_eq(dex.mode, RomLayout.DEXMODE_ABC)
	assert_eq(dex.selected_species(), 12, "the last entry viewed is found again")


## `Pokedex_DrawMainScreenBG`'s two CountSetBits totals.
func test_the_screen_counts_seen_and_owned() -> void:
	var dex: Gen2Pokedex = _dex([1, 2, 3], [1])
	assert_eq(dex.seen_count(), 3)
	assert_eq(dex.caught_count(), 1)


## `Pokedex_InitSearchScreen` opens on NORMAL with the second row empty, and
## does so every time rather than remembering the last search.
func test_the_search_screen_opens_on_normal_with_no_second_type() -> void:
	var dex: Gen2Pokedex = _dex([1])
	dex.search_type_1 = 9
	dex.search_type_2 = 4
	dex.open_search()
	assert_eq(dex.search_type_1, 1)
	assert_eq(dex.search_type_2, Gen2Pokedex.SEARCH_TYPE_NONE)
	assert_eq(dex.search_cursor, Gen2Pokedex.SEARCH_ROW_TYPE_1)


## `PokedexTypeSearchConversionTable`'s order is the search screen's, not the
## type numbering: FIRE follows NORMAL.
func test_the_search_order_is_the_conversion_tables_own() -> void:
	assert_eq(Gen2Pokedex.SEARCH_TYPES.size(), Gen2Pokedex.SEARCH_TYPE_MAX)
	assert_eq(Gen2Pokedex.SEARCH_TYPES[0], RomLayout.TYPE_NORMAL)
	assert_eq(Gen2Pokedex.SEARCH_TYPES[1], RomLayout.TYPE_FIRE)
	assert_eq(Gen2Pokedex.SEARCH_TYPES[Gen2Pokedex.SEARCH_TYPE_MAX - 1], RomLayout.TYPE_STEEL)


## `Pokedex_UpdateSearchMonType` reads left and right on the two type rows only.
func test_the_type_rows_are_the_only_ones_left_and_right_change() -> void:
	var dex: Gen2Pokedex = _dex([1])
	dex.search_cursor = Gen2Pokedex.SEARCH_ROW_BEGIN
	assert_false(dex.move_search_type(Gen2Button.RIGHT))
	dex.search_cursor = Gen2Pokedex.SEARCH_ROW_TYPE_1
	assert_true(dex.move_search_type(Gen2Button.RIGHT))
	assert_eq(dex.search_type_1, 2)


## The two rows wrap differently: the first never empties, and the second wraps
## through the empty value, which is the only way back to a one-type search.
func test_the_first_row_never_empties_and_the_second_wraps_through_empty() -> void:
	var dex: Gen2Pokedex = _dex([1])
	dex.search_cursor = Gen2Pokedex.SEARCH_ROW_TYPE_1
	dex.move_search_type(Gen2Button.LEFT)
	assert_eq(dex.search_type_1, Gen2Pokedex.SEARCH_TYPE_MAX, "1 wraps to the last type")
	dex.move_search_type(Gen2Button.RIGHT)
	assert_eq(dex.search_type_1, 1, "and back round to the first, never to none")

	dex.search_cursor = Gen2Pokedex.SEARCH_ROW_TYPE_2
	assert_eq(dex.search_type_2, Gen2Pokedex.SEARCH_TYPE_NONE)
	dex.move_search_type(Gen2Button.LEFT)
	assert_eq(dex.search_type_2, Gen2Pokedex.SEARCH_TYPE_MAX)
	dex.move_search_type(Gen2Button.RIGHT)
	assert_eq(dex.search_type_2, Gen2Pokedex.SEARCH_TYPE_NONE, "the second row can empty again")


## A row prints the imported type name, and the empty value prints
## PokedexTypeSearchStrings' own first entry.
func test_a_search_row_names_its_type() -> void:
	var dex: Gen2Pokedex = _dex([1])
	assert_eq(dex.search_type_name(Gen2Pokedex.SEARCH_TYPE_NONE), Gen2Pokedex.SEARCH_TYPE_NONE_NAME)
	assert_eq(dex.search_type_name(1), _data.type_name(RomLayout.TYPE_NORMAL))


## `.Search` checks Pokedex_CheckCaught, so a species that has only been seen is
## not a result.
func test_a_search_finds_caught_species_only() -> void:
	# Species 1 and 18 are both the fixture's first search type; only 1 is caught.
	var dex: Gen2Pokedex = _dex([1, 18], [1], RomLayout.DEXMODE_OLD)
	dex.search_type_1 = 1
	assert_eq(dex.begin_search(), 1)
	assert_eq(dex.rows()[0]["species"], 1)


## Two chosen types filter one after the other, so the result carries both.
func test_two_types_narrow_the_search_rather_than_widening_it() -> void:
	var caught: Array = []
	for number: int in range(1, 41):
		caught.append(number)
	var dex: Gen2Pokedex = _dex(caught, caught, RomLayout.DEXMODE_OLD)
	# Species 20 is the fixture's third search type with FIRE second; species 3
	# is that same first type without it.
	dex.search_type_1 = 3
	var one_type: int = dex.begin_search()
	dex.leave_search_results()

	dex.search_type_1 = 3
	dex.search_type_2 = 2
	var two_types: int = dex.begin_search()
	assert_lt(two_types, one_type, "the second type narrows the result")
	assert_eq(dex.rows()[0]["species"], 20)


## A search that finds nothing rebuilds the listing by mode rather than leaving
## it filtered, which is what `.MenuAction_BeginSearch` does before its message.
func test_a_search_with_no_results_leaves_the_listing_whole() -> void:
	var dex: Gen2Pokedex = _dex([1], [], RomLayout.DEXMODE_OLD)
	dex.search_type_1 = 1
	assert_eq(dex.begin_search(), 0)
	assert_eq(dex.rows()[0]["species"], 1, "the listing is the mode's own again")
	assert_eq(dex.listing_end, 1)


## `.show_search_results` backs the listing up and `.return_to_search_screen`
## puts it back.
func test_leaving_the_results_restores_the_listing_exactly() -> void:
	var caught: Array = []
	for number: int in range(1, 41):
		caught.append(number)
	var dex: Gen2Pokedex = _dex(caught, caught, RomLayout.DEXMODE_OLD)
	dex.scroll = 12
	dex.cursor = 3
	dex.prev_entry = 15
	dex.search_type_1 = 1
	assert_gt(dex.begin_search(), 0)
	assert_eq(dex.scroll, 0, "the results open at the top")
	assert_eq(dex.cursor, 0)

	dex.leave_search_results()
	assert_eq(dex.scroll, 12)
	assert_eq(dex.cursor, 3)
	assert_eq(dex.prev_entry, 15)
	assert_eq(dex.listing_end, 40, "and the listing is the mode's own again")


## The results screen draws four rows rather than seven (`ld a, 4`).
func test_the_results_listing_is_four_rows() -> void:
	var caught: Array = []
	for number: int in range(1, 41):
		caught.append(number)
	var dex: Gen2Pokedex = _dex(caught, caught, RomLayout.DEXMODE_OLD)
	dex.search_type_1 = 1
	dex.begin_search()
	dex.listing_height = Gen2Pokedex.SEARCH_RESULTS_HEIGHT
	assert_eq(dex.rows().size(), 4)


## `Pokedex_CheckUnlockedUnownMode` is the whole of the mode's gate, and
## `Pokedex_DrawUnownModeBG` lists `wUnownDex` in catching order behind it.
func test_unown_mode_is_unlocked_by_its_flag_and_lists_the_catching_order() -> void:
	var state: Gen2WorldState = _state([])
	var dex: Gen2Pokedex = Gen2Pokedex.open(_data, state, RomLayout.DEXMODE_NEW)
	assert_false(dex.unown_unlocked())
	assert_eq(Gen2Pokedex.mode_rows(dex.unown_unlocked()).size(), 3)

	state.set_engine_flag(Gen2WorldState.ENGINE_UNOWN_DEX)
	assert_true(dex.unown_unlocked())
	assert_eq(Gen2Pokedex.mode_rows(dex.unown_unlocked()).size(), 4)

	for form: int in [3, 26, 1]:
		state.update_unown_dex(form)
	dex.open_unown_mode()
	assert_eq(dex.unown_forms(), [3, 26, 1] as Array[int])
	assert_eq(dex.selected_unown_form(), 3)
	assert_eq(dex.unown_word(), "CWORD")


## `Pokedex_UnownModeHandleDPadInput` reads left and right only, stops at
## `wDexUnownCount` rather than at twenty-six, and does not wrap at either end.
func test_the_unown_cursor_stops_at_both_ends_of_what_has_been_caught() -> void:
	var state: Gen2WorldState = _state([])
	for form: int in [5, 9]:
		state.update_unown_dex(form)
	var dex: Gen2Pokedex = Gen2Pokedex.open(_data, state, RomLayout.DEXMODE_NEW)
	dex.open_unown_mode()
	assert_false(dex.move_unown(Gen2Button.LEFT), "the first form is the left edge")
	assert_false(dex.move_unown(Gen2Button.UP), "up and down are not read at all")
	assert_true(dex.move_unown(Gen2Button.RIGHT))
	assert_eq(dex.selected_unown_form(), 9)
	assert_eq(dex.unown_word(), "IWORD")
	assert_false(dex.move_unown(Gen2Button.RIGHT), "the last form caught is the right edge")


## An empty dex is a legal state: the flag is set by the research centre before
## anything has been caught, and `Pokedex_LoadUnownFrontpicTiles` reads the zero
## in the first slot.
func test_an_empty_unown_dex_has_no_form_and_no_word() -> void:
	var state: Gen2WorldState = _state([])
	state.set_engine_flag(Gen2WorldState.ENGINE_UNOWN_DEX)
	var dex: Gen2Pokedex = Gen2Pokedex.open(_data, state, RomLayout.DEXMODE_NEW)
	dex.open_unown_mode()
	assert_true(dex.unown_forms().is_empty())
	assert_eq(dex.selected_unown_form(), 0)
	assert_eq(dex.unown_word(), "")
	assert_false(dex.move_unown(Gen2Button.RIGHT))


## Both order tables are cartridge data of exactly 251 entries and OLD counts
## that far, so a mod's species follows the cartridge's own run in every mode
## rather than being left out of the listing entirely.
func test_a_mod_species_follows_the_cartridge_run_in_every_mode() -> void:
	var overlay := Gen2ContentOverlay.new()
	overlay.define(
		Gen2ContentOverlay.KIND_SPECIES, &"testmod", MOD_SPECIES, {"name": "VOLTLING"}
	)
	_data.set_content_overlay(overlay)

	for mode: int in [RomLayout.DEXMODE_NEW, RomLayout.DEXMODE_OLD]:
		var dex: Gen2Pokedex = _dex([MOD_SPECIES], [MOD_SPECIES], mode)
		assert_eq(dex.listing_end, RomLayout.SPECIES_COUNT + 1,
			"the mod species is the last row of the order")
		dex.scroll = dex.listing_end - dex.listing_height
		dex.cursor = dex.listing_height - 1
		assert_eq(dex.selected_species(), MOD_SPECIES)
		assert_eq(String(dex.rows()[dex.cursor]["name"]), "VOLTLING")

	# ABC filters the mod species by seen the way it filters the table.
	var abc: Gen2Pokedex = _dex([4, MOD_SPECIES], [], RomLayout.DEXMODE_ABC)
	assert_eq(abc.listing_end, 2)
	assert_eq(int(abc.rows()[1]["species"]), MOD_SPECIES)


## `wPrevDexEntry` is a species number, so a mod's is past the cartridge's count
## and the order is what says whether it is a real entry.
func test_the_dex_reopens_on_a_mod_species_it_was_left_on() -> void:
	var overlay := Gen2ContentOverlay.new()
	overlay.define(
		Gen2ContentOverlay.KIND_SPECIES, &"testmod", MOD_SPECIES, {"name": "VOLTLING"}
	)
	_data.set_content_overlay(overlay)
	var dex: Gen2Pokedex = _dex([MOD_SPECIES], [], RomLayout.DEXMODE_OLD, MOD_SPECIES)
	assert_eq(dex.selected_species(), MOD_SPECIES)

	# A number no mod defined is out of the order and seeks nowhere, which is
	# where the cartridge's own bound left it.
	var unknown: Gen2Pokedex = _dex(
		[MOD_SPECIES], [], RomLayout.DEXMODE_OLD, Gen2ContentOverlay.FIRST_MOD_NUMBER + 9
	)
	assert_eq(unknown.scroll, 0)
	assert_eq(unknown.cursor, 0)
