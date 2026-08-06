class_name Gen2WorldSnapshot
extends RefCounted

## Save-safe map and player state paired with the mutable world state.
## Cartridge content is looked up from GameData when this snapshot is opened.

const FORMAT_VERSION: int = 1

var format_version: int = FORMAT_VERSION
var map_id: Vector2i = Vector2i(-1, -1)
var player_cell: Vector2i = Vector2i.ZERO
var player_facing: int = Gen2WorldSprite.FACING_DOWN
var movement_mode: StringName = &"walk"
var world_day: int = 0
var world_hour: int = 6
var world_minute: int = 0
var world_state: Gen2WorldState = Gen2WorldState.new()


static func from_world(world: Gen2WorldAPI) -> Gen2WorldSnapshot:
	if world == null or world.current_map == null:
		return null
	var out := Gen2WorldSnapshot.new()
	out.map_id = world.map_id()
	out.player_cell = world.player_cell
	out.player_facing = world.player_facing
	out.movement_mode = world.movement_mode
	var clock: Dictionary = world.world_clock()
	out.world_day = int(clock.get("day", 0))
	out.world_hour = int(clock.get("hour", 6))
	out.world_minute = int(clock.get("minute", 0))
	out.world_state = Gen2WorldState.from_dict(world.state.to_dict())
	return out


func to_dict() -> Dictionary:
	return {
		"format_version": format_version,
		"map": [map_id.x, map_id.y],
		"player_cell": [player_cell.x, player_cell.y],
		"player_facing": player_facing,
		"movement_mode": String(movement_mode),
		"clock": [world_day, world_hour, world_minute],
		"world_state": world_state.to_dict() if world_state != null else {},
	}


static func from_dict(raw: Variant) -> Gen2WorldSnapshot:
	if not raw is Dictionary:
		return null
	var source: Dictionary = raw
	var out := Gen2WorldSnapshot.new()
	out.format_version = int(source.get("format_version", -1))
	out.map_id = _vector_from_value(source.get("map", [-1, -1]))
	out.player_cell = _vector_from_value(source.get("player_cell", [0, 0]))
	out.player_facing = int(source.get("player_facing", Gen2WorldSprite.FACING_DOWN))
	out.movement_mode = StringName(source.get("movement_mode", "walk"))
	var raw_clock: Variant = source.get("clock", [0, 6, 0])
	if raw_clock is Array and (raw_clock as Array).size() >= 3:
		var clock: Array = raw_clock as Array
		out.world_day = int(clock[0])
		out.world_hour = int(clock[1])
		out.world_minute = int(clock[2])
	out.world_state = Gen2WorldState.from_dict(source.get("world_state", {}))
	return out


func world_clock() -> Dictionary:
	return {"day": world_day, "hour": world_hour, "minute": world_minute}


static func _vector_from_value(value: Variant) -> Vector2i:
	if value is Array and (value as Array).size() >= 2:
		return Vector2i(int((value as Array)[0]), int((value as Array)[1]))
	if value is Dictionary:
		return Vector2i(int((value as Dictionary).get("x", -1)), int((value as Dictionary).get("y", -1)))
	return Vector2i(-1, -1)
