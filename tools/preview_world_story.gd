extends SceneTree

## Exercises map-entry callbacks and one facing interaction from an imported
## cartridge cache without opening the ROM at runtime.
##
##   Godot --headless --path . -s res://tools/preview_world_story.gd -- \
##     crystal 3 19 3 5 1 37,1744
##
## The optional final argument is a comma-separated list of event flags. Facing
## uses the runtime values: down=0, up=1, left=2, right=3. The optional eighth
## argument `home` follows the imported bedroom stair warp into the first floor
## and then the imported first-floor warp into New Bark Town. A ninth argument
## `story` drives the imported first-floor Mom event and the New Bark entry
## event through explicit source inputs.


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 5:
		push_error("Usage: preview_world_story.gd -- <game> <group> <map> <x> <y> [facing] [flags]")
		quit(1)
		return

	var data: GameData = GameData.open(StringName(args[0]))
	if data == null:
		push_error("No usable imported cache for %s." % args[0])
		quit(1)
		return

	var state := Gen2WorldState.new()
	if args.size() >= 7:
		for raw_flag: String in args[6].split(",", false):
			if raw_flag.is_valid_int():
				state.set_event_flag(int(raw_flag))

	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, int(args[1]), int(args[2]), Vector2i(int(args[3]), int(args[4])), state
	)
	if world == null:
		push_error("The imported cache does not contain map %s/%s." % [args[1], args[2]])
		quit(1)
		return

	if args.size() >= 6:
		world.player_facing = int(args[5])
	var entry: Array = world.dispatch_map_entry()
	var interaction: Array = world.interact()
	var output: Dictionary = {
		"game": String(data.id),
		"map": world.map_id(),
		"player_cell": world.player_cell,
		"facing": world.player_facing,
		"event_flags": state.event_flags(),
		"entry": entry,
		"interaction": interaction,
		"pending_input": world.pending_script_input(),
		"visible_objects": world.visible_objects().size(),
		"snapshot": world.snapshot().to_dict(),
	}
	if args.size() >= 8 and args[7] == "home":
		output["home_path"] = _home_path(data)
	if args.size() >= 9 and args[8] == "story":
		output["story_path"] = _story_path(data)
	print(JSON.stringify(output))
	quit(0)


func _home_path(data: GameData) -> Array:
	var path: Array = []
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 24, 7, Vector2i.ZERO)
	if world == null:
		return [{"ok": false, "reason": "missing home map"}]
	var stair_warp: Dictionary = _warp_to(world.current_map, 24, 6)
	if stair_warp.is_empty():
		return [{"ok": false, "reason": "missing home stair warp"}]
	world.player_cell = Vector2i(stair_warp["x"], stair_warp["y"])
	path.append({"step": "players_house_2f", "map": _map_value(world), "cell": _cell_value(world)})
	var transition: Dictionary = world.try_warp()
	path.append({"step": "stairs_to_1f", "transition": _transition_value(transition)})
	if not bool(transition.get("ok", false)):
		return path

	var town_warp: Dictionary = _warp_to(world.current_map, 24, 4)
	if town_warp.is_empty():
		path.append({"ok": false, "reason": "missing first-floor town warp"})
		return path
	world.player_cell = Vector2i(town_warp["x"], town_warp["y"])
	path.append({"step": "players_house_1f", "map": _map_value(world), "cell": _cell_value(world)})
	transition = world.try_warp()
	path.append({"step": "front_door_to_new_bark", "transition": _transition_value(transition)})
	if bool(transition.get("ok", false)):
		var callbacks: Array = world.dispatch_map_entry()
		path.append({
			"step": "new_bark_entry_callbacks",
			"map": _map_value(world),
			"cell": _cell_value(world),
			"callback_count": callbacks.size(),
			"callback_statuses": _statuses(callbacks),
		})
	return path


func _story_path(data: GameData) -> Dictionary:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(data, 24, 7, Vector2i.ZERO)
	if world == null:
		return {"ok": false, "reason": "missing home map"}
	var path: Array = []
	var stair_warp: Dictionary = _warp_to(world.current_map, 24, 6)
	if stair_warp.is_empty():
		return {"ok": false, "reason": "missing home stair warp"}
	world.player_cell = Vector2i(stair_warp["x"], stair_warp["y"])
	var transition: Dictionary = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {"ok": false, "reason": "stair warp failed", "transition": _transition_value(transition)}
	path.append({"map": _map_value(world), "cell": _cell_value(world)})

	var mom_results: Array = []
	for event_cell: Vector2i in [Vector2i(8, 4), Vector2i(9, 4)]:
		world.player_cell = event_cell
		mom_results = world.dispatch_script_events(event_cell)
		if not mom_results.is_empty():
			break
	var mom_run: Dictionary = _drain_story(world, mom_results)
	path.append({
		"step": "players_house_1f_mom",
		"trigger_cell": _cell_value(world),
		"run": mom_run,
		"clock": world.world_clock(),
		"dst_enabled": world.daylight_saving_time_enabled(),
		"engine_flags": world.state.engine_flags(),
	})

	var town_warp: Dictionary = _warp_to(world.current_map, 24, 4)
	if town_warp.is_empty():
		return {"ok": false, "path": path, "reason": "missing first-floor town warp"}
	var walked_to_door: Dictionary = _walk_to_story_cell(
		world, Vector2i(town_warp["x"], town_warp["y"])
	)
	if not bool(walked_to_door.get("ok", false)):
		return {"ok": false, "path": path, "reason": "could not walk to first-floor door"}
	transition = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "town warp failed"}
	var entry: Array = world.dispatch_map_entry()
	var teacher: Array = []
	var teacher_cell := Vector2i(-1, -1)
	for target: Vector2i in [Vector2i(1, 9), Vector2i(1, 8)]:
		var walked_to_teacher: Dictionary = _walk_to_story_cell(world, target)
		teacher = walked_to_teacher.get("events", [])
		if not teacher.is_empty():
			teacher_cell = target
			break
	var teacher_run: Dictionary = _drain_story(world, teacher)
	path.append({
		"step": "new_bark_teacher",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"trigger_cell": _cell_value_from_vector(teacher_cell),
		"entry_statuses": _statuses(entry),
		"run": teacher_run,
	})
	return {"ok": true, "path": path}


