class_name Gen2WorldImporter
extends RefCounted

const OBJECTTYPE_TRAINER: int = 2
const TRAINER_RECORD_SIZE: int = 12

## Imports the map table, map attributes, map events, tileset tables, overworld
## object graphics and addressable overworld tile strips for a verified
## Generation 2 cartridge.
##
## Follows the official map macros and the runtime collision lookup: map blocks
## are 4x4 graphics tiles, walk coordinates 2x2 cells per block, and collision
## bytes use x as the low bit and y as the high bit.

static func verify_layout(rom: RomFile) -> Dictionary:
	var result: Dictionary = read_world(rom, RomLayout.for_id(rom.id))
	if not bool(result.get("ok", false)):
		return {"ok": false, "message": String(result.get("message", "World data failed validation."))}
	return {"ok": true, "message": ""}


## Adds one bounded script and every reference that the shared command scanner
## can prove from it. Service tables use this same collector so phone scripts
## enter the cache alongside map and standard scripts.
static func collect_script(
	rom: RomFile,
	bank: int,
	address: int,
	script_data: Dictionary,
	text_data: Dictionary = {},
	movement_data: Dictionary = {},
) -> void:
	_collect_script(rom, bank, address, script_data, text_data, movement_data)


static func import_to_cache(
	rom: RomFile, layout: Dictionary, directory: String, on_progress: Callable = Callable()
) -> Dictionary:
	var result: Dictionary = read_world(rom, layout, on_progress)
	if not bool(result.get("ok", false)):
		return result

	var tilesets: Array = result["tilesets"]
	if not RomCache.write_json(RomCache.overworld_sprites_path(directory), result["sprites"]):
		return {"ok": false, "message": "Could not write overworld sprite data."}
	if not RomCache.write_json(
		RomCache.overworld_sprite_palettes_path(directory), result["sprite_palettes"]
	):
		return {"ok": false, "message": "Could not write overworld sprite palettes."}
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
	if not RomCache.write_payload_map(
		RomCache.world_scripts_path(directory),
		RomCache.blob_path(RomCache.world_scripts_path(directory)),
		result["scripts"],
	):
		return {"ok": false, "message": "Could not write overworld script data."}
	if not RomCache.write_section(
		RomCache.world_standard_scripts_path(directory),
		RomCache.blob_path(RomCache.world_standard_scripts_path(directory)),
		result["standard_scripts"],
	):
		return {"ok": false, "message": "Could not write standard overworld script data."}
	if not RomCache.write_payload_map(
		RomCache.world_text_path(directory),
		RomCache.blob_path(RomCache.world_text_path(directory)),
		result["text"],
	):
		return {"ok": false, "message": "Could not write overworld text data."}
	if not RomCache.write_payload_map(
		RomCache.world_movements_path(directory),
		RomCache.blob_path(RomCache.world_movements_path(directory)),
		result["movements"],
	):
		return {"ok": false, "message": "Could not write overworld movement data."}

	var graphics: Dictionary = result["graphics"]
	for number: int in graphics:
		if not RomCache.write_indices(RomCache.world_tile_path(directory, number), graphics[number]):
			return {"ok": false, "message": "Could not write overworld tileset %d." % number}

	var sprite_graphics: Dictionary = result["sprite_graphics"]
	for number: int in sprite_graphics:
		if not RomCache.write_indices(
			RomCache.overworld_sprite_path(directory, number), sprite_graphics[number]
		):
			return {"ok": false, "message": "Could not write overworld sprite %d." % number}

	return {
		"ok": true,
		"maps": result["maps"].size(),
		"tilesets": tilesets.size(),
		"overworld_sprites": result["sprites"].size(),
		# The service importer scans and extends these. Handing back what was
		# just decoded keeps them raw byte runs; reading them off disk again
		# would hand it the spans the cache stores instead.
		"scripts": result["scripts"],
		"standard_scripts": result["standard_scripts"],
		"text": result["text"],
		"movements": result["movements"],
	}


