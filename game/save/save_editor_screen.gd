extends Control

## The save editor. Presentation only: every rule lives in [Gen2SaveEditor],
## which is what keeps an edit from producing a slot that will not load.
##
## Deliberately built from stock controls with no styling. The look is a later
## pass, and a plain screen is the one that is cheapest to replace.

## Kept in the order the tabs are drawn in, so a snapshot names a tab rather
## than an index a reader has to count.
const TABS: Array[StringName] = [&"party", &"boxes", &"items", &"events", &"map", &"dex"]

var _editor: Gen2SaveEditor = null
var _tabs: TabContainer = null
var _status: Label = null
var _validity: Label = null
var _party_list: ItemList = null
var _party_form: VBoxContainer = null
var _box_picker: OptionButton = null
var _box_list: ItemList = null
var _item_list: ItemList = null
var _money_field: SpinBox = null
var _coins_field: SpinBox = null
var _flag_field: SpinBox = null
var _badge_boxes: Array[CheckBox] = []
var _map_fields: Dictionary = {}
var _dex_field: SpinBox = null
var _dex_list: ItemList = null
var _selected_party: int = -1
var _selected_box: int = 0


func _ready() -> void:
	_build_ui()
	if _editor == null:
		_open_selected_slot()
	_refresh()
	Gen2FocusGuard.attach(self)


## Opens an explicit save. Tests and tools use this instead of relying on
## whatever the runtime happens to have selected.
func set_editor(editor: Gen2SaveEditor) -> void:
	_editor = editor
	if is_inside_tree():
		_refresh()


func _open_selected_slot() -> void:
	var data: GameData = GameData.open(GameRuntime.selected_game_id)
	if data == null or GameRuntime.selected_save_slot < 0:
		return
	var result: Dictionary = Gen2SaveStore.load_result(
		data.id, data.sha1, GameRuntime.selected_save_slot, data
	)
	if bool(result.get("ok", false)):
		_editor = Gen2SaveEditor.open(result["save"], data)


## A read-only view for tests, in the shape the other screens expose.
func editor_snapshot() -> Dictionary:
	if _editor == null:
		return {"open": false, "tab": &"", "valid": false}
	var validation: Dictionary = _editor.validate()
	var party: Array = []
	for mon: Gen2SaveMon in _editor.save.party:
		party.append({"species": mon.species, "level": mon.level, "hp": mon.hp})
	return {
		"open": true,
		"tab": TABS[_tabs.current_tab] if _tabs != null else &"",
		"valid": bool(validation["ok"]),
		"message": String(validation["message"]),
		"dirty": _editor.is_dirty(),
		"player_name": _editor.save.player_name,
		"label": _editor.save.label,
		"party": party,
		"selected_party": _selected_party,
		"selected_box": _selected_box,
		"has_world": _editor.has_world(),
	}


func select_party_member(index: int) -> bool:
	if _editor == null or index < 0 or index >= _editor.save.party.size():
		return false
	_selected_party = index
	_refresh_party_form()
	return true


func select_tab(tab: StringName) -> bool:
	var index: int = TABS.find(tab)
	if index < 0 or _tabs == null:
		return false
	_tabs.current_tab = index
	return true


func save_now() -> bool:
	if _editor == null:
		return false
	var result: Dictionary = _editor.commit()
	_set_status(String(result["message"]) if not result["ok"] else "Saved.")
	if result["ok"]:
		# The slot on disk changed under whatever the runtime is holding.
		GameRuntime.reload_selected_save()
	_refresh()
	return bool(result["ok"])


func reload_now() -> bool:
	if _editor == null:
		return false
	var result: Dictionary = Gen2SaveStore.load_result(
		_editor.save.game_id, _editor.save.rom_sha1, _editor.save.slot, _editor.data
	)
	if not bool(result.get("ok", false)):
		_set_status(String(result.get("message", "the slot could not be reloaded")))
		return false
	_editor = Gen2SaveEditor.open(result["save"], _editor.data)
	_selected_party = -1
	_set_status("Reloaded from disk.")
	_refresh()
	return true


# --- Layout -----------------------------------------------------------------


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 8)
	add_child(margin)

	var root := VBoxContainer.new()
	margin.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "Save editor"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_validity = Label.new()
	header.add_child(_validity)
	header.add_child(_action("Reload", reload_now))
	header.add_child(_action("Save", save_now))
	header.add_child(_action("Close", _close))

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)
	_tabs.add_child(_build_party_tab())
	_tabs.add_child(_build_boxes_tab())
	_tabs.add_child(_build_items_tab())
	_tabs.add_child(_build_events_tab())
	_tabs.add_child(_build_map_tab())
	_tabs.add_child(_build_dex_tab())
	for index: int in TABS.size():
		_tabs.set_tab_title(index, String(TABS[index]).capitalize())

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)


