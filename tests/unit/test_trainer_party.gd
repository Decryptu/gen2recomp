extends GutTest

## Turning one of a trainer class's own trainers into a battle-ready party.
##
## Builds its own small cache, the same way [code]test_game_data.gd[/code]
## does: nothing here opens a cartridge, only [GameData] reading back what was
## written the way the importer writes it.

## Species and move numbers are arbitrary here: [GameData] indexes its species
## table by position, so this cache's array has to be exactly as long as the
## highest number used, which small numbers make easy to keep straight.
const PIDGEY: int = 1
const PIDGEOTTO: int = 2
const TACKLE: int = 1
const MUD_SLAP: int = 2
const GUST: int = 3

var _directory: String = ""
var _data: GameData = null


func before_each() -> void:
	_directory = RomCache.directory_for(&"trainerpartytest", "0123456789abcdef")
	RomCache.clear(_directory)
	RomCache.prepare(_directory)
	_write_cache()
	_data = GameData.open_directory(_directory)


func after_each() -> void:
	RomCache.clear(_directory)


func _write_cache() -> void:
	RomCache.write_json(RomCache.species_path(_directory), [
		{
			"number": PIDGEY, "name": "PIDGEY",
			"stats": {"hp": 40, "attack": 45, "defense": 40, "speed": 56,
				"sp_attack": 35, "sp_defense": 35},
			"types": [0, 0], "front_tiles": [7, 7],
			"palette": {"normal": [0x1234, 0x5678], "shiny": [0x0C63, 0x1084]},
			"learnset": [{"level": 1, "move": TACKLE}, {"level": 5, "move": MUD_SLAP}],
		},
		{
			"number": PIDGEOTTO, "name": "PIDGEOTTO",
			"stats": {"hp": 63, "attack": 60, "defense": 55, "speed": 71,
				"sp_attack": 50, "sp_defense": 50},
			"types": [0, 0], "front_tiles": [7, 7],
			"palette": {"normal": [0x1234, 0x5678], "shiny": [0x0C63, 0x1084]},
			"learnset": [
				{"level": 1, "move": TACKLE}, {"level": 5, "move": MUD_SLAP},
				{"level": 9, "move": GUST},
			],
		},
	])
	RomCache.write_json(RomCache.moves_path(_directory), [
		{"number": TACKLE, "name": "TACKLE"},
		{"number": MUD_SLAP, "name": "MUD-SLAP"},
		{"number": GUST, "name": "GUST"},
	])
	RomCache.write_json(RomCache.items_path(_directory), [])
	RomCache.write_json(RomCache.types_path(_directory), [{"number": 0, "name": "NORMAL"}])
	RomCache.write_json(RomCache.matchups_path(_directory), [])
	RomCache.write_json(RomCache.trainers_path(_directory), [
		{
			"number": 1, "name": "LEADER", "palette": [0x1234, 0x5678],
			"trainers": [
				{
					"name": "FALKNER", "type": RomLayout.TRAINER_MON_NORMAL,
					"party": [
						{"level": 7, "species": PIDGEY, "item": 0, "moves": []},
						{"level": 9, "species": PIDGEOTTO, "item": 0, "moves": []},
					],
				},
				{
					"name": "PICKY", "type": RomLayout.TRAINER_MON_ITEM_MOVES,
					"party": [{
						"level": 20, "species": PIDGEOTTO, "item": 5,
						"moves": [GUST, TACKLE, 0, 0],
					}],
				},
			],
		},
	])
	RomCache.write_json(RomCache.manifest_path(_directory), {
		"format_version": RomCache.FORMAT_VERSION,
		"game_id": "trainerpartytest",
		"sha1": "0123456789abcdef",
		"complete": true,
	})


func test_a_normal_trainers_pokemon_knows_what_its_level_teaches_it() -> void:
	var party: Gen2Party = Gen2TrainerParty.build(_data, 1, 0)
	assert_not_null(party)
	assert_eq(party.size(), 2)

	var lead: Gen2BattleMon = party.at(0)
	assert_eq(lead.species, PIDGEY)
	assert_eq(lead.level, 7)
	assert_eq(lead.moves, [TACKLE, MUD_SLAP], "everything a level 7 Pidgey has learned")

	var second: Gen2BattleMon = party.at(1)
	assert_eq(second.species, PIDGEOTTO)
	assert_eq(second.moves, [TACKLE, MUD_SLAP, GUST])


func test_trainer_pokemon_are_full_health_with_no_stat_experience() -> void:
	var party: Gen2Party = Gen2TrainerParty.build(_data, 1, 0)
	var lead: Gen2BattleMon = party.at(0)
	assert_eq(lead.hp, lead.max_hp())
	assert_eq(lead.dvs, Gen2BattleMon.PERFECT_DVS)
	assert_eq(lead.stat_exp, {})


func test_a_stored_moves_trainers_pokemon_knows_exactly_what_is_stored() -> void:
	var party: Gen2Party = Gen2TrainerParty.build(_data, 1, 1)
	var mon: Gen2BattleMon = party.at(0)
	assert_eq(mon.moves, [GUST, TACKLE], "the two real slots, the zero padding dropped")
	assert_eq(mon.item, 5)


func test_a_normal_trainers_pokemon_holds_nothing() -> void:
	var party: Gen2Party = Gen2TrainerParty.build(_data, 1, 0)
	assert_eq(party.at(0).item, 0)


func test_an_unknown_trainer_or_index_answers_null() -> void:
	assert_null(Gen2TrainerParty.build(_data, 99, 0))
	assert_null(Gen2TrainerParty.build(_data, 1, 9))
	assert_null(Gen2TrainerParty.build(null, 1, 0))


## Falkner's own party through a real battle: this is what
## [code]battle_screen.gd[/code]'s [code]show_trainer[/code] puts on the enemy's
## side, so the same replacement path it draws is worth proving here, where an
## assertion can check it rather than an eye.
func test_falkners_pidgeotto_replaces_his_pidgey_after_it_faints() -> void:
	var enemy: Gen2Party = Gen2TrainerParty.build(_data, 1, 0)
	var player: Gen2Party = Gen2Party.of(Gen2BattleMon.create(_data, PIDGEY, 30, [TACKLE]))
	var battle: Gen2Battle = Gen2Battle.create_parties(
		_data, player, enemy, RandomNumberGenerator.new()
	)
	assert_not_null(battle)
	assert_eq(battle.enemy.species, PIDGEY, "Falkner leads with his level 7 Pidgey")

	battle.enemy.take_damage(battle.enemy.max_hp())
	assert_true(battle.must_replace(Gen2Battle.ENEMY))

	var events: Array = battle.send_out(Gen2Battle.ENEMY, 1)
	assert_eq(battle.enemy.species, PIDGEOTTO)
	assert_eq(battle.enemy.level, 9)
	assert_false(battle.must_replace(Gen2Battle.ENEMY))

	var sent_out: Dictionary = events[events.size() - 1]
	assert_eq(sent_out["type"], Gen2Battle.SENT_OUT)
	assert_eq(int(sent_out["level"]), 9, "the level battle_screen.gd reads out of the event")
