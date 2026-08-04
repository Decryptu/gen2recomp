class_name Gen2WorldImporter
extends RefCounted

## Imports the map table, map attributes, map events, tileset tables and
## addressable overworld tile strips for a verified Generation 2 cartridge.
##
## The parser follows the official map macros and the runtime's collision
## lookup: map blocks are 4x4 graphics tiles, walk coordinates are 2x2 cells per
## block, and collision bytes use x as the low bit and y as the high bit.

static func verify_layout(rom: RomFile) -> Dictionary:
	var result: Dictionary = read_world(rom, RomLayout.for_id(rom.id))
	if not bool(result.get("ok", false)):
		return {"ok": false, "message": String(result.get("message", "World data failed validation."))}
	return {"ok": true, "message": ""}


static func import_to_cache(
	rom: RomFile, layout: Dictionary, directory: String, on_progress: Callable = Callable()
) -> Dictionary:
	var result: Dictionary = read_world(rom, layout, on_progress)
	if not bool(result.get("ok", false)):
		return result

	var tilesets: Array = result["tilesets"]
	if not RomCache.write_json(RomCache.world_tilesets_path(directory), tilesets):
		return {"ok": false, "message": "Could not write overworld tileset data."}
	if not RomCache.write_json(RomCache.world_palettes_path(directory), result["palettes"]):
		return {"ok": false, "message": "Could not write overworld palette data."}
	if not RomCache.write_json(
		RomCache.world_animation_assets_path(directory), result["animation_assets"]
	):
		return {"ok": false, "message": "Could not write overworld animation data."}
	if not RomCache.write_json(RomCache.world_maps_path(directory), result["maps"]):
		return {"ok": false, "message": "Could not write overworld map data."}

	var graphics: Dictionary = result["graphics"]
	for number: int in graphics:
		if not RomCache.write_indices(RomCache.world_tile_path(directory, number), graphics[number]):
			return {"ok": false, "message": "Could not write overworld tileset %d." % number}

	return {
		"ok": true,
		"maps": result["maps"].size(),
		"tilesets": tilesets.size(),
	}


static func read_world(
	rom: RomFile, layout: Dictionary, on_progress: Callable = Callable()
) -> Dictionary:
	if layout.is_empty():
		return {"ok": false, "message": "No world layout for %s." % rom.id}

	var palettes: Dictionary = _read_world_palettes(rom, layout)
	if not bool(palettes.get("ok", false)):
		return palettes
	var animation_assets: Dictionary = _read_world_animation_assets(rom, layout)
	if not bool(animation_assets.get("ok", false)):
		return animation_assets

	var tilesets: Array = []
	var graphics: Dictionary = {}
	for number: int in RomLayout.tileset_count(layout):
		var tileset: Dictionary = _read_tileset(rom, layout, number)
		if not bool(tileset.get("ok", false)):
			return tileset
		graphics[number] = tileset["pixels"]
		tileset.erase("ok")
		tileset.erase("pixels")
		tilesets.append(tileset)
		if on_progress.is_valid():
			on_progress.call("world_tilesets", number + 1, tilesets.size())

	var maps: Array = []
	for group: int in range(1, RomLayout.MAP_GROUP_COUNT + 1):
		var pointer_offset: int = RomLayout.map_group_pointer_offset(layout, group)
		if not rom.in_bounds(pointer_offset, RomLayout.MAP_GROUP_POINTER_SIZE):
			return _error("Map group %d pointer is outside the ROM." % group)
		var group_pointer: int = rom.u16le(pointer_offset)
		if not _valid_cpu_address(group_pointer):
			return _error("Map group %d starts at invalid address $%04X." % [group, group_pointer])

		var group_count: int = RomLayout.map_group_count(layout, group)
		for number: int in range(1, group_count + 1):
			var map_result: Dictionary = _read_map(rom, layout, tilesets, group, number, group_pointer)
			if not bool(map_result.get("ok", false)):
				return map_result
			map_result.erase("ok")
			maps.append(map_result)
			if on_progress.is_valid():
				on_progress.call("world_maps", maps.size(), RomLayout.map_count(layout))

	return {
		"ok": true,
		"maps": maps,
		"tilesets": tilesets,
		"graphics": graphics,
		"palettes": palettes["groups"],
		"animation_assets": animation_assets["assets"],
	}


