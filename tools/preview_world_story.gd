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

## How many interruptions one walk may resolve before it is called stuck. A leg
## crosses at most one map, and Route 41 carries the most trainers of any map on
## the route at ten (maps/Route41.asm).
const WALK_RESOLVE_ATTEMPTS: int = 16

## constants/item_constants.asm's add_hm list, whose comment column is hex.
const ITEM_HM_STRENGTH: int = 0xF6
## ENGINE_STORMBADGE's place in source badge order, for Gen2WorldState.badge_flag().
const BADGE_STORM: int = 5


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
	_mirror_party(world, save)

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

	var fog: Dictionary = _fog_badge_path(world, save, random, data, path)
	if not bool(fog.get("ok", false)):
		return fog

	var mineral: Dictionary = _mineral_badge_path(world, save, random, data, path)
	if not bool(mineral.get("ok", false)):
		return mineral

	var glacier: Dictionary = _glacier_badge_path(world, save, random, data, path)
	if not bool(glacier.get("ok", false)):
		return glacier

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
	_mirror_party(world, save)

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

	_mirror_party(world, save)
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


## Goldenrod to the Fog Badge. Two errands gate it: the SquirtBottle needs
## Floria found on Route 36 and then talked to in the flower shop, and Morty is
## absent until the Burned Tower's beasts are released.
func _fog_badge_path(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var leaving_gym: Dictionary = _warp_step(world, 11, 2)
	if not bool(leaving_gym.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Goldenrod Gym exit warp failed"}
	var _city_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)

	var to_route_35: Dictionary = _gate_leg(
		world, save, random, data, Vector2i(19, 1), 10, 2
	)
	if not bool(to_route_35.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Goldenrod to Route 35 failed: %s" % to_route_35.get("reason", ""),
		}
	var first_cut: Dictionary = _cut_at(
		world, Vector2i(17, 7), Gen2WorldSprite.FACING_UP, save, random, data
	)
	if not bool(first_cut.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 35 cut tree failed: %s" % first_cut.get("reason", ""),
		}
	var route36_leg: Dictionary = _walk_connection_resolving(
		world, "north", 10, 3, save, random, data
	)
	var route36_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "goldenrod_to_route_36",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": route36_leg.get("encounters", []),
		"run": route36_entry,
	})
	if not bool(route36_leg.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 35 to Route 36 failed: %s" % route36_leg.get("reason", ""),
		}

	# Floria stands at (33,12) once entering Goldenrod cleared
	# EVENT_FLORIA_AT_SUDOWOODO; talking to her sets EVENT_MET_FLORIA and moves
	# her to the flower shop.
	var floria: Dictionary = _talk_to(
		world, Vector2i(33, 13), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "route_36_floria",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": floria.get("run", {}),
	})
	if not bool(floria.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 36 Floria failed: %s" % floria.get("reason", ""),
		}

	var back_to_35: Dictionary = _walk_connection_resolving(
		world, "south", 10, 2, save, random, data
	)
	var _r35_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	if not bool(back_to_35.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 36 back to Route 35 failed: %s" % back_to_35.get("reason", ""),
		}
	var south_cut: Dictionary = _cut_at(
		world, Vector2i(17, 5), Gen2WorldSprite.FACING_DOWN, save, random, data
	)
	if not bool(south_cut.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 35 southbound cut failed: %s" % south_cut.get("reason", ""),
		}
	var back_to_city: Dictionary = _gate_leg(
		world, save, random, data, Vector2i(9, 33), 11, 2
	)
	if not bool(back_to_city.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 35 back to Goldenrod failed: %s" % back_to_city.get("reason", ""),
		}

	var shop: Dictionary = _warp_walk(world, Vector2i(29, 5), save, random, data)
	if not bool(shop.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "flower shop unreachable: %s" % shop.get("reason", ""),
		}
	var _shop_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	var shop_floria: Dictionary = _talk_to(
		world, Vector2i(5, 5), Gen2WorldSprite.FACING_DOWN, save, random, data
	)
	if not bool(shop_floria.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "flower shop Floria failed: %s" % shop_floria.get("reason", ""),
		}
	var bottle: Dictionary = _talk_to(
		world, Vector2i(2, 5), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "goldenrod_flower_shop_squirtbottle",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"floria_run": shop_floria.get("run", {}),
		"run": bottle.get("run", {}),
		"items": _named_items(data, world.state.items()),
	})
	if not bool(bottle.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "SquirtBottle handoff failed: %s" % bottle.get("reason", ""),
		}

	var leaving_shop: Dictionary = _warp_step(world, 11, 2)
	if not bool(leaving_shop.get("ok", false)):
		return {"ok": false, "path": path, "reason": "flower shop exit warp failed"}
	var _city_again: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	var to_35_again: Dictionary = _gate_leg(
		world, save, random, data, Vector2i(19, 1), 10, 2
	)
	if not bool(to_35_again.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Goldenrod to Route 35 again failed: %s" % to_35_again.get("reason", ""),
		}
	var second_cut: Dictionary = _cut_at(
		world, Vector2i(17, 7), Gen2WorldSprite.FACING_UP, save, random, data
	)
	if not bool(second_cut.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 35 cut tree again failed: %s" % second_cut.get("reason", ""),
		}
	var route36_again: Dictionary = _walk_connection_resolving(
		world, "north", 10, 3, save, random, data
	)
	var _r36_again: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	if not bool(route36_again.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 35 to Route 36 again failed: %s" % route36_again.get("reason", ""),
		}

	# SudowoodoScript answers checkitem SQUIRTBOTTLE from a facing interaction,
	# not from the pack, and the wild battle it starts is what clears the tree
	# blocking Route 37.
	var sudowoodo: Dictionary = _talk_to(
		world, Vector2i(35, 10), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "route_36_sudowoodo",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": sudowoodo.get("run", {}),
	})
	if not bool(sudowoodo.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Sudowoodo failed: %s" % sudowoodo.get("reason", ""),
		}

	for leg: Dictionary in [
		{"step": "route_36_to_route_37", "group": 10, "number": 4},
		{"step": "route_37_to_ecruteak", "group": 4, "number": 9},
	]:
		var walked: Dictionary = _walk_connection_resolving(
			world, "north", int(leg["group"]), int(leg["number"]), save, random, data
		)
		var entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
		path.append({
			"step": String(leg["step"]),
			"map": _map_value(world),
			"cell": _cell_value(world),
			"encounters": walked.get("encounters", []),
			"run": entry,
		})
		if not bool(walked.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "%s failed: %s" % [leg["step"], walked.get("reason", "")],
			}

	# The gym is closed until the Burned Tower beasts are released: its scene 0
	# is SCENE_ECRUTEAKGYM_FORCED_TO_LEAVE and a gramps stands on the entrance.
	var tower: Dictionary = _warp_walk(world, Vector2i(5, 5), save, random, data)
	if not bool(tower.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Burned Tower door unreachable: %s" % tower.get("reason", ""),
		}
	var eusine: Dictionary = _drain_story(world, world.dispatch_map_entry(), save, random, data)
	path.append({
		"step": "burned_tower_meet_eusine",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": eusine,
	})
	if not bool(eusine.get("terminal", false)):
		return {"ok": false, "path": path, "reason": "Burned Tower entry did not finish"}

	# The rival scene ends by opening the hole under the player and taking it
	# with warpcheck, so the map after this step is the basement.
	var rival: Dictionary = _walk_cell_resolving(world, Vector2i(11, 9), save, random, data)
	var fell: bool = world.current_map != null \
		and world.current_map.group == 3 and world.current_map.number == 14
	path.append({
		"step": "burned_tower_rival_battle",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": rival.get("encounters", []),
		"fell_through_the_hole": fell,
	})
	if not fell:
		return {
			"ok": false, "path": path,
			"reason": "Burned Tower rival scene did not drop the player: %s" % rival.get(
				"reason", ""
			),
		}
	var basement_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)

	var beasts: Dictionary = _walk_cell_resolving(world, Vector2i(10, 6), save, random, data)
	path.append({
		"step": "burned_tower_release_the_beasts",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"entry_statuses": basement_entry.get("statuses", []),
		"encounters": beasts.get("encounters", []),
		"roaming": world.state.roaming_mons(),
		"gym_scene": world.state.map_scene(4, 7),
	})
	if not bool(beasts.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "beast release failed: %s" % beasts.get("reason", ""),
		}

	# ReleaseTheBeasts appears Eusine at (10,12), which is the single cell of
	# the corridor south, so the way out is through him: his script has him
	# leave once the player has talked to him.
	var eusine_basement: Dictionary = _talk_to(
		world, Vector2i(10, 11), Gen2WorldSprite.FACING_DOWN, save, random, data
	)
	path.append({
		"step": "burned_tower_eusine_leaves",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": eusine_basement.get("run", {}),
	})
	if not bool(eusine_basement.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "basement Eusine failed: %s" % eusine_basement.get("reason", ""),
		}

	# ReleaseTheBeasts changeblocks the ladder in at walk-cell (6,14), which is
	# the block holding (7,15); the hole the player fell through is not a way
	# back up.
	var out_of_basement: Dictionary = _warp_walk(world, Vector2i(7, 15), save, random, data)
	if not bool(out_of_basement.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Burned Tower ladder unreachable: %s" % out_of_basement.get("reason", ""),
		}
	var _tower_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	var out_of_tower: Dictionary = _warp_walk(world, Vector2i(9, 15), save, random, data)
	if not bool(out_of_tower.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Burned Tower exit unreachable: %s" % out_of_tower.get("reason", ""),
		}
	var _ecruteak_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)

	_mirror_party(world, save)
	var gym: Dictionary = _warp_walk(world, Vector2i(6, 27), save, random, data)
	if not bool(gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Ecruteak Gym door unreachable: %s" % gym.get("reason", ""),
		}
	var gym_entry: Dictionary = _drain_story(world, world.dispatch_map_entry(), save, random, data)

	# The gym floor is thirty holes that warp back to the entrance, so the walk
	# to Morty at (5,1) is the maze itself; the BFS refuses a warp cell that is
	# not its target, which is what keeps it on the invisible floor.
	var morty: Dictionary = _talk_to(
		world, Vector2i(5, 2), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "ecruteak_gym_morty",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"entry_statuses": gym_entry.get("statuses", []),
		"run": morty.get("run", {}),
		"badge_count": world.state.badge_count(),
		"engine_flags": world.state.engine_flags(),
	})
	if not bool(morty.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Morty failed: %s" % morty.get("reason", ""),
		}
	return {"ok": true}


