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
## Three of the source's six states are here: the listing, the entry screen and
## the OPTION screen. SEARCH, its results and the Unown dex are not, so START on
## the listing does nothing rather than opening a screen that is not built.

## Emitted on B from the listing, which is where `DEXSTATE_EXIT` lands.
signal closed

enum Mode { LIST, ENTRY, OPTION }

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

var _dex: Gen2Pokedex = null
var _world: Gen2WorldAPI = null
var _data: GameData = null
var _mode: Mode = Mode.LIST
## The OPTION screen's own cursor (`wDexArrowCursorPosIndex`), which opens on
## the row matching the current mode.
var _option_cursor: int = 0
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
	return false


## `Pokedex_UpdateMainScreen`. START would open SEARCH, which is not built, so
## it is answered as handled and does nothing rather than reaching a screen that
## is not there.
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
			_dex.toggle_page()
			_render_entry()
			return true
		Gen2Button.UP, Gen2Button.DOWN:
			if _dex.step_entry(button):
				_render_entry()
			return true
	return false


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


func _open_list_mode() -> void:
	_mode = Mode.LIST
	_title.text = "#DEX"
	_footer.text = "D-pad: move    A: entry    SELECT: option    B: close"
	_status.text = ""
	_render_list()


func _open_entry_mode() -> void:
	_mode = Mode.ENTRY
	_footer.text = "A: page    Up/Down: entry    B: back"
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


func _render_option() -> void:
	_render_rows(_mode_rows, func(row: Dictionary) -> String:
		return String(row["label"])
	)
	_summary.text = String(_mode_rows[_option_cursor]["description"])


func _render_rows(values: Array, label_for: Callable) -> void:
	if _options == null:
		return
	for child: Node in _options.get_children():
		child.queue_free()
	var cursor: int = _dex.cursor if _mode == Mode.LIST else _option_cursor
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
