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
	var save: Gen2SaveData = Gen2SaveStore.create_new_game(data, 0, "ASH")
	if save == null:
		return {"ok": false, "reason": "could not create source-shaped new game"}
	save.world = world.snapshot()
	var random := RandomNumberGenerator.new()
	random.seed = 7
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
	var mom_run: Dictionary = _drain_story(world, mom_results, save, random)
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
	world.player_cell = Vector2i(town_warp["x"], town_warp["y"])
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
	var teacher_run: Dictionary = _drain_story(world, teacher, save, random)
	path.append({
		"step": "new_bark_teacher",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"trigger_cell": _cell_value_from_vector(teacher_cell),
		"entry_statuses": _statuses(entry),
		"run": teacher_run,
	})

	var lab_warp: Dictionary = _warp_to(world.current_map, 24, 5)
	if lab_warp.is_empty():
		return {"ok": false, "path": path, "reason": "missing New Bark to Elm lab warp"}
	world.player_cell = Vector2i(lab_warp["x"], lab_warp["y"])
	transition = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Elm lab warp failed"}
	var lab_entry: Array = world.dispatch_map_entry()
	var lab_entry_run: Dictionary = _drain_story(world, lab_entry, save, random)
	path.append({
		"step": "elm_lab_entry_scene",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": lab_entry_run,
	})
	if not bool(lab_entry_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Elm lab entry scene did not finish"}

	# The source Cyndaquil ball is object 2 at (6,3). Interact from its
	# validated south-facing cell so the imported object script owns the choice.
	world.player_cell = Vector2i(6, 4)
	world.player_facing = Gen2WorldSprite.FACING_UP
	var starter: Array = world.interact()
	var starter_run: Dictionary = _drain_story(world, starter, save, random)
	path.append({
		"step": "elm_lab_cyndaquil_handoff",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": starter_run,
	})
	if not bool(starter_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "starter handoff did not finish"}

	# Elm's directions scene arms the imported aide Potion event. The second
	# scene, which gives Poké Balls, belongs to the later Mystery Egg return and
	# is deliberately not skipped here.
	var potion_events: Array = []
	for target: Vector2i in [Vector2i(4, 8), Vector2i(5, 8)]:
		var walked_to_potion: Dictionary = _walk_to_story_cell(world, target)
		potion_events = walked_to_potion.get("events", [])
		if not potion_events.is_empty():
			break
	var potion_run: Dictionary = _drain_story(world, potion_events, save, random, data)
	path.append({
		"step": "elm_lab_aide_potion",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": potion_run,
		"items": _named_items(data, world.state.items()),
	})
	if not bool(potion_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "aide Potion event did not finish"}

	var lab_exit: Dictionary = _warp_to(world.current_map, 24, 4)
	if lab_exit.is_empty():
		return {"ok": false, "path": path, "reason": "missing Elm lab exit warp"}
	world.player_cell = Vector2i(lab_exit["x"], lab_exit["y"])
	transition = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "lab exit warp failed"}
	var town_entry: Array = world.dispatch_map_entry()
	var town_entry_run: Dictionary = _drain_story(world, town_entry, save, random, data)
	path.append({
		"step": "new_bark_after_starter",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": town_entry_run,
	})
	if not bool(town_entry_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "New Bark entry did not finish"}

	var route_transition: Dictionary = _walk_to_connection(world, "west", 24, 3)
	path.append({
		"step": "new_bark_to_route_29",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"transition": _transition_value(route_transition.get("transition", {})),
	})
	if not bool(route_transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "New Bark to Route 29 connection failed"}
	var route_entry: Array = world.dispatch_map_entry()
	var route_entry_run: Dictionary = _drain_story(world, route_entry, save, random, data)
	path.append({
		"step": "route_29_entry",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": route_entry_run,
	})
	if not bool(route_entry_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Route 29 entry did not finish"}

	var city_transition: Dictionary = _walk_to_connection(world, "west", 26, 3)
	path.append({
		"step": "route_29_to_cherrygrove",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"transition": _transition_value(city_transition.get("transition", {})),
	})
	if not bool(city_transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Route 29 to Cherrygrove connection failed"}
	var city_entry: Array = world.dispatch_map_entry()
	var city_entry_run: Dictionary = _drain_story(world, city_entry, save, random, data)
	path.append({
		"step": "cherrygrove_entry",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": city_entry_run,
		"scene": world.state.map_scene(26, 3),
	})
	if not bool(city_entry_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Cherrygrove entry did not finish"}

	var route30_transition: Dictionary = _walk_to_connection(world, "north", 26, 1)
	path.append({
		"step": "cherrygrove_to_route_30",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"transition": _transition_value(route30_transition.get("transition", {})),
	})
	if not bool(route30_transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Cherrygrove to Route 30 connection failed"}
	var route30_entry: Array = world.dispatch_map_entry()
	var route30_entry_run: Dictionary = _drain_story(world, route30_entry, save, random, data)
	path.append({
		"step": "route_30_entry",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": route30_entry_run,
	})
	if not bool(route30_entry_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Route 30 entry did not finish"}

	var mr_pokemon_warp: Dictionary = _warp_to(world.current_map, 26, 10)
	if mr_pokemon_warp.is_empty():
		return {"ok": false, "path": path, "reason": "missing Route 30 to Mr Pokemon warp"}
	world.player_cell = Vector2i(mr_pokemon_warp["x"], mr_pokemon_warp["y"])
	transition = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Mr Pokemon warp failed"}
	var mr_pokemon_entry: Array = world.dispatch_map_entry()
	var mr_pokemon_run: Dictionary = _drain_story(world, mr_pokemon_entry, save, random, data)
	path.append({
		"step": "mr_pokemon_mystery_egg",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": mr_pokemon_run,
		"items": _named_items(data, world.state.items()),
		"engine_flags": world.state.engine_flags(),
		"map_scenes": world.state.map_scenes(),
	})
	if not bool(mr_pokemon_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Mr Pokemon event did not finish"}

	var return_warp: Dictionary = _warp_to(world.current_map, 26, 1)
	if return_warp.is_empty():
		return {"ok": false, "path": path, "reason": "missing Mr Pokemon return warp"}
	world.player_cell = Vector2i(return_warp["x"], return_warp["y"])
	transition = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Route 30 return warp failed"}
	var route30_return: Array = world.dispatch_map_entry()
	var route30_return_run: Dictionary = _drain_story(world, route30_return, save, random, data)
	path.append({
		"step": "route_30_return",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": route30_return_run,
	})
	if not bool(route30_return_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Route 30 return did not finish"}

	var city_return: Dictionary = _walk_to_connection(world, "south", 26, 3)
	path.append({
		"step": "route_30_to_cherrygrove_return",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"transition": _transition_value(city_return.get("transition", {})),
	})
	if not bool(city_return.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Route 30 to Cherrygrove return failed"}
	var city_return_entry: Array = world.dispatch_map_entry()
	var city_return_run: Dictionary = _drain_story(world, city_return_entry, save, random, data)
	path.append({
		"step": "cherrygrove_rival_scene_entry",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": city_return_run,
		"scene": world.state.map_scene(26, 3),
	})
	if not bool(city_return_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Cherrygrove return entry did not finish"}

	var rival_events: Array = []
	for target: Vector2i in [Vector2i(33, 6), Vector2i(33, 7)]:
		var walked_to_rival: Dictionary = _walk_to_story_cell(world, target)
		rival_events = walked_to_rival.get("events", [])
		if not rival_events.is_empty():
			break
	if rival_events.is_empty():
		return {
			"ok": false, "path": path,
			"reason": "Cherrygrove rival event was not dispatched",
		}
	var rival_run: Dictionary = _drain_story(world, rival_events, save, random, data)
	path.append({
		"step": "cherrygrove_first_rival",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": rival_run,
		"scene": world.state.map_scene(26, 3),
	})
	if not bool(rival_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Cherrygrove rival event did not finish"}

	var route29_return: Dictionary = _walk_to_connection(world, "east", 24, 3)
	path.append({
		"step": "cherrygrove_to_route_29_after_rival",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"transition": _transition_value(route29_return.get("transition", {})),
	})
	if not bool(route29_return.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Cherrygrove to Route 29 return failed"}
	var route29_return_entry: Array = world.dispatch_map_entry()
	var route29_return_run: Dictionary = _drain_story(
		world, route29_return_entry, save, random, data
	)
	path.append({
		"step": "route_29_after_rival",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": route29_return_run,
	})
	if not bool(route29_return_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Route 29 return entry did not finish"}

	var new_bark_return: Dictionary = _walk_to_connection(world, "east", 24, 4)
	path.append({
		"step": "route_29_to_new_bark_after_rival",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"transition": _transition_value(new_bark_return.get("transition", {})),
	})
	if not bool(new_bark_return.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Route 29 to New Bark return failed"}
	var new_bark_return_entry: Array = world.dispatch_map_entry()
	var new_bark_return_run: Dictionary = _drain_story(
		world, new_bark_return_entry, save, random, data
	)
	path.append({
		"step": "new_bark_after_rival",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": new_bark_return_run,
	})
	if not bool(new_bark_return_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "New Bark return entry did not finish"}

	var lab_return_warp: Dictionary = _warp_to(world.current_map, 24, 5)
	if lab_return_warp.is_empty():
		return {"ok": false, "path": path, "reason": "missing New Bark return lab warp"}
	world.player_cell = Vector2i(lab_return_warp["x"], lab_return_warp["y"])
	transition = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "return lab warp failed"}
	var officer_entry: Array = world.dispatch_map_entry()
	var officer_entry_run: Dictionary = _drain_story(world, officer_entry, save, random, data)
	path.append({
		"step": "elm_lab_officer_entry",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": officer_entry_run,
		"scene": world.state.map_scene(24, 5),
	})
	if not bool(officer_entry_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Elm lab officer entry did not finish"}

	var officer_events: Array = []
	for target: Vector2i in [Vector2i(4, 5), Vector2i(5, 5)]:
		var walked_to_officer: Dictionary = _walk_to_story_cell(world, target)
		officer_events = walked_to_officer.get("events", [])
		if not officer_events.is_empty():
			break
	var officer_run: Dictionary = _drain_story(world, officer_events, save, random, data)
	path.append({
		"step": "elm_lab_officer_dialogue",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": officer_run,
		"scene": world.state.map_scene(24, 5),
	})
	if not bool(officer_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Elm lab officer event did not finish"}

	var elm_events: Array = []
	var walked_to_elm: Dictionary = _walk_to_story_cell(world, Vector2i(5, 3))
	if bool(walked_to_elm.get("ok", false)):
		world.player_facing = Gen2WorldSprite.FACING_UP
		elm_events = world.interact()
	var elm_run: Dictionary = _drain_story(world, elm_events, save, random, data, true)
	path.append({
		"step": "elm_lab_mystery_egg_return",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": elm_run,
		"items": _named_items(data, world.state.items()),
		"scene": world.state.map_scene(24, 5),
	})
	if not bool(elm_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Elm mystery egg return did not finish"}

	var balls_events: Array = []
	for target: Vector2i in [Vector2i(4, 8), Vector2i(5, 8)]:
		var walked_to_balls: Dictionary = _walk_to_story_cell(world, target)
		balls_events = walked_to_balls.get("events", [])
		if not balls_events.is_empty():
			break
	var balls_run: Dictionary = _drain_story(world, balls_events, save, random, data, true)
	path.append({
		"step": "elm_lab_aide_pokeballs",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": balls_run,
		"items": _named_items(data, world.state.items()),
		"scene": world.state.map_scene(24, 5),
	})
	if not bool(balls_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Aide Poke Ball event did not finish"}

	# Route 30's corridor north is sealed until ElmAfterTheftScript's
	# setevent EVENT_ROUTE_30_BATTLE hides the two objects standing on it
	# (maps/Route30.asm, maps/ElmsLab.asm; CheckObjectFlag in
	# engine/overworld/map_objects_2.asm masks an object whose flag is set).
	# The Mystery Egg return above is what sets it, so the route walks from
	# here on the same world and state.
	var lab_exit_warp: Dictionary = _warp_to(world.current_map, 24, 4)
	if lab_exit_warp.is_empty():
		return {"ok": false, "path": path, "reason": "missing Elm lab exit warp"}
	world.player_cell = Vector2i(lab_exit_warp["x"], lab_exit_warp["y"])
	transition = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Elm lab exit warp failed"}
	var departure_entry: Array = world.dispatch_map_entry()
	var departure_run: Dictionary = _drain_story(world, departure_entry, save, random, data)
	path.append({
		"step": "new_bark_departure",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": departure_run,
	})
	if not bool(departure_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "New Bark departure entry did not finish"}

	var legs: Array = [
		{"step": "new_bark_to_route_29_north", "direction": "west", "group": 24, "number": 3},
		{"step": "route_29_to_cherrygrove_north", "direction": "west", "group": 26, "number": 3},
		{"step": "cherrygrove_to_route_30_north", "direction": "north", "group": 26, "number": 1},
		{"step": "route_30_to_route_31", "direction": "north", "group": 26, "number": 2},
	]
	for leg: Dictionary in legs:
		var walked: Dictionary = _walk_connection_resolving(
			world, String(leg["direction"]), int(leg["group"]), int(leg["number"]),
			save, random, data
		)
		var leg_entry: Array = world.dispatch_map_entry()
		var leg_run: Dictionary = _drain_story(world, leg_entry, save, random, data)
		path.append({
			"step": String(leg["step"]),
			"map": _map_value(world),
			"cell": _cell_value(world),
			"transition": _transition_value(walked.get("transition", {})),
			"encounters": walked.get("encounters", []),
			"run": leg_run,
		})
		if not bool(walked.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "%s failed: %s" % [leg["step"], walked.get("reason", "")],
			}
		if not bool(leg_run.get("terminal", false)):
			return {"ok": false, "path": path, "reason": "%s entry did not finish" % leg["step"]}

	# Route 31 reaches Violet City through Route31VioletGate, not through its
	# west map connection: the map's four westmost cell columns are wall on
	# every row, so no walkable west edge exists (maps/Route31.asm's
	# warp_event 4, 6 and maps/Route31VioletGate.asm's warp_event 0, 4).
	var gate_walk: Dictionary = _walk_cell_resolving(world, Vector2i(4, 6), save, random, data)
	path.append({
		"step": "route_31_to_violet_gate",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": gate_walk.get("encounters", []),
	})
	if not bool(gate_walk.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 31 gate approach failed: %s" % gate_walk.get("reason", ""),
		}
	transition = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Route 31 Violet gate warp failed"}
	var gate_entry: Array = world.dispatch_map_entry()
	var gate_run: Dictionary = _drain_story(world, gate_entry, save, random, data)
	path.append({
		"step": "violet_gate_entry",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": gate_run,
	})
	if not bool(gate_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Violet gate entry did not finish"}

	var city_side: Dictionary = _walk_cell_resolving(world, Vector2i(0, 4), save, random, data)
	if not bool(city_side.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Violet gate west exit unreachable: %s" % city_side.get("reason", ""),
		}
	transition = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Violet gate to Violet City warp failed"}
	var violet_entry: Array = world.dispatch_map_entry()
	var violet_entry_run: Dictionary = _drain_story(world, violet_entry, save, random, data)
	path.append({
		"step": "violet_city_entry",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": violet_entry_run,
	})
	if not bool(violet_entry_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Violet City entry did not finish"}

	# The Pokemon Center nurse reads CheckPokerus and VAR_PARTYCOUNT, so the
	# world needs the read-only party mirror before either can resolve.
	world.set_party_summary(save.party.size(), false)

	var pokecenter_warp: Dictionary = _warp_to(world.current_map, 10, 10)
	if pokecenter_warp.is_empty():
		return {"ok": false, "path": path, "reason": "missing Violet Pokemon Center warp"}
	world.player_cell = Vector2i(pokecenter_warp["x"], pokecenter_warp["y"])
	transition = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Violet Pokemon Center warp failed"}
	var pokecenter_entry: Array = world.dispatch_map_entry()
	var pokecenter_entry_run: Dictionary = _drain_story(world, pokecenter_entry, save, random, data)
	path.append({
		"step": "violet_pokecenter_entry",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": pokecenter_entry_run,
	})

	# VioletPokecenter1F places the nurse object at block (3,1); the counter
	# tile directly below her at (3,2) is not walkable, so ordinary pathfinding
	# cannot reach it (a counter, not a ledge; Gen2WorldCollision.allows_hop
	# does not apply). The player is placed there directly rather than
	# guessing an unverified counter-side approach.
	world.player_cell = Vector2i(3, 2)
	world.player_facing = Gen2WorldSprite.FACING_UP
	var nurse_events: Array = world.interact()
	for mon: Gen2SaveMon in save.party:
		mon.hp = 1
	var nurse_run: Dictionary = _drain_story(world, nurse_events, save, random, data)
	path.append({
		"step": "violet_pokecenter_nurse",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": nurse_run,
		"party_hp_after": _party_hp(save),
	})
	if not bool(nurse_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Pokemon Center nurse event did not finish"}

	var pokecenter_exit: Dictionary = _warp_to(world.current_map, 10, 5)
	if pokecenter_exit.is_empty():
		return {"ok": false, "path": path, "reason": "missing Violet Pokemon Center exit warp"}
	world.player_cell = Vector2i(pokecenter_exit["x"], pokecenter_exit["y"])
	transition = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Violet Pokemon Center exit warp failed"}
	path.append({"step": "violet_city_after_heal", "map": _map_value(world), "cell": _cell_value(world)})

	var gym_warp: Dictionary = _warp_to(world.current_map, 10, 7)
	if gym_warp.is_empty():
		return {"ok": false, "path": path, "reason": "missing Violet Gym warp"}
	world.player_cell = Vector2i(gym_warp["x"], gym_warp["y"])
	transition = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Violet Gym warp failed"}
	var gym_entry: Array = world.dispatch_map_entry()
	var gym_entry_run: Dictionary = _drain_story(world, gym_entry, save, random, data)
	path.append({
		"step": "violet_gym_entry",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": gym_entry_run,
	})

	# Falkner is object 0 at block (5,1); facing up from (5,2) matches the
	# source's faceplayer interaction cell. The gym's two Bird Keepers stand
	# on sight lines across the way to him, so they are fought on the approach
	# exactly as they are on the cartridge.
	var falkner_events: Array = []
	var walked_to_falkner: Dictionary = _walk_cell_resolving(
		world, Vector2i(5, 2), save, random, data
	)
	path.append({
		"step": "violet_gym_bird_keepers",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": walked_to_falkner.get("encounters", []),
	})
	if not bool(walked_to_falkner.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Falkner approach failed: %s" % walked_to_falkner.get("reason", ""),
		}
	world.player_facing = Gen2WorldSprite.FACING_UP
	falkner_events = world.interact()
	var falkner_run: Dictionary = _drain_story(world, falkner_events, save, random, data, true)
	path.append({
		"step": "violet_gym_falkner",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": falkner_run,
		"badge_count": world.state.badge_count(),
		"engine_flags": world.state.engine_flags(),
	})
	if not bool(falkner_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Falkner event did not finish"}

	var party_summary: Array = []
	for mon: Gen2SaveMon in save.party:
		party_summary.append({
			"species": mon.species,
			"level": mon.level,
			"item": mon.item,
		})
	return {
		"ok": true,
		"path": path,
		"party": party_summary,
		"event_flags": world.state.event_flags(),
		"map_scenes": world.state.to_dict().get("map_scenes", {}),
		"badge_count": world.state.badge_count(),
	}


func _party_hp(save: Gen2SaveData) -> Array:
	var values: Array = []
	for mon: Gen2SaveMon in save.party:
		values.append(int(mon.hp))
	return values


## Runs a dispatched event list to its terminal state. [param require_events]
## is set by a step whose whole point is that an imported script ran: without
## it an empty [param initial] drains in zero iterations and reports terminal,
## so a step that silently found nothing to talk to passes. Map-entry steps
## leave it false, since a map with no entry callback legitimately dispatches
## nothing.
func _drain_story(
	world: Gen2WorldAPI,
	initial: Array,
	save: Gen2SaveData = null,
	random: RandomNumberGenerator = null,
	data: GameData = null,
	require_events: bool = false,
) -> Dictionary:
	if require_events and initial.is_empty():
		return {
			"statuses": [],
			"waits": 0,
			"pending_trace": [],
			"battles": [],
			"terminal": false,
			"reason": "no events dispatched",
			"details": "",
		}
	var results: Array = initial.duplicate(true)
	var statuses: Array = _statuses(results)
	var waits: int = 0
	var last_reason: String = ""
	var last_details: String = ""
	var pending_trace: Array[String] = []
	var battles: Array = []
	var catch_tutorials: int = 0
	var approaches: Array = []
	for result: Dictionary in results:
		if not bool(result.get("ok", false)):
			last_reason = String(result.get("reason", "script_failed"))
			last_details = JSON.stringify(result.get("details", result))
			break
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
			var request_kind: StringName = StringName(request.get("kind", &""))
			if request_kind == &"rival_name_requested":
				var name_host_result: Dictionary = Gen2WorldHost.complete_runtime_request(
					world, {"ok": true, "name": "SILVER"}, save, false, random
				)
				if not bool(name_host_result.get("ok", false)):
					last_reason = String(name_host_result.get("reason", "rival name host failed"))
					last_details = JSON.stringify(name_host_result.get("details", {}))
					break
				results = name_host_result.get("results", [])
			elif request_kind in [&"pokemon_requested", &"trade_requested", &"party_heal_requested"]:
				var host_result: Dictionary = Gen2WorldHost.complete_runtime_request(
					world, {"ok": true}, save, false, random
				)
				if not bool(host_result.get("ok", false)):
					last_reason = String(host_result.get("reason", "party host failed"))
					last_details = JSON.stringify(host_result.get("details", {}))
					break
				results = host_result.get("results", [])
			elif request_kind == &"battle_requested":
				var player_party: Gen2Party = (
					Gen2SaveBattleAdapter.to_battle_party(data, save)
					if data != null and save != null else Gen2WorldBattleAdapter.fallback_party(data)
				)
				var prepared: Dictionary = Gen2WorldBattleAdapter.prepare(
					data, request, player_party, random
				)
				if not bool(prepared.get("ok", false)):
					last_reason = String(prepared.get("reason", "battle setup failed"))
					last_details = JSON.stringify(prepared.get("details", {}))
					break
				var enemy_party: Gen2Party = prepared.get("enemy_party", null)
				battles.append({
					"trainer_class": int(prepared.get("trainer_class", 0)),
					"trainer_index": int(prepared.get("trainer_index", 0)),
					"enemy_species": int(enemy_party.active_mon().species)
						if enemy_party != null and enemy_party.active_mon() != null else 0,
					"battle_type": int(request.get("values", {}).get("battle_type", 0)),
					"can_lose": bool(request.get("values", {}).get("can_lose", false)),
				})
				results = world.complete_runtime_request({
					"ok": true,
					"outcome": Gen2WorldBattleAdapter.OUTCOME_WON,
				})
			elif request_kind == &"trainer_approach_requested":
				# Route 30's trainers see the player on the corridor north, so
				# the walked route runs the source presentation: shock emote for
				# TRAINER_SHOCK_FRAMES, then one slow step per planned cell,
				# then the facing update, before the seen text resumes. The
				# same order tools/validate_crystal_route30_trainer.gd checks.
				var approach_values: Dictionary = request.get("values", {})
				var approach_index: int = int(approach_values.get("object_index", -1))
				var raw_direction: Variant = approach_values.get("direction", Vector2i.ZERO)
				var approach_direction: Vector2i = (
					raw_direction if raw_direction is Vector2i else Vector2i.ZERO
				)
				var plan: Dictionary = world.start_trainer_approach(
					approach_index, approach_direction,
					int(approach_values.get("distance", 0))
				)
				if not bool(plan.get("ok", false)):
					last_reason = String(plan.get("reason", "trainer approach plan failed"))
					last_details = JSON.stringify(plan)
					break
				for _frame: int in int(plan.get("emote_frames", 0)):
					world.tick()
				var approach_failed: bool = false
				for path_step: Vector2i in plan.get("path", []):
					var stepped: Dictionary = world.advance_trainer_approach_step(
						approach_index, path_step
					)
					if not bool(stepped.get("ok", false)):
						last_reason = String(stepped.get("reason", "trainer approach step failed"))
						last_details = JSON.stringify(stepped)
						approach_failed = true
						break
				if approach_failed:
					break
				var faced: Dictionary = world.finish_trainer_approach(approach_index)
				if not bool(faced.get("ok", false)):
					last_reason = String(faced.get("reason", "trainer approach finish failed"))
					last_details = JSON.stringify(faced)
					break
				approaches.append({
					"object_index": approach_index,
					"path": plan.get("path", []).size(),
				})
				results = world.complete_runtime_request({
					"ok": true,
					"object_index": approach_index,
					"path": plan.get("path", []),
				})
			elif request_kind == &"catch_tutorial_requested":
				# ElmAfterTheftScript sets SCENE_ROUTE29_CATCH_TUTORIAL, so this
				# is on the route from here on. The source guarantees the ball,
				# and Gen2WorldScriptRunner refuses any other outcome, so the
				# only valid completion is OUTCOME_CAUGHT. It changes no
				# persistent party, PC or ball state.
				catch_tutorials += 1
				results = world.complete_runtime_request({
					"ok": true,
					"outcome": Gen2WorldBattleAdapter.OUTCOME_CAUGHT,
				})
			elif request_kind == &"audio_requested":
				results = world.complete_runtime_request({"ok": true})
			else:
				last_reason = "unsupported preview request: %s" % String(request.get("kind", ""))
				break
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
		"battles": battles,
		"catch_tutorials": catch_tutorials,
		"approaches": approaches,
		"terminal": last_reason.is_empty() \
			and not world.script_input_waiting() and world.pending_runtime_request().is_empty(),
		"reason": last_reason,
		"details": last_details,
}


func _walk_to_connection(
	world: Gen2WorldAPI, direction_name: String, target_group: int, target_number: int
) -> Dictionary:
	if world == null or world.current_map == null:
		return {"ok": false, "reason": "missing world"}
	var connection: Dictionary = {}
	for candidate: Dictionary in world.current_map.connections:
		if String(candidate.get("direction", "")) == direction_name \
			and int(candidate.get("map_group", -1)) == target_group \
			and int(candidate.get("map_number", -1)) == target_number:
			connection = candidate
			break
	if connection.is_empty():
		return {"ok": false, "reason": "missing connection", "direction": direction_name}

	var frontier: Array[Vector2i] = [world.player_cell]
	var previous: Dictionary = {world.player_cell: {"cell": Vector2i(-1, -1), "direction": Vector2i.ZERO}}
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var edge: Vector2i = Vector2i(-1, -1)
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		if _is_connection_edge(world, cell, direction_name):
			edge = cell
			break
		for step: Vector2i in directions:
			var next: Vector2i = _reachable_step(world, cell, step)
			if next.x < 0 or previous.has(next):
				continue
			previous[next] = {"cell": cell, "direction": step}
			frontier.append(next)
	if edge.x < 0:
		return {"ok": false, "reason": "connection edge unreachable", "direction": direction_name}

	var steps: Array[Vector2i] = []
	var cursor: Vector2i = edge
	while cursor != world.player_cell:
		var link: Dictionary = previous[cursor]
		steps.push_front(link["direction"])
		cursor = link["cell"]
	for step: Vector2i in steps:
		var moved: Dictionary = world.move_result(step)
		if not bool(moved.get("ok", false)):
			return {"ok": false, "reason": "walk step failed", "step": step}
		var events: Array = _dispatch_after_step(world)
		if not events.is_empty():
			return {"ok": false, "reason": "connection walk hit a scripted event", "events": events}
	var transition: Dictionary = world.move_result(_connection_direction(direction_name))
	return {
		"ok": bool(transition.get("ok", false)),
		"steps": steps.size(),
		"transition": transition,
	}


## The cell [param step] from [param cell] reaches by an ordinary walk or, when
## that is blocked, a ledge hop (Gen2WorldCollision.allows_hop, mirroring
## Gen2WorldAPI._try_ledge_hop's order and its surf and map-bounds refusals).
## Returns (-1, -1) when neither applies, so a BFS frontier can use it as one
## reachability test. Replaying the recorded direction through
## world.move_result() performs the same hop, so no separate replay step exists.
func _reachable_step(world: Gen2WorldAPI, cell: Vector2i, step: Vector2i) -> Vector2i:
	var direct: Vector2i = cell + step
	if world.can_walk_to(direct):
		return direct
	if world.movement_mode == Gen2WorldAPI.MOVEMENT_SURF:
		return Vector2i(-1, -1)
	if not Gen2WorldCollision.allows_hop(world.collision_code_at(cell), step):
		return Vector2i(-1, -1)
	var landing: Vector2i = cell + step * 2
	var size: Vector2i = world.map_size_cells()
	if landing.x < 0 or landing.y < 0 or landing.x >= size.x or landing.y >= size.y:
		return Vector2i(-1, -1)
	return landing


func _is_connection_edge(world: Gen2WorldAPI, cell: Vector2i, direction_name: String) -> bool:
	var size: Vector2i = world.map_size_cells()
	match direction_name:
		"north": return cell.y == 0
		"south": return cell.y == size.y - 1
		"west": return cell.x == 0
		"east": return cell.x == size.x - 1
	return false


func _connection_direction(direction_name: String) -> Vector2i:
	match direction_name:
		"north": return Vector2i.UP
		"south": return Vector2i.DOWN
		"west": return Vector2i.LEFT
		"east": return Vector2i.RIGHT
	return Vector2i.ZERO


func _named_items(data: GameData, items: Dictionary) -> Dictionary:
	var named: Dictionary = {}
	if data == null:
		return named
	for raw_item: Variant in items:
		var item_name: String = data.item_name(int(raw_item))
		named[item_name if not item_name.is_empty() else String(raw_item)] = int(items[raw_item])
	return named


func _walk_to_story_cell(world: Gen2WorldAPI, target: Vector2i) -> Dictionary:
	if world == null or world.current_map == null:
		return {"ok": false, "reason": "missing world"}
	if world.player_cell == target:
		return {"ok": true, "events": _dispatch_after_step(world, target)}
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
			var next: Vector2i = _reachable_step(world, cell, direction)
			if next.x < 0 or previous.has(next):
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
		events = _dispatch_after_step(world)
		if not events.is_empty():
			break
	return {"ok": true, "steps": steps.size(), "events": events}


## The order Gen2WorldScreen uses after a successful step: a trainer who can
## see the player answers before the cell's own scripts. A walked route past
## Route 30's trainers reaches nothing otherwise, since sight is queued by
## dispatch_sight_events() and never by dispatch_script_events().
func _dispatch_after_step(world: Gen2WorldAPI, cell: Vector2i = Vector2i(-1, -1)) -> Array:
	var sight: Array = world.dispatch_sight_events()
	if not sight.is_empty():
		return sight
	return world.dispatch_script_events(cell if cell.x >= 0 else world.player_cell)


## Walks toward a connection edge, resolving anything met on the way and
## resuming from wherever the walk stopped. Route 30 puts two trainers on the
## corridor north, and a trainer who sees the player interrupts the walk, so a
## single _walk_to_connection() call cannot carry the route on its own.
func _walk_connection_resolving(
	world: Gen2WorldAPI,
	direction_name: String,
	target_group: int,
	target_number: int,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
) -> Dictionary:
	var runs: Array = []
	for _attempt: int in 8:
		var walked: Dictionary = _walk_to_connection(
			world, direction_name, target_group, target_number
		)
		if bool(walked.get("ok", false)):
			walked["encounters"] = runs
			return walked
		var events: Array = walked.get("events", [])
		if events.is_empty():
			walked["encounters"] = runs
			return walked
		var run: Dictionary = _drain_story(world, events, save, random, data, true)
		runs.append({
			"cell": _cell_value(world),
			"statuses": run.get("statuses", []),
			"battles": run.get("battles", []),
		})
		if not bool(run.get("terminal", false)):
			return {
				"ok": false,
				"reason": "encounter on the way to the %s connection did not finish" % direction_name,
				"encounters": runs,
				"details": run.get("reason", ""),
			}
	return {"ok": false, "reason": "connection walk did not settle", "encounters": runs}


## The _walk_to_story_cell() counterpart of _walk_connection_resolving().
func _walk_cell_resolving(
	world: Gen2WorldAPI,
	target: Vector2i,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
) -> Dictionary:
	var runs: Array = []
	for _attempt: int in 8:
		var walked: Dictionary = _walk_to_story_cell(world, target)
		if not bool(walked.get("ok", false)):
			walked["encounters"] = runs
			return walked
		var events: Array = walked.get("events", [])
		if events.is_empty() and world.player_cell == target:
			walked["encounters"] = runs
			return walked
		if events.is_empty():
			return {
				"ok": false,
				"reason": "walk stopped short of %s" % target,
				"encounters": runs,
			}
		var run: Dictionary = _drain_story(world, events, save, random, data, true)
		runs.append({
			"cell": _cell_value(world),
			"statuses": run.get("statuses", []),
			"battles": run.get("battles", []),
		})
		if not bool(run.get("terminal", false)):
			return {
				"ok": false,
				"reason": "encounter on the way to %s did not finish" % target,
				"encounters": runs,
				"details": run.get("reason", ""),
			}
	return {"ok": false, "reason": "walk to %s did not settle" % target, "encounters": runs}


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