## The Fog Badge to the Mineral Badge, taking the Storm Badge on the way, on the
## same world, state and save. This is the first leg that needs Surf on the real
## route: HM03 is the Dance Theater's reward for the five Kimono Girls, and
## Routes 40 and 41 are the only way to Cianwood, whose pharmacy holds the
## SecretPotion that maps/OlivineLighthouse6F.asm wants before it clears
## EVENT_OLIVINE_GYM_JASMINE.
##
## Chuck is on this leg rather than one of its own because the crossing is: the
## Mineral Badge sends the player to Cianwood for the SecretPotion anyway, and
## maps/CianwoodGym.asm is two doors from the pharmacy. Doing it here costs no
## extra Route 40/41 crossing, which is also the order a player walks. HM04 is
## collected before the outbound crossing, from maps/OlivineCafe.asm.
func _mineral_badge_path(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var leaving_gym: Dictionary = _warp_step(world, 4, 9)
	if not bool(leaving_gym.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Ecruteak Gym exit warp failed"}
	var _city_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)

	var theater: Dictionary = _warp_walk(world, Vector2i(23, 21), save, random, data)
	if not bool(theater.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Dance Theater door unreachable: %s" % theater.get("reason", ""),
		}
	var _theater_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)

	# The five Kimono Girls stand on the stage above a row of COLL_HOP_DOWN, so
	# the only ways up are the floor cells at (1,4) and (10,4). Their sight range
	# is 0, so none of them can start a battle: every one has to be talked to.
	var kimono_battles: Array = []
	for girl: Dictionary in [
		{"name": "naoko", "cell": Vector2i(1, 2), "facing": Gen2WorldSprite.FACING_LEFT},
		{"name": "sayo", "cell": Vector2i(2, 2), "facing": Gen2WorldSprite.FACING_UP},
		{"name": "zuki", "cell": Vector2i(5, 2), "facing": Gen2WorldSprite.FACING_RIGHT},
		{"name": "kuni", "cell": Vector2i(9, 2), "facing": Gen2WorldSprite.FACING_UP},
		{"name": "miki", "cell": Vector2i(10, 2), "facing": Gen2WorldSprite.FACING_RIGHT},
	]:
		var fought: Dictionary = _talk_to(
			world, girl["cell"], int(girl["facing"]), save, random, data
		)
		kimono_battles.append({
			"girl": String(girl["name"]),
			"battles": fought.get("run", {}).get("battles", []),
		})
		if not bool(fought.get("ok", false)):
			path.append({"step": "dance_theater_kimono_girls", "run": kimono_battles})
			return {
				"ok": false, "path": path,
				"reason": "Kimono Girl %s failed: %s" % [girl["name"], fought.get("reason", "")],
			}

	# DanceTheaterSurfGuy checks all five beaten flags before .GetSurf, so this
	# interaction is what the five battles were for.
	var surf_guy: Dictionary = _talk_to(
		world, Vector2i(7, 11), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "dance_theater_hm03_surf",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"kimono_girls": kimono_battles,
		"run": surf_guy.get("run", {}),
		"items": _named_items(data, world.state.items()),
	})
	if not bool(surf_guy.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "HM03 handoff failed: %s" % surf_guy.get("reason", ""),
		}

	var leaving_theater: Dictionary = _warp_step(world, 4, 9)
	if not bool(leaving_theater.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Dance Theater exit warp failed"}
	var _city_again: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)

	var to_route_38: Dictionary = _gate_leg(
		world, save, random, data, Vector2i(0, 18), 1, 12
	)
	if not bool(to_route_38.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Ecruteak to Route 38 failed: %s" % to_route_38.get("reason", ""),
		}
	for leg: Dictionary in [
		{"step": "route_38_to_route_39", "direction": "west", "group": 1, "number": 13},
		{"step": "route_39_to_olivine", "direction": "south", "group": 1, "number": 14},
	]:
		var walked: Dictionary = _walk_connection_resolving(
			world, String(leg["direction"]), int(leg["group"]), int(leg["number"]),
			save, random, data
		)
		var entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
		path.append({
			"step": String(leg["step"]),
			"map": _map_value(world),
			"cell": _cell_value(world),
			"encounters": walked.get("encounters", []),
			"run": entry,
		})
		if not bool(walked.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "%s failed: %s" % [leg["step"], walked.get("reason", "")],
			}

	# OlivineCity's first scene is SCENE_OLIVINECITY_RIVAL_ENCOUNTER, and its
	# coord event is the only thing that retires it. The scene ends on
	# variablesprite plus LoadUsedSpritesGFX, so it also exercises the pair.
	var rival: Dictionary = _walk_cell_resolving(world, Vector2i(13, 12), save, random, data)
	path.append({
		"step": "olivine_city_rival",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": rival.get("encounters", []),
		"map_scene": world.state.map_scene(1, 14),
	})
	if not bool(rival.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Olivine rival scene failed: %s" % rival.get("reason", ""),
		}

	var cafe: Dictionary = _olivine_cafe_hm04(world, save, random, data, path)
	if not bool(cafe.get("ok", false)):
		return cafe

	var first_visit: Dictionary = _lighthouse_visit(world, save, random, data, path, "first")
	if not bool(first_visit.get("ok", false)):
		return first_visit

	var to_cianwood: Dictionary = _cianwood_crossing(world, save, random, data, path, false)
	if not bool(to_cianwood.get("ok", false)):
		return to_cianwood

	var pharmacy: Dictionary = _warp_walk(world, Vector2i(15, 47), save, random, data)
	if not bool(pharmacy.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Cianwood Pharmacy door unreachable: %s" % pharmacy.get("reason", ""),
		}
	var _pharmacy_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	# CianwoodPharmacist hands the SecretPotion over only while
	# EVENT_JASMINE_EXPLAINED_AMPHYS_SICKNESS is set; without it the same
	# interaction opens MART_CIANWOOD instead.
	var potion: Dictionary = _talk_to(
		world, Vector2i(2, 4), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "cianwood_pharmacy_secretpotion",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": potion.get("run", {}),
		"items": _named_items(data, world.state.items()),
	})
	if not bool(potion.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "SecretPotion handoff failed: %s" % potion.get("reason", ""),
		}
	var leaving_pharmacy: Dictionary = _warp_step(world, 22, 3)
	if not bool(leaving_pharmacy.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Cianwood Pharmacy exit warp failed"}
	var _cianwood_again: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)

	var storm: Dictionary = _storm_badge_leg(world, save, random, data, path)
	if not bool(storm.get("ok", false)):
		return storm

	var back_to_olivine: Dictionary = _cianwood_crossing(world, save, random, data, path, true)
	if not bool(back_to_olivine.get("ok", false)):
		return back_to_olivine

	var second_visit: Dictionary = _lighthouse_visit(world, save, random, data, path, "cure")
	if not bool(second_visit.get("ok", false)):
		return second_visit

	_mirror_party(world, save)
	var gym: Dictionary = _warp_walk(world, Vector2i(10, 11), save, random, data)
	if not bool(gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Olivine Gym door unreachable: %s" % gym.get("reason", ""),
		}
	var gym_entry: Dictionary = _drain_story(world, world.dispatch_map_entry(), save, random, data)
	var jasmine: Dictionary = _talk_to(
		world, Vector2i(5, 4), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "olivine_gym_jasmine",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"entry_statuses": gym_entry.get("statuses", []),
		"run": jasmine.get("run", {}),
		"badge_count": world.state.badge_count(),
		"engine_flags": world.state.engine_flags(),
		"items": _named_items(data, world.state.items()),
	})
	if not bool(jasmine.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Jasmine failed: %s" % jasmine.get("reason", ""),
		}
	return {"ok": true}


