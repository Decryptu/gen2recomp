extends SceneTree

## Verifies the overworld field-move prompts against freshly imported real
## caches, for both command profiles.
##
## The expected values come from the pinned pokecrystal and pokegold sources:
## engine/overworld/events.asm's TryTileCollisionEvent from `.cut` on, and
## engine/events/overworld.asm's TryCutOW, TryWhirlpoolOW, TryWaterfallOW,
## TryHeadbuttOW, TrySurfOW and the five Ask*Scripts behind them, all of which
## are byte identical between the pins.
##
## The real-cartridge counterpart to the prompt half of
## tests/integration/test_world_field_move_screen.gd. Each move is driven on the
## same map its own validator uses, so a failure here is about the prompt rather
## than about the move.
##
##   Godot --headless --path . -s res://tools/validate_field_move_prompts.gd

const GAME_IDS: Array[StringName] = [&"gold", &"silver", &"crystal"]

## validate_cut.gd's Ilex Forest tree, and the cell it is faced from.
const ILEX_GROUP: int = 3
const ILEX_NUMBER_CRYSTAL: int = 52
const ILEX_NUMBER_GOLD_SILVER: int = 44
const ILEX_TREE_CELL := Vector2i(8, 25)

## validate_surf.gd's New Bark Town shore, the same in all three games.
const NEW_BARK_GROUP: int = 24
const NEW_BARK_NUMBER: int = 4
const NEW_BARK_SHORE_CELL := Vector2i(17, 6)
const NEW_BARK_WATER_CELL := Vector2i(18, 6)

## validate_headbutt.gd's Ilex Forest tree, faced from below.
const ILEX_HEADBUTT_CELL := Vector2i(13, 0)
const ILEX_HEADBUTT_STAND := Vector2i(13, 1)

var _failures: PackedStringArray = []


func _initialize() -> void:
	for game_id: StringName in GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		var crystal: bool = Gen2WorldState.is_crystal_profile(data)
		_verify_cut_prompt(game_id, data, crystal)
		_verify_surf_prompt(game_id, data, crystal)
		_verify_headbutt_prompt(game_id, data, crystal)
	_finish()


## TryCutOW: CheckPartyMove, then ENGINE_HIVEBADGE, then AskCutScript. A failure
## of either gate is CantCutScript's _CanCutText, which has no yes/no behind it.
func _verify_cut_prompt(game_id: StringName, data: GameData, crystal: bool) -> void:
	var number: int = ILEX_NUMBER_CRYSTAL if crystal else ILEX_NUMBER_GOLD_SILVER
	var world: Gen2WorldAPI = _world(
		data, ILEX_GROUP, number, ILEX_TREE_CELL + Vector2i.UP,
		Gen2WorldSprite.FACING_DOWN, Gen2WorldFieldMove.MOVE_CUT,
		Gen2WorldFieldMove.BADGE_HIVE, crystal
	)
	if world == null:
		_fail("%s: Ilex Forest is missing." % game_id)
		return
	var opened: Array = world.interact()
	if not _check(
		_waiting_text(opened) == Gen2WorldScriptRunner.CUT_ASK_TEXT,
		"%s: facing Ilex Forest's cut tree asked %s." % [game_id, _waiting_text(opened)]
	):
		return
	_check(
		_choice_offered(world.run_event_queue(true)),
		"%s: AskCutScript's yesorno did not follow its text." % game_id
	)
	var confirmed: Array = world.choose_script_input(0)
	_check(
		_confirmed_move(confirmed) == Gen2WorldFieldMove.MOVE_CUT,
		"%s: a yes did not confirm CUT." % game_id
	)

	# The badge alone decides between the offer and CantCutScript, so the same
	# tree with no badge is the refusal and nothing else.
	var unbadged: Gen2WorldAPI = _world(
		data, ILEX_GROUP, number, ILEX_TREE_CELL + Vector2i.UP,
		Gen2WorldSprite.FACING_DOWN, Gen2WorldFieldMove.MOVE_CUT, -1, crystal
	)
	var refused: Array = unbadged.interact()
	_check(
		_waiting_text(refused) == Gen2WorldScriptRunner.CUT_CAN_TEXT,
		"%s: an unbadged cut tree said %s." % [game_id, _waiting_text(refused)]
	)
	_check(
		StringName((unbadged.run_event_queue(true)[0] as Dictionary).get("status", &"")) \
			== &"complete",
		"%s: CantCutScript offered a choice it does not have." % game_id
	)


