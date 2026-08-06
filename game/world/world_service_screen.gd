class_name Gen2WorldServiceScreen
extends Control

## Presentation host for imported overworld services. It owns only selection,
## labels and input. Script state and transactions stay in the scene-free world
## hosts and API.

signal completed(results: Array)

const PANEL: Color = Color("#14233a")
const BORDER: Color = Color("#4f6f9e")
const SCRIM: Color = Color(0.02, 0.04, 0.08, 0.78)
const TEXT: Color = Color("#f4f7fb")
const MUTED: Color = Color("#9eacc0")
const ACCENT: Color = Color("#f3c969")
const SUCCESS: Color = Color("#7bd89a")
const ERROR: Color = Color("#ef8a8a")

enum MODE { MENU, MART, PHONE, PHONE_LIST, AUDIO }

const WorldMenu := preload("res://game/world/world_menu.gd")

var _world: Gen2WorldAPI = null
var _data: GameData = null
var _save: Gen2SaveData = null
var _persist: bool = false
var _request: Dictionary = {}
var _resolved: Dictionary = {}
var _mode: int = -1
var _choices: Array = []
var _menu_input: Dictionary = {}
var _menu: Gen2WorldMenu = null
var _cursor: int = 0
var _mart_entries: Array = []
var _mart_quantity: int = 1
var _mart_purchased: bool = false
var _phone_entries: Array = []

var _title: Label = null
var _summary: Label = null
var _options: VBoxContainer = null
var _status: Label = null
var _footer: Label = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


## Opens the host for whatever pending input the world currently exposes.
func open_pending(
	world: Gen2WorldAPI,
	data: GameData,
	save: Gen2SaveData = null,
	persist: bool = false
) -> bool:
	_world = world
	_data = data
	_save = save
	_persist = persist
	if _world == null or _data == null:
		_show_error("Service host has no world or cartridge cache.")
		return false
	var input: Dictionary = _world.pending_script_input()
	var input_type: StringName = StringName(input.get("type", &""))
	if input_type in [&"choice", &"menu"]:
		_open_menu(input)
		return true
	var request: Dictionary = _world.pending_runtime_request()
	if request.is_empty():
		_show_error("No pending service request.")
		return false
	_request = request
	var resolved: Dictionary = Gen2WorldHost.resolve_runtime_request(_world, request)
	if not bool(resolved.get("ok", false)):
		_show_error("Service unavailable: %s" % String(resolved.get("reason", "unknown")))
		return false
	_resolved = resolved
	match StringName(request.get("kind", &"")):
		&"mart_requested":
			_open_mart(resolved.get("data", {}).get("mart", {}))
			return true
		&"phone_call_requested", &"special_phone_call_requested":
			_open_phone(request, resolved.get("data", {}))
			return true
		&"audio_requested":
			_open_audio(request, resolved.get("data", {}).get("audio", {}))
			return true
	_show_error("No scene host for %s." % String(request.get("kind", "request")))
	return false


func is_active() -> bool:
	return _mode >= 0


## Opens the Pokegear phone list. Contact order follows the cartridge table,
## and only registered numbers are selectable.
func open_phone_list(
	world: Gen2WorldAPI,
	data: GameData,
	save: Gen2SaveData = null,
	persist: bool = false
) -> bool:
	_world = world
	_data = data
	_save = save
	_persist = persist
	if _world == null or _data == null:
		_show_error("Phone has no world or cartridge cache.")
		return false
	_phone_entries = _world.registered_phone_contacts()
	_open_phone_list()
	return true


## Parent screens route keys here so the service overlay owns input while open.
func handle_key(keycode: int) -> bool:
	if not is_active():
		return false
	match keycode:
		KEY_UP, KEY_W:
			_move_direction(Vector2i.UP)
			return true
		KEY_DOWN, KEY_S:
			_move_direction(Vector2i.DOWN)
			return true
		KEY_LEFT, KEY_A:
			_move_direction(Vector2i.LEFT)
			return true
		KEY_RIGHT, KEY_D:
			_move_direction(Vector2i.RIGHT)
			return true
		KEY_SPACE, KEY_ENTER, KEY_Z:
			_confirm()
			return true
		KEY_ESCAPE, KEY_X, KEY_B:
			_cancel()
			return true
	return false


