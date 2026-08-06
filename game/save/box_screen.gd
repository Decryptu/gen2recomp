class_name Gen2BoxScreen
extends Control

## First PC presentation: one numbered box, its twenty fixed slots, and the
## explicit party/box transfer boundary. Box names and cartridge SRAM layout
## remain outside this screen until their canonical source is verified.

signal closed(result: Dictionary)

const BACKGROUND: Color = Color("#09111f")
const PANEL: Color = Color("#14233a")
const BORDER: Color = Color("#2d4566")
const TEXT: Color = Color("#f4f7fb")
const MUTED: Color = Color("#9eacc0")
const ACCENT: Color = Color("#f3c969")
const SUCCESS: Color = Color("#7bd89a")
const ERROR: Color = Color("#ef8a8a")

var _data: GameData = null
var _data_override: GameData = null
var _save: Gen2SaveData = null
var _save_override: Gen2SaveData = null
var _persist: bool = true
var _embedded: bool = false
var _box_index: int = 0
var _selected_box_slot: int = -1
var _selected_party_index: int = -1
var _box_title: Label = null
var _party_members: VBoxContainer = null
var _box_grid: GridContainer = null
var _selection: Label = null
var _status: Label = null


func _ready() -> void:
	_data = _data_override if _data_override != null else _resolve_data()
	_save = _save_override if _save_override != null else _resolve_save()
	_build_ui()
	_refresh()


## Supplies the cache/save context. Embedded overworld use can keep the same
## atomic storage operations in memory while a selected runtime save persists.
func set_context(
	data: GameData, save: Gen2SaveData, persist: bool = true, embedded: bool = false
) -> void:
	_data_override = data
	_save_override = save
	_persist = persist
	_embedded = embedded
	_data = data
	_save = save
	if is_inside_tree() and _box_grid != null:
		_refresh()


func box_snapshot() -> Dictionary:
	var boxes: Array = []
	if _save != null:
		for box_index: int in Gen2SaveData.BOX_COUNT:
			var slots: Array = []
			var box: Gen2SaveBox = _save.boxes[box_index] if box_index < _save.boxes.size() else null
			for slot: int in Gen2SaveBox.CAPACITY:
				var mon: Gen2SaveMon = box.slots[slot] if box != null and slot < box.slots.size() else null
				slots.append(_mon_snapshot(box_index, slot, mon))
			boxes.append({"index": box_index, "slots": slots})
	return {
		"box": _box_index,
		"selected_box_slot": _selected_box_slot,
		"selected_party_index": _selected_party_index,
		"boxes": boxes,
	}


func select_box(box_index: int) -> bool:
	if _save == null or box_index < 0 or box_index >= _save.boxes.size():
		return false
	_box_index = box_index
	_selected_box_slot = -1
	if _box_grid != null:
		_refresh()
	return true


func select_box_slot(slot: int) -> bool:
	if slot < 0 or slot >= Gen2SaveBox.CAPACITY:
		return false
	_selected_box_slot = slot
	_selected_party_index = -1
	if _box_grid != null:
		_refresh_selection()
	return true


func select_party_member(index: int) -> bool:
	if _save == null or index < 0 or index >= _save.party.size():
		return false
	_selected_party_index = index
	_selected_box_slot = -1
	if _party_members != null:
		_refresh_selection()
	return true


func deposit_selected_party() -> bool:
	if _save == null or _selected_party_index < 0:
		_set_status("Select a party member first.", ERROR)
		return false
	var result: Dictionary = Gen2SaveStorage.deposit_party_to_box(
		_save, _data, _selected_party_index, _box_index, -1, _persist
	)
	if not bool(result.get("ok", false)):
		_set_status(String(result.get("message", result.get("reason", "Deposit refused."))), ERROR)
		return false
	_set_status("Moved to Box %d slot %d." % [int(result["box"]) + 1, int(result["slot"]) + 1], SUCCESS)
	_selected_party_index = -1
	_refresh()
	return true


