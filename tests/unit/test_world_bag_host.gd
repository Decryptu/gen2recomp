extends GutTest

## The item transactions no party, mart or script is behind: `TossItem`
## (`home/item.asm`) for the bag, and `engine/events/pokecenter_pc.asm`'s own
## deposit, withdraw and toss for `wPCItems`. Both commit through the same
## [Gen2WorldTransaction] boundary, and the PC's menus are checked here for the
## same reason: it is the file that owns the fixture they read.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

const POTION: int = 7
const KEY_ITEM: int = 8

var _data: GameData = null
var _world: Gen2WorldAPI = null
var _save: Gen2SaveData = null


func before_each() -> void:
	_data = Fixture.build()
	_write_items()
	_data = GameData.open_directory(Fixture.directory())
	var state := Gen2WorldState.new({}, {}, {POTION: 5, KEY_ITEM: 1}, {0: 500})
	_world = Gen2WorldAPI.open(
		_data, Fixture.MAP_GROUP, Fixture.MAP_NUMBER, Vector2i(7, 6), state
	)
	_save = Gen2SaveStore.create_development_save(_data, 0)
	_save.world = _world.snapshot()


func after_each() -> void:
	RomCache.clear(Fixture.directory())


## A tossable stack and one `_CheckTossableItem` refuses, which is what the
## source's `ITEMATTR_PERMISSIONS` bit means: set is "cannot".
func _write_items() -> void:
	var items: Array = RomCache.read_json(RomCache.items_path(Fixture.directory()))
	for raw: Dictionary in items:
		match int(raw.get("number", 0)):
			POTION:
				raw["name"] = "POTION"
				raw["pocket"] = Gen2WorldPack.TYPE_ITEM
				raw["permissions"] = Gen2WorldPack.CANT_SELECT
				raw["field_menu"] = Gen2WorldPack.ITEMMENU_PARTY
			KEY_ITEM:
				raw["name"] = "BICYCLE"
				raw["pocket"] = Gen2WorldPack.TYPE_KEY_ITEM
				raw["permissions"] = Gen2WorldPack.CANT_TOSS
				raw["field_menu"] = Gen2WorldPack.ITEMMENU_CURRENT
	RomCache.write_json(RomCache.items_path(Fixture.directory()), items)


## On the flat item model `_TossItem`'s whole pocket walk is one subtraction, and
## the stack it leaves behind is what the pack lists next.
func test_tossing_part_of_a_stack_leaves_the_rest() -> void:
	var result: Dictionary = Gen2WorldBagHost.toss(_world, _save, POTION, 2, false)
	assert_true(bool(result["ok"]), str(result))
	assert_eq(result["quantity"], 2)
	assert_eq(result["remaining"], 3)
	assert_eq(result["name"], "POTION")
	assert_eq(_world.state.item_quantity(POTION), 3)


func test_tossing_the_whole_stack_empties_it() -> void:
	assert_true(bool(Gen2WorldBagHost.toss(_world, _save, POTION, 5, false)["ok"]))
	assert_eq(_world.state.item_quantity(POTION), 0)
	for pocket: Dictionary in Gen2WorldPack.build(_data, _world.state):
		for entry: Dictionary in pocket.get("items", []):
			assert_ne(int(entry.get("item", 0)), POTION, "it is off the list")


## The quantity is `wCurItemQuantity`, which the dial has already clamped to the
## stack; a caller that is not that dial is refused rather than trusted.
func test_a_quantity_outside_the_stack_is_refused_and_changes_nothing() -> void:
	for quantity: int in [0, -1, 6, 99]:
		var result: Dictionary = Gen2WorldBagHost.toss(_world, _save, POTION, quantity, false)
		assert_false(bool(result["ok"]), "quantity %d" % quantity)
		assert_eq(result["reason"], &"invalid_toss_quantity")
	assert_eq(_world.state.item_quantity(POTION), 5)


## `_CheckTossableItem` is the first thing `.ItemBallsKey_LoadSubmenu` branches
## on, so an item that refuses it never has TOSS in its submenu at all.
func test_an_item_that_cannot_be_tossed_is_refused_at_both_ends() -> void:
	assert_false(Gen2WorldPack.can_toss(_data, KEY_ITEM))
	for entry: Dictionary in Gen2WorldPack.item_submenu(_data, KEY_ITEM):
		assert_ne(StringName(entry.get("action", &"")), Gen2WorldPack.ACTION_TOSS)
	var result: Dictionary = Gen2WorldBagHost.toss(_world, _save, KEY_ITEM, 1, false)
	assert_false(bool(result["ok"]))
	assert_eq(result["reason"], &"item_cannot_be_tossed")
	assert_eq(_world.state.item_quantity(KEY_ITEM), 1)


func test_an_unknown_item_is_refused() -> void:
	var result: Dictionary = Gen2WorldBagHost.toss(_world, _save, 250, 1, false)
	assert_false(bool(result["ok"]))
	assert_eq(result["reason"], &"unknown_item")


## The commit boundary is optional: a toss with no save behind it still changes
## the live world, which is what a screen without one does.
func test_a_toss_without_a_save_still_changes_the_world() -> void:
	assert_true(bool(Gen2WorldBagHost.toss(_world, null, POTION, 1, false)["ok"]))
	assert_eq(_world.state.item_quantity(POTION), 4)


## `Gen2WorldTransaction.run` puts the live world back when the candidate save
## refuses, so a refused toss leaves the stack where it was.
func test_a_refused_candidate_save_rolls_the_world_back() -> void:
	_save.party.clear()
	_save.player_name = ""
	var result: Dictionary = Gen2WorldBagHost.toss(_world, _save, POTION, 2, false)
	assert_false(bool(result["ok"]), str(result))
	assert_eq(_world.state.item_quantity(POTION), 5, "the stack is back")


