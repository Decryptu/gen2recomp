class_name Gen2WorldPC
extends RefCounted

## `engine/events/pokecenter_pc.asm`: the Pokemon Center's top menu, the item
## PC behind its `<PLAYER>'S PC` row, and the two transactions that move a stack
## between the bag and `wPCItems`.
##
## Scene-free like the other world hosts. The rows and their per-state lists are
## the source's own tables; a host draws whichever list [method top_menu] and
## [method players_pc_menu] return and calls the transactions below. The commit
## boundary is [Gen2WorldTransaction], the same one the mart, Kurt and the bag
## go through.
##
## Two of the source's rows are absent from the lists this returns rather than
## offered and refused, because neither has anything behind it: HALL OF FAME is
## `_HallOfFamePC`'s viewer over saved induction records and MAIL BOX is
## `_PlayerMailBoxMenu`'s over `wMailbox`, and the save model keeps neither.
## DECORATION is the third: `_PlayerDecorationMenu` browses the owned-decoration
## flags, and [Gen2WorldState] holds only the four decorations already placed.

## `PokemonCenterPC.Jumptable` indexes.
const PCPCITEM_PLAYERS_PC: int = 0
const PCPCITEM_BILLS_PC: int = 1
const PCPCITEM_OAKS_PC: int = 2
const PCPCITEM_HALL_OF_FAME: int = 3
const PCPCITEM_TURN_OFF: int = 4

## `PokemonCenterPC.WhichPC`, the three lists `.ChooseWhichPCListToUse` picks
## between: before the Pokedex, after it, and after the Hall of Fame. The lists
## themselves are imported.
const PCPC_BEFORE_POKEDEX: int = 0
const PCPC_BEFORE_HOF: int = 1
const PCPC_POSTGAME: int = 2

## `PlayersPCMenuData.PlayersPCMenuPointers` indexes.
const PLAYERSPCITEM_WITHDRAW_ITEM: int = 0
const PLAYERSPCITEM_DEPOSIT_ITEM: int = 1
const PLAYERSPCITEM_TOSS_ITEM: int = 2
const PLAYERSPCITEM_MAIL_BOX: int = 3
const PLAYERSPCITEM_DECORATION: int = 4
const PLAYERSPCITEM_LOG_OFF: int = 5
const PLAYERSPCITEM_TURN_OFF: int = 6

## `PlayersPCMenuData.WhichPC`. The bedroom's own list is the one that ends in
## TURN OFF and carries DECORATION; a Pokemon Center's ends in LOG OFF, because
## the top menu is still open behind it.
const PLAYERSPC_NORMAL: int = 0
const PLAYERSPC_HOUSE: int = 1

## What `PlaceNthMenuStrings` would draw the player's own name for. The importer
## keeps the cartridge's marker rather than a placeholder.
const PLAYER_MARKER: String = "<PLAYER>"

## The rows above with nothing behind them, dropped from every list rather than
## offered and refused. See the class comment for what each needs first.
const UNBUILT_TOP_MENU_ROWS: Array[int] = [PCPCITEM_HALL_OF_FAME]
const UNBUILT_PLAYERS_PC_ROWS: Array[int] = [
	PLAYERSPCITEM_MAIL_BOX, PLAYERSPCITEM_DECORATION,
]


## `.ChooseWhichPCListToUse`: the Pokedex first, then `wHallOfFameCount`, which
## is the induction flag here because the save model counts no records.
static func top_menu_list(state: Gen2WorldState) -> int:
	if state == null or not state.is_engine_flag_active(Gen2WorldState.ENGINE_POKEDEX):
		return PCPC_BEFORE_POKEDEX
	return PCPC_POSTGAME if state.hall_of_fame() else PCPC_BEFORE_HOF


## The top menu's rows for [param state], as `{row, name}` in the source list's
## own order. [param player_name] fills the `<PLAYER>` the cartridge stores in
## the first row's own string.
static func top_menu(
	data: GameData, state: Gen2WorldState, player_name: String = ""
) -> Array:
	return _rows(
		data, false, _list(data, false, top_menu_list(state)),
		UNBUILT_TOP_MENU_ROWS, player_name
	)


