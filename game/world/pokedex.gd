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

## `wDexListingHeight` as the main screen sets it (`ld a, 7`). The search results
## screen sets its own, which is why this is the listing's height rather than the
## model's.
const LISTING_HEIGHT: int = 7

## What `.PrintEntry` draws instead of a name for a species that has not been
## seen (`.NameNotSeen`).
const NOT_SEEN_NAME: String = "-----"

## `wPokedexStatus`, which `Pokedex_Page` toggles with `xor 1`.
const PAGE_1: int = 0
const PAGE_2: int = 1

## `Pokedex_DrawOptionScreenBG.Modes`, verbatim, and the description
## `Pokedex_DisplayModeDescription` prints under each. UNOWN is built in its
## source position and refused, the way the start menu builds Pokedex: nothing
## here tracks STATUSFLAGS_UNOWN_DEX_F, so `wUnlockedUnownMode` is always false
## and `.NoUnownModeArrowCursorData`'s three rows are what the screen gets.
const MODE_ROWS: Array[Dictionary] = [
	{
		"mode": RomLayout.DEXMODE_NEW,
		"label": "NEW #DEX MODE",
		"description": "#MN are listed by\nevolution type.",
	},
	{
		"mode": RomLayout.DEXMODE_OLD,
		"label": "OLD #DEX MODE",
		"description": "#MN are listed by\nofficial type.",
	},
	{
		"mode": RomLayout.DEXMODE_ABC,
		"label": "A to Z MODE",
		"description": "#MN are listed\nalphabetically.",
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
## `wPrevDexEntry`. Plain WRAM0 rather than saved data, so it survives the dex
## closing and reopening within a session and is zero on boot; the caller owns it
## for exactly that reason, the way the world screen owns the start menu cursor.
var prev_entry: int = 0

var _data: GameData = null
var _state: Gen2WorldState = null
## `wPokedexOrder`, always [constant RomLayout.SPECIES_COUNT] long. ABC mode
## zero-fills its tail, and a zero is what `.PrintEntry` draws nothing for.
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
func order_by_mode() -> void:
	_order = PackedInt32Array()
	_order.resize(RomLayout.SPECIES_COUNT)
	match mode:
		RomLayout.DEXMODE_ABC:
			_order_abc()
		RomLayout.DEXMODE_OLD:
			for index: int in RomLayout.SPECIES_COUNT:
				_order[index] = index + 1
			_find_last_seen()
		_:
			var table: PackedInt32Array = _data.dex_order_new() if _data != null \
				else PackedInt32Array()
			for index: int in RomLayout.SPECIES_COUNT:
				_order[index] = table[index] if index < table.size() else 0
			_find_last_seen()


## `Pokedex_ABCMode`: the alphabetical table filtered down to what has been
## seen, and `wDexListingEnd` is that count rather than a position.
func _order_abc() -> void:
	var table: PackedInt32Array = _data.dex_order_alpha() if _data != null \
		else PackedInt32Array()
	listing_end = 0
	for index: int in table.size():
		if not _has_seen(table[index]):
			continue
		_order[listing_end] = table[index]
		listing_end += 1


## `.FindLastSeen`: walks the order backwards and stops at the first species that
## has been seen, answering that species' 1-based position. Nothing seen at all
## answers zero, which the loop reaches by counting all the way down.
func _find_last_seen() -> void:
	var end: int = RomLayout.SPECIES_COUNT
	for index: int in range(RomLayout.SPECIES_COUNT - 1, -1, -1):
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
	if prev_entry <= 0 or prev_entry > RomLayout.SPECIES_COUNT:
		return
	var index: int = 0
	if listing_end >= LISTING_HEIGHT + 1:
		for step: int in listing_end - LISTING_HEIGHT:
			if _order[index] == prev_entry:
				return
			index += 1
			scroll += 1
	for step: int in LISTING_HEIGHT:
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
	for index: int in LISTING_HEIGHT:
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
	if LISTING_HEIGHT >= listing_end:
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
	if next < LISTING_HEIGHT:
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
	scroll = scroll - LISTING_HEIGHT if scroll >= LISTING_HEIGHT else 0
	return true


## `Pokedex_ListingMoveDownOnePage`, which always reports a change.
##
## The source adds two pages to the offset in one byte and treats the carry as
## "near the bottom", so an offset that would overflow lands on the last page
## exactly as one that runs past `wDexListingEnd` does. The wrap is kept because
## it is the comparison, not an accident of it.
func _move_down_one_page() -> bool:
	var reach: int = LISTING_HEIGHT * 2 + scroll
	if reach > 0xFF or reach >= listing_end:
		scroll = listing_end - LISTING_HEIGHT
	else:
		scroll += LISTING_HEIGHT
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


func _has_seen(species: int) -> bool:
	return _state != null and _state.has_seen_species(species)


func _has_caught(species: int) -> bool:
	return _state != null and _state.has_caught_species(species)


func _species_name(species: int) -> String:
	if _data == null:
		return ""
	return String(_data.species(species).get("name", ""))
