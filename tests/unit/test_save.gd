extends GutTest

## Save tests use the same synthetic cache as the battle tests. The cartridge
## fixtures exercise the real SRAM byte boundary without requiring a physical
## cartridge or emulator save file.

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
	var game_id: StringName = _data.id if _data != null else &"savetest"
	for slot: int in Gen2SaveStore.MAX_SLOTS:
		var path: String = Gen2SaveStore.path_for(game_id, "0123456789abcdef", slot)
		for copy: String in [path, "%s.bak" % path, "%s.tmp" % path, "%s.bak.tmp" % path]:
			if FileAccess.file_exists(copy):
				DirAccess.remove_absolute(copy)
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


func test_battle_save_writeback_preserves_player_and_pokemon_identity() -> void:
	var source: Gen2SaveData = _save()
	(source.party[0] as Gen2SaveMon).nickname = "SPARKY"
	(source.party[0] as Gen2SaveMon).original_trainer = "RED"
	var boxed: Gen2SaveMon = Gen2SaveMon.from_dict(source.party[1].to_dict())
	source.boxes[2].slots[4] = boxed
	source.world = Gen2WorldSnapshot.new()
	source.world.map_id = Vector2i(1, 1)
	var party: Gen2Party = Gen2SaveBattleAdapter.to_battle_party(_data, source)
	var written: Gen2SaveData = Gen2SaveBattleAdapter.from_battle_party(
		_data.id, _data.sha1, source.slot, party, "", source
	)
	assert_eq(written.player_name, "RED")
	assert_eq((written.party[0] as Gen2SaveMon).nickname, "SPARKY")
	assert_eq((written.party[0] as Gen2SaveMon).original_trainer, "RED")
	assert_eq(written.boxes[2].slots[4].species, boxed.species)
	assert_not_null(written.world)
	assert_eq(written.world.map_id, Vector2i(1, 1))


func _save_with_egg_between() -> Gen2SaveData:
	var source: Gen2SaveData = _save()
	var egg := Gen2SaveMon.new()
	egg.is_egg = true
	egg.species = Fixture.CHARMANDER
	egg.level = 5
	egg.nickname = "EGG"
	egg.original_trainer = "RED"
	source.party.insert(1, egg)
	return source


func test_an_egg_keeps_its_party_slot_and_stays_out_of_the_battle_party() -> void:
	var source: Gen2SaveData = _save_with_egg_between()
	assert_eq(source.party.size(), 3)
	var party: Gen2Party = Gen2SaveBattleAdapter.to_battle_party(_data, source)
	assert_not_null(party, "an egg is skipped, not a party the battle engine refuses")
	assert_eq(party.mons.size(), 2)
	assert_eq(party.at(0).species, Fixture.PIKACHU)
	assert_eq(party.at(1).species, Fixture.GEODUDE)


func test_a_battle_writeback_puts_the_egg_back_in_its_own_slot() -> void:
	var source: Gen2SaveData = _save_with_egg_between()
	var party: Gen2Party = Gen2SaveBattleAdapter.to_battle_party(_data, source)
	var written: Gen2SaveData = Gen2SaveBattleAdapter.from_battle_party(
		_data.id, _data.sha1, source.slot, party, "", source
	)
	assert_not_null(written)
	assert_eq(written.party.size(), 3)
	assert_eq((written.party[0] as Gen2SaveMon).species, Fixture.PIKACHU)
	assert_false((written.party[0] as Gen2SaveMon).is_egg)
	assert_true((written.party[1] as Gen2SaveMon).is_egg)
	assert_eq((written.party[1] as Gen2SaveMon).species, Fixture.CHARMANDER)
	assert_eq((written.party[1] as Gen2SaveMon).nickname, "EGG")
	assert_eq((written.party[2] as Gen2SaveMon).species, Fixture.GEODUDE)
	assert_false((written.party[2] as Gen2SaveMon).is_egg)


func test_a_party_of_nothing_but_eggs_has_no_fit_mon() -> void:
	var source: Gen2SaveData = _save()
	for mon: Gen2SaveMon in source.party:
		mon.is_egg = true
	assert_null(Gen2SaveBattleAdapter.to_battle_party(_data, source))


