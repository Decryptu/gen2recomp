class_name Gen2GameFreakPresents
extends RefCounted

## `GameFreakPresentsScene` and the sprite animation beside it
## (`engine/movie/splash.asm`), which is the second half of `SplashScreen`.
##
## Two cartridges, two sequences. Crystal bounces a Ditto in on
## `BattleAnim_Sine_e`, waits, and fades its pink to orange as it turns into the
## logo; Gold and Silver throw a star that leaves the logo behind it, rotate
## `rOBP1` until the logo is yellow, and spray sparkles out of it. The words
## underneath are the same two `PlaceString`s on both, at different rows.
##
## Every frame here is a frame the cartridge spends. The scene jumptable and the
## sprite's own jumptable run in one `advance_frame()`, in the order that
## profile's loop calls them: Crystal's `.joy_loop` runs the scene and then
## `PlaySpriteAnimations`, Gold's `GameFreakPresentsFrame` the other way round.
##
## Scene-free: a host reads [method sprites], [method words] and
## [method fade_step] and draws them.

## `GameFreakLogoSpriteAnim`'s own jumptable, which is the Ditto's, and Gold's
## three objects. A host maps each onto the sheet it draws from.
const SPRITE_NONE: StringName = &""
const SPRITE_DITTO: StringName = &"ditto"
const SPRITE_LOGO: StringName = &"logo"
const SPRITE_STAR: StringName = &"star"
const SPRITE_SPARKLE: StringName = &"sparkle"

## `depixel 10, 11, 4, 0`, which both profiles use for the Ditto, the star and
## the logo, and `depixel 11, 11` for a sparkle. These are shadow-OAM
## coordinates, so a screen position is eight less across and sixteen less down.
const SPRITE_AT := Vector2i(88, 84)
const SPARKLE_AT := Vector2i(88, 88)

## `SFX_GAME_FREAK_LOGO_GS`, and Crystal's four.
const SFX_LOGO_GS: int = 0xAA
const SFX_DITTO_POP_UP: int = 0xC1
const SFX_DITTO_TRANSFORM: int = 0xC2
const SFX_DITTO_BOUNCE: int = 0xC7
const SFX_GAME_FREAK_PRESENTS: int = 0xC9

## `GameFreakPresentsEnd` on Crystal and `.finish` on Gold: the same
## `ld c, 16 / call DelayFrames` after the tilemap and the sprites are cleared.
const CLEANUP_FRAMES: int = 16

## The two `PlaceString`s. Crystal writes them with `CopyBytes` at (5,10) and
## (7,11); Gold places them a row lower at (5,12) and (7,13). The codes are the
## same tiles either way, counted from the first of `GameFreakLogoGFX`.
const WORD_GAME_FREAK: Array[int] = [0, 1, 2, 3, 13, 4, 5, 3, 1, 6]
const WORD_PRESENTS: Array[int] = [7, 8, 9, 10, 11, 12]
const WORD_AT_CRYSTAL: Array[Vector2i] = [Vector2i(5, 10), Vector2i(7, 11)]
const WORD_AT_GOLD: Array[Vector2i] = [Vector2i(5, 12), Vector2i(7, 13)]

## `OAM_YCOORD_HIDDEN`, which `GameFreakPresentsInit` parks the Ditto at until
## `GameFreakLogo_Bounce` writes a real offset.
const Y_HIDDEN: int = 160

## `.Frameset_GameFreakLogo`, as (OAM set, duration) pairs. A frame lasts its
## duration plus one, because `GetSpriteAnimFrame` returns the entry on the pass
## that loads the counter as well as on each pass that decrements it, and
## `oamend` repeats the last entry rather than stopping the sprite.
const DITTO_FRAMESET: Array[Vector2i] = [
	Vector2i(0, 12), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 4),
	Vector2i(0, 12), Vector2i(1, 12), Vector2i(2, 4), Vector2i(3, 32),
	Vector2i(4, 3), Vector2i(5, 3), Vector2i(6, 4), Vector2i(7, 4),
	Vector2i(8, 4), Vector2i(9, 10), Vector2i(10, 7),
]
## `.Frameset_GSGameFreakLogoStar`, whose second frame is the same picture
## flipped, and `.Frameset_GSGameFreakLogoSparkle`. Both `oamrestart`.
const STAR_FRAMESET: Array[Vector3i] = [Vector3i(0, 3, 0), Vector3i(0, 3, 1)]
const SPARKLE_FRAMESET: Array[Vector2i] = [
	Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(1, 2),
]
## `.Frameset_GameFreakLogo` on Gold, one entry that `oamend`s.
const GOLD_LOGO_FRAMESET: Array[Vector2i] = [Vector2i(0, 8)]

