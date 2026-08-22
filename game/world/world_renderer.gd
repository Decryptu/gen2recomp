class_name Gen2WorldRenderer
extends Node2D

## Draws the visible map page and the development player marker in hardware
## pixels. It does not own map state; call [method set_world] when the API
## changes or [method refresh] after a movement.
##
## The surface is the cartridge's 160x144 unless the world has been given a
## larger [member Gen2WorldAPI.view_pixels], in which case the map fills all of
## it: the connected maps the graph places around this one are drawn as well, on
## [Gen2WorldMapLayer] quads under the sprites, and the border block fills
## whatever no map covers.

const PLAYER_COLOR: Color = Color("#d34a5a")
const FALLBACK_BACKGROUND: Color = Color("#f5f1d8")

## `.InitSprite` (engine/overworld/map_objects.asm) writes an object's OAM y as
## `add OAM_Y_OFS - 4` against a plain `add OAM_X_OFS` on the other axis, so a
## 16x16 overworld sprite stands four pixels above its own cell and nothing
## shifts it sideways. Every map object shares the one write: the emote, the
## shadow, the boulder dust and the shaking grass are tracking objects that copy
## the tracked object's `OBJECT_SPRITE_Y` and go through it too, and the jump
## arc, the tracking bob and the fishing rod are offsets added in front of it.
## The tuft of grass over a sprite's legs is background rather than OAM and takes
## no lift; it moves with the sprite because OAM_PRIO is what draws it.
const SPRITE_LIFT := Vector2(0, -4)

var _world: Gen2WorldAPI = null
var _animation: Gen2WorldAnimation = null
var _effects: Gen2WorldEffects = null
var _actors: Gen2WorldActors = null
var _encounters: Gen2WorldEncounters = null
var _anim_textures: Dictionary = {}
var _time_of_day: int = Gen2WorldPalette.TIME_MORNING
var _atlas: ImageTexture = null
## The coloured tile strips in use this frame, keyed by the pair that chooses
## their colours: see [method _atlas_for]. The current map's is [member _atlas].
var _atlases: Dictionary = {}
## The map quads, in draw order: the void fill, each connected map, then this
## map's own block buffer. Pooled rather than rebuilt, since the camera moves
## every frame and nothing about a quad but its position does.
var _map_layers: Array[Gen2WorldMapLayer] = []
var _block_textures: Dictionary = {}
var _tiles_textures: Dictionary = {}
## `wOverworldMapBlocks` itself: the map plus the three-block margin
## `ChangeMap` leaves, resolved through [method Gen2WorldAPI.drawn_block_at] so
## the connection strips in it are the cartridge's own.
var _buffer_texture: ImageTexture = null
var _buffer_revision: int = -1
## Kept beside the texture so an animation frame can repaint the one or two
## tiles it rewrote instead of recolouring the whole strip.
var _atlas_image: Image = null
var _background_color: Color = FALLBACK_BACKGROUND
var _actor_textures: Dictionary = {}
var _priority_atlas: ImageTexture = null
var _priority_indices: PackedByteArray = PackedByteArray()
var _effect_sheets: Dictionary = {}
var _effect_textures: Dictionary = {}
## The palette order the map fades are one step of, and `FillWhiteBGColor`
## beside it. The identity order is every other frame of the game.
var _fade_order: int = Gen2WorldPalette.FADE_IDENTITY
var _fade_white_fill: bool = false


func set_world(world: Gen2WorldAPI, animation: Gen2WorldAnimation = null) -> void:
	_world = world
	_animation = animation
	_actor_textures.clear()
	_effect_textures.clear()
	_block_textures.clear()
	_buffer_texture = null
	_buffer_revision = -1
	_rebuild_atlas()
	refresh()


## `DoBattleTransition`'s own screen: the cells it has written, the two tiles it
## draws them with and the palette it floods the map with, or an empty one when
## it floods nothing.
var _transition_cells: PackedByteArray = PackedByteArray()
var _transition_tiles: PackedByteArray = PackedByteArray()
var _transition_palette: PackedColorArray = PackedColorArray()
## Which map objects the transition has left in OAM, and which of them is the
## opponent `RespawnPlayerAndOpponent` keeps beside the player.
var _transition_sprites: int = Gen2BattleTransition.SPRITES_ALL
var _transition_opponent: int = -1
## `StartTrainerBattle_Flash` writes `wBGP` and calls `DmgToCgbBGPals` alone, so
## the three flash passes are a background order and the sprites over them keep
## their own colours. The map fade is the other shape and goes through
## [method set_fade], which is both.
var _transition_order: int = Gen2BattleTransition.IDENTITY
## The one patterned tile of the pair, cached rather than drawn pixel by pixel:
## the transition is redrawn once for the screen and again over the lower half of
## every sprite standing in grass.
var _transition_textures: Dictionary = {}


## Gen2ModHost.RENDERER_EFFECTS_METHOD: the emote bubbles, boulder dust, grass
## rustle and headbutt tree this view draws over the map. Presentation only, so a
## renderer may be handed null and draw none of them.
func set_effects(effects: Gen2WorldEffects) -> void:
	_effects = effects
	queue_redraw()


## Gen2ModHost.RENDERER_ACTORS_METHOD: the sprites registered mods put in the
## world. Presentation only, drawn with the map's own objects and taking part in
## nothing else, so a renderer may be handed null and draw none of them.
func set_actors(actors: Gen2WorldActors) -> void:
	_actors = actors
	queue_redraw()


## Gen2ModHost.RENDERER_ENCOUNTERS_METHOD: the host's visible-encounter layer.
## Its population is drawn through [method set_actors] with everything else; what
## is read here is the shiny pulse alone, which is the cartridge's own battle
## animation objects over the map and has no other layer to ride.
func set_encounters(encounters: Gen2WorldEncounters) -> void:
	_encounters = encounters
	queue_redraw()


## Selects the palette rows this view draws with. The world owns the clock and
## object visibility; a renderer only reads them, so a second view of the same
## world cannot change what the first one sees.
func set_time_of_day(time_of_day: int) -> void:
	_time_of_day = clampi(time_of_day, 0, 3)
	_actor_textures.clear()
	_effect_textures.clear()
	_rebuild_atlas()
	queue_redraw()


## Gen2ModHost.RENDERER_FADE_METHOD: one step of `FadeOutToWhite` or
## `FadeInFromWhite`, which is a palette order applied to every palette on
## screen and, on the way out, `FillWhiteBGColor` under it. The identity order
## is a screen that is not fading. Presentation only: the host spends the frames
## whether or not the view it is drawing with takes this.
func set_fade(order: int, white_fill: bool = false) -> void:
	if order == _fade_order and white_fill == _fade_white_fill:
		return
	_fade_order = order
	_fade_white_fill = white_fill
	_actor_textures.clear()
	_effect_textures.clear()
	_anim_textures.clear()
	_rebuild_atlas()
	queue_redraw()


