extends RefCounted

var _r: RefCounted = null

## Verifies the lost-doll errand between Saffron and Vermilion and the Magnet
## Train ride it pays for, against freshly imported real caches for both command
## profiles.
##
## Expected values come from the pinned pokecrystal and pokegold sources:
## constants/map_constants.asm, maps/SaffronCity.asm, maps/CopycatsHouse1F.asm,
## maps/CopycatsHouse2F.asm, maps/VermilionCity.asm, maps/PokemonFanClub.asm,
## maps/SaffronMagnetTrainStation.asm and
## maps/GoldenrodMagnetTrainStation.asm.
##
## Three findings carry the leg. The Copycat is a variable sprite, SPRITE_COPYCAT
## ($fb), that only her own script ever assigns, so she is on the map before
## anything has given her a sprite; GetMonSprite answers SPRITE_CHRIS for an
## unassigned variable sprite, which is what puts her in her cell at all. Each
## station is two regions with no walkable seam: row 9 is solid, so the lobby
## never reaches the platform and the only way onto a train is the officer's own
## `applymovement`, which is a forced step. And the errand is a three-legged
## loop with an order the cartridge enforces, since the Fan Club's Clefairy guy
## reads EVENT_MET_COPYCAT_FOUND_OUT_ABOUT_LOST_ITEM before he parts with the
## doll.
##
##   Godot --headless --path . -s res://tools/validate.gd -- magnet_train


## constants/map_constants.asm. Nothing on this leg splits between the profiles.
const VERMILION_GROUP: int = 12
const ROUTE_6: int = 1
const VERMILION_CITY: int = 3
const POKEMON_FAN_CLUB: int = 7
const ROUTE_6_SAFFRON_GATE: int = 12
const GOLDENROD_GROUP: int = 11
const GOLDENROD_MAGNET_TRAIN_STATION: int = 7
const SAFFRON_GROUP: int = 25
const SAFFRON_CITY: int = 2
const SAFFRON_MAGNET_TRAIN_STATION: int = 9
const COPYCATS_HOUSE_1F: int = 11
const COPYCATS_HOUSE_2F: int = 12


## The errand's doors, as [label, group, number, the cell the warp stands on,
## the target group and number, and the one-based destination warp index].
const WARP_CHAIN: Array = [
	["Saffron's Copycat house door", SAFFRON_GROUP, SAFFRON_CITY, Vector2i(9, 11),
		SAFFRON_GROUP, COPYCATS_HOUSE_1F, 1],
	["the Copycat house stairs", SAFFRON_GROUP, COPYCATS_HOUSE_1F, Vector2i(2, 0),
		SAFFRON_GROUP, COPYCATS_HOUSE_2F, 1],
	["the Copycat house stairs down", SAFFRON_GROUP, COPYCATS_HOUSE_2F, Vector2i(3, 0),
		SAFFRON_GROUP, COPYCATS_HOUSE_1F, 3],
	["the Copycat house exit", SAFFRON_GROUP, COPYCATS_HOUSE_1F, Vector2i(2, 7),
		SAFFRON_GROUP, SAFFRON_CITY, 8],
	["Saffron's Route 6 gate door", SAFFRON_GROUP, SAFFRON_CITY, Vector2i(16, 33),
		VERMILION_GROUP, ROUTE_6_SAFFRON_GATE, 1],
	["the Route 6 gate's south door", VERMILION_GROUP, ROUTE_6_SAFFRON_GATE, Vector2i(4, 7),
		VERMILION_GROUP, ROUTE_6, 2],
	["Vermilion's Fan Club door", VERMILION_GROUP, VERMILION_CITY, Vector2i(7, 13),
		VERMILION_GROUP, POKEMON_FAN_CLUB, 1],
	["the Fan Club exit", VERMILION_GROUP, POKEMON_FAN_CLUB, Vector2i(2, 7),
		VERMILION_GROUP, VERMILION_CITY, 3],
	["Saffron's train station door", SAFFRON_GROUP, SAFFRON_CITY, Vector2i(8, 3),
		SAFFRON_GROUP, SAFFRON_MAGNET_TRAIN_STATION, 2],
	["the Saffron train door", SAFFRON_GROUP, SAFFRON_MAGNET_TRAIN_STATION, Vector2i(6, 5),
		GOLDENROD_GROUP, GOLDENROD_MAGNET_TRAIN_STATION, 4],
	["the Goldenrod train door", GOLDENROD_GROUP, GOLDENROD_MAGNET_TRAIN_STATION, Vector2i(6, 5),
		SAFFRON_GROUP, SAFFRON_MAGNET_TRAIN_STATION, 4],
	["the Saffron station exit", SAFFRON_GROUP, SAFFRON_MAGNET_TRAIN_STATION, Vector2i(8, 17),
		SAFFRON_GROUP, SAFFRON_CITY, 6],
]

