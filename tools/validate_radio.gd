extends SceneTree

## Verifies the Pokegear radio card and the one thing in the overworld that
## reads what it leaves behind: Vermilion City's Snorlax.
##
## Expected values come from the pinned pokecrystal and pokegold sources:
## engine/pokegear/pokegear.asm (RadioChannels, LoadStation_*,
## ExitPokegearRadio_HandleMusic), engine/pokegear/radio.asm
## (StartRadioStation), data/radio/channel_music.asm,
## engine/events/specials.asm (SnorlaxAwake), data/sprites/map_objects.asm
## (BIG_OBJECT) and maps/VermilionCity.asm.
##
## Two findings carry it. The Poke Flute channel is the only way a track other
## than the map's own reaches `wMapMusic`, because a station's music id is
## neither of the two sentinels ExitPokegearRadio_HandleMusic restores on; and
## the Snorlax is a BIG_OBJECT, so it fills four cells rather than one, which is
## exactly why SnorlaxAwake's five proximity coordinates are the cells they are
## and why the Diglett's Cave mouth above it has no approach while it stands.
##
##   Godot --headless --path . -s res://tools/validate_radio.gd

const GAME_IDS: Array[StringName] = [&"gold", &"silver", &"crystal"]

## constants/map_constants.asm.
const VERMILION_GROUP: int = 12
const VERMILION_CITY: int = 3
const DIGLETTS_CAVE_GROUP: int = 3
const DIGLETTS_CAVE: int = 84
const DIGLETTS_CAVE_GOLD_SILVER: int = 75

## maps/VermilionCity.asm: the port passage the walked route lands on, the cave
## mouth, the Snorlax's own cell and the cell it is talked to from.
const PORT_LANDING: Vector2i = Vector2i(20, 31)
const CAVE_MOUTH: Vector2i = Vector2i(34, 7)
const SNORLAX_CELL: Vector2i = Vector2i(34, 8)
const SNORLAX_OBJECT: int = 4
const TALK_FROM: Vector2i = Vector2i(34, 10)
const CITY_CELLS: int = 319

## engine/events/specials.asm's SnorlaxAwake.ProximityCoords, in source order:
## every walkable cell adjacent to the two-by-two body, which its own comments
## call left, below, below, right and right.
const PROXIMITY_CELLS: Array[Vector2i] = [
	Vector2i(33, 8), Vector2i(34, 10), Vector2i(35, 10), Vector2i(36, 8), Vector2i(36, 9),
]
## Three of the five sit behind the Snorlax, in pockets its own body seals, so a
## player can only ever use the two below it. The list is the source's, not a
## reachable set, and it becomes reachable the moment the Snorlax is gone.
const PROXIMITY_REACHABLE: Array[Vector2i] = [Vector2i(34, 10), Vector2i(35, 10)]

## constants/event_flags.asm, the same numbers in both pins.
const EVENT_FOUGHT_SNORLAX: int = 1872
const EVENT_VERMILION_CITY_SNORLAX: int = 1904

## constants/landmark_constants.asm, Crystal side; Gold and Silver sit one lower
## from LANDMARK_BATTLE_TOWER on.
const LANDMARK_VERMILION_CITY: int = 61
const LANDMARK_NEW_BARK_TOWN: int = 1

const KNOB_POKE_FLUTE: int = 78

## What the Snorlax opens. maps/Route2.asm warp 5 is the cave's own mouth, and
## the pocket it lands in is closed by two cut trees; only the northern one
## reaches the rest of the route.
const ROUTE_2_GROUP: int = 23
const ROUTE_2: int = 1
const CAVE_LANDING: Vector2i = Vector2i(12, 7)
const ROUTE_2_POCKET_CELLS: int = 125
const ROUTE_2_POCKET_TREES: Array[Vector2i] = [Vector2i(5, 8), Vector2i(15, 18)]
const ROUTE_2_OPENING_TREE: Vector2i = Vector2i(5, 8)
const ROUTE_2_OPENING_APPROACH: Vector2i = Vector2i(5, 9)
const ROUTE_2_OPEN_CELLS: int = 469

## `loadwildmon SNORLAX, 50` and `loadvar VAR_BATTLETYPE, BATTLETYPE_FORCEITEM`.
const SPECIES_SNORLAX: int = 143
const SNORLAX_LEVEL: int = 50
const BATTLETYPE_FORCEITEM: int = 10

var _failures: PackedStringArray = []


