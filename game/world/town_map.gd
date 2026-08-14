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

## Which screen is being drawn. `_TownMap` is the town map poster and the
## `OverworldTownMap` special; the card is the Pokegear's second page.
const SCREEN_TOWN_MAP: StringName = &"town_map"
const SCREEN_POKEGEAR_CARD: StringName = &"pokegear_card"

var crystal: bool = true
var screen: StringName = SCREEN_TOWN_MAP
## `wTownMapPlayerIconLandmark`, which is where the player icon is drawn and
## which region the screen opens on.
var player_landmark: int = JOHTO_LANDMARK
## `wTownMapCursorLandmark`.
var cursor: int = JOHTO_LANDMARK
var _first: int = JOHTO_LANDMARK
var _last: int = JOHTO_LANDMARK


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
	out.player_landmark = landmark
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
## Kanto there; `InitPokegearTilemap.Map` tests it first and shows Johto.
func region() -> int:
	if screen == SCREEN_POKEGEAR_CARD \
		and player_landmark == Gen2WorldRadio.fast_ship_landmark(crystal):
		return REGION_JOHTO
	return REGION_KANTO if player_landmark >= Gen2WorldRadio.kanto_landmark(crystal) \
		else REGION_JOHTO


func first_landmark() -> int:
	return _first


func last_landmark() -> int:
	return _last


## `.pressed_up` and `.pressed_down`, which wrap round the window's ends rather
## than stopping at them: a cursor already at the last landmark is rewound to one
## before the first and then stepped on.
func press(button: int) -> bool:
	match button:
		Gen2Button.UP:
			cursor = _first if cursor >= _last else cursor + 1
			return true
		Gen2Button.DOWN:
			cursor = _last if cursor == _first else cursor - 1
			return true
	return false
