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
## SPRITEMOVEDATA_STRENGTH_BOULDER. The constants file's comment column is hex,
## which is why this is $19 and not 19: 19 is SPRITEMOVEDATA_FOLLOWING ($13)
## above. A boulder decides nothing on its own, so it is deliberately in neither
## movement_supported() nor movement_advances(); it only reacts to a push.
const MOVEMENT_STRENGTH_BOULDER: int = 0x19
## SPRITEMOVEDATA_SMASHABLE_ROCK, the row directly below the boulder and in
## neither template set for the same reason: a rock decides nothing and only
## reacts to being smashed. Its flags1 are the boulder's, minus the palette bit
## and plus USE_OBP1, so nothing but the movement byte tells the two apart.
const MOVEMENT_SMASHABLE_ROCK: int = 0x18
## SPRITEMOVEDATA_SUDOWOODO, the row above the rock and in neither template set
## for the same reason. Route 36's weird tree is the only object in either game
## on it, and `.CheckCanUseSquirtbottle` is the only reader.
const MOVEMENT_SUDOWOODO: int = 0x17
const MOVEMENT_SWIM_WANDER: int = 0x24
## The three rows data/sprites/map_objects.asm gives BIG_OBJECT in their palette
## flags. Only two objects in either game use one: the player's bedroom big doll
## and Vermilion City's Snorlax. BIGDOLLASYM is referenced by no map.
const MOVEMENT_BIGDOLLSYM: int = 0x15
const MOVEMENT_BIGDOLLASYM: int = 0x20
const MOVEMENT_BIGDOLL: int = 0x21
## WillObjectIntersectBigObject's own two, commented "big doll width" and
## "big doll height".
const BIG_OBJECT_SIZE: int = 2

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
## Whether [member event_flag] was set when this object table was built.
## `ReadObjectEvents` reads the flag at map load and `wMapObjects` carries the
## answer until the next one, so a script that writes the flag while the map is
## up moves nothing: only `appear` and `disappear`, which edit the live struct as
## well, do. Kept across a mid-script object reload for that reason.
var flag_hidden: bool = false
var trainer_data: Dictionary = {}
var facing: int = Gen2WorldSprite.FACING_DOWN
## The `Facings` frame this object is drawn on, 0 to 3: two standing and two
## walking. Derived from step_frame; see walk_frame().
var frame: int = 0
## OBJECT_STEP_FRAME. `SetFacingStepAction` (engine/overworld/map_object_action.asm)
## increments it once per hardware frame of a step and masks it to four bits, and
## the drawn frame is its two high bits, so the drawing changes every four frames.
var step_frame: int = 0
var active: bool = false
var deleted: bool = false
var emote_id: int = -1
var emote_visible: bool = false
var emote_remaining: int = 0
## Transient sub-cell presentation offset toward a cell this object already
## committed to. The logical cell changes at the start of a step, not here;
## a renderer reads this only to draw the approach to it.
var step_direction: Vector2i = Vector2i.ZERO
var step_frames_total: int = 0
var step_frames_remaining: int = 0
## Set on the frame a step starts and cleared by whoever reads it, which is the
## grass rustle `NormalStep` spawns there.
var step_began: bool = false
## OBJECT_ACTION_WEIRD_TREE, while the sleep a `tree_shake` queued runs. See
## queue_tree_shake().
var weird_tree: bool = false
## The rest of a scripted movement stream, still to be drawn. An applymovement
## commits every cell of its path at once, so the whole path is behind the
## committed cell until these drain; each entry is one `{direction, frames}`
## step of it, in stream order.
var queued_steps: Array = []
## True while the trail above belongs to a script rather than to the movement
## templates, which is what tells the two drivers apart:
## Gen2WorldAPI.advance_object_steps_frame() decides movement and is refused while a
## script runs, advance_scripted_steps_frame() only draws and is not.
var scripted_steps: bool = false
## Frames this object waits before its movement template decides again. The
## source keeps this in OBJECT_STEP_DURATION while the object sits in
## STEP_TYPE_SLEEP (engine/overworld/map_objects.asm, StepFunction_Sleep).
var idle_frames_remaining: int = 0


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


## Carries the live presentation of the object this one replaces at the same
## index on the same map: the emote it is showing, the trail it is still being
## drawn walking, and whether a movement stream deleted it.
##
## The cartridge never rebuilds an object struct for any of the reasons this
## project rebuilds a record: `ApplyObjectFacing`, `CopyDECoordsToMapObject` and
## the variable-sprite table all write into the struct that is already there.
## Without this, a `turnobject` between a `showemote` and its `applymovement`
## takes the emote down and empties the trail the script is waiting on.
func carry_presentation_from(previous: Gen2WorldObject) -> void:
	if previous == null:
		return
	emote_id = previous.emote_id
	emote_visible = previous.emote_visible
	emote_remaining = previous.emote_remaining
	step_direction = previous.step_direction
	step_frames_total = previous.step_frames_total
	step_frames_remaining = previous.step_frames_remaining
	queued_steps = previous.queued_steps.duplicate(true)
	scripted_steps = previous.scripted_steps
	step_frame = previous.step_frame
	frame = previous.frame
	idle_frames_remaining = previous.idle_frames_remaining
	deleted = previous.deleted


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


