class_name Gen2Pokedex
extends RefCounted

## Scene-free model of the Pokedex (engine/pokedex/pokedex.asm).
##
## Holds what `wPokedexDataStart`..`wPokedexDataEnd` holds: the current mode, the
## species order that mode built, how far down the listing runs, and the cursor
## and scroll offset into it. A screen draws [method rows] and feeds buttons back
## in; nothing here knows what a Control is.
##
## The two orderings come from the cache ([method GameData.dex_order_new] and
## [method GameData.dex_order_alpha]); DEXMODE_OLD has no table because
## `.OldMode` counts from 1. Seen and caught come from [Gen2WorldState], which
## already keeps both arrays.

## What each screen writes to `wDexListingHeight`: the main screen `ld a, 7` and
## the search results screen `ld a, 4`. It is WRAM the source rewrites per
## screen, so [member listing_height] carries it and these are only the two
## values written to it.
const LISTING_HEIGHT: int = 7
const SEARCH_RESULTS_HEIGHT: int = 4

## What `.PrintEntry` draws instead of a name for a species that has not been
## seen (`.NameNotSeen`).
const NOT_SEEN_NAME: String = "-----"

## `wPokedexStatus`, which `Pokedex_Page` toggles with `xor 1`.
const PAGE_1: int = 0
const PAGE_2: int = 1

## `Pokedex_DrawOptionScreenBG.Modes`, verbatim, and the description
## `Pokedex_DisplayModeDescription` prints under each. UNOWN is offered only once
## `Pokedex_CheckUnlockedUnownMode` has read STATUSFLAGS_UNOWN_DEX_F; without it
## `.NoUnownModeArrowCursorData`'s three rows are what the screen gets.
const MODE_ROWS: Array[Dictionary] = [
	{
		"mode": RomLayout.DEXMODE_NEW,
		"label": "NEW #DEX MODE",
		"description": "PKMN are listed by\nevolution type.",
	},
	{
		"mode": RomLayout.DEXMODE_OLD,
		"label": "OLD #DEX MODE",
		"description": "PKMN are listed by\nofficial type.",
	},
	{
		"mode": RomLayout.DEXMODE_ABC,
		"label": "A to Z MODE",
		"description": "PKMN are listed\nalphabetically.",
	},
	{
		"mode": RomLayout.DEXMODE_UNOWN,
		"label": "UNOWN MODE",
		"description": "UNOWN are listed\nin catching order.",
	},
]

## `Pokedex_DisplayChangingModesMessage`'s own text, shown while a mode change
## rebuilds the order.
const CHANGING_MODES_TEXT: String = "Changing modes.\nPlease wait."

## `PokedexTypeSearchConversionTable` (data/types/search_types.asm), which is
## what turns a search row's 1-based position into a real type number. Its order
## is the cartridge's own and is not the type numbering: FIRE follows NORMAL
## because the search screen lists the special types first.
##
## Kept as named constants rather than imported, the way the matchup multipliers
## are: all seventeen entries are types [RomLayout] already names, and the table
## is identical in both pins.
const SEARCH_TYPES: Array[int] = [
	RomLayout.TYPE_NORMAL, RomLayout.TYPE_FIRE, RomLayout.TYPE_WATER,
	RomLayout.TYPE_GRASS, RomLayout.TYPE_ELECTRIC, RomLayout.TYPE_ICE,
	RomLayout.TYPE_FIGHTING, RomLayout.TYPE_POISON, RomLayout.TYPE_GROUND,
	RomLayout.TYPE_FLYING, RomLayout.TYPE_PSYCHIC, RomLayout.TYPE_BUG,
	RomLayout.TYPE_ROCK, RomLayout.TYPE_GHOST, RomLayout.TYPE_DRAGON,
	RomLayout.TYPE_DARK, RomLayout.TYPE_STEEL,
]
## `NUM_TYPES`, which is [constant SEARCH_TYPES]' own length and the highest
## value either search row takes.
const SEARCH_TYPE_MAX: int = 17
## `PokedexTypeSearchStrings`' first entry, which is the row's "no type chosen"
## and the only value the second row can hold that the first cannot.
const SEARCH_TYPE_NONE: int = 0
const SEARCH_TYPE_NONE_NAME: String = "----"

