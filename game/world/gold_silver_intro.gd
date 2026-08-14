class_name Gen2GoldSilverIntro
extends RefCounted

## `GoldSilverIntro` (pokegold/engine/movie/intro.asm): the movie between the
## GameFreak logo and the title screen on Gold and Silver.
##
## Seventeen scenes behind one jumptable, stepped once per hardware frame, over
## three cutscenes: shellders and magikarp under water rising to a surfacing
## Lapras, Jigglypuff and Pikachu in the grass, and Charizard breathing a
## fireball over the three Johto starters. Crystal runs [Gen2IntroMovie]
## instead, which is a different movie entirely.
##
## Two things here are not [Gen2IntroMovie]'s shape:
##
## - **The colour model is `DmgToCgbBGPals`, not palette runs.** Each cutscene
##   loads one background palette and up to two object palettes through
##   `SCGB_GS_INTRO`, and every fade after that is a table of DMG register bytes
##   reordering those four colours. `WipeAttrmap` leaves every tile on palette 0,
##   so the whole movie is one background palette at a time.
## - **`hLCDCPointer` is `$42`, which is LOW(rSCY).** Crystal's movie gives each
##   scanline its own `hSCX`; this one gives each its own `hSCY`, which is what
##   makes the water wobble. [method scroll_y_at] is the seam.
##
## [Gen2GoldSilverIntroPage] turns all of it into pixels; nothing here draws.

## `wBGPals1` and `wOBPals1`, of which this movie only ever fills the first
## background palette and the first two object ones.
const BG_PALETTES: int = 1
const OBJECT_PALETTES: int = 2
const PALETTE_COLORS: int = RomLayout.INTRO_PALETTE_COLORS

const COLUMNS: int = 20
const ROWS: int = 18
## `TILEMAP_WIDTH`/`TILEMAP_HEIGHT` (constants/hardware.inc), which is the BG map
## rather than the screen: `Intro_DrawBackground` fills the whole thing.
const MAP_COLUMNS: int = 32
const MAP_ROWS: int = 32
const MAP_BYTES: int = MAP_COLUMNS * MAP_ROWS
const SCREEN_HEIGHT_PX: int = 144

## `Intro_Draw2x2Tiles`: a metatile map is sixteen wide and each byte indexes
## four tiles in the scene's own `.bin`.
const META_COLUMNS: int = RomLayout.GS_INTRO_META_COLUMNS
const META_BYTES: int = RomLayout.GS_INTRO_META_BYTES

## `wLYOverrides` and `wLYOverrides2`. The first is one `hSCY` per scanline; the
## second is the sine `Intro_InitSineLYOverrides` fills and
## `Intro_UpdateLYOverrides` rotates one entry per call.
const LY_FLAT_LINES: int = 0x10
const LY_SINE_LINES: int = 0x80
const LY_SINE_AMPLITUDE: int = 4

## The sounds and songs the movie asks for.
const MUSIC_NONE: int = 0x00
const MUSIC_GS_OPENING: int = 0x52
const MUSIC_GS_OPENING_2: int = 0x53
const SFX_GS_INTRO_CHARIZARD_FIREBALL: int = 0xA7
const SFX_GS_INTRO_POKEMON_APPEARS: int = 0xA8

## `%11100100`, the identity order every scene opens on.
const DMG_IDENTITY: int = 0xE4
## `%00111111`, which floods every colour with the fourth: the starters scene's
## silhouette.
const DMG_SILHOUETTE: int = 0x3F
## `%11111111`, the object order the silhouette scene hides its sprites behind.
const DMG_OBJECT_HIDDEN: int = 0xFF

## `IntroScene5.palettes` and `IntroScene9.palettes`, the two water and grass
## fade-outs, and `IntroScene16.palettes`, the fireball's. Each is walked by a
## different shift of the scene's own counter; -1 is the source's `db -1`.
const FADE_WATER: Array[int] = [0xE4, 0xE4, 0x90, 0x40, 0x00]
const FADE_GRASS: Array[int] = [0xE4, 0xE4, 0xE4, 0xE4, 0xE4, 0x90, 0x40, 0x00]
const FADE_FIREBALL: Array[int] = [0xE4, 0x90, 0x40, 0x00]
## `IntroScene12.palettes`, which ends on its own `%00000000` rather than a `-1`.
const CHARIZARD_PALETTES: Array[int] = [0x6A, 0xA5, 0xE4, 0x00]

## Which cutscene's art is loaded, which is what a page reads its sheets from.
const CUTSCENE_WATER: StringName = &"water"
const CUTSCENE_GRASS: StringName = &"grass"
const CUTSCENE_FIRE: StringName = &"fire"

## `DrawIntroCharizardGraphic.charizard_data`, as (vtile, width, height, x, y).
const CHARIZARD_FRAMES: Array[Array] = [
	[0x00, 8, 8, 10, 6], [0x40, 9, 8, 9, 6], [0x88, 9, 8, 8, 6],
]
## Its three `DelayFrame`s, and `hlcoord 0, 6` with `ld c, SCREEN_WIDTH * 8`,
## which is the eight rows it blanks before drawing.
const CHARIZARD_DELAY: int = 3
const CHARIZARD_CLEAR_ROW: int = 6
const CHARIZARD_CLEAR_ROWS: int = 8

## `Intro_CheckSCYEvent.scy_jumptable`, as `hSCY` to what it fires.
const SCY_EVENTS: Dictionary = {
	0x86: &"load_chikorita", 0x87: &"chikorita_appears", 0x88: &"flash_mon",
	0x98: &"flash_silhouette", 0x99: &"load_cyndaquil", 0xAF: &"cyndaquil_appears",
	0xB0: &"flash_mon", 0xC0: &"flash_silhouette", 0xC1: &"load_totodile",
	0xD7: &"totodile_appears", 0xD8: &"flash_mon", 0xE8: &"flash_silhouette",
	0xE9: &"load_charizard",
}
## `Intro_GetMonFrontpic`'s three species and the vtile each is decompressed to.
const STARTERS: Dictionary = {
	&"chikorita": {"species": 152, "vtile": 0x10},
	&"cyndaquil": {"species": 155, "vtile": 0x29},
	&"totodile": {"species": 158, "vtile": 0x42},
}

