extends RefCounted

var _r: RefCounted = null

## Verifies the intro movie against freshly imported real caches, on all three
## cartridges.
##
## The whole movie is run to `JUMPTABLE_EXIT_F` rather than sampled: every scene
## of the jumptable, every sprite it spawns and every sound it asks for is
## exercised once. The expected values come from pokecrystal's
## engine/movie/intro.asm and data/sprite_anims/.
##
## Gold and Silver carry `GoldSilverIntro`, a different movie that is not
## imported, so they are checked for saying so rather than for running.
##
##   Godot --headless --path . -s res://tools/validate.gd -- intro_movie

const MOVIE_GAMES: Array[StringName] = [&"crystal"]

## Long enough for the movie, whose own total is pinned below.
const FRAME_CAP: int = 20000

## Census of the real Crystal cache, pinned so a change is loud: the frames the
## jumptable takes to set its exit bit, the frame each scene starts on, and how
## many sounds the movie asks for.
const EXPECTED_FRAMES: int = 2338
const EXPECTED_SCENE_STARTS: Array[int] = [
	0, 1, 188, 189, 359, 360, 547, 548, 733, 734, 933, 934, 1168, 1169, 1371,
	1372, 1559, 1560, 1713, 1714, 1925, 1926, 1938, 1939, 1972, 2036, 2037, 2209,
]
const EXPECTED_SFX: int = 17
const EXPECTED_MUSIC: int = 1

## `IntroScene10` is the one frame that asks shadow OAM for more than it holds:
## Wooper's sixteen and Pichu's twenty-five come to forty-one, one past
## `wShadowOAMEnd`, so the page drops the last of them the way `UpdateAnimFrame`
## does. Pinned rather than bounded, because the overflow is the finding.
const PEAK_SPRITES: int = 41


func run(r: RefCounted) -> void:
	_r = r
	for game_id: StringName in _r.GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		if not MOVIE_GAMES.has(game_id):
			_r.check(
				not Gen2IntroMovie.available(data),
				"%s reports an intro movie it does not ship." % game_id
			)
			continue
		if not _r.check(
			Gen2IntroMovie.available(data), "%s carries no intro movie art." % game_id
		):
			continue
		_verify_section(game_id, data)
		_run(game_id, data)


## Every entry of the section, at the size the routine that loads it asks VRAM
## for. The walk is what says the one pinned address is right, so a cache whose
## sheets are the wrong length has been imported from the wrong offset.
func _verify_section(game_id: StringName, data: GameData) -> void:
	for row: Array in RomLayout.INTRO_SECTION:
		var name: String = String(row[0])
		match String(row[1]):
			"pal":
				_r.check(
					data.intro_palette(name).size()
						== RomLayout.INTRO_PALETTES * RomLayout.INTRO_PALETTE_COLORS,
					"%s: intro palette run %s is not sixteen palettes." % [game_id, name]
				)
			"map", "attr":
				_r.check(
					data.intro_map(name).size() == RomLayout.INTRO_MAP_BYTES,
					"%s: intro map %s is not a whole BG map." % [game_id, name]
				)
			_:
				var strip: PackedByteArray = data.tile_indices("intro_%s" % name)
				_r.check(
					strip.size() == int(row[2]) * Gen2Tiles.TILE_WIDTH * Gen2Tiles.TILE_HEIGHT,
					"%s: intro sheet %s is not %d tiles." % [game_id, name, int(row[2])]
				)
	for name: String in ["fade", "unown"]:
		_r.check(
			not data.intro_palette(name).is_empty(),
			"%s: the intro %s palettes are missing." % [game_id, name]
		)


## One pixel per tile the screen covers, plus its last one, which is the extra
## tile a scroll that is not a multiple of eight reaches into.
static func _steps(size: int) -> Array[int]:
	var out: Array[int] = []
	for step: int in size / Gen2Tiles.TILE_WIDTH:
		out.append(step * Gen2Tiles.TILE_WIDTH)
	out.append(size - 1)
	return out


func _sheet_tiles(data: GameData, name: String) -> int:
	if name.is_empty():
		return 0
	return int(data.tile_sheet("intro_%s" % name).get("tiles", 0))


