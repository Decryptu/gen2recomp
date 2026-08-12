extends GutTest

const Fixture := preload("res://tests/unit/battle_fixture.gd")

var _data: GameData

func before_each() -> void:
	_data = Fixture.build(RomCache.directory_for(&"evolutiontest", "0123456789abcdef"))


func test_level_evolution_is_selected_in_source_order_and_respects_everstone() -> void:
	var mon := Gen2BattleMon.create(_data, Fixture.BULBASAUR, 16, [])
	assert_eq(_data.evolutions(Fixture.BULBASAUR).size(), 1, "fixture evolution row")
	assert_eq(mon.level, 16, "level")
	assert_eq(int(Gen2Evolution.level_evolution(_data, mon, Gen2WorldPalette.TIME_DAY).get("target", 0)), 2)
	mon.item = Gen2Evolution.EVERSTONE
	assert_true(Gen2Evolution.level_evolution(_data, mon, Gen2WorldPalette.TIME_DAY).is_empty())


func test_happiness_and_time_predicates_match_the_three_source_triggers() -> void:
	var mon := Gen2BattleMon.create(_data, Fixture.BULBASAUR, 5, [])
	mon.happiness = Gen2Evolution.HAPPINESS_TO_EVOLVE - 1
	var row := {"method": RomLayout.EVOLVE_HAPPINESS, "parameter": RomLayout.TRIGGER_MORNDAY}
	assert_false(Gen2Evolution._eligible(row, mon, Gen2WorldPalette.TIME_DAY))
	mon.happiness = Gen2Evolution.HAPPINESS_TO_EVOLVE
	assert_true(Gen2Evolution._eligible(row, mon, Gen2WorldPalette.TIME_DAY))
	assert_false(Gen2Evolution._eligible(row, mon, Gen2WorldPalette.TIME_NIGHT))


func test_evolve_preserves_damage_by_the_max_hp_delta_and_recalculates_stats() -> void:
	var mon := Gen2BattleMon.create(_data, Fixture.BULBASAUR, 16, [])
	mon.take_damage(7)
	var old_max: int = mon.max_hp()
	var old_hp: int = mon.hp
	var result: Dictionary = Gen2Evolution.evolve(mon, 2)
	assert_eq(int(result["old_species"]), Fixture.BULBASAUR)
	assert_eq(mon.species, 2)
	assert_eq(mon.hp, old_hp + mon.max_hp() - old_max)
	assert_ne(mon.max_hp(), old_max)
