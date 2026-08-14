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

## `FillMapConnections` writes three blocks of padding on each side.
const PADDING: int = 3

var _failures: int = 0


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
		from_neighbour += neighbours
		if neighbours > 0:
			connected_maps += 1
	print("%-8s %d maps, %d blocks, %d padded blocks off a neighbour on %d maps" % [
		data.id, maps.size(), blocks, from_neighbour, connected_maps
	])
	if from_neighbour == 0:
		_failures += 1
		printerr("%-8s no padded block came off a neighbour, so the fold proved nothing" % data.id)
