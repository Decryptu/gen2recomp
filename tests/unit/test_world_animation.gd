extends GutTest

## Animation tests run against a cache-shaped fixture. The real cartridge import
## is covered by the ROM tool; this keeps the runtime interpreter fast and
## deterministic in the unit suite.

var _directory: String = ""

## `constants/tileset_constants.asm`: `TILESET_JOHTO` is one of the three
## `home/map.asm` gates `LoadMapGroupRoof` on. `TILESET_KANTO` is not, and it is
## the outdoor counter-example: Kanto's roofs are its tileset's own art.
const ROOFED_TILESET: int = 0x01
const UNROOFED_TILESET: int = 0x03


func before_each() -> void:
	_directory = RomCache.directory_for(&"testanimation", "fedcba9876543210")
	RomCache.clear(_directory)
	RomCache.prepare(_directory)
	_write_cache()


func after_each() -> void:
	RomCache.clear(_directory)


func _write_cache() -> void:
	for path: String in [
		RomCache.species_path(_directory), RomCache.moves_path(_directory),
		RomCache.items_path(_directory), RomCache.types_path(_directory),
		RomCache.matchups_path(_directory), RomCache.trainers_path(_directory),
	]:
		RomCache.write_json(path, [])

	var meta: Array = []
	for _index: int in 16:
		meta.append(0)
	RomCache.write_json(RomCache.world_tilesets_path(_directory), [{
		"number": 0,
		"block_count": 1,
		"tile_count": RomLayout.TILESET_TILE_COUNT,
		"meta": meta,
		"collision": [],
		"palette_map": [0],
		"animation_commands": [
			{"operation": "water", "tile": 0},
			{"operation": "done"},
		],
	}, {
		# The same tile animated properly: a timer bump per pass, so the water
		# command walks all four frames of the asset instead of standing on the
		# first. What tile_frames() has to recover.
		"number": 1,
		"block_count": 1,
		"tile_count": RomLayout.TILESET_TILE_COUNT,
		"meta": meta,
		"collision": [],
		"palette_map": [0],
		"animation_commands": [
			{"operation": "timer_8"},
			{"operation": "water", "tile": 0},
			{"operation": "done"},
		],
	}, {
		# `TilesetForestAnim`'s own four tree commands, in its order: the pair
		# and then the pair the source offsets by a frame, with the timer bump
		# after both so all four see the same `wTileAnimationTimer`.
		"number": 2,
		"block_count": 1,
		"tile_count": RomLayout.TILESET_TILE_COUNT,
		"meta": meta,
		"collision": [],
		"palette_map": [0],
		"animation_commands": [
			{"operation": "forest_left"},
			{"operation": "forest_right"},
			{"operation": "forest_left_2"},
			{"operation": "forest_right_2"},
			{"operation": "timer_8"},
			{"operation": "done"},
		],
	}, {
		# `TilesetCaveAnim` with tiles 0 and 1 standing in for $14 and $40. Its
		# only tick is `ScrollTileRightLeft`'s own, which is what the water
		# palette, the flicker and both scrolls hang off.
		"number": 3,
		"block_count": 1,
		"tile_count": RomLayout.TILESET_TILE_COUNT,
		"meta": meta,
		"collision": [],
		"palette_map": [0],
		"animation_commands": [
			{"operation": "read_buffer", "tile": 0},
			{"operation": "cave_palette"},
			{"operation": "scroll_horizontal", "tile": -1},
			{"operation": "cave_palette"},
			{"operation": "write_buffer", "tile": 0},
			{"operation": "cave_palette"},
			{"operation": "water_palette"},
			{"operation": "cave_palette"},
			{"operation": "read_buffer", "tile": 1},
			{"operation": "cave_palette"},
			{"operation": "scroll_vertical", "tile": -1},
			{"operation": "cave_palette"},
			{"operation": "scroll_vertical", "tile": -1},
			{"operation": "cave_palette"},
			{"operation": "scroll_vertical", "tile": -1},
			{"operation": "cave_palette"},
			{"operation": "write_buffer", "tile": 1},
			{"operation": "cave_palette"},
			{"operation": "done"},
		],
	}])
	RomCache.write_json(RomCache.world_maps_path(_directory), [{
		"group": 1,
		"number": 1,
		"tileset": 0,
		"environment": 0,
		"width_blocks": 1,
		"height_blocks": 1,
		"blocks": [0],
		"collision": [0, 0, 0, 0],
		"collision_width": 2,
		"collision_height": 2,
	}, {
		"group": 1,
		"number": 3,
		"tileset": 2,
		"environment": 0,
		"width_blocks": 1,
		"height_blocks": 1,
		"blocks": [0],
		"collision": [0, 0, 0, 0],
		"collision_width": 2,
		"collision_height": 2,
	}, {
		"group": 1,
		"number": 4,
		"tileset": 3,
		"environment": 0,
		"width_blocks": 1,
		"height_blocks": 1,
		"blocks": [0],
		"collision": [0, 0, 0, 0],
		"collision_width": 2,
		"collision_height": 2,
	}, {
		"group": 1,
		"number": 2,
		"tileset": 1,
		"environment": 0,
		"width_blocks": 1,
		"height_blocks": 1,
		"blocks": [0],
		"collision": [0, 0, 0, 0],
		"collision_width": 2,
		"collision_height": 2,
	}])
	var pixels := PackedByteArray()
	pixels.resize(RomLayout.TILESET_TILE_COUNT * Gen2Tiles.TILE_PIXELS)
	RomCache.write_indices(RomCache.world_tile_path(_directory, 0), pixels)
	RomCache.write_indices(RomCache.world_tile_path(_directory, 1), pixels)
	RomCache.write_indices(RomCache.world_tile_path(_directory, 2), pixels)
	# One lit pixel in the top-left corner of tiles 0 and 1, so where the two
	# scrolls put it is the whole reading of their direction.
	var scrolled: PackedByteArray = pixels.duplicate()
	scrolled[0] = 1
	scrolled[Gen2Tiles.TILE_WIDTH] = 1
	RomCache.write_indices(RomCache.world_tile_path(_directory, 3), scrolled)

	var palettes: Array = []
	for _group: int in RomLayout.WORLD_PALETTE_GROUP_COUNT:
		palettes.append([0x7FFF, 0x421F, 0x2108, 0])
	RomCache.write_json(RomCache.world_palettes_path(_directory), palettes)

	var water: Array = []
	water.resize(64)
	for index: int in water.size():
		water[index] = 0
	# Frame 0 is a solid low plane; the other three are one, two and three lit
	# rows, so the four frames are told apart by their contents.
	for y: int in 8:
		water[y * 2] = 0xFF
	for frame: int in range(1, 4):
		for y: int in frame:
			water[frame * 16 + y * 2] = 0xFF
	# `ForestTreeLeftFrames` and `ForestTreeRightFrames`, four tiles in a row,
	# each filled with its own index so a written tile names the frame it came
	# from: 1 and 2 are the left tree's, 3 and 4 the right tree's.
	var forest: Array = []
	forest.resize(64)
	for index: int in forest.size():
		forest[index] = 0
	for tile: int in 4:
		for y: int in 8:
			forest[tile * 16 + y * 2] = 0xFF if (tile & 1) == 0 else 0
			forest[tile * 16 + y * 2 + 1] = 0xFF if (tile & 1) == 1 else 0
	RomCache.write_json(
		RomCache.world_animation_assets_path(_directory), {"water": water, "forest": forest}
	)
	# Two roofs of nine tiles each, every pixel carrying its own roof number, and
	# a group table naming one, the other and none.
	var roof_tiles: Array = []
	for roof: int in 2:
		var run: Array = []
		run.resize(RomLayout.ROOF_TILES * Gen2Tiles.TILE_PIXELS)
		for index: int in run.size():
			run[index] = roof + 1
		roof_tiles.append(run)
	var roof_groups: Array = [0, 1, 0xFF]
	var roof_palettes: Array = []
	for group: int in roof_groups.size():
		roof_palettes.append([
			0x0001 + group, 0x0002 + group, 0x0003 + group, 0x0004 + group,
		])
	RomCache.write_json(RomCache.world_roofs_path(_directory), {
		"groups": roof_groups, "tiles": roof_tiles, "palettes": roof_palettes,
	})
	RomCache.write_json(RomCache.manifest_path(_directory), {
		"format_version": RomCache.FORMAT_VERSION,
		"game_id": "testanimation",
		"sha1": "fedcba9876543210",
		"complete": true,
	})


