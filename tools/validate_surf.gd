extends SceneTree

## Verifies Surf against freshly imported real caches, for both command profiles.
##
## The expected values come from the pinned pokecrystal and pokegold sources:
## engine/events/overworld.asm's SurfFunction (.TrySurf, GetSurfType,
## CheckDirection) and UsedSurfScript, engine/overworld/player_object.asm's
## SurfStartStep, and engine/overworld/player_movement.asm's .TrySurf/.ExitWater.
##
## The real-cartridge counterpart to tests/unit/test_world_field_move.gd, which
## uses a synthetic cache. New Bark Town is the acceptance case: its east shore
## is the first real water a player walks up to, and maps/NewBarkTown.blk and
## data/tilesets/johto_collision.asm are byte identical between the pins, so the
## same cells answer on all three games.
##
##   Godot --headless --path . -s res://tools/validate_surf.gd

const GAME_IDS: Array[StringName] = [&"gold", &"silver", &"crystal"]

## constants/map_constants.asm, NEW_BARK group. Unlike Ilex Forest, Crystal's
## extra maps are all in earlier groups, so the pair is the same in both.
const NEW_BARK_GROUP: int = 24
const NEW_BARK_NUMBER: int = 4
## maps/NewBarkTown.blk through data/tilesets/johto_collision.asm: the town's
## east shore. x=19 is the map edge into Route 27, so the checks stay on x=18.
const SHORE_CELL := Vector2i(17, 6)
const WATER_CELL := Vector2i(18, 6)
const COLL_FLOOR: int = 0x00
const COLL_WATER: int = 0x29

## Census of the real caches, pinned so a cache change is loud. A surf-entry cell
## is a land cell with a water neighbour the standing tile's own permissions do
## not wall off, which is exactly what .TrySurf accepts.
const EXPECTED_CENSUS: Dictionary = {
	# game id: [surf-entry cells, maps offering one]
	&"gold": [2141, 66],
	&"silver": [2141, 66],
	&"crystal": [2116, 66],
}

var _failures: PackedStringArray = []


func _initialize() -> void:
	for game_id: StringName in GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		var crystal: bool = Gen2WorldState.is_crystal_profile(data)
		_verify_surf_sprites(game_id, data)
		_verify_surf_music(game_id, data)
		_census(game_id, data)
		_verify_new_bark_town(game_id, data, crystal)
	_finish()


## ChrisStateSprites names two sprites this renderer has to draw, so a cache
## whose sprite table stops short would fail loudly rather than falling back to
## the missing-sprite marker.
func _verify_surf_sprites(game_id: StringName, data: GameData) -> void:
	for number: int in [Gen2WorldSprite.SPRITE_SURF, Gen2WorldSprite.SPRITE_SURFING_PIKACHU]:
		var sprite: Gen2WorldSprite = data.overworld_sprite(number)
		if not _check(
			sprite != null, "%s: overworld sprite %d is missing." % [game_id, number]
		):
			continue
		_check(
			sprite.sprite_type == Gen2WorldSprite.TYPE_WALKING,
			"%s: overworld sprite %d is type %d, not WALKING." % [
				game_id, number, sprite.sprite_type,
			]
		)
		_check(
			sprite.tiles == 12,
			"%s: overworld sprite %d has %d tiles, not the 12 sprites.asm declares." % [
				game_id, number, sprite.tiles,
			]
		)
		_check(
			not data.overworld_sprite_indices(number).is_empty(),
			"%s: overworld sprite %d has no decoded tile strip." % [game_id, number]
		)


## SpecialMapMusic answers MUSIC_SURF ahead of the map header, so the record has
## to exist in every cache.
func _verify_surf_music(game_id: StringName, data: GameData) -> void:
	_check(
		not data.world_audio(&"music", Gen2WorldFieldMove.MUSIC_SURF).is_empty(),
		"%s: music record %d (MUSIC_SURF) is missing." % [game_id, Gen2WorldFieldMove.MUSIC_SURF]
	)


## Counts the cells a real cache actually offers Surf, so a cache change that
## moves a shore or a collision code is loud.
func _census(game_id: StringName, data: GameData) -> void:
	var entry_cells: int = 0
	var maps_with_surf: Dictionary = {}
	for map: Gen2WorldMap in data.world_maps():
		var tileset: Gen2WorldTileset = data.world_tileset(map.tileset)
		if tileset == null:
			continue
		var world: Gen2WorldAPI = Gen2WorldAPI.new(
			data, map, tileset, Vector2i.ZERO, Gen2WorldState.new()
		)
		for y: int in map.collision_height:
			for x: int in map.collision_width:
				var cell := Vector2i(x, y)
				if world.collision_permission_at(cell) != Gen2WorldCollision.LAND_TILE:
					continue
				var permissions: int = world.tile_permissions_at(cell)
				for direction: Vector2i in [
					Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT
				]:
					var neighbour: Vector2i = cell + direction
					if neighbour.x < 0 or neighbour.y < 0 \
						or neighbour.x >= map.collision_width \
						or neighbour.y >= map.collision_height:
						continue
					if world.collision_permission_at(neighbour) \
						!= Gen2WorldCollision.WATER_TILE:
						continue
					if (permissions & Gen2WorldCollision.face_mask_for_direction(direction)) != 0:
						continue
					entry_cells += 1
					maps_with_surf[Vector2i(map.group, map.number)] = true
	var counts: Array = [entry_cells, maps_with_surf.size()]
	print("%s: %d surf-entry cells across %d maps." % [game_id, counts[0], counts[1]])
	_check(
		counts == EXPECTED_CENSUS.get(game_id, []),
		"%s: census is %s, not the pinned %s." % [
			game_id, counts, EXPECTED_CENSUS.get(game_id, []),
		]
	)


