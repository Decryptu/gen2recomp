extends SceneTree

## Captures the window-resolution save overlays against a real cache: the party,
## the PC boxes and the start menu's pack.
##
##   Godot --path . -s res://tools/preview_party.gd -- <game> <out.png> [party|box|pack|select|stats] [presses]
##
## `presses` is a comma-separated button list driven into the overlay before the
## shot, the way `preview_world_services.gd` photographs a second page: `d` is
## down, `u` up, `l` left, `r` right, `a` and `b` the two buttons. Several
## comma-separated lists write one file each.
##
## Each is built directly rather than through the overworld, which is what makes
## this a screen test rather than a world one; the pack is given a world of its
## own because its transactions read one. They reach the runtime
## through `Gen2GameRuntime`, so they compile under `-s` where naming the
## autoload by identifier would not.
##
## Opens a window: rendering needs a display. Pass `--resolution` for a size
## other than the project's own.

const FRAMES_BEFORE_CAPTURE: int = 6

## Item numbers from `constants/item_constants.asm`, the three rows the pack's
## own submenu split is worth photographing.
const ITEM_POTION: int = 0x12
const ITEM_BICYCLE: int = 0x07
const ITEM_REPEL: int = 0x14

const BUTTONS: Dictionary = {
	"u": Gen2Button.UP, "d": Gen2Button.DOWN, "l": Gen2Button.LEFT,
	"r": Gen2Button.RIGHT, "a": Gen2Button.A, "b": Gen2Button.B,
}

var _output_path: String = ""
var _what: String = "party"
var _programs: Array[String] = [""]
var _at: int = 0
var _screen: Control = null
var _elapsed: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error(
			"Usage: preview_party.gd -- <game> <out.png> [party|box|pack|select|stats]"
		)
		quit(1)
		return
	var game: StringName = StringName(args[0])
	_output_path = args[1]
	if args.size() > 2:
		_what = args[2]
	if args.size() > 3:
		_programs = []
		for program: String in args[3].split(";"):
			_programs.append(program)

	var directory: String = _find_cache(game)
	if directory.is_empty():
		push_error("No cache for %s. Run tools/import_rom.gd first." % game)
		quit(1)
		return
	var data: GameData = GameData.open_directory(directory)
	if data == null:
		push_error("Could not open the cache for %s." % game)
		quit(1)
		return

	_screen = _build(data)
	if _screen == null:
		quit(1)
		return
	root.add_child(_screen)
	# Both are window-resolution panels rather than hardware-tile screens, so
	# they are given the whole window the way a scene root would be.
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	current_scene = _screen


## A development save, so the party has members without a slot on disk. Both
## screens are opened embedded, which is the shape the overworld stacks them in
## and the one with no scene changes in it.
func _build(data: GameData) -> Control:
	var save: Gen2SaveData = Gen2SaveStore.create_development_save(data, 0)
	if save == null:
		push_error("Could not build a development save for %s." % data.id)
		return null
	if _what == "box":
		var boxes := Gen2BoxScreen.new()
		boxes.set_context(data, save, false, true)
		return boxes
	if _what == "pack" or _what == "select":
		return _build_pack(data, save)
	## The stats screen's mod seam has no player until a mod is installed, so the
	## shipped example's own page is registered here: this is the one place the
	## fourth page and its relaid-out indicators can be looked at.
	if _what == "stats":
		var manifest: Dictionary = Gen2ModManifest.read("res://mods/examples/new_content")
		if not bool(manifest.get("ok", false)) \
			or not bool(Gen2ModHost.instance().load_mod(manifest["manifest"]).get("ok", false)):
			push_error("Could not load the example mod's stats page.")
			return null
	var party := Gen2PartyScreen.new()
	party.set_context(data, save, true)
	return party


## The start menu over a world holding one of each pack row the submenu splits
## on: a POTION (USE/GIVE/TOSS), a REPEL (which also reaches SEL) and the
## BICYCLE, whose key-item row offers neither GIVE nor TOSS.
func _build_pack(data: GameData, save: Gen2SaveData) -> Control:
	var state := Gen2WorldState.new({}, {}, {ITEM_POTION: 3, ITEM_REPEL: 2, ITEM_BICYCLE: 1})
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, Gen2WorldSpawn.NEW_BARK_GROUP, Gen2WorldSpawn.PLAYERS_HOUSE_2F,
		Gen2WorldSpawn.HOME_CELL, state
	)
	if world == null:
		push_error("Could not open a world for %s." % data.id)
		return null
	save.world = world.snapshot()
	var menu := Gen2StartMenuScreen.new()
	## No slot on disk, so nothing this photographs is written anywhere.
	menu.set_party_context(save, false)
	if not menu.open(world, data, func() -> Dictionary: return {"ok": true}):
		push_error("Could not open the start menu for %s." % data.id)
		return null
	## `SelectMenu` over a BICYCLE already registered, which is what the button
	## reaches in the overworld and what no button driven into this screen can.
	if _what == "select":
		state.set_registered_item(ITEM_BICYCLE)
		menu.open_registered_item()
	return menu


func _drive(program: String) -> void:
	for key: String in program.split(",", false):
		var button: Variant = BUTTONS.get(key.strip_edges().to_lower(), null)
		if button == null:
			push_error("Unknown button %s" % key)
			continue
		_screen.handle_button(int(button))


func _process(_delta: float) -> bool:
	_elapsed += 1
	if _elapsed < FRAMES_BEFORE_CAPTURE:
		return false
	if _at >= _programs.size():
		quit(0)
		return true
	if _elapsed == FRAMES_BEFORE_CAPTURE:
		_drive(_programs[_at])
		return false
	RenderingServer.force_draw()
	var image: Image = root.get_texture().get_image()
	var path: String = _output_path
	if _programs.size() > 1:
		path = "%s_%d.%s" % [
			_output_path.get_basename(), _at, _output_path.get_extension(),
		]
	var error: Error = image.save_png(path)
	if error != OK:
		push_error("Could not write %s (error %d)" % [path, error])
		quit(1)
		return true
	print("Wrote %s (%dx%d)" % [path, image.get_width(), image.get_height()])
	_at += 1
	_elapsed = FRAMES_BEFORE_CAPTURE - 1
	return false


func _find_cache(game: StringName) -> String:
	var sha1: String = RomRegistry.sha1_for(game)
	if sha1.is_empty():
		return ""
	var directory: String = RomCache.directory_for(game, sha1)
	return directory if RomCache.is_usable(directory) else ""
