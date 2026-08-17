class_name Gen2SettingsPage
extends VBoxContainer

## Edits [Gen2Options] in three cards: how the launcher looks, how the app
## behaves, and the cartridge's own OPTION menu.
##
## Every change writes immediately. There is no state here worth an apply
## button, and a half-applied options file is worse than none.

signal appearance_changed

## Label, then the values in the order the source cycles them.
const TEXT_SPEEDS: Array[String] = ["Fast", "Mid", "Slow"]
const PRINTER_LABELS: Array[String] = ["Lightest", "Lighter", "Normal", "Darker", "Darkest"]
## [constant Gen2Rules.MODES], in its order. Written out rather than capitalized
## from the names, which would say "Qol".
const RULE_MODES: Array[String] = ["Current", "Vanilla", "QoL"]

var _theme: Gen2LauncherTheme = null
var _options: Gen2Options = null
var _saved: Label = null
## Where a modal opens. The launcher root rather than this page, so a sheet
## covers the dock as well and is not clipped by the settings scroll.
var _host: Control = null


static func create(palette: Gen2LauncherTheme, host: Control = null) -> Gen2SettingsPage:
	var page := Gen2SettingsPage.new()
	page._theme = palette
	page._options = Gen2OptionsStore.current()
	page._host = host
	page._build()
	return page


func _build() -> void:
	add_theme_constant_override("separation", Gen2LauncherUI.GAP_LG)
	var head: VBoxContainer = Gen2LauncherUI.column(2)
	add_child(head)
	head.add_child(Gen2LauncherUI.title(_theme, "Settings", Gen2LauncherTheme.FONT_DISPLAY))
	_saved = Gen2LauncherUI.muted(_theme, "Changes are written as you make them.")
	head.add_child(_saved)

	var scroll: Gen2LauncherScroll = Gen2LauncherScroll.create()
	add_child(scroll)
	var column: VBoxContainer = Gen2LauncherUI.column(Gen2LauncherUI.GAP_LG)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	var look: VBoxContainer = _card(column, "Appearance")
	look.add_child(Gen2LauncherUI.field(_theme, "Theme", Gen2LauncherUI.segmented(
		_theme, ["Light", "Dark"], Gen2Options.UI_THEMES.find(_options.ui_theme),
		func(index: int) -> void:
			_options.ui_theme = Gen2Options.UI_THEMES[index]
			_persist()
			appearance_changed.emit()
	)))

	var app: VBoxContainer = _card(column, "Application")
	app.add_child(Gen2LauncherUI.field(_theme, "Music volume", Gen2LauncherUI.slider(
		_theme, _options.music_volume, 0, Gen2Options.MAX_VOLUME,
		func(value: int) -> void:
			_options.music_volume = value
			_persist()
	)))
	app.add_child(Gen2LauncherUI.field(_theme, "Sound volume", Gen2LauncherUI.slider(
		_theme, _options.sfx_volume, 0, Gen2Options.MAX_VOLUME,
		func(value: int) -> void:
			_options.sfx_volume = value
			_persist()
	)))
	app.add_child(Gen2LauncherUI.field(_theme, "Window", Gen2LauncherUI.segmented(
		_theme, _titles(Gen2Options.VIDEO_MODES),
		maxi(Gen2Options.VIDEO_MODES.find(_options.video_mode), 0),
		func(index: int) -> void:
			_options.video_mode = Gen2Options.VIDEO_MODES[index]
			_persist()
	)))
	app.add_child(Gen2LauncherUI.field(_theme, "Game speed", Gen2LauncherUI.segmented(
		_theme, _titles(Gen2Options.GAME_SPEEDS),
		maxi(Gen2Options.GAME_SPEEDS.find(_options.game_speed), 0),
		func(index: int) -> void:
			_options.game_speed = Gen2Options.GAME_SPEEDS[index]
			_persist()
	)))
	var fps_labels: Array[String] = []
	for fps: int in Gen2Options.FPS_CHOICES:
		fps_labels.append("Max" if fps == 0 else str(fps))
	app.add_child(Gen2LauncherUI.field(_theme, "Frame rate", Gen2LauncherUI.segmented(
		_theme, fps_labels, maxi(Gen2Options.FPS_CHOICES.find(_options.max_fps), 0),
		func(index: int) -> void:
			_options.max_fps = Gen2Options.FPS_CHOICES[index]
			_persist()
	)))

	var controls: VBoxContainer = _card(column, "Controls")
	var section: Gen2ControlsSection = Gen2ControlsSection.create(
		_theme, _options, _host if _host != null else self
	)
	section.changed.connect(func() -> void:
		_persist()
		Gen2InputRuntime.instance().apply_options(_options)
	)
	section.arrange_requested.connect(_open_touch_layout)
	controls.add_child(section)

	var rules: VBoxContainer = _card(column, "Gameplay")
	rules.add_child(Gen2LauncherUI.muted(
		_theme,
		"What the engine does where this port and the cartridge disagree. A run "
		+ "keeps the rules it was created with, so changing these affects the next "
		+ "new game rather than a save already in progress."
	))
	rules.add_child(Gen2LauncherUI.field(_theme, "Bugs", Gen2LauncherUI.segmented(
		_theme, RULE_MODES, maxi(Gen2Rules.MODES.find(_options.rules.mode), 0),
		func(index: int) -> void:
			_options.rules.set_mode(Gen2Rules.MODES[index])
			_persist()
	)))
	rules.add_child(Gen2LauncherUI.field(_theme, "Trainer AI", Gen2LauncherUI.segmented(
		_theme, _titles(Gen2Rules.DIFFICULTIES),
		maxi(Gen2Rules.DIFFICULTIES.find(_options.rules.difficulty), 0),
		func(index: int) -> void:
			_options.rules.difficulty = Gen2Rules.DIFFICULTIES[index]
			_persist()
	)))

	var game: VBoxContainer = _card(column, "In game")
	game.add_child(Gen2LauncherUI.muted(
		_theme, "These are the cartridge's own OPTION menu, kept as the same bytes."
	))
	game.add_child(Gen2LauncherUI.field(_theme, "Text speed", Gen2LauncherUI.segmented(
		_theme, TEXT_SPEEDS, _options.text_speed,
		func(index: int) -> void:
			_options.text_speed = index
			_persist()
	)))
	game.add_child(Gen2LauncherUI.field(_theme, "Battle scene", _toggle(
		_options.battle_scene, func(on: bool) -> void:
			_options.battle_scene = on
			_persist()
	)))
	game.add_child(Gen2LauncherUI.field(_theme, "Battle style", Gen2LauncherUI.segmented(
		_theme, ["Shift", "Set"], 1 if _options.battle_style_set else 0,
		func(index: int) -> void:
			_options.battle_style_set = index == 1
			_persist()
	)))
	game.add_child(Gen2LauncherUI.field(_theme, "Sound", Gen2LauncherUI.segmented(
		_theme, ["Mono", "Stereo"], 1 if _options.stereo else 0,
		func(index: int) -> void:
			_options.stereo = index == 1
			_persist()
	)))
	game.add_child(Gen2LauncherUI.field(_theme, "Text frame", Gen2LauncherUI.slider(
		_theme, _options.textbox_frame, 0, Gen2Options.FRAME_COUNT - 1,
		func(value: int) -> void:
			_options.textbox_frame = value
			_persist()
	)))
	game.add_child(Gen2LauncherUI.field(_theme, "Menu account", _toggle(
		_options.menu_account, func(on: bool) -> void:
			_options.menu_account = on
			_persist()
	)))
	game.add_child(Gen2LauncherUI.field(_theme, "Print", Gen2LauncherUI.segmented(
		_theme, PRINTER_LABELS, _options.printer_brightness,
		func(index: int) -> void:
			_options.printer_brightness = index
			_persist()
	)))
	column.add_child(Gen2LauncherUI.dock_safe_space())