func _verify_new_bark_town(game_id: StringName, data: GameData, crystal: bool) -> void:
	var badge: int = Gen2WorldState.badge_flag(Gen2WorldFieldMove.BADGE_FOG, crystal)
	var state := Gen2WorldState.new()
	state.set_engine_flag(badge)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, NEW_BARK_GROUP, NEW_BARK_NUMBER, SHORE_CELL, state
	)
	if not _check(
		world != null,
		"%s: New Bark Town map %d/%d is missing." % [
			game_id, NEW_BARK_GROUP, NEW_BARK_NUMBER,
		]
	):
		return
	world.player_facing = Gen2WorldSprite.FACING_RIGHT

	var shore_code: int = world.collision_code_at(SHORE_CELL)
	_check(
		shore_code == COLL_FLOOR,
		"%s: New Bark Town %s is $%02X, not COLL_FLOOR." % [game_id, SHORE_CELL, shore_code]
	)
	var water_code: int = world.collision_code_at(WATER_CELL)
	_check(
		water_code == COLL_WATER,
		"%s: New Bark Town %s is $%02X, not COLL_WATER." % [game_id, WATER_CELL, water_code]
	)
	# Walking cannot enter the water; that is what Surf is for.
	_check(
		not world.can_walk_to(WATER_CELL, Vector2i.RIGHT),
		"%s: New Bark Town %s is walkable on foot." % [game_id, WATER_CELL]
	)

	var staged: Dictionary = world.surf_request()
	if not _check(
		bool(staged.get("ok", false)),
		"%s: New Bark Town refused Surf: %s." % [game_id, staged.get("reason", "unknown")]
	):
		return
	_check(
		staged.get("cell", Vector2i.ZERO) == WATER_CELL
			and int(staged.get("sprite", -1)) == Gen2WorldSprite.SPRITE_SURF,
		"%s: New Bark Town staged %s, not %s with sprite %d." % [
			game_id, JSON.stringify(staged), WATER_CELL, Gen2WorldSprite.SPRITE_SURF,
		]
	)
	# UsedSurfScript reaches writevar VAR_MOVEMENT only after its waitbutton, so
	# staging alone must leave the player exactly where they were.
	_check(
		world.player_cell == SHORE_CELL
			and world.movement_mode == Gen2WorldAPI.MOVEMENT_WALK,
		"%s: New Bark Town moved the player before the surf was committed." % game_id
	)

	_check(
		bool(world.complete_surf().get("ok", false)),
		"%s: New Bark Town surf did not commit." % game_id
	)
	_check(
		world.player_cell == WATER_CELL
			and world.movement_mode == Gen2WorldAPI.MOVEMENT_SURF
			and world.player_sprite_number == Gen2WorldSprite.SPRITE_SURF,
		"%s: New Bark Town surf left the player at %s in %s with sprite %d." % [
			game_id, world.player_cell, world.movement_mode, world.player_sprite_number,
		]
	)
	_check(
		StringName(world.surf_request().get("reason", &"")) == &"already_surfing",
		"%s: New Bark Town allowed a second Surf while surfing." % game_id
	)
	print("%s: New Bark Town %d/%d %s -> %s, surfing on sprite %d." % [
		game_id, NEW_BARK_GROUP, NEW_BARK_NUMBER, SHORE_CELL, WATER_CELL,
		Gen2WorldSprite.SPRITE_SURF,
	])

	# .ExitWater restores PLAYER_NORMAL and the walking sprite as the step onto
	# land is taken.
	var exited: Dictionary = world.move_result(Vector2i.LEFT)
	_check(
		bool(exited.get("ok", false))
			and StringName(exited.get("kind", &"")) == &"exit_water",
		"%s: New Bark Town step back to land reported %s." % [game_id, JSON.stringify(exited)]
	)
	_check(
		world.player_cell == SHORE_CELL
			and world.movement_mode == Gen2WorldAPI.MOVEMENT_WALK
			and world.player_sprite_number == Gen2WorldSprite.SPRITE_PLAYER,
		"%s: New Bark Town exit water left the player at %s in %s with sprite %d." % [
			game_id, world.player_cell, world.movement_mode, world.player_sprite_number,
		]
	)

	# .TrySurf tests the badge before the tile, on whichever engine flag table
	# this profile numbers ENGINE_FOGBADGE on.
	var unbadged_world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, NEW_BARK_GROUP, NEW_BARK_NUMBER, SHORE_CELL, Gen2WorldState.new()
	)
	unbadged_world.player_facing = Gen2WorldSprite.FACING_RIGHT
	_check(
		StringName(unbadged_world.surf_request().get("reason", &"")) == &"badge_required",
		"%s: New Bark Town allowed Surf without engine flag %d." % [game_id, badge]
	)
	# The other profile's flag number must not answer for this one.
	var wrong := Gen2WorldState.new()
	wrong.set_engine_flag(Gen2WorldState.badge_flag(Gen2WorldFieldMove.BADGE_FOG, not crystal))
	var wrong_world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, NEW_BARK_GROUP, NEW_BARK_NUMBER, SHORE_CELL, wrong
	)
	wrong_world.player_facing = Gen2WorldSprite.FACING_RIGHT
	_check(
		StringName(wrong_world.surf_request().get("reason", &"")) == &"badge_required",
		"%s: New Bark Town accepted the other profile's Fog Badge flag." % game_id
	)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS surf: sprites, music, the cell census and New Bark Town verified.")
		quit(0)
		return
	for message: String in _failures:
		print("FAIL %s" % message)
	quit(1)