func selected_index() -> int:
	return _cursor


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
	panel.custom_minimum_size = Vector2(500, 300)
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


func _open_menu(input: Dictionary) -> void:
	_mode = MODE.MENU
	_menu_input = input.duplicate(true)
	_menu = WorldMenu.from_input(_menu_input)
	_choices = _menu.options.duplicate(true)
	_cursor = _menu.selected_index()
	_title.text = "MENU"
	_summary.text = String(input.get("command", input.get("menu_kind", "Choose an option")))
	_status.text = ""
	_footer.text = "Arrows: move    Space/Enter: choose    Esc: cancel"
	_render_options()


func _open_mart(mart: Dictionary) -> void:
	_mode = MODE.MART
	_mart_entries = Gen2WorldMartHost.entries(_data, mart)
	_mart_entries.append({"leave": true, "name": "LEAVE"})
	_mart_quantity = 1
	_mart_purchased = false
	_cursor = 0
	_title.text = String(mart.get("label", "MART"))
	_summary.text = "Money: %d" % _world.state.money(Gen2WorldMartHost.MONEY_ACCOUNT)
	_status.text = "Select an item. Left/Right changes quantity."
	_footer.text = "Arrows: move/quantity    Space/Enter: buy    Esc: leave"
	_render_options()


func _open_phone(request: Dictionary, data: Dictionary) -> void:
	_mode = MODE.PHONE
	_cursor = 0
	_title.text = "PHONE"
	var summary: Dictionary = {}
	if StringName(request.get("kind", &"")) == &"phone_call_requested":
		summary = Gen2WorldPhoneHost.contact_summary(
			_data, data.get("contact", {})
		)
		_summary.text = _phone_text(summary)
	else:
		summary = Gen2WorldPhoneHost.special_call_summary(
			_data, data.get("special_call", {})
		)
		_summary.text = "Special call %d for contact %d." % [
			int(summary.get("index", -1)), int(summary.get("contact", -1)),
		]
	_status.text = "The imported call record is ready."
	if bool(data.get("out_of_area", false)):
		_status.text = "This call will use the cartridge out-of-area script."
	elif bool(data.get("phone", {}).get("same_map", false)):
		_status.text = "This call will use the cartridge same-map script."
	_footer.text = "Space/Enter: continue    Esc: hang up"
	_render_options(["Continue"])


func _open_phone_list() -> void:
	_mode = MODE.PHONE_LIST
	_cursor = 0
	_title.text = "PHONE"
	_summary.text = "Registered numbers"
	_status.text = "Choose a contact to call." if not _phone_entries.is_empty() else "No registered numbers."
	_footer.text = "Arrows: move    Space/Enter: call    Esc: close"
	_render_options()


func _open_audio(request: Dictionary, record: Dictionary) -> void:
	_mode = MODE.AUDIO
	_cursor = 0
	_title.text = "AUDIO HOST"
	var kind: StringName = StringName(request.get("values", {}).get("kind", &"audio"))
	var playback: Dictionary = Gen2WorldAudioHost.play(record, kind)
	_summary.text = "Resolved %s %s:%04X (%d bytes)." % [
		String(kind), int(record.get("bank", -1)), int(record.get("address", -1)),
		int(record.get("byte_count", 0)),
	]
	_status.text = "Playback backend: %s" % String(playback.get("backend", "unavailable"))
	_footer.text = "Space/Enter: continue    Esc: stop"
	_render_options(["Continue"])


func _move_cursor(delta: int) -> void:
	var count: int = _option_count()
	if count <= 0:
		return
	_cursor = wrapi(_cursor + delta, 0, count)
	if _mode == MODE.MART:
		_mart_quantity = 1
	_render_options()


