extends GutTest

## Battle requests use a small synthetic cache so their validation and party
## construction stay independent of a real cartridge or a scene tree.

const SPECIES_ONE: int = 1
const SPECIES_TWO: int = 2
const TACKLE: int = 1

var _directory: String = ""
var _data: GameData = null


func before_each() -> void:
	_directory = RomCache.directory_for(&"worldbattletest", "0123456789abcdef")
	RomCache.clear(_directory)
	RomCache.prepare(_directory)
	_write_cache()
	_data = GameData.open_directory(_directory)


func after_each() -> void:
	RomCache.clear(_directory)


func _write_cache() -> void:
	RomCache.write_json(RomCache.species_path(_directory), [
		{
			"number": SPECIES_ONE, "name": "ONE",
			"stats": {"hp": 50, "attack": 50, "defense": 50, "speed": 50,
				"sp_attack": 50, "sp_defense": 50},
			"types": [0, 0], "growth_rate": Gen2Experience.GROWTH_MEDIUM_FAST,
			"base_exp": 50, "gender_ratio": 0,
			"learnset": [{"level": 1, "move": TACKLE}],
		},
		{
			"number": SPECIES_TWO, "name": "TWO",
			"stats": {"hp": 60, "attack": 60, "defense": 60, "speed": 60,
				"sp_attack": 60, "sp_defense": 60},
			"types": [0, 0], "growth_rate": Gen2Experience.GROWTH_MEDIUM_FAST,
			"base_exp": 60, "gender_ratio": 0,
			"learnset": [{"level": 1, "move": TACKLE}],
		},
	])
	RomCache.write_json(RomCache.moves_path(_directory), [{
		"number": TACKLE, "name": "TACKLE", "power": 40, "type": 0,
		"accuracy": 255, "pp": 35, "effect": 0, "chance": 0,
	}])
	RomCache.write_json(RomCache.items_path(_directory), [])
	RomCache.write_json(RomCache.types_path(_directory), [{"number": 0, "name": "NORMAL"}])
	RomCache.write_json(RomCache.matchups_path(_directory), [])
	RomCache.write_json(RomCache.trainers_path(_directory), [{
		"number": 1, "name": "ACE", "palette": [0x1234, 0x5678], "dvs": 0xFFFF,
		"trainers": [{
			"name": "ACE", "type": RomLayout.TRAINER_MON_NORMAL,
			"party": [{"level": 5, "species": SPECIES_TWO, "item": 0, "moves": []}],
		}],
	}])
	RomCache.write_json(RomCache.manifest_path(_directory), {
		"format_version": RomCache.FORMAT_VERSION,
		"game_id": "worldbattletest",
		"sha1": "0123456789abcdef",
		"complete": true,
	})


func _player_party() -> Gen2Party:
	return Gen2WorldBattleAdapter.fallback_party(_data, SPECIES_ONE, 5, 1)


func test_wild_request_builds_a_one_mon_enemy_party() -> void:
	var prepared: Dictionary = Gen2WorldBattleAdapter.prepare(
		_data,
		{"kind": &"battle_requested", "values": {
			"kind": &"wild", "pokemon": SPECIES_TWO, "level": 5,
		}},
		_player_party(), RandomNumberGenerator.new()
	)
	assert_true(prepared["ok"])
	assert_false(prepared["trainer_battle"])
	assert_eq((prepared["enemy_party"] as Gen2Party).size(), 1)
	assert_eq((prepared["battle"] as Gen2Battle).enemy.species, SPECIES_TWO)


func test_trainer_request_uses_the_source_party_and_trainer_battle_rules() -> void:
	var prepared: Dictionary = Gen2WorldBattleAdapter.prepare(
		_data,
		{"kind": &"battle_requested", "values": {
			"kind": &"trainer", "trainer_group": 1, "trainer_id": 0,
		}},
		_player_party(), RandomNumberGenerator.new()
	)
	assert_true(prepared["ok"])
	assert_true(prepared["trainer_battle"])
	assert_eq((prepared["battle"] as Gen2Battle).is_trainer_battle, true)
	assert_eq((prepared["enemy_party"] as Gen2Party).active_mon().species, SPECIES_TWO)


func test_invalid_battle_identifiers_are_structured_failures() -> void:
	var invalid_species: Dictionary = Gen2WorldBattleAdapter.prepare(
		_data,
		{"kind": &"battle_requested", "values": {
			"kind": &"wild", "pokemon": 99, "level": 5,
		}},
		_player_party()
	)
	assert_false(invalid_species["ok"])
	assert_eq(invalid_species["reason"], &"invalid_wild_species")

	var invalid_trainer: Dictionary = Gen2WorldBattleAdapter.prepare(
		_data,
		{"kind": &"battle_requested", "values": {
			"kind": &"trainer", "trainer_group": 1, "trainer_id": 9,
		}},
		_player_party()
	)
	assert_false(invalid_trainer["ok"])
	assert_eq(invalid_trainer["reason"], &"invalid_trainer")
