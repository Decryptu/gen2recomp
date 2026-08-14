extends SceneTree

## Verifies `GoldSilverIntro`'s art against freshly imported real caches, on all
## three cartridges.
##
## The section walk is what says the one pinned address is right: eleven entries
## in a row landing on their exact sizes, each rounded up to a sixteen-byte
## boundary to reach the next. This sweeps the imported result rather than the
## walk, so a cache built from the wrong offset shows up as a sheet of the wrong
## length or a metatile map naming a metatile its own `.bin` does not hold.
##
## Gold and Silver ship the same art byte for byte, which is checked here rather
## than assumed: the two caches are compared against each other entry by entry.
## Crystal runs `CrystalIntro` instead and is checked for saying so.
##
##   Godot --headless --path . -s res://tools/validate_gs_intro.gd

const GAME_IDS: Array[StringName] = [&"gold", &"silver", &"crystal"]
const MOVIE_GAMES: Array[StringName] = [&"gold", &"silver"]

## The palette runs outside the section, as their colour counts.
const EXPECTED_PALETTES: Dictionary = {
	"magikarp": RomLayout.GS_INTRO_MAGIKARP_PALETTES,
	"shellder_lapras": RomLayout.GS_INTRO_SHELLDER_LAPRAS_PALETTES,
	"jigglypuff_pikachu_bg": 1,
	"jigglypuff_pikachu_ob": 1,
	"starters_transition": 1,
	"pack": 1,
}

## Long enough for the movie, whose own total is pinned below.
const FRAME_CAP: int = 20000

## Census of the real Gold and Silver caches, pinned so a change is loud: the
## frames the jumptable takes to set its exit bit, the frame each scene starts
## on, and how many sounds the movie asks for. The two cartridges run the same
## movie off the same art, so one census covers both.
const EXPECTED_FRAMES: int = 2355
const EXPECTED_SCENE_STARTS: Array[int] = [
	0, 1, 139, 620, 1214, 1294, 1295, 1425, 1681, 1746, 1747, 2009, 2021, 2150,
	2158, 2225, 2290,
]
## `SFX_GS_INTRO_POKEMON_APPEARS` once per starter and the fireball once.
const EXPECTED_SFX: int = 4
## `MUSIC_GS_OPENING`, then `MUSIC_NONE` and `MUSIC_GS_OPENING_2` a frame apart.
const EXPECTED_MUSIC: int = 3

## The water scene asks shadow OAM for more than the forty it holds: Lapras is
## twenty-seven sprites on its own and the magikarp triple six each, so
## `UpdateAnimFrame` drops the last seven rather than growing, the way
## `IntroScene10` drops Pichu's last tile on Crystal. Pinned rather than
## bounded, because the overflow is the finding.
const PEAK_SPRITES: int = 47

var _failures: PackedStringArray = []
## Each cartridge's section, so the two that carry one can be compared.
var _sections: Dictionary = {}


func _initialize() -> void:
	for game_id: StringName in GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		if not MOVIE_GAMES.has(game_id):
			_check(
				not data.has_gs_intro(),
				"%s reports a Gold and Silver intro it does not ship." % game_id
			)
			continue
		if not _check(
			data.has_gs_intro(), "%s carries no Gold and Silver intro art." % game_id
		):
			continue
		_verify_section(game_id, data)
		_verify_metatiles(game_id, data)
		_verify_palettes(game_id, data)
		_run(game_id, data)
	_compare_cartridges()
	_finish()


## The whole movie, frame by frame to `JUMPTABLE_EXIT_F`: the scene starts, the
## sounds and the busiest frame's sprite count. Every sound it names has to
## resolve on the cache as well, since a `PlaySFX` the driver cannot answer is a
## silent scene rather than an error.
func _run(game_id: StringName, data: GameData) -> void:
	var movie: Gen2GoldSilverIntro = Gen2GoldSilverIntro.create(
		data, Gen2SplashScreen._sine_table(data)
	)
	var page: Gen2GoldSilverIntroPage = Gen2GoldSilverIntroPage.from_data(data)
	_check(page != null, "%s: the intro page will not build." % game_id)
	var starts: Array[int] = [0]
	var scene: int = 0
	var sfx: int = 0
	var music: int = 0
	var most: int = 0
	while not movie.finished() and movie.frame() < FRAME_CAP:
		for event: Dictionary in movie.advance_frame():
			match StringName(event.get("type", &"")):
				&"play_sfx":
					sfx += 1
					_check(
						not data.world_audio(&"sfx", int(event["sfx"])).is_empty(),
						"%s: intro sfx %d resolves to no record." % [
							game_id, int(event["sfx"]),
						]
					)
				&"play_music":
					music += 1
					_check(
						not data.world_audio(&"music", int(event["music"])).is_empty(),
						"%s: intro music %d resolves to no record." % [
							game_id, int(event["music"]),
						]
					)
		if movie.scene() != scene:
			scene = movie.scene()
			starts.append(movie.frame())
		most = maxi(most, _sprite_count(movie))
	_check(movie.finished(), "%s: the intro never set its exit bit." % game_id)
	_check(
		movie.frame() == EXPECTED_FRAMES,
		"%s: the intro ran %d frames, not the pinned %d." % [
			game_id, movie.frame(), EXPECTED_FRAMES,
		]
	)
	_check(
		starts == EXPECTED_SCENE_STARTS,
		"%s: the intro scenes start on %s, not the pinned starts." % [game_id, starts]
	)
	_check(
		sfx == EXPECTED_SFX and music == EXPECTED_MUSIC,
		"%s: the intro asked for %d effects and %d songs, not %d and %d." % [
			game_id, sfx, music, EXPECTED_SFX, EXPECTED_MUSIC,
		]
	)
	_check(
		most == PEAK_SPRITES,
		"%s: the intro's busiest frame asked for %d sprites, not the pinned %d." % [
			game_id, most, PEAK_SPRITES,
		]
	)


