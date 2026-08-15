extends SceneTree

## Captures the Pokedex against a real imported cache.
##
##   Godot --headless --path . -s res://tools/preview_pokedex.gd -- \
##       crystal /tmp/dex.png [list|entry|option|search|results|unown] [presses]
##
## The world behind it is a new game with every species seen and every second one
## caught, which is what puts a full listing, both row states and a real entry on
## screen at once. [presses] is a
## `u,d,l,r,a,b,sel,start` list driven in before the shot, and `f<n>` spends n
## hardware frames, which is how the arrow is caught blinking either way.
##
## Headless: the screen composes into an [Image] rather than through a viewport,
## so no window and no settle are needed.

const NEW_BARK_GROUP: int = 24
const NEW_BARK_MAP: int = 7
## How far down the dex the preview's save has been filled.
const SEEN: int = 251

const BUTTONS: Dictionary = {
	"u": Gen2Button.UP, "d": Gen2Button.DOWN,
	"l": Gen2Button.LEFT, "r": Gen2Button.RIGHT,
	"a": Gen2Button.A, "b": Gen2Button.B,
	"sel": Gen2Button.SELECT, "start": Gen2Button.START,
}

## Which presses each named screen is reached by, so a caller naming one does not
## have to know the walk.
const ROUTES: Dictionary = {
	"list": "",
	"entry": "a",
	"option": "sel",
	"search": "start",
	"results": "start,d,d,a",
	"unown": "sel,d,d,d,a",
}


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error(
			"Usage: preview_pokedex.gd -- <game> <output.png> "
			+ "[list|entry|option|search|results|unown] [presses]"
		)
		quit(1)
		return
	var data: GameData = GameData.open(StringName(args[0]))
	if data == null:
		push_error("No cache for %s. Import roms/%s.gbc first." % [args[0], args[0]])
		quit(1)
		return

	var screen: String = args[2] if args.size() > 2 else "list"
	var tokens: String = String(ROUTES.get(screen, ""))
	if args.size() > 3:
		tokens = "%s,%s" % [tokens, args[3]] if not tokens.is_empty() else args[3]

	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, NEW_BARK_GROUP, NEW_BARK_MAP, Vector2i.ZERO, _state()
	)
	var host := Gen2PokedexScreen.new()
	root.add_child(host)
	if not host.open(data, world):
		push_error("The %s cache holds no Pokedex graphics." % args[0])
		quit(1)
		return
	# The screen counts hardware frames off wall clock in `_process`; the preview
	# spends them by hand so the arrow is where the presses left it.
	host.set_process(false)
	for token: String in tokens.split(",", false):
		var key: String = token.strip_edges().to_lower()
		if key.begins_with("f"):
			for _frame: int in maxi(1, int(key.substr(1))):
				host.advance_frame()
		elif BUTTONS.has(key):
			host.handle_button(int(BUTTONS[key]))

	var error: Error = host.render().save_png(args[1])
	if error != OK:
		push_error("Could not write %s (error %d)" % [args[1], error])
		quit(1)
		return
	print("Wrote %s: %s, mode %d, cursor on %s" % [
		args[1], screen, host.current_mode(),
		data.species(host.selected_species()).get("name", "?"),
	])
	quit(0)


## A world whose dex is filled far enough to draw every row state: seen up to
## [constant SEEN], caught on every second one, and the Unown dex unlocked so the
## OPTION screen offers its fourth row.
static func _state() -> Gen2WorldState:
	var state := Gen2WorldState.new({}, {}, {}, {})
	for species: int in range(1, SEEN + 1):
		state.set_species_seen(species)
		if species % 2 == 0:
			state.set_species_caught(species)
	state.set_engine_flag(Gen2WorldState.ENGINE_UNOWN_DEX)
	for form: int in range(1, 8):
		state.update_unown_dex(form)
	return state