## Repaints the tiles the last animation frame rewrote.
##
## The sequence touches one or two of a tileset's tiles per frame, so recolouring
## the whole strip was almost all of the frame's cost. A palette
## command is the exception: it changes every tile drawn with that row, so it
## still rebuilds.
func refresh_animation() -> void:
	if _animation == null or _atlas == null or _atlas_image == null \
		or _animation.palette_changed():
		_rebuild_atlas()
		queue_redraw()
		return
	var changed: PackedInt32Array = _animation.changed_tiles()
	if changed.is_empty():
		return
	var indices: PackedByteArray = _animation.current_indices()
	for entry: Dictionary in _atlases.values():
		if not bool(entry["animated"]):
			continue
		var image: Image = entry["image"]
		var palettes: Array = entry["palettes"]
		for tile: int in changed:
			_paint_tile(image, indices, palettes, tile)
		(entry["texture"] as ImageTexture).update(image)
		entry["indices"] = indices
	_priority_indices = indices
	_priority_atlas = null
	queue_redraw()


func _rebuild_atlas() -> void:
	_atlases.clear()
	_atlas = null
	_atlas_image = null
	_background_color = FALLBACK_BACKGROUND
	if _world == null or _world.data == null or _world.current_tileset == null:
		return
	var entry: Dictionary = _atlas_for(_world.current_map, _world.current_tileset)
	if entry.is_empty():
		return
	var palettes: Array = entry["palettes"]
	if not palettes.is_empty() and (palettes[0] as PackedColorArray).size() >= 1:
		_background_color = (palettes[0] as PackedColorArray)[0]
	_atlas = entry["texture"]
	_atlas_image = entry["image"]
	# Built on demand: only an object standing in grass reads it.
	_priority_indices = entry["indices"]
	_priority_atlas = null
	# The quads hold the strip they were configured with, and this is a new one.
	_sync_map_layers()


## The coloured tile strip a map draws with, cached on the two things that
## choose its colours: the tileset the tiles come from and the environment
## `GetMapPalette` reads the eight background slots out of. A connected map
## sharing both shares the strip rather than colouring a second copy of it, and
## the animation repaints every cached strip that came from its own tileset.
func _atlas_for(map: Gen2WorldMap, tileset: Gen2WorldTileset) -> Dictionary:
	if map == null or tileset == null or _world == null or _world.data == null:
		return {}
	var key: String = "%d:%d" % [tileset.number, map.environment]
	if _atlases.has(key):
		return _atlases[key]
	var indices: PackedByteArray = _world.data.world_tileset_indices(tileset.number)
	var animated: bool = _animation != null and _world.current_tileset != null \
		and tileset.number == _world.current_tileset.number \
		and not _animation.current_indices().is_empty()
	if animated:
		indices = _animation.current_indices()
	if indices.size() < tileset.tile_count * Gen2Tiles.TILE_PIXELS:
		return {}
	var palettes: Array = _tile_palettes_for(map, tileset)
	var image := Image.create(
		tileset.tile_count * Gen2Tiles.TILE_WIDTH, Gen2Tiles.TILE_HEIGHT,
		false, Image.FORMAT_RGBA8,
	)
	for tile: int in tileset.tile_count:
		_paint_tile(image, indices, palettes, tile)
	var entry: Dictionary = {
		"texture": ImageTexture.create_from_image(image),
		"image": image,
		"palettes": palettes,
		"indices": indices,
		"animated": animated,
	}
	_atlases[key] = entry
	return entry


## The one palette `.pal_loop` puts every background tile on, through whatever
## order the flash is on. Empty when the transition floods nothing, which is
## every wild battle: those wedges take the palette their own cell was drawn in.
func flood_palette() -> PackedColorArray:
	if _transition_palette.is_empty():
		return PackedColorArray()
	return Gen2WorldPalette.fade_palette(
		Gen2WorldPalette.fade_palette(_transition_palette, _fade_order), _transition_order
	)


func _tile_palettes() -> Array:
	return _tile_palettes_for(_world.current_map, _world.current_tileset)


## The palettes the current map's tile strip was coloured with, which
## [method _atlas_for] already resolved and kept.
func _current_palettes() -> Array:
	var entry: Dictionary = _atlas_for(_world.current_map, _world.current_tileset)
	return entry["palettes"] if not entry.is_empty() else []


func _tile_palettes_for(map: Gen2WorldMap, tileset: Gen2WorldTileset) -> Array:
	## `StartTrainerBattle_LoadPokeBallGraphics.pal_loop` puts every background
	## tile on `PAL_BG_TEXT` and fills that one palette, which is why a trainer
	## transition draws the whole map in four colours.
	if not _transition_palette.is_empty():
		var flooded: Array = []
		var flood: PackedColorArray = flood_palette()
		for _tile: int in tileset.tile_count:
			flooded.append(flood)
		return flooded
	var rows: Array = Gen2WorldPalette.tile_palettes(
		_world.data,
		map,
		tileset,
		_time_of_day,
		_animation.water_palette_color() if _animation != null else -1,
		_animation.cave_palette_color() if _animation != null else -1,
		_fade_order,
		_fade_white_fill,
	)
	if _transition_order == Gen2BattleTransition.IDENTITY:
		return rows
	var faded: Array = []
	for row: PackedColorArray in rows:
		faded.append(Gen2WorldPalette.fade_palette(row, _transition_order))
	return faded


## One tile of the strip, coloured. Index 0 is a colour here rather than a hole:
## the atlas is the background layer, and the cartridge's transparent index
## belongs to sprites.
func _paint_tile(image: Image, indices: PackedByteArray, palettes: Array, tile: int) -> void:
	var width: int = image.get_width()
	var palette: PackedColorArray = palettes[tile] if tile < palettes.size() else PackedColorArray()
	var left: int = tile * Gen2Tiles.TILE_WIDTH
	for y: int in Gen2Tiles.TILE_HEIGHT:
		var row: int = y * width + left
		for x: int in Gen2Tiles.TILE_WIDTH:
			var color_index: int = indices[row + x]
			image.set_pixel(
				left + x, y,
				palette[color_index] if color_index < palette.size() else _background_color
			)


