class_name Gen2TitleScene
extends RefCounted

## `TitleScreenScene` (`engine/menus/intro_menu.asm`), one source frame at a
## time. Two screens under one name: Crystal opens on `TitleScreenEntrance`,
## walking `hSCX` in from 112 while the crystal falls and the interlaced
## `wLYOverrides` pull the logo together, and Gold and Silver go straight to the
## timer with a bird on its own sine.
##
## Scene-free: the frames, the scroll, the sprites and the answer. The pixels are
## [Gen2TitlePage]'s and the caller reads [method selected_option] once
## [method finished] holds.

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

## `TitleScreenEntrance`: `hSCX` from +112 off four a frame, and
## `AnimateTitleCrystal` thirty sprites down two a frame until the first's y
## reaches 6 + two tiles. Both take the same twenty-eight frames.
const ENTRANCE_SCX: int = 112
const ENTRANCE_SCX_STEP: int = 4
## The interlaced band is the logo's height, and only its odd lines take the
## opposite sign.
const ENTRANCE_LINES: int = 8 * 10
## `_TitleScreen`'s own `ld a, 8 / ldh [hSCY]`, which Gold and Silver's zeroes
## instead: Crystal's whole background sits eight pixels up the BG map.
const CRYSTAL_SCY: int = 8
## `hWY`. `_TitleScreen` parks the copyright window off the bottom at -112 and
## `TitleScreenEntrance.done` brings it to $88, which is the one row of
## `vBGMap1` the screen ever shows.
const WINDOW_OFF_Y: int = 144
const WINDOW_Y: int = 0x88
const CRYSTAL_START_Y: int = -0x22
const CRYSTAL_END_Y: int = 6 + 2 * Gen2Tiles.TILE_HEIGHT
const CRYSTAL_STEP: int = 2

## `SuicuneFrameIterator`: the counter rises every frame and the frame it names
## changes on every eighth, walking `.Frames`' four bases.
const SUICUNE_FRAME_MASK: int = 0b111
const SUICUNE_FRAMES: Array[int] = [0x80, 0x88, 0x00, 0x08]
## `_TitleScreen`'s own `ld d, $0`, which is the strip the screen opens on
## before the iterator has re-pointed it once.
const SUICUNE_FIRST_BASE: int = 0x00
## `LoadSuicuneFrame` draws six rows of eight from whichever base it is handed.
## Its `d` rises by one per column and eight more at the row's end, so a row
## starts sixteen past the one above: the sheet is 16 wide, half of it on screen.
const SUICUNE_COLUMNS: int = 8
const SUICUNE_ROW_STRIDE: int = 16
const SUICUNE_ROWS: int = 6
const SUICUNE_AT := Vector2i(6, 12)
## `Decompress` puts the sheet at `vTiles4`, tile $80 of its bank, and a tile
## number is a byte: `.Frames`' last two bases read `vTiles5` $00 and $08 because
## $180 and $188 wrapped. Subtracting the sheet's start as a byte undoes both.
const SUICUNE_VRAM_FIRST_TILE: int = 0x80

## `InitializeBackground`: thirty 8x16 objects as five rows of six. `.InitColumn`
## keeps `d` and walks `b` by eight, so its "column" is a row across; `d` rises
## by $10, one object's height, between them, and the tile number steps by two.
const CRYSTAL_ROWS: int = 5
const CRYSTAL_COLUMNS: int = 6
const CRYSTAL_ROW_STEP: int = 0x10
const CRYSTAL_FIRST_X: int = 0x40
const CRYSTAL_X_STEP: int = 8

## `depixel 12, 11`, the bird's struct coordinate. `_InitSpriteAnimStruct` takes
## x in e and y in d and `ldpixel` loads the first operand high, so it is (y, x).
const BIRD_AT := Vector2i(11 * Gen2Tiles.TILE_WIDTH, 12 * Gen2Tiles.TILE_HEIGHT)
## `AnimSeq_GSIntroHoOhLugia`: Gold counts its sine input up and scales by two,
## Silver counts down and scales by eight, and the answer is the y offset.
const BIRD_SINE_GOLD: int = 2
const BIRD_SINE_SILVER: int = 8

