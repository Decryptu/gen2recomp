class_name Gen2IntroMovie
extends RefCounted

## `CrystalIntro` (engine/movie/intro.asm): the movie between the GameFreak logo
## and the title screen.
##
## Twenty-eight scenes behind one jumptable, stepped once per hardware frame.
## Half of them are setup: they load a graphics sheet, a 32x32 BG map and its
## attribute plane, copy a palette run into `wBGPals1` and `wBGPals2`, and call
## `NextIntroScene`. The other half animate for a fixed number of frames by
## writing the palettes, `hSCX`, `hSCY`, `wLYOverrides` and a handful of sprite
## animation structs, then hand on.
##
## This owns all of that state; [Gen2IntroMoviePage] turns it into pixels. The
## split is the credits': a per-frame jumptable, a tilemap the state machine
## owns, and a page that only turns tile numbers into colours.
##
## Crystal only. Gold and Silver's `GoldSilverIntro` is a different movie and is
## not built.

## `wBGPals2` and the `wOBPals2` behind it, which is what the screen shows.
##
## Every scene's `ld bc, 16 palettes` runs off the end of the background
## buffer and into the object one, which is where the sprites get their colours:
## the Unown's purple, Pichu's yellow and Wooper's blue are all in the second
## half of a run whose first half is a scene's backgrounds.
const BG_PALETTES: int = 8
const PALETTES: int = RomLayout.INTRO_PALETTES
const PALETTE_COLORS: int = RomLayout.INTRO_PALETTE_COLORS
## `ClearPalettes` fills both buffers with $ffff rather than blanking them.
const WHITE: int = 0xFFFF

## `SCREEN_WIDTH`/`SCREEN_HEIGHT` and the BG map behind them.
const COLUMNS: int = 20
const ROWS: int = 18
const MAP_COLUMNS: int = RomLayout.INTRO_MAP_COLUMNS
const MAP_ROWS: int = RomLayout.INTRO_MAP_ROWS
const SCREEN_HEIGHT_PX: int = 144

## The sound effects the movie asks for, as their `SFX_*` numbers.
const SFX_INTRO_UNOWN_1: int = 0xB6
const SFX_INTRO_UNOWN_2: int = 0xB8
const SFX_INTRO_UNOWN_3: int = 0xB9
const SFX_INTRO_SUICUNE_2: int = 0xB7
const SFX_INTRO_SUICUNE_3: int = 0xBA
const SFX_INTRO_SUICUNE_4: int = 0xBB
const SFX_INTRO_WHOOSH: int = 0xBC
const SFX_INTRO_PICHU: int = 0xBD
## `MUSIC_CRYSTAL_OPENING`, started by `IntroScene13` rather than at the top.
const MUSIC_CRYSTAL_OPENING: int = 0x25

## The six `SpriteAnimObjects` rows the movie spawns, as (frameset, function).
const OBJ_INTRO_SUICUNE: StringName = &"suicune"
const OBJ_INTRO_PICHU: StringName = &"pichu"
const OBJ_INTRO_WOOPER: StringName = &"wooper"
const OBJ_INTRO_UNOWN: StringName = &"unown"
const OBJ_INTRO_UNOWN_F: StringName = &"unown_f"
const OBJ_INTRO_SUICUNE_AWAY: StringName = &"suicune_away"

## The framesets, as (OAM set, duration, attributes) plus how the run ends.
## `oamframe X, n` lasts n + 1 frames; `oamend` repeats its last entry forever,
## `oamdelete` takes the struct away and `oamrestart` goes round again.
const FRAMESET_END: StringName = &"end"
const FRAMESET_DELETE: StringName = &"delete"
const FRAMESET_RESTART: StringName = &"restart"
const FRAMESET_WAIT: StringName = &"wait"

## `B_OAM_XFLIP` and `B_OAM_YFLIP` on a frameset entry, which flip each tile
## where it stands rather than mirroring the square.
const FLIP_X: int = 1
const FLIP_Y: int = 2

const FRAMESETS: Dictionary = {
	&"intro_suicune": {
		"frames": [[0, 3, 0], [1, 3, 0], [2, 3, 0], [3, 3, 0]], "end": FRAMESET_RESTART,
	},
	&"intro_suicune_2": {"frames": [[3, 3, 0], [0, 7, 0]], "end": FRAMESET_END},
	&"intro_pichu": {
		"frames": [[4, 32, 0], [5, 7, 0], [6, 7, 0]], "end": FRAMESET_END,
	},
	&"intro_wooper": {"frames": [[7, 3, 0]], "end": FRAMESET_END},
	&"intro_unown_1": {
		"frames": [[8, 3, 0], [9, 3, 0], [10, 7, 0]], "end": FRAMESET_DELETE,
	},
	&"intro_unown_2": {
		"frames": [[8, 3, FLIP_X], [9, 3, FLIP_X], [10, 7, FLIP_X]],
		"end": FRAMESET_DELETE,
	},
	&"intro_unown_3": {
		"frames": [[8, 3, FLIP_Y], [9, 3, FLIP_Y], [10, 7, FLIP_Y]],
		"end": FRAMESET_DELETE,
	},
	&"intro_unown_4": {
		"frames": [
			[8, 3, FLIP_X | FLIP_Y], [9, 3, FLIP_X | FLIP_Y], [10, 7, FLIP_X | FLIP_Y],
		],
		"end": FRAMESET_DELETE,
	},
	&"intro_unown_f": {"frames": [], "end": FRAMESET_WAIT},
	&"intro_unown_f_2": {
		"frames": [[11, 3, 0], [12, 3, 0], [13, 3, 0], [14, 7, 0], [15, 7, 0]],
		"end": FRAMESET_END,
	},
	&"intro_suicune_away": {"frames": [[16, 3, 0]], "end": FRAMESET_END},
}

