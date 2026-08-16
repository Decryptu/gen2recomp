extends Control

## The launcher: a shelf of cartridges, plus the mods, settings and about pages
## reachable from the dock under it.
##
## It owns presentation and workflow, while the ROM and cache layers remain
## responsible for verification and decoding. Everything it draws is built in
## code from [Gen2LauncherShell] and the cards under it, so changing the
## appearance is a rebuild rather than a repaint.

var _palette: Gen2LauncherTheme = null
var _shell: Gen2LauncherShell = null
var _shelf: Gen2ShelfPage = null
var _mods: Gen2ModsPage = null
var _settings: Gen2SettingsPage = null
var _about: Gen2AboutPage = null
var _title_backdrop: Gen2LauncherTitleBackdrop = null

var _file_dialog: FileDialog = null
var _mod_dialog: FileDialog = null
var _update_http: HTTPRequest = null

var _importing: bool = false
var _selected_game_id: StringName = &""
## The game a re-import is replacing, so a cache is only overwritten by a dump
## of the cartridge it already holds.
var _reimport_game_id: StringName = &""
var _status: Dictionary = {"title": "", "detail": ""}


func _ready() -> void:
	_palette = Gen2LauncherTheme.active()
	_build()
	_print_allowlist()
	_refresh_games()


## Rebuilt whole when the appearance changes, which is the only way a launcher
## drawn entirely in code can switch palette without every widget growing a
## repaint path of its own.
func _build() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	theme = _palette.control_theme()

	_shell = Gen2LauncherShell.create(_palette)
	add_child(_shell)
	_title_backdrop = Gen2LauncherTitleBackdrop.new()
	add_child(_title_backdrop)

	_shelf = Gen2ShelfPage.create(_palette, _shell.compact)
	_shelf.insert_requested.connect(_open_import_dialog)
	_shelf.play_requested.connect(_launch_game)
	_shelf.manage_requested.connect(_open_manage_sheet)
	_shelf.selection_changed.connect(_on_cartridge_selected)
	_shell.add_page(&"shelf", "Play", &"shelf", _shelf)

	_mods = Gen2ModsPage.create(_palette, self)
	_mods.install_requested.connect(_open_mod_dialog)
	_shell.add_page(&"mods", "Mods", &"mods", _mods)

	_settings = Gen2SettingsPage.create(_palette, self)
	_settings.appearance_changed.connect(_reload_appearance)
	_shell.add_page(&"settings", "Settings", &"settings", _settings)

	_about = Gen2AboutPage.create(_palette)
	_about.update_check_requested.connect(check_for_updates)
	_shell.add_page(&"about", "About", &"about", _about)

	_shell.page_selected.connect(_on_page_selected)
	_build_dialogs()
	_on_page_selected(_shell.current_page())
	# A message survives a palette rebuild; a launcher with nothing to report
	# shows nothing at all.
	if not String(_status["title"]).is_empty():
		_set_status(&"info", String(_status["title"]), String(_status["detail"]))


func _build_dialogs() -> void:
	_file_dialog = _picker(
		"Choose a cartridge dump",
		PackedStringArray(["*.gbc; Cartridge dump", "*.gb; Cartridge dump"]),
	)
	_file_dialog.file_selected.connect(_on_file_selected)

	_mod_dialog = _picker("Choose a mod .zip", PackedStringArray(["*.zip; Mod archive"]))
	_mod_dialog.file_selected.connect(func(path: String) -> void: import_mod_path(path))

	# Created once and reused. The check only ever runs from the button.
	_update_http = HTTPRequest.new()
	_update_http.request_completed.connect(_on_update_response)
	add_child(_update_http)

	# A window drop is the same import, so the OS file manager works wherever it
	# offers one. Routing is by extension because the two imports validate very
	# differently and neither should be handed the other's file.
	var window: Window = get_window()
	if not window.files_dropped.is_connected(_on_files_dropped):
		window.files_dropped.connect(_on_files_dropped)


