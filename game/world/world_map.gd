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
var connections: int = 0
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
	out.connections = int(value.get("connections", 0))
	out.scripts = value.get("scripts", {}) if value.get("scripts", {}) is Dictionary else {}
	out.events = value.get("events", {}) if value.get("events", {}) is Dictionary else {}
	return out


func block_at(block_x: int, block_y: int) -> int:
	if block_x < 0 or block_x >= width_blocks or block_y < 0 or block_y >= height_blocks:
		return 0
	return int(blocks[block_y * width_blocks + block_x])


func collision_at(cell_x: int, cell_y: int) -> int:
	if cell_x < 0 or cell_x >= collision_width or cell_y < 0 or cell_y >= collision_height:
		return -1
	return int(collision[cell_y * collision_width + cell_x])