## `Pokedex_UpdateSearchScreen.ArrowCursorData`'s four rows. The two type rows
## are the ones left and right change, which is `Pokedex_UpdateSearchMonType`'s
## own `cp 2` check.
const SEARCH_ROW_TYPE_1: int = 0
const SEARCH_ROW_TYPE_2: int = 1
const SEARCH_ROW_BEGIN: int = 2
const SEARCH_ROW_CANCEL: int = 3
const SEARCH_ROWS: Array[String] = ["TYPE1", "TYPE2", "BEGIN SEARCH!!", "CANCEL"]

## `Pokedex_DisplayTypeNotFoundMessage`'s own text.
const TYPE_NOT_FOUND_TEXT: String = "The specified type\nwas not found."

var mode: int = RomLayout.DEXMODE_NEW
## `wDexListingScrollOffset` and `wDexListingCursor`. The selected row is their
## sum, which is what `Pokedex_GetSelectedMon` adds.
var scroll: int = 0
var cursor: int = 0
## `wDexListingEnd`, the 1-based position of the last species the listing runs
## to. Not a count of seen species outside ABC mode: see [method _find_last_seen].
var listing_end: int = 0
## `wPokedexStatus`, the description page the entry screen is showing.
var page: int = PAGE_1
## `wDexListingHeight`, how many rows the screen currently on top draws.
var listing_height: int = LISTING_HEIGHT
## `wPrevDexEntry`. Plain WRAM0 rather than saved data, so it survives the dex
## closing and reopening within a session and is zero on boot; the caller owns it
## for exactly that reason, the way the world screen owns the start menu cursor.
var prev_entry: int = 0

## `wDexSearchMonType1` and `wDexSearchMonType2`, as 1-based positions in
## [constant SEARCH_TYPES]. `Pokedex_InitSearchScreen` opens on `NORMAL + 1`,
## which is position 1, and leaves the second row on
## [constant SEARCH_TYPE_NONE].
var search_type_1: int = 1
var search_type_2: int = SEARCH_TYPE_NONE
## `wDexArrowCursorPosIndex` while the search screen is up.
var search_cursor: int = SEARCH_ROW_TYPE_1
## `wDexSearchResultCount`.
var search_result_count: int = 0

## `wDexCurUnownIndex`, a position in the caught-forms list rather than a letter.
var unown_cursor: int = 0

var _data: GameData = null
var _state: Gen2WorldState = null
## `wDexListingScrollOffsetBackup`, `wDexListingCursorBackup` and
## `wPrevDexEntryBackup`, which `.show_search_results` fills so leaving the
## results screen puts the main listing back exactly where it was.
var _listing_backup: Dictionary = {}
## `wPokedexOrder`, [constant RomLayout.SPECIES_COUNT] long plus one slot per mod
## species. ABC mode zero-fills its tail, and a zero is what `.PrintEntry` draws
## nothing for.
var _order: PackedInt32Array = PackedInt32Array()


## `Pokedex_Init`: clears its own WRAM block, takes the mode from
## `wLastDexMode`, orders the species and seeks the cursor to `wPrevDexEntry`.
static func open(
	data: GameData, state: Gen2WorldState, last_mode: int, previous_entry: int = 0
) -> Gen2Pokedex:
	var dex := Gen2Pokedex.new()
	dex._data = data
	dex._state = state
	dex.mode = last_mode if last_mode in [
		RomLayout.DEXMODE_NEW, RomLayout.DEXMODE_OLD, RomLayout.DEXMODE_ABC,
	] else RomLayout.DEXMODE_NEW
	dex.prev_entry = previous_entry
	dex.order_by_mode()
	dex.init_cursor_position()
	return dex


## `Pokedex_OrderMonsByMode`. NEW copies the new-dex table, OLD counts from 1,
## and ABC keeps only the species that have been seen and zero-fills the rest.
##
## Both tables are cartridge data of exactly [constant RomLayout.SPECIES_COUNT]
## entries and OLD counts that far, so a mod's species can only follow the
## cartridge's own run, ascending by number, the way `FIRST_MOD_POCKET` numbers a
## mod pocket after the cartridge's.
func order_by_mode() -> void:
	var mod_species: Array[int] = _data.mod_species_numbers() if _data != null \
		else [] as Array[int]
	_order = PackedInt32Array()
	_order.resize(RomLayout.SPECIES_COUNT + mod_species.size())
	match mode:
		RomLayout.DEXMODE_ABC:
			_order_abc(mod_species)
		RomLayout.DEXMODE_OLD:
			for index: int in RomLayout.SPECIES_COUNT:
				_order[index] = index + 1
			_append_mod_species(mod_species, RomLayout.SPECIES_COUNT)
			_find_last_seen()
		_:
			var table: PackedInt32Array = _data.dex_order_new() if _data != null \
				else PackedInt32Array()
			for index: int in RomLayout.SPECIES_COUNT:
				_order[index] = table[index] if index < table.size() else 0
			_append_mod_species(mod_species, RomLayout.SPECIES_COUNT)
			_find_last_seen()


