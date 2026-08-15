extends GutTest

## `_TownMap`'s region choice and cursor walk, which is all of the region map
## that is not pixels. The page and the imported art are covered by
## `tools/preview_town_map.gd` against a real cache.


func test_johto_window_is_the_whole_region_and_the_cursor_wraps() -> void:
	var map := Gen2TownMap.create(Gen2TownMap.JOHTO_LANDMARK, true)
	assert_eq(map.region(), Gen2TownMap.REGION_JOHTO)
	assert_eq(map.first_landmark(), 1)
	assert_eq(map.last_landmark(), 46)
	assert_eq(map.cursor, 1)

	map.press(Gen2Button.UP)
	assert_eq(map.cursor, 2)
	map.press(Gen2Button.DOWN)
	assert_eq(map.cursor, 1)
	## `.pressed_down` rewinds to one past the window's end and steps back.
	map.press(Gen2Button.DOWN)
	assert_eq(map.cursor, 46)
	map.press(Gen2Button.UP)
	assert_eq(map.cursor, 1)


func test_gold_and_silver_windows_sit_one_landmark_lower() -> void:
	var map := Gen2TownMap.create(Gen2TownMap.JOHTO_LANDMARK, false)
	assert_eq(map.last_landmark(), 45)
	map.press(Gen2Button.DOWN)
	assert_eq(map.cursor, 45)


func test_kanto_opens_on_the_victory_road_window_until_the_hall_of_fame() -> void:
	var sealed := Gen2TownMap.create(71, true)
	assert_eq(sealed.region(), Gen2TownMap.REGION_KANTO)
	assert_eq(sealed.first_landmark(), Gen2TownMap.LANDMARK_VICTORY_ROAD)
	assert_eq(sealed.last_landmark(), Gen2TownMap.LANDMARK_ROUTE_28)

	var opened := Gen2TownMap.create(71, true, true)
	assert_eq(opened.first_landmark(), 47)
	assert_eq(opened.last_landmark(), Gen2TownMap.LANDMARK_ROUTE_28)


func test_a_cursor_outside_the_window_walks_into_it_rather_than_being_clamped() -> void:
	## `_TownMap` writes the cursor from the player's own landmark and never
	## clamps it, so a Kanto map opened before the Hall of Fame starts below the
	## window and the first press lands inside it.
	var map := Gen2TownMap.create(47, true)
	assert_eq(map.cursor, 47)
	map.press(Gen2Button.UP)
	assert_eq(map.cursor, 48)
	map.press(Gen2Button.DOWN)
	assert_eq(map.cursor, 47)


func test_the_fast_ship_is_kanto_on_the_poster_and_johto_on_the_card() -> void:
	## `_TownMap.InitTilemap` picks by number alone; `InitPokegearTilemap.Map`
	## tests `LANDMARK_FAST_SHIP` first.
	var fast_ship: int = Gen2WorldRadio.fast_ship_landmark(true)
	var poster := Gen2TownMap.create(fast_ship, true)
	assert_eq(poster.region(), Gen2TownMap.REGION_KANTO)

	var card := Gen2TownMap.create(
		fast_ship, true, false, Gen2TownMap.SCREEN_POKEGEAR_CARD
	)
	assert_eq(card.region(), Gen2TownMap.REGION_JOHTO)


func test_only_the_d_pad_moves_the_cursor() -> void:
	var map := Gen2TownMap.create(10, true)
	assert_false(map.press(Gen2Button.A))
	assert_false(map.press(Gen2Button.LEFT))
	assert_eq(map.cursor, 10)


## `Pokedex_GetArea` opens on Johto whatever landmark it is given, holds the
## region in the cursor byte, and reaches Kanto only once the Hall of Fame flag
## is set.
func test_the_dex_area_walks_regions_rather_than_landmarks() -> void:
	var map := Gen2TownMap.create(71, true, false, Gen2TownMap.SCREEN_DEX_AREA)
	assert_eq(map.region(), Gen2TownMap.REGION_JOHTO)
	assert_false(map.press(Gen2Button.LEFT))
	assert_false(map.press(Gen2Button.UP))
	assert_false(map.press(Gen2Button.RIGHT))
	assert_eq(map.region(), Gen2TownMap.REGION_JOHTO)

	var opened := Gen2TownMap.create(71, true, true, Gen2TownMap.SCREEN_DEX_AREA)
	assert_true(opened.press(Gen2Button.RIGHT))
	assert_eq(opened.region(), Gen2TownMap.REGION_KANTO)
	assert_false(opened.press(Gen2Button.RIGHT))
	assert_true(opened.press(Gen2Button.LEFT))
	assert_eq(opened.region(), Gen2TownMap.REGION_JOHTO)


