class_name Gen2SaveScreen
extends Control

## Player-facing save selection for one imported cartridge revision.
##
## The screen only coordinates validated save data. Original SRAM bytes enter
## through [Gen2SramAdapter], and project slots are written through
## [Gen2SaveStore], so no control here needs to know a cartridge offset.

const BACKGROUND: Color = Color("#09111f")
const PANEL: Color = Color("#14233a")
const PANEL_SELECTED: Color = Color("#1d3352")
const BORDER: Color = Color("#2d4566")
const BORDER_SELECTED: Color = Color("#f3c969")
const TEXT: Color = Color("#f4f7fb")
const MUTED: Color = Color("#9eacc0")
const ACCENT: Color = Color("#f3c969")
const SUCCESS: Color = Color("#7bd89a")
const ERROR: Color = Color("#ef8a8a")

var _data: GameData = null
var _data_override: GameData = null
var _selected_slot: int = 0
var _selected_starter: int = Gen2SaveStore.STARTER_SPECIES[1]
var _new_game_visible: bool = false
var _slots: Array = []
var _pending_replace_action: StringName = &""
var _pending_import_path: String = ""

var _slots_container: HBoxContainer = null
var _slots_section: Label = null
var _slot_scroll: ScrollContainer = null
var _details_box: VBoxContainer = null
var _status_label: Label = null
var _status_detail: Label = null
var _name_input: LineEdit = null
var _confirm_dialog: ConfirmationDialog = null
var _file_dialog: FileDialog = null


func _ready() -> void:
	_data = _data_override if _data_override != null else _resolve_data()
	_build_ui()
	_refresh()


## Test and tooling seam for synthetic caches. Production callers use the
## selected registry game through [GameRuntime].
func set_data(data: GameData) -> void:
	_data_override = data
	_data = data
	if is_inside_tree() and _slots_container != null:
		_refresh()


## Selects one of the three project slots.
func select_slot(slot: int) -> bool:
	if slot < 0 or slot >= Gen2SaveStore.SLOT_COUNT:
		return false
	_selected_slot = slot
	_new_game_visible = false
	_refresh()
	return true


## Opens the new-game form for a slot. Existing slots require confirmation
## through the button-driven path, while tests and tools may call this directly.
func open_new_game(slot: int = -1) -> bool:
	if slot >= 0 and not select_slot(slot):
		return false
	_new_game_visible = true
	_refresh_details()
	return true


## Creates and validates a new-game save in the selected slot.
func create_new_game(player_name: String, starter_species: int) -> bool:
	if _data == null:
		_set_status("New game unavailable.", "No imported cartridge cache is selected.", ERROR)
		return false
	var created: Gen2SaveData = Gen2SaveStore.create_new_game(
		_data, _selected_slot, player_name, starter_species
	)
	if created == null:
		_set_status(
			"New game was not created.",
			"Enter a name of ten characters or fewer and choose a valid starter.",
			ERROR
		)
		return false
	var result: Dictionary = Gen2SaveStore.save(created, _data)
	if not result["ok"]:
		_set_status("New game was not saved.", String(result["message"]), ERROR)
		return false
	_new_game_visible = false
	_refresh()
	_set_status(
		"New game created in slot %d." % (_selected_slot + 1),
		"%s is ready." % _species_name(starter_species),
		SUCCESS
	)
	return true


## Imports an original SRAM file into the selected project slot. A failed
## import never reaches [Gen2SaveStore.save], so the previous slot remains.
func import_sav_path(path: String, slot: int = -1) -> bool:
	if _data == null:
		_set_status("Save import unavailable.", "No imported cartridge cache is selected.", ERROR)
		return false
	if slot >= 0 and not select_slot(slot):
		return false
	if not FileAccess.file_exists(path):
		_set_status("Save import failed.", "The selected file could not be opened.", ERROR)
		return false
	var raw: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if raw.is_empty():
		_set_status("Save import failed.", "The selected file is empty.", ERROR)
		return false
	var imported: Dictionary = Gen2SramAdapter.import_bytes(
		_data.id, _data.sha1, _selected_slot, raw, _data
	)
	if not imported["ok"]:
		_set_status("Save import rejected.", String(imported["message"]), ERROR)
		return false
	var save: Gen2SaveData = imported["save"]
	var result: Dictionary = Gen2SaveStore.save(save, _data)
	if not result["ok"]:
		_set_status("Save import failed.", String(result["message"]), ERROR)
		return false
	_new_game_visible = false
	_refresh()
	_set_status(
		"Save imported into slot %d." % (_selected_slot + 1),
		"The cartridge copy was %s and passed validation." % String(imported["copy"]),
		SUCCESS
	)
	return true