func withdraw_selected_box() -> bool:
	if _save == null or _selected_box_slot < 0:
		_set_status("Select a stored Pokémon first.", ERROR)
		return false
	var result: Dictionary = Gen2SaveStorage.withdraw_box_to_party(
		_save, _data, _box_index, _selected_box_slot, _persist
	)
	if not bool(result.get("ok", false)):
		_set_status(String(result.get("message", result.get("reason", "Withdrawal refused."))), ERROR)
		return false
	_set_status("Moved to party slot %d." % (int(result["party_index"]) + 1), SUCCESS)
	_selected_box_slot = -1
	_refresh()
	return true


func _resolve_data() -> GameData:
	return GameRuntime.selected_data() if GameRuntime.has_selected_game() else GameData.open_any()


func _resolve_save() -> Gen2SaveData:
	if _data == null or not GameRuntime.has_selected_save_slot():
		return null
	return GameRuntime.selected_save()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 42)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_right", 42)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	content.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 3)
	header.add_child(heading)
	var title := Label.new()
	title.text = "PC STORAGE"
	title.add_theme_color_override("font_color", TEXT)
	title.add_theme_font_size_override("font_size", 30)
	heading.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Party and fixed twenty-slot boxes"
	subtitle.add_theme_color_override("font_color", MUTED)
	heading.add_child(subtitle)
	var previous := _button("Previous box", TEXT)
	previous.pressed.connect(_previous_box)
	header.add_child(previous)
	var next := _button("Next box", TEXT)
	next.pressed.connect(_next_box)
	header.add_child(next)
	var back := _button("Turn off PC" if _embedded else "Back to party", TEXT)
	back.pressed.connect(_back)
	header.add_child(back)

	_box_title = Label.new()
	_box_title.add_theme_color_override("font_color", ACCENT)
	_box_title.add_theme_font_size_override("font_size", 18)
	content.add_child(_box_title)

	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 18)
	content.add_child(main)

	var box_panel := PanelContainer.new()
	box_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box_panel.add_theme_stylebox_override("panel", _panel_style(PANEL, BORDER, 8))
	main.add_child(box_panel)
	var box_margin := MarginContainer.new()
	box_margin.add_theme_constant_override("margin_left", 14)
	box_margin.add_theme_constant_override("margin_top", 14)
	box_margin.add_theme_constant_override("margin_right", 14)
	box_margin.add_theme_constant_override("margin_bottom", 14)
	box_panel.add_child(box_margin)
	_box_grid = GridContainer.new()
	_box_grid.columns = 4
	_box_grid.add_theme_constant_override("h_separation", 8)
	_box_grid.add_theme_constant_override("v_separation", 8)
	box_margin.add_child(_box_grid)

	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 300
	side.add_theme_constant_override("separation", 10)
	main.add_child(side)
	var party_heading := Label.new()
	party_heading.text = "PARTY"
	party_heading.add_theme_color_override("font_color", TEXT)
	party_heading.add_theme_font_size_override("font_size", 18)
	side.add_child(party_heading)
	_party_members = VBoxContainer.new()
	_party_members.add_theme_constant_override("separation", 6)
	side.add_child(_party_members)
	var deposit := _button("Deposit selected party member", ACCENT)
	deposit.pressed.connect(deposit_selected_party)
	side.add_child(deposit)
	var withdraw := _button("Withdraw selected box slot", ACCENT)
	withdraw.pressed.connect(withdraw_selected_box)
	side.add_child(withdraw)
	_selection = Label.new()
	_selection.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selection.custom_minimum_size.y = 56
	_selection.add_theme_color_override("font_color", MUTED)
	side.add_child(_selection)

	_status = Label.new()
	_status.add_theme_color_override("font_color", MUTED)
	content.add_child(_status)


