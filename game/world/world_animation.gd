class_name Gen2WorldAnimation
extends RefCounted

## Small interpreter for the command tables used by the cartridge overworld.
##
## The original engine writes 2bpp tiles to VRAM. This node-free equivalent
## keeps the same command order and timer semantics, but applies those writes to
## the indexed tile strip held by GameData.

const TILE_BYTES: int = Gen2Tiles.TILE_BYTES
## The hardware VBlank, and the project's one definition of it: every overworld
## timer is counted in these, and [method Gen2WorldScreen.advance_frame] is the
## single place real time is converted into them.
const FRAME_SECONDS: float = 1.0 / 59.7275
## The most catch-up frames one host frame will run. A stall should drop frames,
## not spend the recovery frame walking thousands of commands.
const MAX_CATCHUP_FRAMES: int = 4
const TIMER_WATER_FRAMES: Array = [0, 1, 2, 3]
const TIMER_FOUNTAIN_FRAMES: Array = [0, 1, 2, 3, 2, 3, 4, 0]
const TIMER_TOWER_FRAMES: Array = [0, 1, 2, 3, 4, 3, 2, 1]
const TIMER_WATER_PALETTE: Array = [0, 1, 2, 1]

var data: GameData = null
var map: Gen2WorldMap = null
var tileset: Gen2WorldTileset = null
var _indices: PackedByteArray = PackedByteArray()
var _buffer: PackedByteArray = PackedByteArray()
var _commands: Array = []
var _command_index: int = 0
var _timer: int = 0
var _water_color: int = -1
var _cave_color: int = -1
var _time_of_day: int = Gen2WorldPalette.TIME_MORNING
var _changed: bool = false
## Which tiles a run of commands rewrote, and whether a palette row moved. A
## renderer that keeps a texture only has to redo these tiles: the sequence
## touches one or two tiles per frame, and a palette change is the only thing
## that invalidates the rest.
var _changed_tiles: Dictionary = {}
var _palette_changed: bool = false


func configure(world: Gen2WorldAPI, time_of_day: int = Gen2WorldPalette.TIME_MORNING) -> void:
	data = world.data if world != null else null
	map = world.current_map if world != null else null
	tileset = world.current_tileset if world != null else null
	_time_of_day = clampi(time_of_day, 0, 3)
	_command_index = 0
	_timer = 0
	_water_color = -1
	_cave_color = -1
	_changed = false
	_changed_tiles = {}
	_palette_changed = false
	_buffer.resize(TILE_BYTES)
	if data == null or tileset == null:
		_indices = PackedByteArray()
		_commands = []
		return
	_indices = data.world_tileset_indices(tileset.number).duplicate()
	_commands = tileset.animation_commands.duplicate(true)


## Runs one hardware frame's command and reports whether the tile strip or a
## palette row actually changed.
##
## Most commands are waits and timer bumps that draw nothing new, so the return
## value is what a renderer should gate its atlas rebuild on; [method tick] is
## the single-command step the sequence is defined in.
func advance_frame() -> bool:
	if _commands.is_empty() or tileset == null:
		return false
	_changed_tiles = {}
	_palette_changed = false
	_changed = false
	tick()
	return _changed


## The tiles rewritten by the most recent [method advance_frame], in ascending
## order.
func changed_tiles() -> PackedInt32Array:
	var out := PackedInt32Array()
	for tile: int in _changed_tiles:
		out.append(tile)
	out.sort()
	return out


## Whether the most recent [method advance_frame] moved a palette row, which
## changes every tile drawn with it rather than only the ones it rewrote.
func palette_changed() -> bool:
	return _palette_changed


## How far into the command list the sequence has reached, for tests and cache
## inspection.
func command_index() -> int:
	return _command_index


func current_indices() -> PackedByteArray:
	return _indices


func water_palette_color() -> int:
	return _water_color


func cave_palette_color() -> int:
	return _cave_color


