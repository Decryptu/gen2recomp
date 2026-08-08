class_name Gen2ShelfPage
extends VBoxContainer

## The launcher's home: the cartridge stage, the name of whatever is selected,
## and the one or two things you can do with it.
##
## The page reports what was clicked and displays what it is told. Every import,
## refusal and launch belongs to the launcher.

signal insert_requested(game_id: StringName)
signal play_requested(game_id: StringName)
signal manage_requested(game_id: StringName)
## The shell paints its backdrop in the selected cartridge's colour.
signal selection_changed(game_id: StringName)

var _theme: Gen2LauncherTheme = null
var _stage: Gen2CartridgeStage = null
var _name: Label = null
var _detail: Label = null
var _play: Gen2LauncherButton = null
var _manage: Gen2LauncherButton = null
var _dots: HBoxContainer = null
var _details: Dictionary = {}
var _compact: bool = false


static func create(palette: Gen2LauncherTheme, compact: bool) -> Gen2ShelfPage:
	var page := Gen2ShelfPage.new()
	page._theme = palette
	page._compact = compact
	page._build()
	return page


func _build() -> void:
	add_theme_constant_override("separation", Gen2LauncherUI.GAP_LG)

	_stage = Gen2CartridgeStage.create(_theme, RomRegistry.ORDER)
	_stage.selection_changed.connect(_on_selection_changed)
	_stage.insert_requested.connect(func(id: StringName) -> void: insert_requested.emit(id))
	_stage.play_requested.connect(func(id: StringName) -> void: play_requested.emit(id))
	add_child(_stage)

	var caption: VBoxContainer = Gen2LauncherUI.column(Gen2LauncherUI.GAP_XS)
	caption.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(caption)
	_name = Gen2LauncherUI.title(
		_theme, "", Gen2LauncherTheme.FONT_DISPLAY if _compact else Gen2LauncherTheme.FONT_HERO
	)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_child(_name)
	_detail = Gen2LauncherUI.muted(_theme, "")
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_child(_detail)

	_dots = Gen2LauncherUI.row(Gen2LauncherUI.GAP_SM)
	_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	caption.add_child(_dots)
	for index: int in RomRegistry.ORDER.size():
		var dot := Control.new()
		dot.custom_minimum_size = Vector2(7, 7)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.draw.connect(_draw_dot.bind(dot, index))
		_dots.add_child(dot)

	var actions: HBoxContainer = Gen2LauncherUI.row(Gen2LauncherUI.GAP_SM)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(actions)
	_play = Gen2LauncherButton.create(
		_theme, "Play", Gen2LauncherButton.Variant.PRIMARY, &"play"
	)
	_play.custom_minimum_size = Vector2(168, 48)
	_play.add_theme_font_size_override("font_size", Gen2LauncherTheme.FONT_TITLE)
	_play.sound = &"power"
	_play.pressed.connect(func() -> void: _on_primary())
	actions.add_child(_play)
	# Round, to match the dock rather than the pill beside it.
	_manage = Gen2LauncherButton.icon_only(
		_theme, &"dots", Gen2LauncherButton.Variant.DOCK, 48.0
	)
	_manage.tooltip_text = "Cache and re-import"
	_manage.pressed.connect(func() -> void: manage_requested.emit(_stage.selected_id()))
	actions.add_child(_manage)

	_refresh_caption()


func stage() -> Gen2CartridgeStage:
	return _stage


func cartridge(game_id: StringName) -> Gen2Cartridge:
	return _stage.cartridge(game_id)


func selected_id() -> StringName:
	return _stage.selected_id()


func set_slot_state(game_id: StringName, imported: bool, detail: String) -> void:
	_details[game_id] = detail
	_stage.set_imported(game_id, imported)
	_refresh_caption()


func set_busy(busy: bool) -> void:
	_play.set_disabled_state(busy)
	_manage.set_disabled_state(busy)


## Moves the selection onto [param game_id], used after an import so the freshly
## seated cartridge is the one on show.
func focus_game(game_id: StringName) -> void:
	var index: int = RomRegistry.ORDER.find(game_id)
	if index >= 0:
		_stage.select(index)


func set_compact(compact: bool) -> void:
	if compact == _compact:
		return
	_compact = compact
	_name.add_theme_font_size_override(
		"font_size",
		Gen2LauncherTheme.FONT_DISPLAY if compact else Gen2LauncherTheme.FONT_HERO,
	)


func _on_primary() -> void:
	var id: StringName = _stage.selected_id()
	if _stage.selected_cartridge().imported:
		play_requested.emit(id)
	else:
		insert_requested.emit(id)


func _on_selection_changed(game_id: StringName) -> void:
	_refresh_caption()
	selection_changed.emit(game_id)


func _refresh_caption() -> void:
	var id: StringName = _stage.selected_id()
	var card: Gen2Cartridge = _stage.selected_cartridge()
	if card == null:
		return
	_name.text = RomRegistry.title_for(id)
	_name.add_theme_color_override("font_color", _theme.text if card.imported else _theme.faint)
	if card.imported:
		_detail.text = String(_details.get(id, "Ready"))
		_play.text = "Play"
		_play.set_glyph(&"play")
		_play.sound = &"power"
	else:
		_detail.text = "No cartridge in this bay yet"
		_play.text = "Add cartridge"
		_play.set_glyph(&"download")
		_play.sound = &"click"
	_manage.visible = card.imported
	for dot: Node in _dots.get_children():
		(dot as Control).queue_redraw()


func _draw_dot(dot: Control, index: int) -> void:
	var chosen: bool = index == _stage.selected
	var colour: Color = (
		_theme.tint_for(RomRegistry.ORDER[index]) if chosen
		else _theme.with_alpha(_theme.faint, 0.45)
	)
	dot.draw_circle(dot.size * 0.5, 3.5 if chosen else 3.0, colour)