func _initialize() -> void:
	for game_id: StringName in GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		var crystal: bool = Gen2WorldState.is_crystal_profile(data)
		_verify_stations(data, game_id, crystal)
		_verify_music_records(data, game_id, crystal)
		_verify_big_object_census(data, game_id)
		_verify_snorlax(data, game_id, crystal)
		_verify_route_2(data, game_id, crystal)
	_finish()


## RadioChannels, its three profile splits and the music each station commits.
func _verify_stations(data: GameData, game_id: StringName, crystal: bool) -> void:
	var vermilion: int = LANDMARK_VERMILION_CITY if crystal else LANDMARK_VERMILION_CITY - 1
	var new_bark: int = LANDMARK_NEW_BARK_TOWN
	var kanto: Dictionary = {"landmark": vermilion, "crystal": crystal, "expn_card": true}
	var johto: Dictionary = {"landmark": new_bark, "crystal": crystal, "expn_card": true}

	var flute: Dictionary = Gen2WorldRadio.station_for(KNOB_POKE_FLUTE, kanto)
	_check(
		bool(flute.get("ok", false))
			and int(flute.get("channel", -1)) == Gen2WorldRadio.POKE_FLUTE_RADIO
			and int(flute.get("music", -1)) == Gen2WorldRadio.MUSIC_POKE_FLUTE_CHANNEL,
		"%s: 20.0 in Kanto with the EXPN card is not the Poke Flute channel." % game_id
	)
	_check(
		not bool(Gen2WorldRadio.station_for(KNOB_POKE_FLUTE, johto).get("ok", false)),
		"%s: the Poke Flute channel answers in Johto." % game_id
	)
	var no_card: Dictionary = kanto.duplicate()
	no_card["expn_card"] = false
	_check(
		not bool(Gen2WorldRadio.station_for(KNOB_POKE_FLUTE, no_card).get("ok", false)),
		"%s: the Poke Flute channel answers without the EXPN card." % game_id
	)
	# Gold and Silver ship no Buena's row, and check the region but not the card
	# on the other two Kanto stations.
	_check(
		bool(Gen2WorldRadio.station_for(40, johto).get("ok", false)) == crystal,
		"%s: 10.5 does not match this profile's Buena's Password row." % game_id
	)
	for knob: int in [64, 72]:
		_check(
			bool(Gen2WorldRadio.station_for(knob, no_card).get("ok", false)) != crystal,
			"%s: %.1f does not match this profile's EXPN check." % [
				game_id, Gen2WorldRadio.frequency_for(knob),
			]
		)
	_check(
		Gen2WorldRadio.channel_count(crystal) == (11 if crystal else 10),
		"%s: the channel count is not this profile's." % game_id
	)
	print("%s radio: %d channels, the Poke Flute channel on %.1f, music %d." % [
		game_id, Gen2WorldRadio.channel_count(crystal),
		Gen2WorldRadio.frequency_for(KNOB_POKE_FLUTE), Gen2WorldRadio.MUSIC_POKE_FLUTE_CHANNEL,
	])


## Every station's track has to be a real imported music record, or tuning to it
## would leave the overworld silent.
func _verify_music_records(data: GameData, game_id: StringName, crystal: bool) -> void:
	for channel: int in Gen2WorldRadio.CHANNEL_SONGS.size():
		if channel == Gen2WorldRadio.BUENAS_PASSWORD and not crystal:
			continue
		var song: int = Gen2WorldRadio.CHANNEL_SONGS[channel]
		_check(
			not data.world_audio(&"music", song).is_empty(),
			"%s: channel %d wants music record %d, which this cache lacks." % [
				game_id, channel, song,
			]
		)


## data/sprites/map_objects.asm gives BIG_OBJECT to three SpriteMovementData
## rows, and exactly two objects in either game use one.
func _verify_big_object_census(data: GameData, game_id: StringName) -> void:
	var found: Array = []
	for map: Gen2WorldMap in data.world_maps():
		for row: Variant in map.events.get("objects", []):
			if not row is Dictionary:
				continue
			var movement: int = int((row as Dictionary).get("movement", -1))
			if movement in [
				Gen2WorldObject.MOVEMENT_BIGDOLLSYM,
				Gen2WorldObject.MOVEMENT_BIGDOLLASYM,
				Gen2WorldObject.MOVEMENT_BIGDOLL,
			]:
				found.append("%d/%d %s" % [
					map.group, map.number,
					Vector2i(int(row["x"]), int(row["y"])),
				])
	found.sort()
	_check(
		found.size() == 2,
		"%s: %d big objects, not the pinned two: %s" % [game_id, found.size(), found]
	)
	print("%s big objects: %s." % [game_id, ", ".join(found)])


