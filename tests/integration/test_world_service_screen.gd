extends GutTest

## Scene integration for the cache-backed service overlay. The fixture is
## synthetic, but the world screen, script runner, transaction host and UI
## scene are the production paths.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

const APRICORN_RED: int = 0x55
const APRICORN_BLU: int = 0x59

var _data: GameData = null
var _world_screen: Gen2WorldScreen = null


func before_each() -> void:
	_data = Fixture.build()
	_write_service_cache()
	_data = GameData.open_directory(Fixture.directory())


func after_each() -> void:
	if is_instance_valid(_world_screen):
		_world_screen.free()
		_world_screen = null
	RomCache.clear(Fixture.directory())


func _open_world(items: Dictionary = {7: 1}) -> void:
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_world_screen = packed.instantiate() as Gen2WorldScreen
	_world_screen.map_group = Fixture.MAP_GROUP
	_world_screen.map_number = Fixture.MAP_NUMBER
	_world_screen.start_cell = Vector2i(7, 6)
	var state := Gen2WorldState.new({}, {}, items, {0: 500})
	var world := Gen2WorldAPI.open(
		_data, Fixture.MAP_GROUP, Fixture.MAP_NUMBER, Vector2i(7, 6), state
	)
	var save := Gen2SaveStore.create_development_save(_data, 0)
	save.world = world.snapshot()
	_world_screen.set_data(_data)
	_world_screen.set_save(save)
	add_child(_world_screen)
	await get_tree().process_frame


func _queue_service() -> void:
	var waiting: Array = _world_screen._world.dispatch_script_events(Vector2i(7, 6))
	assert_eq(waiting.size(), 1)
	assert_eq(waiting[0]["status"], &"waiting")
	_world_screen._show_script_results(waiting)
	await get_tree().process_frame


func _write_pc_request() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(Fixture.directory()))
	scripts["48:6190"] = [Gen2WorldScript.SPECIAL, 29, 0, Gen2WorldScript.END]
	RomCache.write_json(RomCache.world_scripts_path(Fixture.directory()), scripts)
	_data = GameData.open_directory(Fixture.directory())


func test_players_house_pc_embeds_box_storage_and_resumes_the_waiting_script() -> void:
	_write_pc_request()
	await _open_world()
	_world_screen._world.current_map.events["coord_events"][0]["script"] = 0x6190
	var waiting: Array = _world_screen._world.dispatch_script_events(Vector2i(7, 6))
	assert_eq(waiting.size(), 1)
	assert_eq(waiting[0]["status"], &"waiting")
	_world_screen._show_script_results(waiting)
	await get_tree().process_frame

	var pc: Gen2BoxScreen = _world_screen._pc_host
	assert_not_null(pc)
	assert_eq(pc.box_snapshot()["boxes"].size(), Gen2SaveData.BOX_COUNT)
	assert_true(pc.select_party_member(0))
	assert_true(pc.deposit_selected_party())
	assert_eq((_world_screen._injected_save as Gen2SaveData).party.size(), 1)

	pc.close_embedded()
	await get_tree().process_frame
	assert_null(_world_screen._pc_host)
	assert_false(_world_screen._world.script_input_waiting())


func test_pokemon_center_pc_embeds_box_storage_and_resumes_the_waiting_script() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(Fixture.directory()))
	scripts["48:6195"] = [
		Gen2WorldScript.SPECIAL, Gen2WorldScriptRunner.SPECIAL_POKEMON_CENTER_PC, 0,
		Gen2WorldScript.END,
	]
	RomCache.write_json(RomCache.world_scripts_path(Fixture.directory()), scripts)
	_data = GameData.open_directory(Fixture.directory())
	await _open_world()
	_world_screen._world.current_map.events["coord_events"][0]["script"] = 0x6195
	var waiting: Array = _world_screen._world.dispatch_script_events(Vector2i(7, 6))
	assert_eq(waiting.size(), 1)
	assert_eq(waiting[0]["status"], &"waiting")
	assert_eq(_world_screen._world.pending_runtime_request()["values"]["mode"], &"pokemon_center")
	_world_screen._show_script_results(waiting)
	await get_tree().process_frame

	var pc: Gen2BoxScreen = _world_screen._pc_host
	assert_not_null(pc)
	assert_eq(pc.box_snapshot()["boxes"].size(), Gen2SaveData.BOX_COUNT)

	pc.close_embedded()
	await get_tree().process_frame
	assert_null(_world_screen._pc_host)
	assert_false(_world_screen._world.script_input_waiting())


