extends SceneTree

## Verifies Headbutt against freshly imported real caches, for both command
## profiles.
##
## The expected values come from the pinned pokecrystal and pokegold sources:
## engine/events/overworld.asm's TryHeadbuttOW and HeadbuttScript,
## engine/events/treemons.asm's TreeMonEncounter, GetTreeMonSet, GetTreeMons,
## GetTreeMon and SelectTreeMon, home/map_objects.asm's CheckHeadbuttTreeTile,
## and data/wild/treemon_maps.asm and treemons.asm.
##
## The real-cartridge counterpart to tests/unit/test_world_treemon.gd and the
## headbutt half of tests/unit/test_world_field_move.gd, both of which use
## hand-built tables. Ilex Forest is the acceptance case, because its trees are
## the same cells in all three games.
##
##   Godot --headless --path . -s res://tools/validate_headbutt.gd

const GAME_IDS: Array[StringName] = [&"gold", &"silver", &"crystal"]

## constants/map_constants.asm, DUNGEONS group. Crystal's extra maps push
## Ilex Forest eight places later within the same group, as validate_cut.gd
## records for the same map.
const ILEX_GROUP: int = 3
const ILEX_NUMBER_CRYSTAL: int = 52
const ILEX_NUMBER_GOLD_SILVER: int = 44
## A headbutt tree on Ilex Forest's north edge, approachable from below in all
## three games, and the cell the player stands on to face it.
const ILEX_TREE_CELL := Vector2i(13, 0)
const ILEX_STAND_CELL := Vector2i(13, 1)

## data/wild/treemon_maps.asm's first and last TreeMonMaps rows, whose set
## numbers differ because the TREEMON_SET_* order does: ROUTE_26 is KANTO on
## Crystal and FOREST on Gold and Silver, and ILEX_FOREST is FOREST in both
## orders but at a different number.
const EXPECTED_ROUTE_26: Dictionary = {&"gold": 1, &"silver": 1, &"crystal": 4}
const EXPECTED_ILEX_SET: Dictionary = {&"gold": 1, &"silver": 1, &"crystal": 6}
const ROUTE_26_GROUP: int = 24
const ROUTE_26_NUMBER: int = 1

## Census of the real caches, pinned so a cache change is loud. The second pair
## counts only the cells whose map resolves to a set this profile will read:
## Crystal marks many of its own tree maps TREEMON_SET_NONE, and Gold and
## Silver refuse TREEMON_SET_CITY outright, so both lose cells here for
## different reasons.
const EXPECTED_CENSUS: Dictionary = {
	# game id: [tree cells, maps, cells with a usable set, maps with one]
	&"gold": [1026, 24, 891, 19],
	&"silver": [1026, 24, 891, 19],
	&"crystal": [1056, 26, 881, 19],
}

## data/wild/treemons.asm's TreeMonSet_Rock, the one set with no rare table:
## `db 90, KRABBY, 15` and `db 10, SHUCKLE, 15`.
const KRABBY: int = 98
const SHUCKLE: int = 213

var _failures: PackedStringArray = []


func _initialize() -> void:
	for game_id: StringName in GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		var crystal: bool = Gen2WorldState.is_crystal_profile(data)
		_verify_map_tables(game_id, data, crystal)
		_verify_sets(game_id, data, crystal)
		_census(game_id, data, crystal)
		_verify_ilex_forest(game_id, data, crystal)
	_finish()


## GetTreeMonSet against the imported TreeMonMaps and RockMonMaps, at the two
## rows whose set numbers prove the profile's own TREEMON_SET_* order was used.
func _verify_map_tables(game_id: StringName, data: GameData, crystal: bool) -> void:
	_check(
		data.treemon_set_for_map(ROUTE_26_GROUP, ROUTE_26_NUMBER) \
			== int(EXPECTED_ROUTE_26[game_id]),
		"%s: ROUTE_26's treemon set is %d, not the pinned %d." % [
			game_id, data.treemon_set_for_map(ROUTE_26_GROUP, ROUTE_26_NUMBER),
			int(EXPECTED_ROUTE_26[game_id]),
		]
	)
	var ilex: int = ILEX_NUMBER_CRYSTAL if crystal else ILEX_NUMBER_GOLD_SILVER
	_check(
		data.treemon_set_for_map(ILEX_GROUP, ilex) == int(EXPECTED_ILEX_SET[game_id]),
		"%s: Ilex Forest's treemon set is %d, not the pinned %d." % [
			game_id, data.treemon_set_for_map(ILEX_GROUP, ilex),
			int(EXPECTED_ILEX_SET[game_id]),
		]
	)
	# RockMonMaps is imported for Rock Smash, which is not implemented; the
	# four rows are checked here so the table cannot rot unnoticed.
	var rock_maps: Array = [
		Vector2i(22, 3), Vector2i(22, 1), Vector2i(3, 78 if crystal else 70),
		Vector2i(3, 40 if crystal else 32),
	]
	for pair: Vector2i in rock_maps:
		var set_number: int = data.treemon_set_for_map(pair.x, pair.y, true)
		_check(
			set_number == (7 if crystal else 3),
			"%s: RockMonMaps row %s names set %d, not TREEMON_SET_ROCK." % [
				game_id, pair, set_number,
			]
		)