func _picker(title: String, filters: PackedStringArray) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = filters
	dialog.title = title
	# Android's own picker is the only one that returns a readable file: the app
	# declares no storage permission, so a path the built-in browser lists still
	# fails to open. The system picker grants access to the one file chosen.
	dialog.use_native_dialog = DisplayServer.has_feature(
		DisplayServer.FEATURE_NATIVE_DIALOG_FILE
	)
	dialog.theme = _palette.control_theme()
	add_child(dialog)
	return dialog


func _reload_appearance() -> void:
	_palette = Gen2LauncherTheme.active()
	_build()
	_refresh_games()


func _on_cartridge_selected(_game_id: StringName) -> void:
	_refresh_backdrop()


## Only the shelf is dressed in a cartridge's artwork. Behind a page of cards the
## same picture reads as a stain rather than as a backdrop.
func _on_page_selected(_id: StringName) -> void:
	_refresh_backdrop()


## The selected cartridge's artwork, and only once that cartridge is imported: an
## empty bay would otherwise advertise a game the player cannot start.
func _refresh_backdrop() -> void:
	var game_id: StringName = _shelf.selected_id()
	var seated: Gen2Cartridge = _shelf.cartridge(game_id)
	var showing: bool = (
		_shell.current_page() == &"shelf" and seated != null and seated.imported
	)
	if not showing:
		_title_backdrop.hide_backdrop()
		_shell.set_backdrop_art(null)
		return
	var data: GameData = GameData.open(game_id)
	var title_texture: Texture2D = _title_backdrop.show_game(data)
	if title_texture != null:
		_shell.set_backdrop_art(title_texture, true)
	else:
		# A legacy cache without imported title art gets the neutral page rather
		# than carrying a second set of authored background images in the build.
		_shell.set_backdrop_art(null)


func _refresh_games() -> void:
	for game_id: StringName in RomRegistry.ORDER:
		var data: GameData = GameData.open(game_id)
		_shelf.set_slot_state(game_id, data != null, _cartridge_detail(game_id, data))
	_shelf.set_busy(_importing)
	_refresh_backdrop()


func _cartridge_detail(game_id: StringName, data: GameData) -> String:
	if data == null:
		return ""
	var slots: Array = Gen2SaveStore.slots_for(game_id, data.sha1, data)
	var ready_slots: int = 0
	for row: Dictionary in slots:
		if row["valid"]:
			ready_slots += 1
	if slots.is_empty():
		return "Ready. No saves yet"
	return "Ready. %d save%s" % [ready_slots, "" if ready_slots == 1 else "s"]


## Public driver used by tests and by non-interactive tooling.
func import_rom_path(path: String) -> void:
	_on_file_selected(path)


## Installs a mod archive and loads it without a restart, which is safe here
## because the launcher is the one screen that exists before any world or
## battle has been built. Public for the same reason [method import_rom_path]
## is: a test drives the import without going through a native dialog.
func import_mod_path(path: String, replace: bool = false) -> Dictionary:
	var result: Dictionary = Gen2ModInstaller.install_zip(path, replace)
	if bool(result.get("ok", false)):
		GameRuntime.load_mods()
		_mods.refresh()
		_set_status(
			&"success",
			"Installed %s." % result.get("name", result.get("id", "the mod")),
			"%d files in %s." % [int(result.get("files", 0)), result.get("directory", "")],
		)
		return result
	if StringName(result.get("reason", &"")) == &"already_installed":
		_confirm_mod_replace(path, String(result.get("detail", "That mod")))
		return result
	_set_status(&"error", "That mod was not installed.", Gen2ModRefusal.text(result))
	return result


func _confirm_mod_replace(path: String, name: String) -> void:
	var sheet: Gen2LauncherSheet = Gen2LauncherSheet.create(_palette, "Replace mod")
	sheet.body().add_child(Gen2LauncherUI.muted(
		_palette, "%s is already installed. Replace it with this archive?" % name
	))
	var replace: Gen2LauncherButton = Gen2LauncherButton.create(
		_palette, "Replace", Gen2LauncherButton.Variant.PRIMARY
	)
	replace.pressed.connect(func() -> void:
		sheet.close()
		import_mod_path(path, true)
	)
	sheet.add_action(replace)
	sheet.open(self)


