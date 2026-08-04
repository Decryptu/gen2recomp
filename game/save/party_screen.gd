class_name Gen2PartyScreen
extends Control

## Player party summary for a validated project save.

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
var _cards: VBoxContainer = null
var _player_label: Label = null
var _status: Label = null


func _ready() -> void:
	_data = _data_override if _data_override != null else _resolve_data()
	_save = _save_override if _save_override != null else _resolve_save()
	_build_ui()
	_refresh()


## Test seam for a synthetic cache and validated save.
func set_context(data: GameData, save: Gen2SaveData) -> void:
	_data_override = data
	_save_override = save
	_data = data
	_save = save
	if is_inside_tree() and _cards != null:
		_refresh()


func party_snapshot() -> Dictionary:
	var members: Array = []
	if _data != null and _save != null:
		for index: int in Gen2SaveData.MAX_PARTY:
			if index >= _save.party.size():
				members.append({"empty": true, "index": index})
				continue
			members.append(_member_snapshot(index, _save.party[index]))
	return {
		"player_name": _save.player_name if _save != null else "",
		"slot": _save.slot if _save != null else -1,
		"members": members,
	}


func _resolve_data() -> GameData:
	if GameRuntime.has_selected_game():
		return GameRuntime.selected_data()
	return GameData.open_any()


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
	margin.add_theme_constant_override("margin_left", 64)
	margin.add_theme_constant_override("margin_top", 42)
	margin.add_theme_constant_override("margin_right", 64)
	margin.add_theme_constant_override("margin_bottom", 42)
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
	title.text = "PARTY"
	title.add_theme_color_override("font_color", TEXT)
	title.add_theme_font_size_override("font_size", 32)
	heading.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Player party and persistent condition"
	subtitle.add_theme_color_override("font_color", MUTED)
	heading.add_child(subtitle)
	var back := _button("Back to save slots", TEXT)
	back.custom_minimum_size = Vector2(190, 44)
	back.pressed.connect(_back)
	header.add_child(back)

	_player_label = Label.new()
	_player_label.add_theme_color_override("font_color", ACCENT)
	_player_label.add_theme_font_size_override("font_size", 18)
	content.add_child(_player_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation", 9)
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_cards)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	content.add_child(footer)
	var battle := _button("Start development battle", ACCENT)
	battle.pressed.connect(_start_battle)
	footer.add_child(battle)
	_status = Label.new()
	_status.add_theme_color_override("font_color", MUTED)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(_status)


func _refresh() -> void:
	if _cards == null:
		return
	for child: Node in _cards.get_children():
		child.free()
	if _player_label != null:
		_player_label.text = "Player: %s" % (_save.player_name if _save != null else "Unavailable")
	if _data == null or _save == null:
		_status.text = "No validated save selected."
		_status.add_theme_color_override("font_color", ERROR)
		return
	for index: int in Gen2SaveData.MAX_PARTY:
		_cards.add_child(_member_card(index))
	_status.text = "Slot %d" % (_save.slot + 1)
	_status.add_theme_color_override("font_color", SUCCESS)


func _member_card(index: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style(PANEL, BORDER, 8))
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	card.add_child(content)
	var number := Label.new()
	number.text = "%d" % (index + 1)
	number.custom_minimum_size = Vector2(28, 0)
	number.add_theme_color_override("font_color", ACCENT)
	number.add_theme_font_size_override("font_size", 20)
	content.add_child(number)
	if _save == null or index >= _save.party.size():
		var empty := Label.new()
		empty.text = "Empty"
		empty.add_theme_color_override("font_color", MUTED)
		content.add_child(empty)
		return card
	var mon: Gen2SaveMon = _save.party[index]
	var summary := VBoxContainer.new()
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_theme_constant_override("separation", 3)
	content.add_child(summary)
	var name := Label.new()
	name.text = _display_name(mon)
	name.add_theme_color_override("font_color", TEXT)
	name.add_theme_font_size_override("font_size", 20)
	summary.add_child(name)
	var details := Label.new()
	details.text = "%s    Level %d    HP %d/%d" % [
		_species_name(mon.species), mon.level, mon.hp, _max_hp(mon)
	]
	details.add_theme_color_override("font_color", MUTED)
	summary.add_child(details)
	var condition := Label.new()
	condition.text = "Status: %s" % _status_name(mon.status)
	condition.add_theme_color_override("font_color", _status_color(mon.status))
	summary.add_child(condition)
	return card


func _member_snapshot(index: int, mon: Gen2SaveMon) -> Dictionary:
	return {
		"empty": false,
		"index": index,
		"name": _display_name(mon),
		"species": mon.species,
		"level": mon.level,
		"hp": mon.hp,
		"max_hp": _max_hp(mon),
		"status": _status_name(mon.status),
	}


func _max_hp(mon: Gen2SaveMon) -> int:
	var battle_mon: Gen2BattleMon = Gen2SaveBattleAdapter.to_battle_mon(_data, mon)
	return battle_mon.max_hp() if battle_mon != null else 0


func _display_name(mon: Gen2SaveMon) -> String:
	return mon.nickname if not mon.nickname.is_empty() else _species_name(mon.species)


func _species_name(species: int) -> String:
	return String(_data.species(species).get("name", "UNKNOWN")) if _data != null else "UNKNOWN"


func _status_name(status: int) -> String:
	var name: StringName = Gen2Status.name_of(status)
	return "OK" if name.is_empty() else String(name).to_upper()


func _status_color(status: int) -> Color:
	return SUCCESS if Gen2Status.name_of(status).is_empty() else ACCENT


func _start_battle() -> void:
	if _data == null or _save == null:
		return
	if not GameRuntime.select_save_slot(_data.id, _save.slot):
		_status.text = "The selected cartridge is not in the registry."
		_status.add_theme_color_override("font_color", ERROR)
		return
	get_tree().change_scene_to_file.call_deferred("res://game/battle/battle_screen.tscn")


func _back() -> void:
	get_tree().change_scene_to_file.call_deferred("res://game/save/save_screen.tscn")


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
