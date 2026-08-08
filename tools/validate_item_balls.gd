extends SceneTree

## Verifies `OBJECTTYPE_ITEMBALL` dispatch against freshly imported real caches,
## for both command profiles.
##
## Expected values come from the pinned pokecrystal and pokegold sources:
## `engine/overworld/events.asm`'s `ObjectEventTypeArray.itemball`,
## `engine/events/misc_scripts.asm`'s `FindItemInBallScript`, and the
## `itemball` macro in `macros/scripts/maps.asm`.
##
## The point of pinning it is that an item ball's script pointer is not a
## script. It addresses `db item, quantity`, and before this dispatch existed
## `interact()` handed those two bytes to the runner as opcodes. Ice Path 1F's
## HM07 is the one that matters most: nothing else in either game gives
## Waterfall.
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

var _failures: PackedStringArray = []


func _initialize() -> void:
	for game_id: StringName in GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_verify_hm07(data, game_id)
		_verify_route_44(data, game_id)
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
		print("PASS item balls: HM07 and Route 44's balls decode and are received.")
		quit(0)
		return
	for failure: String in _failures:
		printerr(failure)
	printerr("FAIL item balls: %d problems." % _failures.size())
	quit(1)
