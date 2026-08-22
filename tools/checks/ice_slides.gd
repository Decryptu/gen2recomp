extends RefCounted

var _r: RefCounted = null

## Sweeps every ice cell on every map of all three cartridges through the slide
## `DoPlayerMovement.CheckForced` and `CheckStandingOnIce` produce, rather than
## sampling the Ice Path. The expected shapes come from the pinned
## engine/overworld/player_movement.asm, identical in pokecrystal and pokegold:
## a step onto ice leaves `wPlayerTurningDirection` set, the next poll ORs that
## direction back into `wCurInput`, and the run ends at the first refused step,
## whose `._WalkInPlace` clears the byte.
##
## Two invariants are what a broken slide trips. It has to terminate, which it
## only does because a refusal clears the byte; and with nothing held it has to
## keep the one direction, since a slide that could turn on its own would carry
## the player off a run the map laid out.
##
##   Godot --headless --path . -s res://tools/validate.gd -- ice_slides

## A slide can be no longer than the map, so anything past this is a loop.
const RUN_CEILING: int = 512
## Passes to spend draining one step, above any STEP_PASSES_* this can reach.
const PASS_CEILING: int = 64


func run(r: RefCounted) -> void:
	_r = r
	for game_id: StringName in [&"crystal", &"gold", &"silver"]:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_sweep(game_id, data)


func _sweep(game_id: StringName, data: GameData) -> void:
	var maps_with_ice: int = 0
	var cells: int = 0
	var slides: int = 0
	for map: Gen2WorldMap in data.world_maps():
		var ice_cells: Array[Vector2i] = _ice_cells(map)
		if ice_cells.is_empty():
			continue
		maps_with_ice += 1
		cells += ice_cells.size()
		for cell: Vector2i in ice_cells:
			for direction: Vector2i in [
				Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT
			]:
				if _run_one(game_id, data, map, cell, direction):
					slides += 1
	_r.check(
		maps_with_ice > 0,
		"%s: no map carries COLL_ICE, so nothing was swept." % game_id
	)
	_r.note("%s: %d ice cells over %d maps, %d slides run." % [
		game_id, cells, maps_with_ice, slides
	])


func _ice_cells(map: Gen2WorldMap) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in map.collision_height:
		for x: int in map.collision_width:
			if Gen2WorldCollision.is_ice(map.collision_at(x, y)):
				out.append(Vector2i(x, y))
	return out


## One slide, started from [param cell] walking [param direction]. Returns
## whether a slide actually ran, so a start that bumps at once is not counted.
func _run_one(
	game_id: StringName,
	data: GameData,
	map: Gen2WorldMap,
	cell: Vector2i,
	direction: Vector2i,
) -> bool:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, map.group, map.number, cell, Gen2WorldState.new()
	)
	if world == null:
		return false
	## `.CheckTurning` would spend the first press on the turn, which is the
	## cartridge's own behaviour and not what this is measuring.
	world.player_facing = world.facing_for_direction(direction)
	var where: String = "%s: map %d/%d %s from %s" % [
		game_id, map.group, map.number, str(direction), str(cell)
	]
	if not bool(world.player_input_move(direction).get("ok", false)):
		return false
	var steps: int = 0
	while world.standing_on_ice():
		if not _drain_step(world, where):
			return false
		## `.CheckForced` with nothing held at all, which is the whole point of
		## the routine: the slide supplies its own direction.
		var forced: Vector2i = world.effective_input_direction(Vector2i.ZERO)
		if not _r.check(forced == direction, "%s: the slide turned to %s." % [
			where, str(forced)
		]):
			return false
		steps += 1
		if not _r.check(steps < RUN_CEILING, "%s: the slide never ended." % where):
			return false
		if not bool(world.player_input_move(forced).get("ok", false)):
			## `._WalkInPlace` cleared the byte, so the player is standing on the
			## ice rather than sliding on it and a press is theirs again.
			return _r.check(
				not world.standing_on_ice(),
				"%s: a refused step left the slide running." % where
			)
	return true


func _drain_step(world: Gen2WorldAPI, where: String) -> bool:
	var passes: int = 0
	while world.player_step_in_progress():
		world.advance_player_step_pass()
		passes += 1
		if not _r.check(passes < PASS_CEILING, "%s: a step never finished." % where):
			return false
	return true
