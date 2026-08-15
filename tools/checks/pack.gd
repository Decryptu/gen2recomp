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

## The ten rows whose field-menu nibble is ITEMMENU_CLOSE, byte identical
## between the pins. The unit tier writes the nibble onto its own fixture, so
## only a real cache can say which rows actually carry it: the Coin Case reads
## like one and is ITEMMENU_CURRENT, printing its count inside the pack.
const CLOSE_ITEMS: Dictionary = {
	0x07: "BICYCLE",
	0x13: "ESCAPE ROPE",
	0x37: "ITEMFINDER",
	0x3A: "OLD ROD",
	0x3B: "GOOD ROD",
	0x3D: "SUPER ROD",
	0x7F: "CARD KEY",
	0x85: "BASEMENT KEY",
	0x9C: "SACRED ASH",
	0xAF: "SQUIRTBOTTLE",
}

## The three maps and cells `card_key.asm`, `basement_key.asm` and
## `squirtbottle.asm` name, with the cell the player stands on to face each.
## Group 3 runs eight lower on pokegold from `UNION_CAVE_1F`, which moves the
## underground and nothing else here.
const RADIO_TOWER_3F := Vector2i(3, 19)
const RADIO_TOWER_STAND := Vector2i(14, 3)
const GOLDENROD_UNDERGROUND_CRYSTAL := Vector2i(3, 53)
const GOLDENROD_UNDERGROUND_GOLD_SILVER := Vector2i(3, 45)
const GOLDENROD_UNDERGROUND_STAND := Vector2i(18, 7)
const ROUTE_36 := Vector2i(10, 3)
const SUDOWOODO_CELL := Vector2i(35, 9)
const SUDOWOODO_STAND := Vector2i(35, 10)
## `.Fight` is `opentext`, `writetext`, `yesorno`, `iffalse` and `closetext`, so
## `WateredWeirdTreeScript` starts nine bytes into it on all three cartridges.
const WATERED_TREE_OFFSET: int = 9

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
		_verify_field_effects(game_id, data)
		_verify_key_item_effects(game_id, data)


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


## `UseItem`'s jumptable over the real nibbles. Every ITEMMENU_CLOSE row has to
## have a `.Field` effect and nothing else may claim one: a row named by
## FIELD_EFFECTS that the cartridge puts on `.Current` or `.Party` is dead, and
## a CLOSE row with no entry falls through to `.Oak` in silence.
func _verify_field_effects(game_id: StringName, data: GameData) -> void:
	var close_rows: Dictionary = {}
	for number: int in range(1, ITEM_ROWS + 1):
		if data.item(number).is_empty():
			continue
		if Gen2WorldPack.field_use_kind(data, number) == Gen2WorldPack.ITEMMENU_CLOSE:
			close_rows[number] = true
		_r.check(
			not Gen2WorldPack.FIELD_EFFECTS.has(number)
				or close_rows.has(number),
			"%s: $%02X (%s) has a field effect but is not ITEMMENU_CLOSE." % [
				game_id, number, data.item_name(number),
			]
		)
	for number: int in CLOSE_ITEMS:
		_r.check(
			close_rows.has(number),
			"%s: $%02X (%s) is not ITEMMENU_CLOSE on this cache." % [
				game_id, number, String(CLOSE_ITEMS[number]),
			]
		)
	_r.check(
		close_rows.size() == CLOSE_ITEMS.size(),
		"%s: %d rows are ITEMMENU_CLOSE, not the pinned %d." % [
			game_id, close_rows.size(), CLOSE_ITEMS.size(),
		]
	)
	for number: int in close_rows:
		_r.check(
			Gen2WorldPack.field_effect(data, number) != Gen2WorldPack.FIELD_EFFECT_NONE,
			"%s: $%02X (%s) is ITEMMENU_CLOSE with no field effect." % [
				game_id, number, data.item_name(number),
			]
		)
	_r.check(
		Gen2WorldPack.field_effect(data, Gen2WorldPack.ITEM_COIN_CASE)
			== Gen2WorldPack.FIELD_EFFECT_NONE
			and Gen2WorldPack.field_use_kind(data, Gen2WorldPack.ITEM_COIN_CASE)
				== Gen2WorldPack.ITEMMENU_CURRENT,
		"%s: the COIN CASE is not ITEMMENU_CURRENT." % game_id
	)


## The three key items whose effect is a `farsjump` at a named map script, each
## driven on the map and cell its own routine insists on. The addresses come from
## the maps rather than from a pin, which is the whole point: `CardKeySlotScript`
## and `BasementDoorScript` are the faced cell's own background event, and
## `WateredWeirdTreeScript` is walked out of `SudowoodoScript`.
func _verify_key_item_effects(game_id: StringName, data: GameData) -> void:
	var crystal: bool = Gen2WorldState.is_crystal_profile(data)
	_verify_faced_script(
		game_id, data, RADIO_TOWER_3F, RADIO_TOWER_STAND, Gen2WorldSprite.FACING_UP,
		&"card_key", Gen2WorldAPI.CARD_KEY_SLOT_CELL
	)
	_verify_faced_script(
		game_id, data,
		GOLDENROD_UNDERGROUND_CRYSTAL if crystal else GOLDENROD_UNDERGROUND_GOLD_SILVER,
		GOLDENROD_UNDERGROUND_STAND, Gen2WorldSprite.FACING_UP,
		&"basement_key", Gen2WorldAPI.BASEMENT_DOOR_CELL
	)
	_verify_squirtbottle(game_id, data)


