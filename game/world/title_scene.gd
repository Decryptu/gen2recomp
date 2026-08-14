class_name Gen2TitleScene
extends RefCounted

## The title screen's own scene machine (`TitleScreenScene`,
## `engine/menus/intro_menu.asm`), one source frame at a time.
##
## Two screens under one name. Crystal opens on `TitleScreenEntrance`, which
## walks `hSCX` in from 112 while the crystal falls into place and the interlaced
## `wLYOverrides` pull the logo together; Gold and Silver have no entrance at all
## and go straight to the timer with a bird flying on its own sine.
##
## Scene-free: this owns the frames, the scroll, the sprites and the option the
## screen answers with. [Gen2TitlePage] owns the pixels and a host owns the
## device. What it never owns is the decision behind the answer: the caller reads
## [method selected_option] once [method finished] holds.

## `.scenes`. Crystal's table opens on the entrance and Gold and Silver's does
## not, so the phase is named rather than numbered here.
const SCENE_ENTRANCE: StringName = &"entrance"
const SCENE_TIMER: StringName = &"timer"
const SCENE_MAIN: StringName = &"main"
const SCENE_END: StringName = &"end"

## `TITLESCREENOPTION_*`, in the source's own const order. `RESTART` and
## `UNUSED` are reachable only from the main menu behind this screen.
const OPTION_MAIN_MENU: int = 0
const OPTION_DELETE_SAVE_DATA: int = 1
## `TitleScreenEnd`'s own answer once the timer has run out and the music has
## faded: `.dw`'s third entry is `IntroSequence`, so a screen nobody pressed
## starts the whole opening again.
const OPTION_RESTART: int = 2
const OPTION_RESET_CLOCK: int = 4

## `TitleScreenTimer`'s own `ld de`: 84 * 60 + 16 on Gold, 73 * 60 + 36 on
## Silver and on Crystal. A timer that runs out is the intro movie's cue.
const TIMER_GOLD: int = 84 * 60 + 16
const TIMER_DEFAULT: int = 73 * 60 + 36

## `TitleScreenEntrance`: `hSCX` starts at +112 and comes off four a frame, and
## `AnimateTitleCrystal` moves thirty sprites down two a frame until the first
## one's y reaches 6 + two tiles. Both take the same twenty-eight frames, which
## is why neither has to wait for the other.
const ENTRANCE_SCX: int = 112
const ENTRANCE_SCX_STEP: int = 4
## The interlaced band is the logo's height, and only its odd lines take the
## opposite sign.
const ENTRANCE_LINES: int = 8 * 10
const CRYSTAL_START_Y: int = -0x22
const CRYSTAL_END_Y: int = 6 + 2 * Gen2Tiles.TILE_HEIGHT
const CRYSTAL_STEP: int = 2

## `SuicuneFrameIterator`: the counter rises every frame and the frame it names
## changes on every eighth, walking `.Frames`' four bases.
const SUICUNE_FRAME_MASK: int = 0b111
const SUICUNE_FRAMES: Array[int] = [0x80, 0x88, 0x00, 0x08]
## `LoadSuicuneFrame` draws six rows of eight from whichever base it is handed.
const SUICUNE_COLUMNS: int = 8
const SUICUNE_ROWS: int = 6
const SUICUNE_AT := Vector2i(6, 12)
## `Decompress` puts the sheet at `vTiles4`, which is tile $80 of the bank the
## Suicune strip is read through, and a tile number is a byte: `.Frames`' last
## two bases are written as `vTiles5` $00 and $08 because $180 and $188 have
## wrapped. Subtracting the sheet's own start as a byte undoes both.
const SUICUNE_VRAM_FIRST_TILE: int = 0x80

## `InitializeBackground`: thirty 8x16 objects as five rows of six. Its
## `.InitColumn` keeps `d` for the whole run and walks `b` by eight, so what it
## calls a column is a row of sprites across; `d` rises by $10, one object's
## height, between them. The tile number steps by two throughout.
const CRYSTAL_ROWS: int = 5
const CRYSTAL_COLUMNS: int = 6
const CRYSTAL_ROW_STEP: int = 0x10
const CRYSTAL_FIRST_X: int = 0x40
const CRYSTAL_X_STEP: int = 8