## The `SpriteAnimObjects` rows: the frameset a struct starts on and the
## `SPRITE_ANIM_FUNC_*` that moves it. Every one of them takes
## `SPRITE_ANIM_DICT_DEFAULT`, so the tile a struct draws from is whatever the
## scene wrote into `wSpriteAnimDict`'s first value.
const OBJECTS: Dictionary = {
	OBJ_INTRO_SUICUNE: {"frameset": &"intro_suicune", "func": &"suicune"},
	OBJ_INTRO_PICHU: {"frameset": &"intro_pichu", "func": &"pichu_wooper"},
	OBJ_INTRO_WOOPER: {"frameset": &"intro_wooper", "func": &"pichu_wooper"},
	OBJ_INTRO_UNOWN: {"frameset": &"intro_unown_1", "func": &"unown"},
	OBJ_INTRO_UNOWN_F: {"frameset": &"intro_unown_f", "func": &"unown_f"},
	OBJ_INTRO_SUICUNE_AWAY: {
		"frameset": &"intro_suicune_away", "func": &"suicune_away",
	},
}

## `CrystalIntro_InitUnownAnim`'s four structs, as (VAR1, frameset). VAR1 is the
## angle `SpriteAnimFunc_IntroUnown` reads its sine and cosine at, so the four
## fly out along four directions while the amplitude grows.
const UNOWN_BURST: Array[Array] = [
	[0x08, &"intro_unown_4"], [0x18, &"intro_unown_3"],
	[0x28, &"intro_unown_1"], [0x38, &"intro_unown_2"],
]

## `IntroScene12`'s `.UnownSounds`, as (frame counter, sfx).
const UNOWN_SOUNDS: Array[Array] = [
	[0x00, SFX_INTRO_UNOWN_3], [0x20, SFX_INTRO_UNOWN_2], [0x40, SFX_INTRO_UNOWN_1],
	[0x60, SFX_INTRO_UNOWN_2], [0x80, SFX_INTRO_UNOWN_3], [0x90, SFX_INTRO_UNOWN_2],
	[0xA0, SFX_INTRO_UNOWN_1], [0xB0, SFX_INTRO_UNOWN_2],
]

## What each setup scene loads, keyed by its scene index. `bg` is the sheet BG
## tile numbers below $80 read from, `bg_first` how far into it that half starts,
## and `bg_high` the sheet $80 and up reads from; `obj` is the sheet a sprite
## tile reads from and `obj_bank1` the one an `OAM_BANK1` sprite does. `map` and
## `attr` name the 32x32 BG maps.
##
## The names are `RomLayout.INTRO_SECTION`'s. A missing key keeps what the scene
## before it left in that part of VRAM, which is what the source's own
## `Intro_DecompressRequest2bpp_*` calls do.
const SCENE_VRAM: Dictionary = {
	0: {
		"bg": "unowns", "map": "unown_a_map", "attr": "unown_a_attr", "obj": "pulse",
	},
	2: {"bg": "background", "map": "background_map", "attr": "background_attr"},
	4: {
		"bg": "unowns", "map": "unown_hi_map", "attr": "unown_hi_attr", "obj": "pulse",
	},
	6: {
		"bg": "background", "map": "background_map", "attr": "background_attr",
		"obj": "suicune_run", "obj_bank1": "pichu_wooper",
	},
	10: {"bg": "unowns", "map": "unowns_map", "attr": "unowns_attr"},
	12: {
		"bg": "background", "map": "background_map", "attr": "background_attr",
		"obj": "suicune_run",
	},
	14: {
		"bg": "suicune_jump", "map": "suicune_jump_map", "attr": "suicune_jump_attr",
		"obj": "unown_back",
	},
	# `Intro_DecompressRequest2bpp_255Tiles` from `vTiles1` runs 255 tiles past
	# the end of that bank, so the close-up's first 128 land where a BG tile
	# number $80 and up reads and the rest in `vTiles2`, where one below $80
	# does. One sheet, both halves of the window, which is why its own map names
	# thirty-three tiles below $80.
	16: {
		"bg": "suicune_close", "bg_first": 128, "bg_high": "suicune_close",
		"map": "suicune_close_map", "attr": "suicune_close_attr",
	},
	18: {
		"bg": "suicune_back", "bg_high": "unowns", "map": "suicune_back_map",
		"attr": "suicune_back_attr",
	},
	25: {
		"bg": "crystal_unowns", "map": "crystal_unowns_map",
		"attr": "crystal_unowns_attr",
	},
}

## The palette run each setup scene copies into both buffers.
const SCENE_PALETTE: Dictionary = {
	0: "unowns_palette", 2: "background_palette", 4: "unowns_palette",
	6: "background_palette", 10: "unowns_palette", 12: "background_palette",
	14: "suicune_palette", 16: "suicune_close_palette", 18: "suicune_palette",
	25: "crystal_unowns_palette",
}

## `IntroScene26`, the one setup scene whose palette clear is `ClearBGPalettes`.
const SCENE_CRYSTAL_UNOWNS: int = 25