## The Mineral Badge to the Glacier Badge. Mahogany's gym is closed until the
## Rocket hideout under its souvenir shop is cleared
## (`EVENT_MAHOGANY_TOWN_POKEFAN_M_BLOCKS_GYM`, `maps/MahoganyTown.asm`), and the
## hideout only opens after Lance is met at the Lake of Rage, which is behind the
## Red Gyarados in the middle of the water.
##
## The hideout is three floors of one-way halves rather than one maze: each floor
## is cut in two and the halves are joined through the other floor, so the route
## climbs and drops the same ladders several times. Its own doors are the only
## other links, and each opens on something learned a floor away.
func _glacier_badge_path(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var leaving_gym: Dictionary = _warp_step(world, 1, 14)
	if not bool(leaving_gym.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Olivine Gym exit warp failed"}
	var _city_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	for leg: Dictionary in [
		{"step": "olivine_to_route_39", "direction": "north", "group": 1, "number": 13},
		{"step": "route_39_to_route_38", "direction": "east", "group": 1, "number": 12},
	]:
		var walked: Dictionary = _walk_connection_resolving(
			world, String(leg["direction"]), int(leg["group"]), int(leg["number"]),
			save, random, data
		)
		var entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
		path.append({
			"step": String(leg["step"]),
			"map": _map_value(world),
			"cell": _cell_value(world),
			"encounters": walked.get("encounters", []),
			"run": entry,
		})
		if not bool(walked.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "%s failed: %s" % [leg["step"], walked.get("reason", "")],
			}
	var to_ecruteak: Dictionary = _gate_leg(
		world, save, random, data, Vector2i(35, 8), 4, 9
	)
	if not bool(to_ecruteak.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 38 back to Ecruteak failed: %s" % to_ecruteak.get("reason", ""),
		}

	var to_route_42: Dictionary = _gate_leg(
		world, save, random, data, Vector2i(35, 26), 2, 5
	)
	if not bool(to_route_42.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Ecruteak to Route 42 failed: %s" % to_route_42.get("reason", ""),
		}
	# Route 42's halves do not join on foot. Its west side ends at x=13 and its
	# only other land exit is Mt Mortar's door at (10,5), which opens into a cave
	# pocket of its own, so the lake is the crossing. (13,9) is the west shore and
	# the water runs east and down to the far shore at (22,12).
	var across_route_42: Dictionary = _surf_at(
		world, Vector2i(13, 9), Gen2WorldSprite.FACING_RIGHT, save, random, data
	)
	if not bool(across_route_42.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 42 surf entry failed: %s" % across_route_42.get("reason", ""),
		}
	var route_42_shore: Dictionary = _walk_cell_resolving(
		world, Vector2i(22, 12), save, random, data, true
	)
	if not bool(route_42_shore.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 42 landfall failed: %s" % route_42_shore.get("reason", ""),
		}
	# The middle strip is its own pocket: a second lake separates it from the
	# half that reaches Mahogany, so the route takes the water twice.
	var second_crossing: Dictionary = _surf_at(
		world, Vector2i(33, 10), Gen2WorldSprite.FACING_RIGHT, save, random, data
	)
	if not bool(second_crossing.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 42 second surf failed: %s" % second_crossing.get("reason", ""),
		}
	var route_42_far_shore: Dictionary = _walk_cell_resolving(
		world, Vector2i(42, 9), save, random, data, true
	)
	path.append({
		"step": "route_42_lake_crossing",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"movement_mode": String(world.movement_mode),
	})
	if not bool(route_42_far_shore.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 42 far landfall failed: %s" % route_42_far_shore.get("reason", ""),
		}
	var to_mahogany: Dictionary = _walk_connection_resolving(
		world, "east", 2, 7, save, random, data
	)
	var mahogany_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "route_42_to_mahogany",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": to_mahogany.get("encounters", []),
		"run": mahogany_entry,
	})
	if not bool(to_mahogany.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 42 to Mahogany failed: %s" % to_mahogany.get("reason", ""),
		}

	var to_route_43: Dictionary = _gate_leg(
		world, save, random, data, Vector2i(9, 1), 9, 5
	)
	if not bool(to_route_43.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Mahogany to Route 43 failed: %s" % to_route_43.get("reason", ""),
		}
	var to_lake: Dictionary = _walk_connection_resolving(
		world, "north", 9, 6, save, random, data
	)
	var lake_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	path.append({
		"step": "route_43_to_lake_of_rage",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": to_lake.get("encounters", []),
		"run": lake_entry,
	})
	if not bool(to_lake.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 43 to the Lake of Rage failed: %s" % to_lake.get("reason", ""),
		}

	# The shore cell north of the gramps: (20,26) is his own cell and (24,26) is
	# Fisher Raymond's, so the walked route takes the water at (22,26).
	var into_the_lake: Dictionary = _surf_at(
		world, Vector2i(22, 26), Gen2WorldSprite.FACING_UP, save, random, data
	)
	if not bool(into_the_lake.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Lake of Rage surf entry failed: %s" % into_the_lake.get("reason", ""),
		}
	# RedGyarados is loadwildmon plus BATTLETYPE_FORCESHINY, not a trainer, and
	# the Red Scale it leaves behind is what Lance appears for.
	var gyarados: Dictionary = _talk_to_on_water(
		world, Vector2i(18, 23), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "lake_of_rage_red_gyarados",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": gyarados.get("run", {}),
		"items": _named_items(data, world.state.items()),
	})
	if not bool(gyarados.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Red Gyarados failed: %s" % gyarados.get("reason", ""),
		}
	var ashore: Dictionary = _walk_cell_resolving(
		world, Vector2i(22, 26), save, random, data, true
	)
	if not bool(ashore.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Lake of Rage landfall failed: %s" % ashore.get("reason", ""),
		}
	var lance: Dictionary = _talk_to(
		world, Vector2i(21, 29), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "lake_of_rage_lance",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": lance.get("run", {}),
		"mart_scene": world.state.map_scene(3, 48),
	})
	if not bool(lance.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Lake of Rage Lance failed: %s" % lance.get("reason", ""),
		}

	var back_to_route_43: Dictionary = _walk_connection_resolving(
		world, "south", 9, 5, save, random, data
	)
	var _r43_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	if not bool(back_to_route_43.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Lake of Rage back to Route 43 failed: %s" % back_to_route_43.get(
				"reason", ""
			),
		}
	var back_to_mahogany: Dictionary = _gate_leg(
		world, save, random, data, Vector2i(9, 51), 2, 7
	)
	if not bool(back_to_mahogany.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Route 43 back to Mahogany failed: %s" % back_to_mahogany.get("reason", ""),
		}

	# MahoganyMart1F's scene 1 is Lance's Dragonite clearing the shop and the
	# changeblock that uncovers the staircase, deferred by the scene script.
	var mart: Dictionary = _warp_walk(world, Vector2i(11, 7), save, random, data)
	if not bool(mart.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Mahogany Mart door unreachable: %s" % mart.get("reason", ""),
		}
	var stairs: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data, true
	)
	path.append({
		"step": "mahogany_mart_lance_uncovers_the_stairs",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": stairs,
	})
	if not bool(stairs.get("terminal", false)):
		return {
			"ok": false, "path": path,
			"reason": "Mahogany Mart staircase scene did not finish: %s" % stairs.get(
				"reason", ""
			),
		}

	var into_the_base: Dictionary = _warp_walk(world, Vector2i(7, 3), save, random, data)
	if not bool(into_the_base.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Rocket base staircase unreachable: %s" % into_the_base.get("reason", ""),
		}
	var _b1f_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	# The secret switch behind the bookshelves sets all five camera events at
	# once, which is what stops the coord events on the way to the B2F ladder
	# from calling two grunts each.
	var switch: Dictionary = _talk_to(
		world, Vector2i(19, 12), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "rocket_base_b1f_secret_switch",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": switch.get("run", {}),
	})
	if not bool(switch.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "B1F secret switch failed: %s" % switch.get("reason", ""),
		}
	var to_b2f: Dictionary = _warp_walk(world, Vector2i(3, 14), save, random, data)
	if not bool(to_b2f.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "B2F ladder unreachable: %s" % to_b2f.get("reason", ""),
		}
	var _b2f_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	var heal: Dictionary = _walk_cell_resolving(world, Vector2i(5, 14), save, random, data)
	path.append({
		"step": "rocket_base_b2f_lance_heals",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": heal.get("encounters", []),
		"scene": world.state.map_scene(3, 50),
	})
	if not bool(heal.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "B2F Lance heal failed: %s" % heal.get("reason", ""),
		}

	# The B2F ladder the heal room reaches is the far one: row 12 is a solid wall
	# and the only way north out of the bottom section is the right-hand column.
	var to_b3f: Dictionary = _warp_walk(world, Vector2i(27, 14), save, random, data)
	if not bool(to_b3f.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "B3F ladder unreachable: %s" % to_b3f.get("reason", ""),
		}
	# B3F's first scene defers LanceGetPasswordScript, which ends by arming the
	# rival scene; the rival scene arms the executive.
	var password_scene: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data, true
	)
	path.append({
		"step": "rocket_base_b3f_lance_asks_for_the_password",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": password_scene,
		"scene": world.state.map_scene(3, 51),
	})
	if not bool(password_scene.get("terminal", false)):
		return {
			"ok": false, "path": path,
			"reason": "B3F Lance scene did not finish: %s" % password_scene.get("reason", ""),
		}
	# Both password grunts stand on the half of B3F the heal-room ladder reaches,
	# and their after-battle scripts are what set EVENT_LEARNED_SLOWPOKETAIL and
	# EVENT_LEARNED_RATICATE_TAIL, which the door to Giovanni's office checks.
	for grunt: Dictionary in [
		{"name": "slowpoketail", "cell": Vector2i(21, 8), "facing": Gen2WorldSprite.FACING_UP},
		{"name": "raticate_tail", "cell": Vector2i(5, 15), "facing": Gen2WorldSprite.FACING_UP},
	]:
		var fought: Dictionary = _talk_to(
			world, grunt["cell"], int(grunt["facing"]), save, random, data
		)
		if not bool(fought.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "B3F %s grunt failed: %s" % [grunt["name"], fought.get("reason", "")],
			}
		# The password is in the after-battle script, and that script opens with
		# endifjustbattled, so the turn that beat the grunt ends before reaching
		# the setevent. The source needs the second conversation, which is what
		# actually says the password.
		var password: Dictionary = _talk_to(
			world, grunt["cell"], int(grunt["facing"]), save, random, data
		)
		path.append({
			"step": "rocket_base_b3f_%s_grunt" % grunt["name"],
			"map": _map_value(world),
			"cell": _cell_value(world),
			"battle": fought.get("run", {}).get("battles", []),
			"run": password.get("run", {}),
		})
		if not bool(password.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "B3F %s password failed: %s" % [
					grunt["name"], password.get("reason", ""),
				],
			}

	# B3F's northern half is walled off from this one, and it is entered from
	# B2F's own northern half, so the route goes up one ladder and down another.
	var b3f_up: Dictionary = _warp_walk(world, Vector2i(27, 2), save, random, data)
	if not bool(b3f_up.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "B3F north-east ladder unreachable: %s" % b3f_up.get("reason", ""),
		}
	var _b2f_north: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	var b3f_down: Dictionary = _warp_walk(world, Vector2i(3, 2), save, random, data)
	if not bool(b3f_down.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "B2F north-west ladder unreachable: %s" % b3f_down.get("reason", ""),
		}
	var _b3f_north: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	var rival: Dictionary = _walk_cell_resolving(world, Vector2i(8, 10), save, random, data)
	path.append({
		"step": "rocket_base_b3f_rival",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": rival.get("encounters", []),
		"scene": world.state.map_scene(3, 51),
	})
	if not bool(rival.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "B3F rival scene failed: %s" % rival.get("reason", ""),
		}
	# Giovanni's door is the only way into the office: row 9 is solid either side
	# of it. It opens on the two passwords and changeblocks itself to floor.
	var office_door: Dictionary = _talk_to(
		world, Vector2i(10, 10), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "rocket_base_b3f_giovannis_door",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": office_door.get("run", {}),
	})
	if not bool(office_door.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "B3F office door failed: %s" % office_door.get("reason", ""),
		}
	var executive: Dictionary = _walk_cell_resolving(world, Vector2i(10, 8), save, random, data)
	path.append({
		"step": "rocket_base_b3f_executive",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": executive.get("encounters", []),
		"scene": world.state.map_scene(3, 51),
	})
	if not bool(executive.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "B3F executive failed: %s" % executive.get("reason", ""),
		}
	# The Murkrow behind the desk is what says the transmitter password.
	var murkrow: Dictionary = _talk_to(
		world, Vector2i(7, 3), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "rocket_base_b3f_murkrow",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": murkrow.get("run", {}),
	})
	if not bool(murkrow.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "B3F Murkrow failed: %s" % murkrow.get("reason", ""),
		}

	# Back down to the machine room's own floor, which means unwinding the same
	# three ladders: B2F's north-west pocket does not reach its south half either.
	for ladder: Dictionary in [
		{"step": "b3f_north_to_b2f_north", "cell": Vector2i(3, 2)},
		{"step": "b2f_north_to_b3f_south", "cell": Vector2i(27, 2)},
		{"step": "b3f_south_to_b2f_south", "cell": Vector2i(27, 14)},
	]:
		var taken: Dictionary = _warp_walk(world, ladder["cell"], save, random, data)
		if not bool(taken.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "%s ladder unreachable: %s" % [
					ladder["step"], taken.get("reason", ""),
				],
			}
		var _floor_entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
	# The machine room is walled off on every side but its own door: B2F's row 12
	# is solid and rows 3 to 11 between x=7 and x=22 touch nothing else. So the
	# transmitter door is the way in, and it opens on the password the Murkrow
	# gave.
	var transmitter_door: Dictionary = _talk_to(
		world, Vector2i(14, 13), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "rocket_base_b2f_transmitter_door",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": transmitter_door.get("run", {}),
	})
	if not bool(transmitter_door.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "B2F transmitter door failed: %s" % transmitter_door.get("reason", ""),
		}
	# Stepping onto the cell north of that door is the executive's coord event,
	# and it ends by arming the electrodes.
	# The scene walks the player itself and then confines them with the
	# electrodes, so the walk is expected not to reach its own target: what says
	# the executive happened is the scene moving on.
	var boss_f: Dictionary = _walk_cell_resolving(world, Vector2i(14, 11), save, random, data)
	var electrodes_armed: bool = world.state.map_scene(3, 50) == 2
	path.append({
		"step": "rocket_base_b2f_executive",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"encounters": boss_f.get("encounters", []),
		"scene": world.state.map_scene(3, 50),
	})
	if not electrodes_armed:
		return {
			"ok": false, "path": path,
			"reason": "B2F executive failed: %s" % boss_f.get("reason", ""),
		}
	# Three Electrodes power the transmitter. Each is a loadwildmon battle, and
	# the third one to fall runs the script that ends the hideout.
	for electrode: Dictionary in [
		{"name": "1", "cell": Vector2i(8, 5)},
		{"name": "2", "cell": Vector2i(8, 7)},
		{"name": "3", "cell": Vector2i(8, 9)},
	]:
		var zapped: Dictionary = _talk_to(
			world, electrode["cell"], Gen2WorldSprite.FACING_LEFT, save, random, data
		)
		path.append({
			"step": "rocket_base_b2f_electrode_%s" % electrode["name"],
			"map": _map_value(world),
			"cell": _cell_value(world),
			"run": zapped.get("run", {}),
			"items": _named_items(data, world.state.items()),
		})
		if not bool(zapped.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "B2F electrode %s failed: %s" % [
					electrode["name"], zapped.get("reason", ""),
				],
			}

	# Out the way the route came in. Clearing the base hides the grunts, so the
	# walk back is not the one that came down.
	for ladder: Dictionary in [
		{"step": "b2f_to_b1f", "group": 3, "number": 49, "cell": Vector2i(3, 14)},
		{"step": "b1f_to_the_shop", "group": 3, "number": 48, "cell": Vector2i(27, 2)},
		{"step": "shop_to_mahogany", "group": 2, "number": 7, "cell": Vector2i(3, 7)},
	]:
		var climbed: Dictionary = _warp_walk(world, ladder["cell"], save, random, data)
		if not bool(climbed.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "%s unreachable: %s" % [ladder["step"], climbed.get("reason", "")],
			}
		var _above: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)

	_mirror_party(world, save)
	var gym: Dictionary = _warp_walk(world, Vector2i(6, 13), save, random, data)
	if not bool(gym.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Mahogany Gym door unreachable: %s" % gym.get("reason", ""),
		}
	var gym_entry: Dictionary = _drain_story(world, world.dispatch_map_entry(), save, random, data)
	# Pryce's floor is COLL_ICE, which is LAND_TILE, so the walk crosses it
	# without the source's sliding.
	var pryce: Dictionary = _talk_to(
		world, Vector2i(5, 4), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "mahogany_gym_pryce",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"entry_statuses": gym_entry.get("statuses", []),
		"run": pryce.get("run", {}),
		"badge_count": world.state.badge_count(),
		"engine_flags": world.state.engine_flags(),
		"items": _named_items(data, world.state.items()),
	})
	if not bool(pryce.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Pryce failed: %s" % pryce.get("reason", ""),
		}
	return {"ok": true}


