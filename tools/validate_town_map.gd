extends SceneTree

## Verifies the region map against freshly imported real caches, on all three
## cartridges.
##
## The expected values come from the pinned sources: data/maps/landmarks.asm,
## gfx/pokegear/johto.bin and kanto.bin, gfx/pokegear/town_map_palette_map.asm,
## and engine/pokegear/pokegear.asm's `_TownMap`, `PokegearMap` and
## `TownMap_GetKantoLandmarkLimits`.
##
## The real-cartridge counterpart to tests/unit/test_town_map.gd and
## test_town_map_page.gd, which use a synthetic cache. What only a real cache can
## say is that the 96 landmarks and the two 360-cell maps decoded, that the
## Gold/Silver split is exactly the one `BATTLE TOWER` causes, that every
## landmark's icon lands on the screen it is drawn on, and that `FindNest` keeps
## each region's own wild tables over all 251 species.
##
##   Godot --headless --path . -s res://tools/validate_town_map.gd

const GAME_IDS: Array[StringName] = [&"gold", &"silver", &"crystal"]

## The one landmark Gold and Silver do not ship, and the two either side of it in
## Crystal's table.
const BATTLE_TOWER: int = 29
const LIGHTHOUSE_NAME: String = "LIGHTHOUSE"
const BATTLE_TOWER_NAME: String = "BATTLE TOWER"
const ROUTE_40_NAME: String = "ROUTE 40"

## Landmarks whose names carry the `<BSP>` the region map breaks a line on, and
## one that does not, so both branches are covered on a real name.
const BROKEN_NAME: int = 1
const UNBROKEN_NAME: int = 2

## An icon is 16 pixels drawn around the landmark's own point, so a point within
## eight pixels of an edge hangs off it. Only `SPECIAL`, which is at (-8,-16) and
## is drawn by nothing, does.
const ICON_ORIGIN: int = Gen2TownMapScreen.ICON_ORIGIN
const LANDMARK_SPECIAL: int = 0

## `wShadowOAMEnd - wShadowOAM` in sprites, which is what `.nestloop` would run
## past if a species were found at more landmarks than the hardware has objects.
const SHADOW_OAM_SPRITES: int = 40

var _failures: PackedStringArray = []


func _initialize() -> void:
	for game_id: StringName in GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		var crystal: bool = Gen2WorldState.is_crystal_profile(data)
		_verify_landmarks(game_id, data, crystal)
		_verify_regions(game_id, data)
		_verify_palettes(game_id, data, crystal)
		_verify_cursor_walk(game_id, data, crystal)
		_verify_page(game_id, data, crystal)
		_verify_nests(game_id, data, crystal)
	_finish()


func _verify_landmarks(game_id: StringName, data: GameData, crystal: bool) -> void:
	var wanted: int = RomLayout.LANDMARK_COUNT if crystal \
		else RomLayout.LANDMARK_COUNT_GOLD_SILVER
	if not _check(
		data.landmark_count() == wanted,
		"%s: %d landmarks, expected %d." % [game_id, data.landmark_count(), wanted]
	):
		return
	_check(
		data.landmark_name(LANDMARK_SPECIAL) == "SPECIAL",
		"%s: landmark 0 is %s, not SPECIAL." % [game_id, data.landmark_name(LANDMARK_SPECIAL)]
	)
	# The whole profile split, as one row: Crystal inserts BATTLE TOWER after the
	# Lighthouse and everything past it is one higher.
	_check(
		data.landmark_name(BATTLE_TOWER - 1) == LIGHTHOUSE_NAME,
		"%s: landmark %d is %s, not %s." % [
			game_id, BATTLE_TOWER - 1, data.landmark_name(BATTLE_TOWER - 1), LIGHTHOUSE_NAME,
		]
	)
	var after: String = BATTLE_TOWER_NAME if crystal else ROUTE_40_NAME
	_check(
		data.landmark_name(BATTLE_TOWER) == after,
		"%s: landmark %d is %s, not %s." % [
			game_id, BATTLE_TOWER, data.landmark_name(BATTLE_TOWER), after,
		]
	)
	_check(
		data.landmark_name(data.landmark_count() - 1) == "FAST SHIP",
		"%s: the last landmark is %s, not FAST SHIP." % [
			game_id, data.landmark_name(data.landmark_count() - 1),
		]
	)
	_check(
		_breaks(data, BROKEN_NAME),
		"%s: landmark %d carries no line break." % [game_id, BROKEN_NAME]
	)
	_check(
		not _breaks(data, UNBROKEN_NAME),
		"%s: landmark %d carries a line break it should not." % [game_id, UNBROKEN_NAME]
	)
	for index: int in range(1, data.landmark_count()):
		var entry: Dictionary = data.landmark(index)
		var x: int = int(entry.get("x", -1))
		var y: int = int(entry.get("y", -1))
		if not _check(
			x >= ICON_ORIGIN and x + ICON_ORIGIN <= Gen2Screen.WIDTH \
				and y >= ICON_ORIGIN and y + ICON_ORIGIN <= Gen2Screen.HEIGHT,
			"%s: landmark %d (%s) is at (%d,%d); its icon hangs off the screen." % [
				game_id, index, data.landmark_name(index), x, y,
			]
		):
			return