func _refresh() -> void:
	if _box_grid == null:
		return
	for child: Node in _box_grid.get_children():
		child.free()
	for slot: int in Gen2SaveBox.CAPACITY:
		var button := _button(_slot_text(slot), TEXT)
		button.custom_minimum_size = Vector2(170, 58)
		button.pressed.connect(_select_box_slot.bind(slot))
		_box_grid.add_child(button)
	if _party_members != null:
		for child: Node in _party_members.get_children():
			child.free()
		for index: int in Gen2SaveData.MAX_PARTY:
			var member := _button(_party_text(index), TEXT)
			member.custom_minimum_size = Vector2(280, 40)
			if _save != null and index < _save.party.size():
				member.pressed.connect(_select_party_member.bind(index))
			else:
				member.disabled = true
			_party_members.add_child(member)
	if _box_title != null:
		_box_title.text = "Box %d of %d" % [_box_index + 1, Gen2SaveData.BOX_COUNT]
	_refresh_selection()


func _refresh_selection() -> void:
	if _selection == null:
		return
	if _save == null:
		_selection.text = "No validated save selected."
		_set_status("No validated save selected.", ERROR)
		return
	if _selected_party_index >= 0 and _selected_party_index < _save.party.size():
		_selection.text = "Selected party: %s\nDeposit uses the first free slot in Box %d." % [
			_display_name(_save.party[_selected_party_index]), _box_index + 1,
		]
		return
	if _selected_box_slot >= 0:
		var box: Gen2SaveBox = _save.boxes[_box_index]
		var mon: Gen2SaveMon = box.slots[_selected_box_slot] if box != null else null
		_selection.text = "Selected Box %d slot %d: %s" % [
			_box_index + 1, _selected_box_slot + 1,
			_display_name(mon) if mon != null else "Empty",
		]
		return
	_selection.text = "Select a party member or a stored Pokémon."


func _slot_text(slot: int) -> String:
	if _save == null or _box_index >= _save.boxes.size() or _save.boxes[_box_index] == null:
		return "%02d\nEmpty" % (slot + 1)
	var mon: Gen2SaveMon = _save.boxes[_box_index].slots[slot]
	if mon == null:
		return "%02d\nEmpty" % (slot + 1)
	return "%02d  %s\nLv %d" % [slot + 1, _display_name(mon), mon.level]


func _party_text(index: int) -> String:
	if _save == null or index >= _save.party.size():
		return "%d  Empty" % (index + 1)
	var mon: Gen2SaveMon = _save.party[index]
	return "%d  %s  Lv %d" % [index + 1, _display_name(mon), mon.level]


func _mon_snapshot(box: int, slot: int, mon: Gen2SaveMon) -> Dictionary:
	if mon == null:
		return {"empty": true, "box": box, "slot": slot}
	return {
		"empty": false, "box": box, "slot": slot,
		"name": _display_name(mon), "species": mon.species, "level": mon.level,
	}


func _display_name(mon: Gen2SaveMon) -> String:
	if mon == null:
		return "Empty"
	if not mon.nickname.is_empty():
		return mon.nickname
	return String(_data.species(mon.species).get("name", "UNKNOWN")) if _data != null else "UNKNOWN"


func _previous_box() -> void:
	if _save != null:
		_box_index = posmod(_box_index - 1, Gen2SaveData.BOX_COUNT)
		_selected_box_slot = -1
		_refresh()


func _next_box() -> void:
	if _save != null:
		_box_index = posmod(_box_index + 1, Gen2SaveData.BOX_COUNT)
		_selected_box_slot = -1
		_refresh()


func _select_box_slot(slot: int) -> void:
	select_box_slot(slot)


func _select_party_member(index: int) -> void:
	select_party_member(index)


func _set_status(message: String, colour: Color) -> void:
	if _status == null:
		return
	_status.text = message
	_status.add_theme_color_override("font_color", colour)


func _back() -> void:
	if _embedded:
		close_embedded()
		return
	get_tree().change_scene_to_file.call_deferred("res://game/save/party_screen.tscn")


func close_embedded() -> void:
	if not _embedded:
		return
	closed.emit({"ok": true, "script_value": 0, "changed": false})


func _button(text: String, colour: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_color_override("font_color", colour)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_font_size_override("font_size", 14)
	return button


func _panel_style(fill: Color, line: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = line
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 18
	style.content_margin_top = 14
	style.content_margin_right = 18
	style.content_margin_bottom = 14
	return style
