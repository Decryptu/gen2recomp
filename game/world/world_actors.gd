class_name Gen2WorldActors
extends RefCounted

## The sprites a mod puts in the world, driven and resolved by the host. A mod
## wanting one thing in the overworld, a follower or a marker, registers an actor
## through [method Gen2ModHost.register_world_actor] rather than a whole
## renderer. The screen drives it with one `advance_frame` per world frame and
## one `sprites()` read after it, resolved into the same [Gen2WorldSprite] the
## map's own objects are drawn from.
##
## PRESENTATION and nothing else: an actor's sprite occupies no cell, blocks
## nothing, is talked to by nobody, is seen by no trainer and is in no snapshot.
## That is why it is a layer of its own rather than a map object, which is world
## state a mod must not be able to change.
##
## A mod names cartridge art and never composes pixels: an entry carries an
## `IconPointers` row (`icon`) or an `OverworldSprites` row (`sprite`), and the
## strip, palette, time of day and animation rate are resolved here the way they
## are for a mon-icon object standing on a map.

## Checked at registration, where the mod's name is still in hand.
const ACTOR_METHODS: Array[String] = ["set_world", "advance_frame", "sprites"]

## `.Frameset_PartyMon`: two OAM sets of eight, nine passes each because
## `GetSpriteAnimFrame` returns the entry on the pass that loads the duration
## too. An actor is not a party row, so no `SetPartyMonIconAnimSpeed` slowdown.
const ICON_FRAME_FRAMES: int = 9
const ICON_FRAMES: int = 2

var _actors: Array = []
## The visible-encounter population, drawn in the same pass. See
## [method set_encounters].
var _encounters: Gen2WorldEncounters = null
var _world: Gen2WorldAPI = null
## Held rather than re-read, so a mod's `sprites()` is asked once a frame however
## many times the screen redraws and two views agree.
var _sprites: Array = []
var _frame: int = 0


## [param actors] is [method Gen2ModHost.world_actors], in registration order,
## which is the order they are drawn in within one row.
func set_actors(actors: Array) -> void:
	_actors = actors
	_collect()


## The host's own visible-encounter layer, whose population is drawn through this
## one so a wild standing on the map sorts into the same rows and reaches both
## views. What it IS is not presentation and lives in [Gen2WorldEncounters]; what
## it looks like is one more sprite here.
func set_encounters(encounters: Gen2WorldEncounters) -> void:
	_encounters = encounters
	_collect()


func has_actors() -> bool:
	return not _actors.is_empty() or (_encounters != null and _encounters.active())


## The map changed, or the view was created.
func set_world(world: Gen2WorldAPI) -> void:
	_world = world
	for actor: Object in _actors:
		actor.call("set_world", world)
	_collect()


## One world frame, spent after the player's step so an actor reading
## `player_step_offset_cells()` sees this frame. Answers whether anything moved.
func advance_frame() -> bool:
	if not has_actors():
		return false
	_frame += 1
	for actor: Object in _actors:
		actor.call("advance_frame")
	var before: Array = _sprites
	_collect()
	return _changed(before, _sprites)


## { sprite, facing, frame, position_cells, colors }, sorted by the row stood on
## and then by registration order, the way the map's own objects are. `colors` is
## empty for everything but a visible encounter.
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
	if _encounters != null:
		for entry: Variant in _encounters.actor_entries():
			var resolved: Dictionary = _resolve(entry, _actors.size())
			if not resolved.is_empty():
				_sprites.append(resolved)
	_sprites.sort_custom(_sort)


## One entry of a mod's answer. Art the cache does not carry is dropped rather
## than drawn as a placeholder.
func _resolve(entry: Variant, order: int) -> Dictionary:
	if not entry is Dictionary:
		return {}
	var row: Dictionary = entry as Dictionary
	var sprite: Gen2WorldSprite = null
	if row.has("icon"):
		sprite = _world.data.overworld_icon(int(row["icon"]))
		if sprite != null:
			# A map object's icon never animates: `GetUsedSprite` copies its
			# eight tiles into both VRAM halves, so `Facings`' walking rows
			# land on the same picture. An actor asks for both frames.
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
		# An overworld sprite wears one of the map's own sprite palettes. A
		# visible encounter wears the SPECIES' four colours instead, which is the
		# only way a shiny one is a shiny one before the battle starts. A view
		# that does not read this draws the ordinary palette and is not wrong.
		"colors": row.get("colors", PackedColorArray()),
	}


## A mon icon steps through its two at `.Frameset_PartyMon`'s rate; anything else
## stands, since `Facings`' walking rows belong to a step this layer never takes.
func _frame_for(sprite: Gen2WorldSprite) -> int:
	if sprite.sprite_type != Gen2WorldSprite.TYPE_MON_ICON:
		return 0
	@warning_ignore("integer_division")
	# Frame 1 is `Gen2WorldSprite.is_walking_frame`'s, which reads the strip's
	# second half.
	var step: int = (_frame / ICON_FRAME_FRAMES) % ICON_FRAMES
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