## The Snorlax itself: what it fills, what it seals, and the whole radio chain
## driven against the real cache.
func _verify_snorlax(data: GameData, game_id: StringName, crystal: bool) -> void:
	var sealed: Gen2WorldAPI = _open(data, VERMILION_GROUP, VERMILION_CITY, PORT_LANDING)
	if sealed == null:
		return
	_check(
		sealed.landmark() == (LANDMARK_VERMILION_CITY if crystal else LANDMARK_VERMILION_CITY - 1),
		"%s: Vermilion's landmark is %d." % [game_id, sealed.landmark()]
	)
	var snorlax: Gen2WorldObject = sealed.object_at(SNORLAX_CELL)
	if not _check(
		snorlax != null and snorlax.index == SNORLAX_OBJECT and snorlax.is_big_object(),
		"%s: %s is not the big Snorlax object." % [game_id, SNORLAX_CELL]
	):
		return
	# WillObjectIntersectBigObject: two by two anchored on its own cell.
	for offset: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		_check(
			sealed.object_at(SNORLAX_CELL + offset) == snorlax,
			"%s: the Snorlax does not fill %s." % [game_id, SNORLAX_CELL + offset]
		)
	_check(
		sealed.object_at(SNORLAX_CELL + Vector2i(2, 0)) != snorlax
			and sealed.object_at(SNORLAX_CELL + Vector2i(0, 2)) != snorlax,
		"%s: the Snorlax fills more than its two by two." % game_id
	)

	var before: Dictionary = _region(sealed, PORT_LANDING)
	_check(
		before.size() == CITY_CELLS,
		"%s: Vermilion is %d cells from the port, not the pinned %d." % [
			game_id, before.size(), CITY_CELLS,
		]
	)
	_check(
		not before.has(CAVE_MOUTH),
		"%s: the Diglett's Cave mouth is reachable while the Snorlax stands." % game_id
	)
	# Every proximity coordinate faces the two-by-two body, which is what makes
	# the list the list; only the two below it can be stood on until it is gone.
	for cell: Vector2i in PROXIMITY_CELLS:
		var faced: bool = false
		for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if sealed.object_at(cell + direction) == snorlax:
				faced = true
		_check(faced, "%s: %s does not face the Snorlax." % [game_id, cell])
		_check(
			before.has(cell) == (cell in PROXIMITY_REACHABLE),
			"%s: %s does not match the pinned reachable set while the Snorlax stands." % [
				game_id, cell,
			]
		)

	_verify_wake(data, game_id, crystal)


## The chain end to end: tune 20.0 next to it, talk to it, win, and watch the
## cave mouth open.
func _verify_wake(data: GameData, game_id: StringName, crystal: bool) -> void:
	var state := Gen2WorldState.new()
	state.set_engine_flag(Gen2WorldState.ENGINE_RADIO_CARD, true)
	state.set_engine_flag(Gen2WorldState.ENGINE_EXPN_CARD, true)
	var world: Gen2WorldAPI = _open(data, VERMILION_GROUP, VERMILION_CITY, TALK_FROM, state)
	if world == null:
		return
	_check(
		state.map_music() == world.current_map.music,
		"%s: map entry did not put the map's own track in wMapMusic." % game_id
	)

	# Talking to it before the radio is tuned takes SnorlaxAwake's false branch.
	world.player_facing = Gen2WorldSprite.FACING_UP
	var asleep: Dictionary = _drain(world, world.interact(), data)
	_check(
		not world.event_flag_active(EVENT_FOUGHT_SNORLAX)
			and int(asleep.get("battles", 0)) == 0,
		"%s: the sleeping Snorlax started a battle without the radio." % game_id
	)

	var tuned: Dictionary = world.tune_radio(KNOB_POKE_FLUTE)
	_check(
		bool(tuned.get("ok", false))
			and state.map_music() == Gen2WorldRadio.MUSIC_POKE_FLUTE_CHANNEL,
		"%s: tuning 20.0 did not put the Poke Flute channel in wMapMusic." % game_id
	)
	world.close_radio()
	_check(
		state.map_music() == Gen2WorldRadio.MUSIC_POKE_FLUTE_CHANNEL,
		"%s: closing the Pokegear cleared a tuned station." % game_id
	)

	world.player_facing = Gen2WorldSprite.FACING_UP
	var awake: Dictionary = _drain(world, world.interact(), data)
	_check(
		int(awake.get("battles", 0)) == 1
			and int(awake.get("species", 0)) == SPECIES_SNORLAX
			and int(awake.get("level", 0)) == SNORLAX_LEVEL
			and int(awake.get("battle_type", -1)) == BATTLETYPE_FORCEITEM,
		"%s: the awake branch did not run its forced-item battle: %s" % [game_id, awake]
	)
	_check(
		world.event_flag_active(EVENT_FOUGHT_SNORLAX)
			and world.event_flag_active(EVENT_VERMILION_CITY_SNORLAX),
		"%s: the Snorlax script did not commit its two flags." % game_id
	)

	# reloadmapafterbattle rebuilds the objects, and the disappeared Snorlax
	# stops filling its four cells.
	var after: Dictionary = _region(world, TALK_FROM)
	_check(
		after.has(CAVE_MOUTH),
		"%s: the Diglett's Cave mouth is still sealed after the Snorlax." % game_id
	)
	# The three pockets its body sealed open with it, which is the clearest
	# proof that the two-by-two occupancy was what closed them.
	for cell: Vector2i in PROXIMITY_CELLS:
		_check(
			after.has(cell),
			"%s: %s is still unreachable once the Snorlax is gone." % [game_id, cell]
		)
	var cave: int = DIGLETTS_CAVE if crystal else DIGLETTS_CAVE_GOLD_SILVER
	var warp: Dictionary = world.warp_at(CAVE_MOUTH)
	_check(
		int(warp.get("map_group", -1)) == DIGLETTS_CAVE_GROUP
			and int(warp.get("map_number", -1)) == cave,
		"%s: %s is not the Diglett's Cave warp." % [game_id, CAVE_MOUTH]
	)
	print("%s snorlax: %d cells sealed, woken on 20.0, %d open, and %s reaches %d/%d." % [
		game_id, CITY_CELLS, after.size(), CAVE_MOUTH, DIGLETTS_CAVE_GROUP, cave,
	])