func tick() -> bool:
	if _commands.is_empty() or tileset == null:
		return false
	if _command_index < 0 or _command_index >= _commands.size():
		_command_index = 0
	var command: Dictionary = _commands[_command_index]
	_command_index += 1
	var operation: String = String(command.get("operation", ""))
	match operation:
		"done":
			_command_index = 0
		"wait":
			pass
		"timer_8":
			_timer = (_timer + 1) & 7
		"timer":
			_timer = (_timer + 1) & 0xFF
		"water":
			_copy_asset_tile("water", 0, (_timer & 6) >> 1, int(command.get("tile", -1)))
		"flower":
			# The CGB branch selects the second and fourth 2bpp tiles in the
			# four-tile asset, not the DMG variants that precede them.
			_copy_asset_tile("flower", 0, 1 if ((_timer & 2) != 0) else 0, 3)
		"fountain":
			_copy_asset_tile(
				"fountain", 0, TIMER_FOUNTAIN_FRAMES[_timer & 7], int(command.get("tile", -1))
			)
		"forest_left":
			_copy_asset_tile("forest", 0, 0, 0x0C)
		"forest_right":
			_copy_asset_tile("forest", 0, 0, 0x0F, 32)
		"forest_left_2":
			_copy_asset_tile("forest", 0, 0, 0x0C)
		"forest_right_2":
			_copy_asset_tile("forest", 0, 0, 0x0F, 32)
		"lava_1":
			_copy_asset_tile("lava", 0, (((_timer & 6) >> 1) + 2) & 3, 0x5B)
		"lava_2":
			_copy_asset_tile("lava", 0, (_timer & 6) >> 1, 0x38)
		"tower":
			_copy_asset_tile(
				"tower",
				int(command.get("asset_index", -1)),
				TIMER_TOWER_FRAMES[_timer & 7],
				int(command.get("tile", -1)),
			)
		"whirlpool":
			_copy_asset_tile(
				"whirlpool", int(command.get("asset_index", -1)), _timer & 3, int(command.get("tile", -1))
			)
		"read_buffer":
			_buffer = _tile_bytes(int(command.get("tile", -1)))
		"write_buffer":
			_set_tile_bytes(int(command.get("tile", -1)), _buffer)
		"scroll_horizontal":
			_scroll_horizontal()
		"scroll_vertical":
			_scroll_vertical()
		"water_palette":
			var water_color: int = TIMER_WATER_PALETTE[(_timer & 6) >> 1]
			if water_color != _water_color:
				_changed = true
				_palette_changed = true
			_water_color = water_color
		"cave_palette":
			if _time_of_day == Gen2WorldPalette.TIME_DARK:
				var cave_color: int = (_timer >> 1) & 1
				if cave_color != _cave_color:
					_changed = true
					_palette_changed = true
				_cave_color = cave_color
	return true


func _copy_asset_tile(
	name: String,
	asset_index: int,
	frame: int,
	tile: int,
	extra_offset: int = 0,
) -> void:
	if data == null or tile < 0 or tile >= tileset.tile_count:
		return
	var asset: PackedByteArray = data.world_animation_asset(name)
	var offset: int = asset_index * 80 + frame * TILE_BYTES + extra_offset
	if name == "flower":
		offset = 16 + frame * 32 + extra_offset
	elif name == "fountain":
		offset = frame * TILE_BYTES
	elif name == "forest":
		offset = extra_offset + frame * TILE_BYTES
	elif name == "lava":
		offset = frame * TILE_BYTES
	elif name == "whirlpool":
		offset = asset_index * 64 + frame * TILE_BYTES
	if offset < 0 or offset + TILE_BYTES > asset.size():
		return
	_set_tile_bytes(tile, asset.slice(offset, offset + TILE_BYTES))


func _tile_bytes(tile: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(TILE_BYTES)
	if tile < 0 or tile >= tileset.tile_count:
		return out
	var width: int = tileset.tile_count * Gen2Tiles.TILE_WIDTH
	for y: int in Gen2Tiles.TILE_HEIGHT:
		var low: int = 0
		var high: int = 0
		for x: int in Gen2Tiles.TILE_WIDTH:
			var value: int = int(_indices[y * width + tile * Gen2Tiles.TILE_WIDTH + x])
			low |= (value & 1) << (7 - x)
			high |= ((value >> 1) & 1) << (7 - x)
		out[y * 2] = low
		out[y * 2 + 1] = high
	return out


func _set_tile_bytes(tile: int, bytes: PackedByteArray) -> void:
	if tile < 0 or tile >= tileset.tile_count or bytes.size() < TILE_BYTES:
		return
	var width: int = tileset.tile_count * Gen2Tiles.TILE_WIDTH
	for y: int in Gen2Tiles.TILE_HEIGHT:
		var low: int = int(bytes[y * 2])
		var high: int = int(bytes[y * 2 + 1])
		for x: int in Gen2Tiles.TILE_WIDTH:
			var value: int = ((low >> (7 - x)) & 1) | (((high >> (7 - x)) & 1) << 1)
			var at: int = y * width + tile * Gen2Tiles.TILE_WIDTH + x
			if _indices[at] == value:
				continue
			_indices[at] = value
			_changed = true
			_changed_tiles[tile] = true


func _scroll_horizontal() -> void:
	for y: int in Gen2Tiles.TILE_HEIGHT:
		var low: int = int(_buffer[y * 2])
		var high: int = int(_buffer[y * 2 + 1])
		var direction_right: bool = (_timer & 4) == 0
		if direction_right:
			low = ((low >> 1) | ((low & 1) << 7)) & 0xFF
			high = ((high >> 1) | ((high & 1) << 7)) & 0xFF
		else:
			low = ((low << 1) | (low >> 7)) & 0xFF
			high = ((high << 1) | (high >> 7)) & 0xFF
		_buffer[y * 2] = low
		_buffer[y * 2 + 1] = high


func _scroll_vertical() -> void:
	var copy: PackedByteArray = _buffer.duplicate()
	var direction_down: bool = (_timer & 4) != 0
	for y: int in Gen2Tiles.TILE_HEIGHT:
		var source_y: int = ((y - 1) & 7) if direction_down else ((y + 1) & 7)
		_buffer[y * 2] = copy[source_y * 2]
		_buffer[y * 2 + 1] = copy[source_y * 2 + 1]
