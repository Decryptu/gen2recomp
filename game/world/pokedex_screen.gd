class_name Gen2PokedexScreen
extends Control

## The Pokedex (engine/pokedex/pokedex.asm), embedded in the overworld the way
## the start menu and its own submenus are.
##
## Presented as a window-resolution Control panel, consistent with the start
## menu, mart, phone and PC storage overlays rather than the hardware's tiled
## screen: no `gfx/pokedex` graphics are imported, so there is nothing to draw a
## tile-accurate listing with. Every rule the screen obeys is [Gen2Pokedex]'s,
## which is the source's own.
##
## Five of the source's six states are here: the listing, the entry screen, the
## OPTION screen, SEARCH and its results. The Unown dex is not, so the OPTION
## screen draws `.NoUnownModeArrowCursorData`'s three rows, which is what the
## cartridge draws while `wUnlockedUnownMode` is clear.

## Emitted on B from the listing, which is where `DEXSTATE_EXIT` lands.
signal closed

## Emitted by the entry screen's CRY button, since this screen owns no audio
## player: the overworld's own answers it, the way it answers a script's cry.
signal cry_requested(species: int)

enum Mode { LIST, ENTRY, OPTION, SEARCH, SEARCH_RESULTS }

const PANEL: Color = Color("#14233a")
const BORDER: Color = Color("#4f6f9e")
const SCRIM: Color = Color(0.02, 0.04, 0.08, 0.78)
const TEXT: Color = Color("#f4f7fb")
const MUTED: Color = Color("#9eacc0")
const ACCENT: Color = Color("#f3c969")

## `Pokedex_PlaceCaughtSymbolIfCaught` writes one tile ahead of the name, and a
## row that is not caught keeps the blank the listing was cleared with.
const CAUGHT_SYMBOL: String = "*"
const UNCAUGHT_SYMBOL: String = " "

## `DexEntryScreen_ArrowCursorData`'s four positions, in its own order. AREA
## wants a town map and PRNT a printer, neither of which is imported, so both are
## drawn and refuse.
const ENTRY_BUTTONS: Array[String] = ["PAGE", "AREA", "CRY", "PRNT"]
const ENTRY_BUTTON_PAGE: int = 0
const ENTRY_BUTTON_CRY: int = 2

var _dex: Gen2Pokedex = null
var _world: Gen2WorldAPI = null
var _data: GameData = null
var _mode: Mode = Mode.LIST
## The OPTION screen's own cursor (`wDexArrowCursorPosIndex`), which opens on
## the row matching the current mode.
var _option_cursor: int = 0
## The entry screen's own `wDexArrowCursorPosIndex`, which
## `Pokedex_ReinitDexEntryScreen` puts back on PAGE for each new entry.
var _entry_cursor: int = 0
var _mode_rows: Array = []

var _title: Label = null
var _summary: Label = null
var _options: VBoxContainer = null
var _status: Label = null
var _footer: Label = null


## Optional the way the trainer card is: without a world, its state or a cache
## carrying the dex order tables there is no listing, so this answers false and
## the caller keeps the start menu open.
func open(data: GameData, world: Gen2WorldAPI, previous_entry: int = 0) -> bool:
	_data = data
	_world = world
	if _data == null or _world == null or _world.state == null:
		return false
	if _data.dex_order_new().is_empty() or _data.dex_order_alpha().is_empty():
		return false
	_dex = Gen2Pokedex.open(
		_data, _world.state, _world.state.last_dex_mode(), previous_entry
	)
	if is_inside_tree() and _options != null:
		_open_list_mode()
	return true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	if _dex != null:
		_open_list_mode()


## `wPrevDexEntry`, so the caller can carry it into the next open() the way the
## cartridge's own byte survives the dex closing.
func previous_entry() -> int:
	return _dex.prev_entry if _dex != null else 0


func current_mode() -> Mode:
	return _mode


func handle_button(button: int) -> bool:
	if _dex == null:
		return false
	match _mode:
		Mode.LIST:
			return _handle_list(button)
		Mode.ENTRY:
			return _handle_entry(button)
		Mode.OPTION:
			return _handle_option(button)
		Mode.SEARCH:
			return _handle_search(button)
		Mode.SEARCH_RESULTS:
			return _handle_search_results(button)
	return false


