class_name Gen2ShelfPage
extends VBoxContainer

## The launcher's home: the cartridge carousel and the one or two things you can
## do with whatever is in the middle of it.
##
## The name of the selected cartridge is written on its own button rather than
## over it, so the page carries one label instead of three that all say the same
## thing.
##
## The page reports what was clicked and displays what it is told. Every import,
## refusal and launch belongs to the launcher.

signal insert_requested(game_id: StringName)
signal play_requested(game_id: StringName)
signal manage_requested(game_id: StringName)
## The shell paints its backdrop for the selected cartridge.
signal selection_changed(game_id: StringName)

var _theme: Gen2LauncherTheme = null
var _stage: Gen2CartridgeStage = null
var _play: Gen2LauncherButton = null
var _manage: Gen2LauncherButton = null
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

	var actions: HBoxContainer = Gen2LauncherUI.row(Gen2LauncherUI.GAP_SM)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(actions)

	_play = Gen2LauncherButton.create(_theme, "", Gen2LauncherButton.Variant.HERO, &"play")
	_play.custom_minimum_size = Vector2(210, 52)
	_play.add_theme_font_size_override("font_size", Gen2LauncherTheme.FONT_TITLE)
	_play.sound = &"power"
	_play.pressed.connect(_on_primary)
	actions.add_child(_play)

	_manage = Gen2LauncherButton.icon_only(_theme, &"dots", Gen2LauncherButton.Variant.DOCK, 44.0)
	_manage.tooltip_text = "Cache and re-import"
	_manage.pressed.connect(func() -> void: manage_requested.emit(_stage.selected_id()))
	actions.add_child(_manage)

	_refresh_action()


func stage() -> Gen2CartridgeStage:
	return _stage


## Where a keyboard or a pad starts on this page: the carousel, which is what the
## page is about and what ui_left and ui_right then turn.
func focus_target() -> Control:
	return _stage


func cartridge(game_id: StringName) -> Gen2Cartridge:
	return _stage.cartridge(game_id)


func selected_id() -> StringName:
	return _stage.selected_id()


func set_slot_state(game_id: StringName, imported: bool, detail: String) -> void:
	_details[game_id] = detail
	_stage.set_imported(game_id, imported)
	_refresh_action()


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
	_play.custom_minimum_size = Vector2(170 if compact else 210, 46 if compact else 52)
	_play.add_theme_font_size_override(
		"font_size",
		Gen2LauncherTheme.FONT_BODY if compact else Gen2LauncherTheme.FONT_TITLE,
	)
	_manage.set_side(40.0 if compact else 44.0)


func _on_primary() -> void:
	var id: StringName = _stage.selected_id()
	if _stage.selected_cartridge().imported:
		play_requested.emit(id)
	else:
		insert_requested.emit(id)


func _on_selection_changed(game_id: StringName) -> void:
	_refresh_action()
	selection_changed.emit(game_id)


## The button carries the cartridge's name, so it says both what is selected and
## what pressing it does.
func _refresh_action() -> void:
	var id: StringName = _stage.selected_id()
	var card: Gen2Cartridge = _stage.selected_cartridge()
	if card == null:
		return
	var title: String = RomRegistry.title_for(id)
	_play.text = title
	if card.imported:
		_play.set_glyph(&"play")
		_play.sound = &"power"
		_play.tooltip_text = "Play %s. %s" % [title, _details.get(id, "Ready")]
	else:
		_play.set_glyph(&"download")
		_play.sound = &"click"
		_play.tooltip_text = "Import a %s cartridge dump" % title
	_manage.visible = card.imported
