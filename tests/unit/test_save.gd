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


func test_new_game_uses_the_real_starter_choices_and_berry() -> void:
	var created: Gen2SaveData = Gen2SaveStore.create_new_game(_data, 1, "ASH", 155)
	assert_not_null(created)
	assert_eq(created.player_name, "ASH")
	assert_eq(created.slot, 1)
	assert_eq(created.party.size(), 1)
	var mon: Gen2SaveMon = created.party[0]
	assert_eq(mon.species, 155)
	assert_eq(mon.level, 5)
	assert_eq(mon.item, Gen2SaveStore.STARTER_ITEM)
	assert_eq(mon.nickname, "FILLER")
	assert_eq(mon.original_trainer, "ASH")
	var validation: Dictionary = Gen2SaveValidator.validate(created, _data)
	assert_true(validation["ok"], validation["message"])


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
	assert_eq((save.party[0] as Gen2SaveMon).hp, (_save().party[0] as Gen2SaveMon).hp)


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
	output[0x2009] ^= 0x01
	var backup_import: Dictionary = Gen2SramAdapter.import_bytes(
		RomRegistry.GOLD, data.sha1, 0, output, data
	)
	assert_true(backup_import["ok"], backup_import["message"])
	assert_eq(backup_import["copy"], "backup")
	assert_eq((backup_import["save"] as Gen2SaveData).player_name, "BLUE")