static func _read_tileset(rom: RomFile, layout: Dictionary, number: int) -> Dictionary:
	var table: int = RomLayout.tileset_offset(layout, number)
	if not rom.in_bounds(table, RomLayout.TILESET_RECORD_SIZE):
		return _error("Tileset %d record is outside the ROM." % number)

	var gfx: Dictionary = rom.far_pointer(table)
	var meta: Dictionary = rom.far_pointer(table + 3)
	var collision: Dictionary = rom.far_pointer(table + 6)
	var gfx_offset: int = _far_offset(rom, gfx)
	var meta_offset: int = _far_offset(rom, meta)
	var collision_offset: int = _far_offset(rom, collision)
	var block_count: int = RomLayout.tileset_block_count(layout, number)
	if gfx_offset < 0 or meta_offset < 0 or collision_offset < 0:
		return _error("Tileset %d has an invalid far pointer." % number)

	var lz := Gen2Lz.new()
	var raw_graphics: PackedByteArray = lz.decompress(rom.bytes(), gfx_offset)
	var expected_graphics: int = RomLayout.TILESET_TILE_COUNT * Gen2Tiles.TILE_BYTES
	if lz.failed or raw_graphics.size() < expected_graphics:
		return _error("Tileset %d graphics decoded to %d bytes, expected at least %d." % [number, raw_graphics.size(), expected_graphics])

	var meta_size: int = block_count * RomLayout.TILESET_META_BYTES_PER_BLOCK
	var collision_size: int = block_count * RomLayout.TILESET_COLLISION_BYTES_PER_BLOCK
	var meta_bytes: PackedByteArray = rom.slice(meta_offset, meta_size)
	var collision_bytes: PackedByteArray = rom.slice(collision_offset, collision_size)
	if meta_bytes.size() != meta_size or collision_bytes.size() != collision_size:
		return _error("Tileset %d tables are shorter than their verified layout." % number)

	var palette_map_offset: int = RomFile.linear(
		int(layout["tileset_palette_bank"]), rom.u16le(table + 13)
	)
	var palette_map: PackedByteArray = rom.slice(palette_map_offset, RomLayout.WORLD_PALETTE_MAP_BYTES)
	if palette_map.size() != RomLayout.WORLD_PALETTE_MAP_BYTES:
		return _error("Tileset %d palette map is outside the cartridge." % number)

	var animation: Dictionary = _read_animation(rom, layout, rom.u16le(table + 9), number)
	if not bool(animation.get("ok", false)):
		return animation

	return {
		"ok": true,
		"number": number,
		"block_count": block_count,
		"tile_count": RomLayout.TILESET_TILE_COUNT,
		"meta": Array(meta_bytes),
		"collision": Array(collision_bytes),
		"animation_pointer": rom.u16le(table + 9),
		"palette_map_pointer": rom.u16le(table + 13),
		"palette_map": Array(palette_map),
		"animation_commands": animation["commands"],
		"pixels": Gen2Tiles.decode_2bpp_strip(raw_graphics, 0, RomLayout.TILESET_TILE_COUNT),
	}


static func _read_world_palettes(rom: RomFile, layout: Dictionary) -> Dictionary:
	var offset: int = int(layout["world_palette_offset"])
	var bytes: PackedByteArray = rom.slice(offset, RomLayout.WORLD_PALETTE_BYTES)
	if bytes.size() != RomLayout.WORLD_PALETTE_BYTES:
		return _error("Overworld palette data is outside the cartridge.")

	var groups: Array = []
	for group: int in RomLayout.WORLD_PALETTE_GROUP_COUNT:
		var colors: Array = []
		for color: int in 4:
			var at: int = group * RomLayout.WORLD_PALETTE_GROUP_BYTES + color * 2
			colors.append(int(bytes[at]) | (int(bytes[at + 1]) << 8))
		groups.append(colors)
	return {"ok": true, "groups": groups}


static func _read_world_animation_assets(rom: RomFile, layout: Dictionary) -> Dictionary:
	var assets: Dictionary = {}
	var specs: Dictionary = layout.get("world_animation_assets", {})
	for name: String in specs:
		var spec: Dictionary = specs[name]
		var bytes: PackedByteArray = rom.slice(int(spec["offset"]), int(spec["bytes"]))
		if bytes.size() != int(spec["bytes"]):
			return _error("Overworld animation asset %s is outside the cartridge." % name)
		assets[name] = Array(bytes)
	return {"ok": true, "assets": assets}