## `.Frameset_GSIntroHoOhLugia` as (OAM set, duration) pairs per profile, the
## same shape as [constant TRAIL_FRAMESET_GOLD]: a frame lasts its duration plus
## one, and `oamrestart` loops rather than ending.
const BIRD_FRAMESET_GOLD: Array[Vector2i] = [
	Vector2i(0, 10), Vector2i(1, 9), Vector2i(2, 10),
	Vector2i(3, 10), Vector2i(2, 9), Vector2i(4, 10),
]
const BIRD_FRAMESET_SILVER: Array[Vector2i] = [
	Vector2i(1, 3), Vector2i(0, 7), Vector2i(1, 7), Vector2i(2, 7),
	Vector2i(2, 7), Vector2i(3, 7), Vector2i(3, 7), Vector2i(2, 7),
	Vector2i(1, 3),
]

## `UpdateTitleTrailSprite`, a trail every fourth frame of the timer. Gold picks
## from `.TitleTrailCoords` by the bird's frame and the timer's bit 2, a row of
## zeroes dropping none; Silver spawns from one fixed place.
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
## `AnimSeq_GSTitleTrail`: four pixels right a frame, gone at x $a4. Two routines
## under one name past that. Only Gold's `.one` has the `inc [hl]` walking y
## down, and only Gold's `.zero` seeds VAR1 from the struct's index and reaches
## `AnimSeqs_IncAnonJumptableIndex`, so its sine is set up once then stepped by
## three.
const TRAIL_X_STEP: int = 4
const TRAIL_Y_STEP: int = 1
const TRAIL_X_END: int = 0xA4
const TRAIL_SINE_STEP: int = 3
const TRAIL_SINE_AMPLITUDE: int = 2
## Silver's `.zero` runs every frame and takes both numbers from
## `wIntroSceneTimer`, which the union at `wJumptableIndex + 2` gives to
## `LOW(wTitleScreenTimer)`, the byte the screen counts down. Masked and swapped
## it is 0 to 3: an amplitude of 3 to 6 and a step of 7 to 10.
const TRAIL_SILVER_TIMER_MASK: int = 0x30
const TRAIL_SILVER_TIMER_SHIFT: int = 4
## `.Frameset_GSTitleTrail` as (OAM set, duration) pairs. Gold alternates two
## `spriteanimoam` vtiles and `oamrestart`s; Silver holds the first and `oamend`s,
## repeating it forever. A frame lasts its duration plus one.
const TRAIL_FRAMESET_GOLD: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 1)]
const TRAIL_FRAMESET_SILVER: Array[Vector2i] = [Vector2i(0, 32)]
const TRAIL_SILVER_AMPLITUDE_BASE: int = 3
const TRAIL_SILVER_STEP_BASE: int = 7

## `ScrollTitleScreenClouds`: forty scanlines from $5f share one falling offset,
## stepped every eighth frame on Gold and every frame on Silver.
const CLOUD_FIRST_LINE: int = 0x5F
const CLOUD_LINES: int = 0x28
const CLOUD_GOLD_MASK: int = 0b111

## `_InitSpriteAnimStruct` walks ten slots and returns carry rather than making
## an eleventh. The bird holds one for the screen's life, leaving nine.
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
## `LoadSuicuneFrame`'s live base, re-pointed by the iterator rather than derived
## by the page: the counter is read before it is raised, so the write lands late.
var _suicune_base: int = SUICUNE_FIRST_BASE
var _bird_var: int = 0
## `SPRITEANIMSTRUCT_FRAME` and `..._DURATION` for the bird's own struct, and
## the frame counter opens at 0 rather than `_InitSpriteAnimStruct`'s -1.
## `_TitleScreen` copies the spawned struct into `wSpriteAnim10` with
## `ld bc, NUM_SPRITE_ANIM_STRUCTS`, which is ten bytes where the struct is
## sixteen, so the six fields from `..._FRAME` up are never copied. They are the
## zeroes `ClearSpriteAnims` left, that routine having wiped the whole of
## `wSpriteAnimData` at the top of `_TitleScreen`, so the values are the
## cartridge's on every entry rather than boot-time WRAM. The one visible
## consequence is `GetSpriteAnimFrame`'s `inc [hl]`: entry 0 is skipped on the
## first pass, and `oamrestart` writes -1, so every later cycle plays it.
var _bird_frame: int = 0
var _bird_duration: int = 0
var _bird_set: int = 0
var _selected: int = -1
var _sine: Gen2BattleAnimData = null
## Live particles as `{ at, var1, yoffset, fresh }`, capped the way
## `_InitSpriteAnimStruct` caps them. `fresh` is a struct with no
## `PlaySpriteAnimations` pass yet: `UpdateTitleTrailSprite` spawns behind that
## call, so a new trail neither runs `.zero` nor reaches OAM until next frame.
var _trails: Array[Dictionary] = []
## `wSpriteAnimCount`, raised on every spawn and kept as each struct's
## `SPRITEANIMSTRUCT_INDEX`. The bird is spawned first, so it opens at one.
var _anim_count: int = 1
var _cloud_scroll: int = 0


