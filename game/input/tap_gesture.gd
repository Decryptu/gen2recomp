class_name Gen2TapGesture
extends RefCounted

## Counts quick repeated taps in roughly one place.
##
## The one way back from hidden on-screen controls. A player who turns them off
## for a plugged-in pad, then unplugs it on a device with no keyboard, has no
## button left to press, so the gesture has to be something no ordinary play
## produces and no button can swallow.
##
## Timing and counting only, with the clock passed in, so a test does not have
## to wait half a second three times.

const TAPS: int = 3
## Between consecutive taps. Long enough to be comfortable, short enough that
## three unrelated taps a second apart are not the gesture.
const WINDOW: float = 0.5
## How far a tap may land from the one before it and still be the same gesture.
const RADIUS: float = 96.0

var _count: int = 0
var _last_at: float = 0.0
var _last_point: Vector2 = Vector2.ZERO


## Records a tap and reports whether it completed the gesture. Completing also
## resets, so the next three taps are a fresh one rather than every tap after
## the third firing again.
func tap(point: Vector2, now: float) -> bool:
	var continues: bool = _count > 0 \
		and now - _last_at <= WINDOW \
		and point.distance_to(_last_point) <= RADIUS
	_count = _count + 1 if continues else 1
	_last_at = now
	_last_point = point
	if _count < TAPS:
		return false
	reset()
	return true


func reset() -> void:
	_count = 0
	_last_at = 0.0
	_last_point = Vector2.ZERO


func count() -> int:
	return _count