## The tiles each setup scene's `Intro_DecompressRequest2bpp_*` calls ask for, in
## order. `Request2bpp` is what makes a setup scene expensive: it hands VBlank
## `TILES_PER_CYCLE` tiles at a time and spends a `DelayFrame` on each, so a
## 128-tile sheet costs seventeen frames and the 255-tile one thirty-two. Half
## the movie's length is these waits.
const SCENE_REQUESTS: Dictionary = {
	0: [64, 128, 128, 64], 2: [64, 128, 64], 4: [64, 128, 128, 64],
	6: [64, 128, 255, 128, 64], 10: [64, 128, 64], 12: [64, 255, 128, 64],
	14: [64, 128, 128, 64], 16: [64, 255, 64], 18: [64, 128, 128, 64],
	25: [64, 128, 64],
}
## `TILES_PER_CYCLE` (home/gfx.asm).
const TILES_PER_CYCLE: int = 8
## `ClearTilemap`'s `WaitBGMap` tail, which every setup scene pays.
const CLEAR_TILEMAP_FRAMES: int = 4

## `Intro_RustleGrass`'s `.RustlingGrassPointers`, four tiles at `vTiles2 tile
## $09` swapped every four frames for the first thirty-six of `IntroScene10`.
const GRASS_FRAMES: Array[String] = ["grass_1", "grass_2", "grass_3", "grass_2"]
const GRASS_RUSTLE_FRAMES: int = 36

var _data: GameData = null
var _sine: Gen2BattleAnimData = null

## `wJumptableIndex` and its `JUMPTABLE_EXIT_F`.
var _scene: int = 0
var _exit: bool = false
## `wIntroSceneFrameCounter` and `wIntroSceneTimer`, which share their addresses
## with the slot machine's bytes; see [method _sprite_unown_f].
var _counter: int = 0
var _timer: int = 0

var _scx: int = 0
var _scy: int = 0
## `wLYOverrides` under `hLCDCPointer` = LOW(rSCX): one `hSCX` per scanline. Off
## when [member _ly_active] is false, which is `hLCDCPointer` zero.
var _ly: PackedByteArray = PackedByteArray()
var _ly_active: bool = false

## `wBGPals2`, eight palettes of four packed colours.
var _palettes: PackedInt32Array = PackedInt32Array()
## `wSpriteAnimDict`'s first value, the tile a `SPRITE_ANIM_DICT_DEFAULT` struct
## counts its OAM sets from.
var _sprite_vtile: int = 0
var _global_x_offset: int = 0

## Which sheet and map each part of VRAM currently holds, built up by the setup
## scenes out of [constant SCENE_VRAM].
var _vram: Dictionary = {}
## `wTilemap`, which only `Intro_LoadTilemap` fills and only
## `Intro_ColoredSuicuneFrameSwap` reads. Empty until a scene loads it.
var _tilemap: PackedByteArray = PackedByteArray()
## The attribute plane `IntroScene9` writes over the loaded one, or empty.
var _attr_override: PackedByteArray = PackedByteArray()
var _grass_frame: int = 0

var _actors: Array[Dictionary] = []
## Frames a scene spends inside `DelayFrames`, during which neither the
## jumptable nor `PlaySpriteAnimations` runs.
var _delay: int = 0
var _frame: int = 0
var _events: Array[Dictionary] = []


## [param sine] is `BattleAnimSineWave`, which every motion callback here scales.
## Without one the sprites sit still and the frame counts do not move, so a
## caller with no animation layer still spends the right frames.
static func create(data: GameData, sine: Gen2BattleAnimData = null) -> Gen2IntroMovie:
	var out := Gen2IntroMovie.new()
	out._data = data
	out._sine = sine
	out._ly.resize(SCREEN_HEIGHT_PX)
	out._palettes.resize(PALETTES * PALETTE_COLORS)
	return out


## Whether [param data] carries the art the movie draws. A cache without it is
## the caller's cue to skip the phase rather than to run it blank.
static func available(data: GameData) -> bool:
	return data != null and data.has_intro_movie()


func scene() -> int:
	return _scene


func finished() -> bool:
	return _exit


func frame() -> int:
	return _frame


func counter() -> int:
	return _counter


## `wIntroSceneTimer`, which `AnimSeq_GSTitleTrail` reads on Gold and Silver and
## `CrystalIntro_UnownFade` writes here.
func timer() -> int:
	return _timer


func scroll() -> Vector2i:
	return Vector2i(_scx, _scy)


## The `hSCX` for one scanline, which is `wLYOverrides` while `hLCDCPointer`
## points at rSCX and plain `hSCX` otherwise.
func scroll_x_at(line: int) -> int:
	if not _ly_active or line < 0 or line >= _ly.size():
		return _scx
	return _ly[line]


## One background palette, as colours a page can draw with.
func palette(index: int) -> PackedColorArray:
	return _palette_at(index)


## One object palette, which is the same run's second half.
func object_palette(index: int) -> PackedColorArray:
	return _palette_at(BG_PALETTES + index)


func _palette_at(index: int) -> PackedColorArray:
	var out := PackedColorArray()
	if index < 0 or index >= PALETTES:
		return out
	for colour: int in PALETTE_COLORS:
		out.append(Gen2Palette.from_packed(_palettes[index * PALETTE_COLORS + colour]))
	return out


## Which sheet [param part] of VRAM holds: `bg`, `bg_high`, `obj` or
## `obj_bank1`. Empty before a scene has loaded one.
func sheet(part: String) -> String:
	return String(_vram.get(part, ""))


## How far into that sheet the half starts, which is only ever the close-up's
## own 255-tile load spilling out of `vTiles1`.
func sheet_first_tile(part: String) -> int:
	return int(_vram.get("%s_first" % part, 0))


## The tile the four rustling-grass tiles at $09 currently show, as a sheet name.
func grass_sheet() -> String:
	return GRASS_FRAMES[_grass_frame]


## The 32x32 BG map and its attribute plane, as the cache holds them.
func bg_map() -> PackedByteArray:
	return _data.intro_map(String(_vram.get("map", ""))) if _data != null \
		else PackedByteArray()


