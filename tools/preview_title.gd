extends SceneTree

## Captures the title screen against a real imported cache, one source frame at
## a time.
##
##   Godot --headless --path . -s res://tools/preview_title.gd -- crystal /tmp/t.png [frame]
##
## [frame] is how many source frames to spend before the shot, so Crystal's
## twenty-eight-frame entrance, its Suicune cycle and Gold's bird can each be
## looked at where they actually are. Several frames separated by `;` write one
## file each, numbered.
##
## Headless: the page is drawn into an [Image] rather than through a viewport, so
## no window and no settle are needed.


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Usage: preview_title.gd -- <game> <output.png> [frame;frame;...]")
		quit(1)
		return

	var data: GameData = GameData.open(StringName(args[0]))
	if data == null:
		push_error("No cache for %s. Import roms/%s.gbc first." % [args[0], args[0]])
		quit(1)
		return

	var page: Gen2TitlePage = Gen2TitlePage.from_data(data)
	if page == null:
		push_error("The %s cache holds no title screen art." % args[0])
		quit(1)
		return

	var frames: Array = []
	for step: String in (args[2] if args.size() > 2 else "0").split(";", false):
		frames.append(maxi(int(step.strip_edges()), 0))
	frames.sort()

	var scene: Gen2TitleScene = Gen2TitleScene.create(data.id, Gen2BattleAnimData.from_game_data(data))
	var spent: int = 0
	var written: int = 0
	for wanted: int in frames:
		while spent < wanted:
			scene.advance_frame()
			spent += 1
		var path: String = args[1]
		if frames.size() > 1:
			path = "%s-%d.%s" % [args[1].get_basename(), wanted, args[1].get_extension()]
		var error: Error = page.draw(scene).save_png(path)
		if error != OK:
			push_error("Could not write %s (error %d)" % [path, error])
			quit(1)
			return
		print("Wrote %s, frame %d, scene %s, scroll %d, timer %d" % [
			path, wanted, scene.scene(), scene.scroll_x(), scene.timer(),
		])
		written += 1
	quit(0 if written > 0 else 1)