## `depixel 12, 11`, the bird's own struct coordinate. `_InitSpriteAnimStruct`
## takes x in e and y in d, and `ldpixel` loads the first operand into the high
## byte, so the pair reads (y, x) however the macro's own comment names them.
const BIRD_AT := Vector2i(11 * Gen2Tiles.TILE_WIDTH, 12 * Gen2Tiles.TILE_HEIGHT)
## `AnimSeq_GSIntroHoOhLugia`: Gold counts its sine input up and scales by two,
## Silver counts down and scales by eight, and the answer is the y offset.
const BIRD_SINE_GOLD: int = 2
const BIRD_SINE_SILVER: int = 8

## `.Frameset_GSIntroHoOhLugia`, as [code](oam set, frames)[/code] pairs in each
## profile's own order. `oamframe X, n` lasts n + 1 frames and `oamrestart`
## takes the sequence back to the top, so both loop rather than settling.
const BIRD_FRAMESET_GOLD: Array[Vector2i] = [
	Vector2i(0, 11), Vector2i(1, 10), Vector2i(2, 11),
	Vector2i(3, 11), Vector2i(2, 10), Vector2i(4, 11),
]
const BIRD_FRAMESET_SILVER: Array[Vector2i] = [
	Vector2i(1, 4), Vector2i(0, 8), Vector2i(1, 8), Vector2i(2, 8),
	Vector2i(2, 8), Vector2i(3, 8), Vector2i(3, 8), Vector2i(2, 8),
	Vector2i(1, 4),
]

## `UpdateTitleTrailSprite`, which spawns a trail behind the bird on every
## fourth frame of the timer. Gold picks the spawn from `.TitleTrailCoords` by
## the bird's own frame and the timer's bit 2, and a row of zeroes means that
## frame drops no trail; Silver spawns from one fixed place.
const TRAIL_SPAWN_MASK: int = 0b11
const TRAIL_SPAWN_ALTERNATE: int = 0b100
## `dbpixel x, y, 4, 0` per entry, as (x, y) pixel pairs and (-1, -1) for the
## `trail_coords 0, 0` rows the routine returns on.
const TRAIL_COORDS_GOLD: Array[Array] = [
	[Vector2i(92, 80), Vector2i(-1, -1)],
	[Vector2i(92, 104), Vector2i(92, 88)],
	[Vector2i(92, 104), Vector2i(92, 120)],
	[Vector2i(92, 136), Vector2i(92, 120)],
	[Vector2i(-1, -1), Vector2i(92, 120)],
	[Vector2i(-1, -1), Vector2i(92, 88)],
]
## `depixel 15, 11, 4, 0`.
const TRAIL_AT_SILVER := Vector2i(88, 124)
## `AnimSeq_GSTitleTrail`: four pixels right a frame, gone once its x reaches
## $a4. The rest of it is two routines under one name. Only Gold's `.one` has the
## `inc [hl]` that walks the y coordinate down, and only Gold's `.zero` seeds
## VAR1 from the struct's own index and then reaches
## `AnimSeqs_IncAnonJumptableIndex`, so its sine is set up once and stepped by
## three a frame from there.
const TRAIL_X_STEP: int = 4
const TRAIL_Y_STEP: int = 1
const TRAIL_X_END: int = 0xA4
const TRAIL_SINE_STEP: int = 3
const TRAIL_SINE_AMPLITUDE: int = 2
## Silver's `.zero` runs every frame, and both numbers it wants come from
## `wIntroSceneTimer`, which the union at `wJumptableIndex + 2` gives to
## `LOW(wTitleScreenTimer)`: the byte the screen itself is counting down. Masked
## and swapped it is 0 to 3, which is an amplitude of 3 to 6 and a step of 7 to
## 10.
const TRAIL_SILVER_TIMER_MASK: int = 0x30
const TRAIL_SILVER_TIMER_SHIFT: int = 4
## `.Frameset_GSTitleTrail`, as (OAM set, duration) pairs. Gold alternates the
## two `spriteanimoam` vtiles and `oamrestart`s, so each picture is up for two
## frames; Silver holds the first and `oamend`s, which repeats it forever. A
## frame lasts its duration plus one, the way `GetSpriteAnimFrame` counts.
const TRAIL_FRAMESET_GOLD: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 1)]
const TRAIL_FRAMESET_SILVER: Array[Vector2i] = [Vector2i(0, 32)]
const TRAIL_SILVER_AMPLITUDE_BASE: int = 3
const TRAIL_SILVER_STEP_BASE: int = 7

