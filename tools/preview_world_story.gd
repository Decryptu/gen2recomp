extends SceneTree

## Exercises map-entry callbacks and one facing interaction from an imported
## cartridge cache without opening the ROM at runtime.
##
##   Godot --headless --path . -s res://tools/preview_world_story.gd -- \
##     crystal 3 19 3 5 1 37,1744
##
## The optional final argument is a comma-separated list of event flags. Facing
## uses the runtime values: down=0, up=1, left=2, right=3.


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
	print(JSON.stringify({
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
	}))
	quit(0)
