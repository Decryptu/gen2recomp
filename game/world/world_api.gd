class_name Gen2WorldAPI
extends RefCounted

## Scene-free runtime access to one imported Generation 2 map.
##
## The API works in walk cells: every cell is a 2x2 group of 8x8 graphics
## tiles. It owns player position, camera framing and live object state, while
## event flags are supplied through a separate scene-free world state.

const VIEW_CELLS: Vector2i = Vector2i(10, 9)
const VIEW_TILES: Vector2i = VIEW_CELLS * RomLayout.MAP_BLOCK_CELL_WIDTH
const CELL_PIXELS: int = Gen2Tiles.TILE_WIDTH * RomLayout.MAP_BLOCK_CELL_WIDTH

var data: GameData = null
var state: Gen2WorldState = null
var current_map: Gen2WorldMap = null
var current_tileset: Gen2WorldTileset = null
var player_cell: Vector2i = Vector2i.ZERO
var player_facing: int = Gen2WorldSprite.FACING_DOWN
var objects: Array = []
var object_hour: int = 6
var object_time_of_day: int = Gen2WorldPalette.TIME_MORNING
var _script_queue: Array = []
var _active_script: Gen2WorldScriptRunner = null
var _object_visibility_overrides: Dictionary = {}
var _object_position_overrides: Dictionary = {}
var _object_facing_overrides: Dictionary = {}
var _object_followers: Dictionary = {}


## Opens one map through the public cartridge-content API.
## Returns null when the cache does not contain the requested map or tileset.
static func open(
	game_data: GameData,
	group: int,
	number: int,
	start_cell: Vector2i,
	world_state: Gen2WorldState = null,
) -> Gen2WorldAPI:
	if game_data == null:
		return null
	var map: Gen2WorldMap = game_data.world_map(group, number)
	if map == null:
		return null
	var tileset: Gen2WorldTileset = game_data.world_tileset(map.tileset)
	if tileset == null:
		return null
	return Gen2WorldAPI.new(game_data, map, tileset, start_cell, world_state)


func _init(
	game_data: GameData,
	map: Gen2WorldMap,
	tileset: Gen2WorldTileset,
	start_cell: Vector2i = Vector2i.ZERO,
	world_state: Gen2WorldState = null,
) -> void:
	data = game_data
	state = world_state if world_state != null else Gen2WorldState.new()
	state.changed.connect(_on_world_state_changed)
	current_map = map
	current_tileset = tileset
	player_cell = _clamp_cell(start_cell)
	_load_objects()


func map_id() -> Vector2i:
	return Vector2i(current_map.group, current_map.number) if current_map != null else Vector2i(-1, -1)


func map_size_cells() -> Vector2i:
	if current_map == null:
		return Vector2i.ZERO
	return Vector2i(current_map.collision_width, current_map.collision_height)


func map_size_pixels() -> Vector2i:
	return map_size_cells() * CELL_PIXELS


func visible_origin_cell() -> Vector2i:
	if current_map == null:
		return Vector2i.ZERO
	var size: Vector2i = map_size_cells()
	var max_x: int = maxi(0, size.x - VIEW_CELLS.x)
	var max_y: int = maxi(0, size.y - VIEW_CELLS.y)
	return Vector2i(
		clampi(player_cell.x - VIEW_CELLS.x / 2, 0, max_x),
		clampi(player_cell.y - VIEW_CELLS.y / 2, 0, max_y)
	)


func player_view_cell() -> Vector2i:
	return player_cell - visible_origin_cell()


func player_pixel_position() -> Vector2i:
	return player_view_cell() * CELL_PIXELS


func player_sprite() -> Gen2WorldSprite:
	return data.overworld_sprite(1) if data != null else null


func set_object_time(hour: int, time_of_day: int) -> void:
	object_hour = clampi(hour, 0, 23)
	object_time_of_day = clampi(time_of_day, 0, 3)
	for object: Gen2WorldObject in objects:
		object.active = object.visible_with_state(object_hour, object_time_of_day, state)
		var key: String = _object_key(current_map.group, current_map.number, object.index)
		if _object_visibility_overrides.has(key):
			object.active = bool(_object_visibility_overrides[key])


func set_event_flag(flag: int, active: bool = true) -> void:
	state.set_event_flag(flag, active)


func clear_event_flag(flag: int) -> void:
	state.clear_event_flag(flag)


func event_flag_active(flag: int) -> bool:
	return state.is_event_flag_active(flag)


func visible_objects() -> Array:
	var out: Array = []
	for object: Gen2WorldObject in objects:
		if object.active and object.sprite != null:
			out.append(object)
	return out


func object_at(cell: Vector2i, visible_only: bool = true) -> Gen2WorldObject:
	for object: Gen2WorldObject in objects:
		if object.cell != cell or (visible_only and not object.active):
			continue
		if object.sprite != null:
			return object
	return null