## `Pokedex_ABCMode`: the alphabetical table filtered down to what has been
## seen, and `wDexListingEnd` is that count rather than a position. A mod's
## species are filtered the same way and follow the table.
func _order_abc(mod_species: Array[int]) -> void:
	var table: PackedInt32Array = _data.dex_order_alpha() if _data != null \
		else PackedInt32Array()
	listing_end = 0
	for index: int in table.size():
		if not _has_seen(table[index]):
			continue
		_order[listing_end] = table[index]
		listing_end += 1
	for species: int in mod_species:
		if not _has_seen(species):
			continue
		_order[listing_end] = species
		listing_end += 1


func _append_mod_species(mod_species: Array[int], at: int) -> void:
	for index: int in mod_species.size():
		_order[at + index] = mod_species[index]


## `.FindLastSeen`: walks the order backwards and stops at the first species that
## has been seen, answering that species' 1-based position. Nothing seen at all
## answers zero, which the loop reaches by counting all the way down.
func _find_last_seen() -> void:
	var end: int = _order.size()
	for index: int in range(_order.size() - 1, -1, -1):
		if _has_seen(_order[index]):
			break
		end -= 1
	listing_end = end


## `Pokedex_InitCursorPosition`: seeks the cursor to `wPrevDexEntry`, scrolling
## first while there is more than one page and then moving the cursor within it.
##
## A zero or out-of-range previous entry leaves both at zero. An entry that is
## not in the order at all is not special-cased on the cartridge either: the
## second walk runs its full seven steps and leaves the cursor past the last row,
## which ABC mode can reach when the last entry viewed has not been seen.
func init_cursor_position() -> void:
	scroll = 0
	cursor = 0
	if prev_entry <= 0:
		return
	# A mod species is numbered past the cartridge's range, so the bound is the
	# order itself rather than the count.
	if prev_entry > RomLayout.SPECIES_COUNT and not _order.has(prev_entry):
		return
	var index: int = 0
	if listing_end >= listing_height + 1:
		for step: int in listing_end - listing_height:
			if _order[index] == prev_entry:
				return
			index += 1
			scroll += 1
	for step: int in listing_height:
		if index < _order.size() and _order[index] == prev_entry:
			return
		index += 1
		cursor += 1


## `Pokedex_GetSelectedMon`, which is the order read at cursor plus scroll.
func selected_species() -> int:
	var index: int = cursor + scroll
	if index < 0 or index >= _order.size():
		return 0
	return _order[index]


## The listing as [constant LISTING_HEIGHT] rows, in `Pokedex_PrintListing`'s
## own order, each as `.PrintEntry` would draw it:
## { species, empty, number, seen, caught, name, selected }.
##
## [code]empty[/code] is the species-zero row `.PrintEntry` returns from
## immediately, which is what the tail of an ABC listing is made of.
## [code]number[/code] is the three-digit zero-padded dex number, and only OLD
## mode prints one.
func rows() -> Array:
	var out: Array = []
	for index: int in listing_height:
		var at: int = scroll + index
		var species: int = _order[at] if at >= 0 and at < _order.size() else 0
		var seen: bool = _has_seen(species)
		out.append({
			"species": species,
			"empty": species == 0,
			"number": "%03d" % species if mode == RomLayout.DEXMODE_OLD and species != 0 else "",
			"seen": seen,
			"caught": _has_caught(species),
			"name": _species_name(species) if seen else NOT_SEEN_NAME,
			"selected": index == cursor,
		})
	return out


## `Pokedex_DrawMainScreenBG`'s two `CountSetBits` totals.
func seen_count() -> int:
	return _state.seen_count() if _state != null else 0


func caught_count() -> int:
	return _state.caught_count() if _state != null else 0


## `wUnlockedUnownMode`, which is `Pokedex_CheckUnlockedUnownMode`'s reading of
## the one engine flag the Ruins of Alph research centre sets.
func unown_unlocked() -> bool:
	return _state != null \
		and _state.is_engine_flag_active(Gen2WorldState.ENGINE_UNOWN_DEX)


