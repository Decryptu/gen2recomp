extends GutTest

## The mod-options registry and the file behind it. These write a real file under
## user://, so each test clears it.
##
## The contract is that a mod describes a setting and never draws one: both
## surfaces are built from the registration, the value is committed on the press,
## and whatever registered it hears about the change.

const MOD: StringName = &"optionmod"
const OTHER: StringName = &"othermod"

var _heard: Array = []


func before_each() -> void:
	_forget_view()
	Gen2ModHost.reset()
	DirAccess.remove_absolute(Gen2ModOptions.PATH)
	Gen2ModOptions.reload()
	_heard = []


func after_each() -> void:
	_forget_view()
	Gen2ModHost.reset()
	DirAccess.remove_absolute(Gen2ModOptions.PATH)
	Gen2ModOptions.reload()


## Choosing a view writes the installation's own file, so a test that chooses one
## puts it back rather than leaving the player on a renderer a test registered.
func _forget_view() -> void:
	DirAccess.remove_absolute(Gen2ModState.PATH)
	Gen2ModState.reload()


func _distance(host: Gen2ModHost) -> Dictionary:
	return host.register_option(MOD, {
		"key": "draw_distance", "label": "DISTANCE",
		"values": [8, 16, 24, 0], "labels": ["8", "16", "24", "FULL"],
	})


func _note(id: StringName, key: StringName, value: Variant) -> void:
	_heard.append([id, key, value])


func test_a_registered_option_starts_on_its_default_and_is_readable_by_key() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_true(bool(_distance(host).get("ok", false)))
	assert_true(bool(host.register_option(MOD, {
		"key": "zoom", "label": "ZOOM", "values": [false, true], "default": true,
	}).get("ok", false)))

	# No default named: the first rung, which is what a ladder written
	# best-first means.
	assert_eq(host.option(MOD, &"draw_distance"), 8)
	assert_eq(host.option(MOD, &"zoom"), true)
	assert_eq(host.option_index(MOD, &"zoom"), 1)
	assert_null(host.option(MOD, &"nothing"))
	assert_eq(host.option_index(MOD, &"nothing"), -1)


func test_labels_default_to_the_values_and_rows_carry_the_live_choice() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_true(bool(host.register_option(MOD, {
		"key": "steps", "label": "STEPS", "values": [1, 2],
	}).get("ok", false)))
	assert_true(bool(_distance(host).get("ok", false)))

	var rows: Array = host.options(MOD)
	# Registration order, which is the order both surfaces list them in.
	assert_eq(rows.size(), 2)
	assert_eq(StringName(rows[0]["key"]), &"steps")
	assert_eq(rows[0]["labels"], ["1", "2"] as Array[String])
	assert_eq(int(rows[1]["index"]), 0)
	assert_eq(String(rows[1]["labels"][0]), "8")

	assert_true(bool(host.set_option(MOD, &"draw_distance", 24).get("ok", false)))
	assert_eq(int((host.options(MOD)[1] as Dictionary)["index"]), 2)
	assert_eq(host.option(MOD, &"draw_distance"), 24)


func test_a_change_is_written_at_once_and_announced() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_true(bool(_distance(host).get("ok", false)))
	host.option_changed.connect(_note)

	assert_true(bool(host.set_option_index(MOD, &"draw_distance", 3).get("ok", false)))
	assert_eq(_heard, [[MOD, &"draw_distance", 0]])
	# The file carries it before the press returns, the way the cartridge's own
	# OPTION menu commits to wOptions rather than on the way out.
	assert_true(FileAccess.file_exists(Gen2ModOptions.PATH))
	Gen2ModOptions.reload()
	assert_eq(host.option(MOD, &"draw_distance"), 0)