## `ScrollTitleScreenClouds`: forty scanlines from line $5f take one shared
## offset that falls by one, on every eighth frame on Gold and on every frame on
## Silver.
const CLOUD_FIRST_LINE: int = 0x5F
const CLOUD_LINES: int = 0x28
const CLOUD_GOLD_MASK: int = 0b111

## `NUM_SPRITE_ANIM_STRUCTS`: `_InitSpriteAnimStruct` walks ten slots and returns
## carry rather than making an eleventh, so a burst of trails simply stops. The
## bird holds one of the ten for the whole screen's life, which leaves nine.
const MAX_SPRITE_STRUCTS: int = 10
const MAX_TRAILS: int = MAX_SPRITE_STRUCTS - 1

## What [method sprites] answers with.
const SPRITE_CRYSTAL: StringName = &"crystal"
const SPRITE_BIRD: StringName = &"bird"
const SPRITE_TRAIL: StringName = &"trail"

var _profile: StringName = &"gold"
var _scene: StringName = SCENE_TIMER
var _frame: int = 0
var _timer: int = 0
var _scx: int = 0
var _crystal_y: int = 0
var _suicune_counter: int = 0
var _bird_var: int = 0
var _bird_frame: int = 0
var _selected: int = -1
var _sine: Gen2BattleAnimData = null
## The live trail particles, each `{ at, var1, yoffset, fresh }`, capped the way
## `_InitSpriteAnimStruct` caps them. `fresh` is a struct that has not had a
## `PlaySpriteAnimations` pass yet: `UpdateTitleTrailSprite` spawns behind that
## call, so a new trail neither runs its `.zero` nor reaches shadow OAM until the
## next frame.
var _trails: Array[Dictionary] = []
## `wSpriteAnimCount`, which `_InitSpriteAnimStruct` raises on every spawn and
## which every struct keeps as its own `SPRITEANIMSTRUCT_INDEX`. `TitleScreen`
## spawns the bird before any trail, so the count opens at one.
var _anim_count: int = 1
var _cloud_scroll: int = 0


## [param sine] is `BattleAnimSineWave`, which the bird's own callback scales.
## Gold and Silver hold still without one rather than inventing a curve.
static func create(profile: StringName, sine: Gen2BattleAnimData = null) -> Gen2TitleScene:
	var out := Gen2TitleScene.new()
	out._profile = profile
	out._sine = sine
	out._scene = SCENE_ENTRANCE if profile == RomRegistry.CRYSTAL else SCENE_TIMER
	out._scx = ENTRANCE_SCX if profile == RomRegistry.CRYSTAL else 0
	out._crystal_y = CRYSTAL_START_Y & 0xFF
	return out


func profile() -> StringName:
	return _profile


func scene() -> StringName:
	return _scene


func frame() -> int:
	return _frame


func timer() -> int:
	return _timer


## `hSCX`, which only Crystal's entrance moves.
func scroll_x() -> int:
	return _scx


## `wLYOverrides`, one signed scroll per scanline, empty when nothing is
## overriding `hSCX`.
##
## Crystal's is `TitleScreenEntrance`: the logo's eighty lines take the scroll
## with the odd ones negated, which is the interlaced pull-together, and `.done`
## clears the pointer so nothing overrides after it. Gold and Silver's is
## `ScrollTitleScreenClouds`, forty lines of cloud walking left for the whole
## screen's life.
func line_offsets() -> PackedInt32Array:
	var out := PackedInt32Array()
	if _profile == RomRegistry.CRYSTAL:
		if _scene != SCENE_ENTRANCE or _scx == 0:
			return out
		for line: int in ENTRANCE_LINES:
			out.append(_scx if line % 2 == 0 else -_scx)
		return out
	out.resize(CLOUD_FIRST_LINE + CLOUD_LINES)
	out.fill(0)
	for index: int in CLOUD_LINES:
		out[CLOUD_FIRST_LINE + index] = _cloud_scroll
	return out


