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


func test_mart_dialog_resolves_all_imported_shop_variants() -> void:
	var standard: Dictionary = Gen2WorldMartHost.resolve_mart(
		_data, Gen2WorldMartHost.MARTTYPE_STANDARD, 0
	)
	assert_true(standard["ok"])
	assert_eq(standard["mart"]["variant"], &"standard")
	var bitter: Dictionary = Gen2WorldMartHost.resolve_mart(
		_data, Gen2WorldMartHost.MARTTYPE_BITTER, 0
	)
	assert_true(bitter["ok"])
	assert_eq(bitter["mart"]["variant"], &"bitter")
	var pharmacy: Dictionary = Gen2WorldMartHost.resolve_mart(
		_data, Gen2WorldMartHost.MARTTYPE_PHARMACY, 0
	)
	assert_true(pharmacy["ok"])
	assert_eq(pharmacy["mart"]["variant"], &"pharmacy")
	var bargain: Dictionary = Gen2WorldMartHost.resolve_mart(
		_data, Gen2WorldMartHost.MARTTYPE_BARGAIN, 0
	)
	assert_true(bargain["ok"])
	assert_eq(bargain["mart"]["variant"], &"bargain")
	assert_eq(bargain["mart"]["items"][0]["price"], 50)
	var rooftop: Dictionary = Gen2WorldMartHost.resolve_mart(
		_data, Gen2WorldMartHost.MARTTYPE_ROOFTOP, 0
	)
	assert_true(rooftop["ok"])
	assert_eq(rooftop["mart"]["variant"], &"rooftop_mart_1")
	assert_eq(rooftop["mart"]["items"][0]["price"], 10)
	var invalid: Dictionary = Gen2WorldMartHost.resolve_mart(_data, 9, 0)
	assert_false(invalid["ok"])
	assert_eq(invalid["reason"], &"unsupported_mart_dialog")


func test_mart_host_uses_hall_of_fame_for_rooftop_stock() -> void:
	_set_mart_script(Gen2WorldMartHost.MARTTYPE_ROOFTOP)
	_world.state.set_hall_of_fame()
	var waiting: Array = _world.dispatch_script_events(Vector2i(7, 6))
	assert_eq(waiting[0]["status"], &"waiting")
	var resolved: Dictionary = Gen2WorldHost.resolve_runtime_request(_world)
	assert_true(resolved["ok"])
	assert_eq(resolved["data"]["mart"]["variant"], &"rooftop_mart_2")
	assert_eq(resolved["data"]["mart"]["items"][0]["price"], 20)


func test_bargain_purchase_closes_merchant_and_sells_each_item_once() -> void:
	var bargain: Dictionary = Gen2WorldMartHost.resolve_mart(
		_data, Gen2WorldMartHost.MARTTYPE_BARGAIN, 0, false, _world.state
	)
	assert_true(bargain["ok"])
	var quantity: Dictionary = Gen2WorldMartHost.purchase(
		_world, _save, bargain["mart"], 7, 2, false
	)
	assert_false(quantity["ok"])
	assert_eq(quantity["reason"], &"bargain_quantity_must_be_one")
	var purchase: Dictionary = Gen2WorldMartHost.purchase(
		_world, _save, bargain["mart"], 7, 1, false
	)
	assert_true(purchase["ok"])
	assert_true(_world.state.bargain_merchant_closed())
	assert_true(_save.world.world_state.bargain_merchant_closed())
	assert_true(Gen2WorldMartHost.entries(_data, bargain["mart"])[0]["sold_out"])
	var sold_out: Dictionary = Gen2WorldMartHost.purchase(
		_world, _save, bargain["mart"], 7, 1, false
	)
	assert_false(sold_out["ok"])
	assert_eq(sold_out["reason"], &"bargain_item_sold_out")
	var closed: Dictionary = Gen2WorldMartHost.resolve_mart(
		_data, Gen2WorldMartHost.MARTTYPE_BARGAIN, 0, false, _world.state
	)
	assert_false(closed["ok"])
	assert_eq(closed["reason"], &"bargain_mart_closed")
	_world.set_world_clock(1, 6, 0)
	var next_day: Dictionary = Gen2WorldMartHost.resolve_mart(
		_data, Gen2WorldMartHost.MARTTYPE_BARGAIN, 0, false, _world.state
	)
	assert_true(next_day["ok"])


