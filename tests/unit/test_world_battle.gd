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


func test_battle_request_carries_the_players_badge_mask() -> void:
	var prepared: Dictionary = Gen2WorldBattleAdapter.prepare(
		_data,
		{"kind": &"battle_requested", "values": {
			"kind": &"wild", "pokemon": SPECIES_TWO, "level": 5,
		}},
		_player_party(), RandomNumberGenerator.new(), 1 << 0
	)
	assert_true(prepared["ok"])
	var battle: Gen2Battle = prepared["battle"]
	assert_eq(battle.player_badge_mask, 1)
	assert_gt(battle.player.stat("attack"), battle.player.stats["attack"])


## LoadEnemyMon's .TreeMon branch: a headbutt encounter whose species is in
## CheckSleepingTreeMon's list for the current time of day enters asleep for
## TREEMON_SLEEP_TURNS. The list question is answered before this boundary,
## since only the caller knows the time of day and the profile.
func test_a_tree_battle_starts_the_wild_asleep_only_when_it_is_told_to() -> void:
	var asleep: Dictionary = Gen2WorldBattleAdapter.prepare(
		_data,
		{"kind": &"battle_requested", "values": {
			"kind": &"wild", "pokemon": SPECIES_TWO, "level": 5,
			"battle_type": Gen2Battle.BATTLETYPE_TREE, "asleep": true,
		}},
		_player_party(), RandomNumberGenerator.new()
	)
	assert_true(asleep["ok"])
	var sleeping: Gen2Battle = asleep["battle"]
	assert_eq(sleeping.battle_type, Gen2Battle.BATTLETYPE_TREE)
	assert_eq(sleeping.enemy.status, Gen2WorldTreemon.SLEEP_TURNS)
	assert_true(Gen2Status.is_asleep(sleeping.enemy.status))

	# A tree battle against an unlisted species, and Gold and Silver's every
	# tree battle, say false and start awake.
	var awake: Dictionary = Gen2WorldBattleAdapter.prepare(
		_data,
		{"kind": &"battle_requested", "values": {
			"kind": &"wild", "pokemon": SPECIES_TWO, "level": 5,
			"battle_type": Gen2Battle.BATTLETYPE_TREE, "asleep": false,
		}},
		_player_party(), RandomNumberGenerator.new()
	)
	assert_true(awake["ok"])
	assert_eq((awake["battle"] as Gen2Battle).enemy.status, Gen2Status.NONE)


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


## A visible encounter chose its DVs before the player met it, so the battle is
## built with those four numbers rather than a fresh roll. Nothing else names
## `dvs`, and what does not gets the perfect word it always got.
func test_a_wild_request_carries_its_own_dvs_into_the_battle() -> void:
	var shiny: int = Gen2Stats.pack_dvs(2, 10, 10, 10)
	var prepared: Dictionary = Gen2WorldBattleAdapter.prepare(
		_data, {"values": {"kind": &"wild", "pokemon": SPECIES_TWO, "level": 5, "dvs": shiny}},
		_player_party()
	)
	assert_true(bool(prepared["ok"]), String(prepared.get("reason", "")))
	assert_eq((prepared["battle"] as Gen2Battle).enemy.dvs, shiny)
	assert_true(Gen2Stats.is_shiny((prepared["battle"] as Gen2Battle).enemy.dvs))

	var rolled: Dictionary = Gen2WorldBattleAdapter.prepare(
		_data, {"values": {"kind": &"wild", "pokemon": SPECIES_TWO, "level": 5}},
		_player_party()
	)
	assert_eq(
		(rolled["battle"] as Gen2Battle).enemy.dvs, Gen2BattleMon.PERFECT_DVS
	)


## `PlayBattleMusic` runs in front of `DoBattleTransition`, so the track has to
## be answerable from the request alone, before a battle exists to read. It is
## the same answer `Gen2Battle.battle_music` gives the prepared fight, which is
## what lets the driver continue the piece rather than restart it behind the
## transition.
func test_the_battle_track_is_answerable_from_the_request_alone() -> void:
	var wild: Dictionary = {"values": {"kind": &"wild", "pokemon": SPECIES_TWO, "level": 5}}
	assert_eq(
		Gen2WorldBattleAdapter.music_for(wild, Gen2Battle.LANDMARK_NONE, Gen2WorldPalette.TIME_DAY),
		Gen2Battle.battle_music(
			Gen2Battle.BATTLETYPE_NORMAL, 0, 0,
			Gen2Battle.LANDMARK_NONE, Gen2WorldPalette.TIME_DAY
		)
	)
	## A trainer's own two numbers are the request's, and a wild request holding
	## neither must not be read as trainer class 0's row by accident.
	var leader: Dictionary = {"values": {
		"kind": &"trainer",
		"trainer_group": Gen2Battle.TRAINER_CLASS_CHAMPION,
		"trainer_id": 1,
	}}
	assert_eq(
		Gen2WorldBattleAdapter.music_for(
			leader, Gen2Battle.LANDMARK_NONE, Gen2WorldPalette.TIME_DAY
		),
		Gen2Battle.MUSIC_CHAMPION_BATTLE
	)
	## `BATTLETYPE_SUICUNE` sits in front of both compares, so it wins over the
	## class the request also carries.
	var roaming: Dictionary = {"values": {
		"kind": &"wild", "pokemon": SPECIES_TWO, "level": 5,
		"battle_type": Gen2Battle.BATTLETYPE_ROAMING,
	}}
	assert_eq(
		Gen2WorldBattleAdapter.music_for(
			roaming, Gen2Battle.LANDMARK_NONE, Gen2WorldPalette.TIME_NIGHT
		),
		Gen2Battle.MUSIC_SUICUNE_BATTLE
	)
	assert_eq(
		Gen2WorldBattleAdapter.music_for(
			{"values": 5}, Gen2Battle.LANDMARK_NONE, Gen2WorldPalette.TIME_DAY
		),
		Gen2Battle.MUSIC_NONE
	)