## _talk_to() for a target the player has to reach across water. The frontier
## stays on water so the plan cannot step ashore partway and stop surfing.
func _talk_to_on_water(
	world: Gen2WorldAPI,
	cell: Vector2i,
	facing: int,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
) -> Dictionary:
	var walked: Dictionary = _walk_cell_resolving(world, cell, save, random, data, true)
	if not bool(walked.get("ok", false)):
		return walked
	world.player_facing = facing
	var run: Dictionary = _drain_story(world, world.interact(), save, random, data, true)
	return {
		"ok": bool(run.get("terminal", false)),
		"reason": run.get("reason", ""),
		"run": run,
	}


## The lighthouse floors reached by ladder on the way up and by hole on the way
## down, from Olivine City's door back to it. [param phase] is "first" for
## Jasmine's SecretPotion errand and "cure" for the visit that carries it.
##
## The climb is not the obvious one: 4F's ladder at (3,5) reaches the half of 5F
## that cannot see the 6F stairs at (9,15), so the route drops back to 3F
## through the hole at 4F (9,3) and climbs the other shaft.
func _lighthouse_visit(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
	phase: String,
) -> Dictionary:
	var door: Dictionary = _warp_walk(world, Vector2i(29, 27), save, random, data)
	if not bool(door.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Olivine Lighthouse door unreachable: %s" % door.get("reason", ""),
		}
	var _entry: Dictionary = _drain_story(world, world.dispatch_map_entry(), save, random, data)

	var climb: Dictionary = _lighthouse_shaft(world, save, random, data, [
		Vector2i(3, 11), Vector2i(5, 3), Vector2i(13, 3), Vector2i(9, 3),
		Vector2i(9, 5), Vector2i(9, 7), Vector2i(9, 15),
	])
	if not bool(climb.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "lighthouse climb (%s) failed: %s" % [phase, climb.get("reason", "")],
		}

	# OlivineLighthouseJasmine answers checkitem SECRETPOTION first, so the same
	# interaction explains Amphy's sickness on the first visit and cures it on
	# the second. The cure runs FadeOutToWhite and FadeInFromWhite either side of
	# the Ampharos cry.
	var jasmine: Dictionary = _talk_to(
		world, Vector2i(8, 9), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "olivine_lighthouse_jasmine_%s" % phase,
		"map": _map_value(world),
		"cell": _cell_value(world),
		"floors": climb.get("floors", []),
		"run": jasmine.get("run", {}),
		"items": _named_items(data, world.state.items()),
	})
	if not bool(jasmine.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "lighthouse Jasmine (%s) failed: %s" % [phase, jasmine.get("reason", "")],
		}

	var descent: Dictionary = _lighthouse_shaft(world, save, random, data, [
		Vector2i(16, 5), Vector2i(16, 7), Vector2i(16, 9), Vector2i(16, 11),
		Vector2i(16, 13), Vector2i(10, 17),
	])
	if not bool(descent.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "lighthouse descent (%s) failed: %s" % [phase, descent.get("reason", "")],
		}
	return {"ok": true}