func test_mart_overlay_uses_production_input_and_returns_to_script() -> void:
	await _open_world()
	await _queue_service()

	var host: Gen2WorldServiceScreen = _world_screen._service_host
	assert_not_null(host)
	assert_eq(host._title.text, "MART")
	assert_eq(host.selected_index(), 0)
	assert_true(host.handle_button(Gen2Button.A))
	assert_eq(_world_screen._world.state.money(), 380)
	assert_eq(_world_screen._world.state.item_quantity(7), 2)
	assert_true(host.is_active())

	assert_true(host.handle_button(Gen2Button.DOWN))
	assert_true(host.handle_button(Gen2Button.A))
	await get_tree().process_frame
	assert_null(_world_screen._service_host)
	assert_false(_world_screen._world.script_input_waiting())


func test_mart_overlay_purchases_the_selected_quantity() -> void:
	await _open_world()
	await _queue_service()

	var host: Gen2WorldServiceScreen = _world_screen._service_host
	assert_not_null(host)
	assert_true(host.handle_button(Gen2Button.RIGHT))
	assert_true(host.handle_button(Gen2Button.A))
	assert_eq(_world_screen._world.state.money(), 260)
	assert_eq(_world_screen._world.state.item_quantity(7), 3)
	assert_true(host.is_active())

	assert_true(host.handle_button(Gen2Button.DOWN))
	assert_true(host.handle_button(Gen2Button.A))
	await get_tree().process_frame
	assert_null(_world_screen._service_host)
	assert_false(_world_screen._world.script_input_waiting())


func test_menu_overlay_cancel_resumes_with_false_script_value() -> void:
	_write_menu_request()
	_data = GameData.open_directory(Fixture.directory())
	await _open_world()
	await _queue_service()

	var host: Gen2WorldServiceScreen = _world_screen._service_host
	assert_not_null(host)
	assert_eq(host._title.text, "MENU")
	assert_eq(host.selected_index(), 0)
	assert_true(host.handle_button(Gen2Button.B))
	await get_tree().process_frame
	assert_null(_world_screen._service_host)
	assert_false(_world_screen._world.script_input_waiting())


func test_two_dimensional_menu_uses_cached_grid_and_default_cursor() -> void:
	_write_2d_menu_request()
	_data = GameData.open_directory(Fixture.directory())
	await _open_world()
	await _queue_service()

	var host: Gen2WorldServiceScreen = _world_screen._service_host
	assert_not_null(host)
	assert_eq(host._title.text, "MENU")
	assert_eq(host.selected_index(), 1)
	assert_eq(host._options.get_child_count(), 1)
	var grid: GridContainer = host._options.get_child(0) as GridContainer
	assert_not_null(grid)
	assert_eq(grid.columns, 2)
	assert_eq(grid.get_child_count(), 4)

	assert_true(host.handle_button(Gen2Button.LEFT))
	assert_eq(host.selected_index(), 0)
	assert_true(host.handle_button(Gen2Button.DOWN))
	assert_eq(host.selected_index(), 2)
	assert_true(host.handle_button(Gen2Button.A))
	await get_tree().process_frame
	assert_null(_world_screen._service_host)
	assert_false(_world_screen._world.script_input_waiting())