func _drain_story(world: Gen2WorldAPI, initial: Array) -> Dictionary:
	var results: Array = initial.duplicate(true)
	var statuses: Array = _statuses(results)
	var waits: int = 0
	var last_reason: String = ""
	var last_details: String = ""
	var pending_trace: Array[String] = []
	for _step: int in 256:
		var input: Dictionary = world.pending_script_input()
		var input_type: StringName = StringName(input.get("type", &""))
		if pending_trace.size() < 24:
			pending_trace.append(String(input_type))
		if input_type in [&"text", &"button"]:
			results = world.run_event_queue(true)
		elif input_type in [&"choice", &"menu"]:
			results = world.choose_script_input(0)
		else:
			var request: Dictionary = world.pending_runtime_request()
			if request.is_empty():
				break
			if pending_trace.size() < 24:
				pending_trace.append("runtime:%s" % String(request.get("kind", "")))
			if StringName(request.get("kind", &"")) != &"audio_requested":
				last_reason = "unsupported preview request: %s" % String(request.get("kind", ""))
				break
			results = world.complete_runtime_request({"ok": true})
		if results.is_empty():
			break
		statuses.append_array(_statuses(results))
		waits += 1
		for result: Dictionary in results:
			if not bool(result.get("ok", false)):
				last_reason = String(result.get("reason", "script_failed"))
				last_details = JSON.stringify(result.get("details", {}))
				break
		if not world.script_input_waiting() and world.pending_runtime_request().is_empty():
			var terminal: bool = false
			for result: Dictionary in results:
				if StringName(result.get("status", &"")) in [&"complete", &"failed"]:
					terminal = true
			if terminal:
				break
	return {
		"statuses": statuses,
		"waits": waits,
		"pending_trace": pending_trace,
		"terminal": not world.script_input_waiting() and world.pending_runtime_request().is_empty(),
		"reason": last_reason,
		"details": last_details,
}


func _walk_to_story_cell(world: Gen2WorldAPI, target: Vector2i) -> Dictionary:
	if world == null or world.current_map == null:
		return {"ok": false, "reason": "missing world"}
	if world.player_cell == target:
		return {"ok": true, "events": world.dispatch_script_events(target)}
	var frontier: Array[Vector2i] = [world.player_cell]
	var previous: Dictionary = {world.player_cell: {"cell": Vector2i(-1, -1), "direction": Vector2i.ZERO}}
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var found: bool = false
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		if cell == target:
			found = true
			break
		for direction: Vector2i in directions:
			var next: Vector2i = cell + direction
			if previous.has(next) or not world.can_walk_to(next):
				continue
			previous[next] = {"cell": cell, "direction": direction}
			frontier.append(next)
	if not found:
		return {"ok": false, "reason": "unreachable target", "target": _cell_value_from_vector(target)}
	var steps: Array[Vector2i] = []
	var cursor: Vector2i = target
	while cursor != world.player_cell:
		var link: Dictionary = previous[cursor]
		steps.push_front(link["direction"])
		cursor = link["cell"]
	var events: Array = []
	for direction: Vector2i in steps:
		var moved: Dictionary = world.move_result(direction)
		if not bool(moved.get("ok", false)):
			return {"ok": false, "reason": "walk step failed", "step": direction}
		events = world.dispatch_script_events(world.player_cell)
		if not events.is_empty():
			break
	return {"ok": true, "steps": steps.size(), "events": events}


func _warp_to(map: Gen2WorldMap, group: int, number: int) -> Dictionary:
	if map == null:
		return {}
	for warp: Dictionary in map.events.get("warps", []):
		if int(warp.get("map_group", -1)) == group and int(warp.get("map_number", -1)) == number:
			return warp.duplicate(true)
	return {}


func _map_value(world: Gen2WorldAPI) -> Array[int]:
	return [world.current_map.group, world.current_map.number]


func _cell_value(world: Gen2WorldAPI) -> Array[int]:
	return [world.player_cell.x, world.player_cell.y]


func _cell_value_from_vector(cell: Vector2i) -> Array[int]:
	return [cell.x, cell.y]


func _transition_value(transition: Dictionary) -> Dictionary:
	return {
		"ok": bool(transition.get("ok", false)),
		"from_map": _vector_value(transition.get("from_map", Vector2i(-1, -1))),
		"from_cell": _vector_value(transition.get("from_cell", Vector2i(-1, -1))),
		"to_map": _vector_value(transition.get("to_map", Vector2i(-1, -1))),
		"to_cell": _vector_value(transition.get("to_cell", Vector2i(-1, -1))),
	}


func _vector_value(value: Variant) -> Array[int]:
	if value is Vector2i:
		return [value.x, value.y]
	return [-1, -1]


func _statuses(results: Array) -> Array[String]:
	var out: Array[String] = []
	for result: Dictionary in results:
		out.append(String(result.get("status", "")))
	return out