## Walks each cell in [param cells] on the floor it belongs to and takes the
## warp there, draining the arrival callbacks between floors.
func _lighthouse_shaft(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	cells: Array,
) -> Dictionary:
	var floors: Array = []
	for cell: Vector2i in cells:
		var taken: Dictionary = _warp_walk(world, cell, save, random, data)
		if not bool(taken.get("ok", false)):
			return {
				"ok": false, "floors": floors,
				"reason": "warp at %s unreachable: %s" % [cell, taken.get("reason", "")],
			}
		var _entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
		floors.append(_map_value(world))
	return {"ok": true, "floors": floors}


## maps/OlivineCafe.asm's sailor at (4,3), who hands over HM04 behind
## EVENT_GOT_HM04_STRENGTH. The cafe is Olivine City warp 7 at (7,21).
##
## The move is then written straight into a party member's slots, because
## AskTeachTMHM and TeachTMHM are not implemented: nothing else can turn the HM
## in the bag into a move the party knows, and the boulder script's
## CheckPartyMove reads exactly that. See _teach_move().
func _olivine_cafe_hm04(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var door: Dictionary = _warp_walk(world, Vector2i(7, 21), save, random, data)
	if not bool(door.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Olivine Cafe door unreachable: %s" % door.get("reason", ""),
		}
	var _cafe_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	var sailor: Dictionary = _talk_to(
		world, Vector2i(4, 4), Gen2WorldSprite.FACING_UP, save, random, data
	)
	var taught: bool = _teach_move(save, Gen2WorldFieldMove.MOVE_STRENGTH)
	_mirror_party(world, save)
	path.append({
		"step": "olivine_cafe_hm04_strength",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": sailor.get("run", {}),
		"items": _named_items(data, world.state.items()),
		"strength_taught": taught,
		"party_moves": _party_moves(save),
	})
	if not bool(sailor.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "HM04 handoff failed: %s" % sailor.get("reason", ""),
		}
	if not world.state.items().has(ITEM_HM_STRENGTH):
		return {"ok": false, "path": path, "reason": "HM04 did not reach the bag"}
	if not taught:
		return {"ok": false, "path": path, "reason": "no party member could learn STRENGTH"}
	var leaving: Dictionary = _warp_step(world, 1, 14)
	if not bool(leaving.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Olivine Cafe exit warp failed"}
	var _city_again: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	return {"ok": true}


## Cianwood City's gym, whose only corridor is walled by three
## SPRITEMOVEDATA_STRENGTH_BOULDER objects at (3,7), (4,7) and (5,7).
##
## Row 7 is the sole link between the entrance half and Chuck, its ends are walls
## at x=2 and x=6, and row 5 above it opens only at (4,5) and (5,5), the second of
## which a Black Belt stands on for good. So no single push opens it: pushing any
## boulder north just moves the wall up a row. The corridor opens by clearing
## (3,7) and (5,7) north first, then pushing the middle boulder sideways into the
## cell (3,7) left behind, which leaves (4,6) and (4,5) free above the freed
## (4,7). A state-space search over player cell plus boulder cells finds no
## shorter answer.
##
## Chuck himself needs no Strength: his script throws BOULDER1 aside with an
## applymovement of its own before the battle.
func _storm_badge_leg(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
) -> Dictionary:
	var door: Dictionary = _warp_walk(world, Vector2i(8, 43), save, random, data)
	if not bool(door.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Cianwood Gym door unreachable: %s" % door.get("reason", ""),
		}
	var gym_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)

	# The boulder at (4,7), faced from (4,8), is the first one the walk meets, so
	# it is the one that runs AskStrengthScript. TryStrengthOW answers 0 here
	# (party move plus Plain Badge, flag still clear), the yes/no is answered yes
	# by _drain_story, and Script_UsedStrength sets the flag.
	var asked: Dictionary = _talk_to(
		world, Vector2i(4, 8), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "cianwood_gym_ask_strength",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"entry_statuses": gym_entry.get("statuses", []),
		"run": asked.get("run", {}),
		"strength_active": world.strength_active(),
	})
	if not bool(asked.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "AskStrengthScript failed: %s" % asked.get("reason", ""),
		}
	if not world.strength_active():
		return {"ok": false, "path": path, "reason": "Strength did not become active"}

	var pushes: Array = []
	for push: Dictionary in [
		{"approach": Vector2i(3, 8), "direction": Vector2i.UP},
		{"approach": Vector2i(5, 8), "direction": Vector2i.UP},
		# The middle boulder goes sideways into the cell the first push freed.
		{"approach": Vector2i(5, 7), "direction": Vector2i.LEFT},
	]:
		var moved: Dictionary = _push_boulder_at(
			world, push["approach"], push["direction"], save, random, data
		)
		pushes.append(moved)
		if not bool(moved.get("ok", false)):
			path.append({
				"step": "cianwood_gym_boulders",
				"map": _map_value(world),
				"cell": _cell_value(world),
				"pushes": pushes,
			})
			return {
				"ok": false, "path": path,
				"reason": "boulder push from %s failed: %s" % [
					push["approach"], moved.get("reason", ""),
				],
			}
	path.append({
		"step": "cianwood_gym_boulders",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"pushes": pushes,
	})

	_mirror_party(world, save)
	var chuck: Dictionary = _talk_to(
		world, Vector2i(4, 2), Gen2WorldSprite.FACING_UP, save, random, data
	)
	path.append({
		"step": "cianwood_gym_chuck",
		"map": _map_value(world),
		"cell": _cell_value(world),
		"run": chuck.get("run", {}),
		"badge_count": world.state.badge_count(),
		"engine_flags": world.state.engine_flags(),
		"items": _named_items(data, world.state.items()),
	})
	if not bool(chuck.get("ok", false)):
		return {
			"ok": false, "path": path,
			"reason": "Chuck failed: %s" % chuck.get("reason", ""),
		}
	if not world.state.is_engine_flag_active(Gen2WorldState.badge_flag(
		BADGE_STORM, Gen2WorldState.is_crystal_profile(data)
	)):
		return {"ok": false, "path": path, "reason": "ENGINE_STORMBADGE was not set"}

	var leaving: Dictionary = _warp_step(world, 22, 3)
	if not bool(leaving.get("ok", false)):
		return {"ok": false, "path": path, "reason": "Cianwood Gym exit warp failed"}
	var _city_again: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	return {"ok": true}