## The expanded graphics tile at a map-space tile coordinate, or -1 outside
## the map. A map block contains sixteen tiles in row-major order.
func tile_index_at(tile_x: int, tile_y: int) -> int:
	if current_map == null or current_tileset == null:
		return -1
	var map_tile_width: int = current_map.width_blocks * RomLayout.MAP_BLOCK_TILE_WIDTH

	if tile_x < 0 or tile_y < 0 or tile_x >= map_tile_width \
		or tile_y >= current_map.height_blocks * RomLayout.MAP_BLOCK_TILE_WIDTH:
		return -1

	var block: int = current_map.block_at(
		tile_x / RomLayout.MAP_BLOCK_TILE_WIDTH,
		tile_y / RomLayout.MAP_BLOCK_TILE_WIDTH,
	)
	var local_tile: int = (tile_y & 3) * RomLayout.MAP_BLOCK_TILE_WIDTH + (tile_x & 3)
	return current_tileset.tile_index(block, local_tile)


## Returns the visible 20x18 graphics-tile page in row-major order. -1 marks
## the padding around maps smaller than the hardware viewport.
func visible_tile_indices() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(VIEW_TILES.x * VIEW_TILES.y)
	for index: int in out.size():
		out[index] = -1

	var origin: Vector2i = visible_origin_cell() * RomLayout.MAP_BLOCK_CELL_WIDTH
	for y: int in VIEW_TILES.y:
		for x: int in VIEW_TILES.x:
			var tile: int = tile_index_at(origin.x + x, origin.y + y)
			out[y * VIEW_TILES.x + x] = tile
	return out


func collision_code_at(cell: Vector2i) -> int:
	if current_map == null:
		return -1
	return current_map.collision_at(cell.x, cell.y)


func collision_permission_at(cell: Vector2i) -> int:
	return Gen2WorldCollision.permission_for(collision_code_at(cell))


## Returns the raw warp record at a cell, or an empty Dictionary when the
## player is not standing on one. Warp destinations are one-based in the
## cartridge data, matching the map macro that writes them.
func warp_at(cell: Vector2i = player_cell) -> Dictionary:
	if current_map == null:
		return {}
	for event: Dictionary in current_map.events.get("warps", []):
		if int(event.get("x", -1)) == cell.x and int(event.get("y", -1)) == cell.y:
			return event.duplicate(true)
	return {}


## Returns all decoded event records at a cell in cartridge checking order.
## Script pointers remain data; this method does not interpret them.
func events_at(cell: Vector2i = player_cell) -> Array:
	if current_map == null:
		return []
	var out: Array = []
	for source: String in ["warps", "coord_events", "bg_events", "objects"]:
		var rows: Array = current_map.events.get(source, [])
		for index: int in rows.size():
			var raw: Dictionary = rows[index]
			if int(raw.get("x", -1)) != cell.x or int(raw.get("y", -1)) != cell.y:
				continue
			var event: Dictionary = raw.duplicate(true)
			event["kind"] = StringName(source)
			if source == "objects":
				event["object_index"] = index
			out.append(event)
	return out


## Public event boundary for the screen and future systems. By default it
## reports active decoded records without interpreting cartridge scripts. The
## optional execution flag keeps the old raw-data call stable while exposing
## the queued interpreter to callers that are ready for it.
func dispatch_events(cell: Vector2i = player_cell, execute_scripts: bool = false) -> Array:
	var events: Array = _active_events_at(cell)
	if execute_scripts:
		if _active_script == null and _script_queue.is_empty():
			_enqueue_script_events(events)
		return run_event_queue(false)
	return events


## Queues the active scripted records at a cell in cartridge source order and
## advances until the queue reaches text/button input or is empty.
func dispatch_script_events(cell: Vector2i = player_cell) -> Array:
	if _active_script == null and _script_queue.is_empty():
		_enqueue_script_events(_active_events_at(cell))
	return run_event_queue(false)


## Queues the first visible trainer who can see the player, matching the
## cartridge's trainer scan order. A trainer sees only along its facing axis,
## and a nonzero event flag prevents the encounter from being queued.
func dispatch_sight_events() -> Array:
	if _active_script != null or not _script_queue.is_empty():
		return run_event_queue(false)
	var request: Dictionary = _find_sight_request()
	if request.is_empty():
		return []
	_script_queue.append(request)
	return run_event_queue(false)


func script_input_waiting() -> bool:
	return _active_script != null and _active_script.is_waiting()


func pending_runtime_request() -> Dictionary:
	return _active_script.pending_runtime_request() if _active_script != null else {}


## Starts one callback type from the current map's callback table. A type of -1
## runs all callbacks in their stored order.
func dispatch_callbacks(callback_type: int = -1) -> Array:
	if current_map == null:
		return []
	if _active_script == null and _script_queue.is_empty():
		_queue_map_callbacks(callback_type)
	return run_event_queue(false)