## What the woken Snorlax is worth: the far side of Diglett's Cave is a pocket
## of Route 2 closed by two cut trees, and cutting the northern one reaches both
## the Pewter and the Viridian crossing. Everything west of Kanto hangs off this,
## so it is checked here rather than left as an assertion in prose.
func _verify_route_2(data: GameData, game_id: StringName, crystal: bool) -> void:
	var world: Gen2WorldAPI = _open(data, ROUTE_2_GROUP, ROUTE_2, CAVE_LANDING)
	if world == null:
		return
	var cave: int = DIGLETTS_CAVE if crystal else DIGLETTS_CAVE_GOLD_SILVER
	var mouth: Dictionary = world.warp_at(CAVE_LANDING)
	_check(
		int(mouth.get("map_group", -1)) == DIGLETTS_CAVE_GROUP
			and int(mouth.get("map_number", -1)) == cave,
		"%s: Route 2's %s is not the Diglett's Cave mouth." % [game_id, CAVE_LANDING]
	)
	var pocket: Dictionary = _region(world, CAVE_LANDING)
	_check(
		pocket.size() == ROUTE_2_POCKET_CELLS,
		"%s: the cave pocket is %d cells, not the pinned %d." % [
			game_id, pocket.size(), ROUTE_2_POCKET_CELLS,
		]
	)
	_check(
		not _reaches_edge(world, pocket, Vector2i.UP)
			and not _reaches_edge(world, pocket, Vector2i.DOWN),
		"%s: the cave pocket already reaches Pewter or Viridian." % game_id
	)
	var trees: Array = []
	for cell: Vector2i in pocket:
		for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = cell + direction
			if pocket.has(next):
				continue
			if world.collision_code_at(next) in Gen2WorldFieldMove.CUTTABLE_COLLISIONS:
				trees.append(next)
	trees.sort()
	_check(
		trees == ROUTE_2_POCKET_TREES,
		"%s: the pocket's cut trees are %s, not the pinned %s." % [
			game_id, trees, ROUTE_2_POCKET_TREES,
		]
	)

	# Now cut the one that opens it, exactly as a player would.
	var cutter: Gen2WorldState = Gen2WorldState.new()
	cutter.set_engine_flag(
		Gen2WorldState.badge_flag(Gen2WorldFieldMove.BADGE_HIVE, crystal), true
	)
	var opened: Gen2WorldAPI = _open(data, ROUTE_2_GROUP, ROUTE_2, CAVE_LANDING, cutter)
	if opened == null:
		return
	opened.player_cell = ROUTE_2_OPENING_APPROACH
	opened.player_facing = Gen2WorldSprite.FACING_UP
	if not _check(
		bool(opened.cut_request().get("ok", false))
			and bool(opened.complete_cut().get("ok", false)),
		"%s: Route 2's %s did not cut." % [game_id, ROUTE_2_OPENING_TREE]
	):
		return
	var open_region: Dictionary = _region(opened, ROUTE_2_OPENING_APPROACH)
	_check(
		open_region.size() == ROUTE_2_OPEN_CELLS,
		"%s: the cut route is %d cells, not the pinned %d." % [
			game_id, open_region.size(), ROUTE_2_OPEN_CELLS,
		]
	)
	_check(
		_reaches_edge(opened, open_region, Vector2i.UP),
		"%s: the cut route does not reach Pewter." % game_id
	)
	_check(
		_reaches_edge(opened, open_region, Vector2i.DOWN),
		"%s: the cut route does not reach Viridian." % game_id
	)
	print("%s route 2: a %d-cell pocket behind the cave, two trees, %d cells and both crossings once %s is cut." % [
		game_id, ROUTE_2_POCKET_CELLS, open_region.size(), ROUTE_2_OPENING_TREE,
	])


