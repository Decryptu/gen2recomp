class_name Gen2ModIndexDialog
extends AcceptDialog

## Browses a mod index and installs from it.
##
## The dialog owns the network and the presentation. Everything it decides
## comes from [Gen2ModIndex], and everything it installs goes through
## [Gen2ModInstaller] with the listed id required to match, so a feed cannot
## deliver a different mod than the one the player pressed.

const MUTED: Color = Color("#9eacc0")
const TEXT: Color = Color("#f4f7fb")
const ACCENT: Color = Color("#f3c969")
const SUCCESS: Color = Color("#7bd89a")
const ERROR: Color = Color("#ef8a8a")
## A feed and a mod archive are both small. This stops a hostile or broken
## server streaming forever into memory.
const MAX_DOWNLOAD_BYTES: int = 96 * 1024 * 1024

## Emitted after a mod is installed so the launcher can reload and relist.
signal mod_installed(id: StringName)

var _url_entry: LineEdit = null
var _sources: OptionButton = null
var _status: Label = null
var _entry_list: VBoxContainer = null
var _http: HTTPRequest = null
var _entries: Array[Dictionary] = []
var _pending_entry: Dictionary = {}
var _busy: bool = false


func _init() -> void:
	title = "Mod index"
	ok_button_text = "Close"
	min_size = Vector2i(640, 480)


func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.custom_minimum_size = Vector2(600, 420)
	add_child(root)

	var explain := Label.new()
	explain.text = (
		"An index lists mods hosted by their authors. Following one is trusting"
		+ " whoever publishes it; nothing is followed until you add it."
	)
	explain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explain.add_theme_color_override("font_color", MUTED)
	root.add_child(explain)

	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 8)
	root.add_child(add_row)

	_url_entry = LineEdit.new()
	_url_entry.placeholder_text = "owner/repo or https://..."
	_url_entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_url_entry.text_submitted.connect(func(_t: String) -> void: _on_follow_pressed())
	add_row.add_child(_url_entry)

	var follow := Button.new()
	follow.text = "Follow"
	follow.pressed.connect(_on_follow_pressed)
	add_row.add_child(follow)

	var source_row := HBoxContainer.new()
	source_row.add_theme_constant_override("separation", 8)
	root.add_child(source_row)

	_sources = OptionButton.new()
	_sources.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_row.add_child(_sources)

	var refresh := Button.new()
	refresh.text = "Open"
	refresh.pressed.connect(_on_open_pressed)
	source_row.add_child(refresh)

	var forget := Button.new()
	forget.text = "Forget"
	forget.pressed.connect(_on_forget_pressed)
	source_row.add_child(forget)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", MUTED)
	root.add_child(_status)

	var scroll: Gen2LauncherScroll = Gen2LauncherScroll.create()
	root.add_child(scroll)

	_entry_list = VBoxContainer.new()
	_entry_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entry_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_entry_list)

	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.body_size_limit = MAX_DOWNLOAD_BYTES
	add_child(_http)

	_refresh_sources()


## Reloads the followed list, so the dialog reflects a source added last time.
func refresh() -> void:
	_refresh_sources()


func _refresh_sources() -> void:
	_sources.clear()
	for row: Dictionary in Gen2ModIndex.followed():
		_sources.add_item(String(row["label"]))
		_sources.set_item_metadata(_sources.item_count - 1, row["feed"])
	if _sources.item_count == 0:
		_set_status("No index followed yet. Add one above.", MUTED)


func _on_follow_pressed() -> void:
	var result: Dictionary = Gen2ModIndex.follow(_url_entry.text)
	if not bool(result.get("ok", false)):
		_set_status(_reason_text(result), ERROR)
		return
	_url_entry.text = ""
	_refresh_sources()
	for index: int in _sources.item_count:
		if _sources.get_item_metadata(index) == result["feed"]:
			_sources.select(index)
			break
	_set_status("Following %s." % result["label"], SUCCESS)
	_on_open_pressed()


func _on_forget_pressed() -> void:
	if _sources.selected < 0:
		return
	Gen2ModIndex.unfollow(String(_sources.get_item_metadata(_sources.selected)))
	_clear_entries()
	_refresh_sources()
	_set_status("Stopped following that index.", MUTED)