## Acknowledge the current text/button pause and continue the first queued
## script. Completed results retain the source event so a screen can react to
## them without reaching into the runner.
func run_event_queue(acknowledge: bool = false) -> Array:
	var results: Array = []
	var accept: bool = acknowledge
	while true:
		if _active_script == null:
			if _script_queue.is_empty():
				break
			var request: Dictionary = _script_queue.pop_front()
			_active_script = Gen2WorldScriptRunner.begin(
				data, state, request, Callable(self, "_validate_script_warp")
			)
		var result: Dictionary = _active_script.advance(accept)
		accept = false
		if StringName(result.get("status", &"")) == &"waiting":
			results.append(result)
			break
		results.append(_finish_script_result(result))
		_active_script = null
	return results


## Completes the currently pending host-owned request and resumes the same
## scene-free script invocation. The world API owns the runner lifecycle, so a
## screen never needs to reach into the runner or replace its state.
func complete_runtime_request(result: Dictionary) -> Array:
	if _active_script == null:
		return []
	var results: Array = []
	var advanced: Dictionary = _active_script.complete_runtime_request(result)
	if StringName(advanced.get("status", &"")) == &"waiting":
		results.append(advanced)
		return results
	if bool(advanced.get("ok", false)):
		results.append(_finish_script_result(advanced))
	else:
		results.append(advanced)
	_active_script = null
	while _active_script == null and not _script_queue.is_empty():
		var request: Dictionary = _script_queue.pop_front()
		_active_script = Gen2WorldScriptRunner.begin(
			data, state, request, Callable(self, "_validate_script_warp")
		)
		var next: Dictionary = _active_script.advance()
		if StringName(next.get("status", &"")) == &"waiting":
			results.append(next)
			break
		results.append(_finish_script_result(next) if bool(next.get("ok", false)) else next)
		_active_script = null
	return results


func _active_events_at(cell: Vector2i) -> Array:
	var out: Array = []
	for event: Dictionary in events_at(cell):
		if event.get("kind", &"") == &"objects":
			var index: int = int(event.get("object_index", -1))
			if index >= 0 and index < objects.size() \
				and not (objects[index] as Gen2WorldObject).active:
				continue
		out.append(event)
	return out


func _enqueue_script_events(events: Array) -> void:
	var bank: int = int(current_map.events.get("bank", 0)) if current_map != null else 0
	for event: Dictionary in events:
		if event.get("kind", &"") == &"warps" or not event.has("script"):
			continue
		_enqueue_script({
			"kind": event.get("kind", &""),
			"map_group": current_map.group,
			"map_number": current_map.number,
			"cell": Vector2i(int(event.get("x", 0)), int(event.get("y", 0))),
			"bank": bank,
			"script": int(event.get("script", 0)),
			"event": event.duplicate(true),
		})


func _enqueue_script(request: Dictionary) -> void:
	if int(request.get("script", 0)) <= 0:
		return
	_script_queue.append(request)


func _queue_map_callbacks(callback_type: int) -> void:
	if current_map == null:
		return
	var bank: int = int(current_map.scripts.get("bank", 0))
	for callback: Dictionary in current_map.scripts.get("callbacks", []):
		if callback_type >= 0 and int(callback.get("type", -1)) != callback_type:
			continue
		_enqueue_script({
			"kind": &"callback",
			"callback_type": int(callback.get("type", -1)),
			"map_group": current_map.group,
			"map_number": current_map.number,
			"bank": bank,
			"script": int(callback.get("script", 0)),
		})


