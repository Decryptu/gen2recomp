class_name Gen2GameTime
extends RefCounted

## The play timer the trainer card prints (`home/game_time.asm`, `GameTimer`).
##
## Not the day cycle: [Gen2WorldClock] is real time and answers what hour the
## world is in, while this counts hardware frames of actual play and is what
## `wGameTimeHours`/`wGameTimeMinutes` hold. The cartridge keeps both, and they
## disagree the moment the game is closed.
##
## `GameTimer` counts 60 frames to a second even though a frame is 1/59.7275 s,
## so the play timer runs about half a percent slow against a wall clock. That
## is the cartridge's own arithmetic and is mirrored rather than corrected.

## `GameTimer.Function`'s own comparisons.
const FRAMES_PER_SECOND: int = 60
const SECONDS_PER_MINUTE: int = 60
const MINUTES_PER_HOUR: int = 60
## "Cap the timer after 1000 hours", leaving 999:59:59.00 on the card.
const MAX_HOURS: int = 1000
const CAPPED_HOURS: int = MAX_HOURS - 1
const CAPPED_MINUTES: int = SECONDS_PER_MINUTE - 1
const CAPPED_SECONDS: int = SECONDS_PER_MINUTE - 1

var hours: int = 0
var minutes: int = 0
var seconds: int = 0
var frames: int = 0
## `wGameTimeCap`'s `GAME_TIME_CAPPED` bit. Held rather than derived, because
## the source stops counting on the bit and never looks at the hours again.
var capped: bool = false


static func create(
	hours_value: int, minutes_value: int, seconds_value: int, frames_value: int,
	capped_value: bool = false,
) -> Gen2GameTime:
	var time := Gen2GameTime.new()
	time.hours = clampi(hours_value, 0, CAPPED_HOURS)
	time.minutes = clampi(minutes_value, 0, MINUTES_PER_HOUR - 1)
	time.seconds = clampi(seconds_value, 0, SECONDS_PER_MINUTE - 1)
	time.frames = clampi(frames_value, 0, FRAMES_PER_SECOND - 1)
	time.capped = capped_value
	return time


## One hardware frame, which is what `GameTimer` is called with. Returns whether
## anything visible on the card changed, so a screen knows when to redraw.
##
## The source's two gates before the count are `wGameLogicPaused` and
## `wGameTimerPaused`; the caller owns both, since only it knows whether the
## game is running.
func advance_frame() -> bool:
	if capped:
		return false
	frames += 1
	if frames < FRAMES_PER_SECOND:
		return false
	frames = 0
	seconds += 1
	if seconds < SECONDS_PER_MINUTE:
		return false
	seconds = 0
	minutes += 1
	if minutes < MINUTES_PER_HOUR:
		return true
	minutes = 0
	hours += 1
	if hours < MAX_HOURS:
		return true
	## `.ok` is skipped: the source writes 59 to minutes and seconds and leaves
	## the hour where the increment put it, so the card reads 999:59:59.
	capped = true
	hours = CAPPED_HOURS
	minutes = CAPPED_MINUTES
	seconds = CAPPED_SECONDS
	return true


## Whole frames at once, for a host that ran several between calls the way
## [method Gen2WorldAnimation.advance] catches up.
func advance_frames(count: int) -> bool:
	var changed: bool = false
	for _frame: int in maxi(count, 0):
		changed = advance_frame() or changed
	return changed


func to_dict() -> Dictionary:
	return {
		"hours": hours,
		"minutes": minutes,
		"seconds": seconds,
		"frames": frames,
		"capped": capped,
	}


## Clamped rather than refused, the way [Gen2Options] clamps: a play timer is
## not progress, and a damaged one should not cost the save.
static func parse(raw: Variant) -> Gen2GameTime:
	if raw is not Dictionary:
		return Gen2GameTime.new()
	var row: Dictionary = raw
	return Gen2GameTime.create(
		int(row.get("hours", 0)),
		int(row.get("minutes", 0)),
		int(row.get("seconds", 0)),
		int(row.get("frames", 0)),
		bool(row.get("capped", false)),
	)


## `TrainerCard_Page1_PrintGameTime`: hours right-aligned in four spaces, then
## the two-digit minutes with leading zeros. The separator is the caller's,
## since the source blinks it.
func hours_text() -> String:
	return "%4d" % hours


func minutes_text() -> String:
	return "%02d" % minutes