## The source's own test in DoPlayerMovement.CheckStrengthBoulder: OBJECT_PALETTE
## bit STRENGTH_BOULDER, which data/sprites/map_objects.asm sets on exactly the
## SPRITEMOVEDATA_STRENGTH_BOULDER row, so the movement template answers it.
func is_strength_boulder() -> bool:
	return movement == MOVEMENT_STRENGTH_BOULDER


## TryRockSmashFromMenu's own test: GetFacingObject hands MAPOBJECT_MOVEMENT
## back in `d` and the whole check is `cp SPRITEMOVEDATA_SMASHABLE_ROCK`. Unlike
## the three below it that is the source asking the movement byte directly
## rather than a palette flag the row happens to carry.
func is_smashable_rock() -> bool:
	return movement == MOVEMENT_SMASHABLE_ROCK


## `.CheckCanUseSquirtbottle`'s own test, read the same way: `GetFacingObject`
## answers MAPOBJECT_MOVEMENT and the whole check is `cp SPRITEMOVEDATA_SUDOWOODO`.
func is_sudowoodo() -> bool:
	return movement == MOVEMENT_SUDOWOODO


## OBJECT_PALETTE bit SWIMMING, which CanObjectMoveInDirection reads to pick
## WillObjectBumpIntoLand over WillObjectBumpIntoWater. Same shape as
## is_strength_boulder(): data/sprites/map_objects.asm sets the bit on exactly the
## SPRITEMOVEDATA_SWIM_WANDER row, so the movement template answers it. Only
## Union Cave B2F's Lapras uses that row, in either game.
func is_swimming() -> bool:
	return movement == MOVEMENT_SWIM_WANDER


## OBJECT_PALETTE bit BIG_OBJECT. Same shape again: the movement template
## answers it, and three rows carry it.
func is_big_object() -> bool:
	return movement in [MOVEMENT_BIGDOLLSYM, MOVEMENT_BIGDOLLASYM, MOVEMENT_BIGDOLL]


## SetFacingBigDoll chooses the symmetric row for Snorlax and Lapras and the
## asymmetric row for every other variable big doll. The two explicit movement
## rows select their matching facing table directly.
func big_object_shape() -> int:
	match movement:
		MOVEMENT_BIGDOLLSYM:
			return Gen2WorldSprite.BIG_SHAPE_SYMMETRIC
		MOVEMENT_BIGDOLLASYM:
			return Gen2WorldSprite.BIG_SHAPE_ASYMMETRIC
		MOVEMENT_BIGDOLL:
			return Gen2WorldSprite.BIG_SHAPE_SYMMETRIC if sprite_number in [33, 47] \
				else Gen2WorldSprite.BIG_SHAPE_ASYMMETRIC
	return Gen2WorldSprite.BIG_SHAPE_NONE


## WillObjectIntersectBigObject: a big object fills a two-by-two square anchored
## on its own cell, so it blocks four cells and can be faced from any of them.
## Every other object is the single cell IsNPCAtCoord compares against.
func occupies(target: Vector2i) -> bool:
	if not is_big_object():
		return cell == target
	var offset: Vector2i = target - cell
	return offset.x >= 0 and offset.x < BIG_OBJECT_SIZE \
		and offset.y >= 0 and offset.y < BIG_OBJECT_SIZE


func movement_supported() -> bool:
	return movement in [
		MOVEMENT_STILL, MOVEMENT_WANDER, MOVEMENT_SPINRANDOM_SLOW,
		MOVEMENT_WALK_UP_DOWN, MOVEMENT_WALK_LEFT_RIGHT,
		MOVEMENT_FIXED_DOWN, MOVEMENT_FIXED_UP, MOVEMENT_FIXED_LEFT,
		MOVEMENT_FIXED_RIGHT, MOVEMENT_SPINRANDOM_FAST, MOVEMENT_SWIM_WANDER,
	]