## Whether the screen has answered. The caller reads [method selected_option]
## and moves on: a timer that ran out answers nothing and is the intro movie's
## cue instead.
func finished() -> bool:
	return _scene == SCENE_END


## `wTitleScreenSelectedOption`, or -1 before the screen has answered.
func selected_option() -> int:
	return _selected


## One source frame. [param held] is the buttons down this frame, as
## [Gen2Button] values, since `GetJoypad`'s `hJoyDown` is what every branch here
## reads rather than a press.
func advance_frame(held: Array = []) -> void:
	if _scene == SCENE_END:
		return
	_frame += 1
	# `RunTitleScreen`'s own order: the clouds, then the scene, which is what
	# counts the timer down, then the sprites and the spawn behind them, both of
	# which read that timer after the count.
	_advance_clouds()
	match _scene:
		SCENE_ENTRANCE:
			_advance_entrance()
		SCENE_TIMER:
			# `TitleScreenTimer` spends a frame doing nothing but arming itself.
			_timer = TIMER_GOLD if _profile == RomRegistry.GOLD else TIMER_DEFAULT
			_scene = SCENE_MAIN
		SCENE_MAIN:
			_advance_main(held)
	_advance_animation()


## `SuicuneFrameIterator` and `AnimSeq_GSIntroHoOhLugia`, both of which run on
## every frame of every scene rather than inside one.
func _advance_animation() -> void:
	if _profile == RomRegistry.CRYSTAL:
		_suicune_counter = (_suicune_counter + 1) & 0xFF
		return
	# The struct's own VAR1, counted the way each profile counts it. A byte, so
	# Silver's countdown wraps rather than going negative.
	_bird_var = (_bird_var + (1 if _profile == RomRegistry.GOLD else -1)) & 0xFF
	_bird_frame += 1
	_advance_trails()


## `ScrollTitleScreenClouds`, whose `dec a` walks one shared offset off the left.
## Crystal's own loop has no clouds in it.
func _advance_clouds() -> void:
	if _profile == RomRegistry.CRYSTAL:
		return
	if _profile == RomRegistry.GOLD and (_frame & CLOUD_GOLD_MASK) != 0:
		return
	_cloud_scroll = (_cloud_scroll - 1) & 0xFF


## `AnimSeq_GSTitleTrail` over every live particle, then
## `UpdateTitleTrailSprite`'s own spawn. The move runs first because
## `PlaySpriteAnimations` does, and the spawn is the call behind it.
func _advance_trails() -> void:
	var alive: Array[Dictionary] = []
	for trail: Dictionary in _trails:
		if bool(trail["fresh"]):
			trail["fresh"] = false
			if _profile == RomRegistry.GOLD:
				# Gold's `.zero`: VAR1 is the struct's own index masked to two bits
				# and swapped, so four consecutive spawns open a quarter turn apart.
				trail["var1"] = (int(trail["index"]) & 0x3) << 4
		if _profile == RomRegistry.SILVER:
			# Silver's `.zero` runs ahead of the move on every frame, because it
			# never reaches `AnimSeqs_IncAnonJumptableIndex`.
			var scale: int = (_timer & TRAIL_SILVER_TIMER_MASK) >> TRAIL_SILVER_TIMER_SHIFT
			trail["var1"] = (
				int(trail["var1"]) + scale + TRAIL_SILVER_STEP_BASE
			) & 0xFF
			trail["yoffset"] = _lift(
				int(trail["var1"]), scale + TRAIL_SILVER_AMPLITUDE_BASE
			)
		var at: Vector2i = trail["at"]
		if at.x >= TRAIL_X_END:
			continue
		at.x += TRAIL_X_STEP
		if _profile == RomRegistry.GOLD:
			at.y = (at.y + TRAIL_Y_STEP) & 0xFF
			trail["var1"] = (int(trail["var1"]) + TRAIL_SINE_STEP) & 0xFF
			trail["yoffset"] = _lift(int(trail["var1"]), TRAIL_SINE_AMPLITUDE)
		trail["at"] = at
		_advance_trail_frameset(trail)
		alive.append(trail)
	_trails = alive
	if (_timer & TRAIL_SPAWN_MASK) != 0 or _trails.size() >= MAX_TRAILS:
		return
	var spawn: Vector2i = TRAIL_AT_SILVER
	if _profile == RomRegistry.GOLD:
		var row: Array = TRAIL_COORDS_GOLD[_bird_entry()]
		spawn = row[1 if (_timer & TRAIL_SPAWN_ALTERNATE) != 0 else 0]
		if spawn.x < 0:
			return
	# `_InitSpriteAnimStruct` steps `wSpriteAnimCount` past zero rather than
	# through it, so no struct is ever indexed nothing.
	_anim_count = (_anim_count + 1) & 0xFF
	if _anim_count == 0:
		_anim_count = 1
	_trails.append({
		"at": spawn, "var1": 0, "yoffset": 0, "fresh": true, "index": _anim_count,
		"set": 0, "frame": -1, "duration": 0,
	})