## `GameFreakPresents_Sparkle`'s `.sparkle_vectors`: an angle in sixty-fourths
## of a turn and a distance, sixteen entries the timer indexes.
const SPARKLE_VECTORS: Array[Vector2i] = [
	Vector2i(0x00, 3), Vector2i(0x08, 4), Vector2i(0x04, 3), Vector2i(0x0C, 2),
	Vector2i(0x10, 2), Vector2i(0x18, 3), Vector2i(0x14, 4), Vector2i(0x1C, 3),
	Vector2i(0x20, 2), Vector2i(0x28, 2), Vector2i(0x24, 3), Vector2i(0x2C, 4),
	Vector2i(0x30, 4), Vector2i(0x38, 3), Vector2i(0x34, 2), Vector2i(0x3C, 4),
]
## The sparkle's speed word falls by this much a frame and it is deleted when it
## reaches zero; its angle flips half a turn every frame, which is what makes one
## struct draw two sparks.
const SPARKLE_STEP: int = 0x10
const SPARKLE_HALF_TURN: int = 0x20

## `lb de, %00100100, %11111000`: d is `rOBP1` and e is `rOBP0`.
## `GameFreakPresents_UpdateLogoPal` rotates `rOBP1` two bits right every
## sixteenth frame until it reads `%10010000` and then leaves it alone.
const LOGO_REGISTER_FIRST: int = 0x24
const LOGO_REGISTER_LAST: int = 0x90
const LOGO_PALETTE_PERIOD: int = 0x10
## `DmgToCgbObjPals` reorders all eight object palettes by `rOBP0` alone, so the
## logo wears that order too until the first rotation reaches `DmgToCgbObjPal1`.
const OBJECT_PALETTE_ORDER: int = 0xF8

var _profile: StringName = &"gold"
var _sine: Gen2BattleAnimData = null

## `wJumptableIndex` and `wIntroSceneTimer`.
var _scene: int = 0
var _timer: int = 0
var _finished: bool = false
## `JUMPTABLE_EXIT_F` on Crystal and `SKIP_SPLASH_F` on Gold: both are read at
## the top of the loop, never where they are set.
var _exit: bool = false
var _cleanup: int = 0
var _frame: int = 0
var _words: int = 0
var _events: Array[Dictionary] = []

## `wIntroSceneFrameCounter`, which Gold's star sets on its way out and
## `GameFreakPresents_PlaceLogo` waits for.
var _star_done: bool = false

## One sprite-anim struct, of which the splash needs at most a Ditto or a star
## and a logo, plus Gold's sparkles.
var _actors: Array[Dictionary] = []
var _logo_register: int = LOGO_REGISTER_FIRST
var _logo_palette: int = OBJECT_PALETTE_ORDER


## [param sine] carries `BattleAnimSineWave`, which is the table both profiles'
## motion is read out of. Without one the sprites sit still and the frame counts
## are unchanged, so a caller with no animation layer still spends the right
## frames.
func start(profile: StringName, sine: Gen2BattleAnimData = null) -> void:
	_profile = profile
	_sine = sine
	_scene = 0
	_timer = 0
	_frame = 0
	_words = 0
	_finished = false
	_exit = false
	_cleanup = 0
	_star_done = false
	_logo_register = LOGO_REGISTER_FIRST
	_logo_palette = OBJECT_PALETTE_ORDER
	_actors.clear()
	_events.clear()
	if _is_crystal():
		# `GameFreakPresentsInit` puts the Ditto up before the loop starts,
		# parked off screen with its jump height and sine offset loaded.
		_actors.append({
			"kind": SPRITE_DITTO, "at": SPRITE_AT, "offset": Vector2i(0, Y_HIDDEN),
			"scene": 0, "var1": 96, "var2": 48, "frame": -1, "duration": 0,
			"set": 0, "flip_y": false,
		})


func profile() -> StringName:
	return _profile


func frame() -> int:
	return _frame


## `wJumptableIndex`, which is the scene the BG half is on.
func scene() -> int:
	return _scene


func finished() -> bool:
	return _finished