## `Intro_InitBubble.pixel_table`, read `ld e, [hl] / inc hl / ld d, [hl]`, so
## each row is (x, y) rather than the (y, x) every `depixel` in the file is.
const BUBBLE_AT: Array[Vector2i] = [
	Vector2i(6 * 8, 14 * 8 + 4), Vector2i(14 * 8, 18 * 8 + 4),
	Vector2i(10 * 8, 16 * 8 + 4), Vector2i(12 * 8, 15 * 8),
	Vector2i(4 * 8, 13 * 8), Vector2i(8 * 8, 17 * 8),
]

## `Intro_InitMagikarps`' two alternating triples, as `depixel` (y, x) pairs
## turned into the (x, y) a struct stores.
const MAGIKARP_AT: Array[Array] = [
	[Vector2i(28 * 8, 29 * 8), Vector2i(0, 26 * 8), Vector2i(24 * 8, 0)],
	[Vector2i(30 * 8, 28 * 8), Vector2i(24 * 8, 31 * 8), Vector2i(28 * 8, 2 * 8)],
]
## `Intro_InitShellders`' three, which fall through one into the next so the
## third is the only one `.InitAnim` is reached with.
const SHELLDER_AT: Array[Vector2i] = [
	Vector2i(7 * 8, 18 * 8), Vector2i(10 * 8, 14 * 8), Vector2i(15 * 8, 16 * 8),
]

## The framesets, as (OAM set, duration, attributes) plus how the run ends.
## `oamframe X, n` lasts n + 1 frames; `oamend` repeats its last entry forever,
## `oamdelete` takes the struct away and `oamrestart` goes round again.
const FRAMESET_END: StringName = &"end"
const FRAMESET_DELETE: StringName = &"delete"
const FRAMESET_RESTART: StringName = &"restart"

## `B_OAM_XFLIP` on a frameset entry, which flips each tile where it stands.
const FLIP_X: int = 1

const FRAMESETS: Dictionary = {
	&"bubble": {"frames": [[0, 8, 0], [1, 8, 0]], "end": FRAMESET_RESTART},
	&"shellder": {"frames": [[2, 8, 0], [3, 8, 0]], "end": FRAMESET_RESTART},
	&"magikarp": {
		"frames": [[4, 1, FLIP_X], [5, 1, FLIP_X]], "end": FRAMESET_RESTART,
	},
	&"lapras": {
		"frames": [[6, 7, 0], [7, 7, 0], [8, 7, 0], [6, 7, 0]], "end": FRAMESET_RESTART,
	},
	&"note": {"frames": [[9, 8, 0]], "end": FRAMESET_END},
	&"invisible_note": {"frames": [[10, 8, 0]], "end": FRAMESET_END},
	&"jigglypuff": {
		"frames": [[11, 25, FLIP_X], [13, 9, 0], [11, 25, 0], [13, 9, 0]],
		"end": FRAMESET_RESTART,
	},
	&"jigglypuff_2": {"frames": [[12, 32, 0]], "end": FRAMESET_END},
	&"pikachu": {
		"frames": [[14, 4, 0], [15, 5, 0], [17, 4, 0]], "end": FRAMESET_RESTART,
	},
	&"pikachu_2": {"frames": [[15, 8, 0]], "end": FRAMESET_END},
	&"pikachu_3": {"frames": [[16, 32, 0]], "end": FRAMESET_END},
	&"pikachu_tail": {
		"frames": [[18, 3, 0], [19, 3, 0], [20, 3, 0], [19, 3, 0]],
		"end": FRAMESET_RESTART,
	},
	&"pikachu_tail_2": {"frames": [[18, 31, 0]], "end": FRAMESET_END},
	&"fireball": {
		"frames": [[21, 1, 0], [22, 1, 0], [23, 1, 0]], "end": FRAMESET_DELETE,
	},
	&"chikorita": {"frames": [[24, 24, 0]], "end": FRAMESET_DELETE},
	&"cyndaquil": {"frames": [[25, 24, FLIP_X]], "end": FRAMESET_DELETE},
	&"totodile": {"frames": [[26, 24, 0]], "end": FRAMESET_DELETE},
}

## The `SpriteAnimObjects` rows the movie spawns: the frameset a struct starts on
## and the `SPRITE_ANIM_FUNC_*` that moves it. Every scene writes
## `wSpriteAnimDict` value `$00`, so every struct's tile base is zero.
const OBJECTS: Dictionary = {
	&"bubble": {"frameset": &"bubble", "func": &"bubble"},
	&"shellder": {"frameset": &"shellder", "func": &"shellder"},
	&"magikarp": {"frameset": &"magikarp", "func": &"magikarp"},
	&"lapras": {"frameset": &"lapras", "func": &"lapras"},
	&"note": {"frameset": &"note", "func": &"note"},
	&"invisible_note": {"frameset": &"invisible_note", "func": &"note"},
	&"jigglypuff": {"frameset": &"jigglypuff", "func": &"jigglypuff"},
	&"pikachu": {"frameset": &"pikachu", "func": &"pikachu"},
	&"pikachu_tail": {"frameset": &"pikachu_tail", "func": &"pikachu_tail"},
	&"fireball": {"frameset": &"fireball", "func": &"fireball"},
	&"chikorita": {"frameset": &"chikorita", "func": &"chikorita_totodile"},
	&"cyndaquil": {"frameset": &"cyndaquil", "func": &"cyndaquil"},
	&"totodile": {"frameset": &"totodile", "func": &"chikorita_totodile"},
}

var _data: GameData = null
var _sine: Gen2BattleAnimData = null

## `wIntroJumptableIndex` and its `JUMPTABLE_EXIT_F`.
var _scene: int = 0
var _exit: bool = false
## Set by `IntroScene17`, which spends its sixty-four frames before the bit.
var _exit_after_delay: bool = false
## `wIntroFrameCounter1` and `wIntroFrameCounter2`.
var _counter1: int = 0
var _counter2: int = 0
## `wIntroSpriteStateFlag`, which Lapras and Pikachu set on their way out and
## Jigglypuff and the note read.
var _sprite_flag: bool = false

var _scx: int = 0
var _scy: int = 0
var _global_x: int = 0
var _global_y: int = 0
## `wLYOverrides` under `hLCDCPointer` = LOW(rSCY): one `hSCY` per scanline. Off
## when [member _ly_active] is false, which is `hLCDCPointer` zero.
var _ly: PackedByteArray = PackedByteArray()
var _ly_active: bool = false
## `wLYOverrides2`, the sine the overrides are built from.
var _ly_sine: PackedByteArray = PackedByteArray()

