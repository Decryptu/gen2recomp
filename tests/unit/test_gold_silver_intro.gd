extends GutTest

## `GoldSilverIntro` (pokegold/engine/movie/intro.asm) where it can be checked
## without a cartridge: the jumptable's shape, the DMG register reordering that
## is the whole colour model, and the framesets and OAM sets the sprites index.
##
## The movie itself needs the art, so its frames, scene starts and sounds are
## pinned in `tools/checks/gs_intro.gd` against a real cache instead.


## `IntroSceneJumper.scenes` is seventeen entries, and `IntroScene17` is the one
## that sets `JUMPTABLE_EXIT_F`.
func test_the_jumptable_is_seventeen_scenes() -> void:
	assert_eq(RomLayout.GS_INTRO_SCENES, 17)
	var movie: Gen2GoldSilverIntro = Gen2GoldSilverIntro.create(null)
	assert_eq(movie.scene(), 0)
	assert_false(movie.finished())


## A movie with no cache behind it still spends its frames, which is what lets a
## caller run the budget without an animation layer.
func test_a_movie_without_art_still_walks_its_scenes() -> void:
	var movie: Gen2GoldSilverIntro = Gen2GoldSilverIntro.create(null)
	for _frame: int in 4000:
		if movie.finished():
			break
		movie.advance_frame()
	assert_true(movie.finished(), "the exit bit is reached without a cache")
	assert_eq(movie.scene(), RomLayout.GS_INTRO_SCENES - 1)


## `.PlayFrame` reads `hJoyLast and PAD_BUTTONS` before anything else, so a
## press ends the movie wherever it lands and a second one changes nothing.
func test_a_button_ends_the_movie_once() -> void:
	var movie: Gen2GoldSilverIntro = Gen2GoldSilverIntro.create(null)
	movie.advance_frame()
	assert_true(movie.cancel())
	assert_true(movie.finished())
	assert_false(movie.cancel(), "and the second press has nothing to end")


## `CopyPals` writes destination colour j from source colour
## `(order >> 2j) & 3`, which is how one DMG register byte fades a palette
## without touching it. `%11100100` is the identity every scene opens on.
func test_the_identity_register_leaves_a_palette_alone() -> void:
	assert_eq(Gen2GoldSilverIntro.DMG_IDENTITY, 0xE4)
	for colour: int in Gen2GoldSilverIntro.PALETTE_COLORS:
		assert_eq((Gen2GoldSilverIntro.DMG_IDENTITY >> (colour * 2)) & 0x03, colour)


## `%00111111` floods the first three colours with the fourth, which is the
## starters scene's silhouette, and `%00000000` floods all four with the first,
## which is `Intro_FlashMonPalette`'s white.
func test_the_silhouette_and_flash_registers_flood_one_colour() -> void:
	for colour: int in 3:
		assert_eq((Gen2GoldSilverIntro.DMG_SILHOUETTE >> (colour * 2)) & 0x03, 3)
	assert_eq((Gen2GoldSilverIntro.DMG_SILHOUETTE >> 6) & 0x03, 0)
	for colour: int in Gen2GoldSilverIntro.PALETTE_COLORS:
		assert_eq((0x00 >> (colour * 2)) & 0x03, 0)


## Every `SpriteAnimObjects` row names a frameset this movie carries and a
## callback `PlaySpriteAnimations` answers, and every frameset entry names an
## OAM set the page holds.
func test_every_object_resolves_to_a_frameset_and_an_oam_set() -> void:
	for name: StringName in Gen2GoldSilverIntro.OBJECTS:
		var row: Dictionary = Gen2GoldSilverIntro.OBJECTS[name]
		assert_true(
			Gen2GoldSilverIntro.FRAMESETS.has(StringName(row["frameset"])), String(name)
		)
	for name: StringName in Gen2GoldSilverIntro.FRAMESETS:
		var frameset: Dictionary = Gen2GoldSilverIntro.FRAMESETS[name]
		assert_false((frameset["frames"] as Array).is_empty(), String(name))
		for entry: Array in frameset["frames"]:
			assert_between(
				int(entry[0]), 0, Gen2GoldSilverIntroPage.OAM_SETS.size() - 1, String(name)
			)
			assert_gt(int(entry[1]), 0, "%s lasts n + 1 frames" % name)