## Read-only state used by scene tests and screenshot drivers.
func save_screen_snapshot() -> Dictionary:
	return {
		"game_id": String(_data.id) if _data != null else "",
		"selected_slot": _selected_slot,
		"new_game": _new_game_visible,
		"status": _status_label.text if _status_label != null else "",
		"detail": _status_detail.text if _status_detail != null else "",
		"slots": _slots.duplicate(true),
	}


func _resolve_data() -> GameData:
	if GameRuntime.has_selected_game():
		return GameRuntime.selected_data()
	return GameData.open_any()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 56)
	margin.add_theme_constant_override("margin_top", 38)
	margin.add_theme_constant_override("margin_right", 56)
	margin.add_theme_constant_override("margin_bottom", 34)
	add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	margin.add_child(content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	content.add_child(header)

	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 3)
	header.add_child(heading)
	var title := Label.new()
	title.text = "SAVE DATA"
	title.add_theme_color_override("font_color", TEXT)
	title.add_theme_font_size_override("font_size", 32)
	heading.add_child(title)
	var subtitle := Label.new()
	subtitle.text = _data.title() if _data != null else "No cartridge selected"
	subtitle.add_theme_color_override("font_color", MUTED)
	subtitle.add_theme_font_size_override("font_size", 16)
	heading.add_child(subtitle)

	var back := _button("Back to cartridges", TEXT)
	back.custom_minimum_size = Vector2(190, 44)
	back.pressed.connect(_back_to_launcher)
	header.add_child(back)

	_slots_section = Label.new()
	var section: Label = _slots_section
	section.text = "SAVE SLOTS"
	section.add_theme_color_override("font_color", ACCENT)
	section.add_theme_font_size_override("font_size", 13)
	content.add_child(section)

	_slot_scroll = ScrollContainer.new()
	var slot_scroll: ScrollContainer = _slot_scroll
	slot_scroll.custom_minimum_size = Vector2(0, 154)
	slot_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(slot_scroll)
	_slots_container = HBoxContainer.new()
	_slots_container.add_theme_constant_override("separation", 16)
	_slots_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slots_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	slot_scroll.add_child(_slots_container)

	var details_panel := PanelContainer.new()
	details_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details_panel.add_theme_stylebox_override("panel", _panel_style(PANEL, BORDER, 10))
	content.add_child(details_panel)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details_panel.add_child(detail_scroll)
	_details_box = VBoxContainer.new()
	_details_box.add_theme_constant_override("separation", 10)
	_details_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_details_box)

	var status_panel := PanelContainer.new()
	status_panel.add_theme_stylebox_override("panel", _panel_style(PANEL, BORDER, 10))
	status_panel.custom_minimum_size = Vector2(0, 54)
	content.add_child(status_panel)
	var status_box := VBoxContainer.new()
	status_box.add_theme_constant_override("separation", 3)
	status_panel.add_child(status_box)
	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", TEXT)
	_status_label.add_theme_font_size_override("font_size", 16)
	status_box.add_child(_status_label)
	_status_detail = Label.new()
	_status_detail.add_theme_color_override("font_color", MUTED)
	_status_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_box.add_child(_status_detail)

	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray(["*.sav; Game Boy save file", "*; All files"])
	_file_dialog.title = "Choose an original Gold, Silver, or Crystal save"
	_file_dialog.file_selected.connect(_on_file_selected)
	add_child(_file_dialog)

	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "Replace save slot?"
	_confirm_dialog.confirmed.connect(_on_replace_confirmed)
	add_child(_confirm_dialog)

	_set_status(
		"Select a save slot.",
		"Create a new game, continue a validated save, or import an original cartridge save.",
		MUTED
	)


func _refresh() -> void:
	if _data == null:
		_set_status("No cartridge cache is ready.", "Return to the launcher and import a supported ROM.", ERROR)
		return
	_slots = Gen2SaveStore.slots_for(_data.id, _data.sha1, _data)
	if _selected_slot < 0 or _selected_slot >= _slots.size():
		_selected_slot = 0
	_slots_section.visible = not _new_game_visible
	_slot_scroll.visible = not _new_game_visible
	_refresh_slot_cards()
	_refresh_details()


func _refresh_slot_cards() -> void:
	for child: Node in _slots_container.get_children():
		child.free()
	for row: Dictionary in _slots:
		var slot: int = int(row["slot"])
		var selected: bool = slot == _selected_slot
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(250, 146)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override(
			"panel", _panel_style(PANEL_SELECTED if selected else PANEL, BORDER_SELECTED if selected else BORDER, 10)
		)
		_slots_container.add_child(card)
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 7)
		card.add_child(body)
		var title := Label.new()
		title.text = "SLOT %d" % (slot + 1)
		title.add_theme_color_override("font_color", TEXT)
		title.add_theme_font_size_override("font_size", 21)
		body.add_child(title)
		var state := Label.new()
		state.text = _slot_state(row)
		state.add_theme_color_override("font_color", _slot_state_color(row))
		state.add_theme_font_size_override("font_size", 14)
		body.add_child(state)
		var message := Label.new()
		message.text = _slot_message(row)
		message.add_theme_color_override("font_color", MUTED)
		message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		message.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_child(message)
		var select := _button("Selected" if selected else "Select slot", ACCENT if selected else TEXT)
		select.custom_minimum_size = Vector2(0, 34)
		select.disabled = selected
		select.pressed.connect(select_slot.bind(slot))
		body.add_child(select)