func _open_mod_dialog() -> void:
	if _importing:
		return
	_mod_dialog.popup_centered(Vector2i(920, 620))


## Asks the release API what the latest version is. Public so a test can drive
## the request path without a button press.
func check_for_updates() -> void:
	if _importing or _update_http == null:
		return
	_about.set_update_result("Checking...", _palette.muted)
	_set_status(&"busy", "Checking for updates...", Gen2UpdateCheck.RELEASES_API)
	var headers: PackedStringArray = PackedStringArray([
		"Accept: application/vnd.github+json",
	])
	if _update_http.request(Gen2UpdateCheck.RELEASES_API, headers) != OK:
		_set_status(&"error", "The update check could not start.", "No request was made.")


func _on_update_response(
	result: int, code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		var offline: String = "This build is %s." % Gen2UpdateCheck.current_version()
		_about.set_update_result("The check did not reach the network.", _palette.error)
		_set_status(&"error", "The update check did not reach the network.", offline)
		return
	var status: Dictionary = Gen2UpdateCheck.status_for(code, body.get_string_from_utf8())
	var kind: StringName = &"info"
	var colour: Color = _palette.muted
	match int(status["status"]):
		Gen2UpdateCheck.Status.UPDATE_AVAILABLE:
			kind = &"info"
			colour = _palette.accent
		Gen2UpdateCheck.Status.UP_TO_DATE:
			kind = &"success"
			colour = _palette.success
		Gen2UpdateCheck.Status.UNREADABLE:
			kind = &"error"
			colour = _palette.error
	var message: String = Gen2UpdateCheck.describe(status)
	_about.set_update_result(message, colour)
	_set_status(kind, message, String(status.get("url", Gen2UpdateCheck.RELEASES_PAGE)))


func _open_manage_sheet(game_id: StringName) -> void:
	if _importing:
		return
	var path: String = RomCache.directory_for(game_id, RomRegistry.sha1_for(game_id))
	var state: StringName = RomCache.state(path)
	var sheet: Gen2LauncherSheet = Gen2LauncherSheet.create(
		_palette, RomRegistry.title_for(game_id)
	)
	var body: VBoxContainer = sheet.body()
	body.add_child(Gen2LauncherUI.muted(_palette, cache_state_text(state)))
	var directory: Label = Gen2LauncherUI.muted(_palette, path)
	directory.add_theme_color_override("font_color", _palette.faint)
	body.add_child(directory)

	# Off the state rather than off the data: a stale or half-written cache is
	# exactly the one worth opening or deleting, and neither can be read.
	if state != RomCache.STATE_MISSING:
		var open_folder: Gen2LauncherButton = Gen2LauncherButton.create(
			_palette, "Open cache folder", Gen2LauncherButton.Variant.NEUTRAL, &"folder"
		)
		open_folder.pressed.connect(func() -> void: _open_cache_folder(game_id))
		body.add_child(open_folder)
		var delete: Gen2LauncherButton = Gen2LauncherButton.create(
			_palette, "Delete cache", Gen2LauncherButton.Variant.DANGER, &"trash"
		)
		delete.pressed.connect(func() -> void:
			sheet.close()
			_delete_cache(game_id)
		)
		body.add_child(delete)

	var reimport: Gen2LauncherButton = Gen2LauncherButton.create(
		_palette,
		"Re-import" if state != RomCache.STATE_MISSING else "Import",
		Gen2LauncherButton.Variant.PRIMARY,
		&"download",
	)
	reimport.pressed.connect(func() -> void:
		_reimport_game_id = game_id
		sheet.close()
		_open_import_dialog()
	)
	sheet.add_action(reimport)
	sheet.open(self)


## What the manage sheet says about a cache in [param state]. Takes the state
## rather than a cartridge so the four sentences can be asserted without a cache
## on disk to put a build's own cartridges at risk.
##
## A cache is never migrated ([constant RomCache.FORMAT_VERSION]), so a build
## that has moved on says so and asks for the dump again rather than reporting
## the cartridge as never imported.
static func cache_state_text(state: StringName) -> String:
	match state:
		RomCache.STATE_USABLE:
			return "This cartridge is imported and verified."
		RomCache.STATE_STALE:
			return "This cache was written by an older build. Import the cartridge again."
		RomCache.STATE_INCOMPLETE:
			return "The last import did not finish. Import the cartridge again."
	return "No cache exists for this cartridge yet."


func _open_cache_folder(game_id: StringName) -> void:
	var directory: String = RomCache.directory_for(game_id, RomRegistry.sha1_for(game_id))
	OS.shell_open(ProjectSettings.globalize_path(directory))


## Removes the decoded cartridge data and nothing else. Saves live under their
## own root, so deleting a cache costs an import and no player progress.
func _delete_cache(game_id: StringName) -> void:
	RomCache.clear(RomCache.directory_for(game_id, RomRegistry.sha1_for(game_id)))
	if _selected_game_id == game_id:
		_selected_game_id = &""
	var seated: Gen2Cartridge = _shelf.cartridge(game_id)
	if seated != null and seated.imported:
		await seated.play_eject()
	_set_status(
		&"info",
		"Removed the %s cache." % RomRegistry.title_for(game_id),
		"Your saves were not touched. Import the cartridge again to play.",
	)
	_refresh_games()


func _on_files_dropped(files: PackedStringArray) -> void:
	if _importing:
		return
	for path: String in files:
		match path.get_extension().to_lower():
			"zip":
				import_mod_path(path)
				return
			"gb", "gbc":
				_on_file_selected(path)
				return
	_set_status(
		&"error",
		"Nothing to import there.",
		"Drop a .gb or .gbc cartridge dump, or a mod .zip.",
	)


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
		"status": String(_status["title"]),
		"detail": String(_status["detail"]),
		"importing": _importing,
		"page": String(_shell.current_page()) if _shell != null else "",
		"theme": String(_palette.mode),
		"games": games,
	}