func test_water_command_writes_the_imported_frame_and_done_loops() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i.ZERO)
	var animation := Gen2WorldAnimation.new()
	animation.configure(world)

	assert_true(animation.tick())
	assert_eq(animation.current_indices()[0], 1)
	assert_eq(animation.current_indices()[7], 1)
	assert_true(animation.tick())
	assert_true(animation.tick())
	assert_eq(animation.current_indices()[0], 1)


func test_advance_frame_reports_no_redraw_when_the_command_changes_nothing() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i.ZERO)
	var animation := Gen2WorldAnimation.new()
	animation.configure(world)

	assert_true(animation.advance_frame())
	# "done" only rewinds the command index, so nothing new is drawn and the
	# renderer must not rebuild its atlas for it.
	assert_false(animation.advance_frame())
	# The water command runs again, but writes the frame that is already there.
	assert_false(animation.advance_frame())


func test_changed_tiles_reports_exactly_the_tiles_a_frame_rewrote() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i.ZERO)
	var animation := Gen2WorldAnimation.new()
	animation.configure(world)

	# A renderer repaints only the reported tiles, so an under-report leaves a
	# stale tile on screen and an over-report costs the work this replaced.
	for _frame: int in 240:
		var before: PackedByteArray = animation.current_indices().duplicate()
		var redraw: bool = animation.advance_frame()
		var after: PackedByteArray = animation.current_indices()
		var actually_changed: Array = []
		var width: int = RomLayout.TILESET_TILE_COUNT * Gen2Tiles.TILE_WIDTH
		for tile: int in RomLayout.TILESET_TILE_COUNT:
			for pixel: int in Gen2Tiles.TILE_PIXELS:
				@warning_ignore("integer_division")
				var at: int = (pixel / Gen2Tiles.TILE_WIDTH) * width \
					+ tile * Gen2Tiles.TILE_WIDTH + pixel % Gen2Tiles.TILE_WIDTH
				if before[at] != after[at]:
					actually_changed.append(tile)
					break
		assert_eq(Array(animation.changed_tiles()), actually_changed)
		assert_eq(redraw, not actually_changed.is_empty() or animation.palette_changed())