## `DoBattleTransition`, drawn over whatever the map was already showing.
##
## [param cells] is [method Gen2BattleTransition.cells], [param tiles] the two
## tiles `LoadBattleTransitionGFX` loads as index buffers, and [param palette]
## the four colours the whole map is flooded with while a trainer's ball is up.
## An empty palette is the wild branch, which floods nothing: its black tile is
## colour 3 of whatever palette the cell under it was already drawn in. Every
## overworld palette's colour 3 is `gfx/overworld/trainer_battle.pal`'s own
## (7,7,7), so both kinds of wedge come out the same dark grey.
##
## [param sprites] is [method Gen2BattleTransition.sprites] and [param opponent]
## the map object `hLastTalked` names; [param order] is the flash's `wBGP`, which
## `DmgToCgbBGPals` applies to the background alone.
func set_transition(
	cells: PackedByteArray, tiles: PackedByteArray, palette: PackedColorArray,
	sprites: int = Gen2BattleTransition.SPRITES_ALL, opponent: int = -1,
	order: int = Gen2BattleTransition.IDENTITY
) -> void:
	var was: PackedColorArray = _transition_palette
	var was_order: int = _transition_order
	_transition_cells = cells
	_transition_tiles = tiles
	_transition_palette = palette
	_transition_sprites = sprites
	_transition_opponent = opponent
	_transition_order = order
	if palette != was or order != was_order:
		_transition_textures.clear()
		_actor_textures.clear()
		_effect_textures.clear()
		_anim_textures.clear()
		_rebuild_atlas()
	queue_redraw()


func clear_transition() -> void:
	if _transition_cells.is_empty() and _transition_palette.is_empty():
		return
	var was_flooding: bool = not _transition_palette.is_empty()
	_transition_cells = PackedByteArray()
	_transition_tiles = PackedByteArray()
	_transition_palette = PackedColorArray()
	_transition_sprites = Gen2BattleTransition.SPRITES_ALL
	_transition_opponent = -1
	_transition_textures.clear()
	if _transition_order != Gen2BattleTransition.IDENTITY:
		_transition_order = Gen2BattleTransition.IDENTITY
		was_flooding = true
	if was_flooding:
		_actor_textures.clear()
		_effect_textures.clear()
		_anim_textures.clear()
		_rebuild_atlas()
	queue_redraw()


## The transition's own cells. `wTilemap` is the background, and OAM draws over
## the background, so these go under every sprite: the player and the NPCs stay
## on top of the wedges until `StartTrainerBattle_Finish` takes them away.
##
## [param clip] is the rectangle to draw inside, and [param priority] the
## OAM_PRIO pass a sprite standing in grass wants: colour 0 loses that test, so
## it is left transparent there and drawn like any other colour here.
func _draw_transition(
	camera_pixels: Vector2, clip: Rect2 = Rect2(), priority: bool = false
) -> void:
	var black: int = Gen2BattleTransition.CELL_BLACK
	var flood: PackedColorArray = flood_palette()
	## The strip's own palettes, not a fresh resolve: this runs again over the
	## lower half of every sprite standing in grass, and building one palette
	## table per sprite was most of such a frame.
	var palettes: Array = [] if not flood.is_empty() else _current_palettes()
	## The screen's own top-left corner, which is the surface's until a view
	## larger than the hardware's puts the twenty by eighteen cells in the middle
	## of something wider.
	var origin: Vector2 = screen_offset()
	var screen_tile := Vector2i(
		floori((camera_pixels.x + origin.x) / float(Gen2Tiles.TILE_WIDTH)),
		floori((camera_pixels.y + origin.y) / float(Gen2Tiles.TILE_HEIGHT)),
	)
	## The whole screen, or the few cells a sprite's own lower half falls in.
	var first := Vector2i.ZERO
	var last := Vector2i(Gen2BattleTransition.COLUMNS - 1, Gen2BattleTransition.ROWS - 1)
	if priority:
		first = Vector2i(
			floori((clip.position.x - origin.x) / Gen2Tiles.TILE_WIDTH),
			floori((clip.position.y - origin.y) / Gen2Tiles.TILE_HEIGHT),
		)
		last = Vector2i(
			mini(ceili((clip.end.x - origin.x) / Gen2Tiles.TILE_WIDTH), last.x),
			mini(ceili((clip.end.y - origin.y) / Gen2Tiles.TILE_HEIGHT), last.y),
		)
	for y: int in range(maxi(first.y, 0), last.y + 1):
		for x: int in range(maxi(first.x, 0), last.x + 1):
			var cell: int = int(_transition_cells[y * Gen2BattleTransition.COLUMNS + x])
			if cell == Gen2BattleTransition.CELL_NONE:
				continue
			var at := Rect2(
				origin + Vector2(x * Gen2Tiles.TILE_WIDTH, y * Gen2Tiles.TILE_HEIGHT),
				Vector2(Gen2Tiles.TILE_WIDTH, Gen2Tiles.TILE_HEIGHT)
			)
			var covered: Rect2 = at if not priority else at.intersection(clip)
			if covered.size.x <= 0.0 or covered.size.y <= 0.0:
				continue
			var palette: PackedColorArray = flood
			if palette.is_empty():
				var tile: int = _drawn_tile_at(screen_tile.x + x, screen_tile.y + y)
				palette = palettes[tile] if tile >= 0 and tile < palettes.size() \
					else PackedColorArray()
			if cell == black or _transition_tiles.is_empty():
				draw_rect(covered, palette[3] if palette.size() > 3 else Color.BLACK, true)
				continue
			var texture: Texture2D = _transition_texture(palette, priority)
			if texture == null:
				continue
			draw_texture_rect_region(
				texture, covered, Rect2(covered.position - at.position, covered.size)
			)


## `BATTLETRANSITION_SQUARE`, the one tile of the pair that has a pattern in it.
## [param transparent_zero] is the OAM_PRIO pass, where the tile's colour 0
## pixels lose to the sprite under them.
func _transition_texture(
	palette: PackedColorArray, transparent_zero: bool
) -> Texture2D:
	if _transition_tiles.size() < Gen2Tiles.TILE_PIXELS:
		return null
	var key: String = "%d:%d" % [hash(palette), int(transparent_zero)]
	var texture: Texture2D = _transition_textures.get(key, null)
	if texture != null:
		return texture
	var image := Image.create(
		Gen2Tiles.TILE_WIDTH, Gen2Tiles.TILE_HEIGHT, false, Image.FORMAT_RGBA8
	)
	for y: int in Gen2Tiles.TILE_HEIGHT:
		for x: int in Gen2Tiles.TILE_WIDTH:
			var index: int = int(_transition_tiles[y * Gen2Tiles.TILE_WIDTH + x])
			var color: Color = palette[index] if index < palette.size() else Color.BLACK
			if index == 0 and transparent_zero:
				color.a = 0.0
			image.set_pixel(x, y, color)
	texture = ImageTexture.create_from_image(image)
	_transition_textures[key] = texture
	return texture


func refresh() -> void:
	_sync_map_layers()
	queue_redraw()