## Opens one of the launcher's pages by id. Public so a preview or a test can
## photograph a page without clicking its navigation entry.
func select_page(id: StringName) -> void:
	if _shell != null:
		_shell.select(id)


## Preview seam: shows the shelf as if these cartridges were imported, so the
## empty and full states can be photographed on one machine. Changes nothing on
## disk and is never called by the launcher itself.
func preview_slot_states(states: Dictionary) -> void:
	for game_id: StringName in RomRegistry.ORDER:
		var imported: bool = bool(states.get(String(game_id), false))
		_shelf.set_slot_state(game_id, imported, "Ready. 2 saves" if imported else "")
	_refresh_backdrop()


## Preview seam: opens one of the mods page's own views, so a mod's page and
## the sources page can be photographed without a press.
func preview_mods_view(view: StringName, id: StringName = &"") -> void:
	select_page(&"mods")
	match view:
		&"mod":
			_mods.open_mod(id)
		&"sources":
			_mods.open_sources()
		_:
			_mods.show_list()


## Preview seam: opens a real launcher sheet without synthesising a pointer
## press, so visual checks can photograph every menu consistently.
func preview_sheet(view: StringName) -> void:
	match view:
		&"manage":
			select_page(&"shelf")
			_open_manage_sheet(_shelf.selected_id())
		&"touch":
			select_page(&"settings")
			_settings._open_touch_layout()
		&"binding":
			select_page(&"settings")
			var sheet: Gen2BindingSheet = Gen2BindingSheet.for_button(
				_palette, Gen2OptionsStore.current(), Gen2Button.A
			)
			sheet.open(self)
		&"delete_mod":
			select_page(&"mods")
			var row: Dictionary = _mods._row_for(&"voxel_preview")
			if not row.is_empty():
				_mods.remove_mod(row)


