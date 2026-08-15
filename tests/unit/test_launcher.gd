extends GutTest

## Launcher tests use the real scene and synthetic rejected files. They never
## import a cartridge or create cartridge-derived data.

var _launcher: Control = null
var _scratch_path: String = "user://launcher-test-small.gbc"
var _mod_archive: String = "user://launcher-test-mod.zip"

## The launcher installs into the real user://mods, so a mod test cleans up
## after itself whether or not it got that far.
const PROBE_MOD_ID: StringName = &"launcher_probe"


func after_each() -> void:
	if is_instance_valid(_launcher):
		_launcher.free()
	_launcher = null
	# A palette change rebuilds the launcher by detaching the old shell and
	# queueing it, so freeing the root leaves that one pending until a frame
	# runs the deletion queue.
	await get_tree().process_frame
	DirAccess.remove_absolute(_scratch_path)
	DirAccess.remove_absolute(_mod_archive)
	Gen2ModInstaller.uninstall(PROBE_MOD_ID)


## The mods page on its own, which is what every mod workflow but the file
## picker lives on. Built outside the launcher because none of it needs one.
func _mods_page() -> Gen2ModsPage:
	var page: Gen2ModsPage = Gen2ModsPage.create(Gen2LauncherTheme.active())
	add_child_autofree(page)
	return page


func _open_launcher() -> void:
	var packed: PackedScene = load("res://game/main/main.tscn")
	_launcher = packed.instantiate()
	add_child(_launcher)
	await get_tree().process_frame


func test_launcher_lists_every_supported_game() -> void:
	await _open_launcher()
	var snapshot: Dictionary = _launcher.launcher_snapshot()
	var games: Dictionary = snapshot["games"]

	assert_eq(games.size(), RomRegistry.ORDER.size())
	for game_id: StringName in RomRegistry.ORDER:
		var row: Dictionary = games[String(game_id)]
		assert_eq(row["title"], RomRegistry.title_for(game_id))
		assert_true(row["imported"] is bool)
		assert_false(row["selected"])


func test_launcher_opens_on_the_shelf_and_moves_between_its_pages() -> void:
	await _open_launcher()
	assert_eq(_launcher.launcher_snapshot()["page"], "shelf")
	for page: String in ["mods", "settings", "about", "shelf"]:
		_launcher.select_page(StringName(page))
		assert_eq(_launcher.launcher_snapshot()["page"], page)
	# An unknown id leaves the current page alone rather than blanking it.
	_launcher.select_page(&"nowhere")
	assert_eq(_launcher.launcher_snapshot()["page"], "shelf")


func test_switching_appearance_rebuilds_the_launcher_and_keeps_its_status() -> void:
	await _open_launcher()
	var before: Dictionary = _launcher.launcher_snapshot()
	# Whichever appearance this machine's options file holds. Naming one would
	# assert the tester's own preference rather than the switch.
	var opened := StringName(before["theme"])
	assert_true(Gen2LauncherTheme.MODES.has(opened), String(opened))

	var wanted: StringName = Gen2LauncherTheme.for_mode(opened).other_mode()
	_launcher.preview_theme(wanted)
	var after: Dictionary = _launcher.launcher_snapshot()
	assert_eq(after["theme"], String(wanted))
	# The shelf is rebuilt whole, so the message on it has to be carried over.
	assert_eq(after["status"], before["status"])
	assert_eq(after["detail"], before["detail"])
	assert_eq(after["page"], before["page"])


func test_launcher_reports_a_rejected_rom_without_importing() -> void:
	await _open_launcher()
	var file: FileAccess = FileAccess.open(_scratch_path, FileAccess.WRITE)
	var bytes := PackedByteArray()
	bytes.resize(1024)
	file.store_buffer(bytes)
	file.close()

	_launcher.import_rom_path(_scratch_path)
	var snapshot: Dictionary = _launcher.launcher_snapshot()

	assert_eq(snapshot["status"], "Import stopped.")
	assert_string_contains(snapshot["detail"], "bytes")
	assert_false(snapshot["importing"])


func test_runtime_selection_accepts_registry_games_and_rejects_unknown_ids() -> void:
	var previous: StringName = GameRuntime.selected_game_id
	var previous_slot: int = GameRuntime.selected_save_slot

	assert_true(GameRuntime.select_game(RomRegistry.CRYSTAL))
	assert_eq(GameRuntime.selected_game_id, RomRegistry.CRYSTAL)
	assert_true(GameRuntime.select_save_slot(RomRegistry.CRYSTAL, 1))
	assert_true(GameRuntime.has_selected_save_slot())
	assert_eq(GameRuntime.selected_save_slot, 1)
	assert_false(GameRuntime.select_game(&"not_a_game"))
	assert_eq(GameRuntime.selected_game_id, RomRegistry.CRYSTAL)
	assert_false(GameRuntime.select_save_slot(RomRegistry.CRYSTAL, Gen2SaveStore.MAX_SLOTS))
	assert_eq(GameRuntime.selected_save_slot, 1)

	GameRuntime.selected_game_id = previous
	GameRuntime.selected_save_slot = previous_slot
	GameRuntime.reload_selected_save()