func test_tile_frames_answers_every_frame_in_order_without_moving_the_sequence() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 2, Vector2i.ZERO)
	var animation := Gen2WorldAnimation.new()
	animation.configure(world)
	for _frame: int in 5:
		animation.advance_frame()
	var before: PackedByteArray = animation.current_indices().duplicate()
	var at: int = animation.command_index()

	# The tileset's own tile, then the four the water command plays.
	var frames: Array[PackedByteArray] = animation.tile_frames(0)
	assert_eq(frames.size(), 5)
	# The asset's four frames light 8, 1, 2 and 3 rows, in that play order.
	var lit: Array[int] = []
	for frame: PackedByteArray in frames:
		lit.append(frame.count(1))
	assert_eq(lit, [0, 64, 8, 16, 24] as Array[int])
	# A mod shares this object with the running game, so asking must not step it.
	assert_eq(animation.current_indices(), before)
	assert_eq(animation.command_index(), at)
	# A tile no command touches has no frames, rather than one of itself.
	assert_eq(animation.tile_frames(1).size(), 0)


func test_reload_tileset_keeps_the_place_a_connection_crossing_left() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 1, Vector2i.ZERO)
	var animation := Gen2WorldAnimation.new()
	animation.configure(world)
	for _frame: int in 3:
		animation.advance_frame()
	var at: int = animation.command_index()
	assert_ne(at, 0)

	# `MapSetupScript_Connection` carries `LoadMapTileset` and no
	# `LoadMapGraphics`, so nothing resets `hTileAnimFrame`: the neighbour's own
	# command list is loaded where the sequence stands.
	var neighbour := Gen2WorldAPI.open(data, 1, 2, Vector2i.ZERO)
	animation.reload_tileset(neighbour)
	assert_eq(animation.command_index(), at)
	assert_eq(animation.tileset.number, 1)
	# A warp is the other setup script and does reset it.
	animation.configure(neighbour)
	assert_eq(animation.command_index(), 0)


## The four tree commands read `wCelebiEvent` on every tick, so an ordinary visit
## to Ilex Forest draws both trees on their first frame and the restless one
## alternates, with `...Animation2`'s `xor %10` a frame ahead of its pair.
func test_the_forest_trees_stand_still_until_the_celebi_event_is_set() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 3, Vector2i.ZERO)
	var animation := Gen2WorldAnimation.new()
	animation.configure(world)

	# Two whole cycles of the six commands, which leaves wTileAnimationTimer at
	# 2 and both trees on the frame the `jr nz` branch never leaves.
	for _command: int in 12:
		animation.tick()
	assert_eq(_tree_frame(animation, 0x0C), 0)
	assert_eq(_tree_frame(animation, 0x0F), 0)

	world.state.set_engine_flag(Gen2WorldState.engine_flag(
		Gen2WorldState.ENGINE_FOREST_IS_RESTLESS, Gen2WorldState.is_crystal_profile(data)
	))
	# An even timer is `GetForestTreeFrame`'s own zero, so the pair draws the
	# first frame and the `xor %10` pair the second.
	_tick_pair(animation)
	assert_eq(_tree_frame(animation, 0x0C), 0)
	assert_eq(_tree_frame(animation, 0x0F), 0)
	_tick_pair(animation)
	assert_eq(_tree_frame(animation, 0x0C), 1)
	assert_eq(_tree_frame(animation, 0x0F), 1)

	# The bump and the rewind, and then the odd timer answers the other way round.
	_tick_pair(animation)
	_tick_pair(animation)
	assert_eq(_tree_frame(animation, 0x0C), 1)
	assert_eq(_tree_frame(animation, 0x0F), 1)
	_tick_pair(animation)
	assert_eq(_tree_frame(animation, 0x0C), 0)
	assert_eq(_tree_frame(animation, 0x0F), 0)


