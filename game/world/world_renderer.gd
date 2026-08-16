class_name Gen2WorldRenderer
extends Node2D

## Draws the visible map page and the development player marker in hardware
## pixels. It does not own map state; call [method set_world] when the API
## changes or [method refresh] after a movement.

const PLAYER_COLOR: Color = Color("#d34a5a")
const FALLBACK_BACKGROUND: Color = Color("#f5f1d8")

var _world: Gen2WorldAPI = null
var _animation: Gen2WorldAnimation = null
var _effects: Gen2WorldEffects = null
var _actors: Gen2WorldActors = null
var _encounters: Gen2WorldEncounters = null
var _anim_textures: Dictionary = {}
var _time_of_day: int = Gen2WorldPalette.TIME_MORNING
var _atlas: ImageTexture = null
## Kept beside the texture so an animation frame can repaint the one or two
## tiles it rewrote instead of recolouring the whole strip.
var _atlas_image: Image = null
var _background_color: Color = FALLBACK_BACKGROUND
var _actor_textures: Dictionary = {}
var _priority_atlas: ImageTexture = null
var _priority_indices: PackedByteArray = PackedByteArray()
var _effect_sheets: Dictionary = {}
var _effect_textures: Dictionary = {}


func set_world(world: Gen2WorldAPI, animation: Gen2WorldAnimation = null) -> void:
	_world = world
	_animation = animation
	_actor_textures.clear()
	_effect_textures.clear()
	_rebuild_atlas()
	queue_redraw()


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
	var palettes: Array = _tile_palettes()
	for tile: int in changed:
		_paint_tile(_atlas_image, indices, palettes, tile)
	_atlas.update(_atlas_image)
	_priority_indices = indices
	_priority_atlas = null
	queue_redraw()


func _rebuild_atlas() -> void:
	_atlas = null
	_atlas_image = null
	if _world == null or _world.data == null or _world.current_tileset == null:
		return
	var indices: PackedByteArray = _world.data.world_tileset_indices(_world.current_tileset.number)
	if _animation != null and not _animation.current_indices().is_empty():
		indices = _animation.current_indices()
	var palettes: Array = _tile_palettes()
	if not palettes.is_empty() and (palettes[0] as PackedColorArray).size() >= 1:
		_background_color = (palettes[0] as PackedColorArray)[0]
	else:
		_background_color = FALLBACK_BACKGROUND
	var tile_count: int = _world.current_tileset.tile_count
	if indices.size() < tile_count * Gen2Tiles.TILE_PIXELS:
		return
	_atlas_image = Image.create(
		tile_count * Gen2Tiles.TILE_WIDTH, Gen2Tiles.TILE_HEIGHT, false, Image.FORMAT_RGBA8
	)
	for tile: int in tile_count:
		_paint_tile(_atlas_image, indices, palettes, tile)
	_atlas = ImageTexture.create_from_image(_atlas_image)
	# Built on demand: only an object standing in grass reads it.
	_priority_indices = indices
	_priority_atlas = null


func _tile_palettes() -> Array:
	return Gen2WorldPalette.tile_palettes(
		_world.data,
		_world.current_map,
		_world.current_tileset,
		_time_of_day,
		_animation.water_palette_color() if _animation != null else -1,
		_animation.cave_palette_color() if _animation != null else -1,
	)


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