## Whether a landmark's name carries the `<BSP>` the region map breaks on.
func _breaks(data: GameData, landmark: int) -> bool:
	var codes: PackedByteArray = data.landmark(landmark).get("codes", PackedByteArray())
	return Gen2TownMapPage.NAME_BREAK_CODES[0] in codes


func _verify_regions(game_id: StringName, data: GameData) -> void:
	for region: String in ["johto", "kanto"]:
		var cells: PackedByteArray = data.town_map_region(region)
		if not _check(
			cells.size() == RomLayout.TOWN_MAP_REGION_CELLS,
			"%s: the %s map is %d cells, expected %d." % [
				game_id, region, cells.size(), RomLayout.TOWN_MAP_REGION_CELLS,
			]
		):
			continue
		for cell: int in cells:
			if not _check(
				cell < RomLayout.TOWN_MAP_TILES,
				"%s: the %s map names tile $%02X, past TownMapGFX." % [game_id, region, cell]
			):
				break


func _verify_palettes(game_id: StringName, data: GameData, crystal: bool) -> void:
	for slot: int in RomLayout.TOWN_MAP_PALETTES:
		var colors: PackedColorArray = data.town_map_palette(slot)
		if not _check(
			colors.size() == RomLayout.TOWN_MAP_PALETTE_COLORS,
			"%s: region palette %d has %d colours." % [game_id, slot, colors.size()]
		):
			continue
		_check(
			colors[0] == Gen2Palette.from_packed(RomLayout.TOWN_MAP_PALETTE_FIRST_COLOR),
			"%s: region palette %d does not open on the shared off-white." % [game_id, slot]
		)
	# `TownMapPals`' table stops at $60; the font above it takes palette 0.
	_check(
		data.town_map_palette_of(RomLayout.TOWN_MAP_PALETTE_MAP_LIMIT) == 0,
		"%s: a tile past the palette map is not on palette 0." % game_id
	)
	# `FemalePokegearPals` differs from the male run in its city palette alone,
	# and only Crystal ships one.
	var male: PackedColorArray = data.town_map_palette(Gen2TownMapPage.CITY_PALETTE)
	var female: PackedColorArray = data.town_map_palette(Gen2TownMapPage.CITY_PALETTE, true)
	_check(
		(male != female) == crystal,
		"%s: the female city palette %s the male one." % [
			game_id, "matches" if male == female else "differs from",
		]
	)


## `.pressed_up` and `.pressed_down` walk the whole window and wrap at both ends,
## so a full lap visits every landmark in it exactly once and comes home.
func _verify_cursor_walk(game_id: StringName, data: GameData, crystal: bool) -> void:
	for opened: bool in [false, true]:
		for landmark: int in [Gen2TownMap.JOHTO_LANDMARK, Gen2WorldRadio.kanto_landmark(crystal)]:
			var map := Gen2TownMap.create(landmark, crystal, opened)
			map.cursor = map.first_landmark()
			var seen: Dictionary = {}
			var length: int = map.last_landmark() - map.first_landmark() + 1
			for _step: int in length:
				seen[map.cursor] = true
				map.press(Gen2Button.UP)
			_check(
				seen.size() == length and map.cursor == map.first_landmark(),
				"%s: the %d..%d window walks %d landmarks and lands on %d." % [
					game_id, map.first_landmark(), map.last_landmark(), seen.size(), map.cursor,
				]
			)
			map.press(Gen2Button.DOWN)
			_check(
				map.cursor == map.last_landmark(),
				"%s: DOWN from %d reached %d, not %d." % [
					game_id, map.first_landmark(), map.cursor, map.last_landmark(),
				]
			)
	# Kanto opens on the Victory Road window until the Hall of Fame is set.
	var kanto: int = Gen2WorldRadio.kanto_landmark(crystal)
	var sealed := Gen2TownMap.create(kanto, crystal, false)
	var shift: int = 0 if crystal else 1
	_check(
		sealed.first_landmark() == Gen2TownMap.LANDMARK_VICTORY_ROAD - shift,
		"%s: the sealed Kanto window opens at %d." % [game_id, sealed.first_landmark()]
	)
	_check(
		Gen2TownMap.create(kanto, crystal, true).first_landmark() == kanto,
		"%s: the Hall of Fame does not open the whole Kanto window." % game_id
	)