static func read_world(
	rom: RomFile, layout: Dictionary, on_progress: Callable = Callable()
) -> Dictionary:
	if layout.is_empty():
		return {"ok": false, "message": "No world layout for %s." % rom.id}

	var sprites: Dictionary = _read_overworld_sprites(rom, layout)
	if not bool(sprites.get("ok", false)):
		return sprites

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
	var script_data: Dictionary = {}
	var text_data: Dictionary = {}
	var movement_data: Dictionary = {}
	for group: int in range(1, RomLayout.MAP_GROUP_COUNT + 1):
		var pointer_offset: int = RomLayout.map_group_pointer_offset(layout, group)
		if not rom.in_bounds(pointer_offset, RomLayout.MAP_GROUP_POINTER_SIZE):
			return _error("Map group %d pointer is outside the ROM." % group)
		var group_pointer: int = rom.u16le(pointer_offset)
		if not _valid_cpu_address(group_pointer):
			return _error("Map group %d starts at invalid address $%04X." % [group, group_pointer])

		var group_count: int = RomLayout.map_group_count(layout, group)
		for number: int in range(1, group_count + 1):
			var map_result: Dictionary = _read_map(
				rom, layout, tilesets, group, number, group_pointer,
				script_data, text_data, movement_data
			)
			if not bool(map_result.get("ok", false)):
				return map_result
			map_result.erase("ok")
			maps.append(map_result)
			if on_progress.is_valid():
				on_progress.call("world_maps", maps.size(), RomLayout.map_count(layout))

	var standard_result: Dictionary = _read_standard_scripts(
		rom, script_data, text_data, movement_data
	)
	if not bool(standard_result.get("ok", false)):
		return standard_result

	return {
		"ok": true,
		"maps": maps,
		"scripts": script_data,
		"standard_scripts": standard_result["scripts"],
		"text": text_data,
		"movements": movement_data,
		"tilesets": tilesets,
		"graphics": graphics,
		"palettes": palettes["groups"],
		"animation_assets": animation_assets["assets"],
		"sprites": sprites["sprites"],
		"sprite_palettes": sprites["palettes"],
		"sprite_graphics": sprites["graphics"],
	}


## JUMPSTD and CALLSTD address a profile-specific far-pointer table. These
## locations and counts come from the verified cartridge layouts, not from a
## scan for plausible pointers.
static func _read_standard_scripts(
	rom: RomFile, script_data: Dictionary, text_data: Dictionary, movement_data: Dictionary
) -> Dictionary:
	var bank: int = 0x2F if rom.id == &"crystal" else 0x40
	var count: int = 52 if rom.id == &"crystal" else 46
	var table_offset: int = RomFile.linear(bank, RomFile.BANK_SIZE)
	if not rom.in_bounds(table_offset, count * 3):
		return _error("Standard-script table is outside the cartridge.")

	var scripts: Dictionary = {}
	for index: int in count:
		var at: int = table_offset + index * 3
		var target_bank: int = rom.u8(at)
		var target_address: int = rom.u16le(at + 1)
		if _far_offset(rom, {"bank": target_bank, "address": target_address}) < 0:
			return _error("Standard script %d has an invalid far pointer." % index)
		_collect_script(
			rom, target_bank, target_address, script_data, text_data, movement_data
		)
		var target_offset: int = _far_offset(
			rom, {"bank": target_bank, "address": target_address}
		)
		var length: int = mini(Gen2WorldScript.MAX_SCRIPT_BYTES, rom.size() - target_offset)
		var raw: PackedByteArray = rom.slice(target_offset, length)
		if raw.is_empty():
			return _error("Standard script %d is empty." % index)
		scripts[str(index)] = {
			"bank": target_bank,
			"address": target_address,
			"bytes": Array(raw),
		}
	return {"ok": true, "scripts": scripts}