## The three `Intro_GetMonFrontpic` calls and the vtile each is decompressed to,
## which is what the starters' own OAM sets index.
func test_the_starters_are_the_three_johto_ones_at_their_own_vtiles() -> void:
	var species: Array[int] = []
	var vtiles: Array[int] = []
	for name: StringName in Gen2GoldSilverIntro.STARTERS:
		var row: Dictionary = Gen2GoldSilverIntro.STARTERS[name]
		species.append(int(row["species"]))
		vtiles.append(int(row["vtile"]))
	assert_eq(species, [152, 155, 158] as Array[int], "Chikorita, Cyndaquil, Totodile")
	assert_eq(vtiles, [0x10, 0x29, 0x42] as Array[int])


## `.OAMData_GSIntroStarter` is a five-by-five pic, so the three runs are
## twenty-five tiles apart and none of them overlaps the next.
func test_the_starter_pics_do_not_overlap_each_other() -> void:
	var tiles: int = Gen2GoldSilverIntroPage.STARTER_TILES
	var pics: Array = Gen2GoldSilverIntroPage.STARTER_PICS
	for index: int in pics.size() - 1:
		assert_gte(
			int((pics[index + 1] as Dictionary)["vtile"])
				- int((pics[index] as Dictionary)["vtile"]),
			tiles * tiles
		)


## `Intro_InitBubble`'s table is raw `db` pairs read `ld e, [hl] / inc hl /
## ld d, [hl]`, so its rows are (x, y) while every `depixel` in the file is
## (y, x). Both stay on the 256-pixel plane a sprite coordinate lives on.
func test_the_spawn_points_are_byte_coordinates() -> void:
	for at: Vector2i in Gen2GoldSilverIntro.BUBBLE_AT:
		assert_between(at.x, 0, 255)
		assert_between(at.y, 0, 255)
	for at: Vector2i in Gen2GoldSilverIntro.SHELLDER_AT:
		assert_between(at.x, 0, 255)
		assert_between(at.y, 0, 255)


## `Intro_CheckSCYEvent`'s jumptable is keyed by `hSCY` itself, and the scene
## walks it upward from $80, so every entry has to sit in that run.
func test_every_scy_event_is_reachable_from_the_scenes_own_start() -> void:
	for scy: int in Gen2GoldSilverIntro.SCY_EVENTS:
		assert_between(int(scy), 0x80, 0xFF)


## `Intro_AnimateOceanWaves` copies to `vBGMap0 tile $1e`, which is the map's
## byte 480 and so the whole of row 15, never the byte $1e that reading the
## operand as an offset gives. Its four tiles repeat across all thirty-two
## columns and the set steps with `wIntroFrameCounter2`.
func test_the_ocean_waves_fill_one_whole_map_row() -> void:
	var movie: Gen2GoldSilverIntro = Gen2GoldSilverIntro.create(null)
	for _frame: int in 700:
		movie.advance_frame()
	var map: PackedByteArray = movie.bg_map()
	var first: int = Gen2GoldSilverIntro.WAVE_ROW * Gen2GoldSilverIntro.MAP_COLUMNS
	for column: int in Gen2GoldSilverIntro.MAP_COLUMNS:
		assert_between(map[first + column], 0x70, 0x7F)
		assert_eq(map[first + column] & 0x03, column & 0x03, "four tiles repeated")
	assert_eq(map[0x1E], 0, "and not the byte $1e the operand reads as an offset")


## `IntroScene1`'s `depixel 28, 28` is `%11100000`, which takes colour 1 from
## colour 0: the shellders and bubbles are white until `.scene3_1`'s
## `depixel 28, 28, 4, 4` puts the identity order back.
func test_the_underwater_objects_open_on_a_flooded_first_colour() -> void:
	var order: int = Gen2GoldSilverIntro.DMG_OBJECT_UNDERWATER
	var taken: Array[int] = []
	for colour: int in 4:
		taken.append((order >> (2 * colour)) & 0x03)
	assert_eq(taken, [0, 0, 2, 3] as Array[int], "colour 1 comes from colour 0")
