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
var _to_hp: int = 0
var _pixels: int = 0
var _target_pixels: int = 0
var _frames: int = 0


## The animation from [param from_hp] to [param to_hp]. A bar already at its
## destination is finished on arrival and never ticks.
static func create(from_hp: int, to_hp: int, max_hp: int) -> Gen2HpBarAnimation:
	var animation := Gen2HpBarAnimation.new()
	animation._max_hp = max_hp
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
## long branch prints as it steps real HP toward the target. The short branch
## back-computes with `ShortHPBar_CalcPixelFrame` instead, whose documented
## off-by-one for low HP is not reproduced; see the divergence note in
## `HANDOFF.md`. Only the number differs, never the bar.
func hp() -> int:
	if finished():
		return _to_hp
	if _max_hp <= 0:
		return 0
	if _pixels <= 0:
		return 0
	if _pixels >= LENGTH_PX:
		return _max_hp
	@warning_ignore("integer_division")
	var value: int = _pixels * _max_hp / LENGTH_PX
	return clampi(maxi(value, 1), 0, _max_hp)
