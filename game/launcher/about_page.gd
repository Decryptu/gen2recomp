class_name Gen2AboutPage
extends VBoxContainer

## What this build is, which cartridges it accepts, and the release check.
##
## The check only ever runs from its button: it reaches a third party and says
## this build exists, so it is the player's act and never a side effect of
## opening the launcher.

signal update_check_requested

var _theme: Gen2LauncherTheme = null
var _result: Label = null


static func create(palette: Gen2LauncherTheme) -> Gen2AboutPage:
	var page := Gen2AboutPage.new()
	page._theme = palette
	page._build()
	return page


func _build() -> void:
	add_theme_constant_override("separation", Gen2LauncherUI.GAP_LG)
	add_child(Gen2LauncherUI.title(_theme, "About", Gen2LauncherTheme.FONT_DISPLAY))

	var scroll: Gen2LauncherScroll = Gen2LauncherScroll.create()
	add_child(scroll)
	var column: VBoxContainer = Gen2LauncherUI.column(Gen2LauncherUI.GAP_LG)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	var build: VBoxContainer = _card(column, "This build")
	build.add_child(Gen2LauncherUI.body(
		_theme, "pokerecomp %s" % Gen2AppVersion.display()
	))
	build.add_child(Gen2LauncherUI.muted(
		_theme,
		"A Godot reimplementation of three second generation handheld role "
		+ "playing cartridges. It ships no game data: everything it plays is "
		+ "decoded from a cartridge you own and dumped yourself.",
	))
	var check: Gen2LauncherButton = Gen2LauncherButton.create(
		_theme, "Check for updates", Gen2LauncherButton.Variant.NEUTRAL, &"refresh"
	)
	check.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	check.pressed.connect(func() -> void: update_check_requested.emit())
	build.add_child(check)
	_result = Gen2LauncherUI.muted(_theme, "")
	build.add_child(_result)

	var accepted: VBoxContainer = _card(column, "Cartridges this build accepts")
	accepted.add_child(Gen2LauncherUI.muted(
		_theme, "A dump is matched by its SHA-1 hash, never by its filename."
	))
	for game_id: StringName in RomRegistry.ORDER:
		var sha1: String = RomRegistry.sha1_for(game_id)
		var row: Dictionary = RomRegistry.lookup(sha1)
		var line: HBoxContainer = Gen2LauncherUI.row(Gen2LauncherUI.GAP_MD)
		accepted.add_child(line)
		var title: Label = Gen2LauncherUI.body(_theme, RomRegistry.title_for(game_id))
		title.custom_minimum_size = Vector2(96, 0)
		line.add_child(title)
		var revision: Label = Gen2LauncherUI.muted(
			_theme, String(row.get("revision", "Supported"))
		)
		revision.custom_minimum_size = Vector2(150, 0)
		line.add_child(revision)
		var hash_label: Label = Gen2LauncherUI.muted(_theme, sha1)
		hash_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hash_label.add_theme_color_override("font_color", _theme.faint)
		line.add_child(hash_label)
	column.add_child(Gen2LauncherUI.dock_safe_space())


## Shown after a release check answers, in the colour its outcome deserves.
func set_update_result(message: String, colour: Color) -> void:
	_result.text = message
	_result.add_theme_color_override("font_color", colour)


func _card(host: VBoxContainer, title: String) -> VBoxContainer:
	var panel: Gen2LauncherCard = Gen2LauncherCard.create(_theme, Gen2LauncherTheme.RADIUS_MD, 22)
	host.add_child(panel)
	var column: VBoxContainer = Gen2LauncherUI.column(Gen2LauncherUI.GAP_MD)
	panel.add_child(column)
	column.add_child(Gen2LauncherUI.caption(_theme, title))
	return column
