class_name Gen2WorldMap
extends RefCounted

## Node-free map data decoded from a Generation 2 map header and event block.
## Coordinates are row-major, with y increasing from the top as on the
## cartridge. Collision values are the raw cartridge permissions, not booleans.

var group: int = 0
var number: int = 0
var tileset: int = 0
var environment: int = 0
var location: int = 0
var music: int = 0
var phone_flag: int = 0
var palette: int = 0
var fish_group: int = 0
var border_block: int = 0
var width_blocks: int = 0
var height_blocks: int = 0
var blocks: Array = []
var collision: Array = []
var collision_width: int = 0
var collision_height: int = 0
var connection_flags: int = 0
var connections: Array = []
var scripts: Dictionary = {}
var events: Dictionary = {}


static func from_cache(value: Dictionary) -> Gen2WorldMap:
	var out := Gen2WorldMap.new()
	out.group = int(value.get("group", 0))
	out.number = int(value.get("number", 0))
	out.tileset = int(value.get("tileset", 0))
	out.environment = int(value.get("environment", 0))
	out.location = int(value.get("location", 0))
	out.music = int(value.get("music", 0))
	out.phone_flag = int(value.get("phone_flag", 0))
	out.palette = int(value.get("palette", 0))
	out.fish_group = int(value.get("fish_group", 0))
	out.border_block = int(value.get("border_block", 0))
	out.width_blocks = int(value.get("width_blocks", 0))
	out.height_blocks = int(value.get("height_blocks", 0))
	out.blocks = value.get("blocks", []) if value.get("blocks", []) is Array else []
	out.collision = value.get("collision", []) if value.get("collision", []) is Array else []
	out.collision_width = int(value.get("collision_width", out.width_blocks * 2))
	out.collision_height = int(value.get("collision_height", out.height_blocks * 2))
	var cached_connections: Variant = value.get("connections", [])
	if cached_connections is Array:
		out.connections = _connection_rows(cached_connections)
		out.connection_flags = int(value.get("connection_flags", 0))
	else:
		# Caches before format 12 stored only the raw direction flags.
		out.connection_flags = int(cached_connections)
		out.connections = []
	out.scripts = _scripts_from_cache(value.get("scripts", {}))
	out.events = _events_from_cache(value.get("events", {}))
	return out


func block_at(block_x: int, block_y: int) -> int:
	if block_x < 0 or block_x >= width_blocks or block_y < 0 or block_y >= height_blocks:
		return 0
	return int(blocks[block_y * width_blocks + block_x])


func collision_at(cell_x: int, cell_y: int) -> int:
	if cell_x < 0 or cell_x >= collision_width or cell_y < 0 or cell_y >= collision_height:
		return -1
	return int(collision[cell_y * collision_width + cell_x])


static func _scripts_from_cache(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var scripts: Dictionary = value
	return {
		"bank": int(scripts.get("bank", 0)),
		"address": int(scripts.get("address", 0)),
		"scenes": _script_pointer_rows(scripts.get("scenes", [])),
		"callbacks": _script_pointer_rows(scripts.get("callbacks", [])),
	}


static func _script_pointer_rows(value: Variant) -> Array:
	if not value is Array:
		return []
	var out: Array = []
	for raw: Dictionary in value as Array:
		var row: Dictionary = raw.duplicate(true)
		for field: String in ["id", "type", "script"]:
			if raw.has(field):
				row[field] = int(raw[field])
		out.append(row)
	return out


static func _connection_rows(value: Array) -> Array:
	var out: Array = []
	for raw: Dictionary in value:
		var connection: Dictionary = raw.duplicate(true)
		for field: String in [
			"map_group", "map_number", "length", "target_width_blocks",
			"x_offset", "y_offset", "target_block_pointer", "map_pointer",
			"window_pointer",
		]:
			connection[field] = int(raw.get(field, 0))
		out.append(connection)
	return out


static func _events_from_cache(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var events: Dictionary = value
	return {
		"bank": int(events.get("bank", 0)),
		"address": int(events.get("address", 0)),
		"warps": _event_rows(events.get("warps", []), ["x", "y", "destination", "map_group", "map_number"]),
		"coord_events": _event_rows(events.get("coord_events", []), ["scene", "x", "y", "script"]),
		"bg_events": _event_rows(events.get("bg_events", []), ["x", "y", "type", "script"]),
		"objects": _event_rows(events.get("objects", []), [
			"sprite", "x", "y", "movement", "x_radius", "y_radius", "hour_1", "hour_2",
			"palette", "object_type", "sight_range", "script", "event_flag",
		]),
	}


static func _event_rows(value: Variant, integer_fields: Array[String]) -> Array:
	if not value is Array:
		return []
	var out: Array = []
	for raw: Dictionary in value as Array:
		var event: Dictionary = raw.duplicate(true)
		for field: String in integer_fields:
			event[field] = int(raw.get(field, 0))
		out.append(event)
	return out