## `GetSpriteAnimFrame` for one trail. The counter starts at -1 and the duration
## is loaded on the pass that reads an entry, so an `oamframe X, n` is drawn
## n + 1 times; Gold `oamrestart`s to the first entry and Silver `oamend`s, which
## repeats the last for as long as the sprite is up.
func _advance_trail_frameset(trail: Dictionary) -> void:
	var frames: Array[Vector2i] = TRAIL_FRAMESET_GOLD if _profile == RomRegistry.GOLD \
		else TRAIL_FRAMESET_SILVER
	if int(trail["duration"]) > 0:
		trail["duration"] = int(trail["duration"]) - 1
		return
	var at: int = int(trail["frame"]) + 1
	if at >= frames.size():
		at = 0 if _profile == RomRegistry.GOLD else frames.size() - 1
	trail["frame"] = at
	trail["set"] = frames[at].x
	trail["duration"] = frames[at].y


## `AnimSeqs_Sine` over `BattleAnimSineWave`, as the byte `UpdateAnimFrame` adds
## to a coordinate. Zero without the table rather than an invented curve.
func _lift(a: int, amplitude: int) -> int:
	if _sine == null:
		return 0
	return Gen2BattleAnimFunctions.sine_of(_sine, a, amplitude)


## `TitleScreenEntrance`. Its `.done` is what starts the music and drops the
## window, and this is the frame the crystal stops falling on as well.
func _advance_entrance() -> void:
	if _scx == 0:
		_scene = SCENE_TIMER
		return
	_scx = maxi(_scx - ENTRANCE_SCX_STEP, 0)
	if _crystal_y != CRYSTAL_END_Y:
		_crystal_y = (_crystal_y + CRYSTAL_STEP) & 0xFF


## `TitleScreenMain`: the timer down a frame, then the three chords. The button
## checks run before the timer is looked at again, so the last frame of the
## count can still be answered.
func _advance_main(held: Array) -> void:
	if _timer <= 0:
		# `.end` into `TitleScreenEnd`, which fades the music out and then answers
		# RESTART: a screen nobody pressed runs the opening again.
		_answer(OPTION_RESTART)
		return
	_timer -= 1
	if _chord(held, [Gen2Button.UP, Gen2Button.B, Gen2Button.SELECT]):
		_answer(OPTION_DELETE_SAVE_DATA)
		return
	if _chord(held, [Gen2Button.DOWN, Gen2Button.B, Gen2Button.SELECT]):
		_answer(OPTION_RESET_CLOCK)
		return
	if held.has(Gen2Button.START) or held.has(Gen2Button.A):
		_answer(OPTION_MAIN_MENU)


func _answer(option: int) -> void:
	_selected = option
	_scene = SCENE_END


static func _chord(held: Array, buttons: Array) -> bool:
	for button: int in buttons:
		if not held.has(button):
			return false
	return true


## `LoadSuicuneFrame`'s own base for this frame, as a tile in the imported
## 256-tile strip. -1 on a profile with no Suicune.
func suicune_base() -> int:
	if _profile != RomRegistry.CRYSTAL:
		return -1
	var base: int = SUICUNE_FRAMES[(_suicune_counter >> 3) & 0x03]
	return (base - SUICUNE_VRAM_FIRST_TILE) & 0xFF