## `PlayerDepositItemMenu` and `PlayerWithdrawItemMenu` are the same move in
## opposite directions, and the flat model keeps one stack per item on each side.
func test_a_stack_moves_between_the_bag_and_the_pc_and_back() -> void:
	var deposited: Dictionary = Gen2WorldPC.deposit(_world, _save, POTION, 2, false)
	assert_true(bool(deposited["ok"]), str(deposited))
	assert_eq(deposited["bag"], 3)
	assert_eq(deposited["pc"], 2)
	assert_eq(_world.state.item_quantity(POTION), 3)
	assert_eq(_world.state.pc_item_quantity(POTION), 2)

	var withdrawn: Dictionary = Gen2WorldPC.withdraw(_world, _save, POTION, 2, false)
	assert_true(bool(withdrawn["ok"]), str(withdrawn))
	assert_eq(_world.state.item_quantity(POTION), 5)
	assert_eq(_world.state.pc_item_quantity(POTION), 0, "an emptied stack is gone")


## `.no_toss` keeps a key item out of the PC, which is the same permission bit
## TOSS reads.
func test_a_key_item_cannot_be_deposited() -> void:
	var result: Dictionary = Gen2WorldPC.deposit(_world, _save, KEY_ITEM, 1, false)
	assert_false(bool(result["ok"]))
	assert_eq(result["reason"], &"item_cannot_be_deposited")
	assert_eq(_world.state.pc_item_quantity(KEY_ITEM), 0)


## `.NoRoomInPC`: `ReceiveItem` fails before anything leaves the bag, so a full
## PC leaves the stack where it was.
func test_a_full_pc_refuses_a_new_stack_without_taking_it() -> void:
	var full: Dictionary = {}
	for slot: int in Gen2WorldPack.MAX_PC_ITEMS:
		full[slot + 20] = 1
	assert_true(bool(_world.state.apply_changes({}, {}, {"pc_items": full})["ok"]))
	var result: Dictionary = Gen2WorldPC.deposit(_world, _save, POTION, 1, false)
	assert_false(bool(result["ok"]))
	assert_eq(result["reason"], &"pc_full")
	assert_eq(_world.state.item_quantity(POTION), 5)


## `TossItemFromPC` is `TossItem` on the other array, and reads `CanToss` the
## same way.
func test_the_pc_tosses_its_own_stack() -> void:
	assert_true(bool(Gen2WorldPC.deposit(_world, _save, POTION, 3, false)["ok"]))
	var result: Dictionary = Gen2WorldPC.toss(_world, _save, POTION, 1, false)
	assert_true(bool(result["ok"]), str(result))
	assert_eq(_world.state.pc_item_quantity(POTION), 2)
	assert_eq(_world.state.item_quantity(POTION), 2, "the bag is not touched")


## `.ChooseWhichPCListToUse`, and the HALL OF FAME row this project drops for
## want of saved induction records.
func test_the_top_menu_grows_with_the_dex_and_the_hall_of_fame() -> void:
	var rows: Callable = func() -> Array:
		var out: Array = []
		for row: Dictionary in Gen2WorldPC.top_menu(_data, _world.state, "GOLD"):
			out.append(int(row["row"]))
		return out
	assert_eq(Gen2WorldPC.top_menu_list(_world.state), Gen2WorldPC.PCPC_BEFORE_POKEDEX)
	assert_eq(rows.call(), [
		Gen2WorldPC.PCPCITEM_BILLS_PC, Gen2WorldPC.PCPCITEM_PLAYERS_PC,
		Gen2WorldPC.PCPCITEM_TURN_OFF,
	])
	assert_eq(
		String(Gen2WorldPC.top_menu(_data, _world.state, "GOLD")[1]["name"]), "GOLD's PC"
	)

	_world.state.set_engine_flag(Gen2WorldState.ENGINE_POKEDEX, true)
	assert_eq(Gen2WorldPC.top_menu_list(_world.state), Gen2WorldPC.PCPC_BEFORE_HOF)
	assert_true(Gen2WorldPC.PCPCITEM_OAKS_PC in rows.call())

	_world.state.set_hall_of_fame(true)
	assert_eq(Gen2WorldPC.top_menu_list(_world.state), Gen2WorldPC.PCPC_POSTGAME)
	assert_false(
		Gen2WorldPC.PCPCITEM_HALL_OF_FAME in rows.call(),
		"the induction viewer has no records to read"
	)


## `PlayersPCMenuData.WhichPC`: the bedroom's list ends in TURN OFF, a Pokemon
## Center's in LOG OFF, because the top menu is still open behind it.
func test_the_item_pc_ends_in_log_off_only_inside_the_pokemon_center() -> void:
	var last: Callable = func(house: bool) -> int:
		var menu: Array = Gen2WorldPC.players_pc_menu(_data, house)
		return int(menu[menu.size() - 1]["row"])
	assert_eq(last.call(false), Gen2WorldPC.PLAYERSPCITEM_LOG_OFF)
	assert_eq(last.call(true), Gen2WorldPC.PLAYERSPCITEM_TURN_OFF)


## `PC_CheckPartyForPokemon`, which is the one refusal the top menu owns.
func test_an_empty_party_cannot_open_the_pokemon_centers_pc() -> void:
	assert_true(Gen2WorldPC.can_open(_save))
	_save.party.clear()
	assert_false(Gen2WorldPC.can_open(_save))