## `Pokedex_DrawUnownModeBG`'s own walk: the forms caught, in catching order.
## `wDexUnownCount` is its length.
func unown_forms() -> Array[int]:
	return _state.unown_dex() if _state != null else [] as Array[int]


## `Pokedex_InitUnownMode`, which opens on the first form caught rather than on
## the one last looked at.
func open_unown_mode() -> void:
	unown_cursor = 0


## The form under the cursor, 1 being A, or zero when nothing has been caught:
## `Pokedex_LoadUnownFrontpicTiles` reads `wUnownDex` at the cursor, and an empty
## dex leaves it on a zero slot.
func selected_unown_form() -> int:
	var forms: Array[int] = unown_forms()
	if unown_cursor < 0 or unown_cursor >= forms.size():
		return 0
	return forms[unown_cursor]


## `PrintUnownWord`, which reads the word for the form under the cursor. Empty
## for an empty dex, which is the blank row the fill leaves.
func unown_word() -> String:
	var form: int = selected_unown_form()
	if form <= 0 or _data == null:
		return ""
	return _data.unown_word(form)


## `Pokedex_UnownModeHandleDPadInput`: right and left only, no wrap at either
## end, and the right edge is `wDexUnownCount` rather than twenty-six. Answers
## whether the cursor moved.
func move_unown(button: int) -> bool:
	var count: int = unown_forms().size()
	match button:
		Gen2Button.RIGHT:
			if unown_cursor + 1 >= count:
				return false
			unown_cursor += 1
			return true
		Gen2Button.LEFT:
			if unown_cursor <= 0:
				return false
			unown_cursor -= 1
			return true
	return false


## `Pokedex_ListingHandleDPadInput`. Answers whether the position changed, which
## is the carry flag the source returns.
##
## Left and right page the listing and are refused outright while it fits on one
## screen: the source checks `wDexListingHeight` against `wDexListingEnd` before
## it looks at either button.
func move_listing(button: int) -> bool:
	match button:
		Gen2Button.UP:
			return _move_cursor_up()
		Gen2Button.DOWN:
			return _move_cursor_down()
	if listing_height >= listing_end:
		return false
	match button:
		Gen2Button.LEFT:
			return _move_up_one_page()
		Gen2Button.RIGHT:
			return _move_down_one_page()
	return false


## `Pokedex_ListingMoveCursorUp`: the cursor moves first, and only a cursor
## already at the top scrolls.
func _move_cursor_up() -> bool:
	if cursor != 0:
		cursor -= 1
		return true
	if scroll == 0:
		return false
	scroll -= 1
	return true


## `Pokedex_ListingMoveCursorDown`: refused at the end of the listing, then the
## cursor moves while it is inside the visible rows and the listing scrolls once
## it is not.
func _move_cursor_down() -> bool:
	var next: int = cursor + 1
	if next >= listing_end:
		return false
	if next < listing_height:
		cursor = next
		return true
	if next + scroll >= listing_end:
		return false
	scroll += 1
	return true


## `Pokedex_ListingMoveUpOnePage`: a page up, or to the top when less than a page
## from it.
func _move_up_one_page() -> bool:
	if scroll == 0:
		return false
	scroll = scroll - listing_height if scroll >= listing_height else 0
	return true


## `Pokedex_ListingMoveDownOnePage`, which always reports a change.
##
## The source adds two pages to the offset in one byte and treats the carry as
## "near the bottom", so an offset that would overflow lands on the last page
## exactly as one that runs past `wDexListingEnd` does. The wrap is kept because
## it is the comparison, not an accident of it.
func _move_down_one_page() -> bool:
	var reach: int = listing_height * 2 + scroll
	if reach > 0xFF or reach >= listing_end:
		scroll = listing_end - listing_height
	else:
		scroll += listing_height
	return true


## `Pokedex_UpdateMainScreen`'s A: the entry screen opens only for a species that
## has been seen (`Pokedex_CheckSeen; ret z`).
func can_open_entry() -> bool:
	return _has_seen(selected_species())


## `Pokedex_InitDexEntryScreen`, which opens on page 1 and records the species as
## `wPrevDexEntry`.
func open_entry() -> void:
	page = PAGE_1
	prev_entry = selected_species()


## `Pokedex_Page`'s `xor 1`.
func toggle_page() -> void:
	page = PAGE_2 if page == PAGE_1 else PAGE_1
	prev_entry = selected_species()


