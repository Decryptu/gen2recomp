class_name Gen2TownMap
extends RefCounted

## `_TownMap` and the Pokegear's MAP card (engine/pokegear/pokegear.asm), as
## state rather than pixels: which region is drawn, where the cursor is and which
## landmarks it may reach.
##
## Both screens share `PokegearMap_UpdateLandmarkName` and the cursor walk; they
## differ in the frame drawn over the region map, which is [Gen2TownMapPage]'s
## business, and in what the Fast Ship counts as. Landmark numbering itself lives
## in [Gen2WorldRadio], whose station rules read the same table.

## `PokegearMap_JohtoMap`'s own `ld e, JOHTO_LANDMARK`.
const JOHTO_LANDMARK: int = 1

## `TownMap_GetKantoLandmarkLimits`' pre-Hall of Fame window, which is Victory
## Road to Route 28 rather than the whole region. Crystal's numbers; Gold and
## Silver's are one lower, the way every landmark past `BATTLE TOWER` is.
const LANDMARK_VICTORY_ROAD: int = 0x58
const LANDMARK_ROUTE_28: int = 0x5E

const REGION_JOHTO: int = 0
const REGION_KANTO: int = 1
## What the cache calls each region map, which is the pinned file name.
const REGION_NAMES: Array[String] = ["johto", "kanto"]

## Which screen is being drawn. `_TownMap` is the town map poster and the
## `OverworldTownMap` special; the card is the Pokegear's second page; the dex
## area is `Pokedex_GetArea`, which draws both maps and switches between them.
const SCREEN_TOWN_MAP: StringName = &"town_map"
const SCREEN_POKEGEAR_CARD: StringName = &"pokegear_card"
const SCREEN_DEX_AREA: StringName = &"dex_area"
## `_FlyMap`, which is the same two maps with the cursor walking flypoints
## instead of landmarks: `wTownMapPlayerIconLandmark` holds a `FLY_*` index there
## rather than a landmark, and the up and down presses skip every flypoint the
## player has not visited.
const SCREEN_FLY: StringName = &"fly"

## `FLY_INDIGO`, the last flypoint and Kanto's own default. It is also the one
## `FlyMap` tests before it will draw Kanto at all.
const FLY_INDIGO: int = RomLayout.FLYPOINT_COUNT - 1

var crystal: bool = true
var screen: StringName = SCREEN_TOWN_MAP
## `wTownMapPlayerIconLandmark`, which is where the player icon is drawn and
## which region the screen opens on.
var player_landmark: int = JOHTO_LANDMARK
## `wTownMapCursorLandmark`, which `Pokedex_GetArea` reuses to hold the region it
## is showing rather than a landmark.
var cursor: int = JOHTO_LANDMARK
## `STATUSFLAGS_HALL_OF_FAME_F`, which the dex area reads on every right press
## rather than once.
var hall_of_fame: bool = false
## Which `FLY_*` indexes the player has visited, for the fly map's own walk.
## Empty on every other screen, which reads none of it.
var visited_flypoints: Array[int] = []
var _first: int = JOHTO_LANDMARK
var _last: int = JOHTO_LANDMARK


## `FlyMap`: the fly map opened on whichever region the player is in, with the
## cursor on that region's default flypoint.
##
## [param visited] is which `FLY_*` indexes `CheckIfVisitedFlypoint` answers for,
## which is the `wVisitedSpawns` bit of each one's own spawn. Kanto is only drawn
## once Indigo Plateau is among them: `.NoKanto` falls back to Johto's map
## instead, which is what stops the source's own crash on a region with no
## flypoint enabled.
##
## The default flypoint is on the map whether or not it has been visited, which
## is the source's own quirk and is why New Bark can always be flown to.
static func fly(
	landmark: int, in_kanto: bool, visited: Array[int], is_crystal: bool
) -> Gen2TownMap:
	var out := Gen2TownMap.new()
	out.crystal = is_crystal
	out.screen = SCREEN_FLY
	out.visited_flypoints = visited.duplicate()
	# `.MapHud` hands `TownMapPlayerIcon` the landmark it popped, so the player
	# icon still says where the player is standing while the cursor walks
	# flypoints.
	out.player_landmark = landmark
	if in_kanto and visited.has(FLY_INDIGO):
		out._first = RomLayout.KANTO_FLYPOINT
		out._last = RomLayout.FLYPOINT_COUNT - 1
		out.cursor = FLY_INDIGO
	else:
		out._first = 0
		out._last = RomLayout.KANTO_FLYPOINT - 1
		out.cursor = 0
	return out