func _build_party_tab() -> Control:
	var page := HBoxContainer.new()
	page.name = "Party"

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(260, 0)
	page.add_child(left)
	_party_list = ItemList.new()
	_party_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_party_list.item_selected.connect(func(index: int) -> void: select_party_member(index))
	left.add_child(_party_list)

	var add_row := HBoxContainer.new()
	left.add_child(add_row)
	var species_field := SpinBox.new()
	species_field.max_value = 255
	species_field.value = 1
	add_row.add_child(species_field)
	var level_field := SpinBox.new()
	level_field.min_value = 1
	level_field.max_value = Gen2Experience.MAX_LEVEL
	level_field.value = 5
	add_row.add_child(level_field)
	add_row.add_child(_action("Add", func() -> void:
		_apply(_editor.add_party_member(int(species_field.value), int(level_field.value)))
	))
	add_row.add_child(_action("Remove", func() -> void:
		_apply(_editor.remove_party_member(_selected_party))
		_selected_party = -1
	))

	_party_form = VBoxContainer.new()
	_party_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(_party_form)
	return page


func _build_boxes_tab() -> Control:
	var page := VBoxContainer.new()
	page.name = "Boxes"
	var row := HBoxContainer.new()
	page.add_child(row)
	_box_picker = OptionButton.new()
	for index: int in Gen2SaveData.BOX_COUNT:
		_box_picker.add_item("Box %d" % (index + 1), index)
	_box_picker.item_selected.connect(func(index: int) -> void:
		_selected_box = index
		_refresh_boxes()
	)
	row.add_child(_box_picker)

	var species_field := SpinBox.new()
	species_field.max_value = 255
	species_field.value = 1
	row.add_child(species_field)
	var level_field := SpinBox.new()
	level_field.min_value = 1
	level_field.max_value = Gen2Experience.MAX_LEVEL
	level_field.value = 5
	row.add_child(level_field)
	row.add_child(_action("Add", func() -> void:
		_apply(_editor.add_box_member(
			_selected_box, int(species_field.value), int(level_field.value)
		))
	))
	row.add_child(_action("Remove", func() -> void:
		_apply(_editor.remove_box_member(_selected_box, _box_list.get_selected_items()[0] \
			if not _box_list.get_selected_items().is_empty() else -1))
	))

	_box_list = ItemList.new()
	_box_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_box_list)
	return page


func _build_items_tab() -> Control:
	var page := VBoxContainer.new()
	page.name = "Items"

	var money_row := HBoxContainer.new()
	page.add_child(money_row)
	money_row.add_child(_label("Money"))
	_money_field = SpinBox.new()
	_money_field.max_value = Gen2WorldInventory.MAX_MONEY
	_money_field.value_changed.connect(func(value: float) -> void:
		_apply(_editor.set_money(0, int(value)), false)
	)
	money_row.add_child(_money_field)
	money_row.add_child(_label("Coins"))
	_coins_field = SpinBox.new()
	_coins_field.max_value = Gen2WorldInventory.MAX_COINS
	_coins_field.value_changed.connect(func(value: float) -> void:
		_apply(_editor.set_coins(int(value)), false)
	)
	money_row.add_child(_coins_field)

	var item_row := HBoxContainer.new()
	page.add_child(item_row)
	var item_field := SpinBox.new()
	item_field.max_value = 255
	item_field.value = 1
	item_row.add_child(item_field)
	var quantity_field := SpinBox.new()
	quantity_field.max_value = 99
	quantity_field.value = 1
	item_row.add_child(quantity_field)
	item_row.add_child(_action("Set", func() -> void:
		_apply(_editor.set_item_quantity(int(item_field.value), int(quantity_field.value)))
	))

	_item_list = ItemList.new()
	_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_item_list)
	return page


func _build_events_tab() -> Control:
	var page := VBoxContainer.new()
	page.name = "Events"

	var badges := HFlowContainer.new()
	page.add_child(badges)
	_badge_boxes = []
	for index: int in Gen2WorldState.BADGE_ENGINE_FLAGS.size():
		var box := CheckBox.new()
		box.text = "Badge %d" % (index + 1)
		box.toggled.connect(func(pressed: bool) -> void: _set_badge(index, pressed))
		badges.add_child(box)
		_badge_boxes.append(box)

	var flag_row := HBoxContainer.new()
	page.add_child(flag_row)
	flag_row.add_child(_label("Event flag"))
	_flag_field = SpinBox.new()
	_flag_field.max_value = 4095
	flag_row.add_child(_flag_field)
	flag_row.add_child(_action("Set", func() -> void:
		_apply(_editor.set_event_flag(int(_flag_field.value), true))
	))
	flag_row.add_child(_action("Clear", func() -> void:
		_apply(_editor.set_event_flag(int(_flag_field.value), false))
	))
	return page


