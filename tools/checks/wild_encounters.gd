extends RefCounted

var _r: RefCounted = null

## Verifies where a wild encounter can be rolled at all, against freshly
## imported real caches, for all three cartridges.
##
## The expected shape comes from engine/overworld/events.asm's RandomEncounter,
## CanEncounterWildMon and CheckWildEncounterCooldown,
## engine/overworld/tile_events.asm's CheckGrassCollision and
## home/map_objects.asm's CheckIceTile. The real-cartridge counterpart to the
## gate cases in tests/unit/test_world_api.gd, which use a hand-built map.
##
## The census is the point: an encounter cell is a small minority of a map's
## walkable cells, and the defect this topic exists to catch was every land cell
## rolling. A route whose grass moves, or a collision code that stops being read
## as grass, moves these counts.
##
##   Godot --headless --path . -s res://tools/validate.gd -- wild_encounters

## Census of the real caches, pinned so a cache or a rule change is loud.
## Per game: encounter cells, maps holding one, and cells refused for ice.
const EXPECTED_CENSUS: Dictionary = {
	&"gold": [39058, 138, 775],
	&"silver": [39058, 138, 775],
	&"crystal": [40156, 146, 779],
}

## Route 29, the first grass a new game walks into, and the same map number in
## all three games (constants/map_constants.asm, group 24).
const ROUTE_29_GROUP: int = 24
const ROUTE_29_NUMBER: int = 3

## Union Cave 1F, whose whole floor rolls because its environment is CAVE.
## pokecrystal inserts eight Ruins of Alph rooms ahead of it in group 3.
const UNION_CAVE_GROUP: int = 3
const UNION_CAVE_NUMBER_CRYSTAL: int = 37
const UNION_CAVE_NUMBER_GOLD_SILVER: int = 29


func run(r: RefCounted) -> void:
	_r = r
	_r.each_game(func() -> void:
		_verify_route_29()
		_verify_union_cave()
		_verify_bug_contest()
		_verify_gate_errand()
		_census()
	)


## The National Park gate, where a contest is entered. Same ids on both
## profiles: group 3 shifts only from Union Cave on, and group 10's gates sit
## ahead of Goldenrod's own inserts.
const GATE_GROUP: int = 10
const GATE_NUMBER: int = 15
const PARK_CONTEST_GROUP: int = 3
const PARK_CONTEST_NUMBER: int = 16
## `Route35OfficerScriptContest` refuses on Sunday, Monday, Wednesday and
## Friday, so the walk is done on a Tuesday.
const CONTEST_WEEKDAY: int = 2
## Route 36's gate, where `BugContestResultsWarpScript` warps to.
const RESULTS_GATE_GROUP: int = 10
const RESULTS_GATE_NUMBER: int = 17