func bg_attr() -> PackedByteArray:
	if not _attr_override.is_empty():
		return _attr_override
	return _data.intro_map(String(_vram.get("attr", ""))) if _data != null \
		else PackedByteArray()


## `wTilemap`, which `Intro_ColoredSuicuneFrameSwap` rewrites in place. Empty
## outside the two scenes that load it, and a page draws the BG map then.
func screen_tilemap() -> PackedByteArray:
	return _tilemap


## Every live sprite-anim struct as the shadow OAM it produces, in struct order,
## which is the z-order: `_InitSpriteAnimStruct` takes the first free slot and
## `PlaySpriteAnimations` walks them in order.
func sprites() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for actor: Dictionary in _actors:
		var entry: Array = _actor_frame(actor)
		if entry.is_empty():
			continue
		out.append({
			"at": Vector2i(
				(int(actor["x"]) + int(actor["x_offset"]) + _global_x_offset) & 0xFF,
				(int(actor["y"]) + int(actor["y_offset"])) & 0xFF,
			),
			"set": int(entry[0]),
			"flip_x": bool(int(entry[2]) & FLIP_X),
			"flip_y": bool(int(entry[2]) & FLIP_Y),
			"vtile": int(actor["vtile"]),
			"bank1": StringName(actor["object"]) in [OBJ_INTRO_PICHU, OBJ_INTRO_WOOPER],
		})
	return out


func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = _events.duplicate(true)
	_events.clear()
	return out


## One `.loop` pass: `IntroSceneJumper` and then `PlaySpriteAnimations`, in the
## order Crystal's loop calls them. A scene that spent `DelayFrames` inside its
## own body holds both off until the debt is paid.
func advance_frame() -> Array[Dictionary]:
	if _exit:
		return drain_events()
	_frame += 1
	if _delay > 0:
		_delay -= 1
		return drain_events()
	_run_scene()
	_run_sprites()
	return drain_events()


## The button `.ShutOffMusic` reads: any of A, B, START or SELECT ends the whole
## movie and stops the music, which is the only skip it has.
func cancel() -> bool:
	if _exit:
		return false
	_exit = true
	_emit(&"play_music", {"music": 0})
	return true


func _run_scene() -> void:
	match _scene:
		0:
			_setup_scene()
		1:
			_scene_unown_a()
		2:
			_setup_scene()
			_reset_ly_overrides()
		3:
			_scene_perspective_scroll()
		4:
			_setup_scene()
			_ly_active = false
		5:
			_scene_unown_hi()
		6:
			_setup_scene()
			_reset_ly_overrides()
			_spawn(OBJ_INTRO_SUICUNE, Vector2i(27 * 8 + 0, 13 * 8 + 4))
			_global_x_offset = 0xF0
		7:
			_scene_suicune_runs_in()
		8:
			_scene_attribute_bands()
		9:
			_scene_pichu_and_wooper()
		10:
			_setup_scene()
			_ly_active = false
		11:
			_scene_many_unown()
		12:
			_setup_scene()
			_spawn(OBJ_INTRO_SUICUNE, Vector2i(11 * 8 + 0, 13 * 8 + 4))
			_emit(&"play_music", {"music": MUSIC_CRYSTAL_OPENING})
			_global_x_offset = 0
		13:
			_scene_suicune_jumps()
		14:
			_setup_scene()
			_load_tilemap()
			_scy = SCREEN_HEIGHT_PX
			_spawn(OBJ_INTRO_UNOWN_F, Vector2i(5 * 8, 8 * 8))
			_spawn(OBJ_INTRO_SUICUNE_AWAY, Vector2i(0, 12 * 8))
		15:
			_scene_suicune_face()
		16:
			_setup_scene()
		17:
			_scene_suicune_close()
		18:
			_setup_scene()
			_load_tilemap()
			# `ld a, -5 * TILE_WIDTH`, which is a byte and stays one.
			_scy = (-5 * 8) & 0xFF
			# The grass tile parked at `vTiles1 tile $7f`, which is what the
			# struct's own OAM set counts from.
			_sprite_vtile = 0x7F
			_spawn(OBJ_INTRO_SUICUNE_AWAY, Vector2i(0, 12 * 8))
		19:
			_scene_suicune_away()
		20:
			_colored_suicune_frame_swap()
			_delay = 3
			_counter = 0
			_timer = 0
			_next_scene()
		21:
			_scene_deinit_sprites()
		22:
			_counter = 0
			_next_scene()
		23:
			_scene_fade_to_white()
		24:
			_scene_wait()
		25:
			_setup_scene()
		26:
			_scene_spell_crystal()
		27:
			_scene_end()