func _tick_pair(animation: Gen2WorldAnimation) -> void:
	animation.tick()
	animation.tick()


## Which of the two frames a tree tile is holding, read off the fixture asset's
## own marking: frame 0 lights the first plane and frame 1 the second, so the
## palette index of a lit pixel is 1 or 2. The strip is one row of tiles, so a
## tile's first pixel is its own column of row zero rather than a tile-sized
## stride into the array.
func _tree_frame(animation: Gen2WorldAnimation, tile: int) -> int:
	return 0 if animation.current_indices()[tile * Gen2Tiles.TILE_WIDTH] == 1 else 1


## `ScrollTileRightLeft` is the cave, dark cave and ice path lists' only tick:
## none of the three carries a `StandingTileFrame8`, so a reading that leaves
## the timer to something else stops the water palette, the flicker and this
## tile's own reversal all at once. `ScrollTileDown` is the referenced vertical
## routine and `ScrollTileUpDown` is not, so the second tile only ever goes down.
func test_the_cave_list_ticks_its_timer_from_the_horizontal_scroll_alone() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var world := Gen2WorldAPI.open(data, 1, 4, Vector2i.ZERO)
	var animation := Gen2WorldAnimation.new()
	animation.configure(world, Gen2WorldPalette.TIME_DARK)
	var commands: int = data.world_tileset(3).animation_commands.size()

	var across: Array[int] = []
	var down: Array[int] = []
	var timers: Array[int] = []
	var flicker: Array[int] = []
	for pass_index: int in 8:
		for _step: int in commands:
			animation.advance_frame()
			flicker.append(animation.cave_palette_color())
		timers.append(animation.timer())
		across.append(_lit_column(animation, 0))
		down.append(_lit_row(animation, 1))

	assert_eq(timers, [1, 2, 3, 4, 5, 6, 7, 0] as Array[int])
	# The tick is in front of the test, so the branch reads 1, 2, 3, 4 ... and
	# `and %100` sends the four passes at 4 to 7 the other way.
	assert_eq(across, [1, 2, 3, 2, 1, 0, 7, 0] as Array[int])
	# Three `ScrollTileDown` a pass and no direction to choose.
	assert_eq(down, [3, 6, 1, 4, 7, 2, 5, 0] as Array[int])
	# `hVBlankCounter and %10`, which is two frames of each and is not the
	# sequence's own timer: the timer moves once per nineteen frames here. The
	# opening -1 is the frame before the list's first `cave_palette`.
	assert_eq(flicker.slice(0, 8), [-1, 1, 1, 0, 0, 1, 1, 0] as Array[int])


## Which column of tile [param tile]'s top row is lit, and which row of its
## first column is, for the two scrolls above.
func _lit_column(animation: Gen2WorldAnimation, tile: int) -> int:
	for x: int in Gen2Tiles.TILE_WIDTH:
		if animation.current_indices()[tile * Gen2Tiles.TILE_WIDTH + x] != 0:
			return x
	return -1


func _lit_row(animation: Gen2WorldAnimation, tile: int) -> int:
	var width: int = RomLayout.TILESET_TILE_COUNT * Gen2Tiles.TILE_WIDTH
	for y: int in Gen2Tiles.TILE_HEIGHT:
		if animation.current_indices()[y * width + tile * Gen2Tiles.TILE_WIDTH] != 0:
			return y
	return -1