## Lays the map quads out under this frame's camera.
##
## The order is the order the cartridge's own buffer would be read in if it had
## one this wide: the border block under everything, then each connected map
## furthest first, then `wOverworldMapBlocks` itself over the top. That last one
## is what keeps the three-block margin byte for byte the cartridge's -- a
## connection strip stops at the `length` the macro stored, and a neighbour map
## drawn whole does not -- so nothing a 20x18 screen can reach changes.
func _sync_map_layers() -> void:
	if _world == null or _world.current_map == null or _world.current_tileset == null \
		or _atlas == null:
		_show_map_layers(0)
		return
	var map: Gen2WorldMap = _world.current_map
	var tileset: Gen2WorldTileset = _world.current_tileset
	var camera: Vector2 = _world.view_origin_pixels().floor()
	var view := Vector2(view_pixels())
	var block_pixels: int = RomLayout.MAP_BLOCK_CELL_WIDTH * Gen2WorldAPI.CELL_PIXELS
	var used: int = 0

	var fill: Gen2WorldMapLayer = _map_layer(used)
	used += 1
	fill.configure(
		_atlas, _one_block_texture(), _tiles_texture(tileset), Vector2i.ZERO,
		map.border_block, tileset.block_count, tileset.tile_count, true,
	)
	fill.place(Vector2.ZERO, view, camera)

	if view.x > Gen2WorldAPI.VIEW_PIXELS.x or view.y > Gen2WorldAPI.VIEW_PIXELS.y:
		var placements: Array = _world.map_placements().values()
		placements.reverse()
		for placement: Dictionary in placements:
			var near: Gen2WorldMap = placement["map"]
			var near_tileset: Gen2WorldTileset = _world.data.world_tileset(near.tileset)
			if near_tileset == null:
				continue
			var at: Vector2 = Vector2(placement["origin"] as Vector2i) * float(block_pixels) \
				- camera
			var size := Vector2(near.width_blocks, near.height_blocks) * float(block_pixels)
			if not Rect2(at, size).intersects(Rect2(Vector2.ZERO, view)):
				continue
			var blocks: ImageTexture = _blocks_texture(near)
			var strip: Dictionary = _atlas_for(near, near_tileset)
			if blocks == null or strip.is_empty():
				continue
			var layer: Gen2WorldMapLayer = _map_layer(used)
			used += 1
			layer.configure(
				strip["texture"], blocks, _tiles_texture(near_tileset),
				Vector2i(near.width_blocks, near.height_blocks), near.border_block,
				near_tileset.block_count, near_tileset.tile_count, false,
			)
			layer.place(at.floor(), size)

	var buffer: ImageTexture = _map_buffer_texture()
	if buffer != null:
		var span := Vector2i(
			map.width_blocks + 2 * Gen2WorldAPI.BUFFER_BLOCKS,
			map.height_blocks + 2 * Gen2WorldAPI.BUFFER_BLOCKS,
		)
		var layer: Gen2WorldMapLayer = _map_layer(used)
		used += 1
		layer.configure(
			_atlas, buffer, _tiles_texture(tileset), span, map.border_block,
			tileset.block_count, tileset.tile_count, false,
		)
		layer.place(
			(Vector2.ONE * float(-Gen2WorldAPI.BUFFER_BLOCKS * block_pixels) - camera).floor(),
			Vector2(span) * float(block_pixels),
		)
	_show_map_layers(used)


func _map_layer(index: int) -> Gen2WorldMapLayer:
	while _map_layers.size() <= index:
		var layer := Gen2WorldMapLayer.new()
		_map_layers.append(layer)
		add_child(layer)
	return _map_layers[index]


func _show_map_layers(count: int) -> void:
	for index: int in _map_layers.size():
		_map_layers[index].visible = index < count


## `wOverworldMapBlocks`: the map's own blocks with the three-block margin
## around them, every byte through [method Gen2WorldAPI.drawn_block_at], so the
## connection strips and the border fill in it are the cartridge's own.
func _map_buffer_texture() -> ImageTexture:
	if _world == null or _world.current_map == null:
		return null
	if _buffer_texture != null and _buffer_revision == _world.block_revision:
		return _buffer_texture
	var map: Gen2WorldMap = _world.current_map
	var span := Vector2i(
		map.width_blocks + 2 * Gen2WorldAPI.BUFFER_BLOCKS,
		map.height_blocks + 2 * Gen2WorldAPI.BUFFER_BLOCKS,
	)
	if span.x <= 0 or span.y <= 0:
		return null
	var bytes := PackedByteArray()
	bytes.resize(span.x * span.y)
	for y: int in span.y:
		var row: int = y * span.x
		for x: int in span.x:
			bytes[row + x] = _world.drawn_block_at(
				x - Gen2WorldAPI.BUFFER_BLOCKS, y - Gen2WorldAPI.BUFFER_BLOCKS
			) & 0xFF
	_buffer_texture = Gen2WorldMapLayer.block_texture(bytes, span)
	_buffer_revision = _world.block_revision
	return _buffer_texture


## A connected map's own block list, which nothing a run does edits: only the
## loaded map takes `changeblock`.
func _blocks_texture(map: Gen2WorldMap) -> ImageTexture:
	var key: String = "%d:%d" % [map.group, map.number]
	if _block_textures.has(key):
		return _block_textures[key]
	var texture: ImageTexture = Gen2WorldMapLayer.block_texture(
		map.blocks, Vector2i(map.width_blocks, map.height_blocks)
	)
	_block_textures[key] = texture
	return texture


## The tileset's metatile table as sixteen bytes a block, with anything past the
## tile strip folded to zero the way [method Gen2WorldTileset.tile_index] does.
func _tiles_texture(tileset: Gen2WorldTileset) -> ImageTexture:
	if _tiles_textures.has(tileset.number):
		return _tiles_textures[tileset.number]
	var slots: int = RomLayout.MAP_BLOCK_TILE_WIDTH * RomLayout.MAP_BLOCK_TILE_WIDTH
	var bytes := PackedByteArray()
	bytes.resize(slots * maxi(tileset.block_count, 1))
	for at: int in bytes.size():
		var index: int = tileset.meta[at] if at < tileset.meta.size() else 0
		bytes[at] = index if index < tileset.tile_count else 0
	var texture: ImageTexture = Gen2WorldMapLayer.block_texture(
		bytes, Vector2i(slots, maxi(tileset.block_count, 1))
	)
	_tiles_textures[tileset.number] = texture
	return texture


## A one-block stand-in for the void fill's block sampler, which its own quad
## never reads: every pixel of that quad is outside the map it declares.
func _one_block_texture() -> ImageTexture:
	if not _block_textures.has("void"):
		_block_textures["void"] = Gen2WorldMapLayer.block_texture(
			PackedByteArray([0]), Vector2i.ONE
		)
	return _block_textures["void"]


## The drawn surface in hardware pixels, which is the cartridge's own until a
## screen asks the world for more.
func view_pixels() -> Vector2i:
	return _world.view_pixels if _world != null else Gen2WorldAPI.VIEW_PIXELS