## `rBGP`, `rOBP0` and `rOBP1`, which are the whole colour model: the palettes
## below are reordered through them by `DmgToCgbBGPals`/`DmgToCgbObjPals`.
var _bgp: int = DMG_IDENTITY
var _obp0: int = DMG_IDENTITY
var _obp1: int = DMG_IDENTITY
## `wBGPals1` and `wOBPals1` as the layout loaded them, before that reordering.
var _bg_palette: PackedInt32Array = PackedInt32Array()
var _ob_palettes: PackedInt32Array = PackedInt32Array()

## Which cutscene's sheets are in VRAM, and the BG map they are drawn into.
var _cutscene: StringName = &""
var _bg_map: PackedByteArray = PackedByteArray()
## `wIntroTilemapPointer` and `wIntroBGMapPointer`, as offsets into the metatile
## map and the BG map rather than addresses.
var _meta_at: int = 0
var _bg_map_at: int = 0

var _actors: Array[Dictionary] = []
## Frames a scene spends inside `DelayFrames`, during which neither the
## jumptable nor `PlaySpriteAnimations` runs.
var _delay: int = 0
var _frame: int = 0
var _events: Array[Dictionary] = []


## [param sine] is `BattleAnimSineWave`, which every motion callback here scales
## and `Intro_InitSineLYOverrides` fills its own buffer from. Without one the
## sprites sit still and the water does not wobble, but the frame counts do not
## move, so a caller with no animation layer still spends the right frames.
static func create(
	data: GameData, sine: Gen2BattleAnimData = null
) -> Gen2GoldSilverIntro:
	var out := Gen2GoldSilverIntro.new()
	out._data = data
	out._sine = sine
	out._ly.resize(SCREEN_HEIGHT_PX)
	out._ly_sine.resize(LY_SINE_LINES + 1)
	out._bg_map.resize(MAP_BYTES)
	out._bg_palette.resize(BG_PALETTES * PALETTE_COLORS)
	out._ob_palettes.resize(OBJECT_PALETTES * PALETTE_COLORS)
	return out


## Whether [param data] carries the art the movie draws. A cache without it is
## the caller's cue to skip the phase rather than to run it blank.
static func available(data: GameData) -> bool:
	return data != null and data.has_gs_intro()


func scene() -> int:
	return _scene


func finished() -> bool:
	return _exit


func frame() -> int:
	return _frame


func counter() -> int:
	return _counter1


## `wIntroSpriteStateFlag`, which is what Jigglypuff waits on and the note stops
## on.
func sprite_flag() -> bool:
	return _sprite_flag


func scroll() -> Vector2i:
	return Vector2i(_scx, _scy)


## The `hSCY` for one scanline, which is `wLYOverrides` while `hLCDCPointer`
## points at rSCY and plain `hSCY` otherwise.
func scroll_y_at(line: int) -> int:
	if not _ly_active or line < 0 or line >= _ly.size():
		return _scy
	return _ly[line]


## Which cutscene's sheets are loaded, as the `RomLayout.GS_INTRO_SECTION` name
## prefix: `water`, `grass` or `fire`. Empty before the first scene has run.
func cutscene() -> StringName:
	return _cutscene


## The BG map `Intro_DrawBackground` and `Intro_UpdateTilemapAndBGMap` fill, one
## tile number per cell of the whole 32x32.
func bg_map() -> PackedByteArray:
	return _bg_map


## The background palette, reordered through `rBGP` the way `DmgToCgbBGPals`
## reorders it. Every tile is on this one, since `WipeAttrmap` leaves the whole
## attribute plane at zero.
func palette() -> PackedColorArray:
	return _reordered(_bg_palette, 0, _bgp)


## One object palette, reordered through `rOBP0` or `rOBP1`.
func object_palette(index: int) -> PackedColorArray:
	return _reordered(_ob_palettes, index, _obp1 if index == 1 else _obp0)


## `CopyPals`: destination colour j is source colour `(order >> 2j) & 3`, which
## is how one DMG register byte fades a four-colour palette without touching it.
func _reordered(run: PackedInt32Array, index: int, order: int) -> PackedColorArray:
	var out := PackedColorArray()
	var base: int = index * PALETTE_COLORS
	if base + PALETTE_COLORS > run.size():
		return out
	for colour: int in PALETTE_COLORS:
		out.append(Gen2Palette.from_packed(
			run[base + ((order >> (colour * 2)) & 0x03)]
		))
	return out


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
				(int(actor["x"]) + int(actor["x_offset"]) + _global_x) & 0xFF,
				(int(actor["y"]) + int(actor["y_offset"]) + _global_y) & 0xFF,
			),
			"set": int(entry[0]),
			"flip_x": bool(int(entry[2]) & FLIP_X),
			"vtile": int(actor["vtile"]),
		})
	return out


func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = _events.duplicate(true)
	_events.clear()
	return out


## One `.PlayFrame` pass: `PlaySpriteAnimations` and then `IntroSceneJumper`, in
## the order this loop calls them, which is the opposite of Crystal's. A scene
## that spent `DelayFrames` inside its own body holds both off until the debt is
## paid.
func advance_frame() -> Array[Dictionary]:
	if _exit:
		return drain_events()
	_frame += 1
	if _delay > 0:
		_delay -= 1
		if _delay == 0 and _exit_after_delay:
			_exit = true
		return drain_events()
	_run_sprites()
	_run_scene()
	return drain_events()


## The button `.PlayFrame` reads: any of A, B, START or SELECT ends the movie,
## which is the only skip it has.
func cancel() -> bool:
	if _exit:
		return false
	_exit = true
	return true


## `IntroSceneJumper`, with the five places the source falls straight into the
## next scene's body on the same frame.
func _run_scene() -> void:
	while _step_scene() and not _exit:
		pass


## One scene body. Answers true when the source falls through into the next.
func _step_scene() -> bool:
	match _scene:
		0:
			_scene_water_setup()
		1:
			return _scene_shellders()
		2:
			return _scene_rise_to_surface()
		3:
			return _scene_lapras_surfs()
		4:
			_scene_water_fade()
		5:
			_scene_grass_setup()
		6:
			_scene_scroll_to_jigglypuff()
		7:
			_scene_pikachu_attacks()
		8:
			_scene_grass_fade()
		9:
			_scene_fire_setup()
		10:
			return _scene_scroll_to_charizard()
		11:
			_scene_charizard_palettes()
		12:
			_scene_mouth_open()
		13:
			return _scene_breathing_fire()
		14:
			_scene_fireball_starts()
		15:
			_scene_fireball_fade()
		16:
			_scene_end()
	return false