## Every BG cell the movie actually samples has to name a tile the sheet that
## part of VRAM currently holds, and every attribute byte a palette its own run
## has. Sampled rather than whole, because only 360 of a map's 1,024 cells are
## the picture: the rest of the Unown maps is $ff, which nothing scrolls onto and
## no scene has loaded a sheet for.
##
## This is what says `SCENE_VRAM` pairs a map with a sheet the way the setup
## scenes do, and that the halves a scene does not reload carry forward: the
## close-up's own map names thirty-three tiles below $80, which read the leaping
## Suicune `IntroScene15` left in `vTiles2`.
func _verify_sampled_tiles(game_id: StringName, movie: Gen2IntroMovie, data: GameData) -> bool:
	var map: PackedByteArray = movie.bg_map()
	var attr: PackedByteArray = movie.bg_attr()
	if map.size() != RomLayout.INTRO_MAP_BYTES:
		return true
	var screen: PackedByteArray = movie.screen_tilemap()
	var low: int = _sheet_tiles(data, movie.sheet("bg")) - movie.sheet_first_tile("bg")
	var high: int = _sheet_tiles(data, movie.sheet("bg_high")) \
		- movie.sheet_first_tile("bg_high")
	var scy: int = movie.scroll().y
	for line: int in _steps(Gen2Screen.HEIGHT):
		var scx: int = movie.scroll_x_at(line)
		var map_row: int = (((line + scy) & 0xFF) / Gen2Tiles.TILE_HEIGHT) % RomLayout.INTRO_MAP_ROWS
		for x: int in _steps(Gen2Screen.WIDTH):
			var map_column: int = ((((x + scx) & 0xFF)
				/ Gen2Tiles.TILE_WIDTH) % RomLayout.INTRO_MAP_COLUMNS)
			var cell: int = map_row * RomLayout.INTRO_MAP_COLUMNS + map_column
			var tile: int = map[cell]
			if not screen.is_empty() and map_column < Gen2IntroMovie.COLUMNS \
					and map_row < Gen2IntroMovie.ROWS:
				tile = screen[map_row * Gen2IntroMovie.COLUMNS + map_column]
			var held: int = high if tile >= 0x80 else low
			if not _r.check(
				(tile - 0x80 if tile >= 0x80 else tile) < held,
				"%s: frame %d, scene %d draws BG tile $%02X, past its own sheet." % [
					game_id, movie.frame(), movie.scene(), tile,
				]
			):
				return false
			if not _r.check(
				attr[cell] & 0x07 < Gen2IntroMovie.BG_PALETTES,
				"%s: frame %d names a background palette past the eighth." % [
					game_id, movie.frame(),
				]
			):
				return false
	return true


## The whole movie, frame by frame: the scene starts, the sounds and the sprite
## count. Every sound record it names has to resolve on the cache as well, since
## a `PlaySFX` the driver cannot answer is a silent scene rather than an error.
func _run(game_id: StringName, data: GameData) -> void:
	var movie: Gen2IntroMovie = Gen2IntroMovie.create(
		data, Gen2SplashScreen._sine_table(data)
	)
	var page: Gen2IntroMoviePage = Gen2IntroMoviePage.from_data(data)
	_r.check(page != null, "%s: the intro movie page will not build." % game_id)
	var starts: Array[int] = [0]
	var scene: int = 0
	var sfx: int = 0
	var music: int = 0
	var most: int = 0
	var sampled: bool = true
	while not movie.finished() and movie.frame() < FRAME_CAP:
		for event: Dictionary in movie.advance_frame():
			match StringName(event.get("type", &"")):
				&"play_sfx":
					sfx += 1
					_r.check(
						not data.world_audio(&"sfx", int(event["sfx"])).is_empty(),
						"%s: intro sfx %d resolves to no record." % [
							game_id, int(event["sfx"]),
						]
					)
				&"play_music":
					music += 1
					_r.check(
						not data.world_audio(&"music", int(event["music"])).is_empty(),
						"%s: intro music %d resolves to no record." % [
							game_id, int(event["music"]),
						]
					)
		if movie.scene() != scene:
			scene = movie.scene()
			starts.append(movie.frame())
		most = maxi(most, _sprite_count(movie))
		if sampled and not _verify_sampled_tiles(game_id, movie, data):
			sampled = false
	_r.check(
		movie.finished(),
		"%s: the intro movie never set its exit bit." % game_id
	)
	_r.check(
		movie.frame() == EXPECTED_FRAMES,
		"%s: the intro movie ran %d frames, not the pinned %d." % [
			game_id, movie.frame(), EXPECTED_FRAMES,
		]
	)
	_r.check(
		starts == EXPECTED_SCENE_STARTS,
		"%s: the intro scenes start on %s, not the pinned starts." % [game_id, starts]
	)
	_r.check(
		sfx == EXPECTED_SFX and music == EXPECTED_MUSIC,
		"%s: the intro asked for %d effects and %d songs, not %d and %d." % [
			game_id, sfx, music, EXPECTED_SFX, EXPECTED_MUSIC,
		]
	)
	_r.check(
		most == PEAK_SPRITES,
		"%s: the intro's busiest frame asked for %d sprites, not the pinned %d." % [
			game_id, most, PEAK_SPRITES,
		]
	)


## How many shadow-OAM entries this frame's structs add up to.
func _sprite_count(movie: Gen2IntroMovie) -> int:
	var total: int = 0
	for sprite: Dictionary in movie.sprites():
		var set: Dictionary = Gen2IntroMoviePage.OAM_SETS[int(sprite["set"])]
		total += (set["parts"] as Array).size()
	return total