func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(
		Rect2(Vector2.ZERO, Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)),
		_background_color,
		true,
	)
	if _world == null:
		return

	var camera_pixels: Vector2 = _world.visible_origin_cells() * Gen2WorldAPI.CELL_PIXELS
	var tile_origin := Vector2i(
		floori(camera_pixels.x / float(Gen2Tiles.TILE_WIDTH)),
		floori(camera_pixels.y / float(Gen2Tiles.TILE_HEIGHT)),
	)
	var tile_offset: Vector2 = camera_pixels - Vector2(
		tile_origin.x * Gen2Tiles.TILE_WIDTH,
		tile_origin.y * Gen2Tiles.TILE_HEIGHT,
	)
	var window_size: Vector2i = Gen2WorldAPI.VIEW_TILES + Vector2i.ONE
	var page: PackedInt32Array = _world.tile_indices_in_window(tile_origin, window_size)
	var hidden: Dictionary = _hidden_tree_tiles()
	for y: int in window_size.y:
		for x: int in window_size.x:
			var tile: int = page[y * window_size.x + x]
			if hidden.has(tile_origin + Vector2i(x, y)):
				tile = Gen2WorldEffects.HEADBUTT_TREE_HIDDEN_TILE
			if _atlas == null or tile < 0 or tile >= _world.current_tileset.tile_count:
				continue
			draw_texture_rect_region(
				_atlas,
				Rect2(
					Vector2(x * Gen2Tiles.TILE_WIDTH, y * Gen2Tiles.TILE_HEIGHT) - tile_offset,
					Vector2(8, 8),
				),
				Rect2(Vector2(tile * Gen2Tiles.TILE_WIDTH, 0), Vector2(8, 8)),
			)

	var objects: Array = _world.visible_objects()
	objects.sort_custom(_sort_objects)
	## A mod's actors are drawn in the same pass and sorted into the same rows:
	## a follower one cell below an NPC has to be drawn over it, and one cell
	## above it under it. They carry no emote, no effect sprite and no grass of
	## their own beyond the tuft the map draws over anything standing in it.
	var drawn: Array = []
	for object: Gen2WorldObject in objects:
		drawn.append({"object": object, "row": float(object.cell.y)})
	if _actors != null:
		for sprite: Dictionary in _actors.sprites():
			drawn.append({"actor": sprite, "row": (sprite["position_cells"] as Vector2).y})
	drawn.sort_custom(_sort_drawn)
	for entry: Dictionary in drawn:
		if entry.has("actor"):
			_draw_actor(entry["actor"], camera_pixels, page, tile_origin, tile_offset, window_size)
			continue
		var object: Gen2WorldObject = entry["object"]
		var pixel: Vector2 = Vector2(object.cell * Gen2WorldAPI.CELL_PIXELS) \
			+ Vector2(object.step_offset(Gen2WorldAPI.CELL_PIXELS)) - camera_pixels
		var texture: Texture2D = _actor_texture(
			object.sprite, object.palette, object.facing, object.frame, object.big_object_shape()
		)
		if texture != null:
			draw_texture(texture, pixel)
		if _in_grass(object.cell):
			_draw_grass_over(pixel, page, tile_origin, tile_offset, window_size)
		if object.emote_visible:
			_draw_emote(object.emote_id, pixel)
		_draw_effect_sprites(object.index, pixel)

	var player: Vector2 = Vector2(_world.player_pixel_position())
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
			_draw_grass_over(player + jump, page, tile_origin, tile_offset, window_size)
		if _world.fishing_busy():
			_draw_fishing_rod(player + jump)
	else:
		var marker := Rect2(Vector2(player.x, player.y), Vector2(16, 16))
		draw_rect(marker, PLAYER_COLOR, false, 1.0)
		draw_line(marker.position, marker.end, PLAYER_COLOR, 1.0)
		draw_line(Vector2(marker.end.x, marker.position.y), Vector2(marker.position.x, marker.end.y), PLAYER_COLOR, 1.0)
	_draw_effect_sprites(-1, player)
	## The tree sprite stands over its own cell rather than over an object, and
	## the source draws every one of these from `wShadowOAMSprite36` up, which is
	## past every map object.
	for sprite: Dictionary in _effect_sprites():
		if int(sprite["object_index"]) != -2:
			continue
		_draw_effect_sprite(
			sprite,
			Vector2((sprite["cell"] as Vector2i) * Gen2WorldAPI.CELL_PIXELS) - camera_pixels,
		)
	_draw_encounter_pulse(camera_pixels)


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
	var colors: PackedColorArray = color_override if not color_override.is_empty() \
		else _world.data.overworld_sprite_palette(palette, _time_of_day)
	var image: Image = Gen2WorldSprite.big_image_for(sprite, indices, colors, big_shape) \
		if big_shape != Gen2WorldSprite.BIG_SHAPE_NONE \
		else Gen2WorldSprite.image_for(sprite, indices, colors, facing, frame)
	var texture: Texture2D = ImageTexture.create_from_image(image)
	_actor_textures[key] = texture
	return texture