func _apply_script_object_events(raw_events: Variant) -> Array:
	var generated: Array = []
	if not raw_events is Array:
		return generated
	var reload_objects: bool = false
	for raw_event: Variant in raw_events as Array:
		if not raw_event is Dictionary:
			continue
		var event: Dictionary = raw_event as Dictionary
		var event_type: StringName = StringName(event.get("type", &""))
		if event_type == &"player_movement_requested":
			generated.append_array(_apply_player_movement(event))
			continue
		if event_type == &"object_movement_requested":
			generated.append_array(_apply_object_movement(event))
			reload_objects = true
			continue
		if event_type == &"object_follow":
			var follow_key: String = _object_key(
				int(event.get("map_group", -1)), int(event.get("map_number", -1)),
				int(event.get("object_index", -1))
			)
			_object_followers[follow_key] = {
				"target_index": int(event.get("target_index", -1)),
				"exact": bool(event.get("exact", true)),
			}
			continue
		if event_type == &"object_stop_follow":
			_object_followers.clear()
			continue
		if event_type not in [
			&"object_visibility", &"object_position", &"object_facing",
			&"object_face_player", &"object_face_object",
		]:
			continue
		var map_group: int = int(event.get("map_group", -1))
		var map_number: int = int(event.get("map_number", -1))
		var object_index: int = int(event.get("object_index", -1))
		if object_index < 0:
			continue
		var key: String = _object_key(map_group, map_number, object_index)
		match event_type:
			&"object_visibility":
				_object_visibility_overrides[key] = bool(event.get("active", false))
				reload_objects = true
			&"object_position":
				var cell: Variant = event.get("cell", Vector2i.ZERO)
				if cell is Vector2i:
					_object_position_overrides[key] = cell
					reload_objects = true
			&"object_facing":
				_object_facing_overrides[key] = clampi(
					int(event.get("facing", Gen2WorldSprite.FACING_DOWN)),
					Gen2WorldSprite.FACING_DOWN, Gen2WorldSprite.FACING_RIGHT
				)
				reload_objects = true
			&"object_face_player":
				if map_group == current_map.group and map_number == current_map.number \
					and object_index < objects.size():
					var object: Gen2WorldObject = objects[object_index]
					var facing: int = _facing_toward(object.cell, player_cell)
					_object_facing_overrides[key] = facing
			&"object_face_object":
				var target_index: int = int(event.get("target_index", -1))
				if map_group == current_map.group and map_number == current_map.number \
					and object_index < objects.size() and target_index >= 0 \
					and target_index < objects.size():
					_object_facing_overrides[key] = _facing_toward(
						(objects[object_index] as Gen2WorldObject).cell,
						(objects[target_index] as Gen2WorldObject).cell
					)
				reload_objects = true
	if reload_objects and current_map != null:
		_load_objects()
	return generated


func _apply_object_movement(event: Dictionary) -> Array:
	var generated: Array = []
	var map_group: int = int(event.get("map_group", -1))
	var map_number: int = int(event.get("map_number", -1))
	var object_index: int = int(event.get("object_index", -1))
	if current_map == null or map_group != current_map.group or map_number != current_map.number \
		or object_index < 0 or object_index >= objects.size():
		generated.append({"type": &"movement_failed", "reason": &"invalid_object"})
		return generated
	var raw: PackedByteArray = data.world_movement(
		int(event.get("bank", 0)), int(event.get("address", 0))
	)
	var decoded: Dictionary = Gen2WorldMovement.decode(raw)
	if not bool(decoded.get("ok", false)):
		generated.append({
			"type": &"movement_failed", "reason": decoded.get("reason", &"invalid_movement"),
			"object_index": object_index,
		})
		return generated
	var object: Gen2WorldObject = objects[object_index]
	for command: Dictionary in decoded.get("commands", []):
		var kind: StringName = StringName(command.get("kind", &""))
		if kind in [&"turn_head", &"turn_in", &"turn_waterfall"]:
			object.apply_direction(_movement_direction(int(command.get("direction", 0))))
			continue
		if kind == &"turn_away":
			object.apply_direction(-_movement_direction(int(command.get("direction", 0))))
			continue
		if kind in [
			&"turn_step", &"slow_step", &"step", &"big_step", &"slow_slide_step",
			&"slide_step", &"fast_slide_step", &"slow_jump_step", &"jump_step",
			&"fast_jump_step",
		]:
			var direction: Vector2i = _movement_direction(int(command.get("direction", 0)))
			object.apply_direction(direction)
			var destination: Vector2i = object.cell + direction
			if can_object_walk_to(destination, object):
				object.cell = destination
			else:
				generated.append({
					"type": &"movement_blocked", "object_index": object_index,
					"cell": destination,
				})
			continue
		match kind:
			&"show_object":
				_object_visibility_overrides[_object_key(map_group, map_number, object_index)] = true
			&"hide_object", &"remove_object":
				_object_visibility_overrides[_object_key(map_group, map_number, object_index)] = false
			&"step_stop":
				break
			&"step_sleep", &"set_sliding", &"remove_sliding", &"fix_facing", &"remove_fixed_facing":
				pass
			_:
				generated.append({
					"type": &"movement_command_requested", "object_index": object_index,
					"command": command.duplicate(true),
				})
	var key: String = _object_key(map_group, map_number, object_index)
	_object_position_overrides[key] = object.cell
	_object_facing_overrides[key] = object.facing
	return generated


