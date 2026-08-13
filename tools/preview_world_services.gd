extends SceneTree

## Captures the production world-service overlay with a deterministic cache.
##
##   Godot --path . -s res://tools/preview_world_services.gd -- /tmp/mart.png
##   Godot --path . -s res://tools/preview_world_services.gd -- /tmp/kurt.png apricorn
##
## `presses` drives the overlay with its own buttons before the shot, which is
## how the apricorn mode's second box is photographed.

const WINDOW_SIZE := Vector2i(1152, 648)
const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

## The seven ApricornBalls rows, named so a capture reads as the cartridge's
## list rather than as the fixture's ITEM<number> placeholders.
const APRICORNS: Dictionary = {
	0x55: "RED APRICORN", 0x59: "BLU APRICORN", 0x5C: "YLW APRICORN",
	0x5D: "GRN APRICORN", 0x61: "WHT APRICORN", 0x63: "BLK APRICORN",
	0x65: "PNK APRICORN",
}

var _screen: Gen2WorldScreen = null
var _data: GameData = null
var _output_path: String = ""
var _kind: StringName = &"mart"
var _presses: Array[int] = []
var _fixture_directory: String = ""
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Usage: preview_world_services.gd -- <output.png> [mart|apricorn] [presses]")
		quit(1)
		return
	_output_path = args[0]
	if args.size() > 1:
		_kind = StringName(args[1])
	if args.size() > 2:
		for name: String in args[2].split(",", false):
			_presses.append(_button(name))
	_fixture_directory = Fixture.directory()
	_data = Fixture.build()
	_write_service_cache()
	_data = GameData.open_directory(_fixture_directory)
	root.set_content_scale_size(WINDOW_SIZE)
	root.size = WINDOW_SIZE
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_screen = packed.instantiate() as Gen2WorldScreen
	_screen.map_group = Fixture.MAP_GROUP
	_screen.map_number = Fixture.MAP_NUMBER
	_screen.start_cell = Vector2i(7, 6)
	var items: Dictionary = {7: 1}
	if _kind == &"apricorn":
		for item: int in [0x55, 0x59, 0x5C, 0x5D, 0x61]:
			items[item] = 6
	var state := Gen2WorldState.new({}, {}, items, {0: 500})
	var world := Gen2WorldAPI.open(
		_data, Fixture.MAP_GROUP, Fixture.MAP_NUMBER, Vector2i(7, 6), state
	)
	var save := Gen2SaveStore.create_development_save(_data, 0)
	save.world = world.snapshot()
	_screen.set_data(_data)
	_screen.set_save(save)
	root.add_child(_screen)
	current_scene = _screen


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		var waiting: Array = _screen._world.dispatch_script_events(Vector2i(7, 6))
		_screen._show_script_results(waiting)
		for button: int in _presses:
			_screen._service_host.handle_button(button)
	if _frames < 18:
		return false
	var image: Image = root.get_texture().get_image()
	var error: Error = image.save_png(_output_path)
	if error != OK:
		push_error("Could not write %s (error %d)" % [_output_path, error])
		quit(1)
		return true
	print("Wrote %s (%dx%d)" % [_output_path, image.get_width(), image.get_height()])
	RomCache.clear(_fixture_directory)
	quit(0)
	return true


static func _button(name: String) -> int:
	match name.to_lower():
		"up": return Gen2Button.UP
		"down": return Gen2Button.DOWN
		"left": return Gen2Button.LEFT
		"right": return Gen2Button.RIGHT
		"a": return Gen2Button.A
		"b": return Gen2Button.B
	return Gen2Button.NONE


func _write_service_cache() -> void:
	var items: Array = RomCache.read_json(RomCache.items_path(_fixture_directory))
	for raw: Dictionary in items:
		var number: int = int(raw.get("number", 0))
		if number == 7:
			raw["name"] = "ITEM7"
			raw["price"] = 120
		elif APRICORNS.has(number):
			raw["name"] = String(APRICORNS[number])
	RomCache.write_json(RomCache.items_path(_fixture_directory), items)
	RomCache.write_json(RomCache.world_marts_path(_fixture_directory), {
		"marts": [{"index": 0, "bank": Fixture.BANK, "address": 0x4000, "items": [7]}],
		"default": {"items": [7]}, "special": {},
	})
	var scripts: Dictionary = RomCache.read_json(
		RomCache.world_scripts_path(_fixture_directory)
	)
	scripts[Gen2WorldScript.pointer_key(Fixture.BANK, 0x6320)] = [
		Gen2WorldScript.SPECIAL,
		Gen2WorldScriptRunner.SPECIAL_SELECT_APRICORN_FOR_KURT, 0x00,
		Gen2WorldScript.END,
	] if _kind == &"apricorn" else [
		0x94, 0, 0x00, 0x40, 0x91,
	]
	RomCache.write_json(RomCache.world_scripts_path(_fixture_directory), scripts)
	var maps: Array = RomCache.read_json(RomCache.world_maps_path(_fixture_directory))
	for raw: Dictionary in maps:
		if int(raw.get("group", -1)) != Fixture.MAP_GROUP \
		or int(raw.get("number", -1)) != Fixture.MAP_NUMBER:
			continue
		var events: Dictionary = raw.get("events", {})
		events["coord_events"] = [{"x": 7, "y": 6, "script": 0x6320}]
		raw["events"] = events
	RomCache.write_json(RomCache.world_maps_path(_fixture_directory), maps)