func test_the_selected_save_is_one_shared_instance_until_the_selection_changes() -> void:
	var previous: StringName = GameRuntime.selected_game_id
	var previous_slot: int = GameRuntime.selected_save_slot
	var data: GameData = GameData.open_any()
	if data == null:
		pass_test("No imported cache on this machine.")
		return

	assert_true(GameRuntime.select_save_slot(data.id, 0))
	var save: Gen2SaveData = GameRuntime.selected_save()
	if save == null:
		pass_test("Slot 0 of the imported cache is empty.")
	else:
		# Two readers must see one save, or a party change made by a battle is
		# invisible to whoever writes the world snapshot.
		assert_same(save, GameRuntime.selected_save())
		GameRuntime.reload_selected_save()
		assert_not_same(save, GameRuntime.selected_save())

	GameRuntime.selected_game_id = previous
	GameRuntime.selected_save_slot = previous_slot
	GameRuntime.reload_selected_save()


func _write_probe_mod_zip() -> void:
	var packer := ZIPPacker.new()
	assert_eq(packer.open(_mod_archive), OK)
	var files: Dictionary = {
		"%s/mod.json" % PROBE_MOD_ID: JSON.stringify({
			"id": String(PROBE_MOD_ID), "name": "Launcher Probe", "version": "1.0.0",
			"api_version": Gen2ModManifest.API_VERSION, "entry": "mod.gd",
		}),
		"%s/mod.gd" % PROBE_MOD_ID:
			"extends RefCounted\n\nfunc register(_h, _m) -> void:\n\tpass\n",
	}
	for entry: String in files:
		packer.start_file(entry)
		packer.write_file(String(files[entry]).to_utf8_buffer())
		packer.close_file()
	packer.close()


func test_launcher_installs_a_mod_zip_and_lists_it_without_a_restart() -> void:
	await _open_launcher()
	_write_probe_mod_zip()

	var result: Dictionary = _launcher.import_mod_path(_mod_archive)
	assert_true(result["ok"], JSON.stringify(result))
	assert_eq(result["id"], PROBE_MOD_ID)
	# Loaded into the live host, not merely written to disk.
	assert_true(Gen2ModHost.instance().manifests().any(
		func(manifest: Gen2ModManifest) -> bool: return manifest.id == PROBE_MOD_ID
	))
	assert_string_contains(_launcher.launcher_snapshot()["status"], "Launcher Probe")


func test_launcher_reports_a_file_that_is_not_a_mod_archive() -> void:
	await _open_launcher()
	var file: FileAccess = FileAccess.open(_mod_archive, FileAccess.WRITE)
	file.store_string("not an archive")
	file.close()

	var result: Dictionary = _launcher.import_mod_path(_mod_archive)
	assert_false(result["ok"])
	assert_eq(result["reason"], &"not_a_zip")
	var snapshot: Dictionary = _launcher.launcher_snapshot()
	assert_eq(snapshot["status"], "That mod was not installed.")
	assert_string_contains(snapshot["detail"], "not a .zip archive")


func test_index_install_requires_the_download_to_be_the_listed_mod() -> void:
	_write_probe_mod_zip()
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(_mod_archive)
	var page: Gen2ModsPage = _mods_page()

	# A source offering one mod cannot deliver another.
	var wrong: Dictionary = page.install_entry_bytes(
		{"id": &"something_else", "name": "Something Else"}, bytes
	)
	assert_false(wrong["ok"])
	assert_eq(wrong["reason"], &"unexpected_mod_id")
	assert_string_contains(page.status_text(), "different mod")

	var right: Dictionary = page.install_entry_bytes(
		{"id": PROBE_MOD_ID, "name": "Launcher Probe"}, bytes
	)
	assert_true(right["ok"], JSON.stringify(right))
	assert_eq(right["id"], PROBE_MOD_ID)
	assert_string_contains(page.status_text(), "Installed")