## How many of the two words are up: `GameFreakPresents_PlaceGameFreak` writes
## the first and `_PlacePresents` the second, and neither is ever taken down.
func words() -> int:
	return _words


func word_positions() -> Array[Vector2i]:
	return WORD_AT_CRYSTAL if _is_crystal() else WORD_AT_GOLD


## Every sprite the frame draws, as
## [code]{ kind, at, set, flip_y }[/code] in shadow-OAM coordinates.
func sprites() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for actor: Dictionary in _actors:
		if not bool(actor.get("visible", true)):
			continue
		out.append({
			"kind": actor["kind"],
			"at": _oam_at(actor["at"], actor["offset"]),
			"set": int(actor["set"]),
			"flip_y": bool(actor.get("flip_y", false)),
		})
	return out


## Which `GameFreakDittoPaletteFade` colour the Ditto is wearing, or -1 before
## `GameFreakLogo_Transform` has written one.
func fade_step() -> int:
	for actor: Dictionary in _actors:
		if actor["kind"] == SPRITE_DITTO:
			return int(actor.get("fade", -1))
	return -1


## The order object palette 1 reads PREDEFPAL_GAMEFREAK_LOGO_OB's four colours
## in, which is what turns Gold's logo yellow. Object palette 0, which the star
## and the sparkles are drawn through, keeps [constant OBJECT_PALETTE_ORDER].
func logo_palette() -> int:
	return _logo_palette


func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = _events.duplicate(true)
	_events.clear()
	return out


## One frame of the loop that owns this phase, sprites and scene both. Answers
## false once the sequence has finished, including the sixteen frames
## `GameFreakPresentsEnd` spends with the screen already cleared.
func advance_frame() -> bool:
	if _finished:
		return false
	_frame += 1
	# The exit bit is read at the top of the loop, so the frame that sets it
	# still runs and the clear happens on the one after it.
	if _cleanup == 0 and _exit:
		_enter_cleanup()
	if _cleanup > 0:
		_cleanup -= 1
		if _cleanup == 0:
			_finished = true
		return true
	if _is_crystal():
		_advance_scene()
		_advance_sprites()
	else:
		_advance_sprites()
		_advance_scene()
	return true


## The button `.joy_loop` reads. `PAD_BUTTONS` alone cancels the animation, and
## the cartridge then still spends `GameFreakPresentsEnd`'s sixteen frames.
func cancel() -> bool:
	if _finished or _exit:
		return false
	_exit = true
	return true


func _is_crystal() -> bool:
	return _profile == RomRegistry.CRYSTAL


func _enter_cleanup() -> void:
	_actors.clear()
	_words = 0
	_cleanup = CLEANUP_FRAMES
	_emit(&"clear", {})


func _advance_scene() -> void:
	if _is_crystal():
		_advance_crystal_scene()
	else:
		_advance_gold_scene()


## `GameFreakPresentsScene`'s four Crystal entries. Scene 0 does nothing at all:
## it waits for the sprite's own transform to call
## `GameFreakPresents_NextScene`, which is why the words only start once the
## Ditto has finished becoming the logo.
func _advance_crystal_scene() -> void:
	match _scene:
		0:
			pass
		1:
			if _timer < 32:
				_timer += 1
				return
			_timer = 0
			_words = 1
			_scene += 1
			_emit(&"play_sfx", {"sfx": SFX_GAME_FREAK_PRESENTS})
		2:
			if _timer < 64:
				_timer += 1
				return
			_timer = 0
			_words = 2
			_scene += 1
		3:
			if _timer < 128:
				_timer += 1
				return
			_exit = true


## `GameFreakPresentsScene`'s six Gold entries. The star is thrown first and the
## logo waits on `wIntroSceneFrameCounter`, which only the star's own animation
## sets, so the two are joined through the sprite layer rather than by a count.
func _advance_gold_scene() -> void:
	match _scene:
		0:
			_star_done = false
			_actors.append(_new_actor(SPRITE_STAR, SPRITE_AT, {"var1": 0x80, "angle": 0}))
			_emit(&"play_sfx", {"sfx": SFX_LOGO_GS})
			_scene += 1
		1:
			if not _star_done:
				return
			_actors.append(_new_actor(SPRITE_LOGO, SPRITE_AT, {}))
			_scene += 1
			_timer = 128
		2:
			if _timer == 0:
				_timer = 128
				_scene += 1
				return
			var was: int = _timer
			_timer -= 1
			if was == 63:
				_words = 1
			_spawn_sparkle(was)
		3:
			_words = 2
			_scene += 1
			_timer = 128
		4:
			if _timer == 0:
				_scene += 1
				return
			_timer -= 1
		5:
			_exit = true