func _build_map_tab() -> Control:
	var page := VBoxContainer.new()
	page.name = "Map"
	for field: String in ["group", "number", "x", "y"]:
		var row := HBoxContainer.new()
		page.add_child(row)
		row.add_child(_label(field.capitalize()))
		var spin := SpinBox.new()
		spin.max_value = 999
		row.add_child(spin)
		_map_fields[field] = spin
	page.add_child(_action("Move player", _apply_position))

	for field: String in ["day", "hour", "minute"]:
		var row := HBoxContainer.new()
		page.add_child(row)
		row.add_child(_label(field.capitalize()))
		var spin := SpinBox.new()
		spin.max_value = 59
		row.add_child(spin)
		_map_fields[field] = spin
	page.add_child(_action("Set clock", func() -> void:
		_apply(_editor.set_clock(
			int(_map_fields["day"].value),
			int(_map_fields["hour"].value),
			int(_map_fields["minute"].value),
		))
	))
	return page


func _build_dex_tab() -> Control:
	var page := VBoxContainer.new()
	page.name = "Dex"
	var row := HBoxContainer.new()
	page.add_child(row)
	row.add_child(_label("Species"))
	_dex_field = SpinBox.new()
	_dex_field.min_value = 1
	_dex_field.max_value = 255
	_dex_field.value = 1
	row.add_child(_dex_field)
	row.add_child(_action("Seen", func() -> void:
		_apply(_editor.set_seen_species(int(_dex_field.value), true))
	))
	row.add_child(_action("Clear", func() -> void:
		_apply(_editor.set_seen_species(int(_dex_field.value), false))
	))
	_dex_list = ItemList.new()
	_dex_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_dex_list)
	return page


# --- Refresh ----------------------------------------------------------------


func _refresh() -> void:
	if _editor == null:
		_set_status("No save is open.")
		return
	_refresh_validity()
	_refresh_party()
	_refresh_party_form()
	_refresh_boxes()
	_refresh_items()
	_refresh_events()
	_refresh_map()
	_refresh_dex()


func _refresh_validity() -> void:
	var validation: Dictionary = _editor.validate()
	_validity.text = "Validates clean" if validation["ok"] else String(validation["message"])


func _refresh_party() -> void:
	_party_list.clear()
	for mon: Gen2SaveMon in _editor.save.party:
		_party_list.add_item("%s  Lv%d  %d/%d HP" % [
			_species_name(mon.species), mon.level, mon.hp, _editor.max_hp_for(mon),
		])
	if _selected_party >= 0 and _selected_party < _party_list.item_count:
		_party_list.select(_selected_party)


## The per-Pokemon form is rebuilt rather than updated, because every control
## in it belongs to whichever member is selected and none of them outlive that.
func _refresh_party_form() -> void:
	if _party_form == null:
		return
	Gen2LauncherUI.clear(_party_form)
	if _selected_party < 0 or _selected_party >= _editor.save.party.size():
		return
	var mon: Gen2SaveMon = _editor.save.party[_selected_party]

	_party_form.add_child(_field("Species", mon.species, 1, 255, func(value: int) -> void:
		_apply(_editor.set_species(mon, value))
	))
	_party_form.add_child(_field("Level", mon.level, 1, Gen2Experience.MAX_LEVEL,
		func(value: int) -> void: _apply(_editor.set_level(mon, value))
	))
	_party_form.add_child(_field("HP", mon.hp, 0, _editor.max_hp_for(mon),
		func(value: int) -> void: _apply(_editor.set_hp(mon, value))
	))
	_party_form.add_child(_field("Happiness", mon.happiness, 0, 255,
		func(value: int) -> void: _apply(_editor.set_happiness(mon, value))
	))
	_party_form.add_child(_field("Held item", mon.item, 0, 255,
		func(value: int) -> void: _apply(_editor.set_held_item(mon, value))
	))
	for slot: int in Gen2SaveMon.MAX_MOVES:
		_party_form.add_child(_field(
			"Move %d" % (slot + 1), int(mon.moves[slot]), 0, 255,
			func(value: int) -> void: _apply(_editor.set_move(mon, slot, value))
		))
	var dv_row := HBoxContainer.new()
	dv_row.add_child(_label("DVs"))
	var dv_fields: Array[SpinBox] = []
	for dv: int in [
		Gen2Stats.attack_dv(mon.dvs), Gen2Stats.defense_dv(mon.dvs),
		Gen2Stats.speed_dv(mon.dvs), Gen2Stats.special_dv(mon.dvs),
	]:
		var spin := SpinBox.new()
		spin.max_value = Gen2Stats.MAX_DV
		spin.value = dv
		dv_row.add_child(spin)
		dv_fields.append(spin)
	dv_row.add_child(_action("Apply", func() -> void:
		_apply(_editor.set_dvs(
			mon, int(dv_fields[0].value), int(dv_fields[1].value),
			int(dv_fields[2].value), int(dv_fields[3].value),
		))
	))
	_party_form.add_child(dv_row)


