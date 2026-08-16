class_name Gen2ModDetailPage
extends VBoxContainer

## One mod's own page: what it is, where it came from, and its settings.
##
## Everything the list deliberately does not carry is here, which is why the
## list can stay one line per mod. The settings are built from what the mod
## registered on [Gen2ModHost] rather than from anything written here, so this
## page and the game's own MODS menu are one registration seen twice.

signal closed
signal enabled_changed(row: Dictionary, on: bool)
signal download_requested(row: Dictionary)
signal remove_requested(row: Dictionary)

var _theme: Gen2LauncherTheme = null
var _title: Label = null
var _subtitle: Label = null
var _body: VBoxContainer = null
var _status: Label = null
var _row: Dictionary = {}


static func create(palette: Gen2LauncherTheme) -> Gen2ModDetailPage:
	var page := Gen2ModDetailPage.new()
	page._theme = palette
	page._build()
	return page


func _build() -> void:
	add_theme_constant_override("separation", Gen2LauncherUI.GAP_LG)

	var head: HBoxContainer = Gen2LauncherUI.row(Gen2LauncherUI.GAP_MD)
	add_child(head)
	var back: Gen2LauncherButton = Gen2LauncherButton.icon_only(
		_theme, &"back", Gen2LauncherButton.Variant.QUIET, 42.0
	)
	back.tooltip_text = "Back to the mod list"
	back.pressed.connect(func() -> void: closed.emit())
	head.add_child(back)
	var text: VBoxContainer = Gen2LauncherUI.column(2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(text)
	_title = Gen2LauncherUI.title(_theme, "", Gen2LauncherTheme.FONT_TITLE)
	text.add_child(_title)
	_subtitle = Gen2LauncherUI.muted(_theme, "")
	text.add_child(_subtitle)

	var scroll: Gen2LauncherScroll = Gen2LauncherScroll.create()
	add_child(scroll)
	_body = Gen2LauncherUI.column(Gen2LauncherUI.GAP_MD)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)

	_status = Gen2LauncherUI.muted(_theme, "")
	add_child(_status)


## Which mod this page is showing, so its owner can hand it a fresh row after
## anything that changed one.
func mod_id() -> StringName:
	return StringName(_row.get("id", &""))


## Draws [param row], which is [Gen2ModCatalogue]'s. An empty row leaves the page
## as it was: the caller closes it rather than showing a page about nothing.
func set_row(row: Dictionary) -> void:
	if row.is_empty():
		return
	_row = row.duplicate(true)
	_title.text = String(row["name"])
	_subtitle.text = "%s  %s" % [row["id"], row["source_label"]]
	Gen2LauncherUI.clear(_body)

	_body.add_child(_summary(row))
	var description: String = String(row["description"])
	if not description.is_empty():
		var detail: Label = Gen2LauncherUI.muted(_theme, description)
		_body.add_child(detail)

	var options: Array = Gen2ModHost.instance().options(mod_id())
	if bool(row["installed"]) and not options.is_empty():
		_body.add_child(Gen2LauncherUI.caption(_theme, "Settings"))
		var panel: Gen2LauncherCard = Gen2LauncherCard.create(
			_theme, Gen2LauncherTheme.RADIUS_MD, 18
		)
		var fields: VBoxContainer = Gen2LauncherUI.column(Gen2LauncherUI.GAP_MD)
		panel.add_child(fields)
		for option: Dictionary in options:
			fields.add_child(_option_field(mod_id(), option))
		_body.add_child(panel)
	_body.add_child(Gen2LauncherUI.dock_safe_space())