## `IntroScene1`. `ClearBGPalettes` and `ClearTilemap` each spend `WaitBGMap`'s
## four `DelayFrame`s while the LCD is still on, and one more falls after
## `EnableLCD`, so the scene costs nine frames beyond its own.
func _scene_water_setup() -> void:
	_load_cutscene(CUTSCENE_WATER, RomLayout.GS_INTRO_WATER_FIRST_ROW)
	_scy = 0
	_global_y = 0
	_global_x = 0
	_scx = 0x58
	_counter2 = 0
	_counter1 = 0x80
	_ly_active = true
	_init_sine_ly_overrides()
	_sprite_flag = false
	_load_layout(CUTSCENE_WATER)
	_bgp = DMG_IDENTITY
	_obp0 = DMG_IDENTITY
	_obp1 = DMG_IDENTITY
	_init_shellders()
	_emit(&"play_music", {"music": MUSIC_GS_OPENING})
	_delay = 9
	_scene += 1


## `IntroScene2`: shellders drift by while the counter runs out, then the rise
## begins on the same frame.
func _scene_shellders() -> bool:
	_update_ly_overrides()
	if _counter1 == 0:
		_counter1 = 0x10
		_scene += 1
		return true
	_counter1 -= 1
	_init_bubble()
	return false


## `IntroScene3`: `IntroScene3_Jumper` picks a sub-scene off the counter the
## scroll is burning down, and reaching the surface falls into `IntroScene4`.
func _scene_rise_to_surface() -> bool:
	_scene3_jumper()
	if not _scroll_to_surface():
		return false
	_reset_ly_overrides()
	_scy = (_scy + 1) & 0xFF
	_scene += 1
	return true


## `IntroScene3_ScrollToSurface`. Answers true on the carry, which is the
## counter the tilemap walk decrements reaching zero.
func _scroll_to_surface() -> bool:
	_counter2 = (_counter2 + 1) & 0xFF
	if _counter2 & 0x03 == 0:
		_scx = (_scx - 1) & 0xFF
	# `and 3` then `and 1` on what that left, which is the counter's low bit.
	if _counter2 & 0x01 != 0:
		return false
	_global_y = (_global_y + 1) & 0xFF
	# `ld a, [hl] / dec [hl] / and $f`: the test is on the value before the
	# decrement, so the walk runs on the sixteenth pixel rather than the first.
	var before: int = _scy
	_scy = (_scy - 1) & 0xFF
	if before & 0x0F == 0:
		_update_tilemap_and_bg_map()
	return _counter1 == 0


## `IntroScene3_Jumper`, a seventeen-entry jumptable on `wIntroFrameCounter1`,
## which counts down from $10 as the screen rises.
func _scene3_jumper() -> void:
	match _counter1:
		3:
			# `.scene3_1` falls into `.scene3_2`.
			_init_lapras()
			_obp0 = DMG_IDENTITY
			_obp1 = DMG_IDENTITY
			_animate_ocean_waves()
		6, 7, 8:
			_init_magikarps()
			_animate_ocean_waves()
		9:
			if _counter2 & 0x1F == 0:
				_load_palette_run("magikarp")
			else:
				_init_magikarps()
		10:
			_ly_active = false
		11, 12, 13, 14, 15, 16:
			_update_ly_overrides()
		_:
			_animate_ocean_waves()


## `IntroScene4`: Lapras surfs left until it deletes itself, which is what sets
## `wIntroSpriteStateFlag` and falls into the fade.
func _scene_lapras_surfs() -> bool:
	if _sprite_flag:
		_scene += 1
		_counter1 = 0
		return true
	_counter2 = (_counter2 + 1) & 0xFF
	if _counter2 & 0x0F == 0:
		_scx = (_scx - 2) & 0xFF
	_animate_ocean_waves()
	return false


## `IntroScene5`: the water fade, one register every sixteen frames.
func _scene_water_fade() -> void:
	var value: int = _counter1
	_counter1 = (_counter1 + 1) & 0xFF
	# `swap a / and $f`, which is the counter's high nybble.
	var index: int = (value >> 4) & 0x0F
	if index >= FADE_WATER.size():
		_scene += 1
		return
	_bgp = FADE_WATER[index]
	_animate_ocean_waves()
	_scx = (_scx - 2) & 0xFF


## `IntroScene6`: the grass cutscene, which spends no frames of its own.
func _scene_grass_setup() -> void:
	_scene += 1
	_reset_ly_overrides()
	_ly_active = false
	_load_cutscene(CUTSCENE_GRASS, 0)
	_scy = 0
	_global_y = 0
	_scx = 0x60
	_global_x = 0xA0
	_counter2 = 0
	_load_layout(CUTSCENE_GRASS)
	_bgp = DMG_IDENTITY
	_obp0 = DMG_IDENTITY
	_obp1 = DMG_IDENTITY
	_init_jigglypuff()
	_sprite_flag = false


## `IntroScene7`: the screen scrolls left to Jigglypuff three frames in four,
## and Pikachu is spawned where it stops.
func _scene_scroll_to_jigglypuff() -> void:
	_init_note()
	var value: int = _counter2
	_counter2 = (_counter2 + 1) & 0xFF
	if value & 0x03 == 0:
		return
	if _scx == 0:
		_counter1 = 0xFF
		_init_pikachu()
		_scene += 1
		return
	_scx = (_scx - 1) & 0xFF
	_global_x = (_global_x + 1) & 0xFF


## `IntroScene8`: Pikachu's attack, which is $ff frames of notes.
func _scene_pikachu_attacks() -> void:
	if _counter1 == 0:
		_counter1 = 0
		# `Intro_LoadAllPal0` is the SGB branch only and does nothing on CGB.
		_scene += 1
		return
	_counter1 -= 1
	_init_note()
	_counter2 = (_counter2 + 1) & 0xFF


## `IntroScene9`: the grass fade, one register every eight frames, with the
## screen scrolling down under it.
func _scene_grass_fade() -> void:
	var value: int = _counter1
	_counter1 = (_counter1 + 1) & 0xFF
	var index: int = value >> 3
	if index >= FADE_GRASS.size():
		_scene += 1
		return
	_bgp = FADE_GRASS[index]
	_scy = (_scy + 1) & 0xFF
	_global_y = (_global_y - 1) & 0xFF