func _apply_player_movement(event: Dictionary) -> Array:
	var generated: Array = []
	var map_group: int = int(event.get("map_group", -1))
	var map_number: int = int(event.get("map_number", -1))
	if current_map == null or map_group != current_map.group or map_number != current_map.number:
		return [{"type": &"movement_failed", "reason": &"invalid_map"}]
	var raw: PackedByteArray = data.world_movement(
		int(event.get("bank", 0)), int(event.get("address", 0))
	)
	var decoded: Dictionary = Gen2WorldMovement.decode(raw)
	if not bool(decoded.get("ok", false)):
		return [{
			"type": &"movement_failed", "reason": decoded.get("reason", &"invalid_movement"),
			"player": true,
		}]
	for command: Dictionary in decoded.get("commands", []):
		var kind: StringName = StringName(command.get("kind", &""))
		if kind in [&"turn_head", &"turn_in", &"turn_waterfall"]:
			player_facing = _facing_for_direction(
				_movement_direction(int(command.get("direction", 0)))
			)
			continue
		if kind == &"turn_away":
			var away: Vector2i = -_movement_direction(int(command.get("direction", 0)))
			player_facing = _facing_for_direction(away)
			continue
		if kind in [
			&"turn_step", &"slow_step", &"step", &"big_step", &"slow_slide_step",
			&"slide_step", &"fast_slide_step", &"slow_jump_step", &"jump_step",
			&"fast_jump_step",
		]:
			var direction: Vector2i = _movement_direction(int(command.get("direction", 0)))
			player_facing = _facing_for_direction(direction)
			var destination: Vector2i = player_cell + direction
			if can_walk_to(destination):
				player_cell = destination
			else:
				generated.append({
					"type": &"movement_blocked", "player": true, "cell": destination,
				})
			continue
		if kind in [&"step_end", &"step_stop"]:
			break
		if kind in [
			&"step_sleep", &"step_wait_end", &"set_sliding", &"remove_sliding",
			&"fix_facing", &"remove_fixed_facing",
		]:
			continue
		generated.append({
			"type": &"movement_command_requested", "player": true,
			"command": command.duplicate(true),
		})
	return generated


func _movement_direction(direction: int) -> Vector2i:
	match direction & 3:
		0:
			return Vector2i.DOWN
		1:
			return Vector2i.UP
		2:
			return Vector2i.LEFT
		3:
			return Vector2i.RIGHT
	return Vector2i.ZERO


func _object_key(map_group: int, map_number: int, object_index: int) -> String:
	return "%d:%d:%d" % [map_group, map_number, object_index]


func _facing_toward(from: Vector2i, to: Vector2i) -> int:
	var delta: Vector2i = to - from
	if abs(delta.x) > abs(delta.y):
		return Gen2WorldSprite.FACING_RIGHT if delta.x > 0 else Gen2WorldSprite.FACING_LEFT
	if delta.y != 0:
		return Gen2WorldSprite.FACING_DOWN if delta.y > 0 else Gen2WorldSprite.FACING_UP
	return Gen2WorldSprite.FACING_DOWN


func _validate_script_warp(map_group: int, map_number: int, cell: Vector2i) -> Dictionary:
	var target_map: Gen2WorldMap = data.world_map(map_group, map_number) if data != null else null
	if target_map == null:
		return {"ok": false, "reason": &"missing_map"}
	var target_tileset: Gen2WorldTileset = data.world_tileset(target_map.tileset) if data != null else null
	if target_tileset == null:
		return {"ok": false, "reason": &"missing_tileset"}
	if cell.x < 0 or cell.y < 0 or cell.x >= target_map.collision_width \
		or cell.y >= target_map.collision_height:
		return {"ok": false, "reason": &"invalid_target_cell"}
	return {"ok": true}


func _finish_script_result(result: Dictionary) -> Dictionary:
	if not bool(result.get("ok", false)):
		return result
	var generated_events: Array = _apply_script_object_events(result.get("events", []))
	for generated: Dictionary in generated_events:
		result["events"].append(generated)
	var warp: Variant = result.get("warp", {})
	if warp is Dictionary and not (warp as Dictionary).is_empty():
		var transition: Dictionary = _apply_script_warp(warp as Dictionary)
		if not bool(transition.get("ok", false)):
			result["ok"] = false
			result["status"] = &"failed"
			result["reason"] = transition.get("reason", &"warp_failed")
			return result
		result["events"].append({"type": &"warp", "transition": transition})
	return result


func _apply_script_warp(request: Dictionary) -> Dictionary:
	var map_group: int = int(request.get("map_group", -1))
	var map_number: int = int(request.get("map_number", -1))
	var cell := Vector2i(int(request.get("x", -1)), int(request.get("y", -1)))
	var validation: Dictionary = _validate_script_warp(map_group, map_number, cell)
	if not bool(validation.get("ok", false)):
		return validation
	var target_map: Gen2WorldMap = data.world_map(map_group, map_number)
	var target_tileset: Gen2WorldTileset = data.world_tileset(target_map.tileset)
	var from_map: Vector2i = map_id()
	var from_cell: Vector2i = player_cell
	_apply_map(target_map, target_tileset, cell)
	return {
		"ok": true,
		"kind": &"warp",
		"from_map": from_map,
		"from_cell": from_cell,
		"to_map": map_id(),
		"to_cell": player_cell,
		"destination": request.duplicate(true),
	}


