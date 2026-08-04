extends GutTest

## Save tests use the same synthetic cache as the battle tests. They exercise
## the save model, validation and storage without opening a real cartridge or
## writing cartridge-derived data.

const Fixture := preload("res://tests/unit/battle_fixture.gd")

var _directory: String = ""
var _data: GameData = null
var _save_directory: String = ""


func before_each() -> void:
	_directory = RomCache.directory_for(&"savetest", "0123456789abcdef")
	_data = Fixture.build(_directory)
	_save_directory = "%s/testgame_01234567" % Gen2SaveStore.ROOT
	_clear_saves()


func after_each() -> void:
	_clear_saves()
	RomCache.clear(_directory)


func _clear_saves() -> void:
	for slot: int in Gen2SaveStore.SLOT_COUNT:
		var path: String = Gen2SaveStore.path_for(_data.id if _data != null else &"savetest", "0123456789abcdef", slot)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(_save_directory):
		DirAccess.remove_absolute(_save_directory)


func _party() -> Gen2Party:
	var pikachu: Gen2BattleMon = Gen2BattleMon.create(
		_data, Fixture.PIKACHU, 20, [Fixture.TACKLE, Fixture.THUNDERBOLT],
		Gen2Stats.pack_dvs(7, 8, 9, 10), {"hp": 1234, "special": 4321}
	)
	pikachu.take_damage(17)
	pikachu.spend_pp(0)
	pikachu.status = Gen2Status.POISON
	var geodude: Gen2BattleMon = Gen2BattleMon.create(
		_data, Fixture.GEODUDE, 18, [Fixture.GROWL], Gen2BattleMon.PERFECT_DVS
	)
	return Gen2Party.create([pikachu, geodude])


func _save() -> Gen2SaveData:
	return Gen2SaveBattleAdapter.from_battle_party(
		_data.id, _data.sha1, 0, _party(), "RED"
	)


func test_a_battle_party_round_trips_into_persistent_fields() -> void:
	var save: Gen2SaveData = _save()
	assert_eq(save.game_id, _data.id)
	assert_eq(save.rom_sha1, _data.sha1)
	assert_eq(save.player_name, "RED")
	assert_eq(save.party.size(), 2)
	var mon: Gen2SaveMon = save.party[0]
	assert_eq(mon.species, Fixture.PIKACHU)
	assert_eq(mon.level, 20)
	assert_eq(mon.moves, [Fixture.TACKLE, Fixture.THUNDERBOLT, 0, 0])
	assert_eq(mon.pp[0], 34)
	assert_eq(mon.status, Gen2Status.POISON)
	assert_eq(mon.stat_exp["hp"], 1234)
	assert_eq(mon.stat_exp["special"], 4321)


func test_a_saved_pokemon_restores_stats_hp_status_exp_and_pp() -> void:
	var save: Gen2SaveData = _save()
	var restored: Gen2Party = Gen2SaveBattleAdapter.to_battle_party(_data, save)
	assert_not_null(restored)
	var original: Gen2BattleMon = _party().at(0)
	var mon: Gen2BattleMon = restored.at(0)
	assert_eq(mon.species, original.species)
	assert_eq(mon.level, original.level)
	assert_eq(mon.dvs, original.dvs)
	assert_eq(mon.stat_exp["hp"], original.stat_exp.get("hp", 0))
	assert_eq(mon.stat_exp["attack"], original.stat_exp.get("attack", 0))
	assert_eq(mon.stat_exp["defense"], original.stat_exp.get("defense", 0))
	assert_eq(mon.stat_exp["speed"], original.stat_exp.get("speed", 0))
	assert_eq(mon.stat_exp["special"], original.stat_exp.get("special", 0))
	assert_eq(mon.exp, original.exp)
	assert_eq(mon.hp, original.hp)
	assert_eq(mon.max_hp(), original.max_hp())
	assert_eq(mon.status, original.status)
	assert_eq(mon.pp, original.pp)
	assert_eq(mon.moves, original.moves)
	assert_eq(mon.substatus, Gen2Substatus.NONE, "volatile battle state is never loaded")


func test_a_valid_save_is_accepted_against_its_cartridge_cache() -> void:
	var result: Dictionary = Gen2SaveValidator.validate(_save(), _data)
	assert_true(result["ok"], result["message"])


func test_a_save_with_the_wrong_cartridge_identity_is_rejected() -> void:
	var save: Gen2SaveData = _save()
	save.rom_sha1 = "different"
	var result: Dictionary = Gen2SaveValidator.validate(save, _data)
	assert_false(result["ok"])
	assert_string_contains(result["message"], "different cartridge")


func test_a_save_with_an_unknown_move_is_rejected() -> void:
	var save: Gen2SaveData = _save()
	(save.party[0] as Gen2SaveMon).moves[0] = 9999
	var result: Dictionary = Gen2SaveValidator.validate(save, _data)
	assert_false(result["ok"])
	assert_string_contains(result["message"], "unknown move")


func test_a_save_with_hp_above_its_derived_maximum_is_rejected() -> void:
	var save: Gen2SaveData = _save()
	var mon: Gen2SaveMon = save.party[0]
	mon.hp = 999
	var result: Dictionary = Gen2SaveValidator.validate(save, _data)
	assert_false(result["ok"])
	assert_string_contains(result["message"], "invalid HP")


func test_save_slots_are_versioned_and_isolated() -> void:
	var save: Gen2SaveData = _save()
	var write: Dictionary = Gen2SaveStore.save(save, _data)
	assert_true(write["ok"], write["message"])
	assert_true(Gen2SaveStore.exists(_data.id, _data.sha1, 0))
	assert_false(Gen2SaveStore.exists(_data.id, _data.sha1, 1))

	var loaded: Dictionary = Gen2SaveStore.load_result(_data.id, _data.sha1, 0, _data)
	assert_true(loaded["ok"], loaded["message"])
	assert_eq((loaded["save"] as Gen2SaveData).party.size(), 2)
	var empty: Dictionary = Gen2SaveStore.load_result(_data.id, _data.sha1, 1, _data)
	assert_false(empty["ok"])
	assert_string_contains(empty["message"], "empty")

	save.player_name = "BLUE"
	var rewrite: Dictionary = Gen2SaveStore.save(save, _data)
	assert_true(rewrite["ok"], rewrite["message"])
	var rewritten: Dictionary = Gen2SaveStore.load_result(_data.id, _data.sha1, 0, _data)
	assert_true(rewritten["ok"], rewritten["message"])
	assert_eq((rewritten["save"] as Gen2SaveData).player_name, "BLUE")


func test_a_malformed_slot_is_refused_without_becoming_a_partial_save() -> void:
	var path: String = Gen2SaveStore.path_for(_data.id, _data.sha1, 0)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{\"format_version\": 1, \"party\": [}")
	file.close()
	var result: Dictionary = Gen2SaveStore.load_result(_data.id, _data.sha1, 0, _data)
	assert_false(result["ok"])
	assert_string_contains(result["message"], "valid JSON")
