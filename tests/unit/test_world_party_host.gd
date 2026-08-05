extends GutTest

## Party transactions run against the same synthetic world and battle cache as
## the scene integration tests. The cache shape is cartridge-shaped, but no ROM
## content is needed to test the atomic host boundary.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

var _data: GameData = null
var _world: Gen2WorldAPI = null
var _save: Gen2SaveData = null
var _random := RandomNumberGenerator.new()


func before_each() -> void:
	_data = Fixture.build()
	_add_party_item_metadata()
	_add_capture_metadata()
	_add_trade_record()
	_add_party_scripts()
	_data = GameData.open_directory(Fixture.directory())
	var state := Gen2WorldState.new(
		{}, {}, {0x12: 1, 0x09: 1, 0x14: 1, 0x01: 1, 0x05: 1}
	)
	_world = Gen2WorldAPI.open(_data, Fixture.MAP_GROUP, Fixture.MAP_NUMBER, Vector2i(2, 2), state)
	_save = Gen2SaveStore.create_development_save(_data, 0)
	_save.world = _world.snapshot()
	_random.seed = 7


func after_each() -> void:
	RomCache.clear(Fixture.directory())


func test_givepoke_appends_a_real_save_mon_and_resumes_the_script() -> void:
	_set_script(0x6200)
	var waiting: Array = _world.dispatch_script_events(Vector2i(2, 2))
	assert_eq(waiting[0]["status"], &"waiting")
	assert_eq(_world.pending_runtime_request()["kind"], &"pokemon_requested")

	var result: Dictionary = Gen2WorldHost.complete_runtime_request(
		_world, {}, _save, false, _random
	)
	assert_true(result["ok"])
	assert_eq(result["results"][0]["status"], &"complete")
	assert_eq(_save.party.size(), 3)
	assert_eq(_save.party[2].species, 25)
	assert_eq(_save.party[2].level, 5)
	assert_eq(_save.party[2].item, 0)


func test_giveegg_records_an_egg_without_pretending_it_can_battle() -> void:
	_set_script(0x6210)
	_world.dispatch_script_events(Vector2i(2, 2))
	var result: Dictionary = Gen2WorldHost.complete_runtime_request(
		_world, {}, _save, false, _random
	)
	assert_true(result["ok"])
	assert_eq(result["results"][0]["status"], &"complete")
	assert_true(_save.party[2].is_egg)
	assert_eq(_save.party[2].hp, 0)
	assert_eq(result["transaction"]["kind"], &"egg")


func test_npc_trade_uses_the_imported_record_and_replaces_the_requested_slot() -> void:
	_set_script(0x6220)
	_world.dispatch_script_events(Vector2i(2, 2))
	var result: Dictionary = Gen2WorldHost.complete_runtime_request(
		_world, {}, _save, false, _random
	)
	assert_true(result["ok"])
	assert_eq(_save.party.size(), 2)
	assert_eq(_save.party[0].species, 74)
	assert_eq(_save.party[0].nickname, "ROCKY")
	assert_eq(_save.party[0].original_trainer, "KYLE")
	assert_eq(_save.party[0].ot_id, 48926)


func test_explicit_trade_slot_still_checks_the_record_gender() -> void:
	var requested_battle: Gen2BattleMon = Gen2SaveBattleAdapter.to_battle_mon(
		_data, _save.party[0]
	)
	_data.world_trade(0)["gender"] = (
		RomLayout.TRADE_GENDER_FEMALE
		if requested_battle.gender() == Gen2BattleMon.GENDER_MALE
		else RomLayout.TRADE_GENDER_MALE
	)
	_set_script(0x6220)
	_world.dispatch_script_events(Vector2i(2, 2))
	var before: Dictionary = _save.to_dict()
	var result: Dictionary = Gen2WorldHost.complete_runtime_request(
		_world, {"party_index": 0}, _save, false, _random
	)
	assert_false(result["ok"])
	assert_eq(result["reason"], &"trade_candidate_gender_mismatch")
	assert_eq(_save.to_dict(), before)


func test_full_party_is_a_script_zero_result_without_mutating_the_save() -> void:
	while _save.party.size() < Gen2SaveData.MAX_PARTY:
		var copy: Gen2SaveMon = Gen2SaveMon.from_dict(_save.party[0].to_dict())
		_save.party.append(copy)
	var before: Dictionary = _save.to_dict()
	_set_script(0x6200)
	_world.dispatch_script_events(Vector2i(2, 2))
	var result: Dictionary = Gen2WorldHost.complete_runtime_request(
		_world, {}, _save, false, _random
	)
	assert_true(result["ok"])
	assert_eq(result["transaction"]["accepted"], false)
	assert_eq(_save.to_dict(), before)


func test_potion_cures_a_party_member_and_consumes_one_item() -> void:
	var mon: Gen2SaveMon = _save.party[0]
	mon.hp = 1
	var before_quantity: int = _world.state.item_quantity(0x12)
	var result: Dictionary = Gen2WorldPartyHost.use_item(
		_world, _save, 0x12, 0, false
	)
	assert_true(result["ok"])
	assert_gt(_save.party[0].hp, 1)
	assert_eq(_world.state.item_quantity(0x12), before_quantity - 1)