## The cartridge stores these graphics as raw 2bpp tile strips. The table is
## independent of map objects: an object event's sprite byte indexes it, while
## the event supplies its movement, visibility and optional palette override.
static func _read_overworld_sprites(rom: RomFile, layout: Dictionary) -> Dictionary:
	var count: int = RomLayout.overworld_sprite_count(layout)
	var table: int = int(layout.get("overworld_sprites", -1))
	if count <= 0 or not rom.in_bounds(table, count * RomLayout.OVERWORLD_SPRITE_RECORD_SIZE):
		return _error("Overworld sprite table is outside the cartridge.")

	var palette_offset: int = int(layout.get("overworld_sprite_palettes", -1))
	if not rom.in_bounds(palette_offset, RomLayout.OVERWORLD_SPRITE_PALETTE_BYTES):
		return _error("Overworld sprite palettes are outside the cartridge.")

	var palettes: Array = []
	for group: int in RomLayout.OVERWORLD_SPRITE_PALETTE_GROUP_COUNT:
		var colors: Array = []
		for color: int in 4:
			var at: int = palette_offset + group * RomLayout.OVERWORLD_SPRITE_PALETTE_GROUP_BYTES + color * 2
			var packed: int = rom.u16le(at)
			if packed & 0x8000:
				return _error("Overworld sprite palette %d has bit 15 set." % group)
			colors.append(packed)
		palettes.append(colors)

	# The first palette row is the source's red overworld palette. It is a
	# stable content check for the palette table because a nearby table still
	# yields legal 15-bit colours.
	var first_palette: Array = palettes[0]
	if first_palette != [0x43FC, 0x2A7F, 0x04FF, 0x0000]:
		return _error("Overworld sprite palette table does not start with red.")

	var sprites: Array = []
	var graphics: Dictionary = {}
	for number: int in range(1, count + 1):
		var at: int = RomLayout.overworld_sprite_offset(layout, number)
		var address: int = rom.u16le(at)
		var byte_size: int = rom.u8(at + 2)
		var bank: int = rom.u8(at + 3)
		var sprite_type: int = rom.u8(at + 4)
		var default_palette: int = rom.u8(at + 5)
		if address < RomFile.BANK_SIZE or address >= RomFile.BANK_SIZE * 2:
			return _error("Overworld sprite %d has an invalid CPU address." % number)
		if byte_size <= 0 or byte_size % Gen2Tiles.TILE_BYTES != 0:
			return _error("Overworld sprite %d has an invalid byte length." % number)
		if sprite_type not in RomLayout.OVERWORLD_SPRITE_TYPES:
			return _error("Overworld sprite %d has unknown type %d." % [number, sprite_type])
		if default_palette < 0 or default_palette >= RomLayout.OVERWORLD_SPRITE_PALETTE_COUNT:
			return _error("Overworld sprite %d has palette %d." % [number, default_palette])

		var graphics_offset: int = RomFile.linear(bank, address)
		var raw: PackedByteArray = rom.slice(graphics_offset, byte_size)
		if raw.size() != byte_size:
			return _error("Overworld sprite %d graphics are truncated." % number)
		var tiles: int = floori(float(byte_size) / float(Gen2Tiles.TILE_BYTES))
		var pixels: PackedByteArray = Gen2Tiles.decode_2bpp_strip(raw, 0, tiles)
		if pixels.size() != tiles * Gen2Tiles.TILE_PIXELS:
			return _error("Overworld sprite %d graphics did not decode." % number)
		graphics[number] = pixels
		sprites.append({
			"number": number,
			"address": address,
			"bank": bank,
			"bytes": byte_size,
			"tiles": tiles,
			"type": sprite_type,
			"palette": default_palette,
		})

	return {"ok": true, "sprites": sprites, "palettes": palettes, "graphics": graphics}


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
	return floori(float(address - 0x9000) / float(Gen2Tiles.TILE_BYTES))


static func _animation_asset_index(_rom: RomFile, layout: Dictionary, operation: String, pointer: int) -> int:
	var name: String = "tower" if operation == "tower" else "whirlpool"
	var spec: Dictionary = layout["world_animation_assets"][name]
	var base: int = int(spec["offset"])
	var stride: int = 80 if name == "tower" else 64
	var offset: int = RomFile.linear(RomLayout.WORLD_ANIMATION_BANK, pointer)
	var delta: int = offset - base
	if delta < 0 or delta % stride != 0 or delta >= int(spec["bytes"]):
		return -1
	return floori(float(delta) / float(stride))


