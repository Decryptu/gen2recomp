extends RefCounted

var _r: RefCounted = null

## The drawn-block fold, from a map record rather than from a loaded world.
##
##   Godot --headless --path . -s res://tools/validate.gd -- drawn_blocks
##
## `Gen2WorldAPI.drawn_block_for` is what a caller with no world has: a battle
## staged on a map knows the map by number and never opens one. It has to be the
## same fold `drawn_block_at` performs, so this sweeps every map of every cache
## over its whole padded rectangle and refuses a single disagreement.
##
## The count of padded blocks that came from a neighbour rather than from the
## border block is reported per game, because two implementations that both
## answer the border block everywhere would agree and prove nothing.
##
## SCREEN FILL adds a second question to the same sweep, since it is the same
## fold one step further out. `expanded_block_at` places whole connected maps
## past the padding, and the two things that has to be true of it are checked
## here rather than photographed:
##
## - inside `wOverworldMapBlocks` it is `drawn_block_at`, byte for byte, so
##   nothing a 20x18 screen can reach moved;
## - where the padding took a block off a neighbour, the placed map answers the
##   same block, which is the seam being continuous rather than merely adjacent.

## `FillMapConnections` writes three blocks of padding on each side.
const PADDING: int = 3

var _failures: int = 0
## How many blocks each half of the expansion question was asked of, so a run
## that quietly stopped asking is visible.
var _buffer_agreed: int = 0
var _seam_agreed: int = 0


func run(r: RefCounted) -> void:
	_r = r
	for game: StringName in _r.GAME_IDS:
		var data: GameData = GameData.open(game)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game, game])
			continue
		_check_game(data)
	if _failures > 0:
		_r.fail("%d blocks disagreed with the fold from a map record alone." % _failures)
	if _buffer_agreed == 0 or _seam_agreed == 0:
		_r.fail("the expansion was never exercised: %d buffer blocks, %d seam blocks." % [
			_buffer_agreed, _seam_agreed
		])


func _check_game(data: GameData) -> void:
	var maps: Array = data.world_maps()
	var blocks: int = 0
	var from_neighbour: int = 0
	var connected_maps: int = 0
	for map: Gen2WorldMap in maps:
		var world: Gen2WorldAPI = Gen2WorldAPI.open(data, map.group, map.number, Vector2i.ZERO)
		if world == null:
			continue
		var neighbours: int = 0
		for block_y: int in range(-PADDING, map.height_blocks + PADDING):
			for block_x: int in range(-PADDING, map.width_blocks + PADDING):
				var loaded: int = world.drawn_block_at(block_x, block_y)
				var recorded: int = Gen2WorldAPI.drawn_block_for(data, map, block_x, block_y)
				blocks += 1
				if loaded != recorded:
					_failures += 1
					printerr("%-8s map %d/%d block (%d,%d): loaded %d, recorded %d" % [
						data.id, map.group, map.number, block_x, block_y, loaded, recorded
					])
					return
				var outside: bool = block_x < 0 or block_y < 0 \
					or block_x >= map.width_blocks or block_y >= map.height_blocks
				if outside and recorded != map.border_block:
					neighbours += 1
				## Inside the buffer the expansion is the fold itself.
				if world.expanded_block_at(block_x, block_y) != loaded:
					_failures += 1
					printerr("%-8s map %d/%d block (%d,%d): expanded %d, drawn %d" % [
						data.id, map.group, map.number, block_x, block_y,
						world.expanded_block_at(block_x, block_y), loaded,
					])
					return
				_buffer_agreed += 1
		from_neighbour += neighbours
		_check_seams(data, map, world)
		if neighbours > 0:
			connected_maps += 1
	print("%-8s %d maps, %d blocks, %d padded blocks off a neighbour on %d maps, %d seam blocks" % [
		data.id, maps.size(), blocks, from_neighbour, connected_maps, _seam_agreed
	])
	if from_neighbour == 0:
		_failures += 1
		printerr("%-8s no padded block came off a neighbour, so the fold proved nothing" % data.id)


## Every padding block the connection strips filled, against the whole map the
## placement graph puts there. `FillMapConnections` writes the strip from a
## pointer sum and [method Gen2WorldAPI.connection_origin_blocks] places the map
## from the same one, so a disagreement is a seam a filled screen would show as
## a step in the ground.
func _check_seams(data: GameData, map: Gen2WorldMap, world: Gen2WorldAPI) -> void:
	var placements: Dictionary = Gen2WorldAPI.placements_around(data, map, 1)
	for block_y: int in range(-PADDING, map.height_blocks + PADDING):
		for block_x: int in range(-PADDING, map.width_blocks + PADDING):
			if block_x >= 0 and block_y >= 0 \
				and block_x < map.width_blocks and block_y < map.height_blocks:
				continue
			var strip: int = world.drawn_block_at(block_x, block_y)
			if strip == map.border_block:
				continue
			for placement: Dictionary in placements.values():
				var near: Gen2WorldMap = placement["map"]
				var origin: Vector2i = placement["origin"]
				var local := Vector2i(block_x - origin.x, block_y - origin.y)
				if local.x < 0 or local.y < 0 \
					or local.x >= near.width_blocks or local.y >= near.height_blocks:
					continue
				var placed: int = Gen2WorldAPI.drawn_block_for(data, near, local.x, local.y)
				if placed != strip:
					_failures += 1
					printerr("%-8s map %d/%d block (%d,%d): strip %d, %d/%d says %d" % [
						data.id, map.group, map.number, block_x, block_y, strip,
						near.group, near.number, placed,
					])
					return
				_seam_agreed += 1
				break