## `Pokedex_NextOrPreviousDexEntry`: moves in the pressed direction until it
## lands on a species that has been seen, and puts the cursor and scroll back
## where they were if it runs out of listing first.
##
## Answers whether it moved. A move re-enters the entry screen at page 1, which
## is `Pokedex_ReinitDexEntryScreen`.
func step_entry(button: int) -> bool:
	if button != Gen2Button.UP and button != Gen2Button.DOWN:
		return false
	var backup_cursor: int = cursor
	var backup_scroll: int = scroll
	while true:
		var moved: bool = _move_cursor_up() if button == Gen2Button.UP else _move_cursor_down()
		if not moved:
			cursor = backup_cursor
			scroll = backup_scroll
			return false
		if _has_seen(selected_species()):
			page = PAGE_1
			prev_entry = selected_species()
			return true
	return false


## The selected species' entry, as `DisplayDexEntry` prints it:
## { species, name, number, category, caught, height, weight, page, text }.
##
## The name, the category and the number are printed whether or not the species
## has been caught; the caught check sits after them and gates the measurements
## and the description. A zero height or weight is left blank rather than printed
## as a zero, which is `.skip_height` and `.skip_weight`.
func entry() -> Dictionary:
	var species: int = selected_species()
	var dex: Dictionary = _data.dex_entry(species) if _data != null else {}
	var caught: bool = _has_caught(species)
	var pages: PackedStringArray = dex.get("pages", PackedStringArray())
	var height: int = int(dex.get("height", 0))
	var weight: int = int(dex.get("weight", 0))
	return {
		"species": species,
		"name": _species_name(species),
		"number": "%03d" % species,
		"category": String(dex.get("category", "")),
		"caught": caught,
		"height": height_text(height) if caught and height != 0 else "",
		"weight": weight_text(weight) if caught and weight != 0 else "",
		"page": page,
		"text": pages[page] if caught and page < pages.size() else "",
	}


## `_PrintNum` (engine/math/print_num.asm) for the two calls this screen makes:
## [param digits] digits with [param before_point] of them in front of a decimal
## point, and neither the money nor the leading-zero flag set.
##
## A leading zero is not printed and not replaced: `.PrintLeadingZero` writes
## nothing while the flag is clear and `.AdvancePointer` steps over the cell
## regardless, leaving the background template's own space. That is why this
## returns a fixed-width field with spaces rather than a trimmed number.
##
## The digit immediately in front of the point is always printed, even when it
## is a zero: `.PrintDigit` latches "a digit has been printed" as `e` runs out,
## which is what makes a height of 8 read 0'08" rather than blank.
static func print_num(value: int, digits: int, before_point: int) -> String:
	var text: String = ""
	var padded: String = String.num_int64(maxi(value, 0)).lpad(digits, "0").right(digits)
	var printed: bool = false
	for index: int in digits:
		var digit: String = padded[index]
		## `dec e` reaching zero on this digit, which is the last one in front
		## of the point.
		if index == before_point - 1:
			printed = true
		if digit != "0":
			printed = true
		text += digit if printed else " "
		if index == before_point - 1:
			text += "."
	return text


## The height as `DisplayDexEntry` prints it: four digits with two in front of
## the point, and the point overwritten by the feet mark. The stored 204 reads
## " 2'04"".
static func height_text(height: int) -> String:
	return "%s\"" % print_num(height, 4, 2).replace(".", "'")


## The weight as `DisplayDexEntry` prints it: five digits with four in front of
## the point. The stored 150 reads "  15.0".
static func weight_text(weight: int) -> String:
	return print_num(weight, 5, 4)


## The OPTION screen's rows. UNOWN is dropped while `wUnlockedUnownMode` is
## clear, which is `.NoUnownModeArrowCursorData`'s shorter table.
static func mode_rows(unown_unlocked: bool = false) -> Array:
	var out: Array = []
	for row: Dictionary in MODE_ROWS:
		if int(row["mode"]) == RomLayout.DEXMODE_UNOWN and not unown_unlocked:
			continue
		out.append(row.duplicate(true))
	return out


## `.ChangeMode`: choosing the mode already in use changes nothing, and choosing
## another reorders the listing and puts the cursor back at the top before
## seeking `wPrevDexEntry` again.
##
## Answers whether the mode changed, which is what decides whether the screen
## shows [constant CHANGING_MODES_TEXT].
func change_mode(next_mode: int) -> bool:
	if next_mode == mode:
		return false
	mode = next_mode
	order_by_mode()
	scroll = 0
	cursor = 0
	init_cursor_position()
	return true