## How many shadow-OAM entries this frame's structs add up to.
func _sprite_count(movie: Gen2GoldSilverIntro) -> int:
	var total: int = 0
	for sprite: Dictionary in movie.sprites():
		var index: int = int(sprite["set"])
		if index < 0 or index >= Gen2GoldSilverIntroPage.OAM_SETS.size():
			continue
		total += ((Gen2GoldSilverIntroPage.OAM_SETS[index] as Dictionary)["parts"]
			as Array).size()
	return total


## Every entry of the section, at the size the routine that loads it asks VRAM
## for. A tile strip is one index per pixel; a `.tilemap` or `.bin` is the file's
## own length, since pret checks those in as binary.
func _verify_section(game_id: StringName, data: GameData) -> void:
	var section: Dictionary = {}
	for row: Array in RomLayout.GS_INTRO_SECTION:
		var name: String = String(row[0])
		var raw: PackedByteArray = data.gs_intro_map(name)
		var wanted: int = int(row[2]) if String(row[1]) == "raw_bytes" \
			else int(row[2]) * Gen2Tiles.TILE_WIDTH * Gen2Tiles.TILE_HEIGHT
		_check(
			raw.size() == wanted,
			"%s: gs intro entry %s is %d bytes, not %d." % [
				game_id, name, raw.size(), wanted,
			]
		)
		section[name] = raw
	_sections[game_id] = section


## `Intro_Draw2x2Tiles` looks a map byte up in the `.bin` four bytes at a time,
## so no metatile a map names may sit past the end of its own table. This is the
## check that pairs the two halves: a `.tilemap` read at the wrong offset names
## metatiles its `.bin` does not have.
func _verify_metatiles(game_id: StringName, data: GameData) -> void:
	for name: String in ["water", "grass"]:
		var map: PackedByteArray = data.gs_intro_map("%s_tilemap" % name)
		var meta: PackedByteArray = data.gs_intro_map("%s_meta" % name)
		var metatiles: int = meta.size() / RomLayout.GS_INTRO_META_BYTES
		if not _check(
			metatiles > 0, "%s: the %s metatile table is empty." % [game_id, name]
		):
			continue
		var worst: int = 0
		for cell: int in map.size():
			worst = maxi(worst, int(map[cell]))
		_check(
			worst < metatiles,
			"%s: the %s map names metatile %d, past its own %d." % [
				game_id, name, worst, metatiles,
			]
		)
		# `Intro_DrawBackground` draws sixteen metatile rows of sixteen, so a map
		# has to hold at least one screenful from wherever the scene starts in it.
		var rows: int = map.size() / RomLayout.GS_INTRO_META_COLUMNS
		var first: int = RomLayout.GS_INTRO_WATER_FIRST_ROW if name == "water" else 0
		_check(
			rows >= first + RomLayout.GS_INTRO_META_COLUMNS,
			"%s: the %s map is %d metatile rows, too few to draw from row %d." % [
				game_id, name, rows, first,
			]
		)


func _verify_palettes(game_id: StringName, data: GameData) -> void:
	for name: String in EXPECTED_PALETTES:
		var wanted: int = int(EXPECTED_PALETTES[name]) * RomLayout.INTRO_PALETTE_COLORS
		_check(
			data.gs_intro_palette(name).size() == wanted,
			"%s: gs intro palette %s is %d colours, not %d." % [
				game_id, name, data.gs_intro_palette(name).size(), wanted,
			]
		)


## Gold and Silver's intro art is the same bytes at two addresses, so each
## cartridge's section is the other's reference. A walk that started one entry
## wrong on one of them shows up here even when both are self-consistent.
func _compare_cartridges() -> void:
	if not (_sections.has(&"gold") and _sections.has(&"silver")):
		return
	var gold: Dictionary = _sections[&"gold"]
	var silver: Dictionary = _sections[&"silver"]
	for row: Array in RomLayout.GS_INTRO_SECTION:
		var name: String = String(row[0])
		_check(
			PackedByteArray(gold[name]) == PackedByteArray(silver[name]),
			"gs intro entry %s differs between Gold and Silver." % name
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
			"PASS gs intro: the section, the metatile maps, the palettes and every "
			+ "scene verified."
		)
		quit(0)
		return
	for message: String in _failures:
		print("FAIL %s" % message)
	quit(1)
