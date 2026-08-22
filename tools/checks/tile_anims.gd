extends RefCounted

var _r: RefCounted = null

## Every tileset's `wTilesetAnim` command list, on all three cartridges, run for
## a whole cycle.
##
##   Godot --headless --path . -s res://tools/validate.gd -- tile_anims
##
## The list is `data/tileset_anims.asm` and the commands are
## `engine/tilesets/tileset_anims.asm`, both byte identical between the pins
## apart from the addresses `RomLayout`'s `world_animation_functions` names. What
## a reading of them costs is which command ticks `wTileAnimationTimer`:
## `StandingTileFrame8` and `StandingTileFrame` do, and so does
## `ScrollTileRightLeft`, which is the **only** tick the cave, dark cave and ice
## path lists have. A timer that never moves leaves those three maps with a still
## water palette, a still cave flicker and a tile scrolling one way for ever.
##
## `.claude/oracle/overworld/trace_tiles.py` and `tools/trace_world_tiles.gd` are
## the frame-by-frame half of this, against a real cartridge.

## The whole set `Gen2WorldAnimation.tick` implements, which is every label
## `_AnimateTileset` can `jp hl` to. An operation outside it is an unread
## function pointer rather than a new command.
const OPERATIONS: Array[String] = [
	"done", "wait", "timer_8", "timer", "water", "flower", "fountain",
	"forest_left", "forest_right", "forest_left_2", "forest_right_2",
	"lava_1", "lava_2", "tower", "whirlpool",
	"read_buffer", "write_buffer", "scroll_horizontal", "scroll_vertical",
	"water_palette", "cave_palette",
]

## The three that write `wTileAnimationTimer`: `StandingTileFrame8`,
## `StandingTileFrame` and `ScrollTileRightLeft`'s own `inc a / and %111`.
const TICKING: Array[String] = ["timer_8", "timer", "scroll_horizontal"]

## The commands that read it. A list holding one of these and no [constant
## TICKING] draws the same frame for ever, which is what the cave, the dark cave
## and the ice path did while `scroll_horizontal` was read as a plain rotate.
const READING: Array[String] = [
	"water", "flower", "fountain", "forest_left", "forest_right",
	"forest_left_2", "forest_right_2", "lava_1", "lava_2", "tower", "whirlpool",
	"scroll_horizontal", "water_palette",
]

## `ScrollTileRightLeft` and `ScrollTileDown` are handed `wTileAnimBuffer`, which
## is WRAM and not a tile, so the importer's own VRAM decode answers -1 for them.
const BUFFER_OPERAND: Array[String] = ["scroll_horizontal", "scroll_vertical"]

## `wTileAnimationTimer` is masked to three bits by every writer, so eight passes
## of any list is one whole cycle of everything it can draw.
const TIMER_VALUES: int = 8

## Census per cartridge, pinned so a cache or a table change is loud:
## tilesets, distinct command lists, lists that draw nothing but `done`,
## commands in all, and distinct tiles animated across the corpus.
const EXPECTED: Dictionary = {
	&"gold": [29, 8, 0, 246, 21],
	&"silver": [29, 8, 0, 246, 21],
	&"crystal": [37, 10, 0, 287, 21],
}


func run(r: RefCounted) -> void:
	_r = r
	_r.each_game(_check_game)


func _check_game() -> void:
	var lists: Dictionary = {}
	var commands: int = 0
	var still: int = 0
	var tiles: Dictionary = {}
	for number: int in _r.data.world_tileset_count():
		var tileset: Gen2WorldTileset = _r.data.world_tileset(number)
		if tileset == null:
			_r.fail("tileset %d is missing from the cache." % number)
			continue
		var list: Array = tileset.animation_commands
		commands += list.size()
		lists[_signature(list)] = true
		if list.size() <= 1:
			still += 1
		_check_list(number, list, tileset.tile_count)
		for tile: int in _check_cycle(tileset):
			tiles[tile] = true
	var census: Array = [
		_r.data.world_tileset_count(), lists.size(), still, commands, tiles.size(),
	]
	_r.note("tilesets %d, lists %d, still %d, commands %d, tiles animated %d" % census)
	var expected: Array = EXPECTED.get(_r.game_id, [])
	_r.check(
		expected.is_empty() or census == expected,
		"census is %s, pinned %s." % [census, expected],
	)