## Copycat's House 2F. She stands on (4,3) facing left and is faced from (5,3).
const COPYCAT_HOUSE_2F_LANDING: Vector2i = Vector2i(3, 0)
const COPYCAT_CELL: Vector2i = Vector2i(4, 3)
const COPYCAT_FACE: Vector2i = Vector2i(5, 3)
const SPRITE_COPYCAT: int = 0xFB
const EVENT_COPYCATS_HOUSE_2F_DOLL: int = 1907

## The Pokemon Fan Club. The Clefairy guy stands on (2,3) facing right.
const FAN_CLUB_LANDING: Vector2i = Vector2i(2, 7)
const CLEFAIRY_GUY_CELL: Vector2i = Vector2i(2, 3)
const CLEFAIRY_GUY_FACE: Vector2i = Vector2i(1, 3)
const FAN_CLUB_DOLL_CELL: Vector2i = Vector2i(2, 4)
const EVENT_VERMILION_FAN_CLUB_DOLL: int = 1908

## Both stations share a layout: the lobby is rows 10 to 17, the platform rows 2
## to 8, and row 9 is solid between them. The officer stands on (9,9) inside that
## solid row, which is why he is talked to across it.
const STATION_LOBBY_LANDING: Vector2i = Vector2i(9, 16)
const STATION_OFFICER_CELL: Vector2i = Vector2i(9, 9)
const STATION_OFFICER_FACE: Vector2i = Vector2i(9, 10)
const STATION_PLATFORM_CELL: Vector2i = Vector2i(6, 6)
const STATION_WEST_TRAIN_DOOR: Vector2i = Vector2i(6, 5)
const STATION_EAST_TRAIN_DOOR: Vector2i = Vector2i(11, 5)
const STATION_ARRIVAL_COORD: Vector2i = Vector2i(11, 6)

## The errand's own flags, from constants/event_flags.asm.
const EVENT_RETURNED_MACHINE_PART: int = 201
const EVENT_MET_COPYCAT_FOUND_OUT_ABOUT_LOST_ITEM: int = 207
const EVENT_GOT_LOST_ITEM_FROM_FAN_CLUB: int = 210


func run(r: RefCounted) -> void:
	_r = r
	for game_id: StringName in _r.GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_verify_warp_chain(data, game_id)
		_verify_copycat(data, game_id)
		_verify_fan_club(data, game_id)
		_verify_stations(data, game_id)


## Every door on the errand and the ride, by the warp it stands on and the
## destination index that decides where it lands.
func _verify_warp_chain(data: GameData, game_id: StringName) -> void:
	for leg: Array in WARP_CHAIN:
		var label: String = leg[0]
		var world: Gen2WorldAPI = _open(data, int(leg[1]), int(leg[2]), leg[3])
		if world == null:
			continue
		var warp: Dictionary = world.warp_at(leg[3])
		if not _r.check(
			int(warp.get("map_group", -1)) == int(leg[4])
				and int(warp.get("map_number", -1)) == int(leg[5]),
			"%s: %s reaches %d/%d, not the pinned %d/%d." % [
				game_id, label,
				int(warp.get("map_group", -1)), int(warp.get("map_number", -1)),
				int(leg[4]), int(leg[5]),
			]
		):
			continue
		_r.check(
			int(warp.get("destination", -1)) == int(leg[6]),
			"%s: %s targets warp %d, not the pinned %d." % [
				game_id, label, int(warp.get("destination", -1)), int(leg[6]),
			]
		)
	print("%s warps: %d doors over the errand and both rides." % [game_id, WARP_CHAIN.size()])


