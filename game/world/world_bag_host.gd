class_name Gen2WorldBagHost
extends RefCounted

## Bag-only transactions: what the pack changes without a party, a mart or a
## script behind it. `TossItem` (`home/item.asm`, `_TossItem`) is the first.
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