func test_item_with_no_effect_is_not_consumed() -> void:
	var before_quantity: int = _world.state.item_quantity(0x09)
	var result: Dictionary = Gen2WorldPartyHost.use_item(
		_world, _save, 0x09, 0, false
	)
	assert_false(result["ok"])
	assert_eq(_world.state.item_quantity(0x09), before_quantity)


func test_master_ball_captures_a_wild_mon_and_records_catch_metadata() -> void:
	var wild: Gen2BattleMon = Gen2BattleMon.create(
		_data, 25, 5, _data.moves_at_level(25, 5), 0x1234
	)
	var result: Dictionary = Gen2WorldPartyHost.capture_wild(
		_world, _save, wild, 0x01, _random, 42, false
	)
	assert_true(result["ok"])
	assert_true(result["caught"])
	assert_eq(result["wobbles"], 3)
	assert_eq(_save.party.size(), 3)
	assert_eq(_save.party[2].species, 25)
	assert_eq(_save.party[2].hp, wild.max_hp())
	assert_eq(_save.party[2].caught_level, 5)
	assert_eq(_save.party[2].caught_location, 42)
	assert_eq(_save.party[2].original_trainer, _save.player_name)
	assert_eq(_world.state.item_quantity(0x01), 0)


func test_failed_poke_ball_still_consumes_the_ball_without_adding_a_mon() -> void:
	_data.species(25)["catch_rate"] = 1
	var wild: Gen2BattleMon = Gen2BattleMon.create(
		_data, 25, 5, _data.moves_at_level(25, 5), 0xFFFF
	)
	var result: Dictionary = Gen2WorldPartyHost.capture_wild(
		_world, _save, wild, 0x05, _random, 0, false
	)
	assert_true(result["ok"])
	assert_false(result["caught"])
	assert_eq(_save.party.size(), 2)
	assert_eq(_world.state.item_quantity(0x05), 0)


func _set_script(address: int) -> void:
	_world.current_map.events["coord_events"] = [{
		"scene": 0, "x": 2, "y": 2, "script": address,
	}]


func _add_party_scripts() -> void:
	var scripts: Dictionary = RomCache.read_json(
		RomCache.world_scripts_path(Fixture.directory())
	)
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, 0x6200)] = [0x2D, 25, 5, 0, 0, 0x91]
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, 0x6210)] = [0x2E, 25, 5, 0x91]
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, 0x6220)] = [0x96, 0, 0x91]
	RomCache.write_json(RomCache.world_scripts_path(Fixture.directory()), scripts)


func _add_trade_record() -> void:
	RomCache.write_json(RomCache.world_trades_path(Fixture.directory()), [{
		"trade_id": 0,
		"dialog": 0,
		"requested_species": 155,
		"offered_species": 74,
		"nickname": "ROCKY",
		"dvs": 0x9666,
		"item": 0,
		"ot_id": 48926,
		"ot_name": "KYLE",
		"gender": RomLayout.TRADE_GENDER_EITHER,
	}])


func _add_party_item_metadata() -> void:
	var items: Array = RomCache.read_json(RomCache.items_path(Fixture.directory()))
	for raw: Dictionary in items:
		var number: int = int(raw["number"])
		raw["permissions"] = RomLayout.ITEM_ATTRIBUTE_CANT_SELECT
		raw["pocket"] = 0
		raw["field_menu"] = RomLayout.ITEMMENU_PARTY
		raw["battle_menu"] = RomLayout.ITEMMENU_PARTY
		raw["status_mask"] = 0
		raw["heal_amount"] = 0
		if number == 0x12:
			raw["heal_amount"] = 20
		if number == 0x09:
			raw["status_mask"] = Gen2Status.POISON
		if number == 0x14:
			raw["field_menu"] = RomLayout.ITEMMENU_CURRENT
		if number == 0x05:
			raw["pocket"] = RomLayout.ITEM_POCKET_BALL
			raw["field_menu"] = 0
			raw["battle_menu"] = RomLayout.ITEMMENU_CLOSE
	RomCache.write_json(RomCache.items_path(Fixture.directory()), items)


func _add_capture_metadata() -> void:
	var species: Array = RomCache.read_json(RomCache.species_path(Fixture.directory()))
	for raw: Dictionary in species:
		if int(raw["number"]) == 25:
			raw["catch_rate"] = 190
	RomCache.write_json(RomCache.species_path(Fixture.directory()), species)
	var items: Array = RomCache.read_json(RomCache.items_path(Fixture.directory()))
	for raw: Dictionary in items:
		if int(raw["number"]) in [0x01, 0x02, 0x04, 0x05]:
			raw["pocket"] = RomLayout.ITEM_POCKET_BALL
	RomCache.write_json(RomCache.items_path(Fixture.directory()), items)