## `Route35OfficerScriptContest` through to `GiveParkBalls`: the errand a player
## actually walks, on the real map with the real script, rather than the specials
## called by hand.
func _verify_gate_errand() -> void:
	var world: Gen2WorldAPI = _r.open_world(GATE_GROUP, GATE_NUMBER, Vector2i.ZERO)
	if world == null:
		return
	world.set_world_clock(CONTEST_WEEKDAY, 12, 0)
	_r.field_move_party(world)
	var talked: Array = _talk_to_officer(world)
	if not _r.check(not talked.is_empty(), "no object at the gate asks about the contest."):
		return

	## The officer's question, then its `yesorno`, then the balls.
	var answered: Array = _drain_to_choice(world, talked)
	if not _r.check(not answered.is_empty(), "the officer never asked a yes/no."):
		return
	world.choose_script_input(0)
	var _entered: Dictionary = _drain_script(world)
	_r.check(
		world.bug_contest_active(),
		"ENGINE_BUG_CONTEST_TIMER is not set after saying yes."
	)
	_r.check(
		world.state.park_balls() == Gen2WorldBugContest.BALLS,
		"the officer handed %d park balls." % world.state.park_balls()
	)
	_r.check(
		world.state.withdrawn_bug_contestants().size()
			== Gen2WorldBugContest.CONTESTANTS_WITHDRAWN,
		"%d contestants withdrew, not five." % world.state.withdrawn_bug_contestants().size()
	)
	_r.check(
		world.map_id() == Vector2i(PARK_CONTEST_GROUP, PARK_CONTEST_NUMBER),
		"the errand ended on map %s, not the contest park." % str(world.map_id())
	)
	_r.check(
		world.bug_contest_minutes_remaining() == Gen2WorldBugContest.MINUTES,
		"the timer opened on %d minutes." % world.bug_contest_minutes_remaining()
	)
	_r.note("gate errand: %d park balls, %d minutes, %d contestants withdrawn." % [
		world.state.park_balls(), world.bug_contest_minutes_remaining(),
		world.state.withdrawn_bug_contestants().size(),
	])

	## `CheckTimeEvents`: twenty minutes on, the contest is over and
	## `BugContestResultsWarpScript` takes the player to the results gate.
	world.set_world_clock(
		CONTEST_WEEKDAY, 12, Gen2WorldBugContest.MINUTES
	)
	## Something caught, so the judging has a score to rank.
	world.state.set_contest_mon({
		"species": 10, "level": 15, "max_hp": 40, "hp": 40, "attack": 20,
		"defense": 20, "speed": 25, "special_attack": 20, "special_defense": 20,
		"dvs": 0xFFFF, "item": 0,
	})
	var over: Array = world.check_bug_contest_timer()
	_r.check(not over.is_empty(), "the timer running out queued nothing.")
	var judged: Dictionary = _drain_script(world)
	_r.check(not judged.is_empty(), "the results script never asked for a judging.")
	if not judged.is_empty():
		_r.check(
			(judged["placings"] as Array).size() == 3,
			"the judging placed %d." % (judged["placings"] as Array).size()
		)
		_r.note("judging: score %d, placed %d, first is %s." % [
			int(judged["score"]), int(judged["player_place"]),
			str((judged["placings"] as Array)[0]),
		])
	_r.check(
		not world.bug_contest_active(),
		"BugContestResultsScript left the contest flag set."
	)
	## `BugContestResultsWarpScript`'s own `warp ROUTE_36_NATIONAL_PARK_GATE`,
	## which it falls into `BugContestResultsScript` past: the same script clears
	## the flag, judges and hands out the prize.
	_r.check(
		world.map_id() == Vector2i(RESULTS_GATE_GROUP, RESULTS_GATE_NUMBER),
		"the contest ended on map %s, not the results gate." % str(world.map_id())
	)
	_r.note("the contest ended on map %s." % str(world.map_id()))


## The step each facing looks along, in FACING_* order.
const FACING_STEPS: Array[Vector2i] = [
	Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT,
]


## Every object on the map faced and talked to, answering with the first one
## whose script says anything. The officer's cell is not pinned: the two gates
## differ between the profiles in nothing else, and a hand-named cell is what
## `HANDOFF.md`'s route habits warn about.
func _talk_to_officer(world: Gen2WorldAPI) -> Array:
	for index: int in world.objects.size():
		var object: Gen2WorldObject = world.objects[index]
		for facing: int in [
			Gen2WorldSprite.FACING_DOWN, Gen2WorldSprite.FACING_UP,
			Gen2WorldSprite.FACING_LEFT, Gen2WorldSprite.FACING_RIGHT,
		]:
			var direction: Vector2i = FACING_STEPS[facing]
			var stand: Vector2i = object.cell - direction
			if stand.x < 0 or stand.y < 0 \
				or stand.x >= world.current_map.collision_width \
				or stand.y >= world.current_map.collision_height:
				continue
			world.player_cell = stand
			world.player_facing = facing
			var results: Array = world.interact()
			if not results.is_empty():
				return results
	return []


## The script run to its end: every text acknowledged and every movement frame
## the applymovements ask for spent, which is what the world screen does a frame
## at a time.
func _drain_script(world: Gen2WorldAPI) -> Dictionary:
	var judged: Dictionary = {}
	var random := RandomNumberGenerator.new()
	random.seed = 13
	for _step: int in 4000:
		if not world.pending_script_wait().is_empty():
			world.advance_script_presentation_frame()
			continue
		if not world.script_busy():
			return judged
		## The one request this errand makes of its host: `BugContestJudging`
		## leaves the placing in wScriptVar, which the script branches on.
		var request: Dictionary = world.pending_runtime_request()
		if StringName(request.get("kind", &"")) == &"bug_contest_judging_requested":
			judged = world.judge_bug_contest(random)
			world.complete_runtime_request({
				"ok": true, "script_value": int(judged.get("player_place", 0)),
			})
			continue
		world.run_event_queue(true)
	return judged