## Resolves and applies an ordinary warp at the current cell. The destination
## field selects a one-based warp in the destination map, as in the original
## map macro. An invalid target leaves this API unchanged and returns an error
## record instead of silently placing the player on another map.
func try_warp(cell: Vector2i = player_cell) -> Dictionary:
	var source_warp: Dictionary = warp_at(cell)
	if source_warp.is_empty():
		return {}
	var target_group: int = int(source_warp.get("map_group", -1))
	var target_number: int = int(source_warp.get("map_number", -1))
	var target_map: Gen2WorldMap = data.world_map(target_group, target_number) if data != null else null
	if target_map == null:
		return {
			"ok": false,
			"kind": &"warp",
			"reason": &"missing_map",
			"from_map": map_id(),
			"from_cell": cell,
		}

	var destination_index: int = int(source_warp.get("destination", 0)) - 1
	var target_warps: Array = target_map.events.get("warps", [])
	if destination_index < 0 or destination_index >= target_warps.size():
		return {
			"ok": false,
			"kind": &"warp",
			"reason": &"missing_destination",
			"from_map": map_id(),
			"from_cell": cell,
		}

	var target_tileset: Gen2WorldTileset = data.world_tileset(target_map.tileset) if data != null else null
	if target_tileset == null:
		return {
			"ok": false,
			"kind": &"warp",
			"reason": &"missing_tileset",
			"from_map": map_id(),
			"from_cell": cell,
		}

	var target_warp: Dictionary = (target_warps[destination_index] as Dictionary).duplicate(true)
	var from_map: Vector2i = map_id()
	var from_cell: Vector2i = cell
	_apply_map(target_map, target_tileset, Vector2i(int(target_warp["x"]), int(target_warp["y"])))
	return {
		"ok": true,
		"kind": &"warp",
		"from_map": from_map,
		"from_cell": from_cell,
		"to_map": map_id(),
		"to_cell": player_cell,
		"source": source_warp,
		"destination": target_warp,
	}


## Resolves the source connection for a cardinal step beyond the current map.
## The stored offsets are the signed cell offsets generated by the cartridge's
## connection macro. No map mutation occurs when the target is invalid.
func try_connection(direction: Vector2i) -> Dictionary:
	var direction_name: String = _direction_name(direction)
	if direction_name.is_empty() or current_map == null or data == null:
		return {}
	if not _at_connection_edge(direction_name):
		return {
			"ok": false,
			"kind": &"connection",
			"reason": &"not_at_edge",
			"from_map": map_id(),
			"from_cell": player_cell,
			"direction": direction_name,
		}
	var source_connection: Dictionary = {}
	for connection: Dictionary in current_map.connections:
		if String(connection.get("direction", "")) == direction_name:
			source_connection = connection.duplicate(true)
			break
	if source_connection.is_empty():
		return {}

	var target_group: int = int(source_connection.get("map_group", -1))
	var target_number: int = int(source_connection.get("map_number", -1))
	var target_map: Gen2WorldMap = data.world_map(target_group, target_number)
	if target_map == null:
		return {
			"ok": false,
			"kind": &"connection",
			"reason": &"missing_map",
			"from_map": map_id(),
			"from_cell": player_cell,
			"direction": direction_name,
		}
	var target_tileset: Gen2WorldTileset = data.world_tileset(target_map.tileset)
	if target_tileset == null:
		return {
			"ok": false,
			"kind": &"connection",
			"reason": &"missing_tileset",
			"from_map": map_id(),
			"from_cell": player_cell,
			"direction": direction_name,
		}

	var target_cell: Vector2i
	match direction_name:
		"north":
			target_cell = Vector2i(
				player_cell.x + int(source_connection.get("x_offset", 0)),
				target_map.collision_height - 1,
			)
		"south":
			target_cell = Vector2i(
				player_cell.x + int(source_connection.get("x_offset", 0)),
				0,
			)
		"west":
			target_cell = Vector2i(
				target_map.collision_width - 1,
				player_cell.y + int(source_connection.get("y_offset", 0)),
			)
		"east":
			target_cell = Vector2i(
				0,
				player_cell.y + int(source_connection.get("y_offset", 0)),
			)
		_:
			return {}
	if target_cell.x < 0 or target_cell.y < 0 \
		or target_cell.x >= target_map.collision_width \
		or target_cell.y >= target_map.collision_height:
		return {
			"ok": false,
			"kind": &"connection",
			"reason": &"invalid_target_cell",
			"from_map": map_id(),
			"from_cell": player_cell,
			"direction": direction_name,
		}

	var from_map: Vector2i = map_id()
	var from_cell: Vector2i = player_cell
	_apply_map(target_map, target_tileset, target_cell)
	return {
		"ok": true,
		"kind": &"connection",
		"direction": direction_name,
		"from_map": from_map,
		"from_cell": from_cell,
		"to_map": map_id(),
		"to_cell": player_cell,
		"source": source_connection,
	}