## Where `LoadSuicuneFrame` writes, and how much: six rows of eight tiles read
## straight out of the strip, sixteen apart because the sheet is 16 wide.
func suicune_tiles() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var base: int = suicune_base()
	if base < 0:
		return out
	for row: int in SUICUNE_ROWS:
		for column: int in SUICUNE_COLUMNS:
			out.append(Vector3i(
				SUICUNE_AT.x + column, SUICUNE_AT.y + row,
				base + row * SUICUNE_COLUMNS + column
			))
	return out


## The screen's objects for this frame, as
## [code]{ kind, at, tile, palette }[/code] in shadow-OAM coordinates. Crystal's
## thirty crystal parts, or Gold and Silver's bird and the trail behind it.
func sprites() -> Array[Dictionary]:
	if _profile == RomRegistry.CRYSTAL:
		return _crystal_sprites()
	return _bird_sprites()


## `InitializeBackground` and `AnimateTitleCrystal` together: the column of
## 8x16 objects as it stands this frame.
func _crystal_sprites() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tile: int = 0
	for row: int in CRYSTAL_ROWS:
		var y: int = (_crystal_y + row * CRYSTAL_ROW_STEP) & 0xFF
		var x: int = CRYSTAL_FIRST_X
		for _column: int in CRYSTAL_COLUMNS:
			# `0 | OAM_PRIO`: the crystal sits behind the logo and shows only
			# where the background is drawing its own colour 0.
			out.append({
				"kind": SPRITE_CRYSTAL, "at": Vector2i(x, y), "tile": tile,
				"palette": 0, "behind": true,
			})
			x = (x + CRYSTAL_X_STEP) & 0xFF
			tile += 2
	return out


## The bird's own frameset and the trail sprite under it. The y offset is
## `AnimSeqs_Sine` over `BattleAnimSineWave`, which is the same table every
## battle animation reads.
func _bird_sprites() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# `TitleScreen` spawns the bird into the first free slot and then copies the
	# struct into `wSpriteAnim10` and clears the first, so the bird holds the last
	# slot however late a trail is spawned: the trails are drawn first and the
	# bird over them.
	for trail: Dictionary in _trails:
		if bool(trail["fresh"]):
			continue
		var trail_at: Vector2i = trail["at"]
		out.append({
			"kind": SPRITE_TRAIL,
			"at": Vector2i(trail_at.x, (trail_at.y + int(trail["yoffset"])) & 0xFF),
			"tile": int(trail["set"]), "palette": 1,
		})

	var amplitude: int = BIRD_SINE_GOLD if _profile == RomRegistry.GOLD else BIRD_SINE_SILVER
	var offset: int = _lift(_bird_var, amplitude)
	# `UpdateAnimFrame` adds the offset to the coordinate as a byte, so a sprite
	# pushed past the screen wraps rather than clamping.
	out.append({
		"kind": SPRITE_BIRD,
		"at": Vector2i(BIRD_AT.x, (BIRD_AT.y + offset) & 0xFF),
		"tile": bird_frame(), "palette": 0,
	})
	return out


## Which of `.Frameset_GSIntroHoOhLugia`'s OAM sets is up. -1 on Crystal.
func bird_frame() -> int:
	if _profile == RomRegistry.CRYSTAL:
		return -1
	return int(_bird_frameset()[_bird_entry()].x)


## `SPRITEANIMSTRUCT_FRAME`, which is the entry of the frameset rather than the
## OAM set it names: Gold's list reaches set 2 twice, and `.TitleTrailCoords` is
## indexed by the entry, not by the picture.
func _bird_entry() -> int:
	var frameset: Array[Vector2i] = _bird_frameset()
	var total: int = 0
	for entry: Vector2i in frameset:
		total += entry.y
	if total <= 0:
		return 0
	var at: int = _bird_frame % total
	for index: int in frameset.size():
		if at < frameset[index].y:
			return index
		at -= frameset[index].y
	return 0


func _bird_frameset() -> Array[Vector2i]:
	if _profile == RomRegistry.GOLD:
		return BIRD_FRAMESET_GOLD
	return BIRD_FRAMESET_SILVER
