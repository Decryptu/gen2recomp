class_name Gen2AboutPage
extends VBoxContainer

## What this build is, which cartridges it accepts, the release check, and the
## two places a player can reach the project from.
##
## The check only ever runs from its button: it reaches a third party and says
## this build exists, so it is the player's act and never a side effect of
## opening the launcher. Every link here is the same: nothing leaves the machine
## until a button is pressed.

signal update_check_requested

var _theme: Gen2LauncherTheme = null
var _result: Label = null
## What a sheet opens over. The page itself is swapped out with the dock, so a
## sheet parented to it would vanish with the page behind it.
var _host: Control = null


static func create(palette: Gen2LauncherTheme, host: Control = null) -> Gen2AboutPage:
	var page := Gen2AboutPage.new()
	page._theme = palette
	page._host = host
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

	var report: VBoxContainer = _card(column, "Something wrong?")
	report.add_child(Gen2LauncherUI.muted(
		_theme,
		"Report it where it will be read. The tracker wants a repeatable case; "
		+ "the chat will help you work out what you are looking at.",
	))
	var bug: Gen2LauncherButton = Gen2LauncherButton.create(
		_theme, "Report a bug", Gen2LauncherButton.Variant.PRIMARY, &"bug"
	)
	bug.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bug.pressed.connect(open_report_sheet)
	report.add_child(bug)

	var project: VBoxContainer = _card(column, "The project")
	var links: HBoxContainer = Gen2LauncherUI.row(Gen2LauncherUI.GAP_SM)
	project.add_child(links)
	links.add_child(_link_button(
		"GitHub", &"github", Gen2AppVersion.REPOSITORY, Gen2LauncherButton.Variant.NEUTRAL
	))
	links.add_child(_link_button(
		"Discord", &"discord", Gen2AppVersion.DISCORD, Gen2LauncherButton.Variant.NEUTRAL
	))
	links.add_child(Gen2LauncherUI.spacer())

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


## The two ways to report, named for who each is for rather than for the service
## behind it: one player has a GitHub account and one has never seen an issue
## tracker, and both need to end up somewhere the report is read.
func open_report_sheet() -> void:
	var sheet: Gen2LauncherSheet = Gen2LauncherSheet.create(_theme, "Report a bug")
	var body: VBoxContainer = sheet.body()
	body.add_child(Gen2LauncherUI.muted(
		_theme,
		"Say which cartridge, where you were and what you did. A screenshot "
		+ "settles most of it.",
	))
	body.add_child(_link_button(
		"Open an issue on GitHub",
		&"github",
		Gen2AppVersion.ISSUES,
		Gen2LauncherButton.Variant.PRIMARY,
		sheet,
	))
	body.add_child(Gen2LauncherUI.muted(
		_theme, "For anyone who already uses an issue tracker."
	))
	body.add_child(_link_button(
		"Tell us on Discord",
		&"discord",
		Gen2AppVersion.DISCORD,
		Gen2LauncherButton.Variant.NEUTRAL,
		sheet,
	))
	body.add_child(Gen2LauncherUI.muted(
		_theme, "For everyone else. Ask in the chat and someone will write it up."
	))
	sheet.open(_host if _host != null else self)


## A button that hands [param url] to the desktop's browser. [param sheet] is
## closed first when the button lives in one, so the launcher is not left behind
## a card the player has already finished with.
func _link_button(
	label: String,
	glyph: StringName,
	url: String,
	kind: Gen2LauncherButton.Variant,
	sheet: Gen2LauncherSheet = null,
) -> Gen2LauncherButton:
	var button: Gen2LauncherButton = Gen2LauncherButton.create(_theme, label, kind, glyph)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.tooltip_text = url
	button.pressed.connect(func() -> void:
		if sheet != null:
			sheet.close()
		OS.shell_open(url)
	)
	return button


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
