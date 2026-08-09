class_name Gen2PartyScreen
extends Control

## Player party summary for a validated project save.

## Emitted only when embedded, mirroring Gen2BoxScreen.closed: the overworld
## start menu resumes on this rather than the screen navigating away with
## change_scene_to_file, which would tear down the running world.
signal closed(result: Dictionary)
## A chosen submenu entry this screen does not own, mirroring
## Gen2StartMenuScreen.action_chosen. Field moves need the live world, which
## belongs to the world screen, so the choice is reported rather than run here.
signal action_chosen(action: Dictionary)

const BACKGROUND: Color = Color("#09111f")
const PANEL: Color = Color("#14233a")
const BORDER: Color = Color("#2d4566")
const TEXT: Color = Color("#f4f7fb")
const MUTED: Color = Color("#9eacc0")
const ACCENT: Color = Color("#f3c969")
const SUCCESS: Color = Color("#7bd89a")
const ERROR: Color = Color("#ef8a8a")

## data/mon_menu.asm's MONMENUVALUE_* option strings, in that file's order.
const OPTION_STATS: StringName = &"stats"
const OPTION_SWITCH: StringName = &"switch"
const OPTION_ITEM: StringName = &"item"
const OPTION_CANCEL: StringName = &"cancel"
const OPTION_MOVE: StringName = &"move"
## engine/pokemon/mon_submenu.asm's NUM_MONMENU_ITEMS: a list already this long
## drops CANCEL rather than growing.
const MAX_SUBMENU_ITEMS: int = 8

var _data: GameData = null
var _data_override: GameData = null
var _save: Gen2SaveData = null
var _save_override: Gen2SaveData = null
var _embedded: bool = false
var _cards: VBoxContainer = null
var _player_label: Label = null
var _status: Label = null
var _storage_button: Button = null
var _battle_button: Button = null
## The cursor and per-mon submenu. Reachable only through handle_button(),
## which only the world screen calls, so the standalone save-screen view keeps
## its mouse-driven behavior unchanged.
var _member_cursor: int = 0
var _submenu: VBoxContainer = null
var _submenu_items: Array = []
var _submenu_cursor: int = 0
var _submenu_open: bool = false


func _ready() -> void:
	_data = _data_override if _data_override != null else _resolve_data()
	_save = _save_override if _save_override != null else _resolve_save()
	_build_ui()
	_refresh()


## Test seam for a synthetic cache and validated save. `embedded` is the
## overworld start menu's Pokemon entry: the save-screen navigation actions
## (development battle, PC storage by scene change) do not apply while a
## world is running, so they are hidden rather than left to tear it down.
func set_context(data: GameData, save: Gen2SaveData, embedded: bool = false) -> void:
	_data_override = data
	_save_override = save
	_embedded = embedded
	_data = data
	_save = save
	_member_cursor = 0
	_submenu_open = false
	_submenu_items = []
	_submenu_cursor = 0
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


## engine/pokemon/mon_submenu.asm's GetMonSubmenuItems for one party member.
##
## An egg gets three entries and no moves. Otherwise the four move slots are
## walked in the mon's own slot order, appending every move that appears in
## MonMenuOptions' field-move rows, then the fixed options follow. Only entries
## this project acts on are marked available; the rest keep their source
## position rather than being omitted, the same way Gen2WorldStartMenu carries
## its unimplemented entries.
##
## The MAIL branch is not reproduced: ItemIsMail tests the held item against
## data/items/mail_items.asm, and this project has no mail, so ITEM is always
## the entry in that position.
static func submenu_items_for(data: GameData, mon: Gen2SaveMon) -> Array:
	var items: Array = []
	if mon == null:
		return items
	# The source compares wCurPartySpecies against EGG ($fd); this save model
	# carries the same fact as Gen2SaveMon.is_egg beside a real species.
	if mon.is_egg:
		items.append(_option_entry(OPTION_STATS, "STATS"))
		items.append(_option_entry(OPTION_SWITCH, "SWITCH"))
		items.append(_option_entry(OPTION_CANCEL, "CANCEL"))
		return items
	for move: int in mon.moves:
		if move == 0 or not Gen2WorldFieldMove.is_field_move(move):
			continue
		items.append({
			"kind": &"field_move",
			"move": move,
			"label": String(data.move(move).get("name", "MOVE")) if data != null else "MOVE",
			"available": true,
		})
	items.append(_option_entry(OPTION_STATS, "STATS"))
	items.append(_option_entry(OPTION_SWITCH, "SWITCH"))
	items.append(_option_entry(OPTION_MOVE, "MOVE"))
	items.append(_option_entry(OPTION_ITEM, "ITEM"))
	if items.size() < MAX_SUBMENU_ITEMS:
		items.append(_option_entry(OPTION_CANCEL, "CANCEL"))
	return items


static func _option_entry(option: StringName, label: String) -> Dictionary:
	return {"kind": &"option", "option": option, "label": label, "available": false}


func _party_size() -> int:
	return _save.party.size() if _save != null else 0


