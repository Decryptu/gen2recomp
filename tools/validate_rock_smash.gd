extends SceneTree

## Verifies Rock Smash against freshly imported real caches, for both command
## profiles.
##
## The expected values come from the pinned pokecrystal and pokegold sources:
## engine/events/overworld.asm's TryRockSmashFromMenu, RockSmashScript and
## AskRockSmashScript, engine/events/treemons.asm's RockMonEncounter,
## engine/events/std_scripts.asm's SmashRockScript, and
## data/sprites/map_objects.asm's SPRITEMOVEDATA_SMASHABLE_ROCK row.
##
## The real-cartridge counterpart to the rock half of
## tests/unit/test_world_treemon.gd and
## tests/integration/test_world_field_move_screen.gd. Cianwood City is the
## acceptance case, because its six rocks are the largest population and its map
## is one of the four RockMonMaps names.
##
##   Godot --headless --path . -s res://tools/validate_rock_smash.gd

const GAME_IDS: Array[StringName] = [&"gold", &"silver", &"crystal"]

## constants/map_constants.asm. Cianwood City and Route 40 keep their numbers
## between the pins; the two dungeon maps do not, the way Ilex Forest does not.
const CIANWOOD_GROUP: int = 22
const CIANWOOD_NUMBER: int = 3
const ROUTE_40_GROUP: int = 22
const ROUTE_40_NUMBER: int = 1
const DARK_CAVE_GROUP: int = 3
const DARK_CAVE_CRYSTAL: int = 78
const DARK_CAVE_GOLD_SILVER: int = 70
const SLOWPOKE_WELL_GROUP: int = 3
const SLOWPOKE_WELL_CRYSTAL: int = 40
const SLOWPOKE_WELL_GOLD_SILVER: int = 32

## maps/CianwoodCity.asm's first rock object, identical in both pins, and the
## cell the player stands on to face it.
const CIANWOOD_ROCK_CELL := Vector2i(8, 16)
const CIANWOOD_STAND_CELL := Vector2i(8, 15)

## Census of the real caches. Crystal ships one rock fewer than Gold and Silver.
## Only 13 of them stand on a map RockMonMaps names, because Burned Tower 1F,
## Ice Path B3F and Mt. Moon Square carry rocks with no rock set: smashing those
## is the source's own guaranteed nothing.
const EXPECTED_CENSUS: Dictionary = {
	# game id: [rocks, maps, rocks on a map with a rock set]
	&"gold": [17, 6, 13],
	&"silver": [17, 6, 13],
	&"crystal": [16, 6, 13],
}

## constants/event_flags.asm's EVENT_MT_MOON_SQUARE_ROCK, the only event flag any
## rock carries. The other fifteen or sixteen are `-1`, so they come back on the
## next map load and this one does not.
const MT_MOON_SQUARE_GROUP: int = 15
const MT_MOON_SQUARE_NUMBER: int = 10
const MT_MOON_SQUARE_ROCK_FLAG: int = 1912

## data/wild/treemons.asm's TreeMonSet_Rock.
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
		_verify_rock_map_table(game_id, data, crystal)
		_census(game_id, data, crystal)
		_verify_cianwood(game_id, data, crystal)
	_finish()


## GetTreeMonSet over RockMonMaps, at all four rows. Slowpoke Well B1F is in the
## table and ships no rock at all, which is checked in _census() rather than
## here: the table naming a map is not a promise that anything smashable stands
## on it.
func _verify_rock_map_table(game_id: StringName, data: GameData, crystal: bool) -> void:
	var expected_set: int = 7 if crystal else 3
	var rows: Array = [
		Vector2i(CIANWOOD_GROUP, CIANWOOD_NUMBER),
		Vector2i(ROUTE_40_GROUP, ROUTE_40_NUMBER),
		Vector2i(DARK_CAVE_GROUP, DARK_CAVE_CRYSTAL if crystal else DARK_CAVE_GOLD_SILVER),
		Vector2i(
			SLOWPOKE_WELL_GROUP,
			SLOWPOKE_WELL_CRYSTAL if crystal else SLOWPOKE_WELL_GOLD_SILVER
		),
	]
	for pair: Vector2i in rows:
		_check(
			data.treemon_set_for_map(pair.x, pair.y, true) == expected_set,
			"%s: RockMonMaps row %s is set %d, not TREEMON_SET_ROCK %d." % [
				game_id, pair, data.treemon_set_for_map(pair.x, pair.y, true), expected_set,
			]
		)
	# TreeMonMaps must not answer for these: the two tables are separate lookups
	# and a rock reads only its own.
	_check(
		data.treemon_set_for_map(ROUTE_40_GROUP, ROUTE_40_NUMBER) == 0,
		"%s: Route 40 has a tree set, which TreeMonMaps gives TREEMON_SET_NONE." % game_id
	)
	var rock: Dictionary = data.treemon_set(expected_set)
	var common: Array = rock.get("common", [])
	_check(
		common.size() == 2 and int(common[0]["species"]) == KRABBY \
			and int(common[1]["species"]) == SHUCKLE,
		"%s: TreeMonSet_Rock is not the pinned KRABBY and SHUCKLE." % game_id
	)