func test_new_game_starts_empty_until_the_elm_lab_handoff() -> void:
	var created: Gen2SaveData = Gen2SaveStore.create_new_game(_data, 1, "ASH", 155)
	assert_not_null(created)
	assert_eq(created.player_name, "ASH")
	assert_eq(created.slot, 1)
	assert_eq(created.party.size(), 0)
	assert_null(created.world)
	var validation: Dictionary = Gen2SaveValidator.validate(created, _data)
	assert_true(validation["ok"], validation["message"])


## wPlayerID is rolled once when the game starts. The generator is injectable
## so a run that has to reproduce itself can pin it; GetTreeScore reads the
## result, so an unpinned one would move every headbutt tier.
func test_a_new_game_rolls_a_player_id_and_a_seeded_generator_pins_it() -> void:
	var generator := RandomNumberGenerator.new()
	generator.seed = 99
	var first: Gen2SaveData = Gen2SaveStore.create_new_game(_data, 1, "ASH", -1, generator)
	generator.seed = 99
	var second: Gen2SaveData = Gen2SaveStore.create_new_game(_data, 1, "ASH", -1, generator)
	assert_eq(first.player_id, second.player_id)
	assert_between(first.player_id, 0, 0xFFFF)
	# The whole two bytes survive the round trip, unlike a value clamped to a
	# byte or dropped by to_dict().
	var restored: Gen2SaveData = Gen2SaveData.from_dict(first.to_dict())
	assert_eq(restored.player_id, first.player_id)


func test_development_save_has_a_valid_default_player_name() -> void:
	var result: Dictionary = Gen2SaveStore.ensure_development_save(_data, 2)
	assert_true(result["ok"], result["message"])
	assert_eq((result["save"] as Gen2SaveData).player_name, "PLAYER")


func test_a_valid_save_is_accepted_against_its_cartridge_cache() -> void:
	var result: Dictionary = Gen2SaveValidator.validate(_save(), _data)
	assert_true(result["ok"], result["message"])
	assert_eq((_save().boxes as Array).size(), Gen2SaveData.BOX_COUNT)


func test_boxed_pokemon_round_trips_and_is_validated_against_the_cache() -> void:
	var save: Gen2SaveData = _save()
	var boxed: Gen2SaveMon = Gen2SaveMon.from_dict(save.party[0].to_dict())
	save.boxes[2].slots[4] = boxed
	var validation: Dictionary = Gen2SaveValidator.validate(save, _data)
	assert_true(validation["ok"], validation["message"])
	var round_trip: Gen2SaveData = Gen2SaveData.from_dict(save.to_dict())
	assert_eq(round_trip.boxes.size(), Gen2SaveData.BOX_COUNT)
	assert_eq(round_trip.boxes[2].occupied_count(), 1)
	assert_eq(round_trip.boxes[2].slots[4].species, boxed.species)


func test_per_mod_save_namespaces_round_trip_without_aliasing() -> void:
	var save: Gen2SaveData = _save()
	assert_true(save.set_mod_data(&"weather_plus", {
		"seed": 42, "visits": [1, 2], "nested": {"enabled": true},
	})["ok"])
	var read: Dictionary = save.mod_data(&"weather_plus")
	read["seed"] = 99
	assert_eq(save.mod_data(&"weather_plus")["seed"], 42)
	var restored: Gen2SaveData = Gen2SaveData.from_dict(save.to_dict())
	assert_eq(restored.mod_data(&"weather_plus"), save.mod_data(&"weather_plus"))


func test_mod_save_namespaces_refuse_bad_ids_and_large_documents() -> void:
	var save: Gen2SaveData = _save()
	assert_eq(save.set_mod_data(&"Bad Id", {"x": 1})["reason"], &"invalid_mod_save_id")
	assert_eq(
		save.set_mod_data(&"large", {"text": "x".repeat(65537)})["reason"],
		&"mod_save_too_large"
	)


## The seed and the mod list a crash report or a replay would name, beside the
## per-mod namespace rather than inside it.
func test_the_run_block_round_trips_and_refuses_an_invented_mod_id() -> void:
	var save: Gen2SaveData = _save()
	save.run_seed = 0x0BADF00D
	save.run_mods = [
		{"id": "weather_plus", "version": "1.2.0"},
		{"id": "Bad Id", "version": "9"},
	]
	var restored: Gen2SaveData = Gen2SaveData.from_dict(save.to_dict())
	assert_eq(restored.run_seed, 0x0BADF00D)
	assert_eq(restored.run_mods, [{"id": "weather_plus", "version": "1.2.0"}])


