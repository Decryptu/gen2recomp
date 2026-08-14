class_name Gen2WorldBagHost
extends RefCounted

## Bag-only transactions: what the pack changes without a party, a mart or a
## script behind it. `TossItem` (`home/item.asm`, `_TossItem`), the two halves of
## `GiveTakePartyMonItem` and `RegisterItem`.
##
## The source routine walks `_TossItem`'s pocket jumptable to find which packed
## array the item lives in and calls `RemoveItemFromPocket` on it. The flat item
## model has one stack per item and no pocket arrays, so the whole walk is a
## subtraction; HANDOFF's item-stack divergence covers the difference.
##
## The commit boundary is [Gen2WorldTransaction], the same one the mart, Kurt
## and the party hosts go through.

## `TossItem` with `wCurItemQuantity`, as one validated transaction.
##
## `TossMenu` is only reachable from a submenu that offered TOSS, so the
## permission is already settled by the time the source gets here; it is checked
## again because a caller is not always that menu.
static func toss(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	item: int,
	quantity: int = 1,
	persist: bool = true
) -> Dictionary:
	if world == null or world.data == null or world.state == null:
		return Gen2WorldTransaction.failure(&"missing_world", {})
	var definition: Dictionary = world.data.item(item)
	if definition.is_empty():
		return Gen2WorldTransaction.failure(&"unknown_item", {"item": item})
	if not Gen2WorldPack.can_toss(world.data, item):
		return Gen2WorldTransaction.failure(&"item_cannot_be_tossed", {"item": item})
	var owned: int = world.state.item_quantity(item)
	if quantity < 1 or quantity > owned:
		return Gen2WorldTransaction.failure(&"invalid_toss_quantity", {
			"item": item, "quantity": quantity, "owned": owned,
		})
	var before: Gen2WorldSnapshot = world.snapshot()
	var applied: Dictionary = world.state.apply_changes({}, {}, {
		"items": {item: owned - quantity},
	})
	if not bool(applied.get("ok", false)):
		return Gen2WorldTransaction.failure(&"toss_state_failed", applied)
	var committed: Dictionary = Gen2WorldTransaction.run(world, save, before, persist)
	if not bool(committed.get("ok", false)):
		return committed
	return {
		"ok": true,
		"item": item,
		"name": String(definition.get("name", "UNKNOWN")),
		"quantity": quantity,
		"remaining": owned - quantity,
	}


## `TryGiveItemToPartymon`, which the pack's GIVE and the party submenu's ITEM
## both reach. [param swap] is the answer to `PokemonAskSwapItemText`: without it
## a Pokemon already holding something is refused with nothing written, which is
## where the source stops to ask.
##
## `ItemIsMail` has no counterpart here, so `.please_remove_mail` and
## `ComposeMailMessage` are unreachable and no item is refused for being mail.
static func give_to_party(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	item: int,
	party_index: int,
	swap: bool = false,
	persist: bool = true
) -> Dictionary:
	if world == null or world.data == null or world.state == null:
		return Gen2WorldTransaction.failure(&"missing_world", {})
	var definition: Dictionary = world.data.item(item)
	if definition.is_empty():
		return Gen2WorldTransaction.failure(&"unknown_item", {"item": item})
	if not Gen2WorldPack.can_hold(world.data, item):
		return Gen2WorldTransaction.failure(&"item_cannot_be_held", {"item": item})
	var owned: int = world.state.item_quantity(item)
	if owned <= 0:
		return Gen2WorldTransaction.failure(&"insufficient_item_quantity", {"item": item})
	var opened: Dictionary = Gen2WorldTransaction.begin(world, save)
	if not bool(opened.get("ok", false)):
		return opened
	var candidate: Gen2SaveData = opened["candidate"]
	var mon: Gen2SaveMon = _party_member(candidate, party_index)
	if mon == null:
		return Gen2WorldTransaction.failure(&"unknown_party_member", {"party_index": party_index})
	if mon.is_egg:
		return Gen2WorldTransaction.failure(&"cannot_hold_egg", {"party_index": party_index})
	var held: int = mon.item
	if held > 0 and not swap:
		return Gen2WorldTransaction.failure(&"already_holding", {
			"party_index": party_index, "held": held,
			"held_name": world.data.item_name(held),
		})
	var changes: Dictionary = {item: owned - 1}
	if held > 0:
		## `GiveItemToPokemon` runs before `ReceiveItemFromPokemon`, so the entry
		## the outgoing item just freed is there for the one coming back.
		var remaining: Dictionary = world.state.items()
		remaining[item] = owned - 1
		if int(remaining[item]) <= 0:
			remaining.erase(item)
		var room: Dictionary = Gen2WorldPack.receive_check(world.data, remaining, held, 1)
		if not bool(room.get("ok", false)):
			return Gen2WorldTransaction.failure(&"bag_full", room)
		changes[held] = int(remaining.get(held, 0)) + 1
	mon.item = item
	var before: Gen2WorldSnapshot = world.snapshot()
	var applied: Dictionary = world.state.apply_changes({}, {}, {"items": changes})
	if not bool(applied.get("ok", false)):
		return Gen2WorldTransaction.failure(&"give_state_failed", applied)
	var committed: Dictionary = Gen2WorldTransaction.commit(
		world, save, candidate, before, persist
	)
	if not bool(committed.get("ok", false)):
		return committed
	return {
		"ok": true,
		"item": item,
		"name": String(definition.get("name", "UNKNOWN")),
		"party_index": party_index,
		"held": held,
		"held_name": world.data.item_name(held) if held > 0 else "",
	}