## The list's own shape, which is what `_AnimateTileset` walks: one terminator,
## at the end, every operation read, every tile inside the strip, and a tick
## somewhere, since a list with none freezes every timer-driven command in it.
func _check_list(number: int, list: Array, tiles_in_strip: int) -> void:
	if not _r.check(not list.is_empty(), "tileset %d has no command list." % number):
		return
	var ticks: int = 0
	var reads: int = 0
	for index: int in list.size():
		var command: Dictionary = list[index]
		var operation: String = String(command.get("operation", ""))
		_r.check(
			OPERATIONS.has(operation),
			"tileset %d command %d is %s, which nothing implements." % [
				number, index, operation,
			],
		)
		_r.check(
			(operation == "done") == (index == list.size() - 1),
			"tileset %d command %d is %s, so the list does not end on its own." % [
				number, index, operation,
			],
		)
		if TICKING.has(operation):
			ticks += 1
		if command.has("tile"):
			var tile: int = int(command["tile"])
			if BUFFER_OPERAND.has(operation):
				_r.check(
					tile == -1,
					"tileset %d command %d scrolls tile %d rather than the buffer." % [
						number, index, tile,
					],
				)
			else:
				_r.check(
					tile >= 0 and tile < tiles_in_strip,
					"tileset %d command %d names tile %d, outside the strip." % [
						number, index, tile,
					],
				)
		if READING.has(operation):
			reads += 1
	_r.check(
		reads == 0 or ticks > 0,
		"tileset %d reads the timer %d times and never ticks it." % [number, reads],
	)


## Eight passes of the list, which is one whole cycle of `wTileAnimationTimer`.
## Answers the tiles it rewrote. Two things are proved by running it rather than
## reading it: a list that draws at all visits every timer value, and the strip
## it leaves behind is the one it started from, since every scroll is a rotation
## and every other command writes a frame out of a cycle.
func _check_cycle(tileset: Gen2WorldTileset) -> PackedInt32Array:
	var animation := Gen2WorldAnimation.new()
	animation.configure_tileset(_r.data, tileset)
	var seen: Dictionary = {}
	var tiles: Dictionary = {}
	var opening := PackedByteArray()
	# Two cycles, and the first is a warm-up: a tileset's own tile stands until
	# the command that owns it writes for the first time, so the strip a list
	# returns to is the one after a whole cycle rather than the one on the map
	# load.
	for cycle: int in 2:
		if cycle == 1:
			opening = animation.current_indices().duplicate()
		for _pass: int in TIMER_VALUES:
			for _step: int in tileset.animation_commands.size():
				animation.advance_frame()
				seen[animation.timer() & 0x7] = true
				for tile: int in animation.changed_tiles():
					tiles[tile] = true
	if not tiles.is_empty():
		_r.check(
			seen.size() == TIMER_VALUES,
			"tileset %d drew %d tiles but its timer only reached %s." % [
				tileset.number, tiles.size(), seen.keys(),
			],
		)
		_r.check(
			animation.current_indices() == opening,
			"tileset %d does not return to its own strip after a whole cycle." % (
				tileset.number
			),
		)
	var out := PackedInt32Array()
	for tile: int in tiles:
		out.append(tile)
	return out


## A list as its operations, so two tilesets sharing one table count once.
func _signature(list: Array) -> String:
	var parts: PackedStringArray = []
	for command: Dictionary in list:
		parts.append("%s:%d" % [
			String(command.get("operation", "")), int(command.get("tile", -1)),
		])
	return ",".join(parts)
