extends SceneTree

## Prints Prof Oak's PC against a real imported cache.
##
##   Godot --headless --path . -s res://tools/preview_prof_oaks_pc.gd -- crystal [caught]
##
## Without `caught` it walks every threshold `FindOakRating` bands into, which is
## the whole table and the boundary either side of each row. With one it prints
## the three pages `ProfOaksPCBoot` shows for that many owned, with the seen
## count matching.


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Usage: preview_prof_oaks_pc.gd -- <game> [caught]")
		quit(1)
		return

	var data: GameData = GameData.open(StringName(args[0]))
	if data == null:
		push_error("No cache for %s. Import roms/%s.gbc first." % [args[0], args[0]])
		quit(1)
		return
	if data.oak_ratings().is_empty():
		push_error("The %s cache holds no Oak rating table." % args[0])
		quit(1)
		return

	if args.size() > 1:
		_print_boot(data, int(args[1]))
		quit(0)
		return

	print("ask:    %s" % data.oak_pc_text("ask").replace("\n", " / "))
	print("level:  %s" % data.oak_pc_text("level").replace("\n", " / "))
	print("closed: %s" % data.oak_pc_text("closed").replace("\n", " / "))
	var previous: int = -1
	for row: Variant in data.oak_ratings():
		var threshold: int = int((row as Dictionary)["threshold"])
		print("%3d..%3d  sfx %3d  %s" % [
			previous + 1, threshold, int((row as Dictionary)["sfx"]),
			String((row as Dictionary)["text"]).replace("\n", " / "),
		])
		# Both ends of the band answer this row and nothing else does.
		for caught: int in [previous + 1, threshold]:
			var found: Dictionary = Gen2ProfOaksPC.rating_for(data, caught)
			if int(found.get("threshold", -1)) != threshold:
				push_error("caught %d landed on threshold %d, wanted %d" % [
					caught, int(found.get("threshold", -1)), threshold,
				])
				quit(1)
				return
		previous = threshold
	quit(0)


func _print_boot(data: GameData, caught: int) -> void:
	var state := Gen2WorldState.new()
	for species: int in range(1, caught + 1):
		state.set_species_caught(species)
	var boot: Dictionary = Gen2ProfOaksPC.boot(data, state)
	print("seen %d, caught %d, sfx %d" % [boot["seen"], boot["caught"], boot["sfx"]])
	for page: Variant in boot["pages"] as Array:
		print("---")
		print(String(page))
