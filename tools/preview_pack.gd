extends SceneTree

## Captures the pack against a real imported cache.
##
##   Godot --headless --path . -s res://tools/preview_pack.gd -- \
##       crystal /tmp/pack.png [items|balls|key|tmhm|use|give] [presses] [female]
##
## The world behind it is a new game holding enough of each pocket to fill the
## five visible rows and scroll past them, with a development party behind it so
## `use` and `give` reach `.Party`'s own list. Those two are the party menu
## `GiveItem` and every `.Party` item effect open, so what they photograph is
## [Gen2PartyMenuPage] with the prompt that entrance writes. [presses] is a `u,d,l,r,a,b` list
## driven into the real screen before the shot, so the picture is what the
## cartridge's own listing would show after those buttons.
##
## Headless: the page composes into an [Image] rather than through a viewport,
## so no window and no settle are needed.

const NEW_BARK_GROUP: int = 24
const NEW_BARK_MAP: int = 7

const BUTTONS: Dictionary = {
	"u": Gen2Button.UP, "d": Gen2Button.DOWN,
	"l": Gen2Button.LEFT, "r": Gen2Button.RIGHT,
	"a": Gen2Button.A, "b": Gen2Button.B,
}

## Which presses each pocket is reached by, since the pack opens on Items and
## the cartridge cycles left and right through the four.
const ROUTES: Dictionary = {
	"items": "",
	"balls": "r",
	"key": "r,r",
	"tmhm": "l",
	## The first Items row is a healing item, so its submenu is USE / GIVE / TOSS
	## and both rows reach `.Party`'s own list.
	"use": "a,a",
	"give": "a,d,a",
}

## What the preview's world is carrying: enough items for the listing to scroll,
## a ball, two key items and two TMs, by their own item numbers.
const ITEMS: Dictionary = {
	1: 1, 4: 12, 5: 30,
	17: 3, 18: 2, 19: 1, 20: 5, 21: 9, 22: 4,
	7: 1, 70: 1,
	0xBF: 1, 0xF3: 1,
}


## The screen builds its panel in `_ready`, which does not run until the tree has
## processed a frame, so the shot is taken from [method _process] rather than
## from `_initialize`.
func _process(_delta: float) -> bool:
	_capture()
	return true


func _capture() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error(
			"Usage: preview_pack.gd -- <game> <output.png> "
			+ "[items|balls|key|tmhm] [presses] [female]"
		)
		quit(1)
		return
	var data: GameData = GameData.open(StringName(args[0]))
	if data == null:
		push_error("No cache for %s. Import roms/%s.gbc first." % [args[0], args[0]])
		quit(1)
		return

	var pocket: String = args[2] if args.size() > 2 else "items"
	var tokens: String = String(ROUTES.get(pocket, ""))
	if args.size() > 3 and not args[3].is_empty():
		tokens = "%s,%s" % [tokens, args[3]] if not tokens.is_empty() else args[3]

	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, NEW_BARK_GROUP, NEW_BARK_MAP, Vector2i.ZERO,
		Gen2WorldState.new({}, {}, ITEMS, {})
	)
	if args.size() > 4 and args[4] == "female":
		world.set_player_gender(true)

	var host := Gen2StartMenuScreen.new()
	root.add_child(host)
	## No slot on disk, so nothing this photographs is written anywhere.
	var save: Gen2SaveData = Gen2SaveStore.create_development_save(data, 0)
	if save != null:
		save.world = world.snapshot()
		host.set_party_context(save, false)
	if not host.open(world, data, func() -> Dictionary: return {"ok": true}):
		push_error("The %s cache holds no start menu." % args[0])
		quit(1)
		return
	# The pack is opened by walking the start menu's own list to its PACK row and
	# pressing A, rather than by naming the mode: a preview that sets its own
	# state photographs a screen no player can reach.
	var menu: Gen2WorldStartMenu = host.get("_menu")
	var rows: Array = menu.items()
	for index: int in rows.size():
		if StringName((rows[index] as Dictionary).get("kind", &"")) \
			== Gen2WorldStartMenu.ITEM_PACK:
			for _step: int in index - menu.cursor:
				host.handle_button(Gen2Button.DOWN)
			break
	host.handle_button(Gen2Button.A)
	for token: String in tokens.split(",", false):
		var key: String = token.strip_edges().to_lower()
		if BUTTONS.has(key):
			host.handle_button(int(BUTTONS[key]))

	## Whichever cartridge screen the presses landed on, so a route that opens
	## `.Party`'s list photographs that rather than the pocket behind it.
	var image: Image = host.call("_hardware_image") as Image
	if image == null:
		push_error("Mode %d has no cartridge screen to photograph." % int(host.get("_mode")))
		quit(1)
		return
	var error: Error = image.save_png(args[1])
	if error != OK:
		push_error("Could not write %s (error %d)" % [args[1], error])
		quit(1)
		return
	print("Wrote %s: %s pocket, cursor %d, mode %d" % [
		args[1], String(host.call("_current_pocket").get("name", "?")),
		int(host.get("_pack_cursor")), int(host.get("_mode")),
	])
	quit(0)