## A slot written before the block existed says so rather than claiming frame
## zero of a seeded run.
func test_a_save_without_a_run_block_records_no_seed() -> void:
	var raw: Dictionary = _save().to_dict()
	raw.erase("run")
	var restored: Gen2SaveData = Gen2SaveData.from_dict(raw)
	assert_not_null(restored)
	assert_eq(restored.run_seed, 0)
	assert_eq(restored.run_mods, [])


func test_format_five_migrates_to_an_empty_mod_namespace() -> void:
	var raw: Dictionary = _save().to_dict()
	raw["format_version"] = 5
	raw.erase("mods")
	var restored: Gen2SaveData = Gen2SaveData.from_dict(raw)
	assert_not_null(restored)
	assert_eq(restored.mods, {})


func test_a_current_save_with_the_wrong_box_shape_is_rejected() -> void:
	var save: Gen2SaveData = _save()
	var raw: Dictionary = save.to_dict()
	(raw["boxes"] as Array).pop_back()
	var malformed: Gen2SaveData = Gen2SaveData.from_dict(raw)
	var result: Dictionary = Gen2SaveValidator.validate(malformed, _data)
	assert_false(result["ok"])
	assert_string_contains(result["message"], "PC boxes")


func test_a_legacy_save_migrates_to_empty_pc_boxes_without_inventing_world_state() -> void:
	var save: Gen2SaveData = _save()
	var raw: Dictionary = save.to_dict()
	raw["format_version"] = Gen2SaveData.LEGACY_FORMAT_VERSION
	raw.erase("boxes")
	var path: String = Gen2SaveStore.path_for(_data.id, _data.sha1, 0)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(raw))
	file.close()
	var loaded: Dictionary = Gen2SaveStore.load_result(_data.id, _data.sha1, 0, _data)
	assert_true(loaded["ok"], loaded["message"])
	assert_true(loaded["migrated"])
	var migrated: Gen2SaveData = loaded["save"]
	assert_eq(migrated.format_version, Gen2SaveData.FORMAT_VERSION)
	assert_eq(migrated.boxes.size(), Gen2SaveData.BOX_COUNT)
	assert_true(migrated.world == null)
	assert_true(Gen2SaveValidator.validate(migrated, _data)["ok"])


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


func test_a_save_writes_a_primary_and_a_backup_copy() -> void:
	var write: Dictionary = Gen2SaveStore.save(_save(), _data)
	assert_true(write["ok"], write["message"])
	var path: String = Gen2SaveStore.path_for(_data.id, _data.sha1, 0)
	var backup: String = Gen2SaveStore.backup_path_for(_data.id, _data.sha1, 0)
	assert_true(FileAccess.file_exists(path))
	assert_true(FileAccess.file_exists(backup))
	var document: String = _read_text(path)
	assert_eq(_read_text(backup), document)
	assert_true(document.begins_with(
		"%s %d " % [Gen2SaveStore.CONTAINER_PREFIX, Gen2SaveStore.CONTAINER_VERSION]
	))


func test_a_corrupt_primary_is_recovered_from_the_backup() -> void:
	assert_true(Gen2SaveStore.save(_save(), _data)["ok"])
	var path: String = Gen2SaveStore.path_for(_data.id, _data.sha1, 0)
	var document: String = _read_text(path)
	_write_text(path, document.substr(0, document.length() / 2))
	var loaded: Dictionary = Gen2SaveStore.load_result(_data.id, _data.sha1, 0, _data)
	assert_true(loaded["ok"], loaded["message"])
	assert_true(loaded["recovered"])
	var recovered: Gen2SaveData = loaded["save"]
	assert_eq(recovered.player_name, "RED")
	assert_eq(recovered.party.size(), 2)


func test_a_missing_primary_still_reports_the_slot_as_occupied() -> void:
	assert_true(Gen2SaveStore.save(_save(), _data)["ok"])
	DirAccess.remove_absolute(Gen2SaveStore.path_for(_data.id, _data.sha1, 0))
	assert_true(Gen2SaveStore.exists(_data.id, _data.sha1, 0))
	var loaded: Dictionary = Gen2SaveStore.load_result(_data.id, _data.sha1, 0, _data)
	assert_true(loaded["ok"], loaded["message"])
	assert_true(loaded["recovered"])