static func _read_map(
	rom: RomFile,
	layout: Dictionary,
	tilesets: Array,
	group: int,
	number: int,
	group_pointer: int,
	script_data: Dictionary,
	text_data: Dictionary,
	movement_data: Dictionary,
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

	var connection_flags: int = rom.u8(attributes + 11)
	if (connection_flags & 0xF0) != 0:
		return _error("Map %d/%d has undefined connection flags $%02X." % [group, number, connection_flags])
	var connections: Array = _read_connections(
		rom, layout, attributes + RomLayout.MAP_ATTRIBUTES_SIZE, connection_flags
	)
	if connections.is_empty() and connection_flags != 0:
		return _error("Map %d/%d connection records are truncated or invalid." % [group, number])

	var event_result: Dictionary = _read_events(
		rom, scripts_bank, events_address, group, number, width * 2, height * 2
	)
	if not bool(event_result.get("ok", false)):
		return event_result

	var scripts_result: Dictionary = _read_map_scripts(
		rom, scripts_bank, scripts_address, group, number,
		script_data, text_data, movement_data
	)
	if not bool(scripts_result.get("ok", false)):
		return scripts_result
	for source: String in ["coord_events", "bg_events", "objects"]:
		for event: Dictionary in event_result[source]:
			if source == "objects" and event.has("trainer"):
				var trainer: Dictionary = event.get("trainer", {})
				_collect_script(
					rom, scripts_bank, int(trainer.get("after_script", 0)),
					script_data, text_data, movement_data
				)
				for text_key: String in ["seen_text", "win_text", "loss_text"]:
					var text_pointer: Dictionary = trainer.get(text_key, {})
					_collect_text(
						rom, int(text_pointer.get("bank", scripts_bank)),
						int(text_pointer.get("address", 0)), text_data
					)
				continue
			_collect_script(
				rom, scripts_bank, int(event.get("script", 0)),
				script_data, text_data, movement_data
			)

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
		"connection_flags": connection_flags,
		"connections": connections,
		"scripts": {
			"bank": scripts_bank,
			"address": scripts_address,
			"scenes": scripts_result["scenes"],
			"callbacks": scripts_result["callbacks"],
		},
		"events": {
			"bank": scripts_bank,
			"address": events_address,
			"warps": event_result["warps"],
			"coord_events": event_result["coord_events"],
			"bg_events": event_result["bg_events"],
			"objects": event_result["objects"],
		},
	}


static func _read_connections(
	rom: RomFile, layout: Dictionary, at: int, connection_flags: int
) -> Array:
	var out: Array = []
	# The cartridge emits connection records in this order, regardless of which
	# direction bits are present: north, south, west, east.
	var directions: Array = [
		["north", RomLayout.MAP_CONNECTION_FLAG_NORTH],
		["south", RomLayout.MAP_CONNECTION_FLAG_SOUTH],
		["west", RomLayout.MAP_CONNECTION_FLAG_WEST],
		["east", RomLayout.MAP_CONNECTION_FLAG_EAST],
	]
	for direction: Array in directions:
		var name: String = String(direction[0])
		var flag: int = int(direction[1])
		if (connection_flags & flag) == 0:
			continue
		if not rom.in_bounds(at, RomLayout.MAP_CONNECTION_RECORD_SIZE):
			return []
		var map_group: int = rom.u8(at)
		var map_number: int = rom.u8(at + 1)
		if map_group <= 0 or map_group > RomLayout.MAP_GROUP_COUNT \
			or map_number <= 0 or map_number > RomLayout.map_group_count(layout, map_group):
			return []
		out.append({
			"direction": name,
			"map_group": map_group,
			"map_number": map_number,
			"target_block_pointer": rom.u16le(at + 2),
			"map_pointer": rom.u16le(at + 4),
			"length": rom.u8(at + 6),
			"target_width_blocks": rom.u8(at + 7),
			"y_offset": _signed_byte(rom.u8(at + 8)),
			"x_offset": _signed_byte(rom.u8(at + 9)),
			"window_pointer": rom.u16le(at + 10),
		})
		at += RomLayout.MAP_CONNECTION_RECORD_SIZE
	return out


