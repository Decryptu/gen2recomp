class_name Gen2HpBarAnimation
extends RefCounted

## The HP bar draining or filling, one pixel at a time
## (engine/battle/anim_hp_bar.asm).
##
## Scene-free like the rest of the battle layer: the screen ticks this once per
## hardware frame and draws [method pixels], and the bar arrives before the
## message that describes the hit is printed. That ordering is the source's, not
## a choice: `NormalHit` runs `applydamage` before `criticaltext` and
## `supereffectivetext`, and `DoEnemyDamage` ends with `predef AnimateHPBar`.
##
## `_AnimateHPBar` has two branches, keyed on whether the maximum is at least
## `HP_BAR_LENGTH_PX`: over it the loop steps real HP and redraws only when the
## pixel moves, under it the loop steps the pixel itself. Both redraw exactly one
## pixel per iteration, so both are one pixel per step here; what differs is only
## the HP *number* printed beside the bar, which [method hp] answers.

## `HP_BAR_LENGTH * TILE_WIDTH`, the bar's full width in pixels.
const LENGTH_PX: int = Gen2BattleHud.HP_BAR_TILES * Gen2BattleHud.TILE

## `HPBarAnim_BGMapUpdate` waits two frames per redraw, on both the DMG path and
## the CGB one: a battle bar is `wWhichHPBar` 0 or 1, which takes `.load_0` or
## `.load_1` into `.finish`'s two `DelayFrame`s.
const FRAMES_PER_STEP: int = 2

var _max_hp: int = 0
var _from_hp: int = 0
var _to_hp: int = 0
var _pixels: int = 0
var _target_pixels: int = 0
var _frames: int = 0


## The animation from [param from_hp] to [param to_hp]. A bar already at its
## destination is finished on arrival and never ticks.
static func create(from_hp: int, to_hp: int, max_hp: int) -> Gen2HpBarAnimation:
	var animation := Gen2HpBarAnimation.new()
	animation._max_hp = max_hp
	animation._from_hp = from_hp
	animation._to_hp = to_hp
	animation._pixels = Gen2BattleHud.bar_pixels(from_hp, max_hp, LENGTH_PX)
	animation._target_pixels = Gen2BattleHud.bar_pixels(to_hp, max_hp, LENGTH_PX)
	return animation


func finished() -> bool:
	return _pixels == _target_pixels


func pixels() -> int:
	return _pixels


## One hardware frame. Answers whether the bar moved, which is what tells the
## screen to redraw.
func advance_frame() -> bool:
	if finished():
		return false
	_frames += 1
	if _frames < FRAMES_PER_STEP:
		return false
	_frames = 0
	_pixels += 1 if _target_pixels > _pixels else -1
	return true


## The HP to print beside the bar while it moves, and the real value once it has
## arrived.
##
## Mid-animation this is the inverse of `ComputeHPBarPixels`, which is what the
## long branch prints as it steps real HP toward the target. The short branch is
## `ShortHPBar_CalcPixelFrame`'s own answer instead, whose off-by-one for low HP
## is switched by `short_hp_bar_number_off_by_one`. Only the number differs,
## never the bar.
func hp() -> int:
	if finished():
		return _to_hp
	if _max_hp <= 0:
		return 0
	if _pixels <= 0:
		return 0
	if _pixels >= LENGTH_PX:
		return _max_hp
	if _max_hp < LENGTH_PX:
		return _short_bar_hp()
	@warning_ignore("integer_division")
	var value: int = _pixels * _max_hp / LENGTH_PX
	return clampi(maxi(value, 1), 0, _max_hp)


## `ShortHPBar_CalcPixelFrame`, which is how a maximum under the bar's own width
## recovers an HP number from a pixel count: multiply, subtract the width until it
## borrows, then round with its `add hl, $80` and one more subtraction.
##
## Its loop subtracts before it tests, so an exact multiple of the width is
## counted and then rounded up again: one HP too many, which is
## `docs/bugs_and_glitches.md`'s "HP bar animation off-by-one error for low HP".
## pret's fix stops the loop on the zero, and the rounding then lands on the
## quotient itself. Everything else about the routine is the same either way.
##
## The answer is clamped to the two ends of this animation, which is the routine's
## own `wCurHPAnimLowHP`/`wCurHPAnimHighHP` comparison and is why the extra HP is
## invisible until the drain passes through an exact multiple.
func _short_bar_hp() -> int:
	var total: int = _max_hp * _pixels
	var counted: int = 0
	var rest: int = total
	while true:
		rest -= LENGTH_PX
		if rest < 0:
			break
		if rest == 0 and not Gen2Rules.hardware(&"short_hp_bar_number_off_by_one"):
			break
		counted += 1
	if rest + 0x80 - LENGTH_PX >= 0:
		counted += 1
	return clampi(counted, mini(_from_hp, _to_hp), maxi(_from_hp, _to_hp))
