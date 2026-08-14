extends RefCounted

var _r: RefCounted = null

## Verifies the first Route 30 trainer against a freshly imported Crystal cache.
## The expected record comes from the pinned pokecrystal Route30 map source.
##
##   Godot --headless --path . -s res://tools/validate.gd -- crystal_route30_trainer

const MAP_GROUP: int = 26
const MAP_NUMBER: int = 1
const TRAINER_OBJECT_INDEX: int = 1
const TRAINER_CELL := Vector2i(2, 28)
const START_CELL := Vector2i(3, 28)
const SIGHT_CELL := Vector2i(4, 28)
const OBJECT_EVENT_FLAG: int = 1813
const TRAINER_EVENT_FLAG: int = 1449
const TRAINER_GROUP: int = 22
const TRAINER_ID: int = 1


func run(r: RefCounted) -> void:
	_r = r
	var data: GameData = GameData.open(&"crystal")
	if data == null:
		_r.fail("Crystal cache is unavailable. Import roms/crystal.gbc first.")
		return
	var route: Gen2WorldMap = data.world_map(MAP_GROUP, MAP_NUMBER)
	if route == null:
		_r.fail("Route 30 map 26/1 is missing from the Crystal cache.")
		return
	var rows: Array = route.events.get("objects", [])
	if not _r.check(rows.size() > TRAINER_OBJECT_INDEX, "Route 30 trainer object is missing."):
		return
	var first_trainer_index: int = -1
	for index: int in rows.size():
		if rows[index] is Dictionary and int(
			(rows[index] as Dictionary).get("object_type", -1)
		) == Gen2WorldObject.OBJECTTYPE_TRAINER:
			first_trainer_index = index
			break
	_r.check(
		first_trainer_index == TRAINER_OBJECT_INDEX,
		"Joey is not the first Route 30 trainer object in source order."
	)
	var event: Dictionary = (rows[TRAINER_OBJECT_INDEX] as Dictionary).duplicate(true)
	var trainer_value: Variant = event.get("trainer", {})
	if not _r.check(trainer_value is Dictionary, "Joey's trainer record is missing."):
		return
	var trainer: Dictionary = (trainer_value as Dictionary).duplicate(true)
	_verify_imported_record(data, event, trainer)
	_verify_runtime_flow(data, trainer)


func _verify_imported_record(data: GameData, event: Dictionary, trainer: Dictionary) -> void:
	_r.check(
		Vector2i(int(event.get("x", -1)), int(event.get("y", -1))) == TRAINER_CELL,
		"Joey's imported cell does not match the pinned Route30 object event."
	)
	_r.check(
		int(event.get("movement", -1)) == Gen2WorldObject.MOVEMENT_FIXED_RIGHT,
		"Joey's imported facing movement is not fixed right."
	)
	_r.check(int(event.get("sight_range", -1)) == 3, "Joey's sight range is not three.")
	_r.check(
		int(event.get("event_flag", -1)) == OBJECT_EVENT_FLAG,
		"Joey's object visibility flag is incorrect."
	)
	_r.check(
		int(trainer.get("event_flag", -1)) == TRAINER_EVENT_FLAG,
		"Joey's beaten-trainer flag is incorrect."
	)
	_r.check(
		int(trainer.get("event_flag", -1)) != int(event.get("event_flag", -1)),
		"Object visibility and beaten-trainer flags were collapsed."
	)
	_r.check(int(trainer.get("trainer_group", -1)) == TRAINER_GROUP, "Trainer class is wrong.")
	_r.check(int(trainer.get("trainer_id", -1)) == TRAINER_ID, "Trainer party ID is wrong.")
	_r.check(
		int(trainer.get("after_script", 0)) == int(event.get("script", 0)) + 12,
		"After-battle script does not follow the 12-byte trainer record."
	)
	var seen: Dictionary = trainer.get("seen_text", {})
	var win: Dictionary = trainer.get("win_text", {})
	var loss: Dictionary = trainer.get("loss_text", {})
	_r.check(_text_decodes(data, seen), "Joey's seen text is not readable from the cache.")
	_r.check(_text_decodes(data, win), "Joey's win text is not readable from the cache.")
	_r.check(int(loss.get("address", -1)) == 0, "Joey's source loss-text sentinel is not zero.")


