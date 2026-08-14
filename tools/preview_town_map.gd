extends SceneTree

## Captures the region map against a real imported cache.
##
##   Godot --headless --path . -s res://tools/preview_town_map.gd -- \
##       crystal /tmp/map.png [landmark] [town_map|card|area:<species>] [presses]
##
## [landmark] is `TownMap_GetCurrentLandmark`'s answer, which picks the region and
## where the player icon stands; `card` draws the Pokegear's own MAP frame instead
## of `_TownMap`'s corner box, and `area:19` draws `Pokedex_GetArea` for that
## species. [presses] is a `u,d,l,r,a,b` list driven into the screen before the
## shot, which is how a cursor walk is photographed. Three other tokens: `hof`
## opens with `STATUSFLAGS_HALL_OF_FAME_F` set, which widens the Kanto window past
## Victory Road and is what lets the dex area reach Kanto at all; `sel` and `rel`
## press and release SELECT, the dex area's held button; and `f<n>` spends n
## hardware frames, which is how the nest blink is caught either way up.
##
## Headless: the screen composes into an [Image] rather than through a viewport,
## so no window and no settle are needed.

const BUTTONS: Dictionary = {
	"u": Gen2Button.UP, "d": Gen2Button.DOWN,
	"l": Gen2Button.LEFT, "r": Gen2Button.RIGHT,
	"a": Gen2Button.A, "b": Gen2Button.B, "sel": Gen2Button.SELECT,
}


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error(
			"Usage: preview_town_map.gd -- <game> <output.png> [landmark] "
			+ "[town_map|card|area:<species>] [presses]"
		)
		quit(1)
		return

	var data: GameData = GameData.open(StringName(args[0]))
	if data == null:
		push_error("No cache for %s. Import roms/%s.gbc first." % [args[0], args[0]])
		quit(1)
		return

	var landmark: int = int(args[2]) if args.size() > 2 else Gen2TownMap.JOHTO_LANDMARK
	var mode: String = args[3] if args.size() > 3 else "town_map"
	var species: int = int(mode.split(":")[1]) if mode.begins_with("area:") else 0
	var hall_of_fame: bool = false
	var steps: Array = []
	for token: String in (args[4] if args.size() > 4 else "").split(",", false):
		var key: String = token.strip_edges().to_lower()
		if key == "hof":
			hall_of_fame = true
		elif key.begins_with("f"):
			steps.append(["frames", maxi(1, int(key.substr(1)))])
		elif key == "rel":
			steps.append(["release", Gen2Button.SELECT])
		elif BUTTONS.has(key):
			steps.append(["press", int(BUTTONS[key])])

	var host := Gen2TownMapScreen.new()
	root.add_child(host)
	var opened: bool = _open(host, data, species, landmark, hall_of_fame, mode)
	if not opened:
		push_error("The %s cache holds no region map." % args[0])
		quit(1)
		return
	for step: Array in steps:
		match String(step[0]):
			"frames":
				for _frame: int in int(step[1]):
					host.advance_frame()
			"release":
				host.release_button(int(step[1]))
			_:
				host.handle_button(int(step[1]))

	var error: Error = host.render().save_png(args[1])
	if error != OK:
		push_error("Could not write %s (error %d)" % [args[1], error])
		quit(1)
		return
	var region: String = Gen2TownMap.region_name(host.map().region())
	if species > 0:
		print("Wrote %s: %s'S NEST, region %s, %d nests, player at landmark %d %s" % [
			args[1], data.species(species).get("name", "?"), region,
			host.current_nests().size(), landmark,
			data.landmark_name(landmark).replace(" ", "_"),
		])
	else:
		print("Wrote %s: landmark %d, region %s, cursor %d %s, window %d..%d" % [
			args[1], landmark, region,
			host.cursor_landmark(), host.cursor_name().replace(" ", "_"),
			host.map().first_landmark(), host.map().last_landmark(),
		])
	quit(0)


func _open(
	host: Gen2TownMapScreen, data: GameData, species: int, landmark: int,
	hall_of_fame: bool, mode: String
) -> bool:
	if species > 0:
		var roaming: Array = data.world_roaming_mons()
		var nests: Array = []
		for region: int in Gen2TownMap.REGION_NAMES.size():
			nests.append(Gen2WorldEncounter.nests(
				data, species, Gen2TownMap.region_name(region), roaming
			))
		return host.open_dex_area(data, species, nests, landmark, hall_of_fame)
	return host.open(
		data, landmark, hall_of_fame,
		Gen2TownMap.SCREEN_POKEGEAR_CARD if mode == "card" else Gen2TownMap.SCREEN_TOWN_MAP,
		[&"map", &"phone", &"radio"] as Array,
	)