## Counts the smashable rocks a real cache carries, so a cache change that drops
## one is loud. Also pins the single flagged rock and the RockMonMaps row that
## has no rock on it.
func _census(game_id: StringName, data: GameData, crystal: bool) -> void:
	var rocks: int = 0
	var with_set: int = 0
	var flagged: Array = []
	var maps: Dictionary = {}
	var slowpoke_number: int = SLOWPOKE_WELL_CRYSTAL if crystal else SLOWPOKE_WELL_GOLD_SILVER
	var slowpoke_rocks: int = 0
	for map: Gen2WorldMap in data.world_maps():
		var rows: Variant = map.events.get("objects", [])
		if not rows is Array:
			continue
		var usable: bool = Gen2WorldTreemon.set_is_usable(
			data.treemon_set_for_map(map.group, map.number, true), crystal
		)
		for row: Variant in rows as Array:
			if not row is Dictionary:
				continue
			if int((row as Dictionary).get("movement", 0)) \
				!= Gen2WorldObject.MOVEMENT_SMASHABLE_ROCK:
				continue
			rocks += 1
			maps[Vector2i(map.group, map.number)] = true
			if usable:
				with_set += 1
			if map.group == SLOWPOKE_WELL_GROUP and map.number == slowpoke_number:
				slowpoke_rocks += 1
			var flag: int = int((row as Dictionary).get("event_flag", 0))
			if flag != 0xFFFF and flag > 0:
				flagged.append([map.group, map.number, flag])
	var counts: Array = [rocks, maps.size(), with_set]
	print("%s: %d smashable rocks over %d maps, %d of them on a map RockMonMaps names." % [
		game_id, counts[0], counts[1], counts[2],
	])
	_check(
		counts == EXPECTED_CENSUS.get(game_id, []),
		"%s: census is %s, not the pinned %s." % [
			game_id, counts, EXPECTED_CENSUS.get(game_id, []),
		]
	)
	_check(
		flagged == [[MT_MOON_SQUARE_GROUP, MT_MOON_SQUARE_NUMBER, MT_MOON_SQUARE_ROCK_FLAG]],
		"%s: the flagged rocks are %s, not Mt. Moon Square's alone." % [game_id, flagged]
	)
	_check(
		slowpoke_rocks == 0,
		"%s: Slowpoke Well B1F has %d rocks; RockMonMaps names it but no rock stands there."
			% [game_id, slowpoke_rocks]
	)


## The acceptance case: a real rock, faced from a real cell, with no badge set
## anywhere, staged and then committed.
func _verify_cianwood(game_id: StringName, data: GameData, _crystal: bool) -> void:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, CIANWOOD_GROUP, CIANWOOD_NUMBER, CIANWOOD_STAND_CELL, Gen2WorldState.new()
	)
	if not _check(world != null, "%s: Cianwood City is missing." % game_id):
		return
	world.player_facing = Gen2WorldSprite.FACING_DOWN
	var rock: Gen2WorldObject = world.object_at(CIANWOOD_ROCK_CELL)
	if not _check(
		rock != null and rock.is_smashable_rock(),
		"%s: Cianwood City %s is not a smashable rock." % [game_id, CIANWOOD_ROCK_CELL]
	):
		return
	_check(
		not world.can_walk_to(CIANWOOD_ROCK_CELL),
		"%s: Cianwood City's rock does not block its cell." % game_id
	)

	# CheckPartyMove is the whole gate: no badge, no tile and no player state.
	var refused: Dictionary = world.rock_smash_request()
	_check(
		StringName(refused.get("reason", &"")) == &"move_not_known",
		"%s: a party without ROCK SMASH answered %s." % [game_id, refused]
	)
	_rock_smash_party(world)
	var request: Dictionary = world.rock_smash_request()
	if not _check(
		bool(request.get("ok", false)),
		"%s: Cianwood City rock smash refused with %s." % [game_id, request.get("reason", "")]
	):
		return

	var random := RandomNumberGenerator.new()
	random.seed = 2
	var applied: Dictionary = world.complete_rock_smash(random)
	_check(
		bool(applied.get("ok", false)),
		"%s: the commit failed with %s." % [game_id, applied.get("reason", "")]
	)
	_check(
		world.object_at(CIANWOOD_ROCK_CELL) == null,
		"%s: the rock is still there after disappear LAST_TALKED." % game_id
	)
	_check(
		world.can_walk_to(CIANWOOD_ROCK_CELL),
		"%s: the smashed rock's cell is still blocked." % game_id
	)
	# Its event flag is -1, so nothing was written and the next map load brings
	# it back, which is what the cartridge does with fifteen of the sixteen.
	world.reload_current_map()
	_check(
		world.object_at(CIANWOOD_ROCK_CELL) != null,
		"%s: an unflagged rock did not come back on a map reload." % game_id
	)

	var encounter: Dictionary = applied.get("encounter", {})
	if _check(
		not encounter.is_empty(),
		"%s: seed 2's roll of 0 is under RockMonEncounter's 4 and must resolve." % game_id
	):
		_check(
			int(encounter["pokemon"]) in [KRABBY, SHUCKLE],
			"%s: a Cianwood rock produced species %d, not one of the ROCK set's two."
				% [game_id, int(encounter["pokemon"])]
		)
		_check(
			not encounter["values"].has("battle_type"),
			"%s: RockMonEncounter writes no wBattleType, unlike TreeMonEncounter." % game_id
		)
		print("%s: Cianwood City %s smashed to species %d at level %d." % [
			game_id, CIANWOOD_ROCK_CELL, int(encounter["pokemon"]), int(encounter["level"]),
		])


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS rock smash: the rock table, the census and Cianwood City verified.")
		quit(0)
		return
	for message: String in _failures:
		print("FAIL %s" % message)
	quit(1)


## CheckPartyMove gates Rock Smash and nothing else does.
func _rock_smash_party(world: Gen2WorldAPI) -> void:
	world.set_party_summary(
		1, false, [1] as Array[int], [[Gen2WorldFieldMove.MOVE_ROCK_SMASH]],
		["MON"], [false]
	)