## Where the cartridge's own 160x144 screen sits inside the drawn surface. Zero
## unless the view is larger, and always a whole tile, since everything the
## hardware laid out on the screen -- the transition's twenty by eighteen cells
## first -- is laid out in tiles.
func screen_offset() -> Vector2:
	return ((Vector2(view_pixels() - Gen2WorldAPI.VIEW_PIXELS) * 0.5)
		/ float(Gen2Tiles.TILE_WIDTH)).floor() * float(Gen2Tiles.TILE_WIDTH)


func _draw() -> void:
	if _world == null or _atlas == null:
		draw_rect(Rect2(Vector2.ZERO, Vector2(view_pixels())), _background_color, true)
		return

	var camera_pixels: Vector2 = _world.view_origin_pixels()
	## `Cut_Headbutt_GetPixelFacing`'s tree goes away while its own sprite
	## animation plays, which the map quad knows nothing about: the four tiles of
	## the cell are painted over with the tileset's own blank one.
	for cell: Vector2i in (_effects.hidden_tree_cells() if _effects != null else []):
		var at: Vector2 = Vector2(cell * Gen2WorldAPI.CELL_PIXELS) - camera_pixels
		for row: int in RomLayout.MAP_BLOCK_CELL_WIDTH:
			for column: int in RomLayout.MAP_BLOCK_CELL_WIDTH:
				draw_texture_rect_region(
					_atlas,
					Rect2(
						at + Vector2(column * Gen2Tiles.TILE_WIDTH, row * Gen2Tiles.TILE_HEIGHT),
						Vector2(Gen2Tiles.TILE_WIDTH, Gen2Tiles.TILE_HEIGHT),
					),
					Rect2(
						Vector2(
							Gen2WorldEffects.HEADBUTT_TREE_HIDDEN_TILE * Gen2Tiles.TILE_WIDTH, 0
						),
						Vector2(Gen2Tiles.TILE_WIDTH, Gen2Tiles.TILE_HEIGHT),
					),
				)
	if not _transition_cells.is_empty():
		_draw_transition(camera_pixels)
	if _transition_sprites == Gen2BattleTransition.SPRITES_NONE:
		return

	var objects: Array = _world.visible_objects()
	objects.sort_custom(_sort_objects)
	## `RespawnPlayerAndOpponent` at each outro's setup: from there the only map
	## objects left in OAM are the player and, in a scripted battle, whoever
	## `hLastTalked` names.
	var battlers_only: bool = _transition_sprites == Gen2BattleTransition.SPRITES_BATTLERS
	## A mod's actors are drawn in the same pass and sorted into the same rows:
	## a follower one cell below an NPC has to be drawn over it, and one cell
	## above it under it. They carry no effect sprite and no grass of their own
	## beyond the tuft the map draws over anything standing in it, an emote only
	## when the entry asked for one, and they are map objects here, so the
	## respawn takes them with the rest.
	var drawn: Array = []
	for object: Gen2WorldObject in objects:
		if battlers_only and object.index != _transition_opponent:
			continue
		drawn.append({"object": object, "row": float(object.cell.y)})
	if _actors != null and not battlers_only:
		for sprite: Dictionary in _actors.sprites():
			drawn.append({"actor": sprite, "row": (sprite["position_cells"] as Vector2).y})
	## The people on the maps around this one, sorted into the same rows: a view
	## wide enough to see the next town is wide enough to see somebody standing
	## in it. They are the world API's read-only copies and take no part in
	## anything: see [method Gen2WorldAPI.connected_map_objects].
	if not battlers_only and view_pixels() != Gen2WorldAPI.VIEW_PIXELS:
		for entry: Dictionary in _world.connected_map_objects():
			var neighbour: Gen2WorldObject = entry["object"]
			if not neighbour.active or neighbour.sprite == null:
				continue
			var offset: Vector2i = entry["offset"]
			drawn.append({
				"object": neighbour,
				"offset": offset,
				"row": float(offset.y + neighbour.cell.y),
			})
	drawn.sort_custom(_sort_drawn)
	for entry: Dictionary in drawn:
		if entry.has("actor"):
			_draw_actor(entry["actor"], camera_pixels)
			continue
		var object: Gen2WorldObject = entry["object"]
		var offset: Vector2i = entry.get("offset", Vector2i.ZERO)
		var pixel: Vector2 = Vector2((object.cell + offset) * Gen2WorldAPI.CELL_PIXELS) \
			+ Vector2(object.step_offset(Gen2WorldAPI.CELL_PIXELS)) - camera_pixels \
			+ SPRITE_LIFT
		var texture: Texture2D = _actor_texture(
			object.sprite, object.palette, object.facing, object.frame, object.big_object_shape()
		)
		# The same sprite offset the player's hop takes, so a `jump_step` in a
		# movement stream arcs rather than sliding.
		var object_jump := Vector2(0, -object.height_offset_pixels())
		if texture != null:
			draw_texture(texture, pixel + object_jump)
		if offset != Vector2i.ZERO:
			continue
		if _in_grass(object.cell):
			_draw_grass_over(pixel, camera_pixels)
		if object.emote_visible:
			_draw_emote(object.emote_id, pixel)
		if not battlers_only:
			_draw_effect_sprites(object.index, pixel)

	var player: Vector2 = Vector2(_world.player_view_pixel()) + SPRITE_LIFT
	## The jump arc is a sprite offset, not a position: the shadow and the grass
	## the hop leaves behind stay on the ground.
	var jump: Vector2 = Vector2(0, _world.player_jump_offset())
	var player_texture: Texture2D = _actor_texture(
		_world.player_sprite(), _world.player_palette(), _world.player_facing,
		_world.player_walk_frame()
	)
	if player_texture != null:
		draw_texture(player_texture, player + jump)
		if _in_grass(_world.player_cell):
			_draw_grass_over(player + jump, camera_pixels)
		if _world.fishing_busy():
			_draw_fishing_rod(player + jump)
	else:
		var marker := Rect2(Vector2(player.x, player.y), Vector2(16, 16))
		draw_rect(marker, PLAYER_COLOR, false, 1.0)
		draw_line(marker.position, marker.end, PLAYER_COLOR, 1.0)
		draw_line(Vector2(marker.end.x, marker.position.y), Vector2(marker.position.x, marker.end.y), PLAYER_COLOR, 1.0)
	if battlers_only:
		return
	_draw_effect_sprites(-1, player)
	## The tree sprite stands over its own cell rather than over an object, and
	## the source draws every one of these from `wShadowOAMSprite36` up, which is
	## past every map object. `Cut_Headbutt_GetPixelFacing` is a sprite anim
	## rather than a map object, so it takes no lift.
	for sprite: Dictionary in _effect_sprites():
		if int(sprite["object_index"]) != -2:
			continue
		_draw_effect_sprite(
			sprite,
			Vector2((sprite["cell"] as Vector2i) * Gen2WorldAPI.CELL_PIXELS) - camera_pixels,
		)
	## `HealMachineAnim` writes OAM at fixed screen pixels rather than over an
	## object or a cell, so the camera does not move it.
	for sprite: Dictionary in _effect_sprites():
		if bool(sprite.get("screen", false)):
			_draw_effect_sprite(sprite, Vector2.ZERO)
	_draw_encounter_pulse(camera_pixels)