## The half of a setup scene every one of them shares: clear the palettes, the
## sprites and the tilemap, load this scene's own VRAM and palette run, put the
## scroll back at the origin and hand on.
##
## `Intro_ClearBGPals` spends two `DelayFrame`s of its own, which is why a setup
## scene is not free.
func _setup_scene() -> void:
	var vram: Dictionary = SCENE_VRAM.get(_scene, {})
	for part: String in vram:
		_vram[part] = vram[part]
	# A sheet reloaded without an offset starts at its own first tile again.
	for part: String in ["bg", "bg_high"]:
		if vram.has(part) and not vram.has("%s_first" % part):
			_vram.erase("%s_first" % part)
	_actors.clear()
	# `wGlobalAnimXOffset` lives inside `wSpriteAnimData`, so `ClearSpriteAnims`
	# takes it with the structs: the offset the jump scene walked to $80 does not
	# survive into the scene after it.
	_global_x_offset = 0
	_tilemap = PackedByteArray()
	_attr_override = PackedByteArray()
	_sprite_vtile = 0
	_grass_frame = 0
	_scx = 0
	_scy = 0
	var name: String = String(SCENE_PALETTE.get(_scene, ""))
	if not name.is_empty() and _data != null:
		_load_palettes(name)
	# `Intro_ClearBGPals` spends two `DelayFrame`s. `IntroScene26` is the one
	# setup scene that calls `ClearBGPalettes` instead, whose `WaitBGMap` tail
	# spends four. `ClearTilemap` then spends four of its own, and every sheet
	# the scene asks for is a `Request2bpp` wait on top.
	_delay = CLEAR_TILEMAP_FRAMES + (4 if _scene == SCENE_CRYSTAL_UNOWNS else 2)
	for tiles: int in SCENE_REQUESTS.get(_scene, []):
		# `.cycle` spends a frame per `TILES_PER_CYCLE`, and the remainder below
		# one cycle spends a last one whether or not there is anything left.
		_delay += tiles / TILES_PER_CYCLE + 1
	_counter = 0
	_timer = 0
	_next_scene()


func _load_palettes(name: String) -> void:
	var packed: PackedInt32Array = _packed(name)
	for index: int in mini(packed.size(), _palettes.size()):
		_palettes[index] = packed[index]


