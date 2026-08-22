extends SceneTree

## Renders one imported map's expanded 4x4-tile blocks to a PNG.
##
##   Godot --headless --path . -s res://tools/preview_world.gd -- gold 1 1 /tmp/world.png
##
## A fifth `live` argument photographs the real screen on that map instead, with
## the sprites the engine draws over an object staged on it: an emote over the
## first visible object, the boulder dust, the grass rustle and the headbutt
## tree. That mode drives the screen's own path and needs a display, so it runs
## without `--headless`:
##
##   Godot --path . -s res://tools/preview_world.gd -- crystal 26 2 /tmp/out.png live [kind] [x y] [WxH] [touch]
##
## `kind` may carry the player's own cell as `<kind>@x,y`, which is what a kind
## reading the two numbers as something else needs: `battle_transition@5,7`.
##
## `WxH` is the window to photograph in, for the two shapes a phone has, and
## `touch` draws the on-screen controller with it, which is the only way to see
## how [Gen2GameFrame] splits a portrait screen:
##
##   ... live effects 4 4 430x932 touch
##
## `kind` is `effects` (the emote, the dust, the rustle and the headbutt tree),
## `unown_wall` (`DisplayUnownWords`' box, read off a Ruins of Alph chamber's
## own wall pattern from the cell below it: maps 23 to 26 of group 3 say HO-OH,
## ESCAPE, WATER and LIGHT, as `crystal 3 24 ... unown_wall 3 1`),
## `cut` (`OWCutAnimation`'s two halves and the jump shadow), `mart`
## (`BuyMenu`, talked open from the cell in front of a shop's counter, as
## `crystal 1 8 ... mart 3 3`), `pokepic`
## (`Script_pokepic`'s box over the map, holding Chikorita),
## `pet_actor` (a mod's world actor one cell in front of the player, pressed with
## A so it wears the heart `showemote` puts over a map object),
## `warp` (`MapSetupScript_Door` at its whitest: the player is walked up onto the
## warp tile named by the two numbers below it, and the picture is
## `FadeOutToWhite`'s last order, which is the frame the new map is loaded on:
## `crystal 24 7 ... warp 7 1` is the bedroom staircase),
## `script_fade` (one of the five fade specials over the map, as
## `crystal 24 4 ... script_fade 46 6`: the first number is the special and the
## second how many of its frames to spend before the picture),
## `door` (`.CheckWarp`'s carpet: the player is walked down onto an interior
## door's mat and photographed standing on it, which the step itself no longer
## warps: `crystal 24 6 ... door 6 5` is the front door of the player's house),
## `ledge` (the ledge hop at the top of its arc, walking south from the cell the
## two numbers name until one allows the hop: `crystal 24 4 ... ledge 5 4`),
## `map_name_sign` (`InitMapNameSign`'s window, raised by walking west off the
## map's edge onto its neighbour: `crystal 24 4 ... map_name_sign 1 8` crosses
## New Bark Town into Route 29),
## `yes_no` (`Script_yesorno`'s box, over the map's first script run to the
## choice it ends on: `crystal 26 3 ... yes_no 31 6` is Cherrygrove's guide),
## `name_rater` and `move_deleter` (`special NameRater` and `special
## MoveDeletion`, which no fixture cell reaches: the first number is how many
## presses into the routine to photograph, so 0 is the introduction, 2 its last
## page with the YES/NO up, and 4 the party list),
## `move_tutor` (`special MoveTutor`, driven the same way, except that it opens
## on `ChooseMonToLearnTMHM` rather than on a box: 0 is that list),
## `day_care` (the Day-Care's five specials, driven the same way: the first
## number is how many presses in and the second which routine, 0 the man,
## 1 the lady, 2 the man outside, 3 and 4 the two signs),
## `slot_machine` (`special SlotMachine`, which no fixture cell reaches: the
## first number is how many frames into the game to photograph and the second
## the bet, 1 to 3, plus 4 for the lucky machine),
## `tile_anim` (the map after the first number's worth of `AnimateTileset`
## frames, which is how the water, the flowers, the lava and the cave scroll are
## photographed at a chosen point in their cycle: `crystal 3 37 ... tile_anim 60`
## is Union Cave a second in),
## `card_flip` (`special CardFlip`, which no fixture cell reaches: the first
## number is how many frames into the game to photograph and the second the
## balance in hundreds of coins),
## `unown_puzzle` (`special UnownPuzzle`'s board, which no fixture cell reaches:
## the first number is how many frames in to photograph and the second which
## picture, 0 Kabuto, 1 Omanyte, 2 Aerodactyl and 3 Ho-Oh, or 4 to 7 for the
## same four solved; the empty cursor blinks off `hVBlankCounter`, so a frame
## with bit 4 clear has none on it),
## `visible_encounter` (a shiny of the map's own table standing on the eligible
## cell nearest the player, with the cartridge's sparkle over it: try
## `crystal 24 3 ... visible_encounter 4 9`), the name of any
## `preview_*` driver on the world screen without that prefix (`field_move` is
## `PartyMenu` with a taught CUT on it, `start_menu`, `capture`, `move_forget`
## and the rest; a `*_use` name is driven twice, since each call is one step of
## its own sequence), or one of
## [constant FIELD_ITEMS]' own names, which is the pack's USE on that item: the
## Itemfinder closes the pack over the world's answer, the Coin Case prints
## inside the pack, and the three in [constant FACE_UP_FIRST] each need their own
## map and the cell below their target. The two numbers are the cell
## the player stands on, which is how the grass a standing object is drawn behind
## is photographed.