## The strip of facts and the buttons that act on them: what is installed, what
## the source offers, which cartridges it is for, and one row of actions.
func _summary(row: Dictionary) -> Control:
	var panel: Gen2LauncherCard = Gen2LauncherCard.create(_theme, Gen2LauncherTheme.RADIUS_MD, 18)
	var column: VBoxContainer = Gen2LauncherUI.column(Gen2LauncherUI.GAP_MD)
	panel.add_child(column)

	var installed: String = String(row["installed_version"])
	column.add_child(Gen2LauncherUI.field(
		_theme, "Installed", _value(installed if not installed.is_empty() else "Not installed")
	))
	var listed: String = String(row["listed_version"])
	if bool(row["listed"]):
		column.add_child(Gen2LauncherUI.field(
			_theme, "Offered", _value(listed if not listed.is_empty() else "no version given")
		))
	# What it is for, so a player reads it before pressing Play rather than after
	# the mod refused to load. A mod that declares nothing is for every cartridge
	# and says nothing here.
	var manifest: Gen2ModManifest = row["manifest"]
	if manifest != null:
		var titles: Array[String] = manifest.game_titles()
		if not titles.is_empty():
			column.add_child(Gen2LauncherUI.field(_theme, "For", _value(", ".join(titles))))

	var actions: HBoxContainer = Gen2LauncherUI.row(Gen2LauncherUI.GAP_SM)
	column.add_child(actions)
	if bool(row["installed"]):
		var switch: Gen2LauncherToggle = Gen2LauncherToggle.create(_theme, bool(row["enabled"]))
		switch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		switch.toggled.connect(func(on: bool) -> void: enabled_changed.emit(_row, on))
		actions.add_child(switch)
	actions.add_child(Gen2LauncherUI.spacer())
	if bool(row["listed"]):
		var get_it: Gen2LauncherButton = Gen2LauncherButton.create(
			_theme, _download_label(row), Gen2LauncherButton.Variant.PRIMARY, &"download"
		)
		get_it.pressed.connect(func() -> void: download_requested.emit(_row))
		actions.add_child(get_it)
	if bool(row["installed"]):
		var remove: Gen2LauncherButton = Gen2LauncherButton.create(
			_theme,
			"Delete" if Gen2ModCatalogue.removal_is_permanent(row) else "Remove",
			Gen2LauncherButton.Variant.DANGER,
			&"trash",
		)
		remove.pressed.connect(func() -> void: remove_requested.emit(_row))
		actions.add_child(remove)
	return panel


## A field's right-hand side. Wrapping is off, because a label given the room
## its text asks for is a value and one squeezed against the field name is a
## column of single letters.
func _value(text: String) -> Label:
	var label: Label = Gen2LauncherUI.muted(_theme, text)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return label


static func _download_label(row: Dictionary) -> String:
	match Gen2ModCatalogue.action_for(row):
		&"download":
			return "Download"
		&"update":
			return "Update to %s" % row["listed_version"]
	return "Reinstall"


func _option_field(id: StringName, option: Dictionary) -> Control:
	var key: StringName = StringName(option.get("key", &""))
	var label: String = String(option.get("label", ""))
	match StringName(option.get("kind", Gen2ModHost.OPTION_LADDER)):
		Gen2ModHost.OPTION_BUTTON:
			var press: Gen2LauncherButton = Gen2LauncherButton.create(
				_theme, String(option.get("press_label", "Go")),
				Gen2LauncherButton.Variant.NEUTRAL,
			)
			press.pressed.connect(func() -> void:
				_report(Gen2ModHost.instance().press_option(id, key))
			)
			return Gen2LauncherUI.field(_theme, label, press)
		Gen2ModHost.OPTION_NUMBER:
			# Typed rather than dialled: a seed is one field with ten thousand
			# values and no player wants to hold an arrow through it.
			return Gen2LauncherUI.field(_theme, label, Gen2LauncherUI.number(
				_theme, int(option.get("value", 0)), int(option.get("minimum", 0)),
				int(option.get("maximum", 0)), int(option.get("step", 1)),
				func(value: int) -> void:
					_report(Gen2ModHost.instance().set_option(id, key, value))
			))
	return Gen2LauncherUI.field(_theme, label, Gen2LauncherUI.segmented(
		_theme, option.get("labels", []) as Array, int(option.get("index", 0)),
		func(index: int) -> void:
			_report(Gen2ModHost.instance().set_option_index(id, key, index))
	))


func _report(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		set_status(Gen2ModRefusal.text(result), _theme.error)


func set_status(message: String, colour: Color) -> void:
	_status.text = message
	_status.add_theme_color_override("font_color", colour)
