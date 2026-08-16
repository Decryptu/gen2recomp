extends RefCounted

var _r: RefCounted = null

## Verifies `InitMapNameSign` and its sign against freshly imported real caches:
## every map on all three cartridges is asked what landmark it would raise, and
## every name that answers is drawn through the same [Gen2MapNameSignPage] the
## overworld displays.
##
## What a sampled map cannot say: the rule is three tests over the whole corpus
## (`GATE`, the two National Park gates, and `.CheckSpecialMap`'s six landmarks),
## and the sign is Crystal's own screen, so Gold and Silver must raise none at
## all rather than draw one out of a sheet they do not ship.
##
##   Godot --headless --path . -s res://tools/validate.gd -- map_name_sign

const TILE: int = Gen2Font.TILE
const SIZE: Vector2i = Vector2i(
	Gen2MapNameSignPage.COLUMNS * TILE, Gen2MapNameSignPage.ROWS * TILE
)


func run(r: RefCounted) -> void:
	_r = r
	_r.each_game(_check_game)


func _check_game() -> void:
	var maps: Array = _r.data.world_maps()
	var silent: int = 0
	var raising: Dictionary = {}
	for map: Gen2WorldMap in maps:
		var world: Gen2WorldAPI = Gen2WorldAPI.open(
			_r.data, map.group, map.number, Vector2i.ZERO
		)
		if world == null:
			continue
		var landmark: int = world.map_name_sign_landmark()
		_check_landmark(map, landmark)
		if not _raises(landmark):
			silent += 1
			continue
		raising[landmark] = int(raising.get(landmark, 0)) + 1
	if not _r.crystal:
		_r.check(
			_r.data.tile_indices("map_entry_sign").is_empty(),
			"Gold and Silver ship no MapEntryFrameGFX, but the cache holds one."
		)
		_r.check(
			Gen2MapNameSignPage.render(_r.data, "ROUTE 29") == null,
			"a sign was drawn on a cartridge with no map name sign."
		)
	_check_signs(raising.keys())
	_r.note("map name sign: %d of %d maps raise one, %d landmarks, %d silent" % [
		maps.size() - silent, maps.size(), raising.size(), silent
	])


## `.CheckNationalParkGate` and the `GetMapEnvironment` test behind it, which are
## the only two things that take a map's own landmark away.
func _check_landmark(map: Gen2WorldMap, landmark: int) -> void:
	var gate: bool = map.environment == Gen2WorldAPI.ENVIRONMENT_GATE \
		or (map.group == Gen2WorldAPI.NATIONAL_PARK_GATE_GROUP
			and Gen2WorldAPI.NATIONAL_PARK_GATE_MAPS.has(map.number))
	if gate:
		_r.check(
			landmark == Gen2WorldAPI.MAP_NAME_SIGN_NO_LANDMARK,
			"map %d/%d is a gate and still names landmark %d." % [
				map.group, map.number, landmark
			]
		)
		return
	_r.check(
		landmark == map.location,
		"map %d/%d names landmark %d, not its own %d." % [
			map.group, map.number, landmark, map.location
		]
	)


## Whether a map arrived at from a different landmark would raise a sign, which
## is `.CheckSpecialMap` once `.CheckMovingWithinLandmark` has been passed.
func _raises(landmark: int) -> bool:
	if not _r.crystal:
		return false
	return landmark != Gen2WorldAPI.MAP_NAME_SIGN_NO_LANDMARK \
		and not Gen2WorldAPI.MAP_NAME_SIGN_SILENT_LANDMARKS.has(landmark)


## Every landmark a map raises a sign for, drawn: the frame is the sheet's own
## fourteen tiles and the name is centred on `hlcoord 0, 2`, so the row above it
## must be blank interior and the name must sit inside the frame.
func _check_signs(landmarks: Array) -> void:
	for landmark: int in landmarks:
		var name: String = _r.data.landmark_name(landmark)
		if not _r.check(not name.is_empty(), "landmark %d has no name." % landmark):
			continue
		var image: Image = Gen2MapNameSignPage.render(_r.data, name)
		if not _r.check(image != null, "landmark %d draws no sign." % landmark):
			continue
		if not _r.check(
			image.get_size() == SIZE,
			"landmark %d draws %s, not %s." % [landmark, image.get_size(), SIZE]
		):
			continue
		var column: int = Gen2MapNameSignPage.name_column(name)
		var blank: Color = image.get_pixel(TILE + 1, TILE + 1)
		_r.check(
			_ink(image, Rect2i(
				Vector2i(column, Gen2MapNameSignPage.NAME_ROW) * TILE,
				Vector2i(Gen2Text.encoded_length(name), 1) * TILE
			), blank),
			"landmark %d draws no name where PlaceMapNameCenterAlign puts it." % landmark
		)
		_r.check(
			not _ink(image, Rect2i(
				Vector2i(TILE, TILE), Vector2i((Gen2MapNameSignPage.COLUMNS - 2) * TILE, TILE)
			), blank),
			"landmark %d draws on the sign's upper interior row." % landmark
		)
		_r.check(
			column + Gen2Text.encoded_length(name) <= Gen2MapNameSignPage.COLUMNS - 1,
			"landmark %d's name runs into the frame's right edge." % landmark
		)


static func _ink(image: Image, area: Rect2i, blank: Color) -> bool:
	for y: int in area.size.y:
		for x: int in area.size.x:
			if image.get_pixel(area.position.x + x, area.position.y + y) != blank:
				return true
	return false