## [param sine] is `BattleAnimSineWave`, which the bird's own callback scales.
## Gold and Silver hold still without one rather than inventing a curve.
static func create(profile_name: StringName, sine: Gen2BattleAnimData = null) -> Gen2TitleScene:
	var out := Gen2TitleScene.new()
	out._profile = profile_name
	out._sine = sine
	out._scene = SCENE_ENTRANCE if profile_name == RomRegistry.CRYSTAL else SCENE_TIMER
	out._scx = ENTRANCE_SCX if profile_name == RomRegistry.CRYSTAL else 0
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


## `hSCY`, a constant on each profile.
func scroll_y() -> int:
	return CRYSTAL_SCY if _profile == RomRegistry.CRYSTAL else 0


## `hWY`: the row the copyright window starts on, or off the bottom of the
## screen while it is parked there. Gold and Silver draw no window at all.
func window_y() -> int:
	if _profile != RomRegistry.CRYSTAL or _scene == SCENE_ENTRANCE:
		return WINDOW_OFF_Y
	return WINDOW_Y


## `wLYOverrides`, one signed scroll per scanline, empty when nothing overrides
## `hSCX`. Crystal's is `TitleScreenEntrance`: the logo's eighty lines take the
## scroll with the odd ones negated, the interlaced pull-together, and `.done`
## clears the pointer. Gold and Silver's is `ScrollTitleScreenClouds`, forty
## lines walking left for the screen's whole life.
func line_offsets() -> PackedInt32Array:
	var out := PackedInt32Array()
	if _profile == RomRegistry.CRYSTAL:
		if _scene != SCENE_ENTRANCE or _scx == 0:
			return out
		# `wLYOverrides` is read live rather than copied at VBlank, so the screen
		# this state's sprites reach carries the *next* pass's fill:
		# `TitleScreenEntrance` writes it before the frame it opened is drawn.
		var scx: int = _scx - ENTRANCE_SCX_STEP
		# Only the logo's eighty lines are written; `_TitleScreen` zeroed the
		# rest, so the strip below it stands still while the logo comes in.
		out.resize(Gen2Screen.HEIGHT)
		out.fill(0)
		for line: int in ENTRANCE_LINES:
			out[line] = scx if line % 2 == 0 else -scx
		return out
	out.resize(CLOUD_FIRST_LINE + CLOUD_LINES)
	out.fill(0)
	for index: int in CLOUD_LINES:
		out[CLOUD_FIRST_LINE + index] = _cloud_scroll
	return out


## Whether the screen has answered. A timer that ran out answers nothing and is
## the intro movie's cue instead.
func finished() -> bool:
	return _scene == SCENE_END


## `wTitleScreenSelectedOption`, or -1 before the screen has answered.
func selected_option() -> int:
	return _selected