## `Pokedex_UpdateMainScreen`.
func _handle_list(button: int) -> bool:
	match button:
		Gen2Button.B:
			_exit()
			return true
		Gen2Button.A:
			if _dex.can_open_entry():
				_dex.open_entry()
				_open_entry_mode()
			return true
		Gen2Button.SELECT:
			_open_option_mode()
			return true
		Gen2Button.START:
			_open_search_mode()
			return true
	if _dex.move_listing(button):
		_render_list()
	return Gen2Button.is_direction(button)


## `Pokedex_UpdateDexEntryScreen`: B returns to the listing, A turns the page,
## and up and down step to the neighbouring entry.
##
## The source's four-button row is PAGE, AREA, CRY and PRNT; only PAGE is built,
## so A always turns the page rather than moving a cursor along a row whose
## other three entries would refuse.
func _handle_entry(button: int) -> bool:
	match button:
		Gen2Button.B:
			_open_list_mode()
			return true
		Gen2Button.A:
			_entry_action()
			return true
		Gen2Button.LEFT, Gen2Button.RIGHT:
			## `DexEntryScreen_ArrowCursorData` allows left and right only, over
			## four positions, and stops at either end.
			var next: int = _entry_cursor + (1 if button == Gen2Button.RIGHT else -1)
			_entry_cursor = clampi(next, 0, ENTRY_BUTTONS.size() - 1)
			_render_entry()
			return true
		Gen2Button.UP, Gen2Button.DOWN:
			if _dex.step_entry(button):
				## `Pokedex_ReinitDexEntryScreen` calls `Pokedex_InitArrowCursor`,
				## so a new entry opens on PAGE whatever the last one ended on.
				_entry_cursor = 0
				_render_entry()
			return true
	return false


## `DexEntryScreen_MenuActionJumptable`. PAGE and CRY are built; `.Area` needs a
## town map and `.Print` a printer, and both do nothing rather than refusing out
## loud, since the cartridge's own row has no refusal for them either.
func _entry_action() -> void:
	match _entry_cursor:
		ENTRY_BUTTON_PAGE:
			_dex.toggle_page()
			_render_entry()
		ENTRY_BUTTON_CRY:
			## `.Cry` is `GetCryIndex` and `PlayCry`, which is the species number
			## less one straight into `PokemonCries`, not a lookup through the
			## cry table: the row and the species share an index.
			cry_requested.emit(_dex.selected_species())


## `Pokedex_UpdateOptionScreen`: SELECT and B both return to the listing, and A
## takes the row's mode.
func _handle_option(button: int) -> bool:
	match button:
		Gen2Button.B, Gen2Button.SELECT:
			_open_list_mode()
			return true
		Gen2Button.A:
			_choose_mode()
			return true
		Gen2Button.UP, Gen2Button.DOWN:
			## `.ArrowCursorData` allows up and down only, and
			## `Pokedex_MoveArrowCursor` stops at either end rather than wrapping.
			var next: int = _option_cursor + (1 if button == Gen2Button.DOWN else -1)
			_option_cursor = clampi(next, 0, _mode_rows.size() - 1)
			_render_option()
			return true
	return false


## `.ChangeMode`, including the message it shows while the order is rebuilt.
## Choosing the mode already in use returns to the listing untouched.
func _choose_mode() -> void:
	var row: Dictionary = _mode_rows[_option_cursor]
	var changed: bool = _dex.change_mode(int(row["mode"]))
	if changed:
		_world.state.set_last_dex_mode(_dex.mode)
	_open_list_mode()
	if changed:
		_status.text = Gen2Pokedex.CHANGING_MODES_TEXT
		_status.add_theme_color_override("font_color", MUTED)


## `.exit` writes the mode back to `wLastDexMode` before it leaves.
func _exit() -> void:
	_world.state.set_last_dex_mode(_dex.mode)
	closed.emit()


## `Pokedex_InitMainScreen`, whose own `ld a, 7` is what puts the listing height
## back after the search results screen has set it to four.
func _open_list_mode() -> void:
	_mode = Mode.LIST
	_dex.listing_height = Gen2Pokedex.LISTING_HEIGHT
	_title.text = "#DEX"
	_footer.text = "D-pad: move    A: entry    SELECT: option    B: close"
	_status.text = ""
	_render_list()


func _open_entry_mode() -> void:
	_mode = Mode.ENTRY
	_entry_cursor = 0
	_status.text = ""
	_render_entry()


