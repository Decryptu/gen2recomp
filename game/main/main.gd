extends Control

## The launcher: cartridge discovery, ROM import and entry into a development
## battle. It owns presentation and workflow, while the ROM and cache layers
## remain responsible for verification and decoding.

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

var _cards_container: HBoxContainer = null
var _import_button: Button = null
var _status_label: Label = null
var _status_detail: Label = null
var _progress: ProgressBar = null
var _progress_label: Label = null
var _file_dialog: FileDialog = null
var _cards: Dictionary = {}
var _selected_game_id: StringName = &""
var _importing: bool = false


func _ready() -> void:
	_build_ui()
	_print_allowlist()
	_refresh_games()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 64)
	margin.add_theme_constant_override("margin_top", 46)
	margin.add_theme_constant_override("margin_right", 64)
	margin.add_theme_constant_override("margin_bottom", 42)
	add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	margin.add_child(content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	content.add_child(header)

	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 4)
	header.add_child(heading)

	var title := Label.new()
	title.text = "gen2recomp"
	title.add_theme_color_override("font_color", TEXT)
	title.add_theme_font_size_override("font_size", 38)
	heading.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Generation 2, rebuilt for Godot"
	subtitle.add_theme_color_override("font_color", MUTED)
	subtitle.add_theme_font_size_override("font_size", 16)
	heading.add_child(subtitle)

	_import_button = _button("Import ROM", ACCENT)
	_import_button.custom_minimum_size = Vector2(168, 48)
	_import_button.pressed.connect(_open_import_dialog)
	header.add_child(_import_button)

	var section := Label.new()
	section.text = "CARTRIDGES"
	section.add_theme_color_override("font_color", ACCENT)
	section.add_theme_font_size_override("font_size", 13)
	content.add_child(section)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 216)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)

	_cards_container = HBoxContainer.new()
	_cards_container.add_theme_constant_override("separation", 16)
	_cards_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll.add_child(_cards_container)

	var status_panel := PanelContainer.new()
	status_panel.add_theme_stylebox_override("panel", _panel_style(PANEL, BORDER, 10))
	status_panel.custom_minimum_size = Vector2(0, 78)
	content.add_child(status_panel)

	var status_box := VBoxContainer.new()
	status_box.add_theme_constant_override("separation", 4)
	status_panel.add_child(status_box)

	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", TEXT)
	_status_label.add_theme_font_size_override("font_size", 16)
	status_box.add_child(_status_label)

	_status_detail = Label.new()
	_status_detail.add_theme_color_override("font_color", MUTED)
	_status_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_box.add_child(_status_detail)

	_progress = ProgressBar.new()
	_progress.max_value = 100.0
	_progress.show_percentage = false
	_progress.visible = false
	_progress.custom_minimum_size = Vector2(0, 8)
	status_box.add_child(_progress)

	_progress_label = Label.new()
	_progress_label.add_theme_color_override("font_color", MUTED)
	_progress_label.visible = false
	status_box.add_child(_progress_label)

	var footer := Label.new()
	footer.text = "Save slot 1 is used by the development battle. Mods are not available yet."
	footer.add_theme_color_override("font_color", MUTED)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(footer)

	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray([
		"*.gb; Game Boy ROM",
		"*.gbc; Game Boy Color ROM",
	])
	_file_dialog.title = "Choose a Gold, Silver, or Crystal ROM"
	_file_dialog.file_selected.connect(_on_file_selected)
	add_child(_file_dialog)

	_set_status("Choose an imported game to begin.", "Your own verified cartridge dump is required.", MUTED)


func _refresh_games() -> void:
	for child: Node in _cards_container.get_children():
		child.free()
	_cards.clear()

	for game_id: StringName in RomRegistry.ORDER:
		var data: GameData = GameData.open(game_id)
		var card: PanelContainer = _create_game_card(game_id, data)
		_cards_container.add_child(card)
		_cards[game_id] = card

	_update_import_controls()


## Public driver used by tests and by non-interactive tooling.
func import_rom_path(path: String) -> void:
	_on_file_selected(path)


## A small read-only view of the launcher state, useful for UI checks without
## reaching into the controls the launcher creates dynamically.
func launcher_snapshot() -> Dictionary:
	var games: Dictionary = {}
	for game_id: StringName in RomRegistry.ORDER:
		var data: GameData = GameData.open(game_id)
		games[String(game_id)] = {
			"title": RomRegistry.title_for(game_id),
			"imported": data != null,
			"selected": game_id == _selected_game_id,
			"save_slots": Gen2SaveStore.slots_for(game_id, data.sha1, data) if data != null else [],
		}
	return {
		"status": _status_label.text if _status_label != null else "",
		"detail": _status_detail.text if _status_detail != null else "",
		"importing": _importing,
		"games": games,
	}


