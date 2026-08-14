extends RefCounted

var _r: RefCounted = null

## Verifies the pack submenu's three permission tests against freshly imported
## real caches, over every item row rather than a sampled one.
##
## Expected values come from the pinned pokecrystal and pokegold sources:
## `engine/items/pack.asm`'s `.ItemBallsKey_LoadSubmenu`, which asks
## `_CheckTossableItem`, `CheckSelectableItem` and `CheckItemMenu` in that order,
## `RegisterItem`, and `engine/pokemon/mon_menu.asm`'s `.GiveItem`, whose loop
## refuses the key item pocket and then whatever `CheckTossableItem` refuses.
## `data/items/attributes.asm` is byte identical between the pins, so nothing
## here is profile split.
##
## The point of sweeping all 256 rows is that a permission bit read the wrong way
## round is invisible on the one item a screen test picks: the bit is set on the
## item that *cannot* do the thing, so an inverted read offers TOSS on every key
## item and SEL on none.
##
##   Godot --headless --path . -s res://tools/validate.gd -- pack

## `constants/item_constants.asm`'s own hex comment column. The five key items
## whose `item_attribute` is `CANT_TOSS` alone, which is the whole of what a
## player can hand the SELECT button on all three cartridges: every other key
## item is `CANT_SELECT | CANT_TOSS`, the CARD KEY and the SQUIRTBOTTLE included.
const REGISTERABLE_KEY_ITEMS: Dictionary = {
	0x07: "BICYCLE",
	0x37: "ITEMFINDER",
	0x3A: "OLD ROD",
	0x3B: "GOOD ROD",
	0x3D: "SUPER ROD",
}

## `ItemAttributes` is 256 rows on both pins, the last of which is the terminator
## the item list never reaches.
const ITEM_ROWS: int = 255


func run(r: RefCounted) -> void:
	_r = r
	for game_id: StringName in _r.GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_verify_registerable(game_id, data)
		_verify_submenus(game_id, data)


## `CheckSelectableItem` over the real rows. The eight named key items are the
## whole of what a player can register; the unused `NO_LIMITS` rows carry no bit
## either, which is faithful and is what the census counts separately.
func _verify_registerable(game_id: StringName, data: GameData) -> void:
	var key_items: Array[int] = []
	var total: int = 0
	for number: int in range(1, ITEM_ROWS + 1):
		if data.item(number).is_empty() or not Gen2WorldPack.can_select(data, number):
			continue
		total += 1
		if Gen2WorldPack.pocket_for(data, number) == Gen2WorldPack.TYPE_KEY_ITEM:
			key_items.append(number)
	for number: int in REGISTERABLE_KEY_ITEMS:
		_r.check(
			key_items.has(number),
			"%s: $%02X (%s) cannot be registered." % [
				game_id, number, String(REGISTERABLE_KEY_ITEMS[number]),
			]
		)
	_r.check(
		key_items.size() == REGISTERABLE_KEY_ITEMS.size(),
		"%s: %d key items are registerable, not the pinned %d." % [
			game_id, key_items.size(), REGISTERABLE_KEY_ITEMS.size(),
		]
	)
	print("%s: %d rows are registerable, %d of them key items." % [
		game_id, total, key_items.size(),
	])


## The submenu each row builds, against the permissions it was built from. GIVE
## and SEL are the two the screens act on, so each is checked both ways: an
## action offered that the transaction would refuse is the bug worth catching.
func _verify_submenus(game_id: StringName, data: GameData) -> void:
	var holdable: int = 0
	for number: int in range(1, ITEM_ROWS + 1):
		if data.item(number).is_empty():
			continue
		var actions: Array[StringName] = []
		for entry: Dictionary in Gen2WorldPack.item_submenu(data, number):
			actions.append(StringName(entry.get("action", &"")))
		var name: String = data.item_name(number)
		_r.check(
			actions.has(Gen2WorldPack.ACTION_QUIT),
			"%s: $%02X (%s) has a submenu with no QUIT." % [game_id, number, name]
		)
		if Gen2WorldPack.can_hold(data, number):
			holdable += 1
		else:
			_r.check(
				not actions.has(Gen2WorldPack.ACTION_GIVE),
				"%s: $%02X (%s) offers GIVE but cannot be held." % [game_id, number, name]
			)
		_r.check(
			not actions.has(Gen2WorldPack.ACTION_SELECT)
				or Gen2WorldPack.can_select(data, number),
			"%s: $%02X (%s) offers SEL but cannot be registered." % [game_id, number, name]
		)
		## `.ItemBallsKey_LoadSubmenu` reaches a header with SEL only from the
		## tossable branch or the untossable one, never from the TM/HM pocket's
		## own two.
		_r.check(
			not actions.has(Gen2WorldPack.ACTION_SELECT)
				or Gen2WorldPack.pocket_for(data, number) != Gen2WorldPack.TYPE_TM_HM,
			"%s: $%02X (%s) is a TM or HM offering SEL." % [game_id, number, name]
		)
	print("%s: %d rows can be held by a Pokemon." % [game_id, holdable])