## `StartTrainerBattle_LoadPokeBallGraphics.copypals` writes the trainer palette
## over `wOBPals1/2 palette PAL_OW_TREE` and `PAL_OW_ROCK` as well as
## `PAL_BG_TEXT`, so a boulder or a fruit tree standing on the map turns with the
## background it is standing on.
func _sprite_palette(palette: int) -> PackedColorArray:
	if not _transition_palette.is_empty() \
		and palette in [Gen2WorldEffects.PAL_OW_TREE, Gen2WorldEffects.PAL_OW_ROCK]:
		return _transition_palette
	return _world.data.overworld_sprite_palette(palette, _time_of_day)


func _actor_texture(
	sprite: Gen2WorldSprite,
	palette_override: int,
	facing: int,
	frame: int,
	big_shape: int = Gen2WorldSprite.BIG_SHAPE_NONE,
	color_override: PackedColorArray = PackedColorArray(),
) -> Texture2D:
	if sprite == null or _world == null or _world.data == null:
		return null
	var palette: int = palette_override if palette_override != 0 else sprite.default_palette
	var key: String = "%d:%d:%d:%d:%d:%d:%d:%d" % [
		sprite.sprite_type, sprite.number, palette, facing, frame, big_shape, _time_of_day,
		hash(color_override),
	]
	if _actor_textures.has(key):
		return _actor_textures[key]
	var indices: PackedByteArray = _world.data.overworld_icon_indices(sprite.icon_number) \
		if sprite.sprite_type == Gen2WorldSprite.TYPE_MON_ICON \
		else _world.data.overworld_sprite_indices(sprite.number)
	## A visible encounter names the species' own four colours; everything else
	## wears one of the map's sprite palettes.
	## `DmgToCgbObjPals` takes the fade's own order too, and `FillWhiteBGColor`
	## is background only, so a sprite flattens onto its own colour 0.
	var colors: PackedColorArray = Gen2WorldPalette.fade_palette(
		color_override if not color_override.is_empty() \
			else _sprite_palette(palette),
		_fade_order,
	)
	var image: Image = Gen2WorldSprite.big_image_for(sprite, indices, colors, big_shape) \
		if big_shape != Gen2WorldSprite.BIG_SHAPE_NONE \
		else Gen2WorldSprite.image_for(sprite, indices, colors, facing, frame)
	var texture: Texture2D = ImageTexture.create_from_image(image)
	_actor_textures[key] = texture
	return texture


## One mod actor, drawn from the [Gen2WorldSprite] the actor layer resolved for
## it. Its position is in walk cells, the unit `player_position_cells()` is in,
## so a follower halfway through a step is drawn halfway.
func _draw_actor(sprite: Dictionary, camera_pixels: Vector2) -> void:
	var cell_position: Vector2 = sprite["position_cells"]
	var pixel: Vector2 = cell_position * float(Gen2WorldAPI.CELL_PIXELS) - camera_pixels \
		+ SPRITE_LIFT
	var texture: Texture2D = _actor_texture(
		sprite["sprite"], 0, int(sprite["facing"]), int(sprite["frame"]),
		Gen2WorldSprite.BIG_SHAPE_NONE, sprite.get("colors", PackedColorArray())
	)
	if texture == null:
		return
	draw_texture(texture, pixel)
	if _in_grass(Vector2i(roundi(cell_position.x), roundi(cell_position.y))):
		_draw_grass_over(pixel, camera_pixels)
	## The same bubble a map object's `showemote` puts up, over an actor that
	## asked for one. Drawn after the grass, as an object's is: `SpawnEmote` is
	## its own OAM and stands over the tuft rather than behind it.
	var emote: int = int(sprite.get("emote", Gen2WorldActors.EMOTE_NONE))
	if emote != Gen2WorldActors.EMOTE_NONE:
		_draw_emote(emote, pixel)


## The object pass's own order, with a mod's actors sorted into it: the row a
## thing stands on, then the map's objects before any actor on that row.
func _sort_drawn(first: Dictionary, second: Dictionary) -> bool:
	if is_equal_approx(float(first["row"]), float(second["row"])):
		if first.has("object") and second.has("object"):
			return _sort_objects(first["object"], second["object"])
		return first.has("object")
	return float(first["row"]) < float(second["row"])


func _sort_objects(first: Gen2WorldObject, second: Gen2WorldObject) -> bool:
	if first.cell.y == second.cell.y:
		return first.index < second.index
	return first.cell.y < second.cell.y


## `SpawnEmote`: four tiles of the emote's own sheet, two rows above the object
## the source's `MovementFunction_Emote` writes `-2 * TILE_WIDTH` for.
func _draw_emote(emote_id: int, pixel: Vector2) -> void:
	if emote_id < 0 or emote_id >= RomLayout.EMOTE_NAMES.size():
		return
	var sheet: Dictionary = _effect_sheet(RomLayout.EMOTE_NAMES[emote_id])
	if sheet.is_empty():
		return
	for index: int in 4:
		_draw_effect_tile(
			sheet,
			index,
			Gen2WorldEffects.PAL_OW_EMOTE,
			false,
			pixel + Vector2((index & 1) * 8, (index >> 1) * 8 - 16),
		)


## `SetTallGrassFlags` sets IN_GRASS_F on an object standing in either kind of
## grass, and `.InitSprite` turns that into OAM_PRIO on the two tiles carrying
## RELATIVE_ATTRIBUTES, which are the bottom half of every facing: the grass in
## front of the object covers its legs.
func _in_grass(cell: Vector2i) -> bool:
	return _world != null and _world.current_map != null \
		and Gen2WorldCollision.is_grass(_world.collision_code_at(cell))