const WINDOW_SIZE := Vector2i(1152, 648)
## What the live mode actually opens in, which a phone-shaped argument replaces.
var _window: Vector2i = WINDOW_SIZE
## Longer than a step onto a warp tile and the fade behind it, for the `warp`
## kind, which drives to a frame rather than spending a count.
const WARP_FRAME_CAP: int = 120
## How long one of the two routines' boxes may take to finish printing, which is
## a text speed rather than a count this file knows.
const MON_SPECIAL_FRAME_CAP: int = 600
## The Day-Care's five routines, in the order the second number picks them.
const DAY_CARE_ROLES: Array[StringName] = [
	&"man", &"lady", &"outside", &"mon1", &"mon2",
]


## `UpdateJumpPosition`'s highest `.y_offsets` entry, which is where the `ledge`
## kind photographs the hop.
const LEDGE_ARC_TOP: float = 12.0
## Hardware frames spent after the sprites are staged. Two puts the grass rustle
## on its first facing and the boulder dust on its second, so every one of them
## is up and none is on the frame it was spawned. Cut needs more: its tree stands
## for three frames before it splits, and its leaves open on top of each other.
## The `kind`s that are a pack USE rather than a staged sprite, and the item
## each one uses. Every one of them is driven through the pack's own key item
## pocket, so the picture is the screen's answer and not a staged state.
const FIELD_ITEMS: Dictionary = {
	&"field_item": Gen2WorldPack.ITEM_ITEMFINDER,
	&"bike": Gen2WorldPack.ITEM_BICYCLE,
	&"coin_case": Gen2WorldPack.ITEM_COIN_CASE,
	&"squirtbottle": Gen2WorldPack.ITEM_SQUIRTBOTTLE,
	&"card_key": Gen2WorldPack.ITEM_CARD_KEY,
	&"basement_key": Gen2WorldPack.ITEM_BASEMENT_KEY,
}

## The three whose effect reads what the player is facing. Each is photographed
## from the cell below its own target, so one press turns without moving: the
## tree, the slot and the door all block their own cell.
const FACE_UP_FIRST: Array[StringName] = [
	&"squirtbottle", &"card_key", &"basement_key",
]

## `ElmsLabScript`'s left ball, which is the first `pokepic` a new game shows.
const POKEPIC_SPECIES: int = 152

## How a `kind` names one of [Gen2WorldScreen]'s own screenshot drivers, so
## every `preview_*` on it is reachable from here rather than from nothing.
const SCREEN_DRIVER: String = "preview_%s"

