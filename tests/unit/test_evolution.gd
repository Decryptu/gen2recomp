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


## The rows `EvolveAfterBattle` reaches that the shared fixture has no use for:
## an item evolution, a bare trade and a trade wanting a held item.
const ITEM_STONE: int = 0x08
const TRADE_HELD_ITEM: int = 0x2D
const TRADE_TARGET: int = Fixture.PIKACHU


func _with_evolution_rows() -> GameData:
	var directory: String = RomCache.directory_for(&"evolutiontest", "0123456789abcdef")
	var species: Array = RomCache.read_json(RomCache.species_path(directory))
	for raw: Dictionary in species:
		match int(raw["number"]):
			Fixture.BULBASAUR:
				(raw["evolutions"] as Array).append({
					"method": RomLayout.EVOLVE_ITEM, "parameter": ITEM_STONE,
					"condition": 0, "target": TRADE_TARGET,
				})
			Fixture.GEODUDE:
				raw["evolutions"] = [{
					"method": RomLayout.EVOLVE_TRADE,
					"parameter": Gen2Evolution.TRADE_NO_ITEM,
					"condition": 0, "target": TRADE_TARGET,
				}]
			Fixture.GASTLY:
				raw["evolutions"] = [{
					"method": RomLayout.EVOLVE_TRADE, "parameter": TRADE_HELD_ITEM,
					"condition": 0, "target": TRADE_TARGET,
				}]
	RomCache.write_json(RomCache.species_path(directory), species)
	return GameData.open_directory(directory)


## `.item` never calls `IsMonHoldingEverstone`; only `.level`, `.happiness`,
## `.trade` and `EVOLVE_STAT` do. `EvoStoneEffect` is where the pack refuses one,
## which is Gen2WorldPartyHost's own test, not this predicate's.
func test_a_stone_evolves_an_everstone_holder_and_a_trade_does_not() -> void:
	var data: GameData = _with_evolution_rows()
	var mon := Gen2BattleMon.create(data, Fixture.BULBASAUR, 20, [])
	mon.item = Gen2Evolution.EVERSTONE
	assert_eq(int(Gen2Evolution.item_evolution(data, mon, ITEM_STONE).get("target", 0)), TRADE_TARGET)
	var stony := Gen2BattleMon.create(data, Fixture.GEODUDE, 20, [])
	stony.item = Gen2Evolution.EVERSTONE
	assert_true(Gen2Evolution.trade_evolution(data, stony).is_empty())


func test_a_trade_evolution_honours_its_held_item_parameter() -> void:
	var data: GameData = _with_evolution_rows()
	var plain := Gen2BattleMon.create(data, Fixture.GEODUDE, 20, [])
	assert_eq(int(Gen2Evolution.trade_evolution(data, plain).get("target", 0)), TRADE_TARGET)
	assert_false(Gen2Evolution.trade_evolution(data, plain).has("consumes_held_item"))

	var held := Gen2BattleMon.create(data, Fixture.GASTLY, 20, [])
	assert_true(Gen2Evolution.trade_evolution(data, held).is_empty())
	held.item = TRADE_HELD_ITEM
	var row: Dictionary = Gen2Evolution.trade_evolution(data, held)
	assert_eq(int(row.get("target", 0)), TRADE_TARGET)
	assert_eq(int(row.get("consumes_held_item", 0)), TRADE_HELD_ITEM)
