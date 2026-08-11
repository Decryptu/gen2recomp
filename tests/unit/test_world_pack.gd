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


## Each fixture item carries its real ItemAttributes row, so the submenu shapes
## below are the ones the cartridge builds rather than invented combinations.
func before_each() -> void:
	Gen2ModHost.reset()
	Fixture.build()
	var items: Array = RomCache.read_json(RomCache.items_path(Fixture.directory()))
	for raw: Dictionary in items:
		match int(raw.get("number", 0)):
			ITEM_POTION:
				raw["name"] = "POTION"
				raw["pocket"] = Gen2WorldPack.TYPE_ITEM
				raw["permissions"] = Gen2WorldPack.CANT_SELECT
				raw["field_menu"] = Gen2WorldPack.ITEMMENU_PARTY
			ITEM_MASTER_BALL:
				raw["name"] = "MASTER BALL"
				raw["pocket"] = Gen2WorldPack.TYPE_BALL
				raw["permissions"] = Gen2WorldPack.CANT_SELECT
				raw["field_menu"] = Gen2WorldPack.ITEMMENU_NOUSE
			ITEM_BICYCLE:
				raw["name"] = "BICYCLE"
				raw["pocket"] = Gen2WorldPack.TYPE_KEY_ITEM
				raw["permissions"] = Gen2WorldPack.CANT_TOSS
				raw["field_menu"] = Gen2WorldPack.ITEMMENU_CLOSE
			ITEM_TM01:
				raw["name"] = "TM01"
				raw["pocket"] = Gen2WorldPack.TYPE_TM_HM
				raw["permissions"] = Gen2WorldPack.CANT_SELECT
				raw["field_menu"] = Gen2WorldPack.ITEMMENU_PARTY
	RomCache.write_json(RomCache.items_path(Fixture.directory()), items)
	_data = GameData.open_directory(Fixture.directory())


func after_each() -> void:
	RomCache.clear(Fixture.directory())
	Gen2ModHost.reset()


func _actions(item: int) -> Array:
	var out: Array = []
	for entry: Dictionary in Gen2WorldPack.item_submenu(_data, item):
		out.append(StringName(entry.get("action", &"")))
	return out


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
	assert_eq(
		(pockets[0]["items"] as Array)[0]["field_menu"], Gen2WorldPack.ITEMMENU_PARTY
	)


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


func test_receive_check_enforces_stack_and_pocket_capacity() -> void:
	assert_eq(Gen2WorldPack.pocket_capacity(Gen2WorldPack.TYPE_ITEM), 20)
	assert_eq(Gen2WorldPack.pocket_capacity(Gen2WorldPack.TYPE_BALL), 12)
	assert_eq(Gen2WorldPack.pocket_capacity(Gen2WorldPack.TYPE_KEY_ITEM), 25)
	var full_stack: Dictionary = Gen2WorldPack.receive_check(
		_data, {ITEM_POTION: 99}, ITEM_POTION, 1
	)
	assert_false(full_stack["ok"])
	assert_eq(full_stack["reason"], &"item_stack_full")

	var items: Array = RomCache.read_json(RomCache.items_path(Fixture.directory()))
	for raw: Dictionary in items:
		var item: int = int(raw.get("number", 0))
		if item >= 5 and item <= 25:
			raw["pocket"] = Gen2WorldPack.TYPE_ITEM
	RomCache.write_json(RomCache.items_path(Fixture.directory()), items)
	var data: GameData = GameData.open_directory(Fixture.directory())
	var owned: Dictionary = {}
	for item: int in range(5, 25):
		owned[item] = 1
	var pocket_full: Dictionary = Gen2WorldPack.receive_check(data, owned, 25, 1)
	assert_false(pocket_full["ok"])
	assert_eq(pocket_full["reason"], &"pocket_full")


## engine/items/pack.asm's .ItemBallsKey_LoadSubmenu picks between six headers on
## two inverted permission bits and the field-menu nibble. POTION is CANT_SELECT
## with a usable field menu, so it reaches MenuHeader_UsableItem.
func test_a_usable_unselectable_item_offers_use_give_toss_quit() -> void:
	assert_eq(_actions(ITEM_POTION), [
		Gen2WorldPack.ACTION_USE, Gen2WorldPack.ACTION_GIVE,
		Gen2WorldPack.ACTION_TOSS, Gen2WorldPack.ACTION_QUIT,
	])