## A same-length edit still parses and still validates, so the checksum is the
## only thing that can refuse it.
func test_a_tampered_payload_fails_its_checksum() -> void:
	assert_true(Gen2SaveStore.save(_save(), _data)["ok"])
	var path: String = Gen2SaveStore.path_for(_data.id, _data.sha1, 0)
	_write_text(path, _read_text(path).replace("\"RED\"", "\"BLU\""))
	DirAccess.remove_absolute(Gen2SaveStore.backup_path_for(_data.id, _data.sha1, 0))
	var loaded: Dictionary = Gen2SaveStore.load_result(_data.id, _data.sha1, 0, _data)
	assert_false(loaded["ok"])
	assert_string_contains(loaded["message"], "checksum")


func test_both_copies_corrupt_report_the_primary_failure() -> void:
	assert_true(Gen2SaveStore.save(_save(), _data)["ok"])
	for copy: String in [
		Gen2SaveStore.path_for(_data.id, _data.sha1, 0),
		Gen2SaveStore.backup_path_for(_data.id, _data.sha1, 0),
	]:
		_write_text(copy, "{\"format_version\": 1, \"party\": [}")
	var loaded: Dictionary = Gen2SaveStore.load_result(_data.id, _data.sha1, 0, _data)
	assert_false(loaded["ok"])
	assert_string_contains(loaded["message"], "valid JSON")


func test_a_headerless_slot_loads_and_the_next_save_adds_both_copies() -> void:
	var path: String = Gen2SaveStore.path_for(_data.id, _data.sha1, 0)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_write_text(path, JSON.stringify(_save().to_dict(), "\t"))
	var loaded: Dictionary = Gen2SaveStore.load_result(_data.id, _data.sha1, 0, _data)
	assert_true(loaded["ok"], loaded["message"])
	assert_false(loaded["recovered"])
	assert_true(Gen2SaveStore.save(loaded["save"], _data)["ok"])
	var backup: String = Gen2SaveStore.backup_path_for(_data.id, _data.sha1, 0)
	assert_true(FileAccess.file_exists(backup))
	assert_true(_read_text(path).begins_with(Gen2SaveStore.CONTAINER_PREFIX))
	assert_true(_read_text(backup).begins_with(Gen2SaveStore.CONTAINER_PREFIX))


func test_deleting_a_slot_removes_both_copies() -> void:
	assert_true(Gen2SaveStore.save(_save(), _data)["ok"])
	assert_true(Gen2SaveStore.delete_slot(_data.id, _data.sha1, 0))
	assert_false(FileAccess.file_exists(Gen2SaveStore.path_for(_data.id, _data.sha1, 0)))
	assert_false(FileAccess.file_exists(Gen2SaveStore.backup_path_for(_data.id, _data.sha1, 0)))
	assert_false(Gen2SaveStore.exists(_data.id, _data.sha1, 0))


func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var text: String = file.get_as_text()
	file.close()
	return text


