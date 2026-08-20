extends SceneTree

## Photographs the save screen for a cached cartridge.
##
##   Godot --path . -s res://tools/preview_saves.gd -- <out.png> [light|dark]

var _output: String = ""
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_output = args[0]
	var mode: String = args[1] if args.size() > 1 else "light"
	var options: Gen2Options = Gen2OptionsStore.current()
	options.ui_theme = StringName(mode)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	root.set_content_scale_size(Vector2i(1280, 800))
	root.size = Vector2i(1280, 800)
	# Autoloads are not global identifiers inside a tool script, and an absolute
	# path does not resolve from outside the running scene, so the runtime is
	# found on the root by name.
	var runtime: Node = root.get_node_or_null(NodePath("GameRuntime"))
	for game_id: StringName in RomRegistry.ORDER:
		var data: GameData = GameData.open(game_id)
		if data != null:
			runtime.call("select_game", game_id)
			break
	root.add_child(load("res://game/save/save_screen.tscn").instantiate())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 26:
		return false
	RenderingServer.force_draw()
	var image: Image = root.get_texture().get_image()
	image.save_png(_output)
	print("Wrote %s" % _output)
	quit()
	return true
