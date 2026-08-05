extends GutTest

## Service hosts use the imported cache and the production world transaction
## boundaries. The fixture remains synthetic so no cartridge data enters tests.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

var _data: GameData = null
var _world: Gen2WorldAPI = null
var _save: Gen2SaveData = null


func before_each() -> void:
	_data = Fixture.build()
	_write_services()
	_data = GameData.open_directory(Fixture.directory())
	var state := Gen2WorldState.new({}, {}, {7: 1}, {0: 500})
	_world = Gen2WorldAPI.open(
		_data, Fixture.MAP_GROUP, Fixture.MAP_NUMBER, Vector2i(7, 6), state
	)
	_save = Gen2SaveStore.create_development_save(_data, 0)
	_save.world = _world.snapshot()


func after_each() -> void:
	RomCache.clear(Fixture.directory())


func test_mart_entries_use_imported_items_and_prices() -> void:
	var mart: Dictionary = _data.world_mart(0)
	var entries: Array = Gen2WorldMartHost.entries(_data, mart)
	assert_eq(entries.size(), 2)
	assert_eq(entries[0]["item"], 7)
	assert_eq(entries[0]["name"], "ITEM7")
	assert_eq(entries[0]["price"], 120)


func test_mart_purchase_updates_money_items_and_save_atomically() -> void:
	_set_mart_script()
	var waiting: Array = _world.dispatch_script_events(Vector2i(7, 6))
	assert_eq(waiting[0]["status"], &"waiting")
	assert_eq(_world.pending_runtime_request()["kind"], &"mart_requested")

	var resolved: Dictionary = Gen2WorldHost.resolve_runtime_request(_world)
	assert_true(resolved["ok"])
	var purchase: Dictionary = Gen2WorldMartHost.purchase(
		_world, _save, resolved["data"]["mart"], 7, 2, false
	)
	assert_true(purchase["ok"])
	assert_eq(_world.state.item_quantity(7), 3)
	assert_eq(_world.state.money(), 260)
	assert_eq(_save.world.world_state.item_quantity(7), 3)
	assert_eq(_save.world.world_state.money(), 260)

	var complete: Dictionary = Gen2WorldHost.complete_runtime_request(
		_world, {"ok": true, "script_value": 1}, _save, false
	)
	assert_true(complete["ok"])
	assert_eq(complete["results"][0]["status"], &"complete")


func test_mart_purchase_refuses_insufficient_money_without_mutation() -> void:
	var mart: Dictionary = _data.world_mart(0)
	var before: Dictionary = _world.snapshot().to_dict()
	var result: Dictionary = Gen2WorldMartHost.purchase(
		_world, _save, mart, 7, 5, false
	)
	assert_false(result["ok"])
	assert_eq(result["reason"], &"insufficient_money")
	assert_eq(_world.snapshot().to_dict(), before)
	assert_eq(_save.world.world_state.money(), 500)


func test_phone_summary_uses_imported_contact_and_trainer_class() -> void:
	var contact: Dictionary = _data.world_phone_contact(0)
	var summary: Dictionary = Gen2WorldPhoneHost.contact_summary(_data, contact)
	assert_eq(summary["index"], 0)
	assert_eq(summary["trainer_name"], "LEADER")
	assert_eq(summary["trainer_number"], 2)
	assert_eq(summary["map_group"], Fixture.MAP_GROUP)


func test_audio_host_renders_the_real_record() -> void:
	var record: Dictionary = _data.world_audio(&"music", 0)
	var result: Dictionary = Gen2WorldAudioHost.play(record, &"music")
	assert_true(result["ok"])
	assert_false(result["played"])
	assert_eq(result["backend"], Gen2WorldAudioHost.BACKEND_WAV)
	assert_true(result["ready"])
	assert_eq(result["byte_count"], 6)


func test_menu_input_can_be_cancelled_without_selecting_an_option() -> void:
	_write_menu_script()
	var runner := Gen2WorldScriptRunner.begin(_data, _world.state, {
		"kind": &"test", "bank": Fixture.BANK, "script": 0x6310,
	})
	var waiting: Dictionary = runner.advance()
	assert_eq(waiting["status"], &"waiting")
	assert_eq(waiting["event"]["type"], &"menu")
	var complete: Dictionary = runner.cancel_input()
	assert_eq(complete["status"], &"complete")
	assert_true(complete["events"].any(func(event: Dictionary) -> bool:
		return event.get("type", &"") == &"state_changed"
	) == false)


func _write_services() -> void:
	var items: Array = RomCache.read_json(RomCache.items_path(Fixture.directory()))
	for raw: Dictionary in items:
		if int(raw.get("number", 0)) == 7:
			raw["name"] = "ITEM7"
			raw["price"] = 120
	RomCache.write_json(RomCache.items_path(Fixture.directory()), items)
	RomCache.write_json(RomCache.world_marts_path(Fixture.directory()), {
		"marts": [{"index": 0, "bank": Fixture.BANK, "address": 0x4000, "items": [7, 8]}],
		"default": {"items": [7]}, "special": {},
	})
	RomCache.write_json(RomCache.world_phone_path(Fixture.directory()), {
		"contacts": [{
			"index": 0, "trainer_class": 1, "trainer_number": 2,
			"map_group": Fixture.MAP_GROUP, "map_number": Fixture.MAP_NUMBER,
			"callee_time": 1, "caller_time": 2,
		}],
		"special_calls": [],
	})
	RomCache.write_json(RomCache.world_audio_path(Fixture.directory()), {
		"music": [{"index": 0, "bank": Fixture.BANK, "address": 0x4000,
			"bytes": [0x00, 0x03, 0x40, 0xD4, 0x10, 0xFF], "byte_count": 6}],
		"sfx": [],
	})


func _set_mart_script() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(Fixture.directory()))
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, 0x6300)] = [0x94, 0, 0x00, 0x40, 0x91]
	RomCache.write_json(RomCache.world_scripts_path(Fixture.directory()), scripts)
	var maps: Array = RomCache.read_json(RomCache.world_maps_path(Fixture.directory()))
	for raw: Dictionary in maps:
		if int(raw.get("group", -1)) != Fixture.MAP_GROUP \
		or int(raw.get("number", -1)) != Fixture.MAP_NUMBER:
			continue
		var events: Dictionary = raw.get("events", {})
		events["coord_events"] = [{"x": 7, "y": 6, "script": 0x6300}]
		raw["events"] = events
	RomCache.write_json(RomCache.world_maps_path(Fixture.directory()), maps)
	_data = GameData.open_directory(Fixture.directory())
	_world = Gen2WorldAPI.open(
		_data, Fixture.MAP_GROUP, Fixture.MAP_NUMBER, Vector2i(7, 6),
		Gen2WorldState.new({}, {}, {7: 1}, {0: 500})
	)
	_save = Gen2SaveStore.create_development_save(_data, 0)
	_save.world = _world.snapshot()


func _write_menu_script() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(Fixture.directory()))
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, 0x6310)] = [0x4F, 0x34, 0x12, 0x59, 0x91]
	RomCache.write_json(RomCache.world_scripts_path(Fixture.directory()), scripts)
	RomCache.write_json(RomCache.world_menus_path(Fixture.directory()), {
		Gen2WorldScript.pointer_key(Fixture.BANK, 0x1234): {
			"bank": Fixture.BANK, "address": 0x1234, "options": ["YES", "NO"],
		},
	})
	_data = GameData.open_directory(Fixture.directory())