## `TownMap_GetCurrentLandmark` has already run: [param landmark] is the resolved
## one, never `LANDMARK_SPECIAL`. [param hall_of_fame] is `STATUSFLAGS_HALL_OF_FAME_F`,
## which is what opens the whole Kanto map rather than the Victory Road window.
static func create(
	landmark: int, is_crystal: bool, hall_of_fame: bool = false,
	on_screen: StringName = SCREEN_TOWN_MAP
) -> Gen2TownMap:
	var out := Gen2TownMap.new()
	out.crystal = is_crystal
	out.screen = on_screen
	out.hall_of_fame = hall_of_fame
	out.player_landmark = landmark
	if on_screen == SCREEN_DEX_AREA:
		# `.Area` sets hWY to 144 before calling, so the window is off and BG map
		# 0, the Johto one, is what `Pokedex_GetArea` opens on whatever landmark
		# the player is standing at.
		out.cursor = REGION_JOHTO
		return out
	if out.region() == REGION_KANTO:
		# `TownMap_GetKantoLandmarkLimits`. Its two branches end on the same
		# landmark, `LANDMARK_ROUTE_28` being `KANTO_LANDMARK_LAST`; only the
		# first moves, from Victory Road to the top of the region.
		out._first = Gen2WorldRadio.kanto_landmark(is_crystal) if hall_of_fame \
			else out._shift(LANDMARK_VICTORY_ROAD)
		out._last = out._shift(LANDMARK_ROUTE_28)
	else:
		out._first = JOHTO_LANDMARK
		out._last = Gen2WorldRadio.kanto_landmark(is_crystal) - 1
	# `_TownMap` writes the cursor from the same landmark the player icon takes
	# and never clamps it into the window, so a Kanto map opened before the Hall
	# of Fame starts below Victory Road and the first press walks in.
	out.cursor = landmark
	return out


## A Crystal landmark number on the active profile. Gold and Silver ship no
## `BATTLE TOWER`, so everything past it is one lower.
func _shift(landmark: int) -> int:
	if crystal:
		return landmark
	return landmark - 1


## Which map is drawn. `_TownMap` picks by number alone, so the Fast Ship shows
## Kanto there; `InitPokegearTilemap.Map` tests it first and shows Johto; the dex
## area is told which one to show and keeps it in the cursor byte.
func region() -> int:
	if screen == SCREEN_DEX_AREA:
		return cursor
	# `FlyMap` fills one region's map and walks that region's flypoints, and
	# `.NoKanto` is what puts a player standing in Kanto on Johto's.
	if screen == SCREEN_FLY:
		return REGION_KANTO if _first == RomLayout.KANTO_FLYPOINT else REGION_JOHTO
	if screen == SCREEN_POKEGEAR_CARD \
		and player_landmark == Gen2WorldRadio.fast_ship_landmark(crystal):
		return REGION_JOHTO
	return REGION_KANTO if player_landmark >= Gen2WorldRadio.kanto_landmark(crystal) \
		else REGION_JOHTO


static func region_name(region: int) -> String:
	return REGION_NAMES[clampi(region, REGION_JOHTO, REGION_KANTO)]


## `.CheckPlayerLocation`, which is what decides whether the dex area draws the
## player icon at all: the Fast Ship counts as Johto, and a player in the region
## that is not on screen is not drawn.
func player_in_region() -> bool:
	var player: int = REGION_KANTO if Gen2WorldRadio.is_kanto_landmark(
		player_landmark, crystal
	) else REGION_JOHTO
	return player == region()


func first_landmark() -> int:
	return _first


func last_landmark() -> int:
	return _last


## `.pressed_up` and `.pressed_down`, which wrap round the window's ends rather
## than stopping at them: a cursor already at the last landmark is rewound to one
## before the first and then stepped on.
##
## The dex area walks regions instead: `.left` shows Johto and `.right` Kanto,
## the second only once the Hall of Fame flag is set, and each returns without
## redrawing when that region is already up.
func press(button: int) -> bool:
	if screen == SCREEN_DEX_AREA:
		match button:
			Gen2Button.LEFT:
				if cursor == REGION_JOHTO:
					return false
				cursor = REGION_JOHTO
				return true
			Gen2Button.RIGHT:
				if not hall_of_fame or cursor == REGION_KANTO:
					return false
				cursor = REGION_KANTO
				return true
		return false
	match button:
		Gen2Button.UP:
			cursor = _first if cursor >= _last else cursor + 1
			_skip_unvisited(1)
			return true
		Gen2Button.DOWN:
			cursor = _last if cursor == _first else cursor - 1
			_skip_unvisited(-1)
			return true
	return false


## `.ScrollNext` and `.ScrollPrev`'s own loop: a press keeps stepping while the
## flypoint it lands on has not been visited, wrapping the way one press does.
## The window is at most twelve wide and the default is always on it, so the walk
## cannot run forever.
func _skip_unvisited(step: int) -> void:
	if screen != SCREEN_FLY:
		return
	for _guard: int in RomLayout.FLYPOINT_COUNT:
		if visited_flypoints.has(cursor) or cursor == _default_flypoint():
			return
		if step > 0:
			cursor = _first if cursor >= _last else cursor + 1
		else:
			cursor = _last if cursor == _first else cursor - 1


## Which flypoint the map opened on, and so the one the source leaves reachable
## whether or not it has been visited.
func _default_flypoint() -> int:
	return FLY_INDIGO if _first == RomLayout.KANTO_FLYPOINT else 0