func _refresh_details() -> void:
	if _details_box == null:
		return
	_slots_section.visible = not _new_game_visible
	_slot_scroll.visible = not _new_game_visible
	for child: Node in _details_box.get_children():
		child.free()
	if _data == null or _slots.is_empty():
		return
	var row: Dictionary = _slots[_selected_slot]
	var heading := Label.new()
	heading.text = "SLOT %d" % (_selected_slot + 1)
	heading.add_theme_color_override("font_color", TEXT)
	heading.add_theme_font_size_override("font_size", 24)
	_details_box.add_child(heading)
	var state := Label.new()
	state.text = _slot_state(row)
	state.add_theme_color_override("font_color", _slot_state_color(row))
	_details_box.add_child(state)

	if _new_game_visible:
		_build_new_game_form()
		return

	var save: Gen2SaveData = _load_selected_save()
	if save != null:
		var player := Label.new()
		player.text = "Player: %s" % save.player_name
		player.add_theme_color_override("font_color", MUTED)
		_details_box.add_child(player)
		_add_party_summary(save)
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 10)
		_details_box.add_child(actions)
		var continue_button := _button("Continue", ACCENT)
		continue_button.pressed.connect(_continue_selected)
		actions.add_child(continue_button)
		var party_button := _button("Open party", TEXT)
		party_button.pressed.connect(_open_party)
		actions.add_child(party_button)
		var import_button := _button("Import .sav", TEXT)
		import_button.pressed.connect(_request_import)
		actions.add_child(import_button)
		var replace_button := _button("Replace", TEXT)
		replace_button.pressed.connect(_request_new_game)
		actions.add_child(replace_button)
		return

	var message := Label.new()
	message.text = _slot_message(row)
	message.add_theme_color_override("font_color", MUTED)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details_box.add_child(message)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	_details_box.add_child(actions)
	var new_button := _button("New game", ACCENT)
	new_button.pressed.connect(_request_new_game)
	actions.add_child(new_button)
	var import_button := _button("Import .sav", TEXT)
	import_button.pressed.connect(_request_import)
	actions.add_child(import_button)


func _build_new_game_form() -> void:
	var prompt := Label.new()
	prompt.text = "Choose a name and Professor Elm's starter Pokémon."
	prompt.add_theme_color_override("font_color", MUTED)
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details_box.add_child(prompt)
	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Player name"
	_name_input.max_length = Gen2SaveData.MAX_PLAYER_NAME
	_name_input.custom_minimum_size = Vector2(0, 42)
	_details_box.add_child(_labeled_control("PLAYER NAME", _name_input))
	var starter_label := Label.new()
	starter_label.text = "STARTER"
	starter_label.add_theme_color_override("font_color", ACCENT)
	starter_label.add_theme_font_size_override("font_size", 12)
	_details_box.add_child(starter_label)
	var starters := HBoxContainer.new()
	starters.add_theme_constant_override("separation", 10)
	_details_box.add_child(starters)
	for starter: int in Gen2SaveStore.STARTER_SPECIES:
		var button := _button(_species_name(starter), ACCENT if starter == _selected_starter else TEXT)
		button.custom_minimum_size = Vector2(150, 38)
		button.pressed.connect(_select_starter.bind(starter))
		starters.add_child(button)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	_details_box.add_child(actions)
	var create_button := _button("Create save", ACCENT)
	create_button.pressed.connect(_create_from_form)
	actions.add_child(create_button)
	var cancel_button := _button("Cancel", TEXT)
	cancel_button.pressed.connect(_cancel_new_game)
	actions.add_child(cancel_button)