func test_pending_special_call_dispatches_the_imported_script() -> void:
	_write_phone_request()
	_data = GameData.open_directory(Fixture.directory())
	await _open_world()
	var staged: Dictionary = _world_screen._world.state.apply_changes({}, {}, {
		"pending_special_phone_call": 1,
	})
	assert_true(staged["ok"])
	var attempt: Dictionary = _world_screen._world.try_special_phone_call()
	assert_true(attempt["attempted"])
	_world_screen._show_script_results(attempt["results"])
	await get_tree().process_frame
	## The screen's own pump is what spends the two rings and shows what
	## finishing them produced.
	_world_screen.advance_frames(4 * Gen2WorldPhoneRing.TOTAL_FRAMES)
	await get_tree().process_frame
	assert_null(_world_screen._service_host)
	assert_true(_world_screen._world.script_input_waiting())
	assert_eq(_world_screen._world.pending_script_input()["text"], "PHONE SCRIPT")
	## The first press completes the revealing page, as holding A does in
	## `PrintLetterDelay`; the second acknowledges it.
	_world_screen._advance_script_input()
	_world_screen._advance_script_input()
	await get_tree().process_frame
	assert_false(_world_screen._world.script_input_waiting())


func test_phone_list_shows_registered_numbers_and_can_close() -> void:
	_write_phone_request()
	_data = GameData.open_directory(Fixture.directory())
	await _open_world()
	var registered: Dictionary = _world_screen._world.state.apply_changes({}, {}, {
		"phone_contacts": {0: true},
	})
	assert_true(registered["ok"])
	_world_screen._open_phone_list()
	await get_tree().process_frame
	var host: Gen2WorldServiceScreen = _world_screen._service_host
	assert_not_null(host)
	assert_eq(host._title.text, "PHONE")
	assert_eq(host._summary.text, "Registered numbers")
	assert_eq(host.selected_index(), 0)
	assert_true(host.handle_button(Gen2Button.B))
	await get_tree().process_frame
	assert_null(_world_screen._service_host)


func test_phone_list_starts_the_source_timed_outgoing_ring() -> void:
	_write_phone_request()
	_data = GameData.open_directory(Fixture.directory())
	await _open_world()
	var registered: Dictionary = _world_screen._world.state.apply_changes({}, {}, {
		"phone_contacts": {0: true},
	})
	assert_true(registered["ok"])
	_world_screen._open_phone_list()
	await get_tree().process_frame
	var host: Gen2WorldServiceScreen = _world_screen._service_host
	assert_not_null(host)
	assert_true(host.handle_button(Gen2Button.A))
	await get_tree().process_frame
	assert_null(_world_screen._service_host)
	assert_true(_world_screen._world.phone_ring_active())
	assert_true(_world_screen._caption.text.contains("PHONE RING"))
	## The screen's own pump is what spends the two rings and shows what
	## finishing them produced.
	_world_screen.advance_frames(4 * Gen2WorldPhoneRing.TOTAL_FRAMES)
	await get_tree().process_frame
	assert_true(_world_screen._world.script_input_waiting())
	assert_eq(_world_screen._world.pending_script_input()["text"], "PHONE SCRIPT")


func test_pokegear_clock_card_renders_source_time_and_returns_to_cards() -> void:
	await _open_world()
	_world_screen._world.set_world_clock(3, 0, 7)
	_world_screen._clock.day = 3
	_world_screen._clock.hour = 0
	_world_screen._clock.minute = 7
	_world_screen._open_pokegear()
	await get_tree().process_frame
	var host: Gen2WorldServiceScreen = _world_screen._service_host
	assert_not_null(host)
	assert_eq(host._mode, Gen2WorldServiceScreen.MODE.POKEGEAR)
	assert_true(host.handle_button(Gen2Button.A))
	assert_eq(host._mode, Gen2WorldServiceScreen.MODE.CLOCK)
	assert_true(host._summary.text.contains("WEDNESDAY"))
	assert_true(host._summary.text.contains("12:07 AM"))
	assert_true(host._status.text.contains("NIGHT"))
	assert_true(host.handle_button(Gen2Button.B))
	assert_eq(host._mode, Gen2WorldServiceScreen.MODE.POKEGEAR)


func test_audio_request_decodes_and_starts_the_runtime_player() -> void:
	_write_audio_request()
	_data = GameData.open_directory(Fixture.directory())
	await _open_world()
	await _queue_service()

	assert_null(_world_screen._service_host)
	var audio_player: Node = _world_screen.get_node("AudioPlayer") as Node
	assert_not_null(audio_player)
	assert_not_null(audio_player.get_node("MusicPlayer").stream)
	assert_false(_world_screen._world.script_input_waiting())


