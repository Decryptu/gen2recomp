class_name Gen2WorldObject
extends RefCounted

## Scene-free state for one map-object event. Script pointers and event flags
## remain data here. The movement templates implemented in this slice cover
## the source's standing, fixed-facing, axis-wander and random-wander rows.
## Scripted movement and follower state are driven by the world event runtime.

const MOVEMENT_STILL: int = 1
const MOVEMENT_WANDER: int = 2
const MOVEMENT_SPINRANDOM_SLOW: int = 3
const MOVEMENT_WALK_UP_DOWN: int = 4
const MOVEMENT_WALK_LEFT_RIGHT: int = 5
const MOVEMENT_FIXED_DOWN: int = 6
const MOVEMENT_FIXED_UP: int = 7
const MOVEMENT_FIXED_LEFT: int = 8
const MOVEMENT_FIXED_RIGHT: int = 9
const MOVEMENT_SPINRANDOM_FAST: int = 10
const MOVEMENT_PLAYER: int = 11
const MOVEMENT_FOLLOW: int = 19
const MOVEMENT_SCRIPTED: int = 20
const MOVEMENT_SWIM_WANDER: int = 0x24

const OBJECTTYPE_SCRIPT: int = 0
const OBJECTTYPE_ITEMBALL: int = 1
const OBJECTTYPE_TRAINER: int = 2

const TIME_MASKS: Array = [1, 2, 4, 4]

var index: int = 0
var sprite_number: int = 0
var sprite: Gen2WorldSprite = null
var cell: Vector2i = Vector2i.ZERO
var initial_cell: Vector2i = Vector2i.ZERO
var movement: int = MOVEMENT_STILL
var x_radius: int = 0
var y_radius: int = 0
var hour_1: int = -1
var hour_2: int = -1
var palette: int = 0
var object_type: int = 0
var sight_range: int = 0
var event_script: int = 0
var event_flag: int = 0
var trainer_data: Dictionary = {}
var facing: int = Gen2WorldSprite.FACING_DOWN
var frame: int = 0
var active: bool = false
var deleted: bool = false
var emote_id: int = -1
var emote_visible: bool = false
var emote_remaining: int = 0


static func from_event(
	event_index: int, value: Dictionary, sprite_asset: Gen2WorldSprite = null
) -> Gen2WorldObject:
	var out := Gen2WorldObject.new()
	out.index = event_index
	out.sprite_number = int(value.get("sprite", 0))
	out.sprite = sprite_asset
	out.cell = Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
	out.initial_cell = out.cell
	out.movement = int(value.get("movement", MOVEMENT_STILL))
	out.x_radius = int(value.get("x_radius", 0))
	out.y_radius = int(value.get("y_radius", 0))
	out.hour_1 = int(value.get("hour_1", -1))
	out.hour_2 = int(value.get("hour_2", -1))
	out.palette = int(value.get("palette", 0))
	out.object_type = int(value.get("object_type", 0))
	out.sight_range = int(value.get("sight_range", 0))
	out.event_script = int(value.get("script", 0))
	out.event_flag = int(value.get("event_flag", 0))
	var trainer: Variant = value.get("trainer", {})
	if trainer is Dictionary:
		out.trainer_data = (trainer as Dictionary).duplicate(true)
	if out.event_flag == 0xFFFF:
		out.event_flag = -1
	out.facing = out.initial_facing()
	return out


func initial_facing() -> int:
	match movement:
		MOVEMENT_FIXED_UP:
			return Gen2WorldSprite.FACING_UP
		MOVEMENT_FIXED_LEFT:
			return Gen2WorldSprite.FACING_LEFT
		MOVEMENT_FIXED_RIGHT:
			return Gen2WorldSprite.FACING_RIGHT
		_:
			return Gen2WorldSprite.FACING_DOWN


func movement_supported() -> bool:
	return movement in [
		MOVEMENT_STILL, MOVEMENT_WANDER, MOVEMENT_SPINRANDOM_SLOW,
		MOVEMENT_WALK_UP_DOWN, MOVEMENT_WALK_LEFT_RIGHT,
		MOVEMENT_FIXED_DOWN, MOVEMENT_FIXED_UP, MOVEMENT_FIXED_LEFT,
		MOVEMENT_FIXED_RIGHT, MOVEMENT_SPINRANDOM_FAST, MOVEMENT_SWIM_WANDER,
	]


## Exact time-window test from CheckObjectTime in the source runtime. Ranges
## include both endpoints, and a range that wraps midnight is split in two.
func visible_at(hour: int, time_of_day: int) -> bool:
	if hour_1 < 0:
		if hour_2 < 0:
			return true
		var mask: int = TIME_MASKS[clampi(time_of_day, 0, TIME_MASKS.size() - 1)]
		return (hour_2 & mask) != 0
	if hour_1 == hour_2 or hour < 0:
		return hour_1 == hour_2
	if hour_1 < hour_2:
		return hour >= hour_1 and hour <= hour_2
	return hour >= hour_1 or hour <= hour_2


## A zero or negative flag is the cache's no-flag/default value. The source
## uses $FFFF as the explicit always-visible sentinel, imported as -1.
func visible_with_state(hour: int, time_of_day: int, state: Gen2WorldState) -> bool:
	return visible_at(hour, time_of_day) and not event_flag_active(state)


func event_flag_active(state: Gen2WorldState) -> bool:
	return event_flag > 0 and state != null and state.is_event_flag_active(event_flag)


func trainer_flag_active(state: Gen2WorldState) -> bool:
	var flag: int = int(trainer_data.get("event_flag", -1))
	return flag >= 0 and state != null and state.is_event_flag_active(flag)


func can_leave_to(destination: Vector2i) -> bool:
	return destination.x >= initial_cell.x - x_radius \
		and destination.x <= initial_cell.x + x_radius \
		and destination.y >= initial_cell.y - y_radius \
		and destination.y <= initial_cell.y + y_radius


func next_direction(random: RandomNumberGenerator) -> Vector2i:
	match movement:
		MOVEMENT_WALK_UP_DOWN:
			return Vector2i.UP if random.randi_range(0, 1) == 0 else Vector2i.DOWN
		MOVEMENT_WALK_LEFT_RIGHT:
			return Vector2i.LEFT if random.randi_range(0, 1) == 0 else Vector2i.RIGHT
		MOVEMENT_WANDER, MOVEMENT_SWIM_WANDER:
			return [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT][random.randi_range(0, 3)]
		_:
			return Vector2i.ZERO


func apply_direction(direction: Vector2i) -> void:
	if direction == Vector2i.UP:
		facing = Gen2WorldSprite.FACING_UP
	elif direction == Vector2i.DOWN:
		facing = Gen2WorldSprite.FACING_DOWN
	elif direction == Vector2i.LEFT:
		facing = Gen2WorldSprite.FACING_LEFT
	elif direction == Vector2i.RIGHT:
		facing = Gen2WorldSprite.FACING_RIGHT


func set_emote(value: int, visible: bool, duration: int = 0) -> void:
	emote_id = value
	emote_visible = visible
	emote_remaining = maxi(0, duration) if visible else 0


func tick_emote() -> bool:
	if not emote_visible or emote_remaining <= 0:
		return false
	emote_remaining -= 1
	if emote_remaining == 0:
		emote_visible = false
		return true
	return false