static func _read_animation(rom: RomFile, layout: Dictionary, pointer: int, number: int) -> Dictionary:
	var offset: int = RomFile.linear(RomLayout.WORLD_ANIMATION_BANK, pointer)
	var functions: Dictionary = layout.get("world_animation_functions", {})
	var done: int = int(layout["world_animation_done"])
	var commands: Array = []
	var found_done: bool = false
	for index: int in RomLayout.WORLD_ANIMATION_MAX_COMMANDS:
		var at: int = offset + index * RomLayout.WORLD_ANIMATION_COMMAND_BYTES
		if not rom.in_bounds(at, RomLayout.WORLD_ANIMATION_COMMAND_BYTES):
			return _error("Tileset %d animation table is truncated." % number)
		var parameter: int = rom.u16le(at)
		var function: int = rom.u16le(at + 2)
		if not functions.has(function):
			return _error("Tileset %d uses unknown animation function $%04X." % [number, function])
		var command: Dictionary = {
			"parameter": parameter,
			"function": function,
			"operation": String(functions[function]),
		}
		if command["operation"] in ["water", "fountain", "scroll_horizontal", "scroll_vertical", "read_buffer", "write_buffer"]:
			command["tile"] = _vram_tile(parameter)
		elif command["operation"] in ["tower", "whirlpool"]:
			var target: int = RomFile.linear(RomLayout.WORLD_ANIMATION_BANK, parameter)
			if not rom.in_bounds(target, 4):
				return _error("Tileset %d animation target is outside the cartridge." % number)
			command["tile"] = _vram_tile(rom.u16le(target))
			command["asset_index"] = _animation_asset_index(
				rom, layout, command["operation"], rom.u16le(target + 2)
			)
		commands.append(command)
		if function == done:
			found_done = true
			break
	if not found_done:
		return _error("Tileset %d animation table has no terminator." % number)
	return {"ok": true, "commands": commands}


static func _vram_tile(address: int) -> int:
	if address < 0x9000 or address >= 0xA000 or (address - 0x9000) % Gen2Tiles.TILE_BYTES != 0:
		return -1
	return (address - 0x9000) / Gen2Tiles.TILE_BYTES


static func _animation_asset_index(rom: RomFile, layout: Dictionary, operation: String, pointer: int) -> int:
	var name: String = "tower" if operation == "tower" else "whirlpool"
	var spec: Dictionary = layout["world_animation_assets"][name]
	var base: int = int(spec["offset"])
	var stride: int = 80 if name == "tower" else 64
	var offset: int = RomFile.linear(RomLayout.WORLD_ANIMATION_BANK, pointer)
	var delta: int = offset - base
	if delta < 0 or delta % stride != 0 or delta >= int(spec["bytes"]):
		return -1
	return delta / stride


