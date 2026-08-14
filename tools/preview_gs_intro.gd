extends SceneTree

## Captures Gold and Silver's intro movie against a real imported cache, one
## source frame at a time.
##
##   Godot --headless --path . -s res://tools/preview_gs_intro.gd -- gold /tmp/i.png [frame;frame]
##
## [frame] is how many source frames to spend before the shot; several separated
## by `;` write one file each, numbered. With no frame list the tool runs the
## whole movie and prints the frame each scene starts on, which is what pins the
## budgets.
##
## Headless: the page draws into an [Image] rather than through a viewport, so
## there is no window and no settle.

const MAX_FRAMES: int = 20000


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 1:
		push_error("Usage: preview_gs_intro.gd -- <game> [output.png] [frame;frame;...]")
		quit(1)
		return

	var data: GameData = GameData.open(StringName(args[0]))
	if data == null:
		push_error("No cache for %s. Import roms/%s.gbc first." % [args[0], args[0]])
		quit(1)
		return
	if not Gen2GoldSilverIntro.available(data):
		push_error("The %s cache holds no Gold and Silver intro." % args[0])
		quit(1)
		return

	var sine: Gen2BattleAnimData = Gen2BattleAnimData.from_game_data(data)
	var movie: Gen2GoldSilverIntro = Gen2GoldSilverIntro.create(data, sine)
	if args.size() < 2:
		_report(movie)
		quit(0)
		return

	var page: Gen2GoldSilverIntroPage = Gen2GoldSilverIntroPage.from_data(data)
	if page == null:
		push_error("The %s cache holds no Gold and Silver intro art." % args[0])
		quit(1)
		return

	var frames: Array = []
	for step: String in (args[2] if args.size() > 2 else "0").split(";", false):
		frames.append(maxi(int(step.strip_edges()), 0))
	frames.sort()

	var spent: int = 0
	for wanted: int in frames:
		while spent < wanted and not movie.finished():
			movie.advance_frame()
			spent += 1
		var path: String = args[1]
		if frames.size() > 1:
			path = "%s-%d.%s" % [args[1].get_basename(), wanted, args[1].get_extension()]
		var error: Error = page.draw(movie).save_png(path)
		if error != OK:
			push_error("Could not write %s (%d)." % [path, error])
			quit(1)
			return
		print("frame %d, scene %d, %s -> %s" % [
			spent, movie.scene(), movie.cutscene(), path,
		])
	quit(0)


## The whole movie, printing the frame each scene starts on and every sound it
## asks for. This is the budget the boot cinema spends.
func _report(movie: Gen2GoldSilverIntro) -> void:
	var scene: int = movie.scene()
	print("scene 0 starts at frame 0")
	var frames: int = 0
	while not movie.finished() and frames < MAX_FRAMES:
		for event: Dictionary in movie.advance_frame():
			print("  frame %d: %s %s" % [
				movie.frame(), event["type"],
				event.get("sfx", event.get("music", "")),
			])
		frames += 1
		if movie.scene() != scene:
			scene = movie.scene()
			print("scene %d starts at frame %d" % [scene, movie.frame()])
	print("%d frames, %d scenes" % [movie.frame(), movie.scene()])