## Every set a map table names must be readable, and TreeMonSet_Rock must be
## the one that carries no rare table.
func _verify_sets(game_id: StringName, data: GameData, crystal: bool) -> void:
	var rock_set: int = 7 if crystal else 3
	var rock: Dictionary = data.treemon_set(rock_set)
	_check(
		(rock.get("common", []) as Array).size() == 2,
		"%s: TreeMonSet_Rock has %d common rows, not 2." % [
			game_id, (rock.get("common", []) as Array).size(),
		]
	)
	_check(
		(rock.get("rare", []) as Array).is_empty(),
		"%s: TreeMonSet_Rock read a rare table it does not have." % game_id
	)
	var rows: Array = rock.get("common", [])
	if rows.size() == 2:
		_check(
			int(rows[0]["species"]) == KRABBY and int(rows[0]["percent"]) == 90 \
				and int(rows[1]["species"]) == SHUCKLE and int(rows[1]["percent"]) == 10,
			"%s: TreeMonSet_Rock is not the pinned 90 KRABBY / 10 SHUCKLE." % game_id
		)
	# GetTreeMons refuses set 0 and everything at or past the profile's limit,
	# so every other set must carry a common table for a headbutt to resolve.
	for index: int in range(1, Gen2WorldTreemon.set_limit(crystal)):
		var record: Dictionary = data.treemon_set(index)
		_check(
			not (record.get("common", []) as Array).is_empty(),
			"%s: treemon set %d has no common table." % [game_id, index]
		)


## Counts the headbutt trees a real cache carries, and how many of them stand on
## a map whose set this profile will actually read, so a cache change is loud
## rather than silently emptying the trees.
func _census(game_id: StringName, data: GameData, crystal: bool) -> void:
	var cells: int = 0
	var usable_cells: int = 0
	var maps: Dictionary = {}
	var usable_maps: Dictionary = {}
	for map: Gen2WorldMap in data.world_maps():
		var usable: bool = Gen2WorldTreemon.set_is_usable(
			data.treemon_set_for_map(map.group, map.number), crystal
		)
		for y: int in map.collision_height:
			for x: int in map.collision_width:
				if not Gen2WorldFieldMove.headbutt_tile(map.collision_at(x, y)):
					continue
				cells += 1
				maps[Vector2i(map.group, map.number)] = true
				if usable:
					usable_cells += 1
					usable_maps[Vector2i(map.group, map.number)] = true
	var counts: Array = [cells, maps.size(), usable_cells, usable_maps.size()]
	print("%s: %d headbutt trees over %d maps, %d of them on the %d maps with a usable set." % [
		game_id, counts[0], counts[1], counts[2], counts[3],
	])
	_check(
		counts == EXPECTED_CENSUS.get(game_id, []),
		"%s: census is %s, not the pinned %s." % [
			game_id, counts, EXPECTED_CENSUS.get(game_id, []),
		]
	)


