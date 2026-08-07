class_name Gen2StartMenuScreen
extends Control

## The overworld pause menu (engine/menus/start_menu.asm), presented as a
## window-resolution Control panel consistent with the mart, phone and PC
## storage overlays rather than the hardware `menu_coords` box.
##
## Pokemon and Pokegear are screens the world already owns (Gen2PartyScreen, the
## phone list on Gen2WorldServiceScreen), so this only reports the choice through
## [signal action_chosen]. Pack and Save live here as internal modes, the way
## Gen2WorldServiceScreen owns a mart mode beside its menu mode.

## Emitted for an available entry this screen does not own itself
## (Pokemon, Pokegear); the caller opens the matching screen.
signal action_chosen(kind: StringName)
## Emitted on Exit or cancel from the top-level list.
signal closed

enum Mode { LIST, PACK, SAVE_CONFIRM }

const PANEL: Color = Color("#14233a")
const BORDER: Color = Color("#4f6f9e")
const SCRIM: Color = Color(0.02, 0.04, 0.08, 0.78)
const TEXT: Color = Color("#f4f7fb")
const MUTED: Color = Color("#9eacc0")
const ACCENT: Color = Color("#f3c969")
const SUCCESS: Color = Color("#7bd89a")
const ERROR: Color = Color("#ef8a8a")

var _world: Gen2WorldAPI = null
var _data: GameData = null
var _save_action: Callable = Callable()
var _mode: Mode = Mode.LIST
var _menu: Gen2WorldStartMenu = null

var _pack_pockets: Array = []
var _pack_pocket_index: int = 0
var _pack_cursor: int = 0

var _save_cursor: int = 0
var _save_result_shown: bool = false

var _title: Label = null
var _summary: Label = null
var _options: VBoxContainer = null
var _status: Label = null
var _footer: Label = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	if _menu != null:
		_open_list_mode()


## `save_action` is called with no arguments and must return a Dictionary
## shaped like Gen2WorldScreen.persist_world_snapshot()'s result (an "ok" key,
## with "reason" on failure). Kept as a Callable so this screen does not need
## to know how a snapshot is written or where saves live.
##
## Mirrors Gen2BoxScreen.set_context(): open() may be called before or after this
## node enters the tree, so building the option list defers to _ready() until
## _title/_options exist, and runs immediately here otherwise.
func open(world: Gen2WorldAPI, data: GameData, save_action: Callable, previous_cursor: int = 0) -> bool:
	_world = world
	_data = data
	_save_action = save_action
	if _world == null or _data == null:
		return false
	_menu = Gen2WorldStartMenu.from_world(_world, previous_cursor)
	if is_inside_tree() and _options != null:
		_open_list_mode()
	return true


## The list model's cursor, so a caller can carry it into the next open() the
## way the source's wBattleMenuCursorPosition survives a reopen.
func cursor() -> int:
	return _menu.cursor if _menu != null else 0


func handle_key(keycode: int) -> bool:
	match keycode:
		KEY_UP, KEY_W:
			_move(Vector2i.UP)
			return true
		KEY_DOWN, KEY_S:
			_move(Vector2i.DOWN)
			return true
		KEY_LEFT, KEY_A:
			_move(Vector2i.LEFT)
			return true
		KEY_RIGHT, KEY_D:
			_move(Vector2i.RIGHT)
			return true
		KEY_SPACE, KEY_ENTER, KEY_Z:
			_confirm()
			return true
		KEY_ESCAPE, KEY_X, KEY_B:
			_cancel()
			return true
	return false


func _move(direction: Vector2i) -> void:
	match _mode:
		Mode.LIST:
			## The source's .MenuData omits STATICMENU_ENABLE_LEFT_RIGHT, so
			## only vertical input moves the top-level list.
			if direction.x == 0 and _menu != null and _menu.move(direction.y):
				_render_list()
		Mode.PACK:
			if direction.x != 0:
				_cycle_pocket(direction.x)
			elif direction.y != 0:
				_move_pack_cursor(direction.y)
		Mode.SAVE_CONFIRM:
			if not _save_result_shown and (direction.x != 0 or direction.y != 0):
				_save_cursor = 1 - _save_cursor
				_render_save_confirm()


func _confirm() -> void:
	match _mode:
		Mode.LIST:
			_confirm_list()
		Mode.PACK:
			if not _current_pocket_items().is_empty():
				_status.text = "Items cannot be used from the Pack yet."
				_status.add_theme_color_override("font_color", MUTED)
		Mode.SAVE_CONFIRM:
			_confirm_save()


func _cancel() -> void:
	match _mode:
		Mode.LIST:
			closed.emit()
		Mode.PACK:
			_open_list_mode()
		Mode.SAVE_CONFIRM:
			_open_list_mode()