## Walks to [param approach] and steps into [param direction], which is a push
## rather than a step because a boulder stands there. DoPlayerMovement.CheckNPC
## bumps the player on a push, so the step reports blocked and the boulder moving
## is the success signal.
func _push_boulder_at(
	world: Gen2WorldAPI,
	approach: Vector2i,
	direction: Vector2i,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
) -> Dictionary:
	var walked: Dictionary = _walk_cell_resolving(world, approach, save, random, data)
	if not bool(walked.get("ok", false)):
		return walked
	var result: Dictionary = world.move_result(direction)
	if not result.has("boulder_pushed"):
		return {
			"ok": false,
			"reason": "no boulder moved from %s: %s" % [
				approach, result.get("reason", "step succeeded"),
			],
		}
	var pushed: Dictionary = result["boulder_pushed"]
	return {
		"ok": true,
		"from_cell": _cell_value_from_vector(pushed["from_cell"]),
		"to_cell": _cell_value_from_vector(pushed["to_cell"]),
		"player_cell": _cell_value(world),
	}


## Stands in for AskTeachTMHM and TeachTMHM, which are not implemented: fills the
## first empty move slot of the first party member that has one, so the party
## mirror can answer CheckPartyMove. An egg is skipped, matching
## CheckIfCurPartyMonIsFitToFight refusing one as a combatant.
func _teach_move(save: Gen2SaveData, move: int) -> bool:
	for mon: Gen2SaveMon in save.party:
		if mon.is_egg or mon.moves.has(move):
			continue
		for slot: int in mon.moves.size():
			if int(mon.moves[slot]) == 0:
				mon.moves[slot] = move
				return true
	return false