## The item PC's own rows. [param house] picks `PLAYERSPC_HOUSE`, which is what
## `_PlayersHousePC` passes and the Pokemon Center's `PlayersPC` does not.
static func players_pc_menu(data: GameData, house: bool) -> Array:
	return _rows(
		data, true, _list(data, true, PLAYERSPC_HOUSE if house else PLAYERSPC_NORMAL),
		UNBUILT_PLAYERS_PC_ROWS, ""
	)


## One imported `.WhichPC` list, or an empty one on a cache without the tables,
## which leaves the menu with nothing to offer rather than a guessed order.
static func _list(data: GameData, players: bool, index: int) -> Array:
	if data == null:
		return []
	var lists: Array = data.pokecenter_pc_lists(players)
	if index < 0 or index >= lists.size() or not lists[index] is Array:
		return []
	return lists[index]


## `PlaceNthMenuStrings`: each list entry names a jumptable row, and the row
## names its own string.
static func _rows(
	data: GameData, players: bool, list: Array, unbuilt: Array[int],
	player_name: String
) -> Array:
	var order: Array[String] = RomLayout.POKECENTER_PC_PLAYERS_ORDER if players \
		else RomLayout.POKECENTER_PC_ROWS
	var out: Array = []
	for raw_row: Variant in list:
		var row: int = int(raw_row)
		if row < 0 or row >= order.size() or row in unbuilt:
			continue
		var name: String = data.pokecenter_pc_row(String(order[row]), players)
		if name.is_empty():
			continue
		out.append({
			"row": row,
			"name": name.replace(
				PLAYER_MARKER, player_name if not player_name.is_empty() else "PLAYER"
			),
		})
	return out


## `PC_CheckPartyForPokemon`: an empty party cannot open the Pokemon Center's PC
## at all, which is the one refusal the top menu has of its own.
static func can_open(save: Gen2SaveData) -> bool:
	return save != null and not save.party.is_empty()


## The bag as rows a deposit list can draw, and the PC as rows a withdraw or
## toss list can. Both are sorted by item number, which is the only order a flat
## map has; the source's packed arrays keep insertion order instead.
static func bag_entries(data: GameData, state: Gen2WorldState) -> Array:
	return _entries(data, state.items() if state != null else {})


static func pc_entries(data: GameData, state: Gen2WorldState) -> Array:
	return _entries(data, state.pc_items() if state != null else {})


static func _entries(data: GameData, owned: Dictionary) -> Array:
	var out: Array = []
	if data == null:
		return out
	var numbers: Array = owned.keys()
	numbers.sort()
	for raw_item: Variant in numbers:
		var item: int = int(raw_item)
		var quantity: int = int(owned[raw_item])
		if quantity <= 0:
			continue
		var definition: Dictionary = data.item(item)
		if definition.is_empty():
			continue
		out.append({
			"item": item,
			"name": String(definition.get("name", "UNKNOWN")),
			"quantity": quantity,
		})
	return out


## `PlayerDepositItemMenu`: the stack leaves `wNumItems` and arrives in
## `wNumPCItems`. The source refuses an item whose `CheckItemMenu` attribute is
## one of the three `.no_toss` rows, which is what keeps a key item out of the
## PC.
static func deposit(
	world: Gen2WorldAPI, save: Gen2SaveData, item: int, quantity: int = 1,
	persist: bool = true
) -> Dictionary:
	return _transfer(world, save, item, quantity, true, persist)


## `PlayerWithdrawItemMenu`, which is the same move the other way and refuses
## nothing: anything in the PC came out of the bag.
static func withdraw(
	world: Gen2WorldAPI, save: Gen2SaveData, item: int, quantity: int = 1,
	persist: bool = true
) -> Dictionary:
	return _transfer(world, save, item, quantity, false, persist)


