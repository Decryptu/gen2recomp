extends RefCounted

var _r: RefCounted = null

## Verifies the credits against freshly imported real caches, for both command
## profiles.
##
## The whole script is run to `CREDITS_END` rather than sampled: every command it
## carries, every string it names and every scene it selects is exercised once,
## which is the sweep tests/integration/test_credits.gd's four-string fixture
## cannot be. The expected values come from pokecrystal and pokegold's
## engine/movie/credits.asm, data/credits_script.asm and credits_strings.asm.
##
##   Godot --headless --path . -s res://tools/validate.gd -- credits


## Long enough for either script, whose own totals are pinned below.
const FRAME_CAP: int = 20000

## Census of the real caches, pinned so a cache change is loud: the frames the
## script takes to reach `CREDITS_END`, how many strings the table holds, and how
## many frames the BG map changes on, which is three per `CREDITS_WAIT` batch
## since `UpdateBGMap` copies it a third at a time.
const EXPECTED: Dictionary = {
	# game id: [frames to CREDITS_END, strings in the table, frames the BG map moves]
	&"gold": [6956, 76, 55],
	&"silver": [6956, 76, 55],
	&"crystal": [6982, 103, 83],
}

## `PlaceString`'s own vocabulary in these strings: a space, `<NEXT>`, `#` and
## the letters. Anything else is `CopyrightGFX`'s and belongs to one string.
const SPACE_CODE: int = 0x7F
const FIRST_LETTER: int = 0x80


func run(r: RefCounted) -> void:
	_r = r
	for game_id: StringName in _r.GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_verify_strings(game_id, data)
		_verify_palettes_and_frames(game_id, data)
		_run(game_id, data)


## Every string in the table, whose codes have to be ones the screen can draw:
## the font's, `<NEXT>`, `#`, or `CopyrightGFX`'s, which only the copyright
## string is allowed to name.
func _verify_strings(game_id: StringName, data: GameData) -> void:
	var copyright: int = data.credits_index("copyright")
	var count: int = 0
	while not data.credits_string(count).is_empty():
		count += 1
	_r.check(
		count == int(EXPECTED[game_id][1]),
		"%s: %d credits strings decode, not the pinned %d." % [
			game_id, count, int(EXPECTED[game_id][1]),
		]
	)
	for index: int in count:
		for code: int in data.credits_string(index):
			if code >= FIRST_LETTER or code == SPACE_CODE \
				or code == Gen2Credits.CODE_NEXT_LINE or code == Gen2Credits.CODE_POKE:
				continue
			_r.check(
				index == copyright and code >= RomLayout.COPYRIGHT_FIRST_CODE,
				"%s: credits string %d carries code $%02X, which is not a glyph." % [
					game_id, index, code,
				]
			)


## The four scenes' palettes and `Credits_LoadBorderGFX.Frames`, every entry of
## which has to name a block the imported mon run actually holds.
func _verify_palettes_and_frames(game_id: StringName, data: GameData) -> void:
	var strip: PackedByteArray = data.tile_indices("credits_mons")
	var blocks: int = 0
	if not strip.is_empty():
		@warning_ignore("integer_division")
		blocks = strip.size() / Gen2Tiles.TILE_HEIGHT / Gen2Tiles.TILE_WIDTH \
			/ RomLayout.CREDITS_MON_FRAME_TILES
	for scene: int in RomLayout.CREDITS_SCENES:
		for slot: int in [
			Gen2Credits.PALETTE_BANNER, Gen2Credits.PALETTE_BORDER, Gen2Credits.PALETTE_TEXT,
		]:
			_r.check(
				data.credits_palette(scene, slot).size() \
					== RomLayout.CREDITS_PALETTE_COLORS,
				"%s: credits scene %d has no palette in slot %d." % [game_id, scene, slot]
			)
		for frame: int in RomLayout.CREDITS_SCENE_FRAMES:
			var block: int = data.credits_frame_block(scene, frame)
			_r.check(
				block >= 0 and block < blocks,
				"%s: credits scene %d frame %d names block %d of %d." % [
					game_id, scene, frame, block, blocks,
				]
			)


## The whole script, frame by frame through the real page. Every batch it draws
## is checked for staying inside the text region, and the run has to reach
## `CREDITS_END` on the pinned frame with "The End" still on the BG map.
func _run(game_id: StringName, data: GameData) -> void:
	var page: Gen2CreditsPage = Gen2CreditsPage.from_data(data)
	if page == null or not page.ready():
		_r.fail("%s: the cache carries no credits graphics." % game_id)
		return
	var credits: Gen2Credits = Gen2Credits.create(data, true)
	if credits == null:
		_r.fail("%s: the cache carries no credits script." % game_id)
		return
	var crystal: bool = Gen2WorldState.is_crystal_profile(data)
	var bottom: int = Gen2Credits.BORDER_BOTTOM_ROW if crystal \
		else Gen2Credits.BORDER_BOTTOM_ROW_GOLD_SILVER
	var batches: int = 0
	var frames: int = 0
	var previous := PackedInt32Array()
	while frames < FRAME_CAP and not credits.finished():
		credits.advance_frame()
		frames += 1
		var map: PackedInt32Array = credits.bg_map()
		if map != previous:
			previous = map
			batches += 1
			_verify_region(game_id, map, bottom)
	_r.check(
		frames == int(EXPECTED[game_id][0]),
		"%s: the credits ran %d frames to CREDITS_END, not the pinned %d." % [
			game_id, frames, int(EXPECTED[game_id][0]),
		]
	)
	_r.check(
		batches == int(EXPECTED[game_id][2]),
		"%s: the BG map moved on %d frames, not the pinned %d." % [
			game_id, batches, int(EXPECTED[game_id][2]),
		]
	)
	var the_end: Vector2i = Gen2Credits.THE_END_AT if crystal \
		else Gen2Credits.THE_END_AT_GOLD_SILVER
	_r.check(
		credits.bg_map()[the_end.y * Gen2Credits.COLUMNS + the_end.x] \
			== Gen2Credits.THE_END_TILE,
		"%s: The End is not on screen when the script ends." % game_id
	)
	## The live path, not the model: a page that cannot resolve a tile the script
	## placed draws a hole rather than failing.
	var image: Image = page.image(data, credits.frame_state())
	_r.check(
		image.get_width() == Gen2Screen.WIDTH and image.get_height() == Gen2Screen.HEIGHT,
		"%s: the credits page did not draw a hardware screen." % game_id
	)


## `.parse` fills rows 5 to the lower border, and nothing it prints may reach
## either band: a string longer than the region would run into the border, which
## `PlaceString` has no clip to stop.
func _verify_region(game_id: StringName, map: PackedInt32Array, bottom: int) -> void:
	for column: int in Gen2Credits.COLUMNS:
		var within: int = column % Gen2Credits.BORDER_TILES
		_r.check(
			map[Gen2Credits.BORDER_TOP_ROW * Gen2Credits.COLUMNS + column] \
				== Gen2Credits.BORDER_TOP_TILE + within,
			"%s: the credits text reached the upper border band." % game_id
		)
		_r.check(
			map[bottom * Gen2Credits.COLUMNS + column] \
				== Gen2Credits.BORDER_BOTTOM_TILE + within,
			"%s: the credits text reached the lower border band." % game_id
		)