## The clerk's own text box, which is the one press between `pokemart` and the
## welcome the buy screen opens on. One more reaches the list, two the quantity
## dial and three the yes/no.
const MART_PRESSES: int = 1

const STAGED_FRAMES: int = 2
const STAGED_FRAMES_CUT: int = 12

var _screen: Gen2WorldScreen = null
var _output_path: String = ""
var _frames: int = 0
var _kind: StringName = &"effects"
## The two numbers after the kind. Most kinds read them as the cell the player
## stands on; a few read them as their own arguments.
var _cell := Vector2i(-1, -1)
## `<kind>@x,y`: the cell for a kind whose own two numbers are not one, which is
## `battle_transition`. `battle_transition@5,7` photographs the animation with
## the player standing on that cell, which is how the grass over a sprite's legs
## is photographed with the transition already written over it.
var _kind_cell := Vector2i(-1, -1)


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 4:
		push_error("Usage: preview_world.gd -- <game> <group> <map> <output.png> [live]")
		quit(1)
		return

	var data: GameData = GameData.open(StringName(args[0]))
	if args.size() >= 5 and args[4] == "live":
		if data == null:
			push_error("No cache for %s. Import roms/%s.gbc first." % [args[0], args[0]])
			quit(1)
			return
		_output_path = args[3]
		var kind_arg: String = args[5] if args.size() >= 6 else "effects"
		if kind_arg.contains("@"):
			var halves: PackedStringArray = kind_arg.split("@")
			kind_arg = halves[0]
			var at: PackedStringArray = halves[1].split(",")
			if at.size() == 2:
				_kind_cell = Vector2i(int(at[0]), int(at[1]))
		_kind = StringName(kind_arg)
		if args.size() >= 9:
			var shape: PackedStringArray = args[8].split("x")
			if shape.size() == 2:
				_window = Vector2i(int(shape[0]), int(shape[1]))
		if args.size() >= 10 and args[9] == "touch":
			var options: Gen2Options = Gen2OptionsStore.current()
			options.touch_mode = Gen2Options.TOUCH_ALWAYS
			Gen2InputRuntime.instance().apply_options(options)
		_build_live(
			data, int(args[1]), int(args[2]),
			Vector2i(int(args[6]), int(args[7])) if args.size() >= 8 else Vector2i(-1, -1),
		)
		return
	var map: Gen2WorldMap = data.world_map(int(args[1]), int(args[2])) if data != null else null
	var tileset: Gen2WorldTileset = data.world_tileset(map.tileset) if map != null else null
	if data == null or map == null or tileset == null:
		push_error("The requested imported map is not available.")
		quit(1)
		return

	var image: Image = _render(data, map, tileset)
	var error: int = image.save_png(args[3])
	if error != OK:
		push_error("Could not write %s (error %d)." % [args[3], error])
		quit(1)
		return

	print("Wrote %s (%dx%d), tileset %d, %d warps, %d objects." % [
		args[3], image.get_width(), image.get_height(), map.tileset,
		(map.events.get("warps", []) as Array).size(),
		(map.events.get("objects", []) as Array).size(),
	])
	quit(0)


## The production screen on a real map, with every effect sprite running at
## once. Each is started through the same call the game makes, so what is
## photographed is the renderer's own path rather than a drawing of it.
func _build_live(data: GameData, group: int, number: int, cell: Vector2i) -> void:
	DisplayServer.window_set_size(_window)
	root.set_content_scale_size(_window)
	root.size = _window
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_screen = packed.instantiate() as Gen2WorldScreen
	_screen.map_group = group
	_screen.map_number = number
	_cell = cell
	## The transition reads them as a frame count and a branch rather than as a
	## cell, so the player is left where the map puts them.
	if _kind_cell.x >= 0:
		_screen.start_cell = _kind_cell
	elif cell.x >= 0 and _kind not in [
		&"battle_transition", &"level_evolution", &"egg_hatch", &"name_rater",
		&"move_deleter", &"move_tutor", &"day_care", &"unown_puzzle", &"slot_machine",
		&"card_flip", &"tile_anim",
	]:
		_screen.start_cell = cell
	## Pinned so two captures of the same map are the same picture: the seed the
	## screen resolves is what a wandering NPC's own generator is built from.
	_screen.encounter_seed = 1
	_screen.set_data(data)
	root.add_child(_screen)
	current_scene = _screen
	## The screen counts hardware frames off wall-clock delta, so a capture that
	## let it run would photograph a different frame of each animation every
	## time. It owns none of them here: the staged frames below are spent by
	## hand.
	_screen.set_process(false)


