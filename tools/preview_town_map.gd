extends SceneTree

## Captures the region map against a real imported cache.
##
##   Godot --headless --path . -s res://tools/preview_town_map.gd -- \
##       crystal /tmp/map.png [landmark] [town_map|card] [presses]
##
## [landmark] is `TownMap_GetCurrentLandmark`'s answer, which picks the region and
## where the player icon stands; `card` draws the Pokegear's own MAP frame instead
## of `_TownMap`'s corner box. [presses] is a `u,d,b` list driven into the screen
## before the shot, which is how a cursor walk is photographed. Pass `hof` in the
## press list to open with `STATUSFLAGS_HALL_OF_FAME_F` set, which is what widens
## the Kanto window past Victory Road.
##
## Headless: the screen composes into an [Image] rather than through a viewport,
## so no window and no settle are needed.

const BUTTONS: Dictionary = {
	"u": Gen2Button.UP, "d": Gen2Button.DOWN,
	"l": Gen2Button.LEFT, "r": Gen2Button.RIGHT,
	"a": Gen2Button.A, "b": Gen2Button.B,
}


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error(
			"Usage: preview_town_map.gd -- <game> <output.png> [landmark] "
			+ "[town_map|card] [presses]"
		)
		quit(1)
		return

	var data: GameData = GameData.open(StringName(args[0]))
	if data == null:
		push_error("No cache for %s. Import roms/%s.gbc first." % [args[0], args[0]])
		quit(1)
		return

	var landmark: int = int(args[2]) if args.size() > 2 else Gen2TownMap.JOHTO_LANDMARK
	var screen: StringName = Gen2TownMap.SCREEN_POKEGEAR_CARD \
		if args.size() > 3 and args[3] == "card" else Gen2TownMap.SCREEN_TOWN_MAP
	var presses: Array = []
	var hall_of_fame: bool = false
	for token: String in (args[4] if args.size() > 4 else "").split(",", false):
		var key: String = token.strip_edges().to_lower()
		if key == "hof":
			hall_of_fame = true
		elif BUTTONS.has(key):
			presses.append(int(BUTTONS[key]))

	var host := Gen2TownMapScreen.new()
	root.add_child(host)
	var opened: bool = host.open(
		data, landmark, hall_of_fame, screen,
		[&"map", &"phone", &"radio"] as Array,
	)
	if not opened:
		push_error("The %s cache holds no region map." % args[0])
		quit(1)
		return
	for button: int in presses:
		host.handle_button(button)

	var error: Error = host.render().save_png(args[1])
	if error != OK:
		push_error("Could not write %s (error %d)" % [args[1], error])
		quit(1)
		return
	print("Wrote %s: landmark %d, region %s, cursor %d %s, window %d..%d" % [
		args[1], landmark,
		"kanto" if host.map().region() == Gen2TownMap.REGION_KANTO else "johto",
		host.cursor_landmark(), host.cursor_name().replace(" ", "_"),
		host.map().first_landmark(), host.map().last_landmark(),
	])
	quit(0)