func _open_touch_layout() -> void:
	var sheet: Gen2TouchLayoutSheet = Gen2TouchLayoutSheet.create(_theme, _options)
	sheet.closed.connect(_persist)
	sheet.open(_host if _host != null else self)


func _card(host: VBoxContainer, name: String) -> VBoxContainer:
	var panel: Gen2LauncherCard = Gen2LauncherCard.create(_theme, Gen2LauncherTheme.RADIUS_MD, 22)
	host.add_child(panel)
	var column: VBoxContainer = Gen2LauncherUI.column(Gen2LauncherUI.GAP_MD)
	panel.add_child(column)
	column.add_child(Gen2LauncherUI.caption(_theme, name))
	return column


func _toggle(on: bool, handler: Callable) -> Gen2LauncherToggle:
	var switch: Gen2LauncherToggle = Gen2LauncherToggle.create(_theme, on)
	switch.toggled.connect(handler)
	return switch


func _titles(values: Array[StringName]) -> Array[String]:
	var out: Array[String] = []
	for value: StringName in values:
		out.append(String(value).capitalize())
	return out


func _persist() -> void:
	var ok: bool = Gen2OptionsStore.save(_options)
	_saved.text = (
		"Saved." if ok else "The options file could not be written."
	)
	_saved.add_theme_color_override("font_color", _theme.muted if ok else _theme.error)