## One source frame. [param held] is the buttons down, since every branch here
## reads `GetJoypad`'s `hJoyDown` rather than a press.
func advance_frame(held: Array = []) -> void:
	if _scene == SCENE_END:
		return
	_frame += 1
	# `RunTitleScreen`'s order: clouds, then the scene that counts the timer
	# down, then the sprites and the spawn, both of which read it after.
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
		var value: int = _suicune_counter
		_suicune_counter = (value + 1) & 0xFF
		if value & SUICUNE_FRAME_MASK == 0:
			_suicune_base = SUICUNE_FRAMES[(value >> 3) & 0x03]
		return
	# The struct's own VAR1, counted the way each profile counts it. A byte, so
	# Silver's countdown wraps rather than going negative.
	_bird_var = (_bird_var + (1 if _profile == RomRegistry.GOLD else -1)) & 0xFF
	var bird: Dictionary = {
		"frame": _bird_frame, "duration": _bird_duration, "set": _bird_set,
	}
	_advance_frameset(bird, _bird_frameset(), true)
	_bird_frame = int(bird["frame"])
	_bird_duration = int(bird["duration"])
	_bird_set = int(bird["set"])
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
## `UpdateTitleTrailSprite`'s spawn, which is the call behind it.
func _advance_trails() -> void:
	var alive: Array[Dictionary] = []
	for trail: Dictionary in _trails:
		if bool(trail["dead"]):
			# `DeinitializeSprite` cleared the index on the pass before this one,
			# so `.loop`'s `and a` skips the struct and nothing draws it again.
			continue
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
			# `DoNextFrameForAllSprites` calls `UpdateAnimFrame` whatever the
			# animation did, so `.delete`'s `DeinitializeSprite` does not take the
			# sprite off this frame: the struct is drawn once more where it
			# stands, and the frameset it is drawn through steps as usual.
			trail["dead"] = true
			_advance_trail_frameset(trail)
			alive.append(trail)
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
	# A struct deleted on this pass has already released its slot, so it is not
	# one of the ten `_InitSpriteAnimStruct` walks even though it is still drawn.
	var live: int = 0
	for trail: Dictionary in _trails:
		if not bool(trail["dead"]):
			live += 1
	if (_timer & TRAIL_SPAWN_MASK) != 0 or live >= MAX_TRAILS:
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
		"at": spawn, "var1": 0, "yoffset": 0, "fresh": true, "dead": false,
		"index": _anim_count, "set": 0, "frame": -1, "duration": 0,
	})


## `GetSpriteAnimFrame` for one struct, [param state] carrying its `frame`,
## `duration` and `set`. The duration loads on the pass that reads an entry, so
## `oamframe X, n` is drawn n + 1 times; [param restarts] is `oamrestart` and
## the other end is `oamend`, whose `.repeat_last` holds the last entry.
func _advance_frameset(
	state: Dictionary, frames: Array[Vector2i], restarts: bool
) -> void:
	if int(state["duration"]) > 0:
		state["duration"] = int(state["duration"]) - 1
		return
	var at: int = int(state["frame"]) + 1
	if at >= frames.size():
		at = 0 if restarts else frames.size() - 1
	state["frame"] = at
	state["set"] = frames[at].x
	state["duration"] = frames[at].y


## The trails' own frameset, which Gold `oamrestart`s and Silver `oamend`s.
func _advance_trail_frameset(trail: Dictionary) -> void:
	_advance_frameset(
		trail,
		TRAIL_FRAMESET_GOLD if _profile == RomRegistry.GOLD else TRAIL_FRAMESET_SILVER,
		_profile == RomRegistry.GOLD
	)


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


## `TitleScreenMain`: the timer down a frame, then the three chords. The buttons
## are checked before the timer is looked at again, so its last frame answers.
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
	return (_suicune_base - SUICUNE_VRAM_FIRST_TILE) & 0xFF


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
				base + row * SUICUNE_ROW_STRIDE + column
			))
	return out


## [code]{ kind, at, tile, palette }[/code] in shadow-OAM coordinates: Crystal's
## thirty crystal parts, or the bird and its trail.
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


## The bird's frameset and the trail under it. The y offset is `AnimSeqs_Sine`
## over `BattleAnimSineWave`, the table every battle animation reads.
func _bird_sprites() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# `TitleScreen` spawns the bird into the first free slot, copies the struct
	# into `wSpriteAnim10` and clears the first, so the bird holds the last slot
	# however late a trail is spawned and is drawn over them.
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
	return _bird_set


## `SPRITEANIMSTRUCT_FRAME` is the frameset entry, not the OAM set it names:
## Gold's list reaches set 2 twice and `.TitleTrailCoords` indexes the entry.
func _bird_entry() -> int:
	return _bird_frame


func _bird_frameset() -> Array[Vector2i]:
	if _profile == RomRegistry.GOLD:
		return BIRD_FRAMESET_GOLD
	return BIRD_FRAMESET_SILVER