func _confirm_list() -> void:
	if _menu == null or _menu.size() == 0:
		return
	if not _menu.selected_available():
		_status.text = "%s is not available yet." % String(_menu.selected_item().get("label", ""))
		_status.add_theme_color_override("font_color", MUTED)
		return
	match _menu.selected_kind():
		Gen2WorldStartMenu.ITEM_PACK:
			_open_pack_mode()
		Gen2WorldStartMenu.ITEM_SAVE:
			_open_save_confirm_mode()
		Gen2WorldStartMenu.ITEM_EXIT:
			closed.emit()
		Gen2WorldStartMenu.ITEM_POKEMON, Gen2WorldStartMenu.ITEM_POKEGEAR:
			action_chosen.emit(_menu.selected_kind())


func _open_list_mode() -> void:
	_mode = Mode.LIST
	_title.text = "MENU"
	_summary.text = ""
	_status.text = ""
	_footer.text = "Arrows: move    Space/Enter: choose    Esc: close"
	_render_list()


func _render_list() -> void:
	if _menu == null:
		return
	_render_options(_menu.items(), _menu.cursor, func(entry: Dictionary) -> String:
		var label: String = String(entry.get("label", ""))
		return label if bool(entry.get("available", false)) else "%s (unavailable)" % label
	)


func _open_pack_mode() -> void:
	_mode = Mode.PACK
	_pack_pockets = Gen2WorldPack.build(_data, _world.state) if _world != null else []
	_pack_pocket_index = 0
	_pack_cursor = 0
	_status.text = ""
	_footer.text = "Left/Right: pocket    Up/Down: move    Esc: back"
	_render_pack()


func _current_pocket() -> Dictionary:
	if _pack_pockets.is_empty():
		return {}
	return _pack_pockets[_pack_pocket_index]


func _current_pocket_items() -> Array:
	return _current_pocket().get("items", [])


func _cycle_pocket(delta: int) -> void:
	if _pack_pockets.is_empty():
		return
	_pack_pocket_index = wrapi(_pack_pocket_index + signi(delta), 0, _pack_pockets.size())
	_pack_cursor = 0
	_render_pack()


func _move_pack_cursor(delta: int) -> void:
	var items: Array = _current_pocket_items()
	if items.is_empty():
		return
	_pack_cursor = wrapi(_pack_cursor + signi(delta), 0, items.size())
	_render_pack()


func _render_pack() -> void:
	var pocket: Dictionary = _current_pocket()
	_title.text = "PACK"
	_summary.text = String(pocket.get("name", ""))
	var items: Array = pocket.get("items", [])
	if items.is_empty():
		_status.text = "No items in this pocket."
		_status.add_theme_color_override("font_color", MUTED)
	_render_options(items, _pack_cursor, func(entry: Dictionary) -> String:
		return "%s    x%d" % [entry.get("name", "UNKNOWN"), int(entry.get("quantity", 0))]
	)


func _open_save_confirm_mode() -> void:
	_mode = Mode.SAVE_CONFIRM
	_save_cursor = 0
	_save_result_shown = false
	_title.text = "SAVE"
	_summary.text = "Save your progress?"
	_status.text = ""
	_footer.text = "Arrows: choose    Space/Enter: confirm    Esc: cancel"
	_render_save_confirm()


func _confirm_save() -> void:
	if _save_result_shown:
		_open_list_mode()
		return
	if _save_cursor == 1:
		_open_list_mode()
		return
	var result: Dictionary = _save_action.call() if _save_action.is_valid() else {"ok": false, "reason": &"no_save_action"}
	_save_result_shown = true
	if bool(result.get("ok", false)):
		_status.text = "World saved."
		_status.add_theme_color_override("font_color", SUCCESS)
	else:
		_status.text = "Save failed: %s" % String(result.get("reason", "unknown"))
		_status.add_theme_color_override("font_color", ERROR)
	_render_options(["Continue"], 0, func(entry: Variant) -> String: return str(entry))


func _render_save_confirm() -> void:
	_render_options(["Yes", "No"], _save_cursor, func(entry: Variant) -> String: return str(entry))


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


func _render_options(values: Array, cursor: int, label_for: Callable) -> void:
	if _options == null:
		return
	for child: Node in _options.get_children():
		child.queue_free()
	for index: int in values.size():
		var label := Label.new()
		var name: String = label_for.call(values[index])
		label.text = ("> " if index == cursor else "  ") + name
		label.add_theme_color_override("font_color", ACCENT if index == cursor else TEXT)
		label.add_theme_font_size_override("font_size", 18)
		_options.add_child(label)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	return style