static func _signed_byte(value: int) -> int:
	return value - 0x100 if (value & 0x80) != 0 else value


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
		var hour_1: int = rom.u8(at + 5)
		var hour_2: int = rom.u8(at + 6)
		# The source macro writes -1 as $FF to select the time-of-day mask in
		# hour_2. Preserve that sentinel as a signed value in the cache.
		if hour_1 == 0xFF:
			hour_1 = -1
		if hour_2 == 0xFF:
			hour_2 = -1
		var event_flag: int = rom.u16le(at + 11)
		if event_flag == 0xFFFF:
			event_flag = -1
		var object_type: int = palette_type & 0x0F
		var object_script: int = rom.u16le(at + 9)
		var trainer: Dictionary = {}
		if object_type == OBJECTTYPE_TRAINER:
			trainer = _read_trainer_record(rom, bank, object_script)
		var object: Dictionary = {
			"sprite": rom.u8(at),
			"x": object_x,
			"y": object_y,
			"movement": rom.u8(at + 3),
			"x_radius": radius & 0x0F,
			"y_radius": radius >> 4,
			"hour_1": hour_1,
			"hour_2": hour_2,
			"palette": palette_type >> 4,
			"object_type": object_type,
			"sight_range": rom.u8(at + 8),
			"script": object_script,
			"event_flag": event_flag,
		}
		if not trainer.is_empty():
			object["trainer"] = trainer
		objects.append(object)
		at += RomLayout.MAP_OBJECT_EVENT_SIZE

	return {
		"ok": true,
		"warps": warps,
		"coord_events": coord_events,
		"bg_events": bg_events,
		"objects": objects,
}


## Decodes the source trainer macro referenced by an OBJECTTYPE_TRAINER event.
## The object pointer is not executable script: it names a 12-byte record whose
## final pointer enters the trainer's after-battle script.
static func _read_trainer_record(rom: RomFile, bank: int, address: int) -> Dictionary:
	var offset: int = _far_offset(rom, {"bank": bank, "address": address})
	if offset < 0 or not rom.in_bounds(offset, TRAINER_RECORD_SIZE):
		return {}
	var event_flag: int = rom.u16le(offset)
	if event_flag == 0xFFFF:
		event_flag = -1
	return {
		"event_flag": event_flag,
		"trainer_group": rom.u8(offset + 2),
		"trainer_id": rom.u8(offset + 3),
		"seen_text": {"bank": bank, "address": rom.u16le(offset + 4)},
		"win_text": {"bank": bank, "address": rom.u16le(offset + 6)},
		"loss_text": {"bank": bank, "address": rom.u16le(offset + 8)},
		"after_script": address + TRAINER_RECORD_SIZE,
	}


static func _read_map_scripts(
	rom: RomFile,
	bank: int,
	address: int,
	group: int,
	number: int,
	script_data: Dictionary,
	text_data: Dictionary,
	movement_data: Dictionary,
) -> Dictionary:
	var at: int = _far_offset(rom, {"bank": bank, "address": address})
	if at < 0 or not rom.in_bounds(at):
		return _error("Map %d/%d scripts are outside the ROM." % [group, number])

	var scene_count: int = rom.u8(at)
	if scene_count > RomLayout.MAP_MAX_SCENE_SCRIPTS:
		return _error("Map %d/%d has %d scene scripts." % [group, number, scene_count])
	at += 1
	var scenes: Array = []
	for scene: int in scene_count:
		if not rom.in_bounds(at, RomLayout.MAP_SCENE_SCRIPT_SIZE):
			return _error("Map %d/%d scene scripts are truncated." % [group, number])
		var script_address: int = rom.u16le(at)
		scenes.append({"id": scene, "script": script_address})
		_collect_script(rom, bank, script_address, script_data, text_data, movement_data)
		at += RomLayout.MAP_SCENE_SCRIPT_SIZE

	if not rom.in_bounds(at):
		return _error("Map %d/%d has no callback count." % [group, number])
	var callback_count: int = rom.u8(at)
	if callback_count > RomLayout.MAP_MAX_CALLBACKS:
		return _error("Map %d/%d has %d callbacks." % [group, number, callback_count])
	at += 1
	var callbacks: Array = []
	for _callback: int in callback_count:
		if not rom.in_bounds(at, RomLayout.MAP_CALLBACK_SIZE):
			return _error("Map %d/%d callbacks are truncated." % [group, number])
		var callback_type: int = rom.u8(at)
		var script_address: int = rom.u16le(at + 1)
		callbacks.append({"type": callback_type, "script": script_address})
		_collect_script(rom, bank, script_address, script_data, text_data, movement_data)
		at += RomLayout.MAP_CALLBACK_SIZE

	return {"ok": true, "scenes": scenes, "callbacks": callbacks}