func test_bargain_host_refuses_a_closed_merchant_before_opening_ui() -> void:
	_set_mart_script(Gen2WorldMartHost.MARTTYPE_BARGAIN)
	_world.state.set_engine_flag(Gen2WorldState.ENGINE_GOLDENROD_UNDERGROUND_MERCHANT_CLOSED)
	var waiting: Array = _world.dispatch_script_events(Vector2i(7, 6))
	assert_eq(waiting[0]["status"], &"waiting")
	var resolved: Dictionary = Gen2WorldHost.resolve_runtime_request(_world)
	assert_false(resolved["ok"])
	assert_eq(resolved["reason"], &"bargain_mart_closed")


func test_bargain_script_keeps_the_source_monday_morning_gate() -> void:
	_write_bargain_schedule_script()
	var monday_morning := Gen2WorldScriptRunner.begin(_data, _world.state, {
		"kind": &"test", "bank": Fixture.BANK, "script": 0x6300,
		"clock": {"day": 1, "hour": 6, "minute": 0},
	})
	var morning_result: Dictionary = monday_morning.advance()
	assert_eq(morning_result["status"], &"waiting")
	assert_eq(morning_result["event"]["request"]["kind"], &"mart_requested")
	assert_eq(morning_result["event"]["request"]["values"]["dialog"], Gen2WorldMartHost.MARTTYPE_BARGAIN)
	var sunday := Gen2WorldScriptRunner.begin(_data, _world.state, {
		"kind": &"test", "bank": Fixture.BANK, "script": 0x6300,
		"clock": {"day": 0, "hour": 6, "minute": 0},
	})
	assert_eq(sunday.advance()["status"], &"complete")
	var monday_night := Gen2WorldScriptRunner.begin(_data, _world.state, {
		"kind": &"test", "bank": Fixture.BANK, "script": 0x6300,
		"clock": {"day": 1, "hour": 18, "minute": 0},
	})
	assert_eq(monday_night.advance()["status"], &"complete")


func test_mart_purchase_refuses_crossing_the_source_item_stack_limit() -> void:
	var mart: Dictionary = _data.world_mart(0)
	var before: Dictionary = _world.snapshot().to_dict()
	var result: Dictionary = Gen2WorldMartHost.purchase(
		_world, _save, mart, 7, Gen2WorldMartHost.MAX_ITEM_STACK, false
	)
	assert_false(result["ok"])
	assert_eq(result["reason"], &"item_stack_full")
	assert_eq(_world.snapshot().to_dict(), before)


func test_phone_summary_uses_imported_contact_and_trainer_class() -> void:
	var contact: Dictionary = _data.world_phone_contact(0)
	var summary: Dictionary = Gen2WorldPhoneHost.contact_summary(_data, contact)
	assert_eq(summary["index"], 0)
	assert_eq(summary["trainer_name"], "LEADER")
	assert_eq(summary["trainer_number"], 2)
	assert_eq(summary["map_group"], Fixture.MAP_GROUP)