static func _read_map(
	rom: RomFile,
	layout: Dictionary,
	tilesets: Array,
	group: int,
	number: int,
	group_pointer: int,
) -> Dictionary:
	var record: int = RomLayout.map_record_offset(layout, group_pointer, number)
	if not rom.in_bounds(record, RomLayout.MAP_RECORD_SIZE):
		return _error("Map %d/%d record is outside the ROM." % [group, number])

	var tileset_number: int = rom.u8(record + 1)
	if tileset_number < 0 or tileset_number >= tilesets.size():
		return _error("Map %d/%d references tileset %d." % [group, number, tileset_number])

	var attr_bank: int = rom.u8(record)
	var attr_address: int = rom.u16le(record + 3)
	var attributes: int = _far_offset(rom, {"bank": attr_bank, "address": attr_address})
	if attributes < 0 or not rom.in_bounds(attributes, RomLayout.MAP_ATTRIBUTES_SIZE):
		return _error("Map %d/%d has an invalid attributes pointer." % [group, number])

	var border_block: int = rom.u8(attributes)
	var height: int = rom.u8(attributes + 1)
	var width: int = rom.u8(attributes + 2)
	if width <= 0 or width > RomLayout.MAP_MAX_WIDTH_BLOCKS or height <= 0 \
		or height > RomLayout.MAP_MAX_HEIGHT_BLOCKS:
		return _error("Map %d/%d has dimensions %dx%d blocks." % [group, number, width, height])

	var block_bank: int = rom.u8(attributes + 3)
	var block_address: int = rom.u16le(attributes + 4)
	var block_offset: int = _far_offset(rom, {"bank": block_bank, "address": block_address})
	var block_size: int = width * height
	if block_offset < 0 or not rom.in_bounds(block_offset, block_size):
		return _error("Map %d/%d block data is outside the ROM." % [group, number])
	var block_bytes: PackedByteArray = rom.slice(block_offset, block_size)
	var block_count: int = int(tilesets[tileset_number]["block_count"])
	for block: int in block_bytes:
		if block >= block_count:
			return _error("Map %d/%d uses block %d in a %d-block tileset." % [group, number, block, block_count])

	var scripts_bank: int = rom.u8(attributes + 6)
	var scripts_address: int = rom.u16le(attributes + 7)
	var events_address: int = rom.u16le(attributes + 9)
	if _far_offset(rom, {"bank": scripts_bank, "address": scripts_address}) < 0 \
		or _far_offset(rom, {"bank": scripts_bank, "address": events_address}) < 0:
		return _error("Map %d/%d has an invalid scripts or events pointer." % [group, number])

	var event_result: Dictionary = _read_events(
		rom, scripts_bank, events_address, group, number, width * 2, height * 2
	)
	if not bool(event_result.get("ok", false)):
		return event_result

	var tileset: Dictionary = tilesets[tileset_number]
	var collision_grid: Array = []
	for cell_y: int in height * RomLayout.MAP_BLOCK_CELL_WIDTH:
		for cell_x: int in width * RomLayout.MAP_BLOCK_CELL_WIDTH:
			var block: int = int(block_bytes[(cell_y >> 1) * width + (cell_x >> 1)])
			var value: int = -1
			if block > 0:
				var collision_at: int = block * RomLayout.TILESET_COLLISION_BYTES_PER_BLOCK \
					+ (cell_x & 1) + ((cell_y & 1) * 2)
				value = int(tileset["collision"][collision_at])
			collision_grid.append(value)

	var phone_palette: int = rom.u8(record + 7)
	return {
		"ok": true,
		"group": group,
		"number": number,
		"tileset": tileset_number,
		"environment": rom.u8(record + 2),
		"location": rom.u8(record + 5),
		"music": rom.u8(record + 6),
		"phone_flag": phone_palette >> 4,
		"palette": phone_palette & 0x0F,
		"fish_group": rom.u8(record + 8),
		"border_block": border_block,
		"width_blocks": width,
		"height_blocks": height,
		"blocks": Array(block_bytes),
		"collision": collision_grid,
		"collision_width": width * 2,
		"collision_height": height * 2,
		"connections": rom.u8(attributes + 11),
		"scripts": {"bank": scripts_bank, "address": scripts_address},
		"events": {
			"bank": scripts_bank,
			"address": events_address,
			"warps": event_result["warps"],
			"coord_events": event_result["coord_events"],
			"bg_events": event_result["bg_events"],
			"objects": event_result["objects"],
		},
	}