func _refresh_boxes() -> void:
	if _box_list == null:
		return
	_box_list.clear()
	var box: Gen2SaveBox = _editor.box(_selected_box)
	if box == null:
		return
	for slot: int in box.slots.size():
		var mon: Gen2SaveMon = box.slots[slot]
		_box_list.add_item("%d. %s" % [
			slot + 1,
			"empty" if mon == null else "%s Lv%d" % [_species_name(mon.species), mon.level],
		])


func _refresh_items() -> void:
	if _item_list == null:
		return
	_item_list.clear()
	var state: Gen2WorldState = _editor.save.world.world_state if _editor.has_world() else null
	if state == null:
		_item_list.add_item("This save has no world state.")
		_money_field.editable = false
		_coins_field.editable = false
		return
	_money_field.set_value_no_signal(state.money(0))
	_coins_field.set_value_no_signal(state.coins())
	for item: Variant in state.items():
		_item_list.add_item("%s x%d" % [
			_item_name(int(item)), state.item_quantity(int(item)),
		])


func _refresh_events() -> void:
	var flags: Array[int] = _editor.badge_flags()
	var state: Gen2WorldState = _editor.save.world.world_state if _editor.has_world() else null
	for index: int in _badge_boxes.size():
		var box: CheckBox = _badge_boxes[index]
		box.disabled = state == null or index >= flags.size()
		box.set_pressed_no_signal(
			state != null and index < flags.size() and state.is_engine_flag_active(flags[index])
		)


func _refresh_map() -> void:
	if not _editor.has_world():
		return
	var world: Gen2WorldSnapshot = _editor.save.world
	_map_fields["group"].set_value_no_signal(world.map_id.x)
	_map_fields["number"].set_value_no_signal(world.map_id.y)
	_map_fields["x"].set_value_no_signal(world.player_cell.x)
	_map_fields["y"].set_value_no_signal(world.player_cell.y)
	_map_fields["day"].set_value_no_signal(world.world_day)
	_map_fields["hour"].set_value_no_signal(world.world_hour)
	_map_fields["minute"].set_value_no_signal(world.world_minute)


func _refresh_dex() -> void:
	if _dex_list == null:
		return
	_dex_list.clear()
	if not _editor.has_world():
		_dex_list.add_item("This save has no world state.")
		return
	var seen: Dictionary = _editor.save.world.world_state.seen_species()
	var numbers: Array = seen.keys()
	numbers.sort()
	for species: Variant in numbers:
		_dex_list.add_item("%d %s" % [int(species), _species_name(int(species))])


# --- Helpers ----------------------------------------------------------------


func _set_badge(index: int, pressed: bool) -> void:
	var flags: Array[int] = _editor.badge_flags()
	if index >= flags.size():
		return
	_apply(_editor.set_engine_flag(flags[index], pressed))


func _apply_position() -> void:
	_apply(_editor.set_player_position(
		Vector2i(int(_map_fields["group"].value), int(_map_fields["number"].value)),
		Vector2i(int(_map_fields["x"].value), int(_map_fields["y"].value)),
	))


## A refused edit reports why and leaves the controls showing what is actually
## stored, which is why this refreshes on failure as well as success.
func _apply(result: Dictionary, refresh: bool = true) -> void:
	if _editor == null:
		return
	_set_status("" if bool(result["ok"]) else String(result["message"]))
	if refresh:
		_refresh()
	else:
		_refresh_validity()


func _close() -> void:
	get_tree().change_scene_to_file.call_deferred("res://game/save/save_screen.tscn")


func _species_name(species: int) -> String:
	var row: Dictionary = _editor.data.species(species)
	return String(row.get("name", "?")) if not row.is_empty() else "unknown %d" % species


func _item_name(item: int) -> String:
	var row: Dictionary = _editor.data.item(item)
	return String(row.get("name", "?")) if not row.is_empty() else "unknown %d" % item


func _set_status(message: String) -> void:
	if _status != null:
		_status.text = message


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _action(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(handler)
	return button


func _field(text: String, value: int, minimum: int, maximum: int, handler: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(_label(text))
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.value = value
	spin.value_changed.connect(func(changed: float) -> void: handler.call(int(changed)))
	row.add_child(spin)
	return row