## `GameFreakPresents_Sparkle`, which runs on every second frame of the timer
## and picks one of sixteen vectors by the half of it.
func _spawn_sparkle(timer: int) -> void:
	if timer & 1:
		return
	var vector: Vector2i = SPARKLE_VECTORS[(timer >> 1) & 0x0F]
	_actors.append(_new_actor(SPRITE_SPARKLE, SPARKLE_AT, {
		"angle": vector.x, "speed": vector.y << 8, "radius": 0,
	}))


func _new_actor(kind: StringName, at: Vector2i, extra: Dictionary) -> Dictionary:
	var actor: Dictionary = {
		"kind": kind, "at": at, "offset": Vector2i.ZERO,
		"scene": 0, "var1": 0, "var2": 0, "frame": -1, "duration": 0,
		"set": 0, "flip_y": false,
	}
	actor.merge(extra, true)
	return actor


## `DoNextFrameForAllSprites`, which runs each struct's own sequence and then
## advances its frameset.
func _advance_sprites() -> void:
	var live: Array[Dictionary] = []
	for actor: Dictionary in _actors:
		if not _advance_actor(actor):
			continue
		_advance_frameset(actor)
		live.append(actor)
	_actors = live


func _advance_actor(actor: Dictionary) -> bool:
	match StringName(actor["kind"]):
		SPRITE_DITTO:
			_advance_ditto(actor)
		SPRITE_STAR:
			return _advance_star(actor)
		SPRITE_SPARKLE:
			return _advance_sparkle(actor)
		SPRITE_LOGO:
			_advance_logo_palette()
	return true


## `GameFreakLogoSpriteAnim`'s five states: one to step past, the bounce, a wait,
## the transform and a stop.
func _advance_ditto(actor: Dictionary) -> void:
	match int(actor["scene"]):
		0:
			actor["scene"] = 1
		1:
			_advance_ditto_bounce(actor)
		2:
			# `GameFreakLogo_Ditto`: wait a little, then start transforming.
			if int(actor["var2"]) < 32:
				actor["var2"] = int(actor["var2"]) + 1
				return
			actor["scene"] = 3
			actor["var2"] = 0
			_emit(&"play_sfx", {"sfx": SFX_DITTO_TRANSFORM})
		3:
			_advance_ditto_transform(actor)
		4:
			pass


## `GameFreakLogo_Bounce`. The sine offset starts at 48, a quarter turn past the
## top, and is kept out of the wave's negative half so the Ditto never rises off
## the screen; every whole turn of it takes 48 off the jump height, which is two
## bounces from 96.
func _advance_ditto_bounce(actor: Dictionary) -> void:
	var height: int = int(actor["var1"])
	if height == 0:
		actor["scene"] = 2
		actor["var2"] = 0
		_emit(&"play_sfx", {"sfx": SFX_DITTO_POP_UP})
		return
	var offset: int = int(actor["var2"]) & 0x3F
	if offset < 0x20:
		offset += 0x20
	actor["offset"] = Vector2i(0, _sine_of(offset, height))
	var before: int = int(actor["var2"])
	actor["var2"] = (before - 1) & 0xFF
	if before & 0x1F:
		return
	actor["var1"] = (height - 48) & 0xFF
	_emit(&"play_sfx", {"sfx": SFX_DITTO_BOUNCE})


## `GameFreakLogo_Transform`: sixty-four frames, one `GameFreakDittoPaletteFade`
## colour every four, and then the scene the words are waiting on.
func _advance_ditto_transform(actor: Dictionary) -> void:
	var count: int = int(actor["var2"])
	if count == 64:
		actor["scene"] = 4
		_scene += 1
		return
	actor["var2"] = count + 1
	actor["fade"] = count >> 2


## `AnimSeq_GSGameFreakLogoStar`: `var1` falls by two a frame from $80 and is
## also the swing's amplitude, so the star spirals in; `var2` is how far its
## angle turns each frame and drops by one every whole turn of `var1`.
func _advance_star(actor: Dictionary) -> bool:
	var life: int = int(actor["var1"])
	if life == 0:
		_star_done = true
		return false
	actor["var1"] = life - 2
	if (life & 0x1F) == 0:
		actor["var2"] = (int(actor["var2"]) - 1) & 0xFF
	var angle: int = int(actor["angle"])
	actor["offset"] = Vector2i(_cosine_of(angle, life), _sine_of(angle, life))
	actor["angle"] = (angle + int(actor["var2"])) & 0xFF
	return true