## `LoadMapGroupRoof` copies nine tiles over `vTiles2 tile $0a` and touches
## nothing else, and a group whose entry is -1 leaves the strip alone.
##
## `TILESET_JOHTO`, because `home/map.asm` gates the call on three tilesets and
## every other one owns tiles $0A..$12 itself; see the second half of this test.
func test_a_map_group_roof_replaces_nine_tiles_of_the_strip() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var tileset: Gen2WorldTileset = data.world_tileset(ROOFED_TILESET)
	var base: PackedByteArray = data.world_tileset_indices(ROOFED_TILESET)
	var width: int = tileset.tile_count * Gen2Tiles.TILE_WIDTH
	var left: int = RomLayout.ROOF_VRAM_TILE * Gen2Tiles.TILE_WIDTH
	var span: int = RomLayout.ROOF_TILES * Gen2Tiles.TILE_WIDTH

	assert_eq(data.map_group_roof(0), 0)
	assert_eq(data.map_group_roof(1), 1)
	assert_eq(data.map_group_roof(2), -1)

	for group: int in 2:
		var map := Gen2WorldMap.from_cache({"group": group, "tileset": ROOFED_TILESET})
		var drawn: PackedByteArray = data.map_tile_indices(map, tileset)
		assert_eq(drawn.size(), base.size())
		for y: int in Gen2Tiles.TILE_HEIGHT:
			for x: int in width:
				var inside: bool = x >= left and x < left + span
				assert_eq(
					drawn[y * width + x], group + 1 if inside else base[y * width + x],
					"group %d pixel %d,%d" % [group, x, y],
				)

	var plain := Gen2WorldMap.from_cache({"group": 2, "tileset": ROOFED_TILESET})
	assert_eq(data.map_tile_indices(plain, tileset), base)


## `home/map.asm`: "These tilesets support dynamic per-mapgroup roof tiles",
## and it names three. Every other tileset owns tiles $0A..$12 itself, so a roof
## written over them is the map's own art destroyed: reading the group alone put
## roof shingles through 106 Crystal maps and 98 Gold and Silver ones, every
## house, gym and Pokemon Center in a roofed group among them.
func test_only_the_three_gated_tilesets_take_their_map_groups_roof() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var roofed: Gen2WorldTileset = data.world_tileset(ROOFED_TILESET)
	var indoor: Gen2WorldTileset = data.world_tileset(UNROOFED_TILESET)
	assert_not_null(roofed)
	assert_not_null(indoor)
	assert_eq(data.map_group_roof(0), 0, "the group carries a roof either way")

	var outdoor_map := Gen2WorldMap.from_cache({"group": 0, "tileset": ROOFED_TILESET})
	var indoor_map := Gen2WorldMap.from_cache({"group": 0, "tileset": UNROOFED_TILESET})
	assert_eq(data.map_roof(outdoor_map, roofed), 0)
	assert_eq(data.map_roof(indoor_map, indoor), -1)
	assert_eq(
		data.map_tile_indices(indoor_map, indoor),
		data.world_tileset_indices(UNROOFED_TILESET),
		"an indoor map draws its tileset's own tiles and nothing else"
	)


## `_LoadMapPals`' tail: colours 1 and 2 of `PAL_BG_ROOF` come from the map
## group, on a TOWN or ROUTE map alone, and `cp NITE_F` puts DARKNESS on the
## nite pair rather than a third one.
func test_roof_colours_replace_two_slots_on_outdoor_maps_only() -> void:
	var data: GameData = GameData.open_directory(_directory)
	var morning: PackedColorArray = Gen2WorldPalette.roof_colors(
		data, Gen2WorldPalette.ENVIRONMENT_TOWN, Gen2WorldPalette.TIME_MORNING, 1
	)
	assert_eq(morning.size(), 2)
	assert_eq(morning[0], Gen2Palette.from_packed(0x0002))
	assert_eq(morning[1], Gen2Palette.from_packed(0x0003))
	for time: int in [Gen2WorldPalette.TIME_NIGHT, Gen2WorldPalette.TIME_DARK]:
		var night: PackedColorArray = Gen2WorldPalette.roof_colors(
			data, Gen2WorldPalette.ENVIRONMENT_ROUTE, time, 1
		)
		assert_eq(night[0], Gen2Palette.from_packed(0x0004))
		assert_eq(night[1], Gen2Palette.from_packed(0x0005))
	for environment: int in [0, 3, 4, 6, 7]:
		assert_eq(Gen2WorldPalette.roof_colors(
			data, environment, Gen2WorldPalette.TIME_DAY, 1
		).size(), 0, "environment %d has no roof branch" % environment)
	# `_LoadMapPals` reads `RoofPals` off `wMapGroup` alone and never consults
	# `MapGroupRoofs`, so a group with no roof tiles still tints the slot.
	assert_eq(data.map_group_roof(2), -1)
	assert_eq(Gen2WorldPalette.roof_colors(
		data, Gen2WorldPalette.ENVIRONMENT_TOWN, Gen2WorldPalette.TIME_DAY, 2
	)[0], Gen2Palette.from_packed(0x0003))