static func _collect_script(
	rom: RomFile,
	bank: int,
	address: int,
	script_data: Dictionary,
	text_data: Dictionary,
	movement_data: Dictionary,
) -> void:
	if address < RomFile.BANK_SIZE or address >= RomFile.BANK_SIZE * 2:
		return
	var key: String = Gen2WorldScript.pointer_key(bank, address)
	if script_data.has(key):
		return
	var offset: int = _far_offset(rom, {"bank": bank, "address": address})
	if offset < 0:
		return
	var length: int = mini(Gen2WorldScript.MAX_SCRIPT_BYTES, rom.size() - offset)
	var bytes: PackedByteArray = rom.slice(offset, length)
	if bytes.is_empty():
		return
	script_data[key] = Array(bytes)
	var references: Dictionary = Gen2WorldScript.scan_references(
		bytes, bank, address, rom.id == &"crystal"
	)
	for script_reference: Dictionary in references.get("scripts", []):
		_collect_script(
			rom, int(script_reference.get("bank", bank)), int(script_reference.get("address", 0)),
			script_data, text_data, movement_data
		)
	for text_reference: Dictionary in references.get("texts", []):
		_collect_text(
			rom, int(text_reference.get("bank", bank)), int(text_reference.get("address", 0)), text_data
		)
	for movement_reference: Dictionary in references.get("movements", []):
		_collect_movement(
			rom, int(movement_reference.get("bank", bank)), int(movement_reference.get("address", 0)), movement_data
		)


static func _collect_movement(
	rom: RomFile, bank: int, address: int, movement_data: Dictionary
) -> void:
	if address < RomFile.BANK_SIZE or address >= RomFile.BANK_SIZE * 2:
		return
	var key: String = Gen2WorldScript.pointer_key(bank, address)
	if movement_data.has(key):
		return
	var offset: int = _far_offset(rom, {"bank": bank, "address": address})
	if offset < 0:
		return
	var bytes: PackedByteArray = rom.slice(
		offset, mini(Gen2WorldMovement.MAX_BYTES, rom.size() - offset)
	)
	var decoded: Dictionary = Gen2WorldMovement.decode(bytes)
	if not bool(decoded.get("ok", false)):
		return
	movement_data[key] = Array(bytes.slice(0, int(decoded.get("bytes", bytes.size()))))


static func _collect_text(rom: RomFile, bank: int, address: int, text_data: Dictionary) -> void:
	if address < RomFile.BANK_SIZE or address >= RomFile.BANK_SIZE * 2:
		return
	var key: String = Gen2WorldScript.pointer_key(bank, address)
	if text_data.has(key):
		return
	var offset: int = _far_offset(rom, {"bank": bank, "address": address})
	if offset < 0:
		return
	var length: int = mini(Gen2WorldScript.MAX_TEXT_BYTES, rom.size() - offset)
	var bytes: PackedByteArray = rom.slice(offset, length)
	if bytes.is_empty():
		return
	# World text is a command stream, not a fixed-width name field. $50 is a
	# page control; the source $57 done command is the bounded text resource end.
	for index: int in bytes.size():
		if bytes[index] != Gen2WorldScript.TEXT_TERMINATOR \
			and bytes[index] != Gen2WorldScript.TEXT_PROMPT:
			continue
		text_data[key] = Array(bytes.slice(0, index + 1))
		return
	# Preserve an unterminated bounded slice for diagnostics. Runtime decoding
	# still fails explicitly instead of reading into an adjacent resource.
	text_data[key] = Array(bytes)


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
