extends SceneTree

## Verifies `OBJECTTYPE_ITEMBALL` and `BGEVENT_ITEM` dispatch against freshly
## imported real caches, for both command profiles.
##
## Expected values come from the pinned pokecrystal and pokegold sources:
## `engine/overworld/events.asm`'s `ObjectEventTypeArray.itemball` and
## `.itemifset`, `engine/events/misc_scripts.asm`'s `FindItemInBallScript`,
## `engine/events/hidden_item.asm`'s `HiddenItemScript`, and the `itemball` and
## `hiddenitem` macros in `macros/scripts/maps.asm`.
##
## The point of pinning both is that neither pointer is a script. A ball's
## addresses `db item, quantity` and a hidden item's `dwb event, item`, and
## before these dispatches existed `interact()` handed those bytes to the runner
## as opcodes. Two of them matter most: Ice Path 1F's HM07, since nothing else in
## either game gives Waterfall, and Cerulean Gym's MACHINE_PART, since nothing
## else opens the Power Plant and with it the Cascade Badge.
##
##   Godot --headless -s res://tools/validate_item_balls.gd

const GAME_IDS: Array[StringName] = [&"gold", &"silver", &"crystal"]

## data/maps/maps.asm group/number pairs. Crystal's own extra maps push both
## dungeon floors down the Dungeons group.
const ICE_PATH_1F: Dictionary = {
	&"gold": [3, 53],
	&"silver": [3, 53],
	&"crystal": [3, 61],
}
const ROUTE_44: Array = [2, 6]

## constants/item_constants.asm's `add_hm` list, whose comment column is hex.
const ITEM_HM_WATERFALL: int = 0xF9

## The balls this drives, by map and cell, with the item each `itemball` names.
## Ice Path 1F's HM07 is on (31,7) in both games (`maps/IcePath1F.asm`), which is
## the only cell on this list that has to match: nothing else gives Waterfall.
## Route 44 is profile split (`maps/Route44.asm`). Crystal ships three balls and
## Gold and Silver two, and the Ultra Ball moved between them.
const HM07_CELL: Vector2i = Vector2i(31, 7)
const ROUTE_44_BALLS: Dictionary = {
	&"gold": [
		{"cell": Vector2i(30, 8), "item": 0x28},   # MAX_REVIVE
		{"cell": Vector2i(43, 2), "item": 0x02},   # ULTRA_BALL
	],
	&"silver": [
		{"cell": Vector2i(30, 8), "item": 0x28},
		{"cell": Vector2i(43, 2), "item": 0x02},
	],
	&"crystal": [
		{"cell": Vector2i(30, 8), "item": 0x28},
		{"cell": Vector2i(45, 4), "item": 0x02},
		{"cell": Vector2i(14, 9), "item": 0x2B},   # MAX_REPEL
	],
}

## The two hidden items this drives. Both map ids and both flag numbers are the
## same in either pin. Route 45's PP Up starts pickable; Cerulean Gym's machine
## part starts behind a flag `InitializeEventsScript` sets
## (`engine/events/std_scripts.asm`), which the Power Plant manager clears, so it
## is the one that shows the gate working in both directions.
const ROUTE_45: Array = [5, 8]
const CERULEAN_GYM: Array = [7, 6]
## Both records sit on water, which is the point of each: the machine part is
## the one the Route 24 grunt says he dropped in the gym pool, faced from the
## bank above it, and Route 45's PP Up is out in the river with no land cell
## adjacent at all, so it is reached surfing. `surfing` says which.
const HIDDEN_ITEMS: Array[Dictionary] = [
	{
		"map": ROUTE_45, "cell": Vector2i(13, 80), "from": Vector2i(13, 81),
		"facing": Gen2WorldSprite.FACING_UP, "surfing": true,
		"item": 0x3E, "flag": 175,   # PP_UP, EVENT_ROUTE_45_HIDDEN_PP_UP
	},
	{
		"map": CERULEAN_GYM, "cell": Vector2i(3, 8), "from": Vector2i(3, 7),
		"facing": Gen2WorldSprite.FACING_DOWN, "surfing": false,
		"item": 0x80, "flag": 251,   # MACHINE_PART, EVENT_FOUND_MACHINE_PART_IN_CERULEAN_GYM
	},
]

var _failures: PackedStringArray = []


func _initialize() -> void:
	for game_id: StringName in GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_verify_hm07(data, game_id)
		_verify_route_44(data, game_id)
		_verify_hidden_items(data, game_id)
	_finish()