func _open_option_mode() -> void:
	_mode = Mode.OPTION
	_mode_rows = Gen2Pokedex.mode_rows()
	_title.text = "OPTION"
	_summary.text = ""
	_status.text = ""
	_footer.text = "D-pad: move    A: choose    B: back"
	## `Pokedex_InitOptionScreen` points the cursor at the current mode, which
	## it can do directly because the modes are the row indices.
	_option_cursor = 0
	for index: int in _mode_rows.size():
		if int(_mode_rows[index]["mode"]) == _dex.mode:
			_option_cursor = index
	_render_option()


## `Pokedex_UpdateSearchScreen`: up and down move the four rows, left and right
## change a type on the two rows that carry one, A takes the row, and START or B
## both cancel back to the listing.
func _handle_search(button: int) -> bool:
	match button:
		Gen2Button.B, Gen2Button.START:
			_open_list_mode()
			return true
		Gen2Button.A:
			_confirm_search_row()
			return true
		Gen2Button.UP, Gen2Button.DOWN:
			var next: int = _dex.search_cursor + (1 if button == Gen2Button.DOWN else -1)
			_dex.search_cursor = clampi(next, 0, Gen2Pokedex.SEARCH_ROWS.size() - 1)
			_render_search()
			return true
		Gen2Button.LEFT, Gen2Button.RIGHT:
			if _dex.move_search_type(button):
				_render_search()
			return true
	return false


## `.MenuActionJumptable`: A on either type row steps it the way right does, A on
## BEGIN SEARCH runs the search, and A on CANCEL leaves.
func _confirm_search_row() -> void:
	match _dex.search_cursor:
		Gen2Pokedex.SEARCH_ROW_TYPE_1, Gen2Pokedex.SEARCH_ROW_TYPE_2:
			_dex.move_search_type(Gen2Button.RIGHT)
			_render_search()
		Gen2Pokedex.SEARCH_ROW_BEGIN:
			if _dex.begin_search() > 0:
				_open_search_results_mode()
				return
			## `.MenuAction_BeginSearch`'s no-result branch redraws the search
			## screen under its own message rather than leaving it.
			_render_search()
			_status.text = Gen2Pokedex.TYPE_NOT_FOUND_TEXT
			_status.add_theme_color_override("font_color", MUTED)
		Gen2Pokedex.SEARCH_ROW_CANCEL:
			_open_list_mode()


## `Pokedex_UpdateSearchResultsScreen`: the same listing walk as the main screen
## over four rows instead of seven, A opens an entry and B goes back to SEARCH.
func _handle_search_results(button: int) -> bool:
	match button:
		Gen2Button.B:
			_dex.leave_search_results()
			_open_search_mode()
			return true
		Gen2Button.A:
			if _dex.can_open_entry():
				_dex.open_entry()
				_open_entry_mode()
			return true
	if _dex.move_listing(button):
		_render_search_results()
	return Gen2Button.is_direction(button)


## `Pokedex_InitSearchScreen`, which resets both type rows every time.
##
## Coming back from the results screen resets them too: `.return_to_search_screen`
## jumps to DEXSTATE_SEARCH_SCR, and that jumptable entry is this Init rather
## than its Update, so the search is not remembered.
func _open_search_mode() -> void:
	_mode = Mode.SEARCH
	_dex.open_search()
	_title.text = "SEARCH"
	_status.text = ""
	_footer.text = "D-pad: move    Left/Right: type    A: choose    B: back"
	_render_search()


## `Pokedex_InitSearchResultsScreen`, whose own `ld a, 4` is the shorter listing.
func _open_search_results_mode() -> void:
	_mode = Mode.SEARCH_RESULTS
	_dex.listing_height = Gen2Pokedex.SEARCH_RESULTS_HEIGHT
	_title.text = "SEARCH RESULTS"
	_status.text = ""
	_footer.text = "D-pad: move    A: entry    B: back"
	_render_search_results()


func _render_search() -> void:
	_summary.text = ""
	_render_rows(Gen2Pokedex.SEARCH_ROWS, func(row: String) -> String:
		match row:
			Gen2Pokedex.SEARCH_ROWS[Gen2Pokedex.SEARCH_ROW_TYPE_1]:
				return "%s  %s" % [row, _dex.search_type_name(_dex.search_type_1)]
			Gen2Pokedex.SEARCH_ROWS[Gen2Pokedex.SEARCH_ROW_TYPE_2]:
				return "%s  %s" % [row, _dex.search_type_name(_dex.search_type_2)]
		return row
	, _dex.search_cursor)