func _party_moves(save: Gen2SaveData) -> Array:
	var out: Array = []
	for mon: Gen2SaveMon in save.party:
		out.append(mon.moves.duplicate())
	return out


## Olivine City to Cianwood City and back. Only the Route 40 and Route 41 legs
## are surfed: Olivine reaches Route 40 on foot, since the two maps meet on
## Olivine's western beach, and Route 40's south edge is the first water the
## route cannot walk around.
func _cianwood_crossing(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	path: Array,
	returning: bool,
) -> Dictionary:
	var label: String = "return" if returning else "outbound"
	# Route 40 (12,13) and Cianwood (27,41) are the two shores this leg uses: each
	# is a plain floor cell whose neighbour in `facing` is COLL_WATER, and neither
	# carries one of the SMASHABLE_ROCK objects Route 40 puts on its beach.
	var legs: Array = [
		{"step": "olivine_to_route_40", "direction": "west", "group": 22, "number": 1,
			"water": false},
		{"step": "route_40_to_route_41", "direction": "south", "group": 22, "number": 2,
			"water": true, "surf": Vector2i(12, 13), "facing": Gen2WorldSprite.FACING_DOWN},
		{"step": "route_41_to_cianwood", "direction": "west", "group": 22, "number": 3,
			"water": true, "ashore": Vector2i(27, 41)},
	]
	if returning:
		legs = [
			{"step": "cianwood_to_route_41", "direction": "east", "group": 22, "number": 2,
				"water": true, "surf": Vector2i(27, 41), "facing": Gen2WorldSprite.FACING_RIGHT},
			{"step": "route_41_to_route_40", "direction": "north", "group": 22, "number": 1,
				"water": true, "ashore": Vector2i(12, 13)},
			{"step": "route_40_to_olivine", "direction": "east", "group": 1, "number": 14,
				"water": false},
		]
	for leg: Dictionary in legs:
		if leg.has("surf"):
			var entered: Dictionary = _surf_at(
				world, leg["surf"], int(leg["facing"]), save, random, data
			)
			if not bool(entered.get("ok", false)):
				return {
					"ok": false, "path": path,
					"reason": "%s surf entry (%s) failed: %s" % [
						leg["step"], label, entered.get("reason", ""),
					],
				}
		var walked: Dictionary = _walk_connection_resolving(
			world, String(leg["direction"]), int(leg["group"]), int(leg["number"]),
			save, random, data, bool(leg["water"])
		)
		var entry: Dictionary = _drain_story(
			world, world.dispatch_map_entry(), save, random, data
		)
		var surfing: String = String(world.movement_mode)
		var ashore: Dictionary = {}
		if bool(walked.get("ok", false)) and leg.has("ashore"):
			# The far side of a surfed connection is still water. One water-only
			# walk to a named shore cell ends on .ExitWater, and every walk after
			# it is an ordinary one.
			ashore = _walk_cell_resolving(world, leg["ashore"], save, random, data, true)
		path.append({
			"step": "%s_%s" % [leg["step"], label],
			"map": _map_value(world),
			"cell": _cell_value(world),
			"movement_mode_on_arrival": surfing,
			"movement_mode": String(world.movement_mode),
			"encounters": walked.get("encounters", []),
			"run": entry,
		})
		if not bool(walked.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "%s (%s) failed: %s" % [leg["step"], label, walked.get("reason", "")],
			}
		if not ashore.is_empty() and not bool(ashore.get("ok", false)):
			return {
				"ok": false, "path": path,
				"reason": "%s landfall (%s) failed: %s" % [
					leg["step"], label, ashore.get("reason", ""),
				],
			}
	return {"ok": true}