## Whether [param region] holds an edge cell that really crosses [param axis].
func _reaches_edge(world: Gen2WorldAPI, region: Dictionary, axis: Vector2i) -> bool:
	var size: Vector2i = world.map_size_cells()
	for index: int in (size.y if absi(axis.x) == 1 else size.x):
		var cell: Vector2i = Vector2i(0, index) if axis == Vector2i.LEFT \
			else Vector2i(size.x - 1, index) if axis == Vector2i.RIGHT \
			else Vector2i(index, 0) if axis == Vector2i.UP \
			else Vector2i(index, size.y - 1)
		if region.has(cell) and bool(world.connection_target(cell, axis).get("ok", false)):
			return true
	return false


## Runs a script to its end, answering the one battle it can reach with a win.
func _drain(world: Gen2WorldAPI, results: Array, data: GameData) -> Dictionary:
	var out: Dictionary = {"battles": 0, "species": 0, "level": 0, "battle_type": -1}
	var guard: int = 0
	while guard < 64:
		guard += 1
		var waiting: bool = false
		for result: Dictionary in results:
			if StringName(result.get("status", &"")) == &"waiting":
				waiting = true
		if not waiting:
			return out
		var request: Dictionary = world.pending_runtime_request()
		if StringName(request.get("kind", &"")) == &"battle_requested":
			var values: Dictionary = request.get("values", {})
			out["battles"] = int(out["battles"]) + 1
			out["species"] = int(values.get("pokemon", 0))
			out["level"] = int(values.get("level", 0))
			out["battle_type"] = int(values.get("battle_type", -1))
			results = world.complete_runtime_request({
				"ok": true, "outcome": Gen2WorldBattleAdapter.OUTCOME_WON,
			})
			continue
		results = world.run_event_queue(true)
	_fail("a script did not finish inside its command budget")
	return out


func _open(
	data: GameData, group: int, number: int, cell: Vector2i, state: Gen2WorldState = null
) -> Gen2WorldAPI:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, group, number, cell, state if state != null else Gen2WorldState.new()
	)
	if world == null:
		_fail("map %d/%d is missing." % [group, number])
		return null
	_field_move_party(world)
	var _entry: Array = world.dispatch_map_entry()
	return world


## Ledge hops included, the way tools/validate_fuchsia.gd walks.
func _region(world: Gen2WorldAPI, start: Vector2i) -> Dictionary:
	var seen: Dictionary = {start: true}
	var frontier: Array[Vector2i] = [start]
	var size: Vector2i = world.map_size_cells()
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = cell + direction
			var face: int = Gen2WorldCollision.face_mask_for_direction(direction)
			var walled: bool = face != 0 and (world.tile_permissions_at(cell) & face) != 0
			if walled or not world.can_walk_to(next):
				if not Gen2WorldCollision.allows_hop(world.collision_code_at(cell), direction):
					continue
				next = cell + direction * 2
				if next.x < 0 or next.y < 0 or next.x >= size.x or next.y >= size.y:
					continue
			if seen.has(next):
				continue
			seen[next] = true
			frontier.append(next)
	return seen


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS radio: the station table, its profile splits, the big-object census and the Snorlax chain verified.")
		quit(0)
		return
	for failure: String in _failures:
		printerr(failure)
	printerr("FAIL radio: %d problems." % _failures.size())
	quit(1)


## CheckPartyMove gates every field move, and this file is about the map rather
## than the party, so every world it opens carries one member that knows all
## five. The route preview is where a real party earning them is proved.
func _field_move_party(world: Gen2WorldAPI) -> void:
	world.set_party_summary(
		1, false, [1] as Array[int], [Gen2WorldFieldMove.FIELD_MOVES.duplicate()],
		["MON"], [false]
	)