## `.BottomWindowText` and `Pokedex_PlaceSearchResultsTypeStrings`: the count and
## the types it was found for sit under the listing.
func _render_search_results() -> void:
	var types: String = _dex.search_type_name(_dex.search_type_1)
	if _dex.search_type_2 != Gen2Pokedex.SEARCH_TYPE_NONE:
		types += "/%s" % _dex.search_type_name(_dex.search_type_2)
	_summary.text = "%s    %3d FOUND!" % [types, _dex.search_result_count]
	_render_rows(_dex.rows(), func(row: Dictionary) -> String:
		if bool(row["empty"]):
			return ""
		var symbol: String = CAUGHT_SYMBOL if bool(row["caught"]) else UNCAUGHT_SYMBOL
		var number: String = String(row["number"])
		var prefix: String = "%s " % number if not number.is_empty() else ""
		return "%s%s%s" % [prefix, symbol, String(row["name"])]
	)


## The listing, plus the SEEN and OWN totals `Pokedex_DrawMainScreenBG` prints
## beside it.
func _render_list() -> void:
	_summary.text = "SEEN %3d    OWN %3d" % [_dex.seen_count(), _dex.caught_count()]
	var rows: Array = _dex.rows()
	_render_rows(rows, func(row: Dictionary) -> String:
		if bool(row["empty"]):
			return ""
		var symbol: String = CAUGHT_SYMBOL if bool(row["caught"]) else UNCAUGHT_SYMBOL
		var number: String = String(row["number"])
		var prefix: String = "%s " % number if not number.is_empty() else ""
		return "%s%s%s" % [prefix, symbol, String(row["name"])]
	)


func _render_entry() -> void:
	var entry: Dictionary = _dex.entry()
	_title.text = "No.%s  %s" % [String(entry["number"]), String(entry["name"])]
	_summary.text = String(entry["category"])
	for child: Node in _options.get_children():
		child.queue_free()
	## The height and weight rows come from the entry screen's own template
	## ("HT" and "WT"), and stay blank for a species that has not been caught.
	_add_line("HT  %s" % String(entry["height"]))
	_add_line("WT  %slb" % String(entry["weight"]))
	_add_line("")
	for line: String in String(entry["text"]).split("\n"):
		_add_line(line)
	_status.text = "P.%d" % (int(entry["page"]) + 1) if bool(entry["caught"]) else ""
	var buttons: PackedStringArray = PackedStringArray()
	for index: int in ENTRY_BUTTONS.size():
		buttons.append(
			("[%s]" if index == _entry_cursor else " %s ") % ENTRY_BUTTONS[index]
		)
	_footer.text = "%s   Left/Right: button   A: choose   B: back" % " ".join(buttons)


func _render_option() -> void:
	_render_rows(_mode_rows, func(row: Dictionary) -> String:
		return String(row["label"])
	)
	_summary.text = String(_mode_rows[_option_cursor]["description"])


## [param row_cursor] is the highlighted row; the listing screens pass the
## dex's own cursor and the two form screens pass theirs.
func _render_rows(values: Array, label_for: Callable, row_cursor: int = -1) -> void:
	if _options == null:
		return
	for child: Node in _options.get_children():
		child.queue_free()
	var cursor: int = row_cursor
	if cursor < 0:
		cursor = _option_cursor if _mode == Mode.OPTION else _dex.cursor
	for index: int in values.size():
		var label := Label.new()
		var text: String = label_for.call(values[index])
		label.text = ("> " if index == cursor and not text.is_empty() else "  ") + text
		label.add_theme_color_override(
			"font_color", ACCENT if index == cursor else TEXT
		)
		label.add_theme_font_size_override("font_size", 18)
		_options.add_child(label)


func _add_line(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", TEXT)
	label.add_theme_font_size_override("font_size", 18)
	_options.add_child(label)


func _build_ui() -> void:
	var scrim := ColorRect.new()
	scrim.color = SCRIM
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 320)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)
	_title = Label.new()
	_title.add_theme_color_override("font_color", TEXT)
	_title.add_theme_font_size_override("font_size", 24)
	content.add_child(_title)
	_summary = Label.new()
	_summary.add_theme_color_override("font_color", MUTED)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_summary)
	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 4)
	_options.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_options)
	_status = Label.new()
	_status.add_theme_color_override("font_color", MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status)
	_footer = Label.new()
	_footer.add_theme_color_override("font_color", ACCENT)
	content.add_child(_footer)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	return style
