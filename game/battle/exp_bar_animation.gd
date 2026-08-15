class_name Gen2ExpBarAnimation
extends RefCounted

## The exp bar filling, one pixel at a time (`AnimateExpBar`,
## engine/battle/core.asm).
##
## Not the HP bar again: `.LoopLevels` fills to the end, raises the level and
## refills from empty (`ld c, $40`, then `ld b, $0`), so this is a list of
## segments, one per level crossed plus `.FinishExpBar`'s partial fill. Its text
## ordering is the opposite of the HP bar's: `Text_MonGainedExpPoint` is printed
## before `AnimateExpBar` and `BattleText_StringBuffer1GrewToLevel` inside the
## loop, after that segment has reached the end.
##
## The three guards Gold and Silver lack (`.NoOverflow`'s `$ffffff` clamp, the
## `cp e` after `CalcLevel`, `.LoopLevels`' `cp MAX_LEVEL`) are unreachable from
## a gain, so nothing here is profile split.

## `EXP_BAR_LENGTH * TILE_WIDTH`: `CalcExpBar` returns `$40 - b` over eight
## tiles.
const LENGTH_PX: int = Gen2BattleHud.EXP_BAR_TILES * Gen2BattleHud.TILE

## `.PlayExpBarSound`'s `ld c, 10`, spent before each segment moves. Its
## `SFX_EXP_BAR` is the Poof's boundary: no battle screen has an SFX route.
const LEAD_FRAMES: int = 10

## `.LoopBarAnimation`'s `ld d, 3` and its floor: 3, 3, 2, 2, 1, 1 and on at a
## frame a pixel. The load is inside the routine, so every segment starts slow.
const START_DELAY: int = 3
const MIN_DELAY: int = 1

## How many pixels each delay value is held for before it is decremented.
const STEPS_PER_DELAY: int = 2

## Where each segment ends: [constant LENGTH_PX] but for the last, a level
## boundary being the end of the bar.
var _targets: Array[int] = []
var _segment: int = 0
var _pixels: int = 0
var _lead: int = 0
var _delay: int = START_DELAY
var _held: int = 0
var _frames: int = 0
var _segment_ended: bool = false
## A boundary reached with the bar still full, cleared by the next first draw.
var _pending_reset: bool = false
## Stopped at a level boundary under the grew-to-level textbox.
var _paused: bool = false


## `CalcExpBar`: 64 minus the exp still owed, scaled over the span between the
## two levels. Scaling the exp already earned instead floors the other way and
## answers a pixel high wherever the division is inexact, which is most values.
static func pixels_for(growth_rate: int, level: int, exp_points: int) -> int:
	if level >= Gen2Experience.MAX_LEVEL:
		return LENGTH_PX

	var floor_exp: int = Gen2Experience.total_exp_at(growth_rate, level)
	var span: int = Gen2Experience.total_exp_at(growth_rate, level + 1) - floor_exp
	if span <= 0:
		return LENGTH_PX

	var remaining: int = clampi(floor_exp + span - exp_points, 0, span)
	@warning_ignore("integer_division")
	var owed: int = LENGTH_PX * remaining / span
	return clampi(LENGTH_PX - owed, 0, LENGTH_PX)


## A segment covering no distance is not skipped: `.LoopBarAnimation` draws and
## waits before it compares, so a gain too small to move a pixel still costs its
## lead and one delay. Only an empty [param targets] is finished on arrival.
static func create(from_pixels: int, targets: Array[int]) -> Gen2ExpBarAnimation:
	var animation := Gen2ExpBarAnimation.new()
	animation._pixels = clampi(from_pixels, 0, LENGTH_PX)
	for target: int in targets:
		animation._targets.append(clampi(target, 0, LENGTH_PX))
	if not animation.finished():
		animation._lead = LEAD_FRAMES
	return animation


func finished() -> bool:
	return _segment >= _targets.size()


func pixels() -> int:
	return _pixels


## A segment ended, which is a level boundary for all but the last and is what
## prints `.LoopLevels`' grew-to-level line.
func segment_finished() -> bool:
	return _segment_ended


## `.LoopLevels`' `StdBattleTextbox`, which blocks on a button before the loop
## reaches `.PlayExpBarSound` again.
func paused() -> bool:
	return _paused


## The press that dismisses that textbox and lets the next fill start.
func resume() -> void:
	if not _paused:
		return
	_paused = false
	_pending_reset = true
	_lead = LEAD_FRAMES
	_delay = START_DELAY
	_held = 0
	_frames = 0


## One hardware frame; whether the bar moved is what asks for a redraw.
func advance_frame() -> bool:
	_segment_ended = false
	if finished() or _paused:
		return false

	if _lead > 0:
		_lead -= 1
		if _lead > 0 or not _pending_reset:
			return false
			# `.LoopLevels`' `ld b, $0` is drawn by the next `.LoopBarAnimation`,
			# ten frames later, so the full bar stays up under the textbox and
			# empties on the new segment's first draw.
		_pending_reset = false
		_pixels = 0
		return true

	_frames += 1
	if _frames < _delay:
		return false
	_frames = 0

	var target: int = _targets[_segment]
	var moved: bool = _pixels != target
	if moved:
		_pixels += 1 if target > _pixels else -1

	_held += 1
	if _held >= STEPS_PER_DELAY:
		_held = 0
		_delay = maxi(_delay - 1, MIN_DELAY)

	if _pixels == target:
		_end_segment()
	return moved


## `.LoopLevels`' tail: the level goes up and its textbox blocks on a button, so
## the bar stops here full and [method resume] is that button.
func _end_segment() -> void:
	_segment_ended = true
	_segment += 1
	if not finished():
		_paused = true