## Redraws the map over the bottom half of a sprite drawn at [param pixel], with
## the transparent index left out, which is what OAM_PRIO amounts to here.
func _draw_grass_over(pixel: Vector2, camera_pixels: Vector2) -> void:
	if _priority_atlas == null:
		_build_priority_atlas()
	if _priority_atlas == null:
		return
	var over := Rect2(
		pixel + Vector2(0, Gen2Tiles.TILE_HEIGHT),
		Vector2(Gen2WorldAPI.CELL_PIXELS, Gen2Tiles.TILE_HEIGHT),
	)
	## The tuft is sixteen by eight pixels, so it covers at most three tiles by
	## two. Walking the whole page for it cost the view's every tile once per
	## sprite standing in grass, which a window-filling view cannot afford.
	var first := Vector2i(
		floori((over.position.x + camera_pixels.x) / float(Gen2Tiles.TILE_WIDTH)),
		floori((over.position.y + camera_pixels.y) / float(Gen2Tiles.TILE_HEIGHT)),
	)
	var last := Vector2i(
		ceili((over.end.x + camera_pixels.x) / float(Gen2Tiles.TILE_WIDTH)),
		ceili((over.end.y + camera_pixels.y) / float(Gen2Tiles.TILE_HEIGHT)),
	)
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			var at := Rect2(
				Vector2(x * Gen2Tiles.TILE_WIDTH, y * Gen2Tiles.TILE_HEIGHT) - camera_pixels,
				Vector2(Gen2Tiles.TILE_WIDTH, Gen2Tiles.TILE_HEIGHT),
			)
			var covered: Rect2 = at.intersection(over)
			if covered.size.x <= 0.0 or covered.size.y <= 0.0:
				continue
			var tile: int = _drawn_tile_at(x, y)
			if tile < 0 or tile >= _world.current_tileset.tile_count:
				continue
			for piece: Rect2 in _priority_pieces(covered):
				draw_texture_rect_region(
					_priority_atlas,
					piece,
					Rect2(
						Vector2(tile * Gen2Tiles.TILE_WIDTH, 0) + (piece.position - at.position),
						piece.size,
					),
				)
	## The transition has already overwritten the map under the sprite, so what
	## wins the priority test where it wrote is its own tile rather than the
	## grass. The pieces above left those cells to it.
	if not _transition_cells.is_empty():
		_draw_transition(camera_pixels, over, true)


## The graphics tile drawn at a map-space tile coordinate, through the same
## block fold the map quad's shader runs.
func _drawn_tile_at(tile_x: int, tile_y: int) -> int:
	if _world == null or _world.current_tileset == null:
		return -1
	var width: int = RomLayout.MAP_BLOCK_TILE_WIDTH
	var block: int = _world.expanded_block_at(
		floori(float(tile_x) / float(width)), floori(float(tile_y) / float(width))
	)
	return _world.current_tileset.tile_index(
		block, posmod(tile_y, width) * width + posmod(tile_x, width)
	)


## The parts of [param rect] the map still owns, split on the screen's own
## 8-pixel grid so a cell `DoBattleTransition` has written is left to it.
func _priority_pieces(rect: Rect2) -> Array[Rect2]:
	if _transition_cells.is_empty():
		return [rect] as Array[Rect2]
	var out: Array[Rect2] = []
	var top: float = rect.position.y
	while top < rect.end.y:
		var bottom: float = minf(floorf(top / Gen2Tiles.TILE_HEIGHT) * Gen2Tiles.TILE_HEIGHT \
			+ Gen2Tiles.TILE_HEIGHT, rect.end.y)
		var left: float = rect.position.x
		while left < rect.end.x:
			var right: float = minf(floorf(left / Gen2Tiles.TILE_WIDTH) * Gen2Tiles.TILE_WIDTH \
				+ Gen2Tiles.TILE_WIDTH, rect.end.x)
			if not _transition_wrote(Vector2(left, top)):
				out.append(Rect2(Vector2(left, top), Vector2(right - left, bottom - top)))
			left = right
		top = bottom
	return out


## Whether the transition has taken the screen cell [param at] falls in.
func _transition_wrote(at: Vector2) -> bool:
	var screen: Vector2 = at - screen_offset()
	var x: int = floori(screen.x / Gen2Tiles.TILE_WIDTH)
	var y: int = floori(screen.y / Gen2Tiles.TILE_HEIGHT)
	if x < 0 or x >= Gen2BattleTransition.COLUMNS \
		or y < 0 or y >= Gen2BattleTransition.ROWS:
		return false
	var index: int = y * Gen2BattleTransition.COLUMNS + x
	return index < _transition_cells.size() \
		and int(_transition_cells[index]) != Gen2BattleTransition.CELL_NONE


## The same strip as the atlas with the cartridge's transparent index left out,
## for the tiles that are drawn over a sprite rather than under it.
func _build_priority_atlas() -> void:
	if _atlas_image == null:
		return
	var image: Image = _atlas_image.duplicate()
	var width: int = image.get_width()
	if _priority_indices.size() < width * Gen2Tiles.TILE_HEIGHT:
		return
	for y: int in Gen2Tiles.TILE_HEIGHT:
		for x: int in width:
			if int(_priority_indices[y * width + x]) == 0:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	_priority_atlas = ImageTexture.create_from_image(image)


## `FacingFishDown` and its three siblings: the standing player plus one tile of
## the rod sheet, which is what `Script_FishCastRod`'s `fish_cast_rod` puts up
## and `PutTheRodAway` takes down.
func _draw_fishing_rod(pixel: Vector2) -> void:
	var sheet: Dictionary = _effect_sheet("rod")
	if sheet.is_empty():
		return
	var facing: int = clampi(_world.player_facing, 0, Gen2WorldEffects.FISHING_ROD_TILES.size() - 1)
	var tile: Dictionary = Gen2WorldEffects.FISHING_ROD_TILES[facing]
	_draw_effect_tile(
		sheet, int(tile["tile"]), Gen2WorldEffects.PAL_OW_EMOTE, bool(tile["flip_x"]),
		pixel + Vector2(tile["offset"] as Vector2i),
	)


## The enemy battler's own box on the battle screen, in pixels: `wShadowOAM` from
## an animation aimed at it is written around this, so translating its centre
## onto a walk cell's is what puts the sparkle over the Pokemon out here.
const BATTLER_CENTRE := Vector2(
	(Gen2BattleScreenMap.ENEMY_AT.x + 0.5 * Gen2BattleScreenMap.ENEMY_SIDE) * Gen2Tiles.TILE_WIDTH,
	(Gen2BattleScreenMap.ENEMY_AT.y + 0.5 * Gen2BattleScreenMap.ENEMY_SIDE) * Gen2Tiles.TILE_HEIGHT
)


## The shiny pulse: the cartridge's own `ANIM_SEND_OUT_MON` objects, drawn where
## the Pokemon stands instead of where a battler would. The field and background
## layer the animation shares the screen with in a battle is simply not run, so
## what lands here is the sparkle and nothing behind it.
func _draw_encounter_pulse(camera_pixels: Vector2) -> void:
	if _encounters == null or _world == null or _world.data == null:
		return
	var anchor: Variant = _encounters.pulse_anchor()
	if not anchor is Vector2:
		return
	var origin: Vector2 = (anchor as Vector2) - camera_pixels \
		+ Vector2(Gen2WorldAPI.CELL_PIXELS, Gen2WorldAPI.CELL_PIXELS) * 0.5 - BATTLER_CENTRE
	var window: Array = _encounters.pulse_tiles()
	var pair: Array = _encounters.pulse_battler_pair()
	for entry: Variant in _encounters.pulse_sprites():
		if entry is Dictionary:
			_draw_pulse_sprite(entry as Dictionary, window, pair, origin)