## Spends whatever one of the two routines' boxes still owes, plus the frame
## `advance_frame` reads it on: `PrintText` returning is what opens a `YesNoBox`.
func _settle_mon_special(host_property: String) -> void:
	for _frame: int in MON_SPECIAL_FRAME_CAP:
		var routine: Control = _screen.get(host_property)
		## The routine's last box is handed back to the map, which reveals it on
		## its own clock, so a closed host still owes the frames its ending text
		## is printing. Photographing on the frame the host went away shows an
		## empty box.
		var box: Gen2TextBox = routine.get("_text_box") if routine != null \
			else _screen.get("_text_box") as Gen2TextBox
		if box == null or not box.is_revealing():
			break
		_screen.advance_frame()
	_screen.advance_frame()


func _process(_delta: float) -> bool:
	if _screen == null:
		return false
	_frames += 1
	## Again, and after the screen is in the tree: a node whose script defines
	## `_process` has its processing turned back on when it is made ready, so the
	## call in [method _build_live] alone leaves the screen spending frames of
	## its own beside the ones staged below.
	_screen.set_process(false)
	if _frames == 2:
		if _kind == &"unown_wall":
			## The chamber's own `bg_event ..., BGEVENT_UP`: face the wall from
			## the cell below it and read it, which is the only way in.
			_screen.move_up()
			_screen.interact()
			## `writetext` is one page: the first press finishes the reveal the
			## text speed is still spending, and the second ends the page, which
			## is what runs `special DisplayUnownWords` and puts the box up.
			_screen.press_button(Gen2Button.A)
			_screen.press_button(Gen2Button.A)
		elif _kind == &"battle_transition":
			## `DoBattleTransition` over the map it runs on. The first of the two
			## numbers is how many frames into it to photograph rather than a
			## cell, since a transition is two hundred of them and every one is
			## a different picture; the second is 1 for a trainer's, which is the
			## branch that draws the Poke Ball and floods the map.
			_screen.preview_battle_transition(_cell.x, _cell.y != 0)
		elif _kind == &"script_fade":
			## One of the five fade specials over the map it runs on. The first
			## number is the special (46 `FadeOutToWhite`, 47 `BattleTowerFade`,
			## 48 `FadeOutToBlack`, 49 `FadeInFromWhite`, 50 `FadeInFromBlack`)
			## and the second how many of its frames to spend before the
			## picture, since each of the four rows is a different screen.
			_screen.preview_script_fade(maxi(_cell.x, 0))
			for _frame: int in maxi(_cell.y, 0):
				_screen.advance_frame()
		elif _kind == &"level_evolution":
			## `EvolveAfterBattle`'s own screen, which is a few hundred frames of
			## picture. The first number is how far into it to photograph rather
			## than a cell, the way `battle_transition`'s is; the box is pressed
			## past on the frames it is waiting on, since neither `PrintText` nor
			## `DelayFrames` shortens for a screenshot.
			_screen.preview_level_evolution()
			for _frame: int in maxi(_cell.x, 0):
				_screen.advance_frame()
				var evolving: Gen2EvolutionScreen = _screen.get("_evolution_host")
				if evolving == null:
					break
				if evolving.awaiting_press():
					_screen.press_button(Gen2Button.A)
		elif _kind == &"egg_hatch":
			## `OverworldHatchEgg`, driven the same way and for the same reason:
			## the sequence is five hundred frames of picture, so the first
			## number is how far into it to photograph and the second is the
			## species inside the egg, 0 for the first the cache holds.
			_screen.preview_egg_hatch(maxi(_cell.y, 0))
			for _frame: int in maxi(_cell.x, 0):
				_screen.advance_frame()
				var hatching: Gen2EggHatchScreen = _screen.get("_hatch_host")
				if hatching == null:
					break
				if hatching.awaiting_press():
					_screen.press_button(Gen2Button.A)
		elif _kind == &"unown_puzzle":
			## `special UnownPuzzle`, which no fixture cell reaches. The first
			## number is how many frames into the board to photograph and the
			## second which picture: 0 Kabuto, 1 Omanyte, 2 Aerodactyl, 3 Ho-Oh.
			## The empty cursor blinks off `hVBlankCounter`, so a frame with bit
			## 4 clear photographs a board with no cursor on it.
			## 4 to 7 are the same four pictures with the board walked into
			## `.SolvedPuzzleConfiguration` through the screen's own presses,
			## which is the only way to photograph the assembled picture.
			_screen.preview_unown_puzzle(
				maxi(_cell.y, 0) % RomLayout.UNOWN_PUZZLE_PICTURES.size(),
				maxi(_cell.y, 0) >= RomLayout.UNOWN_PUZZLE_PICTURES.size()
			)
			for _frame: int in maxi(_cell.x, 0):
				if _screen.get("_unown_puzzle_host") == null:
					break
				_screen.advance_frame()
		elif _kind == &"slot_machine":
			## `special SlotMachine`, which no fixture cell reaches either. The
			## first number is how many frames into the game to photograph and
			## the second is the bet, 1 to 3, plus 4 for the lucky machine the
			## Game Corner's own `random 6` picks one time in six.
			var slots_bet: int = maxi(_cell.y, 0) % 4
			_screen.preview_slot_machine(
				100, maxi(_cell.y, 0) >= 4, maxi(slots_bet, 1), maxi(_cell.x, 0)
			)
		elif _kind == &"tile_anim":
			## `AnimateTileset` runs once a hardware frame, so any frame of a
			## map's own water, flowers, lava or cave scroll is reachable by
			## spending them: the first number is how many, and the cell goes in
			## `tile_anim@x,y` as usual.
			for _spent: int in maxi(_cell.x, 0):
				_screen.advance_frame()
		elif _kind == &"card_flip":
			## `special CardFlip`, which no fixture cell reaches either. The
			## first number is how many frames into the game to photograph and
			## the second the balance in hundreds of coins, 0 meaning 100.
			_screen.preview_card_flip(
				maxi(_cell.y, 0) * 100 if _cell.y > 0 else 100, maxi(_cell.x, 0)
			)
		elif _kind == &"day_care":
			## The Day-Care's five, driven the way the two above are. The first
			## number is how many presses into the routine to photograph and the
			## second is which routine: 0 the man, 1 the lady, 2 the man outside,
			## 3 and 4 the two signs.
			_screen.preview_day_care(DAY_CARE_ROLES[clampi(
				_cell.y, 0, DAY_CARE_ROLES.size() - 1
			)])
			_settle_mon_special("_day_care_host")
			for _press: int in maxi(_cell.x, 0):
				if _screen.get("_day_care_host") == null:
					break
				_screen.press_button(Gen2Button.A)
				_settle_mon_special("_day_care_host")
		elif _kind in [&"name_rater", &"move_deleter", &"move_tutor"]:
			## `special NameRater` and `special MoveDeletion`, neither of which
			## any fixture cell reaches. The first number is how many presses
			## into the routine to photograph: 2 is the introduction's last page
			## with its YES/NO up, 4 the party list, and so on. Presses are spent
			## only once the box owes no frames, since nothing shortens a
			## printing text.
			match _kind:
				&"name_rater":
					_screen.preview_name_rater()
				&"move_tutor":
					_screen.preview_move_tutor()
				_:
					_screen.preview_move_deleter()
			var host_property: String = "_%s_host" % _kind
			_settle_mon_special(host_property)
			for _press: int in maxi(_cell.x, 0):
				if _screen.get(host_property) == null:
					break
				_screen.press_button(Gen2Button.A)
				_settle_mon_special(host_property)
		elif _kind == &"yes_no":
			## `Script_yesorno`'s own box: the NPC beside the player is talked
			## to and each page answered until the choice the script ends on is
			## up, which is what photographs `YesNoMenuHeader.MenuData`'s
			## cursor. `crystal 26 3 ... yes_no 31 6` is Cherrygrove's guide.
			_screen.press_button(Gen2Button.RIGHT)
			_screen.interact()
			for _press: int in WARP_FRAME_CAP:
				if StringName(_screen._world.pending_script_input().get(
					"command", &"")) == &"yesorno":
					break
				_screen.press_button(Gen2Button.A)
				for _frame: int in 20:
					_screen.advance_frame()
		elif _kind == &"mart":
			## The clerk behind the counter, talked to from the cell in front of
			## him: his `pokemart` is what opens `BuyMenu`, so the shop is
			## reached the way a player reaches it. The presses are the dialog's
			## own, the welcome box first and then the list.
			_screen.press_button(Gen2Button.LEFT)
			_screen.interact()
			for _press: int in MART_PRESSES:
				_screen.press_button(Gen2Button.A)
		elif _kind == &"warp":
			## `MapSetupScript_Door` at its whitest: the step onto the warp tile
			## and then `FadeOutToWhite`'s last order, which is the frame the map
			## is loaded on.
			for _frame: int in WARP_FRAME_CAP:
				## The first press turns, the second steps: the player is facing
				## the room rather than the stairs when the map opens.
				_screen.move_up()
				_screen.advance_frame()
				var fade: Dictionary = _screen.map_fade()
				if StringName(fade.get("stage", &"")) == &"out" \
					and int(fade.get("step", 0)) == Gen2WorldPalette.FADE_OUT_ORDERS.size() - 1:
					break
		elif _kind == &"door":
			## `CheckDirectionalWarp`'s carpet: the step onto an interior door's
			## mat lands and takes no warp, which is what this photographs. The
			## press after it is `.CheckWarp`, and that is the one that warps.
			for _frame: int in WARP_FRAME_CAP:
				_screen.move_down()
				_screen.advance_frame()
				if Gen2WorldCollision.is_directional_warp(
					int(_screen.world_snapshot().get("collision", -1))
				):
					## player_cell commits when the step starts, so the frames
					## the player is still walking are spent before the picture.
					_screen.advance_frames(
						Gen2WorldAPI.passes_in_frames(Gen2WorldAPI.STEP_PASSES_WALK)
					)
					break
		elif _kind == &"ledge":
			## `StepFunction_PlayerJump` at the top of its arc: the player is
			## walked south until a cell allows the hop below it, and the picture
			## is the frame `UpdateJumpPosition` draws highest
			## (`crystal 24 4 ... ledge 5 4`).
			for _frame: int in WARP_FRAME_CAP:
				_screen.move_down()
				_screen.advance_frame()
				if _screen.player_height_offset_pixels() >= LEDGE_ARC_TOP:
					break
		elif _kind == &"map_name_sign":
			## `MapSetupScript_Connection`'s `InitMapNameSign`: walked west off
			## New Bark Town's edge onto Route 29, photographed while the sign
			## the crossing raised is still up (`crystal 24 4 ... map_name_sign
			## 0 6`). The camera and the tile animation both keep running behind
			## it, which is the whole point of the row.
			for _frame: int in WARP_FRAME_CAP:
				_screen.move_left()
				_screen.advance_frame()
				if _screen.map_name_sign_passes() > 0 \
					and _screen.map_name_sign_passes() < Gen2WorldAPI.MAP_NAME_SIGN_PASSES:
					break
		elif _kind == &"pokepic":
			_screen.preview_pokepic(POKEPIC_SPECIES)
		elif FIELD_ITEMS.has(_kind):
			if _kind in FACE_UP_FIRST:
				_screen.move_up()
			_screen.preview_field_item(int(FIELD_ITEMS[_kind]))
		elif _screen.has_method(SCREEN_DRIVER % _kind):
			## The screen's own `preview_*` drivers, by their name without the
			## prefix. A `*_use` driver is one step per call, so it is called
			## twice: the first opens the menu and the second answers it.
			_screen.call(SCREEN_DRIVER % _kind)
			if String(_kind).ends_with("_use"):
				_screen.call(SCREEN_DRIVER % _kind)
		else:
			_screen.preview_effect_sprites(_kind)
		if _kind not in [
			&"warp", &"door", &"map_name_sign", &"ledge", &"heal_machine",
			&"battle_transition", &"level_evolution", &"egg_hatch", &"name_rater",
			&"move_deleter", &"move_tutor", &"day_care",
		]:
			## Those kinds drove themselves to the frame they want; every other
			## kind stages a sprite and then spends the frames it needs.
			for _frame: int in (STAGED_FRAMES_CUT if _kind == &"cut" else STAGED_FRAMES):
				_screen.advance_frame()
	if _frames < 18:
		return false
	RenderingServer.force_draw()
	var image: Image = root.get_texture().get_image()
	var error: Error = image.save_png(_output_path)
	if error != OK:
		push_error("Could not write %s (error %d)" % [_output_path, error])
		quit(1)
		return true
	print("Wrote %s (%dx%d)" % [_output_path, image.get_width(), image.get_height()])
	quit(0)
	return true