## Runs the script on until it is waiting on a choice, which is the officer's
## own `yesorno`.
func _drain_to_choice(world: Gen2WorldAPI, results: Array) -> Array:
	var out: Array = results.duplicate()
	for _step: int in 40:
		for entry: Dictionary in out:
			var event: Dictionary = entry.get("event", {})
			if StringName(event.get("type", &"")) == &"choice":
				return out
		if not world.script_busy():
			return []
		out = world.run_event_queue(true)
	return []


## `ContestMons` and `BugContestantPointers` as imported, and the contest's own
## encounter over the whole table. All three cartridges ship both byte
## identical, which is why the expected values are not per game.
const CONTEST_SPECIES: Array[int] = [10, 13, 11, 14, 12, 15, 48, 46, 123, 127, 49]
const CONTEST_PERCENTS: Array[int] = [20, 20, 10, 10, 5, 5, 10, 10, 5, 5, 0xFF]
## `BugContestant_BugCatcherDon` and `BugContestant_SchoolboyKipp`, the first and
## last records, as `[class, trainer]`.
const CONTESTANT_EDGES: Array = [[36, 1], [23, 2]]


func _verify_bug_contest() -> void:
	var mons: Array = _r.data.bug_contest_mons()
	if not _r.check(
		mons.size() == Gen2WorldBugContest.NUM_CONTEST_MONS,
		"ContestMons has %d rows, not %d." % [
			mons.size(), Gen2WorldBugContest.NUM_CONTEST_MONS,
		]
	):
		return
	var total: int = 0
	for index: int in mons.size():
		var row: Dictionary = mons[index]
		_r.check(
			int(row["species"]) == CONTEST_SPECIES[index]
				and int(row["percent"]) == CONTEST_PERCENTS[index],
			"ContestMons row %d is %d at %d percent." % [
				index, int(row["species"]), int(row["percent"]),
			]
		)
		if int(row["percent"]) != 0xFF:
			total += int(row["percent"])
	_r.check(total == 100, "ContestMons' percentages add to %d, not 100." % total)

	var contestants: Array = _r.data.bug_contestants()
	if not _r.check(
		contestants.size() == Gen2WorldBugContest.NUM_CONTESTANTS,
		"BugContestantPointers has %d records, not %d." % [
			contestants.size(), Gen2WorldBugContest.NUM_CONTESTANTS,
		]
	):
		return
	for edge: int in CONTESTANT_EDGES.size():
		var entry: Dictionary = contestants[0 if edge == 0 else contestants.size() - 1]
		_r.check(
			int(entry["trainer_class"]) == int(CONTESTANT_EDGES[edge][0])
				and int(entry["trainer"]) == int(CONTESTANT_EDGES[edge][1]),
			"contestant edge %d is class %d trainer %d." % [
				edge, int(entry["trainer_class"]), int(entry["trainer"]),
			]
		)
		_r.check(
			(entry["placings"] as Array).size() == 3,
			"contestant edge %d has %d placings." % [edge, (entry["placings"] as Array).size()]
		)

	## Every draw the walk can produce, over the whole table: a row of it, at a
	## level between that row's own two, and never the `db -1` sentinel.
	var random := RandomNumberGenerator.new()
	random.seed = 7
	var drawn: Dictionary = {}
	for _draw: int in 2000:
		var result: Dictionary = Gen2WorldBugContest.resolve(mons, true, random, true)
		if not _r.check(not result.is_empty(), "a contest draw answered nothing."):
			return
		var species: int = int(result["pokemon"])
		drawn[species] = int(drawn.get(species, 0)) + 1
		for row: Dictionary in mons:
			if int(row["species"]) != species:
				continue
			_r.check(
				int(result["level"]) >= int(row["min_level"])
					and int(result["level"]) <= int(row["max_level"]),
				"a level %d %d is outside its row." % [int(result["level"]), species]
			)
			break
	_r.check(
		not drawn.has(CONTEST_SPECIES[CONTEST_SPECIES.size() - 1]),
		"the sentinel row was drawn."
	)
	_r.check(drawn.size() == mons.size() - 1, "only %d of the ten rows came up." % drawn.size())
	_r.note("bug contest: %d rows, %d contestants, %d species drawn in 2000." % [
		mons.size(), contestants.size(), drawn.size(),
	])