## One key item's request, both ways round: the faced cell answers with the
## background event's own script, and the cell beside it answers `.Oak`.
func _verify_faced_script(
	game_id: StringName,
	data: GameData,
	map: Vector2i,
	stand: Vector2i,
	facing: int,
	item: StringName,
	target: Vector2i
) -> void:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, map.x, map.y, stand, Gen2WorldState.new()
	)
	if not _r.check(world != null, "%s: map %s is missing." % [game_id, map]):
		return
	world.player_facing = facing
	if not _r.check(
		world.facing_cell() == target,
		"%s: %s stands facing %s, not %s." % [game_id, item, world.facing_cell(), target]
	):
		return
	var expected: int = 0
	for event: Variant in world.current_map.events.get("bg_events", []):
		var row: Dictionary = event
		if Vector2i(int(row.get("x", -1)), int(row.get("y", -1))) == target:
			expected = int(row.get("script", 0))
	var request: Dictionary = world.card_key_request() if item == &"card_key" \
		else world.basement_key_request()
	if not _r.check(
		bool(request.get("ok", false)) and int(request.get("script", 0)) == expected
			and expected > 0,
		"%s: %s answered %s, not the background event's script $%04X." % [
			game_id, item, request, expected,
		]
	):
		return
	## Both scripts open a text box, so a queued one that says nothing means the
	## address decoded but the runner could not fetch it.
	var events: Array = world.queue_item_script(request)
	_r.check(
		not events.is_empty()
			and StringName((events[0] as Dictionary).get("status", &"")) == &"waiting"
			and StringName(
				((events[0] as Dictionary).get("event", {}) as Dictionary).get("type", &"")
			) == &"text",
		"%s: %s queued a script that said nothing: %s." % [game_id, item, events]
	)
	print("%s: %s reaches $%02X:$%04X and opens with its text." % [
		game_id, item, int(request.get("bank", 0)), int(request.get("script", 0)),
	])

	# One cell to the side is the same map and not the faced tile, which is where
	# both routines answer FALSE and the pack says `.Oak`.
	world.player_facing = Gen2WorldSprite.FACING_LEFT
	var refused: Dictionary = world.card_key_request() if item == &"card_key" \
		else world.basement_key_request()
	_r.check(
		not bool(refused.get("ok", false)),
		"%s: %s answered off its own tile: %s." % [game_id, item, refused]
	)


## `.CheckCanUseSquirtbottle`, which never refuses: the tree in front answers
## with `WateredWeirdTreeScript` and anything else with the line the queued
## script says instead.
func _verify_squirtbottle(game_id: StringName, data: GameData) -> void:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, ROUTE_36.x, ROUTE_36.y, SUDOWOODO_STAND, Gen2WorldState.new()
	)
	if not _r.check(world != null, "%s: Route 36 is missing." % game_id):
		return
	world.player_facing = Gen2WorldSprite.FACING_UP
	var tree: Gen2WorldObject = world.object_at(SUDOWOODO_CELL)
	if not _r.check(
		tree != null and tree.is_sudowoodo(),
		"%s: Route 36 %s is not the weird tree." % [game_id, SUDOWOODO_CELL]
	):
		return
	var watered: Dictionary = world.squirtbottle_request()
	if not _r.check(
		StringName(watered.get("kind", &"")) == &"squirtbottle_watered"
			and int(watered.get("offset", 0)) == WATERED_TREE_OFFSET,
		"%s: the squirtbottle answered %s, not %d bytes into `.Fight`." % [
			game_id, watered, WATERED_TREE_OFFSET,
		]
	):
		return
	## The address is only half of it: an interior label has no pointer of its
	## own, so what proves the walk is that the runner reaches the tree's own
	## text from it. `opentext` and `writetext` are the label's first two
	## commands, so the first thing the queued script does is say them.
	var events: Array = world.queue_item_script(watered)
	_r.check(
		not events.is_empty()
			and StringName((events[0] as Dictionary).get("status", &"")) == &"waiting"
			and StringName(
				((events[0] as Dictionary).get("event", {}) as Dictionary).get("type", &"")
			) == &"text",
		"%s: the watered tree script did not open with its text: %s." % [game_id, events]
	)
	print("%s: squirtbottle reaches $%02X:$%04X + %d and opens with its text." % [
		game_id, int(watered.get("bank", 0)), int(watered.get("script", 0)),
		int(watered.get("offset", 0)),
	])

	# Facing away is the `.nope` branch, which is still an effect that succeeded.
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	var nothing: Dictionary = world.squirtbottle_request()
	_r.check(
		bool(nothing.get("ok", false))
			and StringName(nothing.get("kind", &"")) == &"squirtbottle_nothing",
		"%s: the squirtbottle away from the tree answered %s." % [game_id, nothing]
	)