## The page against the real art: every tile a region map or a frame names has to
## resolve out of the two sheets, and both screens have to compose.
func _verify_page(game_id: StringName, data: GameData, crystal: bool) -> void:
	var page: Gen2TownMapPage = Gen2TownMapPage.from_data(data)
	if not _check(page != null and page.ready(), "%s: the region map art is missing." % game_id):
		return
	# The two objects the screen draws come off strips of their own.
	for sheet: Array in [
		["pokegear_sprites", RomLayout.POKEGEAR_SPRITE_TILES],
		["fast_ship", RomLayout.FAST_SHIP_TILES],
	]:
		_check(
			data.tile_indices(String(sheet[0])).size()
				== int(sheet[1]) * Gen2Tiles.TILE_PIXELS,
			"%s: the %s strip is not %d tiles." % [game_id, sheet[0], int(sheet[1])]
		)
	for screen: StringName in [
		Gen2TownMap.SCREEN_TOWN_MAP, Gen2TownMap.SCREEN_POKEGEAR_CARD,
		Gen2TownMap.SCREEN_DEX_AREA,
	]:
		for region: String in ["johto", "kanto"]:
			var landmark: int = BROKEN_NAME if region == "johto" \
				else Gen2WorldRadio.kanto_landmark(crystal)
			var map: PackedInt32Array = page.tilemap(
				data.town_map_region(region),
				data.landmark(landmark).get("codes", PackedByteArray()),
				screen,
				[&"map", &"phone", &"radio"] as Array,
			)
			var image: Image = page.image(data, map)
			_check(
				image.get_width() == Gen2Screen.WIDTH \
					and image.get_height() == Gen2Screen.HEIGHT,
				"%s: the %s %s screen did not compose." % [game_id, region, screen]
			)


## `FindNest` over the whole species range, which is the only sweep that can say
## the merged encounter tables kept their regions: a Johto walk that reached a
## Kanto row would put a nest on the wrong map.
func _verify_nests(game_id: StringName, data: GameData, crystal: bool) -> void:
	_check(
		data.tile_indices("dex_nest_icon").size()
			== RomLayout.DEX_NEST_ICON_TILES * Gen2Tiles.TILE_PIXELS,
		"%s: the dex nest icon is not one tile." % game_id
	)
	var kanto_first: int = Gen2WorldRadio.kanto_landmark(crystal)
	var roaming: Array = data.world_roaming_mons()
	var deepest: int = 0
	for species: int in range(1, RomLayout.SPECIES_COUNT + 1):
		for region: int in Gen2TownMap.REGION_NAMES.size():
			var list: Array = Gen2WorldEncounter.nests(
				data, species, Gen2TownMap.region_name(region), roaming
			)
			deepest = maxi(deepest, list.size())
			var seen: Dictionary = {}
			for landmark: int in list:
				var in_kanto: bool = landmark >= kanto_first
				if not _check(
					landmark != LANDMARK_SPECIAL and in_kanto == (region == Gen2TownMap.REGION_KANTO)
						and not seen.has(landmark),
					"%s: species %d's %s nests name landmark %d." % [
						game_id, species, Gen2TownMap.region_name(region), landmark,
					]
				):
					return
				seen[landmark] = true
	# `.nestloop` writes straight into shadow OAM with no bound of its own, so a
	# species over forty landmarks would run past it. None comes close.
	_check(
		deepest <= SHADOW_OAM_SPRITES,
		"%s: a species nests at %d landmarks, past shadow OAM's %d." % [
			game_id, deepest, SHADOW_OAM_SPRITES,
		]
	)
	# `.RoamMon1` and `.RoamMon2` put a roamer on whatever map it is standing on,
	# and only in Johto. There is no `.RoamMon3`, so Gold and Silver's Suicune
	# has no nest at all.
	for index: int in roaming.size():
		var mon: Dictionary = roaming[index]
		var species: int = int(mon["species"])
		var map: Gen2WorldMap = data.world_map(int(mon["map_group"]), int(mon["map_number"]))
		var wanted: Array = [] if index >= Gen2WorldEncounter.ROAM_NEST_MONS \
			else [map.location]
		_check(
			Gen2WorldEncounter.nests(data, species, "johto", roaming) == wanted,
			"%s: roamer %d (species %d) does not nest on %s." % [
				game_id, index, species, str(wanted),
			]
		)
		_check(
			Gen2WorldEncounter.nests(data, species, "kanto", roaming).is_empty(),
			"%s: roamer %d (species %d) nests in Kanto." % [game_id, index, species]
		)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print(
			"PASS town map: the landmark tables and their profile split, both region "
			+ "maps, the palette map and its two city palettes, the cursor windows, all "
			+ "three frames and every species' nests verified."
		)
		quit(0)
		return
	for message: String in _failures:
		print("FAIL %s" % message)
	quit(1)