func _verify_runtime_flow(data: GameData, trainer_record: Dictionary) -> void:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, MAP_GROUP, MAP_NUMBER, START_CELL, Gen2WorldState.new()
	)
	if not _r.check(world != null, "Route 30 could not be opened through the world API."):
		return
	var joey: Gen2WorldObject = world.objects[TRAINER_OBJECT_INDEX]
	_r.check(joey.cell == TRAINER_CELL, "Joey's live object starts in the wrong cell.")
	_r.check(joey.active, "Joey is hidden with no source flags set.")
	_r.check(joey.facing == Gen2WorldSprite.FACING_RIGHT, "Joey does not face right.")

	var movement: Dictionary = world.move_result(Vector2i.RIGHT)
	_r.check(bool(movement.get("ok", false)), "The source approach setup cell cannot move right.")
	_r.check(world.player_cell == SIGHT_CELL, "The player did not reach Joey's sight line.")

	var sight: Array = world.dispatch_sight_events()
	var sight_source: Dictionary = _single_result(sight, "trainer sight").get("source", {})
	_r.check(int(sight_source.get("object_index", -1)) == TRAINER_OBJECT_INDEX, "Wrong trainer saw the player.")
	_r.check(int(sight_source.get("distance", -1)) == 2, "Joey's sight distance is not two.")
	_r.check(sight_source.get("direction", Vector2i.ZERO) == Vector2i.RIGHT, "Joey's sight direction is wrong.")
	var audio: Dictionary = _runtime_values(sight, &"audio_requested", "encounter music")
	_r.check(audio.get("kind", &"") == &"encounter_music", "Trainer encounter music was not requested.")

	var approach_results: Array = world.complete_runtime_request({
		"ok": true, "audio_played": false,
	})
	var approach: Dictionary = _runtime_values(
		approach_results, &"trainer_approach_requested", "trainer approach"
	)
	_r.check(int(approach.get("object_index", -1)) == TRAINER_OBJECT_INDEX, "Approach object is wrong.")
	_r.check(int(approach.get("distance", -1)) == 2, "Approach distance is wrong.")
	_r.check(approach.get("direction", Vector2i.ZERO) == Vector2i.RIGHT, "Approach direction is wrong.")

	var plan: Dictionary = world.start_trainer_approach(
		TRAINER_OBJECT_INDEX, Vector2i.RIGHT, 2
	)
	_r.check(bool(plan.get("ok", false)), "Joey's approach plan failed.")
	_r.check(plan.get("path", []) == [Vector2i.RIGHT], "Joey does not stop one cell away.")
	_r.check(
		int(plan.get("emote_frames", -1)) == Gen2WorldAPI.TRAINER_SHOCK_FRAMES,
		"Joey's shock-emote duration is wrong."
	)
	for _frame: int in Gen2WorldAPI.TRAINER_SHOCK_FRAMES - 1:
		world.advance_emotes_frame()
	_r.check(joey.emote_visible, "Joey's shock emote ended early.")
	world.advance_emotes_frame()
	_r.check(not joey.emote_visible, "Joey's shock emote outlasted its own count.")

	var step: Dictionary = world.advance_trainer_approach_step(
		TRAINER_OBJECT_INDEX, Vector2i.RIGHT
	)
	_r.check(bool(step.get("ok", false)), "Joey's approach step failed.")
	_r.check(joey.cell == Vector2i(3, 28), "Joey did not stop before the player.")
	var faced: Dictionary = world.finish_trainer_approach(TRAINER_OBJECT_INDEX)
	_r.check(bool(faced.get("ok", false)), "Joey's approach could not finish.")
	_r.check(joey.facing == Gen2WorldSprite.FACING_RIGHT, "Joey's final facing is wrong.")
	_r.check(world.player_facing == Gen2WorldSprite.FACING_LEFT, "Player final facing is wrong.")

	var text_results: Array = world.complete_runtime_request({
		"ok": true, "object_index": TRAINER_OBJECT_INDEX, "path": plan.get("path", []),
	})
	var text_event: Dictionary = _waiting_event(text_results, &"text", "seen text")
	var seen_pointer: Dictionary = trainer_record.get("seen_text", {})
	var decoded: Dictionary = Gen2WorldScript.decode_text(data.world_text(
		int(seen_pointer.get("bank", -1)), int(seen_pointer.get("address", 0))
	))
	_r.check(text_event.get("text", "") == decoded.get("text", ""), "Seen text does not use Joey's pointer.")
	_waiting_event(world.run_event_queue(true), &"button", "seen-text button")
	var battle_results: Array = world.run_event_queue(true)
	var battle: Dictionary = _runtime_values(
		battle_results, &"battle_requested", "trainer battle"
	)
	_r.check(int(battle.get("trainer_group", -1)) == TRAINER_GROUP, "Battle trainer class is wrong.")
	_r.check(int(battle.get("trainer_id", -1)) == TRAINER_ID - 1, "Battle party index is wrong.")
	_r.check(int(battle.get("trainer_flag", -1)) == TRAINER_EVENT_FLAG, "Battle trainer flag is wrong.")

	var completed: Array = world.complete_runtime_request({
		"ok": true, "outcome": Gen2WorldBattleAdapter.OUTCOME_WON,
	})
	var completion: Dictionary = _single_result(completed, "battle completion")
	_r.check(completion.get("status", &"") == &"complete", "Trainer script did not complete after the win.")
	_r.check(_has_event(completion, &"battle_map_reload_requested"), "Battle map reload was not requested.")
	_r.check(world.state.is_event_flag_active(TRAINER_EVENT_FLAG), "Trainer beaten flag was not committed.")
	_r.check(not world.state.is_event_flag_active(OBJECT_EVENT_FLAG), "Object visibility flag changed with the win.")
	_r.check(world.dispatch_sight_events().is_empty(), "Beaten Joey can trigger sight again.")

	world.reload_current_map()
	joey = world.objects[TRAINER_OBJECT_INDEX]
	_r.check(joey.active, "Beaten Joey was hidden by the trainer flag.")
	_r.check(joey.cell == Vector2i(3, 28), "Joey's written approach cell did not survive reload.")
	var after_battle: Array = world.interact()
	var after_result: Dictionary = _single_result(after_battle, "after-battle interaction")
	var source: Dictionary = after_result.get("source", {})
	_r.check(source.get("trainer_phase", &"") == &"after", "Later interaction did not use trainer after phase.")
	_r.check(
		int(source.get("script", 0)) == int(trainer_record.get("after_script", -1)),
		"Later interaction did not use Joey's after-battle script."
	)


