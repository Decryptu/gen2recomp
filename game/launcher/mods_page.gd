class_name Gen2ModsPage
extends VBoxContainer

## Installed mods, with an on/off switch and a delete beside each.
##
## Switching one off takes effect on the next start, which the page says rather
## than pretending a running registration can be withdrawn: a mod has already
## registered its content and renderers by the time this is reachable.

signal install_requested
signal index_requested
signal mods_changed

var _theme: Gen2LauncherTheme = null
var _list: VBoxContainer = null
var _note: Label = null


static func create(palette: Gen2LauncherTheme) -> Gen2ModsPage:
	var page := Gen2ModsPage.new()
	page._theme = palette
	page._build()
	page.refresh()
	return page


func _build() -> void:
	add_theme_constant_override("separation", Gen2LauncherUI.GAP_LG)

	var head: HBoxContainer = Gen2LauncherUI.row(Gen2LauncherUI.GAP_MD)
	add_child(head)
	var text: VBoxContainer = Gen2LauncherUI.column(2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(text)
	text.add_child(Gen2LauncherUI.title(_theme, "Mods", Gen2LauncherTheme.FONT_DISPLAY))
	_note = Gen2LauncherUI.muted(_theme, "")
	text.add_child(_note)

	var actions: HBoxContainer = Gen2LauncherUI.row(Gen2LauncherUI.GAP_SM)
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(actions)
	var install: Gen2LauncherButton = Gen2LauncherButton.create(
		_theme, "Install", Gen2LauncherButton.Variant.PRIMARY, &"plus"
	)
	install.pressed.connect(func() -> void: install_requested.emit())
	actions.add_child(install)
	var browse: Gen2LauncherButton = Gen2LauncherButton.create(
		_theme, "Browse", Gen2LauncherButton.Variant.NEUTRAL, &"download"
	)
	browse.pressed.connect(func() -> void: index_requested.emit())
	actions.add_child(browse)

	var scroll: Gen2LauncherScroll = Gen2LauncherScroll.create()
	add_child(scroll)
	_list = Gen2LauncherUI.column(Gen2LauncherUI.GAP_MD)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)


func refresh() -> void:
	for child: Node in _list.get_children():
		child.queue_free()
	var host: Gen2ModHost = Gen2ModHost.instance()
	var manifests: Array = host.manifests()
	var failures: Array = host.failures()
	_note.text = "Loaded from %s" % Gen2ModHost.ROOT

	if manifests.is_empty() and failures.is_empty():
		_list.add_child(_empty_state())
		return
	for manifest: Gen2ModManifest in manifests:
		_list.add_child(_row(manifest))
	for failure: Dictionary in failures:
		_list.add_child(_refusal(failure))


func _empty_state() -> Control:
	var panel: Gen2LauncherCard = Gen2LauncherCard.well(_theme, Gen2LauncherTheme.RADIUS_MD, 28)
	var box: VBoxContainer = Gen2LauncherUI.column(Gen2LauncherUI.GAP_SM)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	var icon: Gen2LauncherIcon = Gen2LauncherIcon.create(&"mods", 28.0, _theme.faint)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var line: Label = Gen2LauncherUI.muted(
		_theme, "No mods yet. Install a .zip, or browse the published index."
	)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(line)
	return panel


func _row(manifest: Gen2ModManifest) -> Control:
	var panel: Gen2LauncherCard = Gen2LauncherCard.create(_theme, Gen2LauncherTheme.RADIUS_MD, 18)
	var line: HBoxContainer = Gen2LauncherUI.row(Gen2LauncherUI.GAP_MD)
	panel.add_child(line)
	var text: VBoxContainer = Gen2LauncherUI.column(1)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(text)
	text.add_child(Gen2LauncherUI.body(_theme, manifest.name))
	text.add_child(Gen2LauncherUI.muted(_theme, "%s  %s" % [manifest.id, manifest.version]))
	# What it is for, so a player reads it before pressing Play rather than after
	# the mod refused to load. A mod that declares nothing is for every cartridge
	# and says nothing here.
	var titles: Array[String] = manifest.game_titles()
	if not titles.is_empty():
		text.add_child(Gen2LauncherUI.muted(_theme, "For %s" % ", ".join(titles)))

	var switch: Gen2LauncherToggle = Gen2LauncherToggle.create(
		_theme, Gen2ModState.is_enabled(manifest.id)
	)
	switch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	switch.toggled.connect(func(on: bool) -> void: _set_enabled(manifest, on))
	line.add_child(switch)

	var remove: Gen2LauncherButton = Gen2LauncherButton.icon_only(
		_theme, &"trash", Gen2LauncherButton.Variant.DANGER, 40.0
	)
	remove.tooltip_text = "Delete this mod"
	remove.pressed.connect(func() -> void: _delete(manifest))
	line.add_child(remove)

	# The mod's own settings, built from what it registered rather than from
	# anything written here, so this page and the game's MODS menu are the one
	# registration seen twice.
	for option: Dictionary in Gen2ModHost.instance().options(manifest.id):
		panel.add_child(_option_field(manifest.id, option))
	return panel


func _option_field(id: StringName, option: Dictionary) -> Control:
	var key: StringName = StringName(option.get("key", &""))
	return Gen2LauncherUI.field(_theme, String(option.get("label", "")), Gen2LauncherUI.segmented(
		_theme, option.get("labels", []) as Array, int(option.get("index", 0)),
		func(index: int) -> void:
			var result: Dictionary = Gen2ModHost.instance().set_option_index(id, key, index)
			if not bool(result.get("ok", false)):
				_fail(Gen2ModRefusal.text(result))
	))


func _refusal(failure: Dictionary) -> Control:
	var panel: Gen2LauncherCard = Gen2LauncherCard.well(_theme, Gen2LauncherTheme.RADIUS_MD, 18)
	var line: HBoxContainer = Gen2LauncherUI.row(Gen2LauncherUI.GAP_MD)
	panel.add_child(line)
	line.add_child(Gen2LauncherIcon.create(&"warning", 20.0, _theme.warning))
	var text: VBoxContainer = Gen2LauncherUI.column(1)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(text)
	text.add_child(Gen2LauncherUI.body(
		_theme, String(failure.get("directory", failure.get("id", "?")))
	))
	text.add_child(Gen2LauncherUI.muted(_theme, Gen2ModRefusal.text(failure)))
	return panel


func _set_enabled(manifest: Gen2ModManifest, on: bool) -> void:
	if not Gen2ModState.set_enabled(manifest.id, on):
		_fail("That switch could not be written to %s." % Gen2ModState.PATH)
		return
	_note.text = "%s is %s. Restart to apply." % [manifest.name, "on" if on else "off"]
	mods_changed.emit()


func _delete(manifest: Gen2ModManifest) -> void:
	if not bool(Gen2ModInstaller.uninstall(manifest.id).get("ok", false)):
		_fail("%s could not be removed." % manifest.name)
		return
	# Rediscover so the deleted mod leaves the list. What it already registered
	# this session stays until restart, which the message says.
	Gen2ModHost.instance().discover()
	_note.text = "%s was removed. Restart to apply." % manifest.name
	refresh()
	mods_changed.emit()


func _fail(message: String) -> void:
	_note.text = message
	_note.add_theme_color_override("font_color", _theme.error)
	Gen2LauncherAudio.play(&"error")