func _add_party_summary(save: Gen2SaveData) -> void:
	var label := Label.new()
	label.text = "PARTY"
	label.add_theme_color_override("font_color", ACCENT)
	label.add_theme_font_size_override("font_size", 12)
	_details_box.add_child(label)
	for index: int in Gen2SaveData.MAX_PARTY:
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", _panel_style(Color("#102039"), BORDER, 6))
		_details_box.add_child(row)
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 2)
		row.add_child(content)
		if index >= save.party.size():
			var empty := Label.new()
			empty.text = "%d. Empty" % (index + 1)
			empty.add_theme_color_override("font_color", MUTED)
			content.add_child(empty)
			continue
		var mon: Gen2SaveMon = save.party[index]
		var battle_mon: Gen2BattleMon = Gen2SaveBattleAdapter.to_battle_mon(_data, mon)
		var name := Label.new()
		name.text = "%d. %s" % [index + 1, _display_name(mon)]
		name.add_theme_color_override("font_color", TEXT)
		content.add_child(name)
		var details := Label.new()
		details.text = "Lv.%d    HP %d/%d    %s" % [
			mon.level, mon.hp, battle_mon.max_hp(), _status_name(mon.status)
		]
		details.add_theme_color_override("font_color", MUTED)
		content.add_child(details)


func _request_new_game() -> void:
	if _slot_exists():
		_pending_replace_action = &"new_game"
		_pending_import_path = ""
		_confirm_dialog.dialog_text = "Replace slot %d with a new game?" % (_selected_slot + 1)
		_confirm_dialog.popup_centered()
		return
	open_new_game()


func _request_import() -> void:
	_file_dialog.popup_centered(Vector2i(900, 600))


func _on_file_selected(path: String) -> void:
	if _slot_exists():
		_pending_replace_action = &"import"
		_pending_import_path = path
		_confirm_dialog.dialog_text = "Replace slot %d with this cartridge save?" % (_selected_slot + 1)
		_confirm_dialog.popup_centered()
		return
	import_sav_path(path)


func _on_replace_confirmed() -> void:
	var action: StringName = _pending_replace_action
	var path: String = _pending_import_path
	_pending_replace_action = &""
	_pending_import_path = ""
	if action == &"new_game":
		open_new_game()
	elif action == &"import":
		import_sav_path(path)


func _create_from_form() -> void:
	if _name_input != null:
		create_new_game(_name_input.text, _selected_starter)


func _select_starter(species: int) -> void:
	_selected_starter = species
	_refresh_details()


func _cancel_new_game() -> void:
	_new_game_visible = false
	_refresh_details()


func _continue_selected() -> void:
	if _data == null or _load_selected_save() == null:
		return
	if not GameRuntime.select_save_slot(_data.id, _selected_slot):
		_set_status("Could not select save slot.", "The selected cartridge is not in the registry.", ERROR)
		return
	get_tree().change_scene_to_file.call_deferred("res://game/world/world_screen.tscn")


func _open_party() -> void:
	if _data == null or _load_selected_save() == null:
		return
	if not GameRuntime.select_save_slot(_data.id, _selected_slot):
		_set_status("Could not select save slot.", "The selected cartridge is not in the registry.", ERROR)
		return
	get_tree().change_scene_to_file.call_deferred("res://game/save/party_screen.tscn")


func _back_to_launcher() -> void:
	get_tree().change_scene_to_file.call_deferred("res://game/main/main.tscn")


func _load_selected_save() -> Gen2SaveData:
	if _data == null or _selected_slot < 0 or _selected_slot >= _slots.size():
		return null
	var row: Dictionary = _slots[_selected_slot]
	if not row["valid"]:
		return null
	var result: Dictionary = Gen2SaveStore.load_result(_data.id, _data.sha1, _selected_slot, _data)
	return result["save"] if result["ok"] else null


func _slot_exists() -> bool:
	return _selected_slot >= 0 and _selected_slot < _slots.size() and bool(_slots[_selected_slot]["exists"])


func _slot_state(row: Dictionary) -> String:
	if not row["exists"]:
		return "EMPTY"
	return "READY" if row["valid"] else "INCOMPATIBLE"


func _slot_message(row: Dictionary) -> String:
	if not row["exists"]:
		return "No player data in this slot."
	return "Ready to continue." if row["valid"] else String(row["message"])


func _slot_state_color(row: Dictionary) -> Color:
	if not row["exists"]:
		return ACCENT
	return SUCCESS if row["valid"] else ERROR


func _display_name(mon: Gen2SaveMon) -> String:
	if mon.nickname.is_empty():
		return _species_name(mon.species)
	return mon.nickname


func _species_name(species: int) -> String:
	if _data == null:
		return "UNKNOWN"
	return String(_data.species(species).get("name", "UNKNOWN"))


func _status_name(status: int) -> String:
	var name: StringName = Gen2Status.name_of(status)
	return "OK" if name.is_empty() else String(name).to_upper()


func _set_status(title: String, detail: String, colour: Color) -> void:
	if _status_label == null:
		return
	_status_label.text = title
	_status_label.add_theme_color_override("font_color", colour)
	_status_detail.text = detail


func _labeled_control(label_text: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var label := Label.new()
	label.text = label_text
	label.add_theme_color_override("font_color", ACCENT)
	label.add_theme_font_size_override("font_size", 12)
	box.add_child(label)
	box.add_child(control)
	return box


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