func _move_direction(direction: Vector2i) -> void:
	if _mode == MODE.MENU and _menu != null:
		if _menu.move(direction):
			_cursor = _menu.selected_index()
			_render_options()
		return
	if _mode == MODE.MART and direction.x != 0:
		_change_mart_quantity(direction.x)
		return
	if direction.x != 0:
		_move_cursor(direction.x)
	else:
		_move_cursor(direction.y)


func _confirm() -> void:
	if _mode == MODE.MENU:
		if _choices.is_empty():
			_status.text = "The imported menu has no selectable options."
			_status.add_theme_color_override("font_color", ERROR)
			return
		_finish_input(_cursor)
		return
	if _mode == MODE.MART:
		if _cursor >= _mart_entries.size():
			_cancel()
			return
		var entry: Dictionary = _mart_entries[_cursor]
		if bool(entry.get("leave", false)):
			_finish_runtime({"ok": true, "script_value": 1 if _mart_purchased else 0})
			return
		var purchase: Dictionary = Gen2WorldMartHost.purchase(
			_world, _save, _mart_source(), int(entry.get("item", 0)), _mart_quantity, _persist
		)
		if not bool(purchase.get("ok", false)):
			_status.text = "Purchase failed: %s" % String(purchase.get("reason", "unknown"))
			_status.add_theme_color_override("font_color", ERROR)
			return
		_mart_purchased = true
		_summary.text = "Money: %d" % _world.state.money(Gen2WorldMartHost.MONEY_ACCOUNT)
		_status.text = "Bought %s. Owned: %d" % [
			String(purchase.get("name", "UNKNOWN")), int(purchase.get("owned", 0)),
		]
		_status.add_theme_color_override("font_color", SUCCESS)
		_mart_quantity = 1
		_render_options()
		return
	if _mode == MODE.PHONE_LIST:
		if _phone_entries.is_empty():
			_status.text = "No registered numbers."
			return
		var contact: Dictionary = _phone_entries[_cursor]
		var results: Array = _world.request_outgoing_phone_call(int(contact.get("index", -1)))
		_mode = -1
		completed.emit(results)
		return
	if _mode in [MODE.PHONE, MODE.AUDIO]:
		_finish_runtime({"ok": true, "script_value": 1})


func _cancel() -> void:
	if _mode == MODE.MENU:
		_finish_input_cancelled()
	elif _mode == MODE.MART:
		_finish_runtime({"ok": true, "script_value": 1 if _mart_purchased else 0, "cancelled": true})
	elif _mode == MODE.PHONE_LIST:
		_mode = -1
		completed.emit([])
	elif _mode in [MODE.PHONE, MODE.AUDIO]:
		_finish_runtime({"ok": true, "script_value": 0, "cancelled": true})


func _finish_input(choice: int) -> void:
	var results: Array = _world.choose_script_input(choice)
	_finish(results)


func _finish_input_cancelled() -> void:
	var results: Array = _world.cancel_script_input()
	_finish(results)


func _finish_runtime(result: Dictionary) -> void:
	var host_result: Dictionary = Gen2WorldHost.complete_runtime_request(
		_world, result, _save, _persist
	)
	if not bool(host_result.get("ok", false)):
		_status.text = "Request failed: %s" % String(host_result.get("reason", "unknown"))
		_status.add_theme_color_override("font_color", ERROR)
		return
	_finish(host_result.get("results", []))


func _finish(results: Array) -> void:
	_mode = -1
	completed.emit(results)