## One mod actor, drawn from the [Gen2WorldSprite] the actor layer resolved for
## it. Its position is in walk cells, the unit `player_position_cells()` is in,
## so a follower halfway through a step is drawn halfway.
func _draw_actor(
	sprite: Dictionary, camera_pixels: Vector2, page: PackedInt32Array,
	tile_origin: Vector2i, tile_offset: Vector2, window_size: Vector2i
) -> void:
	var position: Vector2 = sprite["position_cells"]
	var pixel: Vector2 = position * float(Gen2WorldAPI.CELL_PIXELS) - camera_pixels
	var texture: Texture2D = _actor_texture(
		sprite["sprite"], 0, int(sprite["facing"]), int(sprite["frame"]),
		Gen2WorldSprite.BIG_SHAPE_NONE, sprite.get("colors", PackedColorArray())
	)
	if texture == null:
		return
	draw_texture(texture, pixel)
	if _in_grass(Vector2i(roundi(position.x), roundi(position.y))):
		_draw_grass_over(pixel, page, tile_origin, tile_offset, window_size)


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
func _draw_grass_over(
	pixel: Vector2,
	page: PackedInt32Array,
	tile_origin: Vector2i,
	tile_offset: Vector2,
	window_size: Vector2i,
) -> void:
	if _priority_atlas == null:
		_build_priority_atlas()
	if _priority_atlas == null:
		return
	var over := Rect2(
		pixel + Vector2(0, Gen2Tiles.TILE_HEIGHT),
		Vector2(Gen2WorldAPI.CELL_PIXELS, Gen2Tiles.TILE_HEIGHT),
	)
	for y: int in window_size.y:
		for x: int in window_size.x:
			var at := Rect2(
				Vector2(x * Gen2Tiles.TILE_WIDTH, y * Gen2Tiles.TILE_HEIGHT) - tile_offset,
				Vector2(Gen2Tiles.TILE_WIDTH, Gen2Tiles.TILE_HEIGHT),
			)
			var covered: Rect2 = at.intersection(over)
			if covered.size.x <= 0.0 or covered.size.y <= 0.0:
				continue
			var tile: int = page[y * window_size.x + x]
			if tile < 0 or tile >= _world.current_tileset.tile_count:
				continue
			draw_texture_rect_region(
				_priority_atlas,
				covered,
				Rect2(
					Vector2(tile * Gen2Tiles.TILE_WIDTH, 0) + (covered.position - at.position),
					covered.size,
				),
			)


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


## The tiles a live effect takes from the map, as a set of absolute tile
## coordinates. See Gen2WorldEffects.hidden_tree_cells().
func _hidden_tree_tiles() -> Dictionary:
	var out: Dictionary = {}
	if _effects == null:
		return out
	for cell: Vector2i in _effects.hidden_tree_cells():
		var origin: Vector2i = cell * RomLayout.MAP_BLOCK_CELL_WIDTH
		for y: int in RomLayout.MAP_BLOCK_CELL_WIDTH:
			for x: int in RomLayout.MAP_BLOCK_CELL_WIDTH:
				out[origin + Vector2i(x, y)] = true
	return out


## Whatever [param object_index] is carrying this frame, drawn over it: the dust
## and the grass rustle are STEP_TYPE_TRACKING_OBJECT and follow the object that
## spawned them, so their anchor is where that object is drawn. -1 is the player.
func _draw_effect_sprites(object_index: int, pixel: Vector2) -> void:
	for sprite: Dictionary in _effect_sprites():
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
		)


func _effect_sheet(name: String) -> Dictionary:
	if _world == null or _world.data == null:
		return {}
	if _effect_sheets.has(name):
		return _effect_sheets[name]
	var sheet: Dictionary = _world.data.overworld_effect(name)
	_effect_sheets[name] = sheet
	return sheet


## One 8x8 tile of an effect sheet. Index 0 is the transparent colour here, as it
## is for every object: these are sprites, not background.
func _draw_effect_tile(
	sheet: Dictionary, tile: int, palette_index: int, flip_x: bool, at: Vector2
) -> void:
	var key: String = "%s:%d:%d:%d:%d" % [
		sheet["name"], tile, palette_index, int(flip_x), _time_of_day,
	]
	var texture: Texture2D = _effect_textures.get(key, null)
	if texture == null:
		var indices: PackedByteArray = sheet["indices"]
		var tiles: int = int(sheet["tiles"])
		if tile < 0 or tile >= tiles or indices.size() < tiles * Gen2Tiles.TILE_PIXELS:
			return
		var palette: PackedColorArray = _world.data.overworld_sprite_palette(
			palette_index, _time_of_day
		)
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