func _create_game_card(game_id: StringName, data: GameData) -> PanelContainer:
	var imported: bool = data != null
	var selected: bool = game_id == _selected_game_id
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(300, 202)
	card.add_theme_stylebox_override(
		"panel", _panel_style(PANEL_SELECTED if selected else PANEL, BORDER_SELECTED if selected else BORDER, 10)
	)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	card.add_child(body)

	var title := Label.new()
	title.text = RomRegistry.title_for(game_id)
	title.add_theme_color_override("font_color", TEXT)
	title.add_theme_font_size_override("font_size", 26)
	body.add_child(title)

	var revision := Label.new()
	revision.text = _revision_for(game_id)
	revision.add_theme_color_override("font_color", MUTED)
	body.add_child(revision)

	var separator := HSeparator.new()
	separator.add_theme_color_override("separator", BORDER)
	body.add_child(separator)

	var state := Label.new()
	state.text = "CACHE READY" if imported else "NOT IMPORTED"
	state.add_theme_color_override("font_color", SUCCESS if imported else ACCENT)
	state.add_theme_font_size_override("font_size", 13)
	body.add_child(state)

	var detail := Label.new()
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_theme_color_override("font_color", MUTED)
	if imported:
		detail.text = "%d species, %d trainer classes\nCache format %d\n%s" % [
			data.species_count(), data.trainer_count(), RomCache.FORMAT_VERSION,
			_save_slot_detail(game_id, data),
		]
	else:
		detail.text = "Bring your own verified dump.\nThe filename does not matter."
	body.add_child(detail)

	var action := _button("Play development battle" if imported else "Choose ROM", ACCENT if imported else TEXT)
	action.custom_minimum_size = Vector2(0, 38)
	action.pressed.connect(_on_game_action.bind(game_id, imported))
	body.add_child(action)

	return card


func _on_game_action(game_id: StringName, imported: bool) -> void:
	if _importing:
		return
	if imported and GameData.open(game_id) != null:
		_launch_game(game_id)
	else:
		_open_import_dialog()


func _launch_game(game_id: StringName) -> void:
	var data: GameData = GameData.open(game_id)
	var save_result: Dictionary = Gen2SaveStore.ensure_development_save(data, 0)
	if not save_result["ok"]:
		_set_status("Could not open save slot 1.", String(save_result["message"]), ERROR)
		_refresh_games()
		return
	if not GameRuntime.select_save_slot(game_id, 0):
		_set_status("Could not select %s." % RomRegistry.title_for(game_id), "The registry did not recognise that game.", ERROR)
		return
	_selected_game_id = game_id
	_set_status("Opening %s." % RomRegistry.title_for(game_id), "Save slot 1 is loaded for the development battle.", SUCCESS)
	get_tree().change_scene_to_file.call_deferred("res://game/battle/battle_screen.tscn")


func _open_import_dialog() -> void:
	if _importing:
		return
	_set_status("Choose a ROM dump.", "The importer identifies the game by SHA-1, never by filename.", MUTED)
	_file_dialog.popup_centered(Vector2i(920, 620))


func _on_file_selected(path: String) -> void:
	if _importing:
		return
	_importing = true
	_update_import_controls()
	_progress.visible = true
	_progress_label.visible = true
	_progress.value = 0.0
	_progress_label.text = "Checking cartridge..."
	_set_status("Verifying cartridge...", path.get_file(), MUTED)

	var identity: Dictionary = RomVerifier.identify(path)
	if identity["status"] != RomVerifier.Status.OK:
		_finish_import(false, String(identity["message"]))
		return

	var rom: RomFile = RomFile.open_verified(path)
	if rom == null:
		_finish_import(false, "The verified cartridge could not be read.")
		return

	_progress_label.text = "Checking table layout..."
	var layout_check: Dictionary = RomImporter.verify_layout(rom)
	if not layout_check["ok"]:
		_finish_import(false, String(layout_check["message"]))
		return

	var importer := RomImporter.new()
	var result: Dictionary = importer.import_rom(rom, _on_import_progress)
	if not result["ok"]:
		_finish_import(false, String(result["message"]))
		return

	var game_id: StringName = identity["id"]
	GameRuntime.select_game(game_id)
	_selected_game_id = game_id
	_finish_import(true, "Imported %s. %d species and %d trainer classes are ready." % [
		identity["message"], int(result["species"]), int(result["trainers"]),
	])
	_refresh_games()


func _on_import_progress(stage: String, done: int, total: int) -> void:
	if total > 0:
		_progress.value = float(done) / float(total) * 100.0
	_progress_label.text = "%s, %d/%d" % [stage.capitalize(), done, total]


func _finish_import(success: bool, message: String) -> void:
	_importing = false
	_update_import_controls()
	_progress.visible = false
	_progress_label.visible = false
	_set_status("Import complete." if success else "Import stopped.", message, SUCCESS if success else ERROR)


func _update_import_controls() -> void:
	if _import_button != null:
		_import_button.disabled = _importing
	for card: PanelContainer in _cards.values():
		var body: VBoxContainer = card.get_child(0)
		var action: Button = body.get_child(body.get_child_count() - 1)
		action.disabled = _importing


func _set_status(title: String, detail: String, colour: Color) -> void:
	if _status_label == null:
		return
	_status_label.text = title
	_status_label.add_theme_color_override("font_color", colour)
	_status_detail.text = detail


func _revision_for(game_id: StringName) -> String:
	var row: Dictionary = RomRegistry.lookup(RomRegistry.sha1_for(game_id))
	return String(row.get("revision", "Supported cartridge"))


func _save_slot_detail(game_id: StringName, data: GameData) -> String:
	var slots: Array = Gen2SaveStore.slots_for(game_id, data.sha1, data)
	var first: Dictionary = slots[0]
	return "Save slot 1: %s" % ("READY" if first["valid"] else "EMPTY")


func _print_allowlist() -> void:
	var lines: PackedStringArray = []
	for id: StringName in RomRegistry.ORDER:
		lines.append("  %-8s %s" % [RomRegistry.title_for(id), RomRegistry.sha1_for(id)])
	print("gen2recomp supported cartridges:")
	print("\n".join(lines))


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
	style.content_margin_left = 20
	style.content_margin_top = 18
	style.content_margin_right = 20
	style.content_margin_bottom = 18
	return style