## `IntroScene10`: the fire cutscene. `DrawIntroCharizardGraphic` spends three
## frames and the gap between the two `PlayMusic` calls one more.
func _scene_fire_setup() -> void:
	_scene += 1
	_reset_ly_overrides()
	_ly_active = false
	_load_cutscene(CUTSCENE_FIRE, -1)
	_draw_charizard(0)
	_scy = 0x80
	_scx = 0
	_global_y = 0
	_global_x = 0
	_counter2 = 0
	_load_layout(CUTSCENE_FIRE)
	_bgp = DMG_SILHOUETTE
	_obp0 = DMG_OBJECT_HIDDEN
	_obp1 = DMG_OBJECT_HIDDEN
	_emit(&"play_music", {"music": MUSIC_NONE})
	_emit(&"play_music", {"music": MUSIC_GS_OPENING_2})
	_delay = CHARIZARD_DELAY + 1


## `IntroScene11`: the screen scrolls up every other frame, firing the starters
## off `hSCY` on the way, and falls into `IntroScene12` at the top.
func _scene_scroll_to_charizard() -> bool:
	var value: int = _counter2
	_counter2 = (_counter2 + 1) & 0xFF
	if value & 0x01 == 0:
		return false
	_check_scy_event()
	if _scy == 0:
		_scene += 1
		_counter1 = 0
		return true
	_scy = (_scy + 1) & 0xFF
	return false


## `IntroScene12`: four registers, four frames each, ending on its own zero.
func _scene_charizard_palettes() -> void:
	var value: int = _counter1
	_counter1 = (_counter1 + 1) & 0xFF
	var order: int = CHARIZARD_PALETTES[(value >> 2) & 0x03]
	if order == 0:
		_scene += 1
		_counter1 = 0x80
		return
	_bgp = order
	_obp0 = order
	_obp1 = order


## `IntroScene13`: $80 frames, then the mouth opens.
func _scene_mouth_open() -> void:
	if _counter1 != 0:
		_counter1 -= 1
		return
	_scene += 1
	_draw_charizard(1)
	_delay = CHARIZARD_DELAY
	_counter1 = 4


## `IntroScene14`: four frames, then the fire, which falls into `IntroScene15`.
func _scene_breathing_fire() -> bool:
	if _counter1 != 0:
		_counter1 -= 1
		return false
	_scene += 1
	_draw_charizard(2)
	_delay = CHARIZARD_DELAY
	_counter1 = 64
	_counter2 = 0
	_emit(&"play_sfx", {"sfx": SFX_GS_INTRO_CHARIZARD_FIREBALL})
	return true


## `IntroScene15`: the fireball for sixty-four frames.
func _scene_fireball_starts() -> void:
	_animate_fireball()
	if _counter1 != 0:
		_counter1 -= 1
		return
	_scene += 1
	_counter1 = 0


## `IntroScene16`: the fireball again, fading out under it.
func _scene_fireball_fade() -> void:
	_animate_fireball()
	var value: int = _counter1
	_counter1 = (_counter1 + 1) & 0xFF
	# `swap a / and 7`, which wraps rather than running off the table.
	var index: int = (value >> 4) & 0x07
	if index >= FADE_FIREBALL.size():
		_scene += 1
		return
	_bgp = FADE_FIREBALL[index]
	_obp0 = FADE_FIREBALL[index]
	_obp1 = FADE_FIREBALL[index]


## `IntroScene17`: `ld c, 64` of `DelayFrame` and then the exit bit, which the
## loop reads on the frame after.
func _scene_end() -> void:
	_delay = 64
	_exit_after_delay = true


## `Intro_DrawBackground` and the pointers `IntroScene1` and `IntroScene6` set
## up for it. [param first_row] is the metatile row the scene starts on, or -1
## for the fire cutscene, which blanks the map instead of drawing one.
func _load_cutscene(name: StringName, first_row: int) -> void:
	_cutscene = name
	_actors.clear()
	_bg_map.fill(0)
	_bg_map_at = 0
	if first_row < 0:
		return
	_meta_at = first_row * META_COLUMNS
	_draw_background()


## `Intro_DrawBackground`: sixteen metatile rows of sixteen, which is the whole
## BG map rather than the twenty visible columns.
func _draw_background() -> void:
	var at: int = _meta_at
	for row: int in META_COLUMNS:
		for column: int in META_COLUMNS:
			_draw_metatile(at, (row * 2) * MAP_COLUMNS + column * 2)
			at += 1


## `Intro_Draw2x2Tiles`: one metatile map byte indexes four tiles in the `.bin`,
## written as a 2x2 block a `TILEMAP_WIDTH` apart.
func _draw_metatile(meta_at: int, cell: int) -> void:
	var map: PackedByteArray = _meta_map()
	var meta: PackedByteArray = _meta_tiles()
	if meta_at < 0 or meta_at >= map.size():
		return
	var first: int = int(map[meta_at]) * META_BYTES
	if first + META_BYTES > meta.size():
		return
	for index: int in META_BYTES:
		var target: int = cell + (index / 2) * MAP_COLUMNS + (index % 2)
		if target >= 0 and target < _bg_map.size():
			_bg_map[target] = meta[first + index]


## `Intro_UpdateTilemapAndBGMap`: one metatile row back, two BG map rows up, and
## a tick off the counter that ends the rise. The BG map pointer wraps inside
## vBGMap0 by `and %11111011 / or %00001000`.
func _update_tilemap_and_bg_map() -> void:
	_meta_at -= META_COLUMNS
	_bg_map_at = (_bg_map_at - 2 * MAP_COLUMNS) & (MAP_BYTES - 1)
	var at: int = _meta_at
	for column: int in META_COLUMNS:
		_draw_metatile(at, (_bg_map_at + column * 2) & (MAP_BYTES - 1))
		at += 1
	_counter1 = (_counter1 - 1) & 0xFF


## `Intro_AnimateOceanWaves`: four tiles cycled through four sets, copied over
## the BG map from `vBGMap0 tile $1e`. The request the source queues for VBlank
## is applied here directly, which lands the same bytes on the same frame.
func _animate_ocean_waves() -> void:
	if _counter2 & 0x03 == 0x03:
		return
	var set: int = (_counter2 & 0x30) >> 4
	for index: int in 32:
		var cell: int = (0x1E + index) & (MAP_BYTES - 1)
		_bg_map[cell] = 0x70 + set * 4 + (index & 0x03)