## Walks to a gate door, takes it, and takes the gate's own warp to
## [param group]/[param number] on the far side.
func _gate_leg(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
	door: Vector2i,
	group: int,
	number: int,
) -> Dictionary:
	var walked: Dictionary = _warp_walk(world, door, save, random, data)
	if not bool(walked.get("ok", false)):
		return walked
	var _gate_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	var crossed: Dictionary = _warp_step(world, group, number)
	if not bool(crossed.get("ok", false)):
		return {"ok": false, "reason": "gate warp to %d/%d failed" % [group, number]}
	var _far_entry: Dictionary = _drain_story(
		world, world.dispatch_map_entry(), save, random, data
	)
	return {"ok": true}


## Cuts the tree the given cell faces. Route 35's only way past row 6 is the
## cut tree at (17,6), and the override dies with the map load, so the walked
## route cuts it again on every crossing exactly as a player would.
func _cut_at(
	world: Gen2WorldAPI,
	approach: Vector2i,
	facing: int,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
) -> Dictionary:
	var walked: Dictionary = _walk_cell_resolving(world, approach, save, random, data)
	if not bool(walked.get("ok", false)):
		return walked
	world.player_facing = facing
	var request: Dictionary = world.cut_request()
	if not bool(request.get("ok", false)):
		return {"ok": false, "reason": "cut refused: %s" % request.get("reason", "")}
	var applied: Dictionary = world.complete_cut()
	if not bool(applied.get("ok", false)):
		return {"ok": false, "reason": "cut failed: %s" % applied.get("reason", "")}
	return {"ok": true, "cell": applied.get("cell", approach)}


## Enters the water the given cell faces, the way _cut_at() cuts: request then
## commit, since UsedSurfScript reaches SurfStartStep only after its waitbutton.
## The commit spends the source's single slow_step, so the player ends one cell
## into the water already surfing.
func _surf_at(
	world: Gen2WorldAPI,
	approach: Vector2i,
	facing: int,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
) -> Dictionary:
	var walked: Dictionary = _walk_cell_resolving(world, approach, save, random, data)
	if not bool(walked.get("ok", false)):
		return walked
	world.player_facing = facing
	var request: Dictionary = world.surf_request()
	if not bool(request.get("ok", false)):
		return {"ok": false, "reason": "surf refused: %s" % request.get("reason", "")}
	var applied: Dictionary = world.complete_surf()
	if not bool(applied.get("ok", false)):
		return {"ok": false, "reason": "surf failed: %s" % applied.get("reason", "")}
	return {"ok": true, "cell": applied.get("cell", approach)}


## Walks to [param cell], faces [param facing] and drains the interaction.
func _talk_to(
	world: Gen2WorldAPI,
	cell: Vector2i,
	facing: int,
	save: Gen2SaveData,
	random: RandomNumberGenerator,
	data: GameData,
) -> Dictionary:
	var walked: Dictionary = _walk_cell_resolving(world, cell, save, random, data)
	if not bool(walked.get("ok", false)):
		return walked
	world.player_facing = facing
	var run: Dictionary = _drain_story(world, world.interact(), save, random, data, true)
	return {
		"ok": bool(run.get("terminal", false)),
		"reason": run.get("reason", ""),
		"run": run,
	}


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


## The whole read-only mirror in one call, so every leg answers VAR_PARTYCOUNT,
## CheckPokerus, checkpoke and CheckPartyMove the same way. Pokerus is false
## throughout: nothing on this route gives it.
func _mirror_party(world: Gen2WorldAPI, save: Gen2SaveData) -> void:
	var species: Array[int] = []
	var moves: Array = []
	var names: Array = []
	for mon: Gen2SaveMon in save.party:
		species.append(int(mon.species))
		var mon_moves: Array = []
		for move: int in mon.moves:
			if move != 0:
				mon_moves.append(move)
		moves.append(mon_moves)
		names.append(mon.nickname if not mon.nickname.is_empty() else "")
	world.set_party_summary(save.party.size(), false, species, moves, names)


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
	world: Gen2WorldAPI, direction_name: String, target_group: int, target_number: int,
	water_only: bool = false,
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
			var next: Vector2i = _reachable_step(world, cell, step, Vector2i(-1, -1), water_only)
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
##
## [param water_only] is what a surfing plan needs. can_walk_to() lets a surfing
## player step onto land, and that step is .ExitWater, so a plan drawn once and
## replayed would stop surfing partway and see every later water step refused.
## Restricting the frontier to WATER_TILE keeps the whole plan legal in the mode
## it was drawn in; the caller enters and leaves the water explicitly.
func _reachable_step(
	world: Gen2WorldAPI, cell: Vector2i, step: Vector2i,
	warp_target: Vector2i = Vector2i(-1, -1),
	water_only: bool = false,
) -> Vector2i:
	var direct: Vector2i = cell + step
	if water_only \
		and world.collision_permission_at(direct) != Gen2WorldCollision.WATER_TILE:
		return Vector2i(-1, -1)
	# Stepping onto a warp tile takes it, so a walked route can only cross one
	# by leaving the map there. The BFS treats it as a wall unless it is the
	# cell it was asked to reach, which is what makes Ecruteak Gym's thirty
	# holes a maze instead of open floor. A warp_event on ordinary floor is
	# inert, as CheckWarpCollision has it, so it is not a wall.
	if direct != warp_target and not world.warp_at(direct).is_empty() \
		and Gen2WorldCollision.is_warp_tile(world.collision_code_at(direct)):
		return Vector2i(-1, -1)
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


## [param water_only] keeps a surfing plan on the water, the way
## _walk_to_connection() does, except that [param target] is always allowed: a
## landfall names one land cell and the step onto it is .ExitWater.
func _walk_to_story_cell(
	world: Gen2WorldAPI, target: Vector2i, water_only: bool = false
) -> Dictionary:
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
			var next: Vector2i = _reachable_step(
				world, cell, direction, target, water_only and cell + direction != target
			)
			if next.x < 0 or previous.has(next):
				continue
			previous[next] = {"cell": cell, "direction": direction}
			frontier.append(next)
	if not found:
		return {
			"ok": false,
			"reason": "target %s unreachable from %s (collision $%02x, walkable %s)" % [
				target, world.player_cell, world.collision_code_at(target),
				world.can_walk_to(target),
			],
			"target": _cell_value_from_vector(target),
		}
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
	water_only: bool = false,
) -> Dictionary:
	var runs: Array = []
	for _attempt: int in WALK_RESOLVE_ATTEMPTS:
		var walked: Dictionary = _walk_to_connection(
			world, direction_name, target_group, target_number, water_only
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
	water_only: bool = false,
) -> Dictionary:
	var runs: Array = []
	for _attempt: int in WALK_RESOLVE_ATTEMPTS:
		var walked: Dictionary = _walk_to_story_cell(world, target, water_only)
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
