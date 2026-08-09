class_name Gen2ExpBarAnimation
extends RefCounted

## The exp bar filling, one pixel at a time (`AnimateExpBar`,
## engine/battle/core.asm).
##
## Scene-free like the rest of the battle layer: the screen ticks this once per
## hardware frame and draws [method fraction].
##
## It is not the HP bar again. `AnimateExpBar` walks over level boundaries
## rather than between two values: the bar fills to the end, the level goes up,
## and it refills from empty, which is what `.LoopLevels` does with `ld c, $40`
## and then `ld b, $0` before it loops. So this is a list of segments, one per
## level crossed plus the final partial fill `.FinishExpBar` computes.
##
## Its ordering against the text is the source's too, and it is the opposite of
## the HP bar's on the way in: `Text_MonGainedExpPoint` is printed before
## `call AnimateExpBar`, while `BattleText_StringBuffer1GrewToLevel` is printed
## inside `.LoopLevels` after that level's segment has reached the end.
##
## The whole routine is byte identical between the pins but for three guards
## Gold and Silver lack: the `$ffffff` exp clamp in `.NoOverflow`, the `cp e`
## downward clamp after `CalcLevel`, and `.LoopLevels`' own `cp MAX_LEVEL`.
## Crystal's top-of-routine level check is `cp MAX_LEVEL` / `jp nc` against
## pokegold's `jp z`. None of them is reachable from a gain: a level only rises
## and [method Gen2Experience.level_for_exp] stops at `MAX_LEVEL`, so nothing
## here is profile split.

## `EXP_BAR_LENGTH * TILE_WIDTH`, the bar's full width in pixels. `CalcExpBar`
## multiplies by 64 and returns `$40 - b`; `PlaceExpBar` draws eight tiles.
const LENGTH_PX: int = Gen2BattleHud.EXP_BAR_TILES * Gen2BattleHud.TILE

## `.PlayExpBarSound`'s `ld c, 10` / `call DelayFrames`, spent before each
## segment starts moving. The `SFX_EXP_BAR` beside it is the same boundary the
## Poof's `SFX_SWITCH_POKEMON` is: no battle screen has an SFX route.
const LEAD_FRAMES: int = 10

## `.LoopBarAnimation`'s `ld d, 3`, and its floor. The delay is spent twice per
## value and then decremented, so a segment paces 3, 3, 2, 2, 1, 1, 1, 1 and on
## at one frame a pixel. `ld d, 3` is inside the routine, which is called once
## per segment, so every segment starts slow again.
const START_DELAY: int = 3
const MIN_DELAY: int = 1

## How many pixels each delay value is held for before it is decremented.
const STEPS_PER_DELAY: int = 2

## Where each segment ends, in pixels. All but the last are [constant LENGTH_PX],
## since a level boundary is reached at the end of the bar.
var _targets: Array[int] = []
var _segment: int = 0
var _pixels: int = 0
var _lead: int = 0
var _delay: int = START_DELAY
var _held: int = 0
var _frames: int = 0
var _segment_ended: bool = false
## Set when a level boundary has been reached and the bar is still showing it
## full, cleared by the next segment's first draw.
var _pending_reset: bool = false
## Stopped at a level boundary under the grew-to-level textbox.
var _paused: bool = false


## The bar's own pixel count for [param exp_points] at [param level], which is
## `CalcExpBar`: 64 minus the exp still owed to the next level, scaled over the
## span between the two levels.
##
## The subtraction is on that side on purpose. Scaling the exp already earned
## instead floors the other way and answers one pixel high wherever the division
## is inexact, which is most values.
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


## The walk from [param from_pixels] over [param targets], each of which is
## where one segment ends.
##
## A segment that covers no distance is not skipped: `.LoopBarAnimation` draws
## and waits before it compares, so a gain too small to move a pixel still costs
## its lead and one delay, exactly as it does on the cartridge. Only an empty
## [param targets] is finished on arrival.
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


## Whether the last [method advance_frame] ended a segment, which is a level
## boundary for every segment but the last. It is what prints the grew-to-level
## line `.LoopLevels` prints once the bar has reached the end.
func segment_finished() -> bool:
	return _segment_ended


## Whether the bar is stopped at a level boundary waiting to be let go, which is
## `.LoopLevels`' own `StdBattleTextbox`: that textbox blocks on a button before
## the loop reaches `.PlayExpBarSound` again.
func paused() -> bool:
	return _paused


## The press that dismisses the grew-to-level textbox, which is what lets
## `.LoopLevels` run on into the next level's fill.
func resume() -> void:
	if not _paused:
		return
	_paused = false
	_pending_reset = true
	_lead = LEAD_FRAMES
	_delay = START_DELAY
	_held = 0
	_frames = 0


## One hardware frame. Answers whether the bar moved, which is what tells the
## screen to redraw.
func advance_frame() -> bool:
	_segment_ended = false
	if finished() or _paused:
		return false

	if _lead > 0:
		_lead -= 1
		if _lead > 0 or not _pending_reset:
			return false
		# `ld b, $0` is set at the end of `.LoopLevels`, but nothing draws it
		# until the next `.LoopBarAnimation` runs, which is after
		# `.PlayExpBarSound`'s ten frames. So the full bar stays up under the
		# grew-to-level textbox and empties on the new segment's first draw.
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


## `.LoopLevels`' own tail: the level goes up and its line is printed by a
## textbox that blocks on a button, so the bar stops here full. [method resume]
## is that button, and it is what empties the bar and starts the next fill.
func _end_segment() -> void:
	_segment_ended = true
	_segment += 1
	if not finished():
		_paused = true