## `Intro_InitSineLYOverrides`: `BattleAnim_Sine_e` at amplitude 4, one entry per
## scanline of the second override buffer.
func _init_sine_ly_overrides() -> void:
	for index: int in _ly_sine.size():
		_ly_sine[index] = _sine_at(index, LY_SINE_AMPLITUDE) & 0xFF


## `Intro_UpdateLYOverrides`: `hSCY` for the first sixteen lines and the sine
## plus `hSCY` for the next 128, rotating that sine one entry per call.
func _update_ly_overrides() -> void:
	for line: int in LY_FLAT_LINES:
		_ly[line] = _scy
	var first: int = _ly_sine[0]
	for index: int in LY_SINE_LINES:
		var value: int = _ly_sine[index + 1]
		_ly_sine[index] = value
		var line: int = LY_FLAT_LINES + index
		if line < _ly.size():
			_ly[line] = (value + _scy) & 0xFF
	_ly_sine[LY_SINE_LINES] = first


func _reset_ly_overrides() -> void:
	for line: int in _ly.size():
		_ly[line] = 0


## `_CGB_GSIntro`'s three scenes, each of which loads one background palette and
## up to two object ones and then wipes the attribute map.
func _load_layout(name: StringName) -> void:
	match name:
		CUTSCENE_WATER:
			_load_palette_run("shellder_lapras")
		CUTSCENE_GRASS:
			_set_palettes(
				_packed("jigglypuff_pikachu_bg"), _packed("jigglypuff_pikachu_ob")
			)
		CUTSCENE_FIRE:
			# `PalPacket_Pack + 1` is PACK, ROUTES, ROUTES, ROUTES, and every tile
			# is on palette 0, so PACK is the only one the screen shows.
			_set_palettes(_packed("pack"), _packed("starters_transition"))


## A run whose background palette is followed by its object palettes, which is
## how both of the INCLUDEd pairs are laid out.
func _load_palette_run(name: String) -> void:
	var run: PackedInt32Array = _packed(name)
	_set_palettes(run, run.slice(PALETTE_COLORS))


func _set_palettes(background: PackedInt32Array, objects: PackedInt32Array) -> void:
	for index: int in mini(background.size(), _bg_palette.size()):
		_bg_palette[index] = background[index]
	for index: int in mini(objects.size(), _ob_palettes.size()):
		_ob_palettes[index] = objects[index]