## `Pokedex_InitSearchScreen`, which resets both rows every time the screen is
## opened rather than remembering the last search.
func open_search() -> void:
	search_type_1 = 1
	search_type_2 = SEARCH_TYPE_NONE
	search_cursor = SEARCH_ROW_TYPE_1


## What `Pokedex_PlaceTypeString` prints for a search row: the imported type name
## for a chosen type, and `PokedexTypeSearchStrings`' first entry for the second
## row's empty value. The strings table is the type names padded to a fixed
## width, so the name itself is what a row says.
func search_type_name(value: int) -> String:
	if value <= SEARCH_TYPE_NONE or value > SEARCH_TYPES.size():
		return SEARCH_TYPE_NONE_NAME
	return _data.type_name(SEARCH_TYPES[value - 1]) if _data != null else ""


## `Pokedex_UpdateSearchMonType`, which reads left and right on the two type rows
## only and answers whether the value changed.
##
## The two rows wrap differently, and deliberately: the first row runs 1 to
## NUM_TYPES and can never be empty, while the second wraps through
## [constant SEARCH_TYPE_NONE] as well, which is the only way to search on one
## type after choosing two.
func move_search_type(button: int) -> bool:
	if search_cursor > SEARCH_ROW_TYPE_2:
		return false
	match button:
		Gen2Button.RIGHT:
			_step_search_type(1)
			return true
		Gen2Button.LEFT:
			_step_search_type(-1)
			return true
	return false


func _step_search_type(delta: int) -> void:
	var first: bool = search_cursor == SEARCH_ROW_TYPE_1
	var value: int = search_type_1 if first else search_type_2
	var lowest: int = 1 if first else SEARCH_TYPE_NONE
	if delta > 0:
		value = lowest if value >= SEARCH_TYPE_MAX else value + 1
	else:
		value = SEARCH_TYPE_MAX if value <= lowest else value - 1
	if first:
		search_type_1 = value
	else:
		search_type_2 = value


## `Pokedex_SearchForMons` plus `.MenuAction_BeginSearch`'s answer to it.
##
## Each chosen type filters the listing in place and the second row is applied
## first, so choosing two types finds the species carrying both rather than
## either. A species has to have been *caught*, not merely seen: `.Search`
## checks `Pokedex_CheckCaught`.
##
## Answers the number of results. Zero leaves the listing rebuilt by mode, which
## is what `.MenuAction_BeginSearch` does before showing its own not-found text;
## anything else moves the listing onto the results and backs up what it
## replaced.
func begin_search() -> int:
	search_result_count = 0
	if search_type_2 != SEARCH_TYPE_NONE:
		_filter_by_type(search_type_2)
	if search_type_1 != SEARCH_TYPE_NONE:
		_filter_by_type(search_type_1)
	if search_result_count == 0:
		order_by_mode()
		return 0
	_listing_backup = {"scroll": scroll, "cursor": cursor, "prev_entry": prev_entry}
	listing_end = search_result_count
	scroll = 0
	cursor = 0
	return search_result_count


## One `.Search` pass: the order is rewritten from its own front, keeping the
## caught species that carry [param value]'s type in either slot and zero-filling
## what is left behind.
func _filter_by_type(value: int) -> void:
	var wanted: int = SEARCH_TYPES[value - 1]
	var kept: int = 0
	for index: int in _order.size():
		var species: int = _order[index]
		if species == 0 or not _has_caught(species):
			continue
		var types: Array = _data.species(species).get("types", []) if _data != null else []
		if types.size() < 2 or (int(types[0]) != wanted and int(types[1]) != wanted):
			continue
		_order[kept] = species
		kept += 1
	for index: int in range(kept, _order.size()):
		_order[index] = 0
	search_result_count = kept


## `.return_to_search_screen`: the three backups go back and the listing is then
## rebuilt by mode, so the search screen is reached with the main listing exactly
## as it was. `wDexListingHeight` is not put back here, because the source never
## does: each screen's own Init writes it.
func leave_search_results() -> void:
	scroll = int(_listing_backup.get("scroll", 0))
	cursor = int(_listing_backup.get("cursor", 0))
	prev_entry = int(_listing_backup.get("prev_entry", 0))
	_listing_backup = {}
	order_by_mode()


func _has_seen(species: int) -> bool:
	return _state != null and _state.has_seen_species(species)


func _has_caught(species: int) -> bool:
	return _state != null and _state.has_caught_species(species)


func _species_name(species: int) -> String:
	if _data == null:
		return ""
	return String(_data.species(species).get("name", ""))