func _render_options(override: Array = []) -> void:
	if _options == null:
		return
	for child: Node in _options.get_children():
		child.queue_free()
	var parent: Container = _options
	if _mode == MODE.MENU and _menu != null and _menu.kind == &"2d":
		var grid := GridContainer.new()
		grid.columns = maxi(1, _menu.columns)
		grid.add_theme_constant_override("h_separation", 18)
		_options.add_child(grid)
		parent = grid
	var values: Array = override if not override.is_empty() else (
		_choices if _mode == MODE.MENU else _mart_entries if _mode == MODE.MART \
		else _phone_entries if _mode == MODE.PHONE_LIST else ["Continue"]
	)
	for index: int in values.size():
		var value: Variant = values[index]
		var label := Label.new()
		var name: String = str(value)
		if value is Dictionary:
			var dictionary: Dictionary = value as Dictionary
			name = str(dictionary.get("name", ""))
			if name.is_empty():
				name = str(dictionary.get("caller_label", ""))
			if name.is_empty():
				name = str(dictionary.get("trainer_name", "UNKNOWN"))
			if name.is_empty() and dictionary.has("index"):
				name = "CONTACT %d" % int(dictionary.get("index", -1))
		if value is Dictionary and _mode == MODE.MART \
			and not bool((value as Dictionary).get("leave", false)):
			var price: int = int((value as Dictionary).get("price", 0))
			if index == _cursor:
				name = "%s    %d x %d = %d" % [
					name, price, _mart_quantity, price * _mart_quantity,
				]
			else:
				name = "%s    %d" % [name, price]
		if value is Dictionary and _mode == MODE.PHONE_LIST:
			if int((value as Dictionary).get("trainer_class", 0)) > 0:
				name = "%s %d" % [name, int((value as Dictionary).get("trainer_number", 0))]
		label.text = ("> " if index == _cursor else "  ") + name
		label.add_theme_color_override("font_color", ACCENT if index == _cursor else TEXT)
		label.add_theme_font_size_override("font_size", 18)
		parent.add_child(label)
	if _mode == MODE.MART:
		_update_mart_status()


func _option_count() -> int:
	if _mode == MODE.MENU:
		return _menu.options.size() if _menu != null else _choices.size()
	if _mode == MODE.MART:
		return _mart_entries.size()
	if _mode == MODE.PHONE_LIST:
		return _phone_entries.size()
	return 1


func _mart_source() -> Dictionary:
	return _resolved.get("data", {}).get("mart", {})


func _change_mart_quantity(delta: int) -> void:
	if _cursor < 0 or _cursor >= _mart_entries.size():
		return
	var entry: Dictionary = _mart_entries[_cursor]
	if bool(entry.get("leave", false)):
		return
	var owned: int = _world.state.item_quantity(int(entry.get("item", 0)))
	var maximum: int = Gen2WorldMartHost.MAX_ITEM_STACK - owned
	if maximum <= 0:
		_mart_quantity = 0
	else:
		_mart_quantity = clampi(_mart_quantity + delta, 1, maximum)
	_render_options()


func _update_mart_status() -> void:
	if _mode != MODE.MART or _cursor < 0 or _cursor >= _mart_entries.size():
		return
	var entry: Dictionary = _mart_entries[_cursor]
	if bool(entry.get("leave", false)):
		_status.text = "Leave this shop."
		return
	var item: int = int(entry.get("item", 0))
	var owned: int = _world.state.item_quantity(item)
	var maximum: int = Gen2WorldMartHost.MAX_ITEM_STACK - owned
	if maximum <= 0:
		_status.text = "This item stack is full."
		return
	_status.text = "Owned: %d    Quantity: %d    Total: %d" % [
		owned, _mart_quantity, int(entry.get("price", 0)) * _mart_quantity,
	]


func _phone_text(summary: Dictionary) -> String:
	return "%s %d\nMap %d/%d\nCaller time %d, callee time %d" % [
		String(summary.get("trainer_name", "UNKNOWN")),
		int(summary.get("trainer_number", 0)),
		int(summary.get("map_group", -1)), int(summary.get("map_number", -1)),
		int(summary.get("caller_time", 0)), int(summary.get("callee_time", 0)),
	]


func _show_error(message: String) -> void:
	_mode = -1
	_menu = null
	if _title != null:
		_title.text = "SERVICE ERROR"
		_summary.text = message
		_status.text = ""
		_footer.text = ""
		_status.add_theme_color_override("font_color", ERROR)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	return style