func _on_open_pressed() -> void:
	if _busy or _sources.selected < 0:
		return
	var feed: String = String(_sources.get_item_metadata(_sources.selected))
	_clear_entries()
	_set_status("Reading %s..." % feed, MUTED)
	_request(feed, _on_feed_received)


func _on_feed_received(
	result: int, code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_set_status("That index could not be read (HTTP %d)." % code, ERROR)
		return
	var parsed: Dictionary = Gen2ModIndex.parse_feed(body.get_string_from_utf8())
	if not bool(parsed.get("ok", false)):
		_set_status(_reason_text(parsed), ERROR)
		return
	_entries.assign(parsed["entries"])
	_show_entries()
	var name: String = String(parsed.get("name", ""))
	_set_status(
		"%s lists %d mod%s." % [
			name if not name.is_empty() else "That index",
			_entries.size(), "" if _entries.size() == 1 else "s",
		],
		MUTED,
	)


func _show_entries() -> void:
	_clear_entries()
	var installed: Dictionary = {}
	for manifest: Gen2ModManifest in Gen2ModHost.instance().manifests():
		installed[manifest.id] = manifest.version
	for entry: Dictionary in _entries:
		_entry_list.add_child(_entry_row(entry, installed))


func _entry_row(entry: Dictionary, installed: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)

	var name := Label.new()
	var version: String = String(entry.get("version", ""))
	name.text = "%s%s" % [entry["name"], "" if version.is_empty() else "  %s" % version]
	name.add_theme_color_override("font_color", TEXT)
	text.add_child(name)

	var description: String = String(entry.get("description", ""))
	if not description.is_empty():
		var detail := Label.new()
		detail.text = description
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.add_theme_color_override("font_color", MUTED)
		text.add_child(detail)

	var button := Button.new()
	var have: bool = installed.has(entry["id"])
	button.text = "Reinstall" if have else "Install"
	button.pressed.connect(_on_install_pressed.bind(entry, have))
	row.add_child(button)
	return row


func _on_install_pressed(entry: Dictionary, replace: bool) -> void:
	if _busy:
		return
	_pending_entry = entry.duplicate(true)
	_pending_entry["replace"] = replace
	_set_status("Downloading %s..." % entry["name"], MUTED)
	_request(String(entry["download"]), _on_download_received)


func _on_download_received(
	result: int, code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	_busy = false
	var entry: Dictionary = _pending_entry
	_pending_entry = {}
	if entry.is_empty():
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_set_status("%s could not be downloaded (HTTP %d)." % [entry["name"], code], ERROR)
		return
	install_entry_bytes(entry, body)


## Installs a downloaded archive for [param entry]. Separate from the request
## handler so the decision this makes can be tested without a server: the listed
## id must match, because a feed names what it is offering and a download that
## turns out to be another mod is exactly what this refuses.
func install_entry_bytes(entry: Dictionary, body: PackedByteArray) -> Dictionary:
	var installed: Dictionary = Gen2ModInstaller.install_bytes(
		body, bool(entry.get("replace", false)), StringName(entry["id"])
	)
	if not bool(installed.get("ok", false)):
		_set_status(
			"%s was not installed: %s" % [entry.get("name", entry["id"]), _reason_text(installed)],
			ERROR,
		)
		return installed
	_set_status("Installed %s." % installed.get("name", entry.get("name", "")), SUCCESS)
	mod_installed.emit(StringName(installed["id"]))
	_show_entries()
	return installed


## The status line, for a test that wants to read what the player would see.
func status_text() -> String:
	return _status.text


func _request(url: String, handler: Callable) -> void:
	if not Gen2ModIndex.is_downloadable(url):
		_set_status("That address is not an https URL.", ERROR)
		return
	for connection: Dictionary in _http.request_completed.get_connections():
		_http.request_completed.disconnect(connection["callable"])
	_http.request_completed.connect(handler, CONNECT_ONE_SHOT)
	_busy = true
	if _http.request(url) != OK:
		_busy = false
		_set_status("Could not reach %s." % url, ERROR)


func _clear_entries() -> void:
	for child: Node in _entry_list.get_children():
		child.queue_free()


func _set_status(text: String, colour: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", colour)


func _reason_text(result: Dictionary) -> String:
	return Gen2ModRefusal.text(result)