## The cache holds a palette run as colours; the movie's own fades work on the
## cartridge's packed 15-bit values, so they are read back as those.
func _packed(name: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _data == null:
		return out
	for colour: Color in _data.intro_palette(name):
		out.append(
			int(round(colour.r * 31.0))
			| (int(round(colour.g * 31.0)) << 5)
			| (int(round(colour.b * 31.0)) << 10)
		)
	return out


func _next_scene() -> void:
	_scene += 1


## `IntroScene2`: the first Unown fades in, pulses and fades out over $80
## frames, with the burst spawned two thirds of the way through.
func _scene_unown_a() -> void:
	var value: int = _counter
	_counter = (_counter + 1) & 0xFF
	if value >= 0x80:
		_next_scene()
		return
	if value == 0x60:
		_init_unown_burst(Vector2i(11 * 8, 11 * 8))
		_emit(&"play_sfx", {"sfx": SFX_INTRO_UNOWN_1})
	_timer = value
	_unown_fade(0)


## `IntroScene6`: two more Unown, the second on the palette the first leaves.
func _scene_unown_hi() -> void:
	var value: int = _counter
	_counter = (_counter + 1) & 0xFF
	if value >= 0x80:
		_next_scene()
		return
	if value == 0x60:
		_init_unown_burst(Vector2i(6 * 8, 14 * 8))
		_emit(&"play_sfx", {"sfx": SFX_INTRO_UNOWN_1})
		_timer = value
		_unown_fade(1)
		return
	if value >= 0x40:
		_timer = value
		_unown_fade(1)
		return
	if value == 0x20:
		_init_unown_burst(Vector2i(15 * 8, 7 * 8))
		_emit(&"play_sfx", {"sfx": SFX_INTRO_UNOWN_2})
	_timer = value
	_unown_fade(0)


## `IntroScene4`: `Intro_PerspectiveScrollBG` for $80 frames.
func _scene_perspective_scroll() -> void:
	_perspective_scroll()
	if _counter == 0x80:
		_next_scene()
		return
	_counter = (_counter + 1) & 0xFF


## `IntroScene8`: the panorama scrolls for $40 frames, then Suicune runs in from
## the right as `wGlobalAnimXOffset` falls to zero.
func _scene_suicune_runs_in() -> void:
	var value: int = _counter
	_counter = (_counter + 1) & 0xFF
	if value < 0x40:
		_perspective_scroll()
		return
	if value == 0x40:
		_emit(&"play_sfx", {"sfx": SFX_INTRO_SUICUNE_3})
	if _global_x_offset == 0:
		_emit(&"play_sfx", {"sfx": SFX_INTRO_SUICUNE_2})
		_actors.clear()
		_next_scene()
		return
	_global_x_offset = (_global_x_offset - 8) & 0xFF


## `IntroScene9`: twelve rows of palette 1, three of 2 and three of 3, pushed
## twice with `hBGMapAddress` twelve tiles apart so the whole 32-wide map is
## covered rather than the twenty visible columns. Six `DelayFrame`s in all.
func _scene_attribute_bands() -> void:
	_ly_active = false
	var attr := PackedByteArray()
	attr.resize(RomLayout.INTRO_MAP_BYTES)
	for row: int in MAP_ROWS:
		var value: int = 1 if row < 12 else (2 if row < 15 else 3)
		for column: int in MAP_COLUMNS:
			attr[row * MAP_COLUMNS + column] = value
	_attr_override = attr
	_delay = 6
	_global_x_offset = 0
	_counter = 0
	_next_scene()


## `IntroScene10`: the grass rustles while Wooper and then Pichu hop in.
func _scene_pichu_and_wooper() -> void:
	_rustle_grass()
	var value: int = _counter
	_counter = (_counter + 1) & 0xFF
	match value:
		0xC0:
			_next_scene()
		0x20:
			_spawn(OBJ_INTRO_WOOPER, Vector2i(6 * 8, 22 * 8))
			_emit(&"play_sfx", {"sfx": SFX_INTRO_PICHU})
		0x40:
			_spawn(OBJ_INTRO_PICHU, Vector2i(16 * 8, 21 * 8 + 1))
			_emit(&"play_sfx", {"sfx": SFX_INTRO_PICHU})


## `IntroScene12`: the whole screen of Unown, fading twice as fast over the
## second half, with eight sound effects along the way.
func _scene_many_unown() -> void:
	_play_unown_sound()
	var value: int = _counter
	_counter = (_counter + 1) & 0xFF
	if value >= 0xC0:
		_next_scene()
		return
	if value >= 0x80:
		_timer = ((value & 0x0F) << 2) & 0xFF
		_unown_fade(_swap_nybbles((value & 0x70) | 0x40))
		return
	_timer = ((value & 0x1F) << 1) & 0xFF
	_unown_fade(_swap_nybbles((value & 0xE0) >> 1))


func _play_unown_sound() -> void:
	for row: Array in UNOWN_SOUNDS:
		if int(row[0]) == _counter:
			_emit(&"play_sfx", {"sfx": int(row[1]), "channels_off": true})
			return


## `IntroScene14`: the background scrolls ten pixels a frame while Suicune runs,
## jumps at $60 and leaves.
func _scene_suicune_jumps() -> void:
	_scx = (_scx - 10) & 0xFF
	var value: int = _counter
	_counter = (_counter + 1) & 0xFF
	if value == 0x80:
		_next_scene()
		return
	if value == 0x60:
		_emit(&"play_sfx", {"sfx": SFX_INTRO_SUICUNE_4})
	if value >= 0x60:
		_timer = 1
		if _global_x_offset < 0x88:
			_actors.clear()
			return
		_global_x_offset = (_global_x_offset - 8) & 0xFF
		return
	if value >= 0x40:
		_global_x_offset = (_global_x_offset - 2) & 0xFF


## `IntroScene16`: Suicune's face rises into frame while an Unown appears in
## front of it.
func _scene_suicune_face() -> void:
	var value: int = _counter
	_counter = (_counter + 1) & 0xFF
	if value >= 0x80:
		_next_scene()
		return
	_animate_suicune_frame_swap()
	if _scy == 0:
		return
	_scy = (_scy + 8) & 0xFF


## `Intro_Scene16_AnimateSuicune`: the two-frame colour swap every fourth frame.
func _animate_suicune_frame_swap() -> void:
	if _counter & 0x03 == 0:
		_colored_suicune_frame_swap()


## `IntroScene18`: the close-up pans right eight pixels a frame until $60.
func _scene_suicune_close() -> void:
	var value: int = _counter
	_counter = (_counter + 1) & 0xFF
	if value >= 0x60:
		_next_scene()
		return
	if _scx == 0x60:
		return
	_scx = (_scx + 8) & 0xFF


## `IntroScene20`: Suicune runs away up the screen and Unown appear behind it.
func _scene_suicune_away() -> void:
	var value: int = _counter
	_counter = (_counter + 1) & 0xFF
	if value >= 0x98:
		_next_scene()
		return
	if value >= 0x58:
		return
	if value >= 0x40:
		var step: int = value - 0x18
		if step & 0x03 != 0x03:
			return
		_timer = (step & 0x1C) >> 2
		_appear_unown(0)
		return
	if value >= 0x28:
		return
	_scy = (_scy + 1) & 0xFF


## `IntroScene22`: eight frames, then the sprites go.
func _scene_deinit_sprites() -> void:
	var value: int = _counter
	_counter = (_counter + 1) & 0xFF
	if value < 0x08:
		return
	_actors.clear()
	_next_scene()


## `IntroScene24`: `.FadePals` over all eight palettes, one step every fourth
## frame for $20 frames.
func _scene_fade_to_white() -> void:
	var value: int = _counter
	_counter = (_counter + 1) & 0xFF
	if value >= 0x20:
		_counter = 0x40
		_next_scene()
		return
	if value & 0x03 != 0:
		return
	_apply_palette_fade(((value & 0x1C) << 1) & 0xFF)


## `IntroScene25`: $40 frames of nothing.
func _scene_wait() -> void:
	_counter = (_counter - 1) & 0xFF
	if _counter == 0:
		_next_scene()


## `IntroScene27`: C R Y S T A L spelled out in Unown, one palette pair fading
## per sixteen frames.
func _scene_spell_crystal() -> void:
	_timer = (_timer + 1) & 0xFF
	var value: int = _counter
	_counter = (_counter + 1) & 0xFF
	if value >= 0x80:
		_next_scene()
		_counter = 0x80
		return
	_timer = value & 0x0F
	_fade_unown_word_pals(_swap_nybbles(value & 0x70))


## `IntroScene28`: count $80 down, whoosh at 8, clear the palettes at $18, and
## set the exit bit when it runs out.
func _scene_end() -> void:
	if _counter == 0:
		_exit = true
		return
	var value: int = _counter
	_counter = (_counter - 1) & 0xFF
	if value == 0x18:
		# `ClearBGPalettes` makes every palette white, both halves.
		for index: int in _palettes.size():
			_palettes[index] = WHITE
		return
	if value == 0x08:
		_emit(&"play_sfx", {"sfx": SFX_INTRO_WHOOSH})


## `Intro_PerspectiveScrollBG`: the trees scroll one pixel every other frame and
## the grass two every frame, which is what makes the ground look nearer.
func _perspective_scroll() -> void:
	if _counter & 0x01 != 0:
		var trees: int = (_ly[0] + 1) & 0xFF
		for line: int in 0x5F:
			_ly[line] = trees
	var grass: int = (_ly[0x5F] + 2) & 0xFF
	for offset: int in 0x31:
		_ly[0x5F + offset] = grass
	_scx = _ly[0]


func _reset_ly_overrides() -> void:
	for line: int in _ly.size():
		_ly[line] = 0
	_ly_active = true


## `Intro_RustleGrass`: four tiles at `vTiles2 tile $09` cycle through three of
## the grass strips for the scene's first thirty-six frames.
func _rustle_grass() -> void:
	if _counter >= GRASS_RUSTLE_FRAMES:
		return
	_grass_frame = (_counter & 0x0C) >> 2


## `Intro_LoadTilemap`: the top-left 20x18 of the decompressed BG map, copied
## into `wTilemap` so `Intro_ColoredSuicuneFrameSwap` has something to rewrite.
func _load_tilemap() -> void:
	var map: PackedByteArray = bg_map()
	if map.size() < RomLayout.INTRO_MAP_BYTES:
		return
	var out := PackedByteArray()
	out.resize(COLUMNS * ROWS)
	for row: int in ROWS:
		for column: int in COLUMNS:
			out[row * COLUMNS + column] = map[row * MAP_COLUMNS + column]
	_tilemap = out


## `Intro_ColoredSuicuneFrameSwap`: every drawn tile below $80 swaps bit 3,
## which is the two-frame run cycle held in the tile numbers themselves.
func _colored_suicune_frame_swap() -> void:
	for index: int in _tilemap.size():
		var tile: int = _tilemap[index]
		if tile == 0 or tile >= 0x80:
			continue
		_tilemap[index] = tile ^ 0x08


## `CrystalIntro_UnownFade`: black out all eight palettes, then write three
## colours into palette [param slot] from the three fade ramps, at the point
## `wIntroSceneTimer` has reached. The ramp folds back on itself past half way,
## which is what makes one counter fade in and out again.
func _unown_fade(slot: int) -> void:
	var step: int = _timer & 0x3F
	if step > 0x1F:
		step = 0x3F - step
	# `ld bc, 8 palettes`: the background half only, so the Unown's own object
	# colours survive the blank.
	for index: int in BG_PALETTES * PALETTE_COLORS:
		_palettes[index] = 0
	var base: int = (slot * PALETTE_COLORS) & 0xFF
	if base + 3 >= _palettes.size():
		return
	_palettes[base + 1] = _grey_ramp(step)
	_palettes[base + 2] = _light_blue_ramp(step)
	_palettes[base + 3] = _blue_ramp(step)


## The three `for hue, 32` tables the assembler builds behind
## `CrystalIntro_UnownFade`: black to white, black to light blue, black to blue.
static func _grey_ramp(hue: int) -> int:
	return hue | (hue << 5) | (hue << 10)


static func _light_blue_ramp(hue: int) -> int:
	return ((hue / 2) << 5) | (hue << 10)


static func _blue_ramp(hue: int) -> int:
	return hue << 10


## `Intro_Scene20_AppearUnown`: one palette of `unown_1.pal` or `unown_2.pal`
## copied into the slot `wIntroSceneTimer` names.
func _appear_unown(which: int) -> void:
	var run: PackedInt32Array = _packed("unown")
	var slot: int = (_timer & 0x07) * PALETTE_COLORS
	for colour: int in PALETTE_COLORS:
		var source: int = which * PALETTE_COLORS + colour
		if slot + colour >= _palettes.size() or source >= run.size():
			return
		_palettes[slot + colour] = run[source]


## `Intro_Scene24_ApplyPaletteFade`: the [param at]th byte of `fade.pal`, which
## is one palette, copied over all eight.
func _apply_palette_fade(at: int) -> void:
	var run: PackedInt32Array = _packed("fade")
	var first: int = at / Gen2Palette.COLOR_BYTES
	if first + PALETTE_COLORS > run.size():
		return
	for slot: int in BG_PALETTES:
		for colour: int in PALETTE_COLORS:
			_palettes[slot * PALETTE_COLORS + colour] = run[first + colour]


## `Intro_FadeUnownWordPals`: the third and fourth colours of palette
## [param slot], taken from a fast and a slow grey ramp at `wIntroSceneTimer`.
func _fade_unown_word_pals(slot: int) -> void:
	var base: int = slot * PALETTE_COLORS + 2
	if base + 1 >= _palettes.size():
		return
	var step: int = _timer & 0x0F
	# `.FastFadePalettes` steps 31, 30, 28, 27, 25 ...; `.SlowFadePalettes` one
	# hue at a time from 31.
	var fast: int = 31 - (step / 2) * 3 - (step & 1)
	var slow: int = 31 - step
	_palettes[base] = _grey_ramp(maxi(fast, 0))
	_palettes[base + 1] = _grey_ramp(maxi(slow, 0))


## `swap a` on a byte, which the two Unown scenes use to turn the counter's high
## nybble into a palette slot.
static func _swap_nybbles(value: int) -> int:
	return ((value & 0x0F) << 4) | ((value & 0xF0) >> 4)


## `CrystalIntro_InitUnownAnim`: four structs at one point, each on its own
## frameset and its own angle.
func _init_unown_burst(at: Vector2i) -> void:
	for row: Array in UNOWN_BURST:
		var actor: Dictionary = _spawn(OBJ_INTRO_UNOWN, at)
		if actor.is_empty():
			return
		actor["var1"] = int(row[0])
		_reinit_frameset(actor, StringName(row[1]))


## `_InitSpriteAnimStruct`, which takes the first free slot. [param at] is the
## shadow-OAM pixel the `depixel` pair names, x then y.
func _spawn(object: StringName, at: Vector2i) -> Dictionary:
	var actor: Dictionary = {
		"object": object,
		"frameset": StringName((OBJECTS[object] as Dictionary)["frameset"]),
		"func": StringName((OBJECTS[object] as Dictionary)["func"]),
		"vtile": _sprite_vtile,
		"x": at.x, "y": at.y,
		"x_offset": 0, "y_offset": 0,
		"duration": 0, "frame": -1,
		"jumptable": 0, "var1": 0, "var2": 0,
	}
	_actors.append(actor)
	return actor


## `ReinitSpriteAnimFrame`: a new frameset, back at its first entry.
func _reinit_frameset(actor: Dictionary, frameset: StringName) -> void:
	actor["frameset"] = frameset
	actor["frame"] = -1
	actor["duration"] = 0


## `PlaySpriteAnimations`: each struct's own callback, then its frame counter.
func _run_sprites() -> void:
	for actor: Dictionary in _actors.duplicate():
		match StringName(actor["func"]):
			&"suicune":
				_sprite_suicune(actor)
			&"pichu_wooper":
				_sprite_pichu_wooper(actor)
			&"unown":
				_sprite_unown(actor)
			&"unown_f":
				_sprite_unown_f(actor)
			&"suicune_away":
				_sprite_suicune_away(actor)
	var kept: Array[Dictionary] = []
	for actor: Dictionary in _actors:
		if _advance_actor(actor):
			kept.append(actor)
	_actors = kept


## `SpriteAnimFunc_IntroSuicune`: still until `wIntroSceneTimer` is set, then a
## jump on a sine of amplitude 32 and the second frameset under it.
##
## The reinit is unconditional in the source and has to stay that way:
## `_ReinitSpriteAnimFrame` puts FRAME back to -1 and DURATION to 0 every frame,
## so the jump holds `.Frameset_IntroSuicune2`'s first entry for the whole leap
## rather than reaching its second.
func _sprite_suicune(actor: Dictionary) -> void:
	if _timer == 0:
		return
	actor["var2"] = (int(actor["var2"]) + 2) & 0xFF
	actor["y_offset"] = _sine_at(-int(actor["var2"]) & 0xFF, 32)
	_reinit_frameset(actor, &"intro_suicune_2")


## `SpriteAnimFunc_IntroPichuWooper`: one hop, ten steps of a sine of
## amplitude 32, then still.
func _sprite_pichu_wooper(actor: Dictionary) -> void:
	var var1: int = int(actor["var1"])
	if var1 >= 20:
		return
	var1 += 2
	actor["var1"] = var1
	actor["y_offset"] = _sine_at(-var1 & 0xFF, 32)


## `SpriteAnimFunc_IntroUnown`: the struct's own angle, at an amplitude that
## grows three a frame, so the four fly apart along four directions.
func _sprite_unown(actor: Dictionary) -> void:
	var amplitude: int = int(actor["jumptable"])
	actor["jumptable"] = (amplitude + 3) & 0xFF
	var angle: int = int(actor["var1"])
	actor["y_offset"] = _sine_at(angle, amplitude)
	actor["x_offset"] = _cosine_at(angle, amplitude)


## `SpriteAnimFunc_IntroUnownF`: reads `wSlotsDelay`, which is the same WRAM
## byte as `wIntroSceneFrameCounter` (both are in the union at `wJumptableIndex`
## + 1), so the Unown in front of Suicune's face appears on the one frame
## `IntroScene16`'s counter reaches $40 and not because of the slot machine.
func _sprite_unown_f(actor: Dictionary) -> void:
	if _counter != 0x40:
		return
	_reinit_frameset(actor, &"intro_unown_f_2")


## `SpriteAnimFunc_IntroSuicuneAway`: sixteen pixels down the screen a frame, on
## a coordinate that is a byte and wraps rather than clamping.
func _sprite_suicune_away(actor: Dictionary) -> void:
	actor["y"] = (int(actor["y"]) + 16) & 0xFF


## `GetSpriteAnimFrame` and the end of a frameset. Returns false when the struct
## is deleted.
func _advance_actor(actor: Dictionary) -> bool:
	var frameset: Dictionary = FRAMESETS[StringName(actor["frameset"])]
	var frames: Array = frameset["frames"]
	if int(actor["duration"]) > 0:
		actor["duration"] = int(actor["duration"]) - 1
		return true
	var next: int = int(actor["frame"]) + 1
	if next >= frames.size():
		match StringName(frameset["end"]):
			FRAMESET_DELETE:
				return false
			FRAMESET_RESTART:
				next = 0
			_:
				# `oamend` winds back two and re-reads the last entry forever;
				# `oamwait` holds the struct with nothing drawn.
				next = maxi(frames.size() - 1, 0)
	if frames.is_empty():
		actor["frame"] = -1
		return true
	actor["frame"] = next
	actor["duration"] = int((frames[next] as Array)[1])
	return true


## The frameset entry a struct is showing, or empty while it draws nothing.
func _actor_frame(actor: Dictionary) -> Array:
	var frames: Array = (FRAMESETS[StringName(actor["frameset"])] as Dictionary)["frames"]
	var at: int = int(actor["frame"])
	if at < 0 or at >= frames.size():
		return []
	return frames[at]


## `Sprites_Sine`: a = d * sin(a * pi/32), read out of `BattleAnimSineWave`
## rather than derived, and zero without one.
func _sine_at(angle: int, amplitude: int) -> int:
	if _sine == null:
		return 0
	return Gen2BattleAnimFunctions.sine_of(_sine, angle, amplitude)


func _cosine_at(angle: int, amplitude: int) -> int:
	if _sine == null:
		return 0
	return Gen2BattleAnimFunctions.cosine_of(_sine, angle, amplitude)


func _emit(type: StringName, values: Dictionary) -> void:
	var event: Dictionary = {"type": type, "frame": _frame, "scene": _scene}
	event.merge(values, true)
	_events.append(event)