## `AnimSeq_GSGameFreakLogoSparkle`: the speed word falls by $10 a frame and the
## radius accumulates it, so a spark slows as it goes out; the angle flips half a
## turn every frame, which is the second spark of the pair.
func _advance_sparkle(actor: Dictionary) -> bool:
	var speed: int = int(actor["speed"])
	if speed == 0:
		return false
	var angle: int = int(actor["angle"])
	var radius: int = (int(actor["radius"]) >> 8) & 0xFF
	actor["offset"] = Vector2i(_cosine_of(angle, radius), _sine_of(angle, radius))
	actor["radius"] = (int(actor["radius"]) + speed) & 0xFFFF
	actor["speed"] = (speed - SPARKLE_STEP) & 0xFFFF
	actor["angle"] = angle ^ SPARKLE_HALF_TURN
	return true


## `GameFreakPresents_UpdateLogoPal`, which rotates `rOBP1` two bits right every
## sixteenth frame of `wIntroSceneTimer` and leaves it alone once it is yellow.
func _advance_logo_palette() -> void:
	if _logo_register == LOGO_REGISTER_LAST or _timer % LOGO_PALETTE_PERIOD != 0:
		return
	_logo_register = ((_logo_register >> 2) | (_logo_register << 6)) & 0xFF
	_logo_palette = _logo_register


## `GetSpriteAnimFrame`. The frame counter starts at -1 and the duration is
## loaded on the pass that reads an entry, so an `oamframe X, n` is drawn n + 1
## times; `oamrestart` goes back to the first entry and `oamend` repeats the
## last one for as long as the sprite is up.
func _advance_frameset(actor: Dictionary) -> void:
	var frames: Array = _frameset_for(StringName(actor["kind"]))
	if frames.is_empty():
		return
	if int(actor["duration"]) > 0:
		actor["duration"] = int(actor["duration"]) - 1
		return
	var at: int = int(actor["frame"]) + 1
	if at >= frames.size():
		at = 0 if _frameset_restarts(StringName(actor["kind"])) else frames.size() - 1
	var entry: Variant = frames[at]
	actor["frame"] = at
	if entry is Vector3i:
		actor["set"] = (entry as Vector3i).x
		actor["duration"] = (entry as Vector3i).y
		actor["flip_y"] = (entry as Vector3i).z != 0
	else:
		actor["set"] = (entry as Vector2i).x
		actor["duration"] = (entry as Vector2i).y


func _frameset_for(kind: StringName) -> Array:
	match kind:
		SPRITE_DITTO:
			return DITTO_FRAMESET
		SPRITE_STAR:
			return STAR_FRAMESET
		SPRITE_SPARKLE:
			return SPARKLE_FRAMESET
		SPRITE_LOGO:
			return GOLD_LOGO_FRAMESET
	return []


func _frameset_restarts(kind: StringName) -> bool:
	return kind == SPRITE_STAR or kind == SPRITE_SPARKLE


## `BattleAnim_Sine_e` and its cosine, which the splash reads out of the same
## `sine_table 32` the battle animations do. The result is a byte and stays one:
## `UpdateAnimFrame` adds it to the struct's coordinate with `add`, so an offset
## past the screen wraps rather than clamping, and a Ditto at the top of its
## first jump is genuinely not drawn.
func _sine_of(a: int, d: int) -> int:
	if _sine == null:
		return 0
	return Gen2BattleAnimFunctions.sine_of(_sine, a, d)


func _cosine_of(a: int, d: int) -> int:
	if _sine == null:
		return 0
	return Gen2BattleAnimFunctions.cosine_of(_sine, a, d)


## The shadow-OAM coordinate a struct's own offset puts it at, added as the
## cartridge adds it.
static func _oam_at(base: Vector2i, offset: Vector2i) -> Vector2i:
	return Vector2i((base.x + offset.x) & 0xFF, (base.y + offset.y) & 0xFF)


func _emit(type: StringName, values: Dictionary) -> void:
	var event: Dictionary = {"type": type, "frame": _frame, "scene": _scene}
	event.merge(values, true)
	_events.append(event)