## A server that is down costs the freshness of a listing rather than the
## listing: the last feed that parsed is kept and shown, with the player told
## which copy they are looking at.
func test_a_source_that_cannot_be_read_falls_back_to_the_copy_on_disk() -> void:
	var feed: String = "https://mods.example.com/index.json"
	var page: Gen2ModsPage = _mods_page()

	var text: String = JSON.stringify({
		"schema_version": Gen2ModIndex.SCHEMA_VERSION,
		"name": "Example",
		"mods": [{"id": "voxel", "name": "Voxel", "version": "1.2.0",
			"download": "https://example.com/voxel.zip"}],
	})
	assert_true(bool(page.receive_feed_response(feed, true, text).get("ok", false)))
	assert_string_contains(page.status_text(), "lists 1 mod")

	page.receive_feed_response(feed, false, "", "That source could not be read (HTTP 503).")
	assert_string_contains(page.status_text(), "Showing the copy saved")

	# A fetch that arrives as something other than a feed is the same answer.
	page.receive_feed_response(feed, true, "not json")
	assert_string_contains(page.status_text(), "Showing the copy saved")

	Gen2ModIndex.forget_cache(feed)
	page.receive_feed_response(feed, false, "", "That source could not be read (HTTP 503).")
	assert_string_contains(page.status_text(), "HTTP 503")
	assert_false(page.status_text().contains("Showing the copy"))


## A listing offering a newer version than the one installed says so, and the
## count of them is on the status line.
func test_a_source_names_the_mods_a_newer_version_is_listed_for() -> void:
	_write_probe_mod_zip()
	var installed: Dictionary = Gen2ModInstaller.install_zip(_mod_archive)
	assert_true(bool(installed.get("ok", false)), JSON.stringify(installed))
	Gen2ModHost.reset()
	Gen2ModHost.instance().discover()

	var feed: String = "https://mods.example.com/updates.json"
	var page: Gen2ModsPage = _mods_page()
	page.receive_feed_response(feed, true, JSON.stringify({
		"schema_version": Gen2ModIndex.SCHEMA_VERSION,
		"name": "Example",
		"mods": [{"id": String(PROBE_MOD_ID), "name": "Launcher Probe", "version": "9.9.9",
			"download": "https://example.com/probe.zip"}],
	}))
	assert_string_contains(page.status_text(), "1 can be updated")

	# The same listing at the installed version offers a reinstall and no update.
	page.receive_feed_response(feed, true, JSON.stringify({
		"schema_version": Gen2ModIndex.SCHEMA_VERSION,
		"name": "Example",
		"mods": [{"id": String(PROBE_MOD_ID), "name": "Launcher Probe",
			"version": String(installed["version"]),
			"download": "https://example.com/probe.zip"}],
	}))
	assert_false(page.status_text().contains("can be updated"))
	Gen2ModIndex.forget_cache(feed)


## A toast with nothing to say occupies nothing: not drawn, and not in the hit
## test either.
func test_a_silent_toast_is_not_on_screen_at_all() -> void:
	await _open_launcher()
	var toast: Gen2LauncherToast = _find_toast(_launcher)
	assert_not_null(toast)

	assert_false(toast.visible, "an empty toast is gone rather than transparent")
	toast.show_message(&"error", "Something", "happened")
	assert_true(toast.visible)


## And it never takes a click, shown or not. The toast is drawn over the bottom
## centre of every launcher page, which is where the shelf puts Play and the
## cache button; a card that stopped the mouse left both of them dead.
func test_a_toast_never_takes_a_click_from_what_is_under_it() -> void:
	await _open_launcher()
	var toast: Gen2LauncherToast = _find_toast(_launcher)
	toast.show_message(&"error", "Something", "happened")

	var stopping: Array[String] = []
	_mouse_stoppers(toast, stopping)
	assert_eq(stopping, [] as Array[String], "nothing in a toast is clickable")


func _mouse_stoppers(node: Node, out: Array[String]) -> void:
	if node is Control and node.mouse_filter == Control.MOUSE_FILTER_STOP:
		out.append("%s %s" % [node.get_class(), node.name])
	for child: Node in node.get_children():
		_mouse_stoppers(child, out)


func _find_toast(node: Node) -> Gen2LauncherToast:
	if node is Gen2LauncherToast:
		return node
	for child: Node in node.get_children():
		var found: Gen2LauncherToast = _find_toast(child)
		if found != null:
			return found
	return null


## There is no cache migration by design, so the one thing the launcher owes a
## player whose cache a build has outgrown is a sentence saying which of the
## four states it is in and that the dump is wanted again.
func test_every_cache_state_says_something_different() -> void:
	var main := preload("res://game/main/main.gd")
	var said: Dictionary = {}
	for state: StringName in [
		RomCache.STATE_USABLE, RomCache.STATE_STALE,
		RomCache.STATE_INCOMPLETE, RomCache.STATE_MISSING,
	]:
		var text: String = main.cache_state_text(state)
		assert_false(text.is_empty(), "%s says nothing" % state)
		assert_false(said.has(text), "%s repeats another state's line" % state)
		said[text] = true
	for state: StringName in [RomCache.STATE_STALE, RomCache.STATE_INCOMPLETE]:
		assert_true(
			main.cache_state_text(state).contains("Import the cartridge again"),
			"%s asks for the dump" % state
		)
