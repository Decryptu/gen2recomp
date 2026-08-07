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

## A ring is 30 lead frames plus two 60-frame rings; the budget only has to
## outlast that.
const PHONE_RING_FRAME_BUDGET: int = 256

## SPECIALCALL_ASSISTANT (constants/phone_constants.asm), armed by beating
## Falkner and answered by ElmPhoneCallerScript's .assistant branch.
const SPECIALCALL_ASSISTANT: int = 3


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

	# The bedroom's MAPCALLBACK_NEWMAP is what runs InitializeEventsScript
	# (maps/PlayersHouse2F.asm's PlayersHouse2FInitializeRoomCallback), which
	# sets the story's initial event flags. Skipping it left the walked route on
	# a different flag baseline from a real new game, where world_screen.gd
	# dispatches the same callbacks on the spawn map.
	var bedroom_entry: Array = world.dispatch_map_entry()
	var bedroom_run: Dictionary = _drain_story(world, bedroom_entry, save, random, data, true)
	path.append({
		"step": "players_house_2f_initial_events",
		"map": _map_value(world),
		"run": bedroom_run,
		"event_flag_count": world.state.event_flags().size(),
		"engine_flags": world.state.engine_flags(),
	})
	if not bool(bedroom_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "initial event callbacks did not finish"}

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

	var hive: Dictionary = _hive_badge_path(world, save, random, data, path)
	if not bool(hive.get("ok", false)):
		return hive

	var plain: Dictionary = _plain_badge_path(world, save, random, data, path)
	if not bool(plain.get("ok", false)):
		return plain

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


