extends SceneTree

## Captures the two menus a battle switches through, against a real imported
## cache: `OfferSwitch`'s yes/no box over the field, and the party list
## `PickSwitchMonInBattle` opens behind it.
##
##   Godot --path . -s res://tools/preview_battle_switch.gd -- crystal /tmp/s.png [stage] [presses]
##
## [stage] is `offer`, the default, or `pick`; [presses] is a `u,d,l,r,a,b` list
## driven into the menu before the shot, so a cursor row or a refusal can be
## photographed. The battle is a real trainer's party out of the cache with the
## player on a bench of three, since a switch needs somebody to switch to.

const WINDOW_SIZE := Vector2i(1152, 648)
## Enough frames for the scene to lay out and for the hardware viewport to hold
## what the menus were driven to; the intro and the turn are settled by hand
## below rather than by waiting. A shorter run photographs the composite as it
## was a few frames before the presses.
const SETTLE_FRAMES: int = 30

## Falkner, and three of the player's own, all at a level where nothing faints
## before the question is asked.
const TRAINER_CLASS: int = 1
const PLAYER_SPECIES: Array[int] = [155, 152, 158]
const PLAYER_LEVEL: int = 30

var _screen: Gen2BattleScreen = null
var _output_path: String = ""
var _stage: String = "offer"
var _presses: PackedStringArray = PackedStringArray()
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Usage: preview_battle_switch.gd -- <game> <output.png> [stage] [presses]")
		quit(1)
		return
	_output_path = args[1]
	_stage = args[2] if args.size() > 2 else "offer"
	if args.size() > 3:
		_presses = args[3].split(",", false)

	var data: GameData = GameData.open(StringName(args[0]))
	if data == null:
		push_error("No cache for %s. Import roms/%s.gbc first." % [args[0], args[0]])
		quit(1)
		return

	root.set_content_scale_size(WINDOW_SIZE)
	root.size = WINDOW_SIZE
	var packed: PackedScene = load("res://game/battle/battle_screen.tscn")
	_screen = packed.instantiate() as Gen2BattleScreen
	_screen.set_data(data)
	root.add_child(_screen)
	current_scene = _screen


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		_open()
	if _frames < SETTLE_FRAMES:
		return false

	var image: Image = root.get_texture().get_image()
	var error: Error = image.save_png(_output_path)
	if error != OK:
		push_error("Could not write %s (error %d)" % [_output_path, error])
		quit(1)
		return true
	print("Wrote %s, stage %s" % [_output_path, _screen.battle_snapshot()["switch_stage"]])
	quit(0)
	return true


## The trainer's second Pokémon coming in, which is what `OfferSwitch` asks
## about. SHIFT is forced on rather than read out of the options file, since the
## question is the thing being photographed.
func _open() -> void:
	var data: GameData = _screen.get("_data")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3

	var members: Array = []
	for species: int in PLAYER_SPECIES:
		members.append(Gen2BattleMon.create(data, species, PLAYER_LEVEL, [33]))
	var enemy: Gen2Party = Gen2TrainerParty.build(data, TRAINER_CLASS, 0)
	if enemy == null or enemy.size() < 2:
		push_error("Trainer class %d has no bench to switch from" % TRAINER_CLASS)
		quit(1)
		return

	_screen.show_trainer(TRAINER_CLASS, 0, PLAYER_SPECIES[0], PLAYER_LEVEL)
	var battle: Gen2Battle = Gen2Battle.create_parties(
		data, Gen2Party.create(members), enemy, rng, true
	)
	battle.battle_style_set = false
	_screen.set("_battle", battle)
	_screen.set("_pending", battle.take_actions(
		Gen2Battle.use_move(0), Gen2Battle.switch_to(1)
	))

	_drain()
	if _stage == "pick":
		_read_question()
		_screen._handle_button(Gen2Button.A)
	for press: String in _presses:
		_screen._handle_button(_button(press))
	if _stage == "offer":
		_read_question()
	## A refusal is a line the box is still revealing, and the capture does not
	## wait on real time.
	_screen.finish()


## Every queued event shown and pressed past, which is what reaches the question.
func _drain() -> void:
	for _press: int in 60:
		if String(_screen.battle_snapshot()["switch_stage"]) != "":
			return
		_settle()
		_screen.finish()
		_screen.advance()


func _settle() -> void:
	var guard: int = 4000
	while _screen.frames_running() and guard > 0:
		_screen.advance_frame()
		guard -= 1


## Reads the question to its last page, which is where the yes/no box appears.
func _read_question() -> void:
	var box: Gen2TextBox = _screen.get("_box")
	while box != null and (box.is_revealing() or box.has_pages_left()):
		box.finish()
		if box.has_pages_left():
			box.advance()
	_screen._refresh_menu_layer()


func _button(name: String) -> int:
	match name.strip_edges().to_lower():
		"u": return Gen2Button.UP
		"d": return Gen2Button.DOWN
		"l": return Gen2Button.LEFT
		"r": return Gen2Button.RIGHT
		"b": return Gen2Button.B
		_: return Gen2Button.A