## Preview seam: switches appearance without writing the options file.
func preview_theme(wanted: StringName) -> void:
	_palette = Gen2LauncherTheme.for_mode(wanted)
	_build()
	_refresh_games()


## Seats the cartridge, then opens its save slots. The animation runs before the
## scene change so the sound and the movement both finish on this screen.
func _launch_game(game_id: StringName) -> void:
	if _importing:
		return
	var data: GameData = GameData.open(game_id)
	if data == null:
		_open_import_dialog()
		return
	if not GameRuntime.select_game(game_id):
		_set_status(
			&"error",
			"Could not select %s." % RomRegistry.title_for(game_id),
			"The registry did not recognise that cartridge.",
		)
		return
	_selected_game_id = game_id
	_set_status(&"success", "Starting %s." % RomRegistry.title_for(game_id), "")
	_shelf.set_busy(true)
	var seated: Gen2Cartridge = _shelf.cartridge(game_id)
	if seated != null:
		await seated.play_start()
	await _shell.flash()
	get_tree().change_scene_to_file.call_deferred("res://game/save/save_screen.tscn")


func _open_import_dialog(_game_id: StringName = &"") -> void:
	if _importing:
		return
	_set_status(
		&"info",
		"Choose a cartridge dump.",
		"The importer identifies the cartridge by SHA-1, never by filename.",
	)
	_file_dialog.popup_centered(Vector2i(920, 620))


func _on_file_selected(path: String) -> void:
	if _importing:
		return
	_importing = true
	_shelf.set_busy(true)
	_shell.toast().set_progress(true, 0.0)
	_set_status(&"busy", "Verifying cartridge...", path.get_file())

	var identity: Dictionary = RomVerifier.identify(path)
	if identity["status"] != RomVerifier.Status.OK:
		_finish_import(false, String(identity["message"]))
		return

	# A re-import replaces one cartridge's cache, so it only accepts that
	# cartridge's own dump. Without this, choosing the wrong file from the
	# manage sheet would quietly import a different one instead of saying so.
	if not _reimport_game_id.is_empty() and StringName(identity["id"]) != _reimport_game_id:
		var wanted: StringName = _reimport_game_id
		_reimport_game_id = &""
		_finish_import(false, "That dump is %s, not %s." % [
			RomRegistry.title_for(StringName(identity["id"])), RomRegistry.title_for(wanted),
		])
		return
	_reimport_game_id = &""

	var rom: RomFile = RomFile.open_verified(path)
	if rom == null:
		_finish_import(false, "The verified cartridge could not be read.")
		return

	_set_status(&"busy", "Checking table layout...", path.get_file())
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
	_finish_import(true, "%d species and %d trainer classes are ready." % [
		int(result["species"]), int(result["trainers"]),
	])
	_refresh_games()
	_shelf.focus_game(game_id)
	var seated: Gen2Cartridge = _shelf.cartridge(game_id)
	if seated != null:
		seated.play_insert()


func _on_import_progress(stage: String, done: int, total: int) -> void:
	if total > 0:
		_shell.toast().set_progress(true, float(done) / float(total) * 100.0)
	_set_status(&"busy", "%s, %d/%d" % [stage.capitalize(), done, total], "")


func _finish_import(success: bool, message: String) -> void:
	_importing = false
	_shelf.set_busy(false)
	_shell.toast().set_progress(false)
	if not success:
		Gen2LauncherAudio.play(&"error")
	_set_status(
		&"success" if success else &"error",
		"Import complete." if success else "Import stopped.",
		message,
	)


func _set_status(kind: StringName, title: String, detail: String) -> void:
	_status = {"title": title, "detail": detail}
	if _shell != null:
		_shell.toast().show_message(kind, title, detail)


func _print_allowlist() -> void:
	var lines: PackedStringArray = []
	for id: StringName in RomRegistry.ORDER:
		lines.append("  %-8s %s" % [RomRegistry.title_for(id), RomRegistry.sha1_for(id)])
	print("pokerecomp supported cartridges:")
	print("\n".join(lines))
