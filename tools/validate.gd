extends SceneTree

## The real-cache check suite. Every topic runs all three cartridges against a
## freshly imported cache; expected values come from the pinned pokecrystal and
## pokegold sources and are named in each topic's own file.
##
##   Godot --headless --path . -s res://tools/validate.gd -- all
##   Godot --headless --path . -s res://tools/validate.gd -- cut surf
##   Godot --headless --path . -s res://tools/validate.gd -- field_moves
##
## A topic is a script under `tools/checks/` with `func run(r) -> void`, found by
## its file name. Add one there rather than writing another entry point; nothing
## here needs editing for it to be picked up.

const CheckRun := preload("res://tools/lib/check_run.gd")
const CHECKS: String = "res://tools/checks"

## Named runs over several topics. A group is a convenience, not a boundary: any
## topic can still be asked for on its own.
const GROUPS: Dictionary = {
	&"field_moves": [
		&"cut", &"surf", &"whirlpool", &"strength", &"headbutt", &"rock_smash",
		&"field_move_prompts",
	],
	&"terrain": [&"ledge_hops", &"side_walls", &"drawn_blocks", &"story_map_ids"],
	&"johto": [
		&"radio_tower", &"rising_badge", &"command_queues", &"item_balls",
		&"route_27", &"magnet_train",
	],
	&"kanto": [
		&"vermilion", &"saffron", &"celadon", &"cerulean", &"lavender", &"fuchsia",
		&"pewter", &"cinnabar", &"radio", &"elite_four", &"ss_aqua", &"mt_silver",
	],
	&"art": [&"intro_movie", &"gs_intro", &"credits", &"town_map", &"battle_anims"],
	&"tables": [&"tmhm", &"naming", &"world_scripts", &"opening_lane"],
	&"trainers": [&"crystal_route30_trainer", &"gold_route30_trainer"],
}


func _initialize() -> void:
	var topics: PackedStringArray = _available()
	var names: PackedStringArray = _requested(topics)
	if names.is_empty():
		print("Topics: %s" % ", ".join(topics))
		print("Groups: %s, all" % ", ".join(PackedStringArray(GROUPS.keys())))
		quit(2)
		return

	var failed: PackedStringArray = []
	for name: String in names:
		var run := CheckRun.new()
		print("--- %s" % name)
		# A topic that will not compile answers no `new`. Reporting that and
		# moving on is what keeps one broken file from taking the suite with it,
		# and from leaving the tree running with nothing left to quit it.
		var script: Script = load("%s/%s.gd" % [CHECKS, name]) as Script
		var topic: Object = script.new() if script != null and script.can_instantiate() else null
		if topic == null:
			printerr("FAIL %s: the topic script did not load." % name)
			failed.append(name)
			continue
		topic.call(&"run", run)
		if run.failures.is_empty():
			print("PASS %s" % name)
			continue
		for message: String in run.failures:
			printerr("FAIL %s: %s" % [name, message])
		failed.append(name)

	if not failed.is_empty():
		printerr("FAILED: %s" % ", ".join(failed))
	quit(1 if not failed.is_empty() else 0)


## Every topic on disk, so a new check file needs no registration.
func _available() -> PackedStringArray:
	var out: PackedStringArray = []
	for file: String in DirAccess.get_files_at(CHECKS):
		if file.ends_with(".gd"):
			out.append(file.get_basename())
	out.sort()
	return out


## The topics named on the command line, expanding groups and refusing an
## unknown name rather than passing silently.
func _requested(topics: PackedStringArray) -> PackedStringArray:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		return PackedStringArray()

	var out: PackedStringArray = []
	for name: String in args:
		if name == "all":
			return topics
		if GROUPS.has(StringName(name)):
			for topic: StringName in GROUPS[StringName(name)]:
				out.append(String(topic))
			continue
		if not topics.has(name):
			printerr("Unknown topic %s." % name)
			return PackedStringArray()
		out.append(name)
	return out