## MASTER BALL shares POTION's permissions but has no field menu, so USE is not
## offered at all: MenuHeader_HoldableItem.
func test_an_unusable_unselectable_item_offers_give_toss_quit() -> void:
	assert_eq(_actions(ITEM_MASTER_BALL), [
		Gen2WorldPack.ACTION_GIVE, Gen2WorldPack.ACTION_TOSS, Gen2WorldPack.ACTION_QUIT,
	])


## BICYCLE is CANT_TOSS and selectable, so the source drops TOSS and GIVE and
## keeps SEL: MenuHeader_UnusableKeyItem.
func test_an_untossable_selectable_item_offers_use_sel_quit() -> void:
	assert_eq(_actions(ITEM_BICYCLE), [
		Gen2WorldPack.ACTION_USE, Gen2WorldPack.ACTION_SELECT, Gen2WorldPack.ACTION_QUIT,
	])


## The TM/HM pocket has its own two-way split on CANT_TOSS alone. TM01 can be
## tossed, so it reaches .MenuHeader2.
func test_the_tm_pocket_has_its_own_submenu() -> void:
	assert_eq(_actions(ITEM_TM01), [
		Gen2WorldPack.ACTION_USE, Gen2WorldPack.ACTION_GIVE, Gen2WorldPack.ACTION_QUIT,
	])


## GIVE, TOSS and SEL keep their source position and are marked unavailable, the
## way the party submenu carries STATS, SWITCH and MOVE.
func test_only_use_and_quit_are_available() -> void:
	for entry: Dictionary in Gen2WorldPack.item_submenu(_data, ITEM_POTION):
		var action: StringName = StringName(entry.get("action", &""))
		assert_eq(
			bool(entry.get("available", false)),
			action in [Gen2WorldPack.ACTION_USE, Gen2WorldPack.ACTION_QUIT],
			"action %s" % action
		)


func test_an_unknown_item_has_no_submenu() -> void:
	assert_eq(Gen2WorldPack.item_submenu(_data, 250), [])
	assert_eq(Gen2WorldPack.item_submenu(null, ITEM_POTION), [])


## UseItem's jumptable: everything below ITEMMENU_CURRENT is .Oak's refusal.
func test_field_use_kind_collapses_the_oak_entries() -> void:
	assert_eq(Gen2WorldPack.field_use_kind(_data, ITEM_POTION), Gen2WorldPack.ITEMMENU_PARTY)
	assert_eq(Gen2WorldPack.field_use_kind(_data, ITEM_BICYCLE), Gen2WorldPack.ITEMMENU_CLOSE)
	assert_eq(
		Gen2WorldPack.field_use_kind(_data, ITEM_MASTER_BALL), Gen2WorldPack.ITEMMENU_NOUSE
	)
	assert_eq(Gen2WorldPack.field_use_kind(null, ITEM_POTION), Gen2WorldPack.ITEMMENU_NOUSE)


## A registered pocket follows the four source ones rather than displacing one,
## so the cartridge cycle is reached the same way it always was.
func test_a_registered_pocket_follows_the_source_cycle() -> void:
	var mod_pocket: int = Gen2ModHost.FIRST_MOD_POCKET
	assert_true(bool(Gen2ModHost.instance().register_menu_entry(
		Gen2ModHost.MENU_PACK_POCKET, &"relics", {"label": "Relics", "pocket": mod_pocket}
	).get("ok", false)))
	assert_eq(Gen2WorldPack.pocket_order(), [
		Gen2WorldPack.TYPE_ITEM, Gen2WorldPack.TYPE_BALL,
		Gen2WorldPack.TYPE_KEY_ITEM, Gen2WorldPack.TYPE_TM_HM, mod_pocket,
	])
	assert_eq(Gen2WorldPack.pocket_name(mod_pocket), "Relics")

	var items: Array = RomCache.read_json(RomCache.items_path(Fixture.directory()))
	for raw: Dictionary in items:
		if int(raw.get("number", 0)) == ITEM_UNCLASSIFIED:
			raw["name"] = "RELIC"
			raw["pocket"] = mod_pocket
	RomCache.write_json(RomCache.items_path(Fixture.directory()), items)
	var data: GameData = GameData.open_directory(Fixture.directory())
	var pockets: Array = Gen2WorldPack.build(
		data, Gen2WorldState.new({}, {}, {ITEM_UNCLASSIFIED: 2})
	)
	assert_eq(pockets.size(), 5)
	assert_eq(pockets[4]["name"], "Relics")
	assert_eq((pockets[4]["items"] as Array)[0]["item"], ITEM_UNCLASSIFIED)
