class_name Gen2WorldAPI
extends RefCounted

## Scene-free runtime access to one imported Generation 2 map.
##
## The API works in walk cells: every cell is a 2x2 group of 8x8 graphics
## tiles. It owns player position and camera framing, but not save data,
## scripts, object state or scene nodes.

const VIEW_CELLS: Vector2i = Vector2i(10, 9)
const VIEW_TILES: Vector2i = VIEW_CELLS * RomLayout.MAP_BLOCK_CELL_WIDTH
const CELL_PIXELS: int = Gen2Tiles.TILE_WIDTH * RomLayout.MAP_BLOCK_CELL_WIDTH

var data: GameData = null
var current_map: Gen2WorldMap = null
var current_tileset: Gen2WorldTileset = null
var player_cell: Vector2i = Vector2i.ZERO


## Opens one map through the public cartridge-content API.
## Returns null when the cache does not contain the requested map or tileset.
static func open(
	game_data: GameData, group: int, number: int, start_cell: Vector2i
) -> Gen2WorldAPI:
	if game_data == null:
		return null
	var map: Gen2WorldMap = game_data.world_map(group, number)
	if map == null:
		return null
	var tileset: Gen2WorldTileset = game_data.world_tileset(map.tileset)
	if tileset == null:
		return null
	return Gen2WorldAPI.new(game_data, map, tileset, start_cell)


func _init(
	game_data: GameData,
	map: Gen2WorldMap,
	tileset: Gen2WorldTileset,
	start_cell: Vector2i = Vector2i.ZERO,
) -> void:
	data = game_data
	current_map = map
	current_tileset = tileset
	player_cell = _clamp_cell(start_cell)


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
		for raw: Dictionary in current_map.events.get(source, []):
			if int(raw.get("x", -1)) != cell.x or int(raw.get("y", -1)) != cell.y:
				continue
			var event: Dictionary = raw.duplicate(true)
			event["kind"] = StringName(source)
			out.append(event)
	return out


## Public event boundary for the screen and future systems. It reports decoded
## records without running cartridge scripts or changing event flags.
func dispatch_events(cell: Vector2i = player_cell) -> Array:
	return events_at(cell)


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
	current_map = target_map
	current_tileset = target_tileset
	player_cell = _clamp_cell(Vector2i(int(target_warp["x"]), int(target_warp["y"])))
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


func can_walk_to(cell: Vector2i) -> bool:
	if current_map == null or cell.x < 0 or cell.y < 0 \
		or cell.x >= current_map.collision_width or cell.y >= current_map.collision_height:
		return false
	return Gen2WorldCollision.is_walkable(collision_code_at(cell))


## Moves exactly one walk cell in a cardinal direction. Diagonal, zero and
## out-of-bounds moves are rejected without changing the player position.
func move(direction: Vector2i) -> bool:
	if abs(direction.x) + abs(direction.y) != 1:
		return false
	var destination: Vector2i = player_cell + direction
	if not can_walk_to(destination):
		return false
	player_cell = destination
	return true


func _clamp_cell(cell: Vector2i) -> Vector2i:
	var size: Vector2i = map_size_cells()
	return Vector2i(
		clampi(cell.x, 0, maxi(0, size.x - 1)),
		clampi(cell.y, 0, maxi(0, size.y - 1)),
	)