func _render(data: GameData, map: Gen2WorldMap, tileset: Gen2WorldTileset) -> Image:
	var width: int = map.width_blocks * RomLayout.MAP_BLOCK_TILE_WIDTH * Gen2Tiles.TILE_WIDTH
	var height: int = map.height_blocks * RomLayout.MAP_BLOCK_TILE_WIDTH * Gen2Tiles.TILE_HEIGHT
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var pixels: PackedByteArray = data.world_tileset_indices(tileset.number)
	var atlas_width: int = tileset.tile_count * Gen2Tiles.TILE_WIDTH
	var palettes: Array = Gen2WorldPalette.tile_palettes(data, map, tileset)

	for tile_y: int in map.height_blocks * RomLayout.MAP_BLOCK_TILE_WIDTH:
		for tile_x: int in map.width_blocks * RomLayout.MAP_BLOCK_TILE_WIDTH:
			var block: int = map.block_at(tile_x >> 2, tile_y >> 2)
			var tile: int = tileset.tile_index(block, (tile_y & 3) * 4 + (tile_x & 3))
			for pixel_y: int in Gen2Tiles.TILE_HEIGHT:
				for pixel_x: int in Gen2Tiles.TILE_WIDTH:
					var color_index: int = 0
					var palette := PackedColorArray()
					if tile < tileset.tile_count:
						color_index = pixels[pixel_y * atlas_width + tile * 8 + pixel_x]
						palette = palettes[tile]
					var color: Color = palette[color_index] if color_index < palette.size() else Color.MAGENTA
					image.set_pixel(
						tile_x * 8 + pixel_x, tile_y * 8 + pixel_y,
						color
					)

	# Mark event coordinates in a restrained red so the screenshot shows that
	# geometry and event data come from the same imported map record.
	for event: Dictionary in map.events.get("warps", []):
		_draw_marker(image, int(event["x"]), int(event["y"]), Color("#d34a5a"))
	for event: Dictionary in map.events.get("objects", []):
		var x: int = int(event["x"])
		var y: int = int(event["y"])
		if x >= 0 and y >= 0 and x < map.collision_width and y < map.collision_height:
			_draw_marker(image, x, y, Color("#3e6ed8"))
	return image


func _draw_marker(image: Image, cell_x: int, cell_y: int, color: Color) -> void:
	var pixel_x: int = cell_x * 16 + 4
	var pixel_y: int = cell_y * 16 + 4
	for y: int in 8:
		for x: int in 8:
			if pixel_x + x < image.get_width() and pixel_y + y < image.get_height():
				image.set_pixel(pixel_x + x, pixel_y + y, color)