func test_a_stored_value_survives_a_reload_and_is_typed_back_to_the_ladder() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_true(bool(_distance(host).get("ok", false)))
	assert_true(bool(host.set_option(MOD, &"draw_distance", 16).get("ok", false)))
	Gen2ModOptions.reload()

	# JSON reads 16 back as a float; the ladder registered an int, and the rung
	# is the same rung.
	assert_eq(Gen2ModOptions.value(MOD, &"draw_distance"), 16.0)
	assert_eq(host.option_index(MOD, &"draw_distance"), 1)
	assert_eq(host.option(MOD, &"draw_distance"), 16)


func test_a_value_the_ladder_no_longer_offers_falls_back_to_the_default() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_true(bool(_distance(host).get("ok", false)))
	assert_true(bool(host.set_option(MOD, &"draw_distance", 24).get("ok", false)))

	# The same mod, one version later, without that rung.
	Gen2ModHost.reset()
	var next: Gen2ModHost = Gen2ModHost.instance()
	assert_true(bool(next.register_option(MOD, {
		"key": "draw_distance", "label": "DISTANCE", "values": [8, 16], "default": 16,
	}).get("ok", false)))
	assert_eq(next.option(MOD, &"draw_distance"), 16)


func test_only_mods_that_registered_a_setting_are_listed() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_eq(host.option_mod_ids(), [] as Array[StringName])
	assert_eq(host.options(OTHER), [])
	assert_true(bool(_distance(host).get("ok", false)))
	assert_eq(host.option_mod_ids(), [MOD] as Array[StringName])


func test_a_malformed_registration_is_refused_and_named() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	for option: Dictionary in [
		{"key": "", "label": "X", "values": [1]},
		{"key": "k", "label": "", "values": [1]},
		{"key": "k", "label": "X", "values": []},
		{"key": "k", "label": "X", "values": [1, 2], "labels": ["one"]},
	]:
		var result: Dictionary = host.register_option(MOD, option)
		assert_false(bool(result.get("ok", false)), "refused: %s" % option)
		assert_false(
			Gen2ModRefusal.text(result).begins_with(String(result.get("reason", &""))),
			"worded: %s" % result.get("reason", &"")
		)
	assert_true(host.option_mod_ids().is_empty())


func test_one_key_cannot_be_registered_twice_and_an_unknown_one_is_not_settable() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_true(bool(_distance(host).get("ok", false)))
	assert_eq(
		StringName(_distance(host).get("reason", &"")), &"duplicate_option"
	)
	assert_eq(
		StringName(host.set_option(MOD, &"missing", 1).get("reason", &"")), &"unknown_option"
	)
	assert_eq(
		StringName(host.set_option(MOD, &"draw_distance", 7).get("reason", &"")),
		&"invalid_option_value"
	)
	assert_eq(
		StringName(host.set_option_index(MOD, &"draw_distance", 9).get("reason", &"")),
		&"invalid_option_value"
	)
	# A refused change writes nothing and announces nothing.
	host.option_changed.connect(_note)
	host.set_option(MOD, &"draw_distance", 7)
	assert_eq(_heard, [])
	assert_eq(host.option(MOD, &"draw_distance"), 8)


func test_uninstalling_a_mod_drops_what_it_stored() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_true(bool(_distance(host).get("ok", false)))
	assert_true(bool(host.set_option(MOD, &"draw_distance", 24).get("ok", false)))

	assert_true(bool(Gen2ModInstaller.uninstall(MOD, "user://mod-options-test").get("ok", false)))
	Gen2ModOptions.reload()
	assert_null(Gen2ModOptions.value(MOD, &"draw_distance"))
	assert_eq(host.option(MOD, &"draw_distance"), 8)


