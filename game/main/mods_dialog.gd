class_name Gen2ModsDialog
extends AcceptDialog

## Lists installed mods with an on/off switch and a delete, beside the refusals
## the host recorded. Installing lives on the launcher itself, next to the ROM
## import that works the same way.
##
## Switching one off takes effect on the next start, which the dialog says
## rather than pretending a running registration can be withdrawn: a mod has
## already registered its content and renderers by the time this is reachable.

signal mods_changed

var _list: VBoxContainer = null
var _status: Label = null


func _init() -> void:
	title = "Mods"
	ok_button_text = "Close"
	_build()


func _build() -> void:
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(560, 320)
	add_child(root)

	var actions := HBoxContainer.new()
	root.add_child(actions)
	actions.add_child(_action("Enable all", func() -> void: _set_all(true)))
	actions.add_child(_action("Disable all", func() -> void: _set_all(false)))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)


func refresh() -> void:
	for child: Node in _list.get_children():
		child.queue_free()
	var host: Gen2ModHost = Gen2ModHost.instance()
	var manifests: Array = host.manifests()
	if manifests.is_empty() and host.failures().is_empty():
		_list.add_child(_text("No mods installed. Put one in %s to load it at start." % Gen2ModHost.ROOT))
		return

	for manifest: Gen2ModManifest in manifests:
		_list.add_child(_row(manifest))
	for failure: Dictionary in host.failures():
		_list.add_child(_text("%s was refused: %s" % [
			failure.get("directory", failure.get("id", "?")),
			Gen2ModRefusal.text(failure),
		]))


func _row(manifest: Gen2ModManifest) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name := Label.new()
	name.text = "%s  %s" % [manifest.name, manifest.version]
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)

	var toggle := CheckBox.new()
	toggle.text = "Enabled"
	toggle.button_pressed = Gen2ModState.is_enabled(manifest.id)
	toggle.toggled.connect(func(on: bool) -> void: _set_enabled(manifest, on))
	row.add_child(toggle)

	row.add_child(_action("Delete", func() -> void: _delete(manifest)))
	return row


func _set_enabled(manifest: Gen2ModManifest, enabled: bool) -> void:
	if not Gen2ModState.set_enabled(manifest.id, enabled):
		_status.text = "That switch could not be written to %s." % Gen2ModState.PATH
		return
	_status.text = "%s is %s. Restart to apply." % [
		manifest.name, "enabled" if enabled else "disabled",
	]
	mods_changed.emit()


func _set_all(enabled: bool) -> void:
	var ids: Array = []
	for manifest: Gen2ModManifest in Gen2ModHost.instance().manifests():
		ids.append(manifest.id)
	if ids.is_empty():
		return
	if not Gen2ModState.set_all_enabled(ids, enabled):
		_status.text = "Those switches could not be written to %s." % Gen2ModState.PATH
		return
	_status.text = "All mods %s. Restart to apply." % ("enabled" if enabled else "disabled")
	refresh()
	mods_changed.emit()


func _delete(manifest: Gen2ModManifest) -> void:
	var result: Dictionary = Gen2ModInstaller.uninstall(manifest.id)
	if not bool(result.get("ok", false)):
		_status.text = "%s could not be removed." % manifest.name
		return
	# Rediscover so the removed mod leaves the list; what it already registered
	# this session stays until restart, which the message above says.
	Gen2ModHost.instance().discover()
	_status.text = "%s was removed. Restart to apply." % manifest.name
	refresh()
	mods_changed.emit()


func _text(message: String) -> Label:
	var label := Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _action(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(handler)
	return button