## TrySurfOW is the `.surf` fallback every tile that matched nothing else
## reaches, and every one of its failures is silent.
func _verify_surf_prompt(game_id: StringName, data: GameData, crystal: bool) -> void:
	var world: Gen2WorldAPI = _world(
		data, NEW_BARK_GROUP, NEW_BARK_NUMBER, NEW_BARK_SHORE_CELL,
		Gen2WorldSprite.FACING_RIGHT, Gen2WorldFieldMove.MOVE_SURF,
		Gen2WorldFieldMove.BADGE_FOG, crystal
	)
	if world == null:
		_fail("%s: New Bark Town is missing." % game_id)
		return
	_check(
		world.collision_permission_at(NEW_BARK_WATER_CELL) == Gen2WorldCollision.WATER_TILE,
		"%s: New Bark Town %s is not water." % [game_id, NEW_BARK_WATER_CELL]
	)
	var opened: Array = world.interact()
	if not _check(
		_waiting_text(opened) == Gen2WorldScriptRunner.SURF_ASK_TEXT,
		"%s: facing New Bark Town's water asked %s." % [game_id, _waiting_text(opened)]
	):
		return
	world.run_event_queue(true)
	_check(
		_confirmed_move(world.choose_script_input(0)) == Gen2WorldFieldMove.MOVE_SURF,
		"%s: a yes did not confirm SURF." % game_id
	)

	# Without the badge TrySurfOW answers no carry: no text, no choice.
	var unbadged: Gen2WorldAPI = _world(
		data, NEW_BARK_GROUP, NEW_BARK_NUMBER, NEW_BARK_SHORE_CELL,
		Gen2WorldSprite.FACING_RIGHT, Gen2WorldFieldMove.MOVE_SURF, -1, crystal
	)
	_check(
		_silent(unbadged.interact()),
		"%s: an unbadged shore was not silent." % game_id
	)
	# Facing away from the water is not the surf branch at all.
	var inland: Gen2WorldAPI = _world(
		data, NEW_BARK_GROUP, NEW_BARK_NUMBER, NEW_BARK_SHORE_CELL,
		Gen2WorldSprite.FACING_LEFT, Gen2WorldFieldMove.MOVE_SURF,
		Gen2WorldFieldMove.BADGE_FOG, crystal
	)
	_check(
		inland.interact().is_empty(),
		"%s: facing inland produced a prompt." % game_id
	)


## TryHeadbuttOW is CheckPartyMove and nothing else, so its only two answers are
## the ask and silence.
func _verify_headbutt_prompt(game_id: StringName, data: GameData, crystal: bool) -> void:
	var number: int = ILEX_NUMBER_CRYSTAL if crystal else ILEX_NUMBER_GOLD_SILVER
	var world: Gen2WorldAPI = _world(
		data, ILEX_GROUP, number, ILEX_HEADBUTT_STAND, Gen2WorldSprite.FACING_UP,
		Gen2WorldFieldMove.MOVE_HEADBUTT, -1, crystal
	)
	if world == null:
		_fail("%s: Ilex Forest is missing." % game_id)
		return
	var opened: Array = world.interact()
	_check(
		_waiting_text(opened) == Gen2WorldScriptRunner.HEADBUTT_ASK_TEXT,
		"%s: facing Ilex Forest's headbutt tree asked %s." % [game_id, _waiting_text(opened)]
	)
	_check(
		_choice_offered(world.run_event_queue(true)),
		"%s: AskHeadbuttScript's yesorno did not follow its text." % game_id
	)

	var unknowing: Gen2WorldAPI = _world(
		data, ILEX_GROUP, number, ILEX_HEADBUTT_STAND, Gen2WorldSprite.FACING_UP,
		Gen2WorldFieldMove.MOVE_CUT, -1, crystal
	)
	_check(
		_silent(unknowing.interact()),
		"%s: a headbutt tree without the move was not silent." % game_id
	)
	print("%s: cut, surf and headbutt prompts answered on their own maps." % game_id)


## A world standing where it was put, knowing one move and holding at most one
## badge. Every field-move gate reads only these.
func _world(
	data: GameData, group: int, number: int, cell: Vector2i, facing: int,
	move: int, badge: int, crystal: bool
) -> Gen2WorldAPI:
	var state := Gen2WorldState.new()
	if badge >= 0:
		state.set_engine_flag(Gen2WorldState.badge_flag(badge, crystal))
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, group, number, cell, state)
	if world == null:
		return null
	world.player_facing = facing
	world.set_player_id(0)
	world.set_party_summary(
		1, false, [1] as Array[int], [[move]], ["MON"], [false]
	)
	return world


func _waiting_text(results: Array) -> String:
	if results.is_empty():
		return ""
	var result: Dictionary = results[0]
	if StringName(result.get("status", &"")) != &"waiting":
		return ""
	return String((result.get("event", {}) as Dictionary).get("text", ""))


func _choice_offered(results: Array) -> bool:
	if results.is_empty():
		return false
	var event: Dictionary = (results[0] as Dictionary).get("event", {})
	return StringName(event.get("type", &"")) == &"choice"


## `.noevent`: the player event ends having shown nothing. A completed result
## with no events is what that looks like here.
func _silent(results: Array) -> bool:
	if results.is_empty():
		return true
	var result: Dictionary = results[0]
	return StringName(result.get("status", &"")) == &"complete" \
		and (result.get("events", []) as Array).is_empty()


func _confirmed_move(results: Array) -> int:
	for result: Variant in results:
		if not result is Dictionary:
			continue
		for event: Variant in (result as Dictionary).get("events", []):
			if event is Dictionary \
				and StringName((event as Dictionary).get("type", &"")) == &"field_move_confirmed":
				return int((event as Dictionary).get("move", 0))
	return 0


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS field move prompts: the tile chain, both gates and all three answers verified.")
		quit(0)
		return
	for message: String in _failures:
		print("FAIL %s" % message)
	quit(1)