## The acceptance case: a real tree, faced from a real cell, with no badge set
## anywhere, staged and then committed.
func _verify_ilex_forest(game_id: StringName, data: GameData, crystal: bool) -> void:
	var number: int = ILEX_NUMBER_CRYSTAL if crystal else ILEX_NUMBER_GOLD_SILVER
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, ILEX_GROUP, number, ILEX_STAND_CELL, Gen2WorldState.new()
	)
	if not _check(
		world != null, "%s: Ilex Forest map %d/%d is missing." % [game_id, ILEX_GROUP, number]
	):
		return
	world.player_facing = Gen2WorldSprite.FACING_UP
	# GetTreeScore over this cell: wPlayerMapX/Y are (17,4), so 4 * 18 + 17 =
	# 89, 89 / 5 = 17 and 17 % 10 = 7. An ID scoring 7 is the equal case, which
	# is RARE, and seed 1's first RandomRange(10) is 7, under RARE's threshold
	# of 8. Both halves are therefore pinned and the commit must produce a mon.
	world.set_player_id(7)
	_check(
		Gen2WorldFieldMove.headbutt_tile(world.collision_code_at(ILEX_TREE_CELL)),
		"%s: Ilex Forest %s is not a headbutt tree." % [game_id, ILEX_TREE_CELL]
	)
	_check(
		not world.can_walk_to(ILEX_TREE_CELL),
		"%s: Ilex Forest's headbutt tree does not block." % game_id
	)

	# CheckPartyMove is the whole gate, so a party without HEADBUTT refuses and
	# a party with it resolves, on a state carrying no badge at all.
	var refused: Dictionary = world.headbutt_request()
	_check(
		StringName(refused.get("reason", &"")) == &"move_not_known",
		"%s: a party without HEADBUTT answered %s." % [game_id, refused]
	)
	_headbutt_party(world)
	var request: Dictionary = world.headbutt_request()
	if not _check(
		bool(request.get("ok", false)),
		"%s: Ilex Forest headbutt refused with %s." % [game_id, request.get("reason", "")]
	):
		return

	var block_before: int = world.block_at(ILEX_TREE_CELL.x >> 1, ILEX_TREE_CELL.y >> 1)
	var random := RandomNumberGenerator.new()
	random.seed = 1
	var applied: Dictionary = world.complete_headbutt(random)
	_check(
		bool(applied.get("ok", false)),
		"%s: Ilex Forest headbutt commit failed with %s." % [game_id, applied.get("reason", "")]
	)
	_check(
		world.block_at(ILEX_TREE_CELL.x >> 1, ILEX_TREE_CELL.y >> 1) == block_before,
		"%s: a headbutt changed the tree's block; ShakeHeadbuttTree changes none." % game_id
	)
	_check(
		not world.can_walk_to(ILEX_TREE_CELL),
		"%s: the tree stopped blocking after a headbutt." % game_id
	)

	# Every species the set can produce must be a real imported one, whichever
	# way the roll went, and a produced encounter must carry BATTLETYPE_TREE.
	var encounter: Dictionary = applied.get("encounter", {})
	if _check(
		not encounter.is_empty(),
		"%s: a pinned RARE score and roll produced no encounter." % game_id
	):
		_check(
			int(encounter["score"]) == Gen2WorldTreemon.SCORE_RARE,
			"%s: Ilex Forest scored %d, not RARE." % [game_id, int(encounter["score"])]
		)
		_check(
			not data.species(int(encounter["pokemon"])).is_empty(),
			"%s: Ilex Forest produced unknown species %d." % [game_id, int(encounter["pokemon"])]
		)
		_check(
			int(encounter["values"]["battle_type"]) == Gen2Battle.BATTLETYPE_TREE,
			"%s: a headbutt battle is not BATTLETYPE_TREE." % game_id
		)
		print("%s: Ilex Forest %s headbutted to species %d at level %d." % [
			game_id, ILEX_TREE_CELL, int(encounter["pokemon"]), int(encounter["level"]),
		])

	# The other half of GetTreeMon: an ID two below the coordinate score is
	# BAD, whose whole threshold is a roll of zero, so the same seed falls to
	# HeadbuttScript's .no_battle branch.
	world.set_player_id(2)
	_headbutt_party(world)
	if bool(world.headbutt_request().get("ok", false)):
		var bad_random := RandomNumberGenerator.new()
		bad_random.seed = 1
		var bad: Dictionary = world.complete_headbutt(bad_random)
		_check(
			(bad.get("encounter", {}) as Dictionary).is_empty(),
			"%s: a failed BAD roll still produced an encounter." % game_id
		)
	_verify_asleep_lists(game_id, data, crystal)


## CheckSleepingTreeMon is Crystal only: pokegold ships neither the routine nor
## data/wild/treemons_asleep.asm, so its lists must be empty and no Gold or
## Silver tree encounter can start asleep.
func _verify_asleep_lists(game_id: StringName, data: GameData, crystal: bool) -> void:
	var night: Array = data.asleep_treemons(Gen2WorldPalette.TIME_NIGHT)
	var day: Array = data.asleep_treemons(Gen2WorldPalette.TIME_DAY)
	var morning: Array = data.asleep_treemons(Gen2WorldPalette.TIME_MORNING)
	if not crystal:
		_check(
			night.is_empty() and day.is_empty() and morning.is_empty(),
			"%s: imported asleep treemon lists, which pokegold does not ship." % game_id
		)
		return
	_check(
		night.size() == 11 and day.size() == 5 and morning.size() == 5,
		"%s: asleep list sizes are %d/%d/%d, not the pinned 11/5/5." % [
			game_id, night.size(), day.size(), morning.size(),
		]
	)
	_check(
		day == morning,
		"%s: AsleepTreeMonsDay and AsleepTreeMonsMorn are byte identical in the pin." % game_id
	)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS headbutt: map tables, sets, the census and Ilex Forest verified.")
		quit(0)
		return
	for message: String in _failures:
		print("FAIL %s" % message)
	quit(1)


## CheckPartyMove gates Headbutt and nothing else does, so the acceptance world
## carries one member that knows it.
func _headbutt_party(world: Gen2WorldAPI) -> void:
	world.set_party_summary(
		1, false, [1] as Array[int], [[Gen2WorldFieldMove.MOVE_HEADBUTT]],
		["MON"], [false]
	)
