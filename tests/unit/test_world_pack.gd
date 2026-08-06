extends GutTest

## Gen2WorldPack groups owned items into the four cartridge pack pockets using
## the item type byte GameData already imports under "pocket"
## (data/items/attributes.asm's item_attribute macro; constants/item_data_
## constants.asm names the same values ITEM/KEY_ITEM/BALL/TM_HM). Presentation
## only: Gen2WorldState keeps its existing flat item-to-quantity shape.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

const ITEM_POTION: int = 1
const ITEM_MASTER_BALL: int = 2
const ITEM_BICYCLE: int = 3
const ITEM_TM01: int = 4
const ITEM_UNCLASSIFIED: int = 5

var _data: GameData = null


func before_each() -> void:
	Fixture.build()
	var items: Array = RomCache.read_json(RomCache.items_path(Fixture.directory()))
	for raw: Dictionary in items:
		match int(raw.get("number", 0)):
			ITEM_POTION:
				raw["name"] = "POTION"
				raw["pocket"] = Gen2WorldPack.TYPE_ITEM
				raw["field_menu"] = 1
			ITEM_MASTER_BALL:
				raw["name"] = "MASTER BALL"
				raw["pocket"] = Gen2WorldPack.TYPE_BALL
			ITEM_BICYCLE:
				raw["name"] = "BICYCLE"
				raw["pocket"] = Gen2WorldPack.TYPE_KEY_ITEM
			ITEM_TM01:
				raw["name"] = "TM01"
				raw["pocket"] = Gen2WorldPack.TYPE_TM_HM
	RomCache.write_json(RomCache.items_path(Fixture.directory()), items)
	_data = GameData.open_directory(Fixture.directory())


func after_each() -> void:
	RomCache.clear(Fixture.directory())


func test_pockets_are_listed_in_the_source_cycle_order() -> void:
	var state := Gen2WorldState.new()
	var pockets: Array = Gen2WorldPack.build(_data, state)
	var kinds: Array = []
	for pocket: Dictionary in pockets:
		kinds.append(pocket.get("pocket"))
	assert_eq(kinds, [
		Gen2WorldPack.TYPE_ITEM, Gen2WorldPack.TYPE_BALL,
		Gen2WorldPack.TYPE_KEY_ITEM, Gen2WorldPack.TYPE_TM_HM,
	])


func test_an_item_lands_in_the_pocket_its_imported_type_byte_names() -> void:
	var state := Gen2WorldState.new({}, {}, {ITEM_POTION: 3, ITEM_MASTER_BALL: 1})
	var pockets: Array = Gen2WorldPack.build(_data, state)
	var items_pocket: Dictionary = pockets[0]
	var balls_pocket: Dictionary = pockets[1]
	assert_eq((items_pocket["items"] as Array).size(), 1)
	assert_eq((items_pocket["items"] as Array)[0]["item"], ITEM_POTION)
	assert_eq((items_pocket["items"] as Array)[0]["quantity"], 3)
	assert_eq((balls_pocket["items"] as Array).size(), 1)
	assert_eq((balls_pocket["items"] as Array)[0]["item"], ITEM_MASTER_BALL)


func test_empty_pockets_stay_empty_not_absent() -> void:
	var state := Gen2WorldState.new({}, {}, {ITEM_POTION: 1})
	var pockets: Array = Gen2WorldPack.build(_data, state)
	assert_eq(pockets.size(), 4)
	assert_eq((pockets[1]["items"] as Array).size(), 0)
	assert_eq((pockets[2]["items"] as Array).size(), 0)
	assert_eq((pockets[3]["items"] as Array).size(), 0)


func test_a_zero_quantity_item_does_not_appear() -> void:
	var state := Gen2WorldState.new({}, {}, {ITEM_POTION: 1})
	state.apply_changes({}, {}, {"items": {ITEM_POTION: 0}})
	var pockets: Array = Gen2WorldPack.build(_data, state)
	assert_eq((pockets[0]["items"] as Array).size(), 0)


func test_field_menu_value_is_carried_through() -> void:
	var state := Gen2WorldState.new({}, {}, {ITEM_POTION: 1})
	var pockets: Array = Gen2WorldPack.build(_data, state)
	assert_eq((pockets[0]["items"] as Array)[0]["field_menu"], 1)


## An item whose imported pocket byte is 0 does not belong to any of the four
## cartridge pockets and must not be invented into one.
func test_an_unclassified_item_appears_in_no_pocket() -> void:
	var state := Gen2WorldState.new({}, {}, {ITEM_UNCLASSIFIED: 1})
	var pockets: Array = Gen2WorldPack.build(_data, state)
	for pocket: Dictionary in pockets:
		assert_eq((pocket["items"] as Array).size(), 0)


func test_pocket_for_reads_the_imported_type_byte() -> void:
	assert_eq(Gen2WorldPack.pocket_for(_data, ITEM_POTION), Gen2WorldPack.TYPE_ITEM)
	assert_eq(Gen2WorldPack.pocket_for(_data, ITEM_MASTER_BALL), Gen2WorldPack.TYPE_BALL)
	assert_eq(Gen2WorldPack.pocket_for(_data, ITEM_BICYCLE), Gen2WorldPack.TYPE_KEY_ITEM)
	assert_eq(Gen2WorldPack.pocket_for(_data, ITEM_TM01), Gen2WorldPack.TYPE_TM_HM)
	assert_eq(Gen2WorldPack.pocket_for(null, ITEM_POTION), 0)


func test_build_with_no_data_or_state_returns_empty() -> void:
	assert_eq(Gen2WorldPack.build(null, Gen2WorldState.new()), [])
	assert_eq(Gen2WorldPack.build(_data, null), [])
