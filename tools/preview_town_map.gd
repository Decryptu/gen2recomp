extends SceneTree

## Captures the region map against a real imported cache.
##
##   Godot --headless --path . -s res://tools/preview_town_map.gd -- \
##       crystal /tmp/map.png [landmark] [town_map|card|clock|phone|radio|area:<species>|fly[:all]] [presses]
##
## [landmark] is `TownMap_GetCurrentLandmark`'s answer, which picks the region and
## where the player icon stands; `card` draws the Pokegear's own MAP frame instead
## of `_TownMap`'s corner box, `area:19` draws `Pokedex_GetArea` for that
## species, and `fly` draws `_FlyMap` with its own cursor, `fly:all` with every
## flypoint visited rather than none. `clock`, `phone` and `radio` are the
## Pokegear's other three cards, each read off a real world the way the service
## host reads it. [presses] is a `u,d,l,r,a,b` list driven into the screen before the
## shot, which is how a cursor walk is photographed. Three other tokens: `hof`
## opens with `STATUSFLAGS_HALL_OF_FAME_F` set, which widens the Kanto window past
## Victory Road and is what lets the dex area reach Kanto at all; `sel` and `rel`
## press and release SELECT, the dex area's held button; and `f<n>` spends n
## hardware frames, which is how the nest blink is caught either way up.
##
## Headless: the screen composes into an [Image] rather than through a viewport,
## so no window and no settle are needed.

## Where a card preview's world stands, which is what its clock, dial and contact
## list are read from.
const NEW_BARK_GROUP: int = 24
const NEW_BARK_MAP: int = 7

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
			+ "[town_map|card|clock|phone|radio|area:<species>|fly[:all]] [presses]"
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

	if mode in ["clock", "phone", "radio"]:
		_capture_card(data, StringName(mode), args[1], steps)
		return

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
	if mode.begins_with("fly"):
		var visited: Array[int] = []
		if mode == "fly:all":
			for index: int in data.flypoint_count():
				visited.append(index)
		return host.open_fly(
			data, landmark,
			Gen2WorldRadio.is_kanto_landmark(
				landmark, Gen2WorldState.is_crystal_profile(data)
			),
			visited
		)
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


## The Pokegear's other three cards, driven the way the service host drives them:
## a real world for the clock, the dial and the contact list, and the screen's own
## presses on top.
func _capture_card(
	data: GameData, card: StringName, output: String, steps: Array
) -> void:
	# The phone card is a list, so the preview's world carries a full one: ten
	# contacts from the first real one, `PHONECONTACT_NONE` being contact zero.
	var registered: Dictionary = {}
	for index: int in range(1, mini(
		data.world_phone_contact_count(), Gen2WorldState.PHONE_CONTACT_CAPACITY + 1
	)):
		registered[index] = true
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, NEW_BARK_GROUP, NEW_BARK_MAP, Vector2i.ZERO,
		Gen2WorldState.new({}, {}, {}, {}, 0, registered)
	)
	var host := Gen2PokegearScreen.new()
	root.add_child(host)
	if not host.open(
		data, card, [&"map", &"phone", &"radio"] as Array, _card_text(data, card),
		data.pokegear_text("ask_delete")
	):
		push_error("The cache holds no Pokegear cards.")
		quit(1)
		return
	host.tuned.connect(func(knob: int) -> void:
		world.tune_radio(knob)
		host.set_radio(knob, _station_name(world))
	)
	var clock: Dictionary = world.world_clock()
	host.set_clock(
		int(clock["day"]), int(clock["hour"]), int(clock["minute"])
	)
	host.set_radio(world.state.radio_knob(), _station_name(world))
	host.set_contacts(
		world.registered_phone_contacts(),
		Gen2WorldPhoneHost.map_has_phone_service(world.current_map)
	)
	for step: Array in steps:
		if String(step[0]) == "press":
			host.handle_button(int(step[1]))
	var error: Error = host.render().save_png(output)
	if error != OK:
		push_error("Could not write %s (error %d)" % [output, error])
		quit(1)
		return
	print("Wrote %s: %s card, %02d:%02d, knob %d %s, %d contacts" % [
		output, card, int(clock["hour"]), int(clock["minute"]),
		world.state.radio_knob(), _station_name(world).replace(" ", "_"),
		world.registered_phone_contacts().size(),
	])
	quit(0)


static func _card_text(data: GameData, card: StringName) -> String:
	if card == Gen2PokegearScreen.CARD_CLOCK:
		return data.pokegear_text("press_button")
	if card == Gen2PokegearScreen.CARD_PHONE:
		return data.pokegear_text("ask_who")
	return ""


static func _station_name(world: Gen2WorldAPI) -> String:
	var tuned: Dictionary = world.radio_station()
	return String(tuned.get("name", "")) if bool(tuned.get("ok", false)) else ""