## The one that unblocks the route: picking HM07 up puts Waterfall in the bag,
## sets the ball's own event flag and takes the object off the map.
func _verify_hm07(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(data, ICE_PATH_1F[game_id], HM07_CELL + Vector2i.UP)
	if world == null:
		_fail("%s: Ice Path 1F is missing." % game_id)
		return
	var ball: Gen2WorldObject = world.object_at(HM07_CELL)
	if ball == null:
		_fail("%s: Ice Path 1F has no object on %s." % [game_id, HM07_CELL])
		return
	if not _check(
		ball.object_type == Gen2WorldObject.OBJECTTYPE_ITEMBALL,
		"%s: Ice Path 1F's %s is not an item ball." % [game_id, HM07_CELL]
	):
		return

	world.player_facing = Gen2WorldSprite.FACING_DOWN
	var results: Array = world.interact()
	if not _check(
		results.size() == 1
			and StringName(results[0].get("source", {}).get("kind", &"")) == &"item_ball",
		"%s: Ice Path 1F's HM07 did not dispatch as an item ball." % game_id
	):
		return
	var request: Dictionary = results[0].get("source", {})
	_check(
		int(request.get("item", 0)) == ITEM_HM_WATERFALL
			and int(request.get("quantity", 0)) == 1,
		"%s: Ice Path 1F's ball carries item $%02x x%d, not HM07 x1." % [
			game_id, int(request.get("item", 0)), int(request.get("quantity", 0)),
		]
	)
	_check(
		StringName(results[0].get("status", &"")) == &"waiting",
		"%s: the HM07 ball did not pause on its found-item text." % game_id
	)

	var finished: Array = world.run_event_queue(true)
	_check(
		not finished.is_empty()
			and StringName(finished[0].get("status", &"")) == &"complete",
		"%s: the HM07 ball's script did not finish." % game_id
	)
	_check(
		int(world.state.items().get(ITEM_HM_WATERFALL, 0)) == 1,
		"%s: HM07 is not in the bag after the pickup." % game_id
	)
	# `disappear LAST_TALKED` writes the ball's own event flag, so a map reload
	# keeps it gone the way every other disappeared object does.
	_check(
		ball.event_flag <= 0 or world.event_flag_active(ball.event_flag),
		"%s: the HM07 ball's event flag was not set." % game_id
	)
	_check(
		not ball.active and world.object_at(HM07_CELL) == null,
		"%s: the HM07 ball is still on the map after the pickup." % game_id
	)


## More on one map, to show the decode is the macro's two bytes and not HM07
## alone.
func _verify_route_44(data: GameData, game_id: StringName) -> void:
	for entry: Dictionary in ROUTE_44_BALLS[game_id]:
		var cell: Vector2i = entry["cell"]
		var world: Gen2WorldAPI = _open(data, ROUTE_44, cell + Vector2i.UP)
		if world == null:
			_fail("%s: Route 44 is missing." % game_id)
			return
		var ball: Gen2WorldObject = world.object_at(cell)
		if ball == null or ball.object_type != Gen2WorldObject.OBJECTTYPE_ITEMBALL:
			_fail("%s: Route 44 has no item ball on %s." % [game_id, cell])
			continue
		world.player_facing = Gen2WorldSprite.FACING_DOWN
		var results: Array = world.interact()
		var request: Dictionary = results[0].get("source", {}) if not results.is_empty() else {}
		_check(
			int(request.get("item", 0)) == int(entry["item"]),
			"%s: Route 44's ball on %s carries $%02x, not the pinned $%02x." % [
				game_id, cell, int(request.get("item", 0)), int(entry["item"]),
			]
		)


## The BGEVENT_ITEM half. `.itemifset` reads only while the record's flag is
## clear, and `callasm SetMemEvent` is what sets it, so one pickup is all a
## hidden item ever gives.
func _verify_hidden_items(data: GameData, game_id: StringName) -> void:
	for entry: Dictionary in HIDDEN_ITEMS:
		var cell: Vector2i = entry["cell"]
		var item: int = int(entry["item"])
		var flag: int = int(entry["flag"])
		var world: Gen2WorldAPI = _open(data, entry["map"], entry["from"])
		if world == null:
			_fail("%s: map %s is missing." % [game_id, entry["map"]])
			continue
		world.player_facing = int(entry["facing"])
		if bool(entry["surfing"]):
			world.movement_mode = Gen2WorldAPI.MOVEMENT_SURF
		_check(
			world.can_walk_to(entry["from"]),
			"%s: %s is not a cell the hidden item on %s can be faced from%s." % [
				game_id, entry["from"], cell, " while surfing" if entry["surfing"] else "",
			]
		)

		# Set, the record is closed; this is the state the machine part ships in.
		world.set_event_flag(flag)
		_check(
			world.interact().is_empty(),
			"%s: the hidden item on %s answered with its flag %d set." % [game_id, cell, flag]
		)
		world.clear_event_flag(flag)

		var results: Array = world.interact()
		if not _check(
			results.size() == 1
				and StringName(results[0].get("source", {}).get("kind", &"")) == &"hidden_item",
			"%s: the hidden item on %s did not dispatch." % [game_id, cell]
		):
			continue
		var request: Dictionary = results[0].get("source", {})
		_check(
			int(request.get("item", 0)) == item and int(request.get("flag", -1)) == flag,
			"%s: %s carries item $%02x flag %d, not the pinned $%02x and %d." % [
				game_id, cell, int(request.get("item", 0)), int(request.get("flag", -1)),
				item, flag,
			]
		)
		_check(
			StringName(results[0].get("status", &"")) == &"waiting",
			"%s: the hidden item on %s did not pause on its found-item text." % [game_id, cell]
		)
		var finished: Array = world.run_event_queue(true)
		_check(
			not finished.is_empty()
				and StringName(finished[0].get("status", &"")) == &"complete",
			"%s: the hidden item on %s did not finish." % [game_id, cell]
		)
		_check(
			int(world.state.items().get(item, 0)) == 1 and world.event_flag_active(flag),
			"%s: %s did not reach the bag, or its flag was not written." % [game_id, cell]
		)
		# And the flag it just wrote closes it, so a second A press gives nothing.
		_check(
			world.interact().is_empty() and int(world.state.items().get(item, 0)) == 1,
			"%s: the hidden item on %s can be picked up twice." % [game_id, cell]
		)


func _open(data: GameData, id: Array, cell: Vector2i) -> Gen2WorldAPI:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, id[0], id[1], cell, Gen2WorldState.new())
	if world == null:
		return null
	var _entry: Array = world.dispatch_map_entry()
	for _step: int in 8:
		if world.pending_script_input().is_empty():
			break
		world.run_event_queue(true)
	return world


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS item balls: HM07, Route 44's balls and both hidden items decode and are received.")
		quit(0)
		return
	for failure: String in _failures:
		printerr(failure)
	printerr("FAIL item balls: %d problems." % _failures.size())
	quit(1)