## `PlayerTossItemMenu`'s `TossItemFromPC`, which is `TossItem` on the PC's own
## array. `CanToss` is read the same way it is for the bag.
static func toss(
	world: Gen2WorldAPI, save: Gen2SaveData, item: int, quantity: int = 1,
	persist: bool = true
) -> Dictionary:
	if world == null or world.data == null or world.state == null:
		return Gen2WorldTransaction.failure(&"missing_world", {})
	var definition: Dictionary = world.data.item(item)
	if definition.is_empty():
		return Gen2WorldTransaction.failure(&"unknown_item", {"item": item})
	if not Gen2WorldPack.can_toss(world.data, item):
		return Gen2WorldTransaction.failure(&"item_cannot_be_tossed", {"item": item})
	var owned: int = world.state.pc_item_quantity(item)
	if quantity < 1 or quantity > owned:
		return Gen2WorldTransaction.failure(&"invalid_toss_quantity", {
			"item": item, "quantity": quantity, "owned": owned,
		})
	return _commit(world, save, persist, {"pc_items": {item: owned - quantity}}, {
		"item": item,
		"name": String(definition.get("name", "UNKNOWN")),
		"quantity": quantity,
		"bag": world.state.item_quantity(item),
		"pc": owned - quantity,
	})


static func _transfer(
	world: Gen2WorldAPI, save: Gen2SaveData, item: int, quantity: int,
	to_pc: bool, persist: bool
) -> Dictionary:
	if world == null or world.data == null or world.state == null:
		return Gen2WorldTransaction.failure(&"missing_world", {})
	var definition: Dictionary = world.data.item(item)
	if definition.is_empty():
		return Gen2WorldTransaction.failure(&"unknown_item", {"item": item})
	if to_pc and not Gen2WorldPack.can_toss(world.data, item):
		return Gen2WorldTransaction.failure(&"item_cannot_be_deposited", {"item": item})
	var bag: int = world.state.item_quantity(item)
	var pc: int = world.state.pc_item_quantity(item)
	var source: int = bag if to_pc else pc
	var destination: int = pc if to_pc else bag
	if quantity < 1 or quantity > source:
		return Gen2WorldTransaction.failure(&"invalid_transfer_quantity", {
			"item": item, "quantity": quantity, "owned": source,
		})
	if destination + quantity > Gen2WorldPack.MAX_ITEM_STACK:
		return Gen2WorldTransaction.failure(&"item_stack_full", {
			"item": item, "quantity": quantity, "owned": destination,
		})
	## `ReceiveItem` fails on a full destination list before anything is taken
	## from the source, which is what `.PackFull` and `.NoRoomInPC` report. The
	## bag's own check is per pocket, so it goes through the pack's; the PC is
	## one flat list of fifty.
	if to_pc:
		if destination == 0 and world.state.pc_items().size() >= Gen2WorldPack.MAX_PC_ITEMS:
			return Gen2WorldTransaction.failure(&"pc_full", {"item": item})
	else:
		var room: Dictionary = Gen2WorldPack.receive_check(
			world.data, world.state.items(), item, quantity
		)
		if not bool(room.get("ok", false)):
			return Gen2WorldTransaction.failure(
				StringName(room.get("reason", &"pack_full")), {"item": item}
			)
	var changes: Dictionary = {
		"items": {item: bag - quantity if to_pc else bag + quantity},
		"pc_items": {item: pc + quantity if to_pc else pc - quantity},
	}
	return _commit(world, save, persist, changes, {
		"item": item,
		"name": String(definition.get("name", "UNKNOWN")),
		"quantity": quantity,
		"bag": changes["items"][item],
		"pc": changes["pc_items"][item],
	})


static func _commit(
	world: Gen2WorldAPI, save: Gen2SaveData, persist: bool,
	changes: Dictionary, answer: Dictionary
) -> Dictionary:
	var before: Gen2WorldSnapshot = world.snapshot()
	var applied: Dictionary = world.state.apply_changes({}, {}, changes)
	if not bool(applied.get("ok", false)):
		return Gen2WorldTransaction.failure(&"pc_state_failed", applied)
	var committed: Dictionary = Gen2WorldTransaction.run(world, save, before, persist)
	if not bool(committed.get("ok", false)):
		return committed
	var out: Dictionary = answer.duplicate()
	out["ok"] = true
	return out