func test_town_map_decoration_opens_fullscreen_and_closes_the_script_request() -> void:
	_write_service_cache()
	_write_request_script([
		Gen2WorldScript.raw_opcode(0x99), 0x00, Gen2WorldScript.END,
	], 0x6330)
	_data = GameData.open_directory(Fixture.directory())
	await _open_world()
	_world_screen._world.state.set_maptile_decoration(&"poster", 0x10)
	var waiting: Array = _world_screen._world.dispatch_script_events(Vector2i(7, 6))
	assert_eq(waiting.size(), 1)
	_world_screen._show_script_results(waiting)
	await get_tree().process_frame

	_world_screen._text_box.finish()
	_world_screen._advance_script_input()
	await get_tree().process_frame
	var host: Gen2WorldServiceScreen = _world_screen._service_host
	assert_not_null(host)
	assert_eq(host._mode, Gen2WorldServiceScreen.MODE.TOWN_MAP)
	assert_not_null(host._town_map)
	assert_true(host._town_map.visible)
	assert_true(host.handle_button(Gen2Button.B))
	await get_tree().process_frame
	assert_null(_world_screen._service_host)
	assert_false(_world_screen._world.script_input_waiting())


func _write_service_cache() -> void:
	var items: Array = RomCache.read_json(RomCache.items_path(Fixture.directory()))
	for raw: Dictionary in items:
		if int(raw.get("number", 0)) == 7:
			raw["name"] = "ITEM7"
			raw["price"] = 120
	RomCache.write_json(RomCache.items_path(Fixture.directory()), items)
	RomCache.write_json(RomCache.world_marts_path(Fixture.directory()), {
		"marts": [{"index": 0, "bank": Fixture.BANK, "address": 0x4000, "items": [7]}],
		"default": {"items": [7]}, "special": {},
	})
	RomCache.write_json(RomCache.world_audio_path(Fixture.directory()), {
		"music": [{"index": 0, "bank": Fixture.BANK, "address": 0x4000,
			"bytes": [0x00, 0x03, 0x40, 0xD4, 0x10, 0xFF], "byte_count": 6}],
		"sfx": [],
	})
	_write_request_script([0x94, 0, 0x00, 0x40, 0x91], 0x6320)


func _write_menu_request() -> void:
	_write_request_script([0x4F, 0x34, 0x12, 0x59, 0x91], 0x6320)
	RomCache.write_json(RomCache.world_menus_path(Fixture.directory()), {
		Gen2WorldScript.pointer_key(Fixture.BANK, 0x1234): {
			"bank": Fixture.BANK, "address": 0x1234, "options": ["YES", "NO"],
		},
	})


func _write_2d_menu_request() -> void:
	_write_request_script([0x4F, 0x34, 0x12, 0x58, 0x91], 0x6320)
	RomCache.write_json(RomCache.world_menus_path(Fixture.directory()), {
		Gen2WorldScript.pointer_key(Fixture.BANK, 0x1234): {
			"bank": Fixture.BANK, "address": 0x1234, "kind": "2d",
			"data_flags": 1 << 5, "rows": 2, "columns": 2,
			"options": ["A", "B", "C", "D"], "default": 2,
		},
	})