func _text_decodes(data: GameData, pointer: Dictionary) -> bool:
	var decoded: Dictionary = Gen2WorldScript.decode_text(data.world_text(
		int(pointer.get("bank", -1)), int(pointer.get("address", 0))
	))
	return bool(decoded.get("ok", false)) and not String(decoded.get("text", "")).is_empty()


func _runtime_values(results: Array, kind: StringName, label: String) -> Dictionary:
	var event: Dictionary = _waiting_event(results, &"runtime_request", label)
	var request: Dictionary = event.get("request", {})
	_r.check(request.get("kind", &"") == kind, "%s request kind is wrong." % label.capitalize())
	return request.get("values", {})


func _waiting_event(results: Array, event_type: StringName, label: String) -> Dictionary:
	var result: Dictionary = _single_result(results, label)
	_r.check(result.get("status", &"") == &"waiting", "%s did not wait." % label.capitalize())
	var event: Dictionary = result.get("event", {})
	_r.check(event.get("type", &"") == event_type, "%s event type is wrong." % label.capitalize())
	return event


func _single_result(results: Array, label: String) -> Dictionary:
	if not _r.check(results.size() == 1, "%s produced %d results." % [label.capitalize(), results.size()]):
		return {}
	if not _r.check(results[0] is Dictionary, "%s result is not a dictionary." % label.capitalize()):
		return {}
	return results[0] as Dictionary


func _has_event(result: Dictionary, event_type: StringName) -> bool:
	for raw: Variant in result.get("events", []):
		if raw is Dictionary and (raw as Dictionary).get("type", &"") == event_type:
			return true
	return false