## Violet City to the Hive Badge, on the same world, state and save. Three
## gates own this leg and each opens the next: the Togepi egg retires Route 32's
## blocking coord event, Kurt hides the Rocket standing on the Slowpoke Well
## corridor, and clearing the well hides the Rocket standing on the Azalea gym
## door. Appends to [param path] and answers only ok or the failure.
func _hive_badge_path(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var leaving_gym: Dictionary = _warp_step(world, 10, 5)
	if not bool(leaving_gym.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Violet Gym exit warp failed"}
	var after_gym: Dictionary = _drain_story(world, world.dispatch_map_entry(), save, random, data)
	path.append({
		"step": "violet_city_after_falkner",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": after_gym,
		"pending_special_call": world.state.pending_special_phone_call(),
	})
	if not bool(after_gym.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Violet City re-entry did not finish"}
	if world.state.pending_special_phone_call() != SPECIALCALL_ASSISTANT:
		return {"ok": false, "path": path, "reason": "Falkner did not arm the assistant call"}

	# data/phone/special_calls.asm gives SPECIALCALL_ASSISTANT the
	# SpecialCallOnlyWhenOutside condition, so the call resolves on Violet City
	# and not in the gym it was armed in. ElmPhoneCallerScript's .assistant
	# branch is the only thing that clears
	# EVENT_ELMS_AIDE_IN_VIOLET_POKEMON_CENTER, which InitializeEventsScript set.
	var call_attempt: Dictionary = world.try_special_phone_call()
	if not bool(call_attempt.get("attempted", false)):
		return {
			"ok": false, "path": path,
			"reason": "assistant call not attempted: %s" % call_attempt.get("reason", ""),
		}
	var call_run: Dictionary = _drain_story(
		world, call_attempt.get("results", []), save, random, data, true
	)
	path.append({
		"step": "elm_assistant_phone_call",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"call_id": int(call_attempt.get("call_id", 0)),
		"run": call_run,
		"pending_special_call": world.state.pending_special_phone_call(),
	})
	if not bool(call_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "assistant call did not finish"}

	# The aide stands at (4,3); (4,4) is the only walkable cell facing him.
	var entering_pokecenter: Dictionary = _warp_step(world, 10, 10)
	if not bool(entering_pokecenter.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Violet Pokemon Center warp failed"}
	var pokecenter_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	var walked_to_aide: Dictionary = _walk_cell_resolving(world, Vector2i(4, 4), save, random, data)
	if not bool(walked_to_aide.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Elm's aide unreachable: %s" % walked_to_aide.get("reason", ""),
		}
	world.player_facing = Gen2WorldSprite.FACING_UP
	var egg_run: Dictionary = _drain_story(world, world.interact(), save, random, data, true)
	path.append({
		"step": "violet_pokecenter_togepi_egg",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"entry_statuses": pokecenter_entry.get("statuses", []),
		"run": egg_run,
		"party": _party_species(save),
		"route_32_scene": world.state.map_scene(10, 1),
	})
	if not bool(egg_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Togepi egg event did not finish"}
	if not _party_has_egg(save):
		return {"ok": false, "path": path, "reason": "the Togepi egg did not reach the party"}
	world.set_party_summary(save.party.size(), false)

	var leaving_pokecenter: Dictionary = _warp_step(world, 10, 5)
	if not bool(leaving_pokecenter.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Violet Pokemon Center exit warp failed"}
	var route32_leg: Dictionary = _walk_connection_resolving(
		world, "south", 10, 1, save, random, data
	)
	var route32_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "violet_city_to_route_32",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": route32_leg.get("encounters", []),
		"run": route32_entry,
	})
	if not bool(route32_leg.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Violet City to Route 32 failed: %s" % route32_leg.get("reason", ""),
		}

	# Route 32's south edge does connect to Route 33, but that lands in the
	# plaza north of Route 33's wall row, whose only exit is the Union Cave
	# warp. The cartridge's own path is Route 32 (6,79) into Union Cave 1F and
	# out again at (17,31), so the leg walks the warps, not the connection.
	var union_cave: Dictionary = _warp_walk(world, Vector2i(6, 79), save, random, data)
	if not bool(union_cave.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 32 to Union Cave failed: %s" % union_cave.get("reason", ""),
		}
	var union_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "route_32_to_union_cave",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": union_cave.get("encounters", []),
		"run": union_entry,
	})

	var route33: Dictionary = _warp_walk(world, Vector2i(17, 31), save, random, data)
	if not bool(route33.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Union Cave to Route 33 failed: %s" % route33.get("reason", ""),
		}
	var route33_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "union_cave_to_route_33",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": route33.get("encounters", []),
		"run": route33_entry,
	})

	var azalea_leg: Dictionary = _walk_connection_resolving(
		world, "west", 8, 7, save, random, data
	)
	var azalea_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "route_33_to_azalea",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": azalea_leg.get("encounters", []),
		"run": azalea_entry,
	})
	if not bool(azalea_leg.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 33 to Azalea failed: %s" % azalea_leg.get("reason", ""),
		}

	# Kurt1 stands at (3,2); facing him from (3,3) takes his .RunAround branch,
	# and the script sets EVENT_AZALEA_TOWN_SLOWPOKETAIL_ROCKET, which hides the
	# Rocket standing on the well corridor at Azalea (31,9).
	var entering_kurt: Dictionary = _warp_step(world, 8, 4)
	if not bool(entering_kurt.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Kurt's house warp failed"}
	var kurt_entry: Dictionary = _drain_story(world, world.dispatch_map_entry(), save, random, data)
	var walked_to_kurt: Dictionary = _walk_cell_resolving(world, Vector2i(3, 3), save, random, data)
	if not bool(walked_to_kurt.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Kurt unreachable: %s" % walked_to_kurt.get("reason", ""),
		}
	world.player_facing = Gen2WorldSprite.FACING_UP
	var kurt_run: Dictionary = _drain_story(world, world.interact(), save, random, data, true)
	path.append({
		"step": "azalea_kurts_house",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"entry_statuses": kurt_entry.get("statuses", []),
		"run": kurt_run,
	})
	if not bool(kurt_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Kurt event did not finish"}

	var leaving_kurt: Dictionary = _warp_step(world, 8, 7)
	if not bool(leaving_kurt.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Kurt's house exit warp failed"}
	var _kurt_exit_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	var well: Dictionary = _warp_walk(world, Vector2i(31, 7), save, random, data)
	if not bool(well.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Slowpoke Well entrance blocked: %s" % well.get("reason", ""),
		}
	var well_entry: Dictionary = _drain_story(world, world.dispatch_map_entry(), save, random, data)

	# TrainerGruntM1 stands at (5,2) facing down. His post-battle script is the
	# clear sequence itself: it disappears all four Rockets, which share
	# EVENT_SLOWPOKE_WELL_ROCKETS, then heals the party and warps to Kurt's
	# house, so the map after this step is 8/4 rather than the well.
	var well_walk: Dictionary = _walk_cell_resolving(world, Vector2i(5, 3), save, random, data)
	# The clear sequence ends in `warp KURTS_HOUSE, 3, 3`, so the approach is
	# finished by the script rather than by arriving: success is being on 8/4.
	var cleared: bool = world.current_map != null \
		and world.current_map.group == 8 and world.current_map.number == 4
	path.append({
		"step": "slowpoke_well_cleared",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"entry_statuses": well_entry.get("statuses", []),
		"encounters": well_walk.get("encounters", []),
		"party_hp_after": _party_hp(save),
		"cleared": cleared,
	})
	if not cleared:
		return {
			"ok": false, "path": path,
			"reason": "Slowpoke Well clear failed: %s" % well_walk.get("reason", ""),
		}
	var after_well: Dictionary = _drain_story(world, world.dispatch_map_entry(), save, random, data)
	path.append({
		"step": "kurts_house_after_the_well",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": after_well,
	})

	var back_to_azalea: Dictionary = _warp_step(world, 8, 7)
	if not bool(back_to_azalea.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Kurt's house exit after the well failed"}
	var _azalea_after_well: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	var gym_door: Dictionary = _warp_walk(world, Vector2i(10, 15), save, random, data)
	if not bool(gym_door.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Azalea gym door blocked: %s" % gym_door.get("reason", ""),
		}
	var gym_entry: Dictionary = _drain_story(world, world.dispatch_map_entry(), save, random, data)

	# Bugsy is object 0 at (5,7); the gym's Bug Catchers and Twins hold sight
	# lines across the approach, so they are fought on the way exactly as they
	# are on the cartridge.
	var walked_to_bugsy: Dictionary = _walk_cell_resolving(
		world, Vector2i(5, 8), save, random, data
	)
	path.append({
		"step": "azalea_gym_trainers",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"entry_statuses": gym_entry.get("statuses", []),
		"encounters": walked_to_bugsy.get("encounters", []),
	})
	if not bool(walked_to_bugsy.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Bugsy approach failed: %s" % walked_to_bugsy.get("reason", ""),
		}
	world.player_facing = Gen2WorldSprite.FACING_UP
	var bugsy_run: Dictionary = _drain_story(world, world.interact(), save, random, data, true)
	path.append({
		"step": "azalea_gym_bugsy",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": bugsy_run,
		"badge_count": world.state.badge_count(),
		"engine_flags": world.state.engine_flags(),
	})
	if not bool(bugsy_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Bugsy event did not finish"}
	return {"ok": true}


## The herding chain in maps/IlexForest.asm's IlexForestFarfetchdScript. Each
## row is the Farfetch'd cell, the cell to face it from, and the facing that
## takes the fall-through branch; every other facing at that position is an
## explicit `ifequal` that sends it backwards. Position 1 accepts any facing and
## `wFarfetchdPosition` starts at zero, which reaches the same label because no
## `ifequal` matches.
const FARFETCHD_HERD: Array = [
	[Vector2i(14, 31), Vector2i(14, 32), Gen2WorldSprite.FACING_UP],
	[Vector2i(15, 25), Vector2i(15, 26), Gen2WorldSprite.FACING_UP],
	[Vector2i(20, 24), Vector2i(20, 23), Gen2WorldSprite.FACING_DOWN],
	[Vector2i(29, 22), Vector2i(28, 22), Gen2WorldSprite.FACING_RIGHT],
	[Vector2i(28, 31), Vector2i(28, 30), Gen2WorldSprite.FACING_DOWN],
	[Vector2i(24, 35), Vector2i(25, 35), Gen2WorldSprite.FACING_LEFT],
	[Vector2i(22, 31), Vector2i(22, 32), Gen2WorldSprite.FACING_UP],
	[Vector2i(15, 29), Vector2i(15, 28), Gen2WorldSprite.FACING_DOWN],
	[Vector2i(10, 35), Vector2i(11, 35), Gen2WorldSprite.FACING_LEFT],
]

## Ilex Forest's cuttable tree, the only way from the forest's southern half to
## the Route 34 exit (maps/IlexForest.blk; tools/validate_cut.gd pins the cell).
const ILEX_CUT_TREE: Vector2i = Vector2i(8, 25)
const ILEX_CUT_APPROACH: Vector2i = Vector2i(8, 26)


## Azalea Town to the Plain Badge. Cut is the gate: HM01 comes from Ilex
## Forest's charcoal master, who only appears once Farfetch'd has been herded
## the whole way round, and the tree he unlocks is the only way north.
func _plain_badge_path(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var leaving_gym: Dictionary = _warp_step(world, 8, 7)
	if not bool(leaving_gym.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Azalea Gym exit warp failed"}
	var _azalea_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	var azalea_gate: Dictionary = _warp_walk(world, Vector2i(2, 10), save, random, data)
	if not bool(azalea_gate.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Ilex Forest gate unreachable: %s" % azalea_gate.get("reason", ""),
		}
	var _gate_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	var forest: Dictionary = _warp_step(world, 3, 52)
	if not bool(forest.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Ilex Forest warp failed"}
	var forest_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "azalea_to_ilex_forest",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": forest_entry,
	})

	var herded: Array = []
	for index: int in FARFETCHD_HERD.size():
		var row: Array = FARFETCHD_HERD[index]
		var approach: Vector2i = row[1]
		var walked: Dictionary = _walk_cell_resolving(world, approach, save, random, data)
		if not bool(walked.get("ok", false)):
			path.append({"step": "ilex_forest_farfetchd", "herded": herded})
			return {
				"ok": false, "path": path,
				"reason": "Farfetch'd position %d unreachable at %s: %s" % [
					index + 1, approach, walked.get("reason", ""),
				],
			}
		world.player_facing = int(row[2])
		var run: Dictionary = _drain_story(world, world.interact(), save, random, data, true)
		herded.append({
			"position": index + 1,
			"from": _cell_value_from_vector(approach),
			"memory": world.state.script_memory_values(),
			"terminal": bool(run.get("terminal", false)),
			"reason": run.get("reason", ""),
		})
		if not bool(run.get("terminal", false)):
			path.append({"step": "ilex_forest_farfetchd", "herded": herded})
			return {
				"ok": false, "path": path,
				"reason": "Farfetch'd position %d did not finish: %s" % [
					index + 1, run.get("reason", ""),
				],
			}
	path.append({
		"step": "ilex_forest_farfetchd",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"herded": herded,
		"event_flags": world.state.event_flags().size(),
	})

	# The charcoal master is object 2 at (5,28), hidden by
	# EVENT_ILEX_FOREST_CHARCOAL_MASTER until the last herding step appears him.
	var walked_to_master: Dictionary = _walk_cell_resolving(
		world, Vector2i(5, 29), save, random, data
	)
	if not bool(walked_to_master.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "charcoal master unreachable: %s" % walked_to_master.get("reason", ""),
		}
	world.player_facing = Gen2WorldSprite.FACING_UP
	var cut_gift: Dictionary = _drain_story(world, world.interact(), save, random, data, true)
	path.append({
		"step": "ilex_forest_hm01_cut",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": cut_gift,
		"items": _named_items(data, world.state.items()),
	})
	if not bool(cut_gift.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "HM01 handoff did not finish"}

	var walked_to_tree: Dictionary = _walk_cell_resolving(
		world, ILEX_CUT_APPROACH, save, random, data
	)
	if not bool(walked_to_tree.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Ilex cut tree unreachable: %s" % walked_to_tree.get("reason", ""),
		}
	world.player_facing = Gen2WorldSprite.FACING_UP
	var cut_request: Dictionary = world.cut_request()
	var cut_applied: Dictionary = world.complete_cut() if bool(cut_request.get("ok", false)) else {}
	path.append({
		"step": "ilex_forest_cut_tree",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"request": cut_request.get("kind", cut_request.get("reason", "")),
		"applied": cut_applied.get("kind", cut_applied.get("reason", "")),
		"walkable_after": world.can_walk_to(ILEX_CUT_TREE),
	})
	if not bool(cut_applied.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "cut failed: %s" % cut_request.get(
				"reason", cut_applied.get("reason", "")
			),
		}

	var forest_exit: Dictionary = _warp_walk(world, Vector2i(1, 5), save, random, data)
	if not bool(forest_exit.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Ilex Forest north exit unreachable: %s" % forest_exit.get("reason", ""),
		}
	var north_gate_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "ilex_forest_to_route_34_gate",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": forest_exit.get("encounters", []),
		"run": north_gate_entry,
	})

	var route34: Dictionary = _warp_step(world, 11, 1)
	if not bool(route34.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Route 34 warp failed"}
	var route34_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "route_34_entry",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": route34_entry,
	})

	var goldenrod: Dictionary = _walk_connection_resolving(
		world, "north", 11, 2, save, random, data
	)
	var goldenrod_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "route_34_to_goldenrod",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": goldenrod.get("encounters", []),
		"run": goldenrod_entry,
	})
	if not bool(goldenrod.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 34 to Goldenrod failed: %s" % goldenrod.get("reason", ""),
		}

	world.set_party_summary(save.party.size(), false)
	var gym: Dictionary = _warp_walk(world, Vector2i(24, 7), save, random, data)
	if not bool(gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Goldenrod Gym door unreachable: %s" % gym.get("reason", ""),
		}
	var gym_entry: Dictionary = _drain_story(world, world.dispatch_map_entry(), save, random, data)

	# Whitney is object 0 at (8,3). Beating her sets EVENT_MADE_WHITNEY_CRY and
	# she refuses the badge; the coord event at (8,5) under
	# SCENE_GOLDENRODGYM_WHITNEY_STOPS_CRYING is what clears it, so the badge
	# needs a step back onto that cell and a second interaction.
	var walked_to_whitney: Dictionary = _walk_cell_resolving(
		world, Vector2i(8, 4), save, random, data
	)
	if not bool(walked_to_whitney.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Whitney approach failed: %s" % walked_to_whitney.get("reason", ""),
		}
	world.player_facing = Gen2WorldSprite.FACING_UP
	var whitney_fight: Dictionary = _drain_story(world, world.interact(), save, random, data, true)
	path.append({
		"step": "goldenrod_gym_whitney_battle",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"entry_statuses": gym_entry.get("statuses", []),
		"encounters": walked_to_whitney.get("encounters", []),
		"run": whitney_fight,
		"scene": world.state.map_scene(11, 3),
	})
	if not bool(whitney_fight.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Whitney battle did not finish"}

	var crying: Dictionary = _walk_cell_resolving(world, Vector2i(8, 5), save, random, data)
	path.append({
		"step": "goldenrod_gym_whitney_stops_crying",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": crying.get("encounters", []),
		"scene": world.state.map_scene(11, 3),
	})
	if not bool(crying.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Whitney crying scene failed: %s" % crying.get("reason", ""),
		}

	var walked_back: Dictionary = _walk_cell_resolving(
		world, Vector2i(8, 4), save, random, data
	)
	if not bool(walked_back.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Whitney second approach failed: %s" % walked_back.get("reason", ""),
		}
	world.player_facing = Gen2WorldSprite.FACING_UP
	var badge_run: Dictionary = _drain_story(world, world.interact(), save, random, data, true)
	path.append({
		"step": "goldenrod_gym_plain_badge",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": badge_run,
		"badge_count": world.state.badge_count(),
		"engine_flags": world.state.engine_flags(),
	})
	if not bool(badge_run.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Plain Badge event did not finish"}
	return {"ok": true}


## Places the player on this map's warp to [param group]/[param number] and
## takes it. Used where the destination warp is the step, not the walk.
func _warp_step(world: Gen2WorldAPI, group: int, number: int) -> Dictionary:
	var warp: Dictionary = _warp_to(world.current_map, group, number)
	if warp.is_empty():
		return {"ok": false, "reason": "missing warp to %d/%d" % [group, number]}
	world.player_cell = Vector2i(warp["x"], warp["y"])
	return world.try_warp()


## Walks to a warp cell, resolving whatever answers on the way, and takes it.
func _warp_walk(
	world: Gen2WorldAPI,
	cell: Vector2i,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
) -> Dictionary:
	var walked: Dictionary = _walk_cell_resolving(world, cell, save, random, data)
	if not bool(walked.get("ok", false)):
		return walked
	var transition: Dictionary = world.try_warp()
	if not bool(transition.get("ok", false)):
		return {
			"ok": false,
			"reason": "warp at %s did not fire" % cell,
			"encounters": walked.get("encounters", []),
		}
	walked["transition"] = transition
	return walked


func _party_species(save: Gen2SaveData) -> Array:
	var values: Array = []
	for mon: Gen2SaveMon in save.party:
		values.append({"species": mon.species, "level": mon.level, "egg": mon.is_egg})
	return values


func _party_has_egg(save: Gen2SaveData) -> bool:
	for mon: Gen2SaveMon in save.party:
		if mon.is_egg:
			return true
	return false


func _party_hp(save: Gen2SaveData) -> Array:
	var values: Array = []
	for mon: Gen2SaveMon in save.party:
		values.append(int(mon.hp))
	return values


## Spends hardware frames until the source two-ring sequence and any
## special-call lead have elapsed, and returns the imported phone script's
## first results. Gen2WorldPhoneRing answers nothing before that, so a caller
## that only drains script input would see the call as finished state.
func _drain_phone_ring(world: Gen2WorldAPI) -> Array:
	for _frame: int in PHONE_RING_FRAME_BUDGET:
		if not world.phone_ring_active():
			return []
		var results: Array = world.advance_phone_ring(Gen2WorldPhoneRing.FRAME_SECONDS)
		if not results.is_empty():
			return results
	return []


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
		if world.phone_ring_active():
			input_type = &"phone_ring"
		if pending_trace.size() < 24:
			pending_trace.append(String(input_type))
		if input_type == &"phone_ring":
			results = _drain_phone_ring(world)
			if results.is_empty():
				last_reason = "phone ring did not finish"
				break
		elif input_type in [&"text", &"button"]:
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
	# move_result() calls can_walk_to() with the direction, which reads the
	# leave/enter wall mask at the player's own cell; from a BFS frontier that
	# has to be anchored on the frontier cell instead, or the plan crosses walls
	# the replayed walk then refuses. Route 32's UP_WALL row at y=72 is the
	# first cell on the walked route where the two disagree.
	var face: int = Gen2WorldCollision.face_mask_for_direction(step)
	var walled: bool = face != 0 and (world.tile_permissions_at(cell) & face) != 0
	if not walled and world.can_walk_to(direct):
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
			return {
				"ok": false,
				"reason": "walk step %s from %s refused: %s" % [
					direction, _cell_value(world), moved.get("reason", ""),
				],
			}
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