static func _read_events(
	rom: RomFile, bank: int, address: int, group: int, number: int, cell_width: int, cell_height: int
) -> Dictionary:
	var at: int = _far_offset(rom, {"bank": bank, "address": address})
	if at < 0 or not rom.in_bounds(at, RomLayout.MAP_EVENT_HEADER_SIZE):
		return _error("Map %d/%d events are outside the ROM." % [group, number])
	at += RomLayout.MAP_EVENT_HEADER_SIZE

	var warps: Array = []
	if not rom.in_bounds(at):
		return _error("Map %d/%d has no warp-event count." % [group, number])
	var warp_count: int = rom.u8(at)
	at += 1
	for _i: int in warp_count:
		if not rom.in_bounds(at, RomLayout.MAP_WARP_EVENT_SIZE):
			return _error("Map %d/%d warp events are truncated." % [group, number])
		var y: int = rom.u8(at)
		var x: int = rom.u8(at + 1)
		if not _valid_coord(x, y, cell_width, cell_height):
			return _error("Map %d/%d has an out-of-bounds warp at %d,%d." % [group, number, x, y])
		warps.append({
			"x": x,
			"y": y,
			"destination": rom.u8(at + 2),
			"map_group": rom.u8(at + 3),
			"map_number": rom.u8(at + 4),
		})
		at += RomLayout.MAP_WARP_EVENT_SIZE

	var coord_events: Array = []
	if not rom.in_bounds(at):
		return _error("Map %d/%d has no coordinate-event count." % [group, number])
	var coord_count: int = rom.u8(at)
	at += 1
	for _i: int in coord_count:
		if not rom.in_bounds(at, RomLayout.MAP_COORD_EVENT_SIZE):
			return _error("Map %d/%d coordinate events are truncated." % [group, number])
		var coord_y: int = rom.u8(at + 1)
		var coord_x: int = rom.u8(at + 2)
		if not _valid_coord(coord_x, coord_y, cell_width, cell_height):
			return _error("Map %d/%d has an out-of-bounds coordinate event." % [group, number])
		coord_events.append({
			"scene": rom.u8(at),
			"x": coord_x,
			"y": coord_y,
			"script": rom.u16le(at + 4),
		})
		at += RomLayout.MAP_COORD_EVENT_SIZE

	var bg_events: Array = []
	if not rom.in_bounds(at):
		return _error("Map %d/%d has no background-event count." % [group, number])
	var bg_count: int = rom.u8(at)
	at += 1
	for _i: int in bg_count:
		if not rom.in_bounds(at, RomLayout.MAP_BG_EVENT_SIZE):
			return _error("Map %d/%d background events are truncated." % [group, number])
		var bg_y: int = rom.u8(at)
		var bg_x: int = rom.u8(at + 1)
		if not _valid_coord(bg_x, bg_y, cell_width, cell_height):
			return _error("Map %d/%d has an out-of-bounds background event." % [group, number])
		bg_events.append({
			"x": bg_x,
			"y": bg_y,
			"type": rom.u8(at + 2),
			"script": rom.u16le(at + 3),
		})
		at += RomLayout.MAP_BG_EVENT_SIZE

	var objects: Array = []
	if not rom.in_bounds(at):
		return _error("Map %d/%d has no object-event count." % [group, number])
	var object_count: int = rom.u8(at)
	at += 1
	for _i: int in object_count:
		if not rom.in_bounds(at, RomLayout.MAP_OBJECT_EVENT_SIZE):
			return _error("Map %d/%d object events are truncated." % [group, number])
		var object_y: int = rom.u8(at + 1) - 4
		var object_x: int = rom.u8(at + 2) - 4
		# Object templates may sit in the runtime's six-cell connection padding,
		# so unlike warps and coordinate events they are not constrained to the
		# map's interior dimensions.
		var radius: int = rom.u8(at + 4)
		var palette_type: int = rom.u8(at + 7)
		objects.append({
			"sprite": rom.u8(at),
			"x": object_x,
			"y": object_y,
			"movement": rom.u8(at + 3),
			"x_radius": radius & 0x0F,
			"y_radius": radius >> 4,
			"hour_1": rom.u8(at + 5),
			"hour_2": rom.u8(at + 6),
			"palette": palette_type >> 4,
			"object_type": palette_type & 0x0F,
			"sight_range": rom.u8(at + 8),
			"script": rom.u16le(at + 9),
			"event_flag": rom.u16le(at + 11),
		})
		at += RomLayout.MAP_OBJECT_EVENT_SIZE

	return {
		"ok": true,
		"warps": warps,
		"coord_events": coord_events,
		"bg_events": bg_events,
		"objects": objects,
	}


static func _valid_coord(x: int, y: int, width: int, height: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


static func _valid_cpu_address(address: int) -> bool:
	return address >= RomFile.BANK_SIZE and address < RomFile.BANK_SIZE * 2


static func _far_offset(rom: RomFile, pointer: Dictionary) -> int:
	var bank: int = int(pointer.get("bank", -1))
	var address: int = int(pointer.get("address", -1))
	if bank < 0 or address < RomFile.BANK_SIZE or address >= RomFile.BANK_SIZE * 2:
		return -1
	var offset: int = RomFile.linear(bank, address)
	return offset if rom.in_bounds(offset) else -1


static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}