func _draw_pulse_sprite(
	sprite: Dictionary, window: Array, pair: Array, origin: Vector2
) -> void:
	var at: int = int(sprite.get("tile", 0)) - Gen2BattleAnimObject.BASE_TILE
	if at < 0 or at >= window.size() or not window[at] is Dictionary:
		return
	var slot: Dictionary = window[at]
	# `anim_battlergfx_*` moves a battler as objects and has no picture out here.
	if not slot.has("gfx"):
		return
	var attributes: int = int(sprite.get("attributes", 0))
	var texture: Texture2D = _pulse_texture(
		int(slot["gfx"]), int(slot["tile"]), attributes, pair
	)
	if texture == null:
		return
	draw_texture(texture, origin + Vector2(
		float(int(sprite.get("x", 0)) - 8), float(int(sprite.get("y", 0)) - 16)
	))


func _pulse_texture(
	gfx: int, tile: int, attributes: int, pair: Array
) -> Texture2D:
	var key: String = "%d:%d:%d:%s" % [
		gfx, tile, attributes & (Gen2BattleAnimObject.OAM_SHARED_FLAGS
			| Gen2BattleAnimObject.OAM_PALETTE), str(pair),
	]
	if _anim_textures.has(key):
		return _anim_textures[key]
	var strip: PackedByteArray = _world.data.battle_anim_gfx_indices(gfx)
	@warning_ignore("integer_division")
	var width: int = strip.size() / Gen2Tiles.TILE_HEIGHT
	if width <= 0 or (tile + 1) * Gen2Tiles.TILE_WIDTH > width:
		return null
	var pixels := PackedByteArray()
	pixels.resize(Gen2Tiles.TILE_PIXELS)
	for row: int in Gen2Tiles.TILE_HEIGHT:
		var from: int = row * width + tile * Gen2Tiles.TILE_WIDTH
		for column: int in Gen2Tiles.TILE_WIDTH:
			pixels[row * Gen2Tiles.TILE_WIDTH + column] = strip[from + column]
	var image: Image = Gen2PicImage.from_indices(
		pixels, Gen2Tiles.TILE_WIDTH, Gen2Tiles.TILE_HEIGHT,
		_world.data.battle_object_palette(
			attributes & Gen2BattleAnimObject.OAM_PALETTE, pair
		),
		true
	)
	if (attributes & Gen2BattleAnimObject.OAM_XFLIP) != 0:
		image.flip_x()
	if (attributes & Gen2BattleAnimObject.OAM_YFLIP) != 0:
		image.flip_y()
	var texture: Texture2D = ImageTexture.create_from_image(image)
	_anim_textures[key] = texture
	return texture


func _effect_sprites() -> Array:
	return _effects.sprites() if _effects != null else []


## Whatever [param object_index] is carrying this frame, drawn over it: the dust
## and the grass rustle are STEP_TYPE_TRACKING_OBJECT and follow the object that
## spawned them, so their anchor is where that object is drawn. -1 is the player.
func _draw_effect_sprites(object_index: int, pixel: Vector2) -> void:
	for sprite: Dictionary in _effect_sprites():
		if bool(sprite.get("screen", false)):
			continue
		if int(sprite["object_index"]) == object_index:
			_draw_effect_sprite(sprite, pixel)


func _draw_effect_sprite(sprite: Dictionary, anchor: Vector2) -> void:
	var sheet: Dictionary = _effect_sheet(String(sprite["kind"]))
	if sheet.is_empty():
		return
	for tile: Dictionary in sprite["tiles"]:
		_draw_effect_tile(
			sheet,
			int(tile["tile"]),
			int(sprite["palette"]),
			bool(tile["flip_x"]),
			anchor + Vector2(tile["offset"] as Vector2i),
			int(sprite.get("rotation", 0)),
		)


## A sheet with a `colors` of its own is the heal machine, whose palette
## `.LoadPalettes` writes over PAL_OW_TREE and `.FlashPalettes` then rotates
## left. Everything else wears the overworld palette its spawn named, at the
## time of day the map is on.
func _effect_palette(sheet: Dictionary, palette_index: int, rotation_step: int) -> PackedColorArray:
	var own: PackedColorArray = sheet.get("colors", PackedColorArray())
	if own.is_empty():
		return _world.data.overworld_sprite_palette(palette_index, _time_of_day)
	var rotated := PackedColorArray()
	for slot: int in own.size():
		rotated.append(own[(slot + rotation_step) % own.size()])
	return rotated


func _effect_sheet(sheet_name: String) -> Dictionary:
	if _world == null or _world.data == null:
		return {}
	if _effect_sheets.has(sheet_name):
		return _effect_sheets[sheet_name]
	var sheet: Dictionary = _world.data.overworld_effect(sheet_name)
	_effect_sheets[sheet_name] = sheet
	return sheet


## One 8x8 tile of an effect sheet. Index 0 is the transparent colour here, as it
## is for every object: these are sprites, not background.
## [param rotation] is `.FlashPalettes`' rotate-left count, which only a sheet
## carrying its own palette can be asked for.
func _draw_effect_tile(
	sheet: Dictionary, tile: int, palette_index: int, flip_x: bool, at: Vector2,
	rotation_step: int = 0
) -> void:
	var key: String = "%s:%d:%d:%d:%d:%d" % [
		sheet["name"], tile, palette_index, int(flip_x), _time_of_day, rotation_step,
	]
	var texture: Texture2D = _effect_textures.get(key, null)
	if texture == null:
		var indices: PackedByteArray = sheet["indices"]
		var tiles: int = int(sheet["tiles"])
		if tile < 0 or tile >= tiles or indices.size() < tiles * Gen2Tiles.TILE_PIXELS:
			return
		var palette: PackedColorArray = _effect_palette(sheet, palette_index, rotation_step)
		var image := Image.create(
			Gen2Tiles.TILE_WIDTH, Gen2Tiles.TILE_HEIGHT, false, Image.FORMAT_RGBA8
		)
		var width: int = tiles * Gen2Tiles.TILE_WIDTH
		for y: int in Gen2Tiles.TILE_HEIGHT:
			for x: int in Gen2Tiles.TILE_WIDTH:
				var color_index: int = int(indices[y * width + tile * Gen2Tiles.TILE_WIDTH + x])
				var color: Color = palette[color_index] if color_index < palette.size() \
					else Color.MAGENTA
				if color_index == 0:
					color.a = 0.0
				image.set_pixel(x, y, color)
		if flip_x:
			image.flip_x()
		texture = ImageTexture.create_from_image(image)
		_effect_textures[key] = texture
	draw_texture(texture, at)