func can_walk_to(cell: Vector2i) -> bool:
	if current_map == null or cell.x < 0 or cell.y < 0 \
		or cell.x >= current_map.collision_width or cell.y >= current_map.collision_height:
		return false
	return Gen2WorldCollision.is_walkable(collision_code_at(cell)) and object_at(cell) == null


func can_object_walk_to(cell: Vector2i, moving: Gen2WorldObject) -> bool:
	if current_map == null or cell.x < 0 or cell.y < 0 \
		or cell.x >= current_map.collision_width or cell.y >= current_map.collision_height:
		return false
	if not Gen2WorldCollision.is_walkable(collision_code_at(cell)):
		return false
	for object: Gen2WorldObject in objects:
		if object != moving and object.active and object.sprite != null and object.cell == cell:
			return false
	return cell != player_cell


## Advances the movement templates whose source behavior is data-driven in this
## slice. Scripted movement is executed by the script runner, while followers
## advance after each successful player step.
func advance_objects(random: RandomNumberGenerator) -> int:
	var moved: int = 0
	for object: Gen2WorldObject in objects:
		if not object.active or not object.movement_supported():
			continue
		if object.movement in [Gen2WorldObject.MOVEMENT_SPINRANDOM_SLOW, Gen2WorldObject.MOVEMENT_SPINRANDOM_FAST]:
			object.facing = random.randi_range(
				Gen2WorldSprite.FACING_DOWN, Gen2WorldSprite.FACING_RIGHT
			)
			continue
		var direction: Vector2i = object.next_direction(random)
		if direction == Vector2i.ZERO:
			continue
		var destination: Vector2i = object.cell + direction
		if not object.can_leave_to(destination) or not can_object_walk_to(destination, object):
			continue
		object.cell = destination
		object.apply_direction(direction)
		moved += 1
	return moved


func _advance_followers() -> void:
	for key: String in _object_followers:
		var separator: PackedStringArray = key.split(":")
		if separator.size() != 3 or int(separator[0]) != current_map.group \
			or int(separator[1]) != current_map.number:
			continue
		var follower_index: int = int(separator[2])
		if follower_index < 0 or follower_index >= objects.size():
			continue
		var follower: Gen2WorldObject = objects[follower_index]
		if not follower.active:
			continue
		var relation: Dictionary = _object_followers[key]
		var target_index: int = int(relation.get("target_index", -1))
		var target_cell: Vector2i = player_cell
		if target_index >= 0 and target_index < objects.size():
			target_cell = (objects[target_index] as Gen2WorldObject).cell
		var delta: Vector2i = target_cell - follower.cell
		if abs(delta.x) + abs(delta.y) <= 1:
			continue
		var direction: Vector2i
		if abs(delta.x) >= abs(delta.y):
			direction = Vector2i(signi(delta.x), 0)
		else:
			direction = Vector2i(0, signi(delta.y))
		var destination: Vector2i = follower.cell + direction
		if can_object_walk_to(destination, follower):
			follower.cell = destination
			follower.apply_direction(direction)
			var override_key: String = _object_key(
				current_map.group, current_map.number, follower_index
			)
			_object_position_overrides[override_key] = follower.cell
			_object_facing_overrides[override_key] = follower.facing


## Moves one cell or enters a neighboring map when the step leaves a connected
## map edge. The legacy boolean move() wrapper remains available to callers.
func move_result(direction: Vector2i) -> Dictionary:
	if abs(direction.x) + abs(direction.y) != 1:
		return {"ok": false, "kind": &"move", "reason": &"invalid_direction"}
	var destination: Vector2i = player_cell + direction
	if current_map == null:
		return {"ok": false, "kind": &"move", "reason": &"missing_map"}
	if destination.x < 0 or destination.y < 0 \
		or destination.x >= current_map.collision_width \
		or destination.y >= current_map.collision_height:
		var transition: Dictionary = try_connection(direction)
		if not transition.is_empty():
			if bool(transition.get("ok", false)):
				player_facing = _facing_for_direction(direction)
			return transition
		return {"ok": false, "kind": &"move", "reason": &"map_edge"}
	if not can_walk_to(destination):
		return {"ok": false, "kind": &"move", "reason": &"blocked"}
	var from_map: Vector2i = map_id()
	var from_cell: Vector2i = player_cell
	player_cell = destination
	player_facing = _facing_for_direction(direction)
	_advance_followers()
	return {
		"ok": true,
		"kind": &"move",
		"from_map": from_map,
		"from_cell": from_cell,
		"to_map": from_map,
		"to_cell": player_cell,
	}