func _write_phone_request() -> void:
	_write_request_script([0x9C, 0x01, 0x00, 0x91], 0x6320)
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(Fixture.directory()))
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, 0x6400)] = [
		0x4B, Fixture.BANK, 0x00, 0x70, 0x9C, 0x00, 0x00, 0x91,
	]
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, 0x6500)] = [
		0x4B, Fixture.BANK, 0x00, 0x70, 0x9C, 0x00, 0x00, 0x91,
	]
	RomCache.write_json(RomCache.world_scripts_path(Fixture.directory()), scripts)
	var phone_text: Array = [Gen2WorldScript.TEXT_START]
	for byte: int in Gen2Text.encode("PHONE SCRIPT"):
		phone_text.append(byte)
	phone_text.append(Gen2WorldScript.TEXT_TERMINATOR)
	RomCache.write_json(RomCache.world_text_path(Fixture.directory()), {
		Gen2WorldScript.pointer_key(Fixture.BANK, 0x7000): phone_text,
	})
	RomCache.write_json(RomCache.world_phone_path(Fixture.directory()), {
		"contacts": [{
			"index": 0, "trainer_class": 1, "trainer_number": 2,
			"map_group": Fixture.MAP_GROUP + 1, "map_number": Fixture.MAP_NUMBER,
			"callee_time": Gen2WorldPhoneHost.TIME_ANY,
			"caller_time": Gen2WorldPhoneHost.TIME_ANY,
			"caller_script": {"bank": Fixture.BANK, "address": 0x6400},
			"callee_script": {"bank": Fixture.BANK, "address": 0x6500},
		}],
		"special_calls": [{
			"index": 0, "condition_kind": "anywhere", "contact": 0,
			"script": {"bank": Fixture.BANK, "address": 0x6500},
		}],
	})


func _write_audio_request() -> void:
	_write_request_script([0x7F, 0x00, 0x40, 0x91], 0x6320)


func _write_apricorn_request() -> void:
	_write_request_script([
		Gen2WorldScript.SPECIAL,
		Gen2WorldScriptRunner.SPECIAL_SELECT_APRICORN_FOR_KURT, 0x00,
		Gen2WorldScript.END,
	], 0x6320)


func test_apricorn_overlay_gives_kurt_the_chosen_quantity_and_resumes() -> void:
	_write_apricorn_request()
	_data = GameData.open_directory(Fixture.directory())
	await _open_world({APRICORN_RED: 4, APRICORN_BLU: 2})
	await _queue_service()

	var host: Gen2WorldServiceScreen = _world_screen._service_host
	assert_not_null(host)
	assert_eq(host._title.text, "APRICORNS")
	assert_true(host.handle_button(Gen2Button.DOWN))
	assert_true(host.handle_button(Gen2Button.A))
	assert_true(host.handle_button(Gen2Button.UP))
	assert_true(host.handle_button(Gen2Button.A))
	await get_tree().process_frame

	assert_null(_world_screen._service_host)
	assert_false(_world_screen._world.script_input_waiting())
	assert_eq(_world_screen._world.state.item_quantity(APRICORN_BLU), 0)
	assert_eq(_world_screen._world.state.item_quantity(APRICORN_RED), 4)
	assert_eq(_world_screen._world.state.kurt_apricorn_quantity(), 2)


func test_apricorn_overlay_cancel_takes_nothing_and_resumes() -> void:
	_write_apricorn_request()
	_data = GameData.open_directory(Fixture.directory())
	await _open_world({APRICORN_RED: 4})
	await _queue_service()

	var host: Gen2WorldServiceScreen = _world_screen._service_host
	assert_not_null(host)
	assert_true(host.handle_button(Gen2Button.B))
	await get_tree().process_frame

	assert_null(_world_screen._service_host)
	assert_false(_world_screen._world.script_input_waiting())
	assert_eq(_world_screen._world.state.item_quantity(APRICORN_RED), 4)
	assert_eq(_world_screen._world.state.kurt_apricorn_quantity(), 0)


func _write_request_script(script: Array, address: int) -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(Fixture.directory()))
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, address)] = script
	RomCache.write_json(RomCache.world_scripts_path(Fixture.directory()), scripts)
	var maps: Array = RomCache.read_json(RomCache.world_maps_path(Fixture.directory()))
	for raw: Dictionary in maps:
		if int(raw.get("group", -1)) != Fixture.MAP_GROUP \
		or int(raw.get("number", -1)) != Fixture.MAP_NUMBER:
			continue
		var events: Dictionary = raw.get("events", {})
		events["coord_events"] = [{"x": 7, "y": 6, "script": address}]
		raw["events"] = events
	RomCache.write_json(RomCache.world_maps_path(Fixture.directory()), maps)