## The cache holds a palette as colours; the reordering above works on the
## cartridge's packed 15-bit values, so they are read back as those.
func _packed(name: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _data == null:
		return out
	for colour: Color in _data.gs_intro_palette(name):
		out.append(
			int(round(colour.r * 31.0))
			| (int(round(colour.g * 31.0)) << 5)
			| (int(round(colour.b * 31.0)) << 10)
		)
	return out


func _meta_map() -> PackedByteArray:
	return _data.gs_intro_map("%s_tilemap" % _cutscene) if _data != null \
		else PackedByteArray()


func _meta_tiles() -> PackedByteArray:
	return _data.gs_intro_map("%s_meta" % _cutscene) if _data != null \
		else PackedByteArray()


## `DrawIntroCharizardGraphic`: eight rows blanked, then a run of ascending tile
## numbers laid out at the frame's own width, height and corner.
func _draw_charizard(frame: int) -> void:
	for row: int in CHARIZARD_CLEAR_ROWS:
		for column: int in COLUMNS:
			var cell: int = (CHARIZARD_CLEAR_ROW + row) * MAP_COLUMNS + column
			if cell < _bg_map.size():
				_bg_map[cell] = 0
	var entry: Array = CHARIZARD_FRAMES[frame]
	var tile: int = int(entry[0])
	for row: int in int(entry[2]):
		for column: int in int(entry[1]):
			var cell: int = (int(entry[4]) + row) * MAP_COLUMNS + int(entry[3]) + column
			if cell >= 0 and cell < _bg_map.size():
				_bg_map[cell] = tile & 0xFF
			tile += 1


## `Intro_CheckSCYEvent`, whose jumptable is keyed by `hSCY` itself.
func _check_scy_event() -> void:
	if not SCY_EVENTS.has(_scy):
		return
	match StringName(SCY_EVENTS[_scy]):
		&"load_chikorita":
			_load_mon_palette(&"chikorita")
		&"load_cyndaquil":
			_load_mon_palette(&"cyndaquil")
		&"load_totodile":
			_load_mon_palette(&"totodile")
		&"load_charizard":
			# `Intro_LoadCharizardPalette`'s `hCGB` branch picks CYNDAQUIL and only
			# the DMG one picks CHARIZARD, so the colour version never sees
			# Charizard's own palette here.
			_load_mon_palette(&"cyndaquil")
		&"chikorita_appears":
			_spawn_starter(&"chikorita", Vector2i(1 * 8, 22 * 8))
		&"cyndaquil_appears":
			_spawn_starter(&"cyndaquil", Vector2i(20 * 8, 22 * 8))
		&"totodile_appears":
			_spawn_starter(&"totodile", Vector2i(1 * 8, 22 * 8))
		&"flash_mon":
			_obp0 = DMG_IDENTITY
			_obp1 = DMG_IDENTITY
			_bgp = 0x00
		&"flash_silhouette":
			_obp0 = DMG_OBJECT_HIDDEN
			_obp1 = DMG_OBJECT_HIDDEN
			_bgp = DMG_SILHOUETTE


## `Intro_LoadMonPalette`'s CGB branch, which is `LoadPalette_White_Col1_Col2_
## Black` over the object palettes. `GameData.palette` already expands a
## species' stored pair the same way, so it is the run this copies.
func _load_mon_palette(name: StringName) -> void:
	if _data == null:
		return
	var run: PackedColorArray = _data.palette(
		int((STARTERS[name] as Dictionary)["species"])
	)
	if run.size() < PALETTE_COLORS:
		return
	var packed := PackedInt32Array()
	for index: int in PALETTE_COLORS:
		var colour: Color = run[index]
		packed.append(
			int(round(colour.r * 31.0))
			| (int(round(colour.g * 31.0)) << 5)
			| (int(round(colour.b * 31.0)) << 10)
		)
	_set_palettes(_bg_palette, packed)


func _spawn_starter(name: StringName, at: Vector2i) -> void:
	_emit(&"play_sfx", {"sfx": SFX_GS_INTRO_POKEMON_APPEARS})
	var actor: Dictionary = _spawn(name, at)
	if not actor.is_empty():
		actor["vtile"] = int((STARTERS[name] as Dictionary)["vtile"])


## `Intro_AnimateFireball`: a fireball every fourth frame, with the screen
## sliding under it.
func _animate_fireball() -> void:
	var value: int = _counter2
	_counter2 = (_counter2 + 1) & 0xFF
	if value & 0x03 != 0:
		return
	_spawn(&"fireball", Vector2i(10 * 8 + 4, 12 * 8 + 4))
	_scx = (_scx - 1) & 0xFF
	_global_x = (_global_x + 1) & 0xFF


## `Intro_InitBubble`: one bubble every sixteenth frame, at the point the
## counter's own high nybble picks.
func _init_bubble() -> void:
	if _counter1 & 0x0F != 0:
		return
	_spawn(&"bubble", BUBBLE_AT[((_counter1 & 0x70) >> 4) % BUBBLE_AT.size()])


## `Intro_InitShellders`: three `depixel`s falling one into the next, so only the
## last reaches `.InitAnim` and the first two are spawned by the calls above it.
func _init_shellders() -> void:
	for at: Vector2i in SHELLDER_AT:
		_spawn(&"shellder", at)


## `Intro_InitMagikarps`: two alternating triples, gated by the counter through
## the `depixel 8, 7, 0, 7` pair the routine loads as a mask rather than a point.
func _init_magikarps() -> void:
	# `depixel 8, 7, 0, 7` is d = 8 * 8 + 0, e = 7 * 8 + 7, which the routine
	# uses as `and e` and `and d` rather than as a position.
	if _counter2 & 0x3F != 0:
		return
	var row: Array = MAGIKARP_AT[0 if _counter2 & 0x40 == 0 else 1]
	for at: Vector2i in row:
		_spawn(&"magikarp", at)


## `Intro_InitLapras`, which only fires on the thirty-second frame.
func _init_lapras() -> void:
	if _counter2 & 0x1F != 0:
		return
	_spawn(&"lapras", Vector2i(24 * 8, 16 * 8))


## `Intro_InitNote`: one note every sixty-fourth frame while the flag is clear,
## alternating between the visible and the invisible one.
func _init_note() -> void:
	if _sprite_flag:
		return
	if _counter2 & 0x3F != 0:
		return
	if _counter2 & 0x7F == 0:
		_spawn(&"invisible_note", Vector2i(6 * 8, 10 * 8 + 4))
		return
	_spawn(&"note", Vector2i(6 * 8, 11 * 8 + 4))


func _init_jigglypuff() -> void:
	_spawn(&"jigglypuff", Vector2i(6 * 8, 14 * 8))


func _init_pikachu() -> void:
	_spawn(&"pikachu", Vector2i(24 * 8, 14 * 8))
	_spawn(&"pikachu_tail", Vector2i(24 * 8, 14 * 8))


## `_InitSpriteAnimStruct`, which takes the first free slot. [param at] is the
## shadow-OAM pixel as (x, y), which is the order the struct stores.
func _spawn(object: StringName, at: Vector2i) -> Dictionary:
	var actor: Dictionary = {
		"object": object,
		"frameset": StringName((OBJECTS[object] as Dictionary)["frameset"]),
		"func": StringName((OBJECTS[object] as Dictionary)["func"]),
		"vtile": 0,
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
	var deleted: Array[Dictionary] = []
	for actor: Dictionary in _actors.duplicate():
		var alive: bool = true
		match StringName(actor["func"]):
			&"bubble":
				alive = _sprite_bubble(actor)
			&"shellder":
				alive = _sprite_shellder(actor)
			&"magikarp":
				alive = _sprite_magikarp(actor)
			&"lapras":
				alive = _sprite_lapras(actor)
			&"note":
				alive = _sprite_note(actor)
			&"jigglypuff":
				alive = _sprite_jigglypuff(actor)
			&"pikachu":
				alive = _sprite_pikachu(actor)
			&"pikachu_tail":
				alive = _sprite_pikachu_tail(actor)
			&"fireball":
				_sprite_fireball(actor)
			&"chikorita_totodile":
				_sprite_starter(actor, 0x30, 0x30)
			&"cyndaquil":
				_sprite_starter(actor, 0x30, 0x10)
		if not alive:
			deleted.append(actor)
	var kept: Array[Dictionary] = []
	for actor: Dictionary in _actors:
		if actor in deleted:
			continue
		if _advance_actor(actor):
			kept.append(actor)
	_actors = kept


## `AnimSeq_GSIntroBubble`: up one pixel a frame on a sine of amplitude 8, gone
## after $40 of them.
func _sprite_bubble(actor: Dictionary) -> bool:
	var value: int = int(actor["var2"])
	actor["var2"] = (value + 1) & 0xFF
	if value >= 0x40:
		return false
	actor["y_offset"] = (int(actor["y_offset"]) - 1) & 0xFF
	actor["var1"] = (int(actor["var1"]) + 2) & 0xFF
	actor["x_offset"] = _sine_at(int(actor["var1"]), 8)
	return true


## `AnimSeq_GSIntroShellder`: still, and deleted once the screen has risen far
## enough that its own y plus `wGlobalAnimYOffset` passes $b0.
func _sprite_shellder(actor: Dictionary) -> bool:
	return ((_global_y + int(actor["y"])) & 0xFF) < 0xB0


## `AnimSeq_GSIntroMagikarp`: right two pixels a frame on a sine of amplitude 8,
## gone once its offset passes $f0.
func _sprite_magikarp(actor: Dictionary) -> bool:
	if int(actor["jumptable"]) == 0:
		actor["jumptable"] = 1
		# `SPRITEANIMSTRUCT_INDEX and $3, swapped`, which is the slot's own place
		# in the triple turned into a starting angle.
		actor["var1"] = ((_actors.find(actor) & 0x03) << 4) & 0xFF
	var offset: int = int(actor["x_offset"])
	if offset >= 0xF0:
		return false
	actor["x_offset"] = (offset + 2) & 0xFF
	actor["var1"] = (int(actor["var1"]) + 1) & 0xFF
	actor["y_offset"] = _sine_at(int(actor["var1"]), 8)
	return true


## `AnimSeq_GSIntroLapras`: in from the right, a pause, then off to the left,
## bobbing on a sine of amplitude 4 throughout. Leaving sets
## `wIntroSpriteStateFlag`, which is what ends `IntroScene4`.
func _sprite_lapras(actor: Dictionary) -> bool:
	var odd: bool = _lapras_bob(actor)
	match int(actor["jumptable"]):
		0:
			if odd:
				return true
			if int(actor["x"]) < 0x58:
				actor["jumptable"] = 1
				actor["var2"] = 0xB0
				return true
			actor["x"] = (int(actor["x"]) - 1) & 0xFF
		1:
			if int(actor["var2"]) == 0:
				actor["jumptable"] = 2
				return true
			actor["var2"] = int(actor["var2"]) - 1
		_:
			if odd:
				return true
			if int(actor["x"]) == 0xD0:
				_sprite_flag = true
				return false
			actor["x"] = (int(actor["x"]) - 1) & 0xFF
	return true


## `.update_y_offset`, whose answer is the counter's low bit: the two moving
## branches only step on every other frame.
func _lapras_bob(actor: Dictionary) -> bool:
	var value: int = int(actor["var1"])
	actor["var1"] = (value + 1) & 0xFF
	actor["y_offset"] = _sine_at(value, 4)
	return value & 0x01 != 0


## `AnimSeq_GSIntroNote`: right one pixel a frame on a sine of amplitude 4, up
## one every fourth, gone once its offset passes $80.
func _sprite_note(actor: Dictionary) -> bool:
	if int(actor["jumptable"]) == 0:
		actor["jumptable"] = 1
		actor["var1"] = ((_actors.find(actor) & 0x01) << 5) & 0xFF
	var offset: int = int(actor["x_offset"])
	if offset >= 0x80:
		return false
	actor["x_offset"] = (offset + 1) & 0xFF
	actor["var1"] = (int(actor["var1"]) + 2) & 0xFF
	actor["y_offset"] = _sine_at(int(actor["var1"]), 4)
	if int(actor["var1"]) & 0x02 == 0:
		return true
	actor["y"] = (int(actor["y"]) - 1) & 0xFF
	return true


## `AnimSeq_GSIntroJigglypuff`: still until Pikachu's attack sets the flag, then
## off to the left two pixels a frame on its second frameset.
func _sprite_jigglypuff(actor: Dictionary) -> bool:
	if int(actor["jumptable"]) == 0:
		if not _sprite_flag:
			return true
		actor["jumptable"] = 1
		_reinit_frameset(actor, &"jigglypuff_2")
	if int(actor["x"]) == 0xD0:
		return false
	actor["x"] = (int(actor["x"]) - 2) & 0xFF
	return true


## `AnimSeq_GSIntroPikachu`: in to $80, a $30 wind-up, the attack on a sine of
## amplitude 4 down to $50, and then away. Reaching $50 sets the flag.
func _sprite_pikachu(actor: Dictionary) -> bool:
	match int(actor["jumptable"]):
		0:
			if int(actor["x"]) == 0x80:
				actor["jumptable"] = 1
				actor["var2"] = 0x30
				_reinit_frameset(actor, &"pikachu_2")
				return true
			actor["x"] = (int(actor["x"]) - 1) & 0xFF
		1:
			if int(actor["var2"]) == 0:
				actor["jumptable"] = 2
				_reinit_frameset(actor, &"pikachu_3")
				return true
			actor["var2"] = int(actor["var2"]) - 1
		2:
			actor["var1"] = (int(actor["var1"]) + 4) & 0xFF
			actor["y_offset"] = _sine_at(int(actor["var1"]), 4)
			if int(actor["x"]) == 0x50:
				_sprite_flag = true
				actor["jumptable"] = 3
				return true
			actor["x"] = (int(actor["x"]) - 4) & 0xFF
		_:
			if int(actor["x"]) == 0xD0:
				return false
			actor["x"] = (int(actor["x"]) - 2) & 0xFF
	return true


## `AnimSeq_GSIntroPikachuTail`: the same three stages, but the last one moves
## four pixels a frame until the flag is set and two after it, which is what
## makes the tail catch up.
func _sprite_pikachu_tail(actor: Dictionary) -> bool:
	match int(actor["jumptable"]):
		0:
			if int(actor["x"]) == 0x80:
				actor["jumptable"] = 1
				actor["var2"] = 0x30
				_reinit_frameset(actor, &"pikachu_tail_2")
				return true
			actor["x"] = (int(actor["x"]) - 1) & 0xFF
		1:
			var value: int = int(actor["var2"])
			if value == 0:
				actor["jumptable"] = 2
				return true
			actor["var2"] = value - 1
			if value == 0x20:
				_reinit_frameset(actor, &"pikachu_tail")
		_:
			actor["var1"] = (int(actor["var1"]) + 4) & 0xFF
			actor["y_offset"] = _sine_at(int(actor["var1"]), 4)
			if int(actor["x"]) == 0xD0:
				return false
			actor["x"] = (int(actor["x"]) - 2) & 0xFF
			if not _sprite_flag:
				actor["x"] = (int(actor["x"]) - 2) & 0xFF
	return true


## `AnimSeq_GSIntroFireball`: left four pixels a frame on a sine and cosine whose
## angle opens from the struct's own slot and whose amplitude grows eight a
## frame.
func _sprite_fireball(actor: Dictionary) -> void:
	if int(actor["jumptable"]) == 0:
		actor["jumptable"] = 1
		var slot: int = _actors.find(actor)
		actor["var1"] = (((slot & 0x04) << 1) + ((slot & 0x03) << 4)) & 0xFF
		return
	actor["x"] = (int(actor["x"]) - 4) & 0xFF
	var amplitude: int = int(actor["var2"])
	actor["var2"] = (amplitude + 8) & 0xFF
	var angle: int = int(actor["var1"])
	actor["y_offset"] = _sine_at(angle, amplitude)
	actor["x_offset"] = _cosine_at(angle, amplitude)


## `AnimSeq_GSIntroChikoritaTotodile` and `AnimSeq_GSIntroCyndaquil`, which are
## the same flash on two different opening angles.
func _sprite_starter(actor: Dictionary, first: int, second: int) -> void:
	if int(actor["jumptable"]) == 0:
		actor["jumptable"] = 1
		actor["var1"] = first
		actor["var2"] = second
		return
	var angle: int = int(actor["var1"])
	if angle >= 0x3C:
		return
	actor["var1"] = (angle + 2) & 0xFF
	actor["y_offset"] = _sine_at(actor["var1"], 0x90)
	var cosine: int = int(actor["var2"])
	actor["var2"] = (cosine + 2) & 0xFF
	actor["x_offset"] = _cosine_at(cosine, 0x90)


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
				# `oamend` winds back two and re-reads the last entry forever.
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


## `AnimSeqs_Sine`: a = d * sin(a * pi/32), read out of `BattleAnimSineWave`
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
