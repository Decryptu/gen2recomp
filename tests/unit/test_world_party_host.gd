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
	_add_party_evolution_metadata()
	_data = GameData.open_directory(Fixture.directory())
	var state := Gen2WorldState.new(
		{}, {}, {0x08: 1, 0x12: 1, 0x09: 1, 0x14: 1, 0x01: 1, 0x05: 1}
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


func test_full_party_stores_a_gift_in_the_first_pc_box_slot() -> void:
	while _save.party.size() < Gen2SaveData.MAX_PARTY:
		var copy: Gen2SaveMon = Gen2SaveMon.from_dict(_save.party[0].to_dict())
		_save.party.append(copy)
	_set_script(0x6200)
	_world.dispatch_script_events(Vector2i(2, 2))
	var result: Dictionary = Gen2WorldHost.complete_runtime_request(
		_world, {}, _save, false, _random
	)
	assert_true(result["ok"])
	assert_true(result["transaction"]["accepted"])
	assert_eq(_save.party.size(), Gen2SaveData.MAX_PARTY)
	assert_eq(_save.boxes[0].slots[0].species, 25)
	assert_eq(result["transaction"]["destination"]["destination"], &"box")


func test_full_party_and_boxes_refuse_a_gift_without_mutation() -> void:
	while _save.party.size() < Gen2SaveData.MAX_PARTY:
		_save.party.append(Gen2SaveMon.from_dict(_save.party[0].to_dict()))
	for box: Gen2SaveBox in _save.boxes:
		for slot: int in Gen2SaveBox.CAPACITY:
			box.slots[slot] = Gen2SaveMon.from_dict(_save.party[0].to_dict())
	var before: Dictionary = _save.to_dict()
	_set_script(0x6200)
	_world.dispatch_script_events(Vector2i(2, 2))
	var result: Dictionary = Gen2WorldHost.complete_runtime_request(
		_world, {}, _save, false, _random
	)
	assert_false(result["ok"])
	assert_eq(result["reason"], &"storage_full")
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


func test_moon_stone_evolves_a_party_member_and_consumes_the_item() -> void:
	var source: Gen2BattleMon = Gen2BattleMon.create(_data, 1, 5)
	source.hp = maxi(source.max_hp() - 3, 1)
	source.happiness = 80
	_save.party[0] = Gen2SaveBattleAdapter.from_battle_mon(source)
	_save.party[0].nickname = "SPROUT"
	var before_quantity: int = _world.state.item_quantity(0x08)
	var before_hp: int = _save.party[0].hp
	var before_max_hp: int = Gen2SaveBattleAdapter.to_battle_mon(
		_data, _save.party[0]
	).max_hp()

	var result: Dictionary = Gen2WorldPartyHost.use_item(
		_world, _save, 0x08, 0, false
	)

	assert_true(result["ok"], JSON.stringify(result))
	assert_eq(result["effect"], &"evolution")
	assert_eq(result["old_species"], 1)
	assert_eq(result["new_species"], 2)
	assert_eq(_save.party[0].species, 2)
	assert_eq(_save.party[0].nickname, "SPROUT")
	assert_eq(_world.state.item_quantity(0x08), before_quantity - 1)
	var evolved: Gen2BattleMon = Gen2SaveBattleAdapter.to_battle_mon(_data, _save.party[0])
	assert_eq(_save.party[0].hp, before_hp + evolved.max_hp() - before_max_hp)


func _add_party_evolution_metadata() -> void:
	var species: Array = RomCache.read_json(RomCache.species_path(Fixture.directory()))
	for raw: Dictionary in species:
		if int(raw["number"]) != 1:
			continue
		(raw["evolutions"] as Array).append({
			"method": RomLayout.EVOLVE_ITEM, "parameter": 0x08,
			"condition": 0, "target": 2,
		})
		break
	RomCache.write_json(RomCache.species_path(Fixture.directory()), species)


## TM01 and HM04 in this fixture's cache. The party's first member learns both,
## the second learns neither, so one save covers compatibility both ways.
const TM_ITEM: int = 0xBF
const HM_ITEM: int = 0xF6
const TM_MOVE: int = 0xDF
const HM_MOVE: int = 0x46


func _add_tmhm_metadata() -> void:
	var table: Array = []
	for index: int in RomLayout.TMHM_TM_COUNT + RomLayout.TMHM_HM_COUNT:
		table.append(0x60 + index)
	table[0] = TM_MOVE
	table[RomLayout.TMHM_TM_COUNT + 3] = HM_MOVE
	RomCache.write_json(RomCache.tmhm_moves_path(Fixture.directory()), table)

	var species: Array = RomCache.read_json(RomCache.species_path(Fixture.directory()))
	for raw: Dictionary in species:
		var flags: Array = []
		flags.resize(RomLayout.TMHM_BYTES)
		for index: int in flags.size():
			flags[index] = 0
		if int(raw["number"]) == _save.party[0].species:
			# TMNUM 1 (TM01) and 54 (HM04), bit index TMNUM - 1 from the low bit.
			flags[0] = 0x01
			flags[6] = 0x20
		raw["tmhm"] = flags
	RomCache.write_json(RomCache.species_path(Fixture.directory()), species)

	var moves: Array = RomCache.read_json(RomCache.moves_path(Fixture.directory()))
	for raw: Dictionary in moves:
		if int(raw["number"]) in [TM_MOVE, HM_MOVE]:
			raw["pp"] = 15
	RomCache.write_json(RomCache.moves_path(Fixture.directory()), moves)

	# The fixture's item table stops short of the TM/HM range, and the save
	# validator rejects a world holding an item the cache does not know, so the
	# rows have to exist before either can sit in the bag.
	var items: Array = RomCache.read_json(RomCache.items_path(Fixture.directory()))
	while items.size() < HM_ITEM:
		var number: int = items.size() + 1
		items.append({
			"number": number, "name": "TM%02d" % number,
			"permissions": 0, "pocket": Gen2WorldPack.TYPE_TM_HM,
			"field_menu": 0, "battle_menu": 0, "status_mask": 0, "heal_amount": 0,
		})
	RomCache.write_json(RomCache.items_path(Fixture.directory()), items)

	_data = GameData.open_directory(Fixture.directory())
	_world.data = _data


func _teachable_save() -> Gen2SaveMon:
	_add_tmhm_metadata()
	var mon: Gen2SaveMon = _save.party[0]
	mon.moves = [1, 0, 0, 0]
	mon.pp = [10, 0, 0, 0]
	return mon


## LearnMove writes the move into the first empty slot and its PP from
## Moves + MOVE_PP, so a freshly taught move arrives at full PP. TeachTMHM
## returns straight after IsHM, so an HM is never consumed.
func test_teaching_an_hm_fills_the_first_empty_slot_and_keeps_the_hm() -> void:
	var mon: Gen2SaveMon = _teachable_save()
	_world.state.apply_changes({}, {}, {"items": {HM_ITEM: 1}})
	var result: Dictionary = Gen2WorldPartyHost.teach_tm_hm(_world, _save, HM_ITEM, 0, -1, false)
	assert_true(result["ok"], JSON.stringify(result))
	assert_eq(int(result["move"]), HM_MOVE)
	assert_eq(int(result["slot"]), 1)
	assert_eq(int(result["pp"]), 15)
	assert_false(bool(result["consumed"]))
	# _copy_save() rebuilds the party from the candidate, so the committed mon is
	# a new object and the one held before the call is stale.
	var taught: Gen2SaveMon = _save.party[0]
	assert_eq(taught.moves[1], HM_MOVE)
	assert_eq(taught.pp[1], 15)
	assert_eq(taught.moves[0], mon.moves[0], "the slot already in use is untouched")
	assert_eq(_world.state.item_quantity(HM_ITEM), 1)


## ConsumeTM runs for a TM, after IsHM lets it through.
func test_teaching_a_tm_consumes_it() -> void:
	_teachable_save()
	_world.state.apply_changes({}, {}, {"items": {TM_ITEM: 2}})
	var result: Dictionary = Gen2WorldPartyHost.teach_tm_hm(_world, _save, TM_ITEM, 0, -1, false)
	assert_true(result["ok"], JSON.stringify(result))
	assert_true(bool(result["consumed"]))
	assert_eq(_world.state.item_quantity(TM_ITEM), 1)


## The refusal order is CanLearnTMHMMove, then KnowsMove, then LearnMove's slot
## search. Each answers before anything is written.
func test_teaching_refuses_an_incompatible_species_without_writing() -> void:
	_teachable_save()
	_world.state.apply_changes({}, {}, {"items": {HM_ITEM: 1}})
	var before: Dictionary = _save.to_dict()
	var result: Dictionary = Gen2WorldPartyHost.teach_tm_hm(_world, _save, HM_ITEM, 1, -1, false)
	assert_false(result["ok"])
	assert_eq(result["reason"], &"not_compatible")
	assert_eq(_save.to_dict(), before)
	assert_eq(_world.state.item_quantity(HM_ITEM), 1)


func test_teaching_refuses_a_move_the_mon_already_knows() -> void:
	var mon: Gen2SaveMon = _teachable_save()
	mon.moves = [HM_MOVE, 0, 0, 0]
	_world.state.apply_changes({}, {}, {"items": {HM_ITEM: 1}})
	var result: Dictionary = Gen2WorldPartyHost.teach_tm_hm(_world, _save, HM_ITEM, 0, -1, false)
	assert_false(result["ok"])
	assert_eq(result["reason"], &"already_knows_move")
	assert_eq(_world.state.item_quantity(HM_ITEM), 1)


## Where LearnMove opens ForgetMove. With no slot named, this is the call that
## runs the two compatibility checks and then asks; it writes nothing, and it
## carries the moves the menu lists.
func test_teaching_a_full_moveset_asks_rather_than_replacing_one() -> void:
	var mon: Gen2SaveMon = _teachable_save()
	mon.moves = [1, 2, 3, 4]
	mon.pp = [10, 10, 10, 10]
	_world.state.apply_changes({}, {}, {"items": {HM_ITEM: 1}})
	var result: Dictionary = Gen2WorldPartyHost.teach_tm_hm(_world, _save, HM_ITEM, 0, -1, false)
	assert_false(result["ok"])
	assert_eq(result["reason"], &"moveset_full")
	assert_eq(result["details"]["moves"], [1, 2, 3, 4], "the list ForgetMove's menu draws")
	assert_eq(mon.moves, [1, 2, 3, 4])
	assert_eq(_world.state.item_quantity(HM_ITEM), 1)


## LearnMove.learn writes the same way on both branches, so a forgotten slot
## takes the new move at full PP just as an empty one does.
func test_teaching_with_a_forget_slot_replaces_that_move_at_full_pp() -> void:
	var mon: Gen2SaveMon = _teachable_save()
	mon.moves = [1, 2, 3, 4]
	mon.pp = [10, 10, 10, 10]
	_world.state.apply_changes({}, {}, {"items": {TM_ITEM: 1}})
	var result: Dictionary = Gen2WorldPartyHost.teach_tm_hm(_world, _save, TM_ITEM, 0, 2, false)
	assert_true(result["ok"], JSON.stringify(result))
	assert_eq(int(result["slot"]), 2)
	assert_eq(int(result["forgot"]), 3)
	assert_eq(int(result["pp"]), 15)
	var taught: Gen2SaveMon = _save.party[0]
	assert_eq(taught.moves, [1, 2, TM_MOVE, 4])
	assert_eq(taught.pp[2], 15)
	## ConsumeTM still runs: a forgotten move does not change whether the item is
	## used up, only IsHM does.
	assert_true(bool(result["consumed"]))
	assert_eq(_world.state.item_quantity(TM_ITEM), 0)


## ForgetMove's .hmmove branch never returns an HM slot, so one arriving here is
## refused outright rather than honoured.
func test_teaching_refuses_to_forget_an_hm_move_without_writing() -> void:
	var mon: Gen2SaveMon = _teachable_save()
	# Slot 1 is SURF, HM03.
	mon.moves = [1, 0x39, 3, 4]
	mon.pp = [10, 10, 10, 10]
	_world.state.apply_changes({}, {}, {"items": {TM_ITEM: 1}})
	var before: Dictionary = _save.to_dict()
	var result: Dictionary = Gen2WorldPartyHost.teach_tm_hm(_world, _save, TM_ITEM, 0, 1, false)
	assert_false(result["ok"])
	assert_eq(result["reason"], &"cannot_forget_hm")
	assert_eq(int(result["details"]["forgot"]), 0x39)
	assert_eq(_save.to_dict(), before)
	assert_eq(_world.state.item_quantity(TM_ITEM), 1)


func test_teaching_refuses_an_out_of_range_forget_slot_without_writing() -> void:
	var mon: Gen2SaveMon = _teachable_save()
	mon.moves = [1, 2, 3, 4]
	mon.pp = [10, 10, 10, 10]
	_world.state.apply_changes({}, {}, {"items": {TM_ITEM: 1}})
	var before: Dictionary = _save.to_dict()
	var result: Dictionary = Gen2WorldPartyHost.teach_tm_hm(_world, _save, TM_ITEM, 0, 4, false)
	assert_false(result["ok"])
	assert_eq(result["reason"], &"invalid_forget_slot")
	assert_eq(_save.to_dict(), before)


## LearnMove.loop reaches ForgetMove only when its own scan finds no zero, so an
## empty slot wins over a slot the caller named. The save model keeps moves
## contiguous, so the gap is at the end.
func test_an_empty_slot_wins_over_a_passed_forget_slot() -> void:
	var mon: Gen2SaveMon = _teachable_save()
	mon.moves = [1, 2, 0, 0]
	mon.pp = [10, 10, 0, 0]
	_world.state.apply_changes({}, {}, {"items": {HM_ITEM: 1}})
	var result: Dictionary = Gen2WorldPartyHost.teach_tm_hm(_world, _save, HM_ITEM, 0, 0, false)
	assert_true(result["ok"], JSON.stringify(result))
	assert_eq(int(result["slot"]), 2, "the first empty slot, not the named one")
	assert_eq(int(result["forgot"]), 0)
	assert_eq(_save.party[0].moves, [1, 2, HM_MOVE, 0])


func test_teaching_refuses_an_item_that_is_not_a_tm_or_hm_and_an_absent_one() -> void:
	_teachable_save()
	_world.state.apply_changes({}, {}, {"items": {HM_ITEM: 1}})
	assert_eq(
		Gen2WorldPartyHost.teach_tm_hm(_world, _save, 0x12, 0, -1, false)["reason"],
		&"not_a_tm_hm"
	)
	# ConvertCurItemIntoCurTMHM is reached only from the pocket, so an item the
	# bag does not hold fails on the quantity first.
	assert_eq(
		Gen2WorldPartyHost.teach_tm_hm(_world, _save, TM_ITEM, 0, -1, false)["reason"],
		&"insufficient_item_quantity"
	)


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


func test_a_full_party_capture_uses_the_first_pc_box_slot() -> void:
	while _save.party.size() < Gen2SaveData.MAX_PARTY:
		_save.party.append(Gen2SaveMon.from_dict(_save.party[0].to_dict()))
	var wild: Gen2BattleMon = Gen2BattleMon.create(
		_data, 25, 5, _data.moves_at_level(25, 5), 0x1234
	)
	var result: Dictionary = Gen2WorldPartyHost.capture_wild(
		_world, _save, wild, 0x01, _random, 42, false
	)
	assert_true(result["ok"])
	assert_true(result["caught"])
	assert_eq(_save.party.size(), Gen2SaveData.MAX_PARTY)
	assert_eq(_save.boxes[0].slots[0].species, 25)
	assert_eq(result["destination"]["destination"], &"box")


func test_full_storage_refuses_a_capture_before_consuming_the_ball() -> void:
	while _save.party.size() < Gen2SaveData.MAX_PARTY:
		_save.party.append(Gen2SaveMon.from_dict(_save.party[0].to_dict()))
	for box: Gen2SaveBox in _save.boxes:
		for slot: int in Gen2SaveBox.CAPACITY:
			box.slots[slot] = Gen2SaveMon.from_dict(_save.party[0].to_dict())
	var before_quantity: int = _world.state.item_quantity(0x01)
	var wild: Gen2BattleMon = Gen2BattleMon.create(
		_data, 25, 5, _data.moves_at_level(25, 5), 0x1234
	)
	var result: Dictionary = Gen2WorldPartyHost.capture_wild(
		_world, _save, wild, 0x01, _random, 42, false
	)
	assert_false(result["ok"])
	assert_eq(result["reason"], &"storage_full")
	assert_eq(_world.state.item_quantity(0x01), before_quantity)


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


## `Softboiled_MilkDrinkFunction`: a fifth of the user's own maximum health moved
## to another party member, and the three refusals `.SelectMilkDrinkRecipient`
## loops on.

func _fifth_of(index: int) -> int:
	return Gen2WorldPartyHost.one_fifth_max_hp(_data, _save.party[index])


func test_softboiled_moves_a_fifth_of_the_users_own_maximum() -> void:
	var amount: int = _fifth_of(0)
	assert_gt(amount, 0)
	_save.party[1].hp = 1
	var before: int = _save.party[0].hp

	var result: Dictionary = Gen2WorldPartyHost.transfer_health(_world, _save, 0, 1, false)
	assert_true(result["ok"], String(result.get("reason", "")))
	assert_eq(int(result["amount"]), amount)
	assert_eq(_save.party[0].hp, before - amount)
	assert_eq(_save.party[1].hp, 1 + int(result["restored"]))


func test_the_healed_member_is_never_taken_past_its_own_maximum() -> void:
	# The user's fifth is what is spent whatever the recipient can hold, which is
	# why the two numbers are reported separately.
	var max_hp: int = Gen2SaveBattleAdapter.to_battle_mon(_data, _save.party[1]).max_hp()
	_save.party[1].hp = max_hp - 1
	var result: Dictionary = Gen2WorldPartyHost.transfer_health(_world, _save, 0, 1, false)
	assert_true(result["ok"], String(result.get("reason", "")))
	assert_eq(_save.party[1].hp, max_hp)
	assert_eq(int(result["restored"]), 1)
	assert_eq(int(result["amount"]), _fifth_of(0))


func test_a_user_on_a_fifth_or_less_cannot_give_health_away() -> void:
	# `.CheckMonHasEnoughHP` wants more than the fifth, not the fifth itself.
	_save.party[1].hp = 1
	_save.party[0].hp = _fifth_of(0)
	var result: Dictionary = Gen2WorldPartyHost.transfer_health(_world, _save, 0, 1, false)
	assert_false(bool(result.get("ok", false)))
	assert_eq(StringName(result["reason"]), &"not_enough_health")
	assert_eq(_save.party[1].hp, 1, "and nothing moved")


func test_the_user_itself_a_fainted_member_and_a_full_one_are_all_refused() -> void:
	assert_eq(
		StringName(Gen2WorldPartyHost.transfer_health(_world, _save, 0, 0, false)["reason"]),
		&"same_member"
	)
	assert_eq(
		StringName(Gen2WorldPartyHost.transfer_health(_world, _save, 0, 1, false)["reason"]),
		&"already_full"
	)
	_save.party[1].hp = 0
	assert_eq(
		StringName(Gen2WorldPartyHost.transfer_health(_world, _save, 0, 1, false)["reason"]),
		&"fainted_member"
	)