func _write_text(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _adapter_data(game_id: StringName) -> GameData:
	_data.id = game_id
	_data.sha1 = RomRegistry.sha1_for(game_id)
	return _data


func _adapter_save(data: GameData) -> Gen2SaveData:
	var save: Gen2SaveData = _save()
	save.game_id = data.id
	save.rom_sha1 = data.sha1
	save.player_name = "RED"
	(save.party[0] as Gen2SaveMon).original_trainer = "RED"
	(save.party[0] as Gen2SaveMon).nickname = "SPARKY"
	(save.party[1] as Gen2SaveMon).original_trainer = "RED"
	(save.party[1] as Gen2SaveMon).nickname = "ROCKY"
	return save


func _raw_cartridge(game_id: StringName, data: GameData) -> PackedByteArray:
	var raw := PackedByteArray()
	raw.resize(Gen2SramAdapter.SRAM_SIZE)
	var layout: Dictionary = Gen2SramAdapter.LAYOUTS[String(game_id)]
	var save: Gen2SaveData = _adapter_save(data)
	raw[int(layout["player_name"])] = 0x80
	_write_fixed_raw_text(raw, int(layout["player_name"]), 11, save.player_name)
	_write_u16_raw(raw, int(layout["player_id"]), SRAM_PLAYER_ID)
	var game_time: Dictionary = layout["game_time"]
	raw[int(game_time["cap"])] = 0xA1
	_write_u16_raw(raw, int(game_time["hours"]), 321)
	raw[int(game_time["minutes"])] = 45
	raw[int(game_time["seconds"])] = 12
	raw[int(game_time["frames"])] = 34
	var party_start: int = int(layout["party"])
	raw[party_start] = save.party.size()
	for index: int in 6:
		raw[party_start + 1 + index] = 0xFF if index >= save.party.size() else int((save.party[index] as Gen2SaveMon).species)
	raw[party_start + 1 + save.party.size()] = 0xFF
	var mons_start: int = party_start + 8
	var ot_start: int = mons_start + 6 * 48
	var nickname_start: int = ot_start + 6 * 11
	for index: int in 6:
		_write_fixed_raw_text(raw, ot_start + index * 11, 11, "")
		_write_fixed_raw_text(raw, nickname_start + index * 11, 11, "")
		if index >= save.party.size():
			continue
		var mon: Gen2SaveMon = save.party[index]
		_write_raw_mon(raw, mons_start + index * 48, mon, data)
		_write_fixed_raw_text(raw, ot_start + index * 11, 11, mon.original_trainer)
		_write_fixed_raw_text(raw, nickname_start + index * 11, 11, mon.nickname)
	raw[0x2500] = 0x77

	raw[int(layout["primary_check_1"])] = Gen2SramAdapter.SAVE_CHECK_VALUE_1
	raw[int(layout["primary_check_2"])] = Gen2SramAdapter.SAVE_CHECK_VALUE_2
	raw[int(layout["backup_check_1"])] = Gen2SramAdapter.SAVE_CHECK_VALUE_1
	raw[int(layout["backup_check_2"])] = Gen2SramAdapter.SAVE_CHECK_VALUE_2
	for segment: Array in layout["backup_segments"]:
		for index: int in int(segment[2]):
			raw[int(segment[1]) + index] = raw[int(segment[0]) + index]
	_write_u16_le_raw(
		raw, int(layout["primary_checksum"]), _raw_checksum(
			raw, [[int(layout["primary_data_start"]), int(layout["primary_data_end"]) - int(layout["primary_data_start"])] ]
		)
	)
	_write_u16_le_raw(
		raw, int(layout["backup_checksum"]), _raw_checksum(raw, layout["backup_checksum_segments"])
	)
	return raw


func _write_raw_mon(raw: PackedByteArray, start: int, mon: Gen2SaveMon, data: GameData) -> void:
	raw[start] = mon.species
	raw[start + 1] = mon.item
	for index: int in Gen2SaveMon.MAX_MOVES:
		raw[start + 2 + index] = int(mon.moves[index])
	_write_u16_raw(raw, start + 6, mon.ot_id)
	raw[start + 8] = (mon.exp >> 16) & 0xFF
	raw[start + 9] = (mon.exp >> 8) & 0xFF
	raw[start + 10] = mon.exp & 0xFF
	for index: int in Gen2SaveMon.STAT_EXP_KEYS.size():
		_write_u16_raw(raw, start + 11 + index * 2, int(mon.stat_exp.get(Gen2SaveMon.STAT_EXP_KEYS[index], 0)))
	_write_u16_raw(raw, start + 21, mon.dvs)
	for index: int in Gen2SaveMon.MAX_MOVES:
		raw[start + 23 + index] = int(mon.pp[index])
	raw[start + 27] = mon.happiness
	raw[start + 28] = mon.pokerus
	raw[start + 29] = (mon.caught_time << 6) | mon.caught_level
	raw[start + 30] = (mon.caught_gender << 7) | mon.caught_location
	raw[start + 31] = mon.level
	raw[start + 32] = mon.status
	raw[start + 34] = (mon.hp >> 8) & 0xFF
	raw[start + 35] = mon.hp & 0xFF
	var base: Dictionary = data.species(mon.species).get("stats", {})
	var max_hp: int = Gen2Stats.calculate(
		int(base.get("hp", 0)), Gen2Stats.hp_dv(mon.dvs), int(mon.stat_exp.get("hp", 0)), mon.level, true
	)
	_write_u16_raw(raw, start + 36, max_hp)
	var stat_keys: Array = ["attack", "defense", "speed", "sp_attack", "sp_defense"]
	var dv_values: Array = [
		Gen2Stats.attack_dv(mon.dvs), Gen2Stats.defense_dv(mon.dvs),
		Gen2Stats.speed_dv(mon.dvs), Gen2Stats.special_dv(mon.dvs), Gen2Stats.special_dv(mon.dvs),
	]
	var exp_keys: Array = ["attack", "defense", "speed", "special", "special"]
	for index: int in stat_keys.size():
		_write_u16_raw(raw, start + 38 + index * 2, Gen2Stats.calculate(
			int(base.get(stat_keys[index], 0)), dv_values[index],
			int(mon.stat_exp.get(exp_keys[index], 0)), mon.level
		))


func _write_fixed_raw_text(raw: PackedByteArray, start: int, length: int, text: String) -> void:
	for index: int in length:
		raw[start + index] = Gen2Text.TERMINATOR
	var encoded: PackedByteArray = Gen2Text.encode(text)
	for index: int in mini(encoded.size(), length - 1):
		raw[start + index] = encoded[index]


func _write_u16_raw(raw: PackedByteArray, offset: int, value: int) -> void:
	raw[offset] = (value >> 8) & 0xFF
	raw[offset + 1] = value & 0xFF


func _write_u16_le_raw(raw: PackedByteArray, offset: int, value: int) -> void:
	raw[offset] = value & 0xFF
	raw[offset + 1] = (value >> 8) & 0xFF


func _raw_checksum(raw: PackedByteArray, segments: Array) -> int:
	var total: int = 0
	for segment: Array in segments:
		var start: int = int(segment[0])
		var length: int = int(segment[1])
		for index: int in length:
			total = (total + int(raw[start + index])) & 0xFFFF
	return total


## wPlayerID, the two big-endian bytes wPlayerData opens with, which is why it
## shares an address with the layout's primary_data_start.
const SRAM_PLAYER_ID: int = 0xBEEF


func test_a_gold_sram_import_reads_the_primary_party_and_fields() -> void:
	var data: GameData = _adapter_data(RomRegistry.GOLD)
	var raw: PackedByteArray = _raw_cartridge(RomRegistry.GOLD, data)
	var result: Dictionary = Gen2SramAdapter.import_bytes(
		RomRegistry.GOLD, data.sha1, 1, raw, data
	)
	assert_true(result["ok"], result["message"])
	assert_eq(result["copy"], "primary")
	var save: Gen2SaveData = result["save"]
	assert_eq(save.slot, 1)
	assert_eq(save.player_name, "RED")
	assert_eq(save.party.size(), 2)
	assert_eq((save.party[0] as Gen2SaveMon).nickname, "SPARKY")
	assert_eq((save.party[0] as Gen2SaveMon).ot_id, 0)
	assert_eq(save.player_id, SRAM_PLAYER_ID)
	assert_eq((save.party[0] as Gen2SaveMon).hp, (_save().party[0] as Gen2SaveMon).hp)


func test_sram_game_time_round_trips_both_profile_layouts() -> void:
	for game_id: StringName in [RomRegistry.GOLD, RomRegistry.CRYSTAL]:
		var data: GameData = _adapter_data(game_id)
		var raw: PackedByteArray = _raw_cartridge(game_id, data)
		var imported: Dictionary = Gen2SramAdapter.import_bytes(
			game_id, data.sha1, 0, raw, data
		)
		assert_true(imported["ok"], imported["message"])
		var source_time: Gen2GameTime = imported["save"].game_time
		assert_eq(source_time.hours, 321, String(game_id))
		assert_eq(source_time.minutes, 45, String(game_id))
		assert_eq(source_time.seconds, 12, String(game_id))
		assert_eq(source_time.frames, 34, String(game_id))
		assert_true(source_time.capped, String(game_id))

		var save: Gen2SaveData = imported["save"]
		save.game_time = Gen2GameTime.create(999, 59, 58, 42, true)
		var exported: Dictionary = Gen2SramAdapter.export_bytes(save, raw, data)
		assert_true(exported["ok"], exported["message"])
		var output: PackedByteArray = exported["raw"]
		var game_time: Dictionary = Gen2SramAdapter.LAYOUTS[String(game_id)]["game_time"]
		assert_eq(output[int(game_time["cap"])] & 0x80, 0x80, String(game_id))
		assert_eq(output[int(game_time["cap"])] & 1, 1, String(game_id))
		var round_trip: Dictionary = Gen2SramAdapter.import_bytes(
			game_id, data.sha1, 0, output, data
		)
		assert_true(round_trip["ok"], round_trip["message"])
		var restored_time: Gen2GameTime = round_trip["save"].game_time
		assert_eq(restored_time.to_dict(), save.game_time.to_dict(), String(game_id))


## `sCrystalData` is its own SRAM section outside both save copies, so the byte
## is neither checksummed nor mirrored into the backup: an import reads it where
## it stands and an export writes it in place.
func test_crystal_carries_the_players_gender_and_the_others_do_not() -> void:
	var data: GameData = _adapter_data(RomRegistry.CRYSTAL)
	var raw: PackedByteArray = _raw_cartridge(RomRegistry.CRYSTAL, data)
	var at: int = int(Gen2SramAdapter.LAYOUTS["crystal"]["player_gender"])
	# The six bytes after it are the mobile profile's, and so are the seven bits
	# beside it; both have to come back untouched.
	raw[at] = 0xF0
	for byte: int in 6:
		raw[at + 1 + byte] = 0xA0 + byte

	var male: Dictionary = Gen2SramAdapter.import_bytes(
		RomRegistry.CRYSTAL, data.sha1, 0, raw, data
	)
	assert_true(male["ok"], male["message"])
	assert_eq((male["save"] as Gen2SaveData).gender, Gen2SaveData.GENDER_MALE)

	raw[at] = 0xF1
	var female: Dictionary = Gen2SramAdapter.import_bytes(
		RomRegistry.CRYSTAL, data.sha1, 0, raw, data
	)
	assert_true(female["ok"], female["message"])
	var save: Gen2SaveData = female["save"]
	assert_eq(save.gender, Gen2SaveData.GENDER_FEMALE)

	save.gender = Gen2SaveData.GENDER_MALE
	var exported: Dictionary = Gen2SramAdapter.export_bytes(save, raw, data)
	assert_true(exported["ok"], exported["message"])
	var output: PackedByteArray = exported["raw"]
	assert_eq(output[at], 0xF0, "only bit 0 of wPlayerGender is ours to write")
	for byte: int in 6:
		assert_eq(output[at + 1 + byte], 0xA0 + byte, "the mobile profile moved")
	assert_eq(
		(Gen2SramAdapter.import_bytes(
			RomRegistry.CRYSTAL, data.sha1, 0, output, data
		)["save"] as Gen2SaveData).gender,
		Gen2SaveData.GENDER_MALE
	)


func test_gold_and_silver_have_no_gender_byte_to_read_or_write() -> void:
	for game_id: StringName in [RomRegistry.GOLD, RomRegistry.SILVER]:
		assert_false(
			Gen2SramAdapter.LAYOUTS[String(game_id)].has("player_gender"),
			"%s has no sCrystalData section" % game_id
		)
		var data: GameData = _adapter_data(game_id)
		var raw: PackedByteArray = _raw_cartridge(game_id, data)
		var imported: Dictionary = Gen2SramAdapter.import_bytes(
			game_id, data.sha1, 0, raw, data
		)
		assert_true(imported["ok"], imported["message"])
		var save: Gen2SaveData = imported["save"]
		assert_eq(save.gender, Gen2SaveData.GENDER_MALE, String(game_id))
		# An export of a female save must not invent a byte for her.
		save.gender = Gen2SaveData.GENDER_FEMALE
		var exported: Dictionary = Gen2SramAdapter.export_bytes(save, raw, data)
		assert_true(exported["ok"], exported["message"])
		assert_eq(
			(exported["raw"] as PackedByteArray).slice(0x3E00, 0x3F00),
			raw.slice(0x3E00, 0x3F00), String(game_id)
		)


func test_silver_uses_the_gold_save_layout() -> void:
	var data: GameData = _adapter_data(RomRegistry.SILVER)
	var raw: PackedByteArray = _raw_cartridge(RomRegistry.SILVER, data)
	var result: Dictionary = Gen2SramAdapter.import_bytes(
		RomRegistry.SILVER, data.sha1, 0, raw, data
	)
	assert_true(result["ok"], result["message"])
	assert_eq((result["save"] as Gen2SaveData).player_name, "RED")
	assert_eq((result["save"] as Gen2SaveData).party.size(), 2)


func test_a_backup_copy_is_selected_when_primary_checksum_fails() -> void:
	var data: GameData = _adapter_data(RomRegistry.GOLD)
	var raw: PackedByteArray = _raw_cartridge(RomRegistry.GOLD, data)
	raw[0x2500] ^= 0x01
	var result: Dictionary = Gen2SramAdapter.import_bytes(
		RomRegistry.GOLD, data.sha1, 0, raw, data
	)
	assert_true(result["ok"], result["message"])
	assert_eq(result["copy"], "backup")
	assert_eq((result["save"] as Gen2SaveData).player_name, "RED")
	var normalized: Dictionary = Gen2SramAdapter.import_bytes(
		RomRegistry.GOLD, data.sha1, 0, result["raw"], data
	)
	assert_true(normalized["ok"], normalized["message"])
	assert_eq(normalized["copy"], "primary")


func test_an_invalid_primary_and_backup_are_refused() -> void:
	var data: GameData = _adapter_data(RomRegistry.GOLD)
	var raw: PackedByteArray = _raw_cartridge(RomRegistry.GOLD, data)
	raw[0x2009] ^= 0x01
	raw[0x0C6B] ^= 0x01
	var result: Dictionary = Gen2SramAdapter.import_bytes(
		RomRegistry.GOLD, data.sha1, 0, raw, data
	)
	assert_false(result["ok"])
	assert_string_contains(result["message"], "both cartridge save copies")


func test_a_crystal_layout_uses_its_distinct_party_and_backup_offsets() -> void:
	var data: GameData = _adapter_data(RomRegistry.CRYSTAL)
	var raw: PackedByteArray = _raw_cartridge(RomRegistry.CRYSTAL, data)
	var result: Dictionary = Gen2SramAdapter.import_bytes(
		RomRegistry.CRYSTAL, data.sha1, 0, raw, data
	)
	assert_true(result["ok"], result["message"])
	assert_eq(result["copy"], "primary")
	assert_eq((result["save"] as Gen2SaveData).party.size(), 2)


func test_export_updates_both_copies_and_preserves_trailing_bytes() -> void:
	var data: GameData = _adapter_data(RomRegistry.GOLD)
	var raw: PackedByteArray = _raw_cartridge(RomRegistry.GOLD, data)
	raw.resize(Gen2SramAdapter.SRAM_SIZE + 16)
	raw[Gen2SramAdapter.SRAM_SIZE + 4] = 0xA5
	raw[0x2500] = 0x77
	var save: Gen2SaveData = _adapter_save(data)
	save.player_name = "BLUE"
	save.player_id = 0x1234
	var export_result: Dictionary = Gen2SramAdapter.export_bytes(save, raw, data)
	assert_true(export_result["ok"], export_result["message"])
	var output: PackedByteArray = export_result["raw"]
	assert_eq(output.size(), Gen2SramAdapter.SRAM_SIZE + 16)
	assert_eq(output[Gen2SramAdapter.SRAM_SIZE + 4], 0xA5)
	assert_eq(output[0x2500], 0x77)
	var imported: Dictionary = Gen2SramAdapter.import_bytes(
		RomRegistry.GOLD, data.sha1, 0, output, data
	)
	assert_true(imported["ok"], imported["message"])
	assert_eq((imported["save"] as Gen2SaveData).player_name, "BLUE")
	assert_eq((imported["save"] as Gen2SaveData).player_id, 0x1234)
	output[0x2009] ^= 0x01
	var backup_import: Dictionary = Gen2SramAdapter.import_bytes(
		RomRegistry.GOLD, data.sha1, 0, output, data
	)
	assert_true(backup_import["ok"], backup_import["message"])
	assert_eq(backup_import["copy"], "backup")
	assert_eq((backup_import["save"] as Gen2SaveData).player_name, "BLUE")