## `TakePartyItem`. An empty hand and a full pack are both refusals with their
## own text, so neither is folded into the other.
static func take_from_party(
	world: Gen2WorldAPI, save: Gen2SaveData, party_index: int, persist: bool = true
) -> Dictionary:
	if world == null or world.data == null or world.state == null:
		return Gen2WorldTransaction.failure(&"missing_world", {})
	var opened: Dictionary = Gen2WorldTransaction.begin(world, save)
	if not bool(opened.get("ok", false)):
		return opened
	var candidate: Gen2SaveData = opened["candidate"]
	var mon: Gen2SaveMon = _party_member(candidate, party_index)
	if mon == null:
		return Gen2WorldTransaction.failure(&"unknown_party_member", {"party_index": party_index})
	var held: int = mon.item
	if held <= 0:
		return Gen2WorldTransaction.failure(&"not_holding", {"party_index": party_index})
	var room: Dictionary = Gen2WorldPack.receive_check(world.data, world.state.items(), held, 1)
	if not bool(room.get("ok", false)):
		return Gen2WorldTransaction.failure(&"bag_full", room)
	mon.item = 0
	var before: Gen2WorldSnapshot = world.snapshot()
	var applied: Dictionary = world.state.apply_changes({}, {}, {
		"items": {held: world.state.item_quantity(held) + 1},
	})
	if not bool(applied.get("ok", false)):
		return Gen2WorldTransaction.failure(&"take_state_failed", applied)
	var committed: Dictionary = Gen2WorldTransaction.commit(
		world, save, candidate, before, persist
	)
	if not bool(committed.get("ok", false)):
		return committed
	return {
		"ok": true,
		"item": held,
		"name": world.data.item_name(held),
		"party_index": party_index,
	}


## `RegisterItem`. `wWhichRegisteredItem` packs the pocket and the item's number
## within it so `CheckRegisteredItem` can find the entry again; with one stack
## per item that number is the item, and the ownership it stood for is what
## [method registered_item] tests.
static func register(
	world: Gen2WorldAPI, save: Gen2SaveData, item: int, persist: bool = true
) -> Dictionary:
	if world == null or world.data == null or world.state == null:
		return Gen2WorldTransaction.failure(&"missing_world", {})
	var definition: Dictionary = world.data.item(item)
	if definition.is_empty():
		return Gen2WorldTransaction.failure(&"unknown_item", {"item": item})
	if not Gen2WorldPack.can_select(world.data, item):
		return Gen2WorldTransaction.failure(&"item_cannot_be_registered", {"item": item})
	if world.state.item_quantity(item) <= 0:
		return Gen2WorldTransaction.failure(&"insufficient_item_quantity", {"item": item})
	var before: Gen2WorldSnapshot = world.snapshot()
	world.state.set_registered_item(item)
	var committed: Dictionary = Gen2WorldTransaction.run(world, save, before, persist)
	if not bool(committed.get("ok", false)):
		return committed
	return {"ok": true, "item": item, "name": String(definition.get("name", "UNKNOWN"))}


## `CheckRegisteredItem`, which is what SELECT asks first: a registration is only
## good while the pack still holds the item, and the check clears it where it
## does not. The clear is written straight onto the live state, the way the
## source writes `wRegisteredItem` outside any save.
static func registered_item(world: Gen2WorldAPI) -> int:
	if world == null or world.data == null or world.state == null:
		return 0
	var item: int = world.state.registered_item()
	if item <= 0:
		return 0
	if world.state.item_quantity(item) > 0 and Gen2WorldPack.can_select(world.data, item):
		return item
	world.state.set_registered_item(0)
	return 0


static func _party_member(save: Gen2SaveData, party_index: int) -> Gen2SaveMon:
	if save == null or party_index < 0 or party_index >= save.party.size():
		return null
	return save.party[party_index] as Gen2SaveMon
