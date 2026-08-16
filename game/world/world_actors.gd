class_name Gen2WorldActors
extends RefCounted

## The sprites a mod puts in the world, driven and resolved by the host.
##
## A mod that wants one thing in the overworld, a follower, a pet, a marker over
## an object, registers a world ACTOR through
## [method Gen2ModHost.register_world_actor] rather than a whole world renderer.
## This class is what the screen drives it with: one `advance_frame` per world
## frame, one `sprites()` read after it, and the answer resolved into the same
## [Gen2WorldSprite] the map's own objects are drawn from.
##
## PRESENTATION and nothing else. An actor's sprite occupies no cell, blocks
## nothing, is talked to by nobody, is seen by no trainer and appears in no
## snapshot. That is the whole reason this is a layer of its own rather than a
## map object: a mod must not be able to change what the cartridge says the
## world is, and an object is world state.
##
## A mod names cartridge art and never composes pixels: an entry carries an
## `IconPointers` row (`icon`), or an `OverworldSprites` row (`sprite`), and the
## strip, the palette, the time of day and the icon's own animation rate are
## resolved here exactly as they are for a mon-icon object standing on a map.

## The methods an actor has to provide. Checked at registration, where the mod's
## name is still in hand, the way a renderer's are.
const ACTOR_METHODS: Array[String] = ["set_world", "advance_frame", "sprites"]

## `.Frameset_PartyMon`, the icon's own two-frame animation: two OAM sets of
## eight, which is nine passes each because `GetSpriteAnimFrame` returns the
## entry on the pass that loads the duration too. An actor is not a party row,
## so it takes the unmodified speed rather than
## `SetPartyMonIconAnimSpeed`'s hurt-Pokemon slowdown.
const ICON_FRAME_FRAMES: int = 9
const ICON_FRAMES: int = 2

var _actors: Array = []
var _world: Gen2WorldAPI = null
## What the last `advance_frame` collected. Held rather than re-read, so two
## views drawing the same frame draw the same thing and a mod's `sprites()` is
## asked once a frame however many times the screen redraws.
var _sprites: Array = []
var _frame: int = 0


## [param actors] is [method Gen2ModHost.world_actors], in registration order,
## which is the order they are drawn in within one row.
func set_actors(actors: Array) -> void:
	_actors = actors
	_collect()


func has_actors() -> bool:
	return not _actors.is_empty()


## The map changed, or the view was created.
func set_world(world: Gen2WorldAPI) -> void:
	_world = world
	for actor: Object in _actors:
		actor.call("set_world", world)
	_collect()


## One world frame, spent after the player's own step has advanced so an actor
## reading `player_step_offset_cells()` sees this frame's position rather than
## the last one's. Answers whether anything it draws moved.
func advance_frame() -> bool:
	if _actors.is_empty():
		return false
	_frame += 1
	for actor: Object in _actors:
		actor.call("advance_frame")
	var before: Array = _sprites
	_collect()
	return _changed(before, _sprites)


## What to draw now, as { sprite, facing, frame, position_cells }, sorted the way
## the map's own objects are: by the row they stand on, then by the order they
## were registered in.
func sprites() -> Array:
	return _sprites


func _collect() -> void:
	_sprites = []
	if _world == null or _world.data == null:
		return
	for index: int in _actors.size():
		for entry: Variant in _actors[index].call("sprites"):
			var resolved: Dictionary = _resolve(entry, index)
			if not resolved.is_empty():
				_sprites.append(resolved)
	_sprites.sort_custom(_sort)


## One entry of a mod's answer. An entry naming art the cache does not carry is
## dropped rather than drawn as a placeholder: a mod asking for a species icon
## on a cartridge that has none should show nothing, not a magenta square.
func _resolve(entry: Variant, order: int) -> Dictionary:
	if not entry is Dictionary:
		return {}
	var row: Dictionary = entry as Dictionary
	var sprite: Gen2WorldSprite = null
	if row.has("icon"):
		sprite = _world.data.overworld_icon(int(row["icon"]))
		if sprite != null:
			## A map object's icon never animates: `GetUsedSprite` copies its
			## eight tiles into both VRAM halves, so the walking rows of
			## `Facings` land on the same picture. An actor is not a map object
			## and asks for the two frames the strip carries.
			sprite.animate_icon_frames = true
	elif row.has("sprite"):
		sprite = _world.data.overworld_sprite(int(row["sprite"]))
	if sprite == null:
		return {}
	var facing: int = clampi(
		int(row.get("facing", Gen2WorldSprite.FACING_DOWN)),
		Gen2WorldSprite.FACING_DOWN, Gen2WorldSprite.FACING_RIGHT
	)
	return {
		"sprite": sprite,
		"facing": facing,
		"frame": _frame_for(sprite),
		"position_cells": Vector2(row.get("position_cells", Vector2.ZERO)),
		"order": order,
	}


## Which of the sprite's frames is up this frame. A mon icon steps through its
## own two at `.Frameset_PartyMon`'s rate; anything else is drawn standing,
## since only the actor knows whether it is moving and `Facings`' walking rows
## belong to a step this layer does not take.
func _frame_for(sprite: Gen2WorldSprite) -> int:
	if sprite.sprite_type != Gen2WorldSprite.TYPE_MON_ICON:
		return 0
	@warning_ignore("integer_division")
	var step: int = (_frame / ICON_FRAME_FRAMES) % ICON_FRAMES
	## Frame 1 is `Gen2WorldSprite.is_walking_frame`'s own, which is what reads
	## the strip's second half.
	return step


func _sort(first: Dictionary, second: Dictionary) -> bool:
	var first_y: float = (first["position_cells"] as Vector2).y
	var second_y: float = (second["position_cells"] as Vector2).y
	if is_equal_approx(first_y, second_y):
		return int(first["order"]) < int(second["order"])
	return first_y < second_y


func _changed(before: Array, after: Array) -> bool:
	if before.size() != after.size():
		return true
	for index: int in before.size():
		var was: Dictionary = before[index]
		var now: Dictionary = after[index]
		if was["position_cells"] != now["position_cells"] \
			or int(was["facing"]) != int(now["facing"]) \
			or int(was["frame"]) != int(now["frame"]) \
			or (was["sprite"] as Gen2WorldSprite).number \
				!= (now["sprite"] as Gen2WorldSprite).number:
			return true
	return false