## Moves exactly one walk cell in a cardinal direction. Diagonal, zero and
## out-of-bounds moves are rejected without changing the player position.
func move(direction: Vector2i) -> bool:
	return bool(move_result(direction).get("ok", false))


func _clamp_cell(cell: Vector2i) -> Vector2i:
	var size: Vector2i = map_size_cells()
	return Vector2i(
		clampi(cell.x, 0, maxi(0, size.x - 1)),
		clampi(cell.y, 0, maxi(0, size.y - 1)),
	)


func _direction_name(direction: Vector2i) -> String:
	match direction:
		Vector2i.UP:
			return "north"
		Vector2i.DOWN:
			return "south"
		Vector2i.LEFT:
			return "west"
		Vector2i.RIGHT:
			return "east"
	return ""


func _facing_for_direction(direction: Vector2i) -> int:
	match direction:
		Vector2i.UP:
			return Gen2WorldSprite.FACING_UP
		Vector2i.DOWN:
			return Gen2WorldSprite.FACING_DOWN
		Vector2i.LEFT:
			return Gen2WorldSprite.FACING_LEFT
		Vector2i.RIGHT:
			return Gen2WorldSprite.FACING_RIGHT
	return player_facing


func _at_connection_edge(direction_name: String) -> bool:
	if current_map == null:
		return false
	match direction_name:
		"north":
			return player_cell.y == 0
		"south":
			return player_cell.y == current_map.collision_height - 1
		"west":
			return player_cell.x == 0
		"east":
			return player_cell.x == current_map.collision_width - 1
	return false


func _apply_map(
	target_map: Gen2WorldMap, target_tileset: Gen2WorldTileset, target_cell: Vector2i
) -> void:
	current_map = target_map
	current_tileset = target_tileset
	player_cell = _clamp_cell(target_cell)
	_load_objects()
	_queue_map_callbacks(-1)


func _on_world_state_changed() -> void:
	set_object_time(object_hour, object_time_of_day)


func _load_objects() -> void:
	objects = []
	if current_map == null or data == null:
		return
	var rows: Array = current_map.events.get("objects", [])
	for index: int in rows.size():
		var value: Dictionary = rows[index]
		var sprite_number: int = int(value.get("sprite", 0))
		var sprite: Gen2WorldSprite = data.overworld_sprite(sprite_number)
		var object: Gen2WorldObject = Gen2WorldObject.from_event(index, value, sprite)
		var key: String = _object_key(current_map.group, current_map.number, index)
		if _object_position_overrides.has(key):
			object.cell = _object_position_overrides[key]
		if _object_facing_overrides.has(key):
			object.facing = int(_object_facing_overrides[key])
		objects.append(object)
	set_object_time(object_hour, object_time_of_day)


func _find_sight_request() -> Dictionary:
	if current_map == null:
		return {}
	var bank: int = int(current_map.events.get("bank", 0))
	var rows: Array = current_map.events.get("objects", [])
	for object: Gen2WorldObject in objects:
		if not object.active or object.sprite == null \
			or object.object_type != Gen2WorldObject.OBJECTTYPE_TRAINER \
			or object.sight_range <= 0 or object.event_script <= 0:
			continue
		if object.event_flag_active(state):
			continue
		var sight: Dictionary = _sight_distance(object)
		if sight.is_empty() or int(sight["distance"]) > object.sight_range:
			continue
		if object.index < 0 or object.index >= rows.size() or not rows[object.index] is Dictionary:
			continue
		var event: Dictionary = (rows[object.index] as Dictionary).duplicate(true)
		event["kind"] = &"objects"
		event["object_index"] = object.index
		event["trigger"] = &"sight"
		return {
			"kind": &"sight",
			"map_group": current_map.group,
			"map_number": current_map.number,
			"cell": object.cell,
			"bank": bank,
			"script": object.event_script,
			"object_index": object.index,
			"event": event,
			"distance": int(sight["distance"]),
			"direction": sight["direction"],
		}
	return {}


func _sight_distance(object: Gen2WorldObject) -> Dictionary:
	var delta: Vector2i = player_cell - object.cell
	var direction: Vector2i = Vector2i.ZERO
	match object.facing:
		Gen2WorldSprite.FACING_DOWN:
			if delta.x == 0 and delta.y > 0:
				direction = Vector2i.DOWN
		Gen2WorldSprite.FACING_UP:
			if delta.x == 0 and delta.y < 0:
				direction = Vector2i.UP
		Gen2WorldSprite.FACING_LEFT:
			if delta.y == 0 and delta.x < 0:
				direction = Vector2i.LEFT
		Gen2WorldSprite.FACING_RIGHT:
			if delta.y == 0 and delta.x > 0:
				direction = Vector2i.RIGHT
	if direction == Vector2i.ZERO:
		return {}
	return {"distance": absi(delta.x) + absi(delta.y), "direction": direction}