## An outdoor map: only the tiles CheckGrassCollision names roll, and the path
## between them does not.
func _verify_route_29() -> void:
	var world: Gen2WorldAPI = _r.open_world(
		ROUTE_29_GROUP, ROUTE_29_NUMBER, Vector2i.ZERO
	)
	if world == null:
		return
	world.state.set_wild_encounter_cooldown(0)
	var counts: Dictionary = _map_counts(world)
	_r.check(
		world.current_map.environment == Gen2WorldPhoneHost.ENVIRONMENT_ROUTE,
		"Route 29 is environment %d, not ROUTE." % world.current_map.environment
	)
	_r.check(
		int(counts["encounter"]) > 0,
		"Route 29 offers no encounter cell at all."
	)
	_r.check(
		int(counts["encounter"]) < int(counts["walkable"]),
		"Route 29 rolls on all %d of its walkable cells." % int(counts["walkable"])
	)
	_r.note("Route 29: %d encounter cells of %d walkable." % [
		int(counts["encounter"]), int(counts["walkable"]),
	])


## A CAVE map: every walkable cell rolls, which is the branch that skips
## CheckGrassCollision entirely.
func _verify_union_cave() -> void:
	var number: int = UNION_CAVE_NUMBER_CRYSTAL if _r.crystal \
		else UNION_CAVE_NUMBER_GOLD_SILVER
	var world: Gen2WorldAPI = _r.open_world(UNION_CAVE_GROUP, number, Vector2i.ZERO)
	if world == null:
		return
	world.state.set_wild_encounter_cooldown(0)
	if not _r.check(
		world.current_map.environment == Gen2WorldAPI.ENVIRONMENT_CAVE,
		"Union Cave 1F is environment %d, not CAVE." % world.current_map.environment
	):
		return
	var counts: Dictionary = _map_counts(world)
	_r.check(
		int(counts["encounter"]) == int(counts["walkable"]),
		"Union Cave 1F rolls on %d of its %d walkable cells." % [
			int(counts["encounter"]), int(counts["walkable"]),
		]
	)
	_r.note("Union Cave 1F: %d cells, all of them CAVE." % int(counts["encounter"]))


## Every map in the cache, so a rule change is one number rather than one map.
func _census() -> void:
	var cells: int = 0
	var maps: Dictionary = {}
	var iced: int = 0
	for map: Gen2WorldMap in _r.data.world_maps():
		var tileset: Gen2WorldTileset = _r.data.world_tileset(map.tileset)
		if tileset == null:
			continue
		var world := Gen2WorldAPI.new(
			_r.data, map, tileset, Vector2i.ZERO, Gen2WorldState.new()
		)
		world.state.set_wild_encounter_cooldown(0)
		var counts: Dictionary = _map_counts(world)
		cells += int(counts["encounter"])
		iced += int(counts["ice"])
		if int(counts["encounter"]) > 0:
			maps[map.group * 256 + map.number] = true
	var found: Array = [cells, maps.size(), iced]
	_r.note("encounter cells %d over %d maps, %d refused for ice." % [
		cells, maps.size(), iced,
	])
	var expected: Array = EXPECTED_CENSUS[_r.game_id]
	_r.check(
		found == expected,
		"census is %s, not the pinned %s." % [str(found), str(expected)]
	)


## What one map offers: walkable cells, cells CanEncounterWildMon accepts, and
## cells it would have accepted but for the ice test.
func _map_counts(world: Gen2WorldAPI) -> Dictionary:
	var walkable: int = 0
	var encounter: int = 0
	var ice: int = 0
	var map: Gen2WorldMap = world.current_map
	for y: int in map.collision_height:
		for x: int in map.collision_width:
			var cell := Vector2i(x, y)
			var permission: int = world.collision_permission_at(cell)
			if permission != Gen2WorldCollision.LAND_TILE \
				and permission != Gen2WorldCollision.WATER_TILE:
				continue
			walkable += 1
			world.player_cell = cell
			if world.can_encounter_wild_mon():
				encounter += 1
			elif Gen2WorldCollision.is_ice(world.collision_code_at(cell)):
				ice += 1
	return {"walkable": walkable, "encounter": encounter, "ice": ice}