## Button driver for the embedded overworld view, mirroring
## Gen2StartMenuScreen.handle_button. Returns whether the button was used.
func handle_button(button: int) -> bool:
	if _party_size() == 0:
		if button == Gen2Button.B:
			close_embedded()
			return true
		return false
	match button:
		Gen2Button.UP:
			_move_cursor(-1)
			return true
		Gen2Button.DOWN:
			_move_cursor(1)
			return true
		Gen2Button.A:
			_confirm()
			return true
		Gen2Button.B:
			_cancel()
			return true
	return false


func _move_cursor(delta: int) -> void:
	if _submenu_open:
		if _submenu_items.is_empty():
			return
		_submenu_cursor = wrapi(_submenu_cursor + delta, 0, _submenu_items.size())
	else:
		_member_cursor = wrapi(_member_cursor + delta, 0, _party_size())
	_refresh()


func _confirm() -> void:
	if not _submenu_open:
		_open_submenu()
		return
	if _submenu_cursor < 0 or _submenu_cursor >= _submenu_items.size():
		return
	var entry: Dictionary = _submenu_items[_submenu_cursor]
	if StringName(entry.get("option", &"")) == OPTION_CANCEL:
		_close_submenu()
		return
	if not bool(entry.get("available", false)):
		_status.text = "%s is not available yet." % String(entry.get("label", ""))
		_status.add_theme_color_override("font_color", MUTED)
		return
	if StringName(entry.get("kind", &"")) != &"field_move":
		return
	action_chosen.emit({
		"kind": &"field_move",
		"move": int(entry.get("move", 0)),
		"slot": _member_cursor,
		"name": _display_name(_save.party[_member_cursor]),
	})


func _cancel() -> void:
	if _submenu_open:
		_close_submenu()
		return
	close_embedded()


func _open_submenu() -> void:
	if _member_cursor < 0 or _member_cursor >= _party_size():
		return
	_submenu_items = submenu_items_for(_data, _save.party[_member_cursor])
	_submenu_cursor = 0
	_submenu_open = not _submenu_items.is_empty()
	_refresh()


func _close_submenu() -> void:
	_submenu_open = false
	_submenu_items = []
	_submenu_cursor = 0
	_refresh()


## Test and host seam: the submenu as the screen currently shows it.
func submenu_snapshot() -> Dictionary:
	return {
		"open": _submenu_open,
		"cursor": _submenu_cursor,
		"member": _member_cursor,
		"items": _submenu_items.duplicate(true),
	}


func _render_submenu() -> void:
	if _submenu == null:
		return
	for child: Node in _submenu.get_children():
		child.queue_free()
	_submenu.visible = _submenu_open
	if not _submenu_open:
		return
	for index: int in _submenu_items.size():
		var entry: Dictionary = _submenu_items[index]
		var label := Label.new()
		var text: String = String(entry.get("label", ""))
		if not bool(entry.get("available", false)) \
			and StringName(entry.get("option", &"")) != OPTION_CANCEL:
			text = "%s (unavailable)" % text
		label.text = ("> " if index == _submenu_cursor else "  ") + text
		label.add_theme_color_override("font_color", ACCENT if index == _submenu_cursor else TEXT)
		label.add_theme_font_size_override("font_size", 18)
		_submenu.add_child(label)


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
	var back := _button("Close" if _embedded else "Back to save slots", TEXT)
	back.custom_minimum_size = Vector2(190, 44)
	back.pressed.connect(_back)
	_storage_button = _button("Open PC storage", ACCENT)
	_storage_button.custom_minimum_size = Vector2(170, 44)
	_storage_button.pressed.connect(_open_storage)
	_storage_button.visible = not _embedded
	header.add_child(_storage_button)
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

	_submenu = VBoxContainer.new()
	_submenu.add_theme_constant_override("separation", 4)
	_submenu.visible = false
	content.add_child(_submenu)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	content.add_child(footer)
	_battle_button = _button("Start development battle", ACCENT)
	_battle_button.pressed.connect(_start_battle)
	_battle_button.visible = not _embedded
	footer.add_child(_battle_button)
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
	_render_submenu()
	_status.text = "Slot %d" % (_save.slot + 1)
	_status.add_theme_color_override("font_color", SUCCESS)


func _member_card(index: int) -> PanelContainer:
	var card := PanelContainer.new()
	var selected: bool = index == _member_cursor and index < _party_size()
	card.add_theme_stylebox_override(
		"panel", _panel_style(PANEL, ACCENT if selected else BORDER, 8)
	)
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
	if _embedded:
		close_embedded()
		return
	get_tree().change_scene_to_file.call_deferred("res://game/save/save_screen.tscn")


func close_embedded() -> void:
	if not _embedded:
		return
	closed.emit({"ok": true})


func _open_storage() -> void:
	if _data == null or _save == null:
		_status.text = "No validated save selected."
		_status.add_theme_color_override("font_color", ERROR)
		return
	if not GameRuntime.select_save_slot(_data.id, _save.slot):
		_status.text = "The selected cartridge is not in the registry."
		_status.add_theme_color_override("font_color", ERROR)
		return
	get_tree().change_scene_to_file.call_deferred("res://game/save/box_screen.tscn")


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