## `.CheckPlayerLocation`, which counts the Fast Ship as Johto rather than by
## number the way the poster does.
func test_the_dex_area_draws_the_player_only_in_their_own_region() -> void:
	var johto := Gen2TownMap.create(1, true, true, Gen2TownMap.SCREEN_DEX_AREA)
	assert_true(johto.player_in_region())
	johto.press(Gen2Button.RIGHT)
	assert_false(johto.player_in_region())

	var ship := Gen2TownMap.create(
		Gen2WorldRadio.fast_ship_landmark(true), true, true, Gen2TownMap.SCREEN_DEX_AREA
	)
	assert_true(ship.player_in_region())

	var kanto := Gen2TownMap.create(47, true, true, Gen2TownMap.SCREEN_DEX_AREA)
	assert_false(kanto.player_in_region())
	kanto.press(Gen2Button.RIGHT)
	assert_true(kanto.player_in_region())


## `_FlyMap`, whose cursor is a `FLY_*` index rather than a landmark and whose
## walk skips every flypoint the player has not visited.

func test_the_fly_map_opens_on_the_region_the_player_is_in() -> void:
	var johto := Gen2TownMap.fly(Gen2TownMap.JOHTO_LANDMARK, false, [] as Array[int], true)
	assert_eq(johto.region(), Gen2TownMap.REGION_JOHTO)
	assert_eq(johto.cursor, 0, "New Bark is Johto's default")
	assert_eq(johto.first_landmark(), 0)
	assert_eq(johto.last_landmark(), RomLayout.KANTO_FLYPOINT - 1)

	var kanto := Gen2TownMap.fly(
		60, true, [Gen2TownMap.FLY_INDIGO] as Array[int], true
	)
	assert_eq(kanto.region(), Gen2TownMap.REGION_KANTO)
	assert_eq(kanto.cursor, Gen2TownMap.FLY_INDIGO, "Indigo is Kanto's default")
	assert_eq(kanto.first_landmark(), RomLayout.KANTO_FLYPOINT)
	assert_eq(kanto.last_landmark(), RomLayout.FLYPOINT_COUNT - 1)
	# The player icon still says where the player is standing.
	assert_eq(kanto.player_landmark, 60)


func test_kanto_falls_back_to_johtos_map_until_indigo_plateau() -> void:
	# `.NoKanto`, which is what stops the source's own crash on a region with no
	# flypoint enabled.
	var map := Gen2TownMap.fly(60, true, [] as Array[int], true)
	assert_eq(map.region(), Gen2TownMap.REGION_JOHTO)
	assert_eq(map.cursor, 0)


func test_the_fly_cursor_skips_every_flypoint_that_has_not_been_visited() -> void:
	# Violet is flypoint 2 and Goldenrod 4; nothing between them is visited.
	var map := Gen2TownMap.fly(
		Gen2TownMap.JOHTO_LANDMARK, false, [2, 4] as Array[int], true
	)
	map.press(Gen2Button.UP)
	assert_eq(map.cursor, 2)
	map.press(Gen2Button.UP)
	assert_eq(map.cursor, 4)
	# Wrapping past the end lands back on the default, which is on the map
	# whether or not it has been visited.
	map.press(Gen2Button.UP)
	assert_eq(map.cursor, 0)
	map.press(Gen2Button.DOWN)
	assert_eq(map.cursor, 4)


func test_a_fly_map_with_nothing_visited_holds_its_default() -> void:
	var map := Gen2TownMap.fly(Gen2TownMap.JOHTO_LANDMARK, false, [] as Array[int], true)
	for press: int in [Gen2Button.UP, Gen2Button.DOWN, Gen2Button.UP]:
		map.press(press)
		assert_eq(map.cursor, 0)