## The Copycat, who is on the map before anything has given her a sprite.
func _verify_copycat(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(
		data, SAFFRON_GROUP, COPYCATS_HOUSE_2F, COPYCAT_HOUSE_2F_LANDING
	)
	if world == null:
		return
	var authored: int = 0
	for row: Variant in world.current_map.events.get("objects", []):
		if row is Dictionary and int((row as Dictionary).get("sprite", 0)) == SPRITE_COPYCAT:
			authored += 1
	# Crystal authors the pair CopycatsHouse2FWhichGenderCallback picks between;
	# Gold and Silver have one player character and so one Copycat, with no
	# callback and no hide flag.
	var expected: int = 2 if Gen2WorldState.is_crystal_profile(data) else 1
	_r.check(
		authored == expected,
		"%s: Copycat's House 2F authors %d SPRITE_COPYCAT objects, not the pinned %d." % [
			game_id, authored, expected,
		]
	)
	var standing: int = 0
	for object: Gen2WorldObject in world.visible_objects():
		if object.cell == COPYCAT_CELL:
			standing += 1
	_r.check(
		standing == 1,
		"%s: %d Copycats stand on %s, not one." % [game_id, standing, COPYCAT_CELL]
	)
	# She is there with no variablesprite having run yet, which is the whole
	# reason an unassigned variable sprite has to resolve to something.
	_r.check(
		world.object_at(COPYCAT_CELL) != null,
		"%s: nothing occupies the Copycat's cell %s before her script assigns her sprite." % [
			game_id, COPYCAT_CELL,
		]
	)
	var region: Dictionary = _region(world, COPYCAT_HOUSE_2F_LANDING)
	_r.check(
		region.has(COPYCAT_FACE),
		"%s: the Copycat is not faced from %s." % [game_id, COPYCAT_FACE]
	)
	# Her doll is what .ReturnLostItem clears, so it is hidden while the flag is
	# set and its cell is free again once it is not.
	var carrying := Gen2WorldState.new()
	carrying.set_event_flag(EVENT_COPYCATS_HOUSE_2F_DOLL)
	var hidden: Gen2WorldAPI = _open(
		data, SAFFRON_GROUP, COPYCATS_HOUSE_2F, COPYCAT_HOUSE_2F_LANDING, carrying
	)
	if hidden != null:
		_r.check(
			hidden.visible_objects().size() == world.visible_objects().size() - 1,
			"%s: EVENT_COPYCATS_HOUSE_2F_DOLL hides no object on 2F." % game_id
		)
	print("%s copycat: a %d-cell room, %d authored SPRITE_COPYCAT rows and one of them standing." % [
		game_id, region.size(), authored,
	])


## The Fan Club, whose Clefairy guy will not part with the doll until the
## Copycat has been met.
func _verify_fan_club(data: GameData, game_id: StringName) -> void:
	var world: Gen2WorldAPI = _open(
		data, VERMILION_GROUP, POKEMON_FAN_CLUB, FAN_CLUB_LANDING
	)
	if world == null:
		return
	var region: Dictionary = _region(world, FAN_CLUB_LANDING)
	_r.check(
		region.has(CLEFAIRY_GUY_FACE) and world.object_at(CLEFAIRY_GUY_CELL) != null,
		"%s: the Clefairy guy on %s is not faced from %s." % [
			game_id, CLEFAIRY_GUY_CELL, CLEFAIRY_GUY_FACE,
		]
	)
	_r.check(
		world.object_at(FAN_CLUB_DOLL_CELL) != null,
		"%s: %s is not the Fan Club doll's cell." % [game_id, FAN_CLUB_DOLL_CELL]
	)
	# The doll his script `disappear`s is the one behind this flag.
	var taken := Gen2WorldState.new()
	taken.set_event_flag(EVENT_VERMILION_FAN_CLUB_DOLL)
	var without: Gen2WorldAPI = _open(
		data, VERMILION_GROUP, POKEMON_FAN_CLUB, FAN_CLUB_LANDING, taken
	)
	if without != null:
		_r.check(
			without.object_at(FAN_CLUB_DOLL_CELL) == null,
			"%s: the Fan Club doll survives EVENT_VERMILION_FAN_CLUB_DOLL." % game_id
		)
	print("%s fan club: a %d-cell room, the Clefairy guy faced from the west and his doll below him." % [
		game_id, region.size(),
	])


## Both stations, which are the same two-region shape.
func _verify_stations(data: GameData, game_id: StringName) -> void:
	for station: Array in [
		["Saffron", SAFFRON_GROUP, SAFFRON_MAGNET_TRAIN_STATION],
		["Goldenrod", GOLDENROD_GROUP, GOLDENROD_MAGNET_TRAIN_STATION],
	]:
		var label: String = station[0]
		var world: Gen2WorldAPI = _open(
			data, int(station[1]), int(station[2]), STATION_LOBBY_LANDING
		)
		if world == null:
			continue
		var lobby: Dictionary = _region(world, STATION_LOBBY_LANDING)
		_r.check(
			lobby.has(STATION_OFFICER_FACE),
			"%s: %s's lobby does not reach the officer's cell %s." % [
				game_id, label, STATION_OFFICER_FACE,
			]
		)
		_r.check(
			world.object_at(STATION_OFFICER_CELL) != null,
			"%s: %s has no officer on %s." % [game_id, label, STATION_OFFICER_CELL]
		)
		# The whole point of the officer's applymovement: no walk joins the two.
		for cell: Vector2i in [
			STATION_PLATFORM_CELL, STATION_WEST_TRAIN_DOOR,
			STATION_EAST_TRAIN_DOOR, STATION_ARRIVAL_COORD,
		]:
			_r.check(
				not lobby.has(cell),
				"%s: %s's lobby already walks to %s, so the platform is not sealed." % [
					game_id, label, cell,
				]
			)
		var platform: Dictionary = _region(world, STATION_PLATFORM_CELL)
		for cell: Vector2i in [
			STATION_WEST_TRAIN_DOOR, STATION_EAST_TRAIN_DOOR, STATION_ARRIVAL_COORD,
		]:
			_r.check(
				platform.has(cell),
				"%s: %s's platform does not reach %s." % [game_id, label, cell]
			)
		# The arrival script hangs off a coord event on the landing side.
		var arrival: Dictionary = {}
		for row: Variant in world.current_map.events.get("coord_events", []):
			if row is Dictionary \
				and Vector2i(int((row as Dictionary).get("x", -1)),
					int((row as Dictionary).get("y", -1))) == STATION_ARRIVAL_COORD:
				arrival = row as Dictionary
		_r.check(
			not arrival.is_empty(),
			"%s: %s has no arrival coord event on %s." % [
				game_id, label, STATION_ARRIVAL_COORD,
			]
		)
		print("%s %s station: a %d-cell lobby and a %d-cell platform with no seam." % [
			game_id, label, lobby.size(), platform.size(),
		])


func _open(
	data: GameData, group: int, number: int, cell: Vector2i, state: Gen2WorldState = null
) -> Gen2WorldAPI:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, group, number, cell, state if state != null else Gen2WorldState.new()
	)
	if world == null:
		_r.fail("map %d/%d is missing." % [group, number])
		return null
	var _entry: Array = world.dispatch_map_entry()
	return world


## Ledge hops included, the way tools/checks/cinnabar.gd walks.
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