func test_phone_time_masks_and_map_rules_match_the_cartridge() -> void:
	assert_eq(Gen2WorldPhoneHost.time_mask_for_hour(3), Gen2WorldPhoneHost.TIME_NIGHT)
	assert_eq(Gen2WorldPhoneHost.time_mask_for_hour(4), Gen2WorldPhoneHost.TIME_MORNING)
	assert_eq(Gen2WorldPhoneHost.time_mask_for_hour(10), Gen2WorldPhoneHost.TIME_DAY)
	assert_eq(Gen2WorldPhoneHost.time_mask_for_hour(18), Gen2WorldPhoneHost.TIME_NIGHT)
	assert_true(Gen2WorldPhoneHost.time_mask_matches(7, 23))
	assert_false(Gen2WorldPhoneHost.time_mask_matches(2, 6))

	var map := Gen2WorldMap.new()
	map.group = Fixture.MAP_GROUP + 1
	map.number = Fixture.MAP_NUMBER
	map.environment = 0
	map.phone_flag = 0
	var state := Gen2WorldState.new({}, {}, {}, {}, 0, {0: true})
	var incoming: Dictionary = Gen2WorldPhoneHost.resolve_incoming(
		_data, state, map, 6, true, true, 0
	)
	assert_true(incoming["ok"])
	assert_eq(incoming["contact_id"], 0)

	map.group = Fixture.MAP_GROUP
	var same_map: Dictionary = Gen2WorldPhoneHost.resolve_incoming(
		_data, state, map, 6, true, true, 0
	)
	assert_false(same_map["ok"])
	assert_eq(same_map["reason"], &"no_available_caller")
	map.phone_flag = 1
	var no_service: Dictionary = Gen2WorldPhoneHost.resolve_incoming(
		_data, state, map, 6, true, true, 0
	)
	assert_false(no_service["ok"])
	assert_eq(no_service["reason"], &"phone_service_unavailable")


func test_outgoing_phone_uses_imported_same_map_and_out_of_area_scripts() -> void:
	var metadata: Dictionary = {
		"out_of_area_script": {"bank": Fixture.BANK, "address": 0x6600},
		"just_talk_script": {"bank": Fixture.BANK, "address": 0x6610},
	}
	var phone: Dictionary = RomCache.read_json(RomCache.world_phone_path(Fixture.directory()))
	phone["metadata"] = metadata
	RomCache.write_json(RomCache.world_phone_path(Fixture.directory()), phone)
	_data = GameData.open_directory(Fixture.directory())
	var state := Gen2WorldState.new({}, {}, {}, {}, 0, {0: true})
	var same_map: Dictionary = Gen2WorldPhoneHost.resolve_outgoing(
		_data, state, _world.current_map, 0, 12
	)
	assert_true(same_map["ok"])
	assert_true(same_map["phone"]["same_map"])
	assert_eq(same_map["script"]["address"], 0x6610)
	_world.current_map.phone_flag = 1
	var out_of_area: Dictionary = Gen2WorldPhoneHost.resolve_outgoing(
		_data, state, _world.current_map, 0, 12
	)
	assert_true(out_of_area["ok"])
	assert_true(out_of_area["out_of_area"])
	assert_eq(out_of_area["script"]["address"], 0x6600)


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
		"default": {"items": [7]}, "special": {
			"bargain": [{"item": 7, "price": 50}],
			"rooftop_mart_1": [{"item": 8, "price": 10}],
			"rooftop_mart_2": [{"item": 8, "price": 20}],
		},
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


func _set_mart_script(dialog_id: int = Gen2WorldMartHost.MARTTYPE_STANDARD) -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(Fixture.directory()))
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, 0x6300)] = [0x94, dialog_id, 0x00, 0x40, 0x91]
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


func _write_bargain_schedule_script() -> void:
	var scripts: Dictionary = RomCache.read_json(RomCache.world_scripts_path(Fixture.directory()))
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, 0x6300)] = [
		0x1C, 0x0B, 0x06, 1, 0x10, 0x63, 0x91,
	]
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, 0x6310)] = [
		0x2B, Gen2WorldPhoneHost.TIME_MORNING, 0x09, 0x20, 0x63, 0x91,
	]
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, 0x6320)] = [
		0x94, Gen2WorldMartHost.MARTTYPE_BARGAIN, 0x00, 0x40, 0x91,
	]
	RomCache.write_json(RomCache.world_scripts_path(Fixture.directory()), scripts)
	_data = GameData.open_directory(Fixture.directory())


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