## The supported templates that actually decide something on their own: the
## three random-walk rows and the two random-spin rows. The standing and
## fixed-facing rows resolve once in the source and never ask again, so a
## per-frame driver skips them rather than re-deciding nothing every frame.
func movement_advances() -> bool:
	return movement in [
		MOVEMENT_WANDER, MOVEMENT_WALK_UP_DOWN, MOVEMENT_WALK_LEFT_RIGHT,
		MOVEMENT_SWIM_WANDER, MOVEMENT_SPINRANDOM_SLOW, MOVEMENT_SPINRANDOM_FAST,
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
##
## Read once, when the object table is built: `ReadObjectEvents` tests the flag
## at map load and nothing re-tests it while the map is up, which is the whole
## reason `appear` and `disappear` exist. A `setevent` on an object's own flag
## therefore changes nothing on screen until the map is loaded again. See
## [member flag_hidden].
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


## Starts the presentation offset for a step whose destination cell is
## already committed. [param frames] is the caller's own step duration, kept
## caller-side so a slow trainer approach and an ordinary walk can share this
## helper without this class knowing which one is running.
func start_step(direction: Vector2i, frames: int) -> void:
	queued_steps.clear()
	scripted_steps = false
	_begin_step(direction, frames)


## Adds one step of a scripted stream to the trail. The first one starts at
## once and the rest wait their turn, so a five-step applymovement is drawn as
## five steps rather than as one arrival.
func queue_step(direction: Vector2i, frames: int) -> void:
	scripted_steps = true
	if step_frames_remaining > 0:
		queued_steps.append({"direction": direction, "frames": maxi(0, frames)})
		return
	_begin_step(direction, frames)


## `Movement_tree_shake`: 24 frames of STEP_TYPE_SLEEP with OBJECT_ACTION_WEIRD_TREE.
##
## Nothing moves and nothing shakes but this object's own drawing:
## `SetFacingWeirdTree` steps the frame counter every frame and takes its two
## high bits, which is `walk_frame()` again, so Sudowoodo wobbles between its
## standing drawing and its two walking ones where it stands.
func queue_tree_shake(frames: int) -> void:
	weird_tree = true
	queue_wait(frames)


## Adds a `step_sleep` to the same trail: frames the stream spends standing.
## STEP_TYPE_SLEEP writes STANDING into OBJECT_WALKING, so this walks nothing
## and moves nothing, but the script waiting on the stream still waits for it.
func queue_wait(frames: int) -> void:
	queue_step(Vector2i.ZERO, sleep_frames(frames))


## `StepFunction_Sleep` decrements OBJECT_STEP_DURATION before testing it, so a
## zero-length sleep wraps a whole byte instead of ending at once.
static func sleep_frames(length: int) -> int:
	return length if length > 0 else 0x100


func _begin_step(direction: Vector2i, frames: int) -> void:
	step_direction = direction
	step_frames_total = maxi(0, frames)
	step_frames_remaining = step_frames_total
	## `NormalStep` calls `ShakeGrass` where it starts the step, and a queued
	## stream starts its later steps here rather than at a call site, so the flag
	## is raised here and read once by Gen2WorldAPI.take_grass_rustles().
	step_began = direction != Vector2i.ZERO


## Consumes one frame of an in-flight step. Returns true when a frame was
## consumed, false once the step has already finished, so a caller pacing by
## call count rather than delta time can tell "still stepping" from "done".
func tick_step() -> bool:
	if step_frames_remaining <= 0:
		return false
	if step_direction != Vector2i.ZERO or weird_tree:
		advance_walk_frame()
	step_frames_remaining -= 1
	if step_frames_remaining <= 0:
		if weird_tree:
			## The 24 frames are not a multiple of the four-frame cycle, so
			## unlike a step this one has to be stood back up by hand.
			weird_tree = false
			step_frame = 0
			frame = 0
		if queued_steps.is_empty():
			scripted_steps = false
		else:
			var next: Dictionary = queued_steps.pop_front()
			_begin_step(next["direction"], int(next["frames"]))
	return true


func is_stepping() -> bool:
	return step_frames_remaining > 0


## One hardware frame of `SetFacingStepAction`. The counter is never cleared
## here: `EndSpriteMovement` is what zeroes it on the cartridge, and every step
## duration is a multiple of four, so a stopped object is already standing on
## frame 0 or 2 without one. Frames 1 and 3 are the two walking drawings.
func advance_walk_frame() -> void:
	step_frame = (step_frame + 1) & 0x0F
	frame = walk_frame()


func walk_frame() -> int:
	return (step_frame >> 2) & 3


## Starts the wait a movement template takes before deciding again. The source
## rolls this duration itself; the caller supplies the rolled value so this
## class stays free of the generator.
func start_idle(frames: int) -> void:
	idle_frames_remaining = maxi(0, frames)


## Consumes one frame of that wait. Returns true when a frame was consumed,
## matching tick_step() so one caller can pace both.
func tick_idle() -> bool:
	if idle_frames_remaining <= 0:
		return false
	idle_frames_remaining -= 1
	return true


func is_idle() -> bool:
	return idle_frames_remaining > 0


## Pixel offset from the committed cell back toward where the step began,
## shrinking to zero as step_frames_remaining reaches zero.
func step_offset(cell_pixels: int) -> Vector2i:
	var offset: Vector2 = step_offset_cells() * float(cell_pixels)
	return Vector2i(int(round(offset.x)), int(round(offset.y)))


## The same offset in fractional walk cells, from where the sprite is drawn back
## to the committed cell. A renderer that does not think in hardware pixels reads
## this instead of step_offset(), exactly as a renderer reads the player's
## Gen2WorldAPI.player_step_offset_cells().
##
## One in-flight step is at most a cell behind. A scripted stream commits its
## whole path at once, so its trail is as many cells behind as it has left to
## draw.
func step_offset_cells() -> Vector2:
	var behind := Vector2.ZERO
	for entry: Dictionary in queued_steps:
		behind -= Vector2(entry["direction"] as Vector2i)
	if step_frames_remaining > 0 and step_frames_total > 0:
		behind -= Vector2(step_direction) \
			* (float(step_frames_remaining) / float(step_frames_total))
	return behind