func test_the_shipped_example_registers_the_setting_its_renderer_reads() -> void:
	# mods/examples/voxel_preview/ is what a mod author copies, so the pair is
	# run rather than read: a key the renderer reads and the mod never
	# registered would leave the camera on its constant and teach that.
	var manifest: Dictionary = Gen2ModManifest.read("res://mods/examples/voxel_preview")
	assert_true(bool(manifest.get("ok", false)), "example manifest reads")
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_true(bool(host.load_mod(manifest["manifest"]).get("ok", false)))

	assert_true(bool(host.select_view(manifest["manifest"].id).get("ok", false)))
	var renderer: Node = host.create_world_renderer()
	assert_eq(renderer.get_script().resource_path, "res://mods/examples/voxel_preview/renderer.gd")
	assert_eq(host.option(renderer.MOD_ID, renderer.OPTION_PITCH), renderer.camera_pitch())
	assert_true(bool(host.set_option_index(renderer.MOD_ID, renderer.OPTION_PITCH, 0).get(
		"ok", false
	)))
	# The renderer heard the change rather than polling for it.
	assert_eq(renderer.camera_pitch(), host.option(renderer.MOD_ID, renderer.OPTION_PITCH))
	renderer.free()


## A slot's own settings, which is what makes its recorded walk reproducible: the
## file is the template a new run is created from, and the run holds the values it
## was played with from then on.
func test_a_new_save_records_the_settings_it_was_created_with() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_true(bool(_distance(host).get("ok", false)))
	assert_true(bool(host.set_option(MOD, &"draw_distance", 24).get("ok", false)))

	var save := Gen2SaveData.new()
	host.created_save(save)
	assert_eq(save.run_options, {MOD: {&"draw_distance": 24}})

	host.activate_save(save)
	# The installation moves on; the run does not, and the value the run is played
	# with is the one it recorded.
	Gen2ModOptions.unbind_run()
	assert_true(bool(host.set_option(MOD, &"draw_distance", 8).get("ok", false)))
	host.activate_save(save)
	assert_eq(host.option(MOD, &"draw_distance"), 24)

	host.deactivate_save()
	assert_false(Gen2ModOptions.run_bound())
	assert_eq(host.option(MOD, &"draw_distance"), 8, "and the launcher edits the installation")


## A slot written before the snapshot existed adopts the installation once, which
## is the only honest reconciliation: nothing recorded what it was played with.
func test_a_save_with_no_recorded_settings_adopts_the_installation_once() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_true(bool(_distance(host).get("ok", false)))
	assert_true(bool(host.set_option(MOD, &"draw_distance", 16).get("ok", false)))

	var save := Gen2SaveData.new()
	host.activate_save(save)
	assert_eq(save.run_options, {MOD: {&"draw_distance": 16}})
	assert_eq(host.option(MOD, &"draw_distance"), 16)


## A change made while a slot is played belongs to that slot: the installation is
## left alone, so the other slots keep the walk they recorded.
func test_a_change_during_a_run_is_kept_by_the_run() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_true(bool(_distance(host).get("ok", false)))
	assert_true(bool(host.set_option(MOD, &"draw_distance", 8).get("ok", false)))

	var save := Gen2SaveData.new()
	host.created_save(save)
	host.activate_save(save)
	assert_true(bool(host.set_option(MOD, &"draw_distance", 24).get("ok", false)))
	assert_eq(save.run_options, {MOD: {&"draw_distance": 24}}, "the save carries it")
	assert_eq(
		Gen2SaveData.from_dict(save.to_dict()).run_options, {MOD: {&"draw_distance": 24}},
		"and it survives the round trip through the file"
	)

	host.deactivate_save()
	assert_eq(host.option(MOD, &"draw_distance"), 8, "the installation was left alone")


## A development run has no slot, so there is nothing to bind and nothing to
## invent: the installation is what it plays with.
func test_a_run_with_no_slot_plays_the_installations_settings() -> void:
	var host: Gen2ModHost = Gen2ModHost.instance()
	assert_true(bool(_distance(host).get("ok", false)))
	assert_true(bool(host.set_option(MOD, &"draw_distance", 16).get("ok", false)))
	host.activate_save(null)
	assert_false(Gen2ModOptions.run_bound())
	assert_eq(host.option(MOD, &"draw_distance"), 16)
