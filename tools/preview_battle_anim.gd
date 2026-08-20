extends SceneTree

## Captures a battle animation mid-flight against a real imported cache, which
## `tools/screenshot.gd` cannot drive: an animation needs a turn taken, an event
## queue walked to the animation it wants, and then a counted number of hardware
## frames spent inside it.
##
##   Godot --path . -s res://tools/preview_battle_anim.gd -- \
##       <game> <output.png> <move> <side> <frames> [scene_off]
##
## `<move>` is a move number, given to both Pokemon so either side's animation
## can be photographed; `<side>` is 0 for the player's own and 1 for the
## enemy's; `<frames>` is how many frames into the animation to stop.
##
## `<move> 0` photographs the entrance instead, which is `BattleStartMessage` and
## the opening of `DoBattle` rather than a turn: a wild one, or a trainer's with
## `<side>` at 1, and `<frames>` counted from the frame the pics stop sliding.
## `scene_off` clears the OPTION menu's battle-scene row first, which is what
## `CheckBattleScene` reads, and the capture should then show the field
## untouched.

const WINDOW_SIZE := Vector2i(1152, 648)
## Enough frames for the scene to lay out before anything is driven, and enough
## after it for the viewport to draw what was driven.
const SETTLE_FRAMES: int = 4
const DRAW_FRAMES: int = 3
## A runaway guard on the event pump: no turn produces anywhere near this many
## steps, and a driver that never reaches its animation should say so.
const MAX_STEPS: int = 4096

var _screen: Gen2BattleScreen = null
var _output_path: String = ""
var _move: int = 1
var _side_is_enemy: bool = false
var _frames_in: int = 0
var _scene_off: bool = false
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 5:
		push_error(
			"Usage: preview_battle_anim.gd -- <game> <output.png> <move> <side> <frames> [scene_off]"
		)
		quit(1)
		return
	_output_path = args[1]
	_move = int(args[2])
	_side_is_enemy = int(args[3]) != 0
	_frames_in = int(args[4])
	_scene_off = args.size() > 5 and args[5] == "scene_off"

	var data: GameData = GameData.open(StringName(args[0]))
	if data == null:
		push_error("No cache for %s. Import roms/%s.gbc first." % [args[0], args[0]])
		quit(1)
		return

	var options: Gen2Options = Gen2OptionsStore.current()
	options.battle_scene = not _scene_off
	Gen2OptionsStore.save(options)

	root.set_content_scale_size(WINDOW_SIZE)
	root.size = WINDOW_SIZE
	var packed: PackedScene = load("res://game/battle/battle_screen.tscn")
	_screen = packed.instantiate() as Gen2BattleScreen
	_screen.set_data(data)
	root.add_child(_screen)
	current_scene = _screen
	# The screen counts hardware frames off `_process` deltas. The frames spent
	# here are counted rather than timed, so nothing drifts while the viewport
	# catches up with what was driven.
	_screen.set_process(false)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	if _frames == SETTLE_FRAMES:
		if not _drive():
			quit(1)
			return true
		return false
	if _frames < SETTLE_FRAMES + DRAW_FRAMES:
		return false

	var image: Image = root.get_texture().get_image()
	var error: Error = image.save_png(_output_path)
	if error != OK:
		push_error("Could not write %s (error %d)" % [_output_path, error])
		quit(1)
		return true
	print("Wrote %s (%dx%d) %s" % [
		_output_path, image.get_width(), image.get_height(),
		JSON.stringify(_screen.animation_snapshot()),
	])
	quit(0)
	return true


## The entrance, stopped [member _frames_in] frames after the slide. `<side>` 1
## opens a real trainer's fight instead of a wild one, which is the branch with
## `SFX_SHINE`, a line of its own and two balls thrown rather than one.
func _drive_entrance() -> bool:
	if _side_is_enemy:
		_screen.show_trainer(1, 0)
	else:
		_screen.show_matchup(16, 155, 20, 20)
	while _screen.intro_running():
		_screen.advance_frame()
	for _frame: int in _frames_in:
		if not _screen.frames_running() and _screen.entrance_running():
			_screen.finish()
			_screen.advance()
			continue
		_screen.advance_frame()
	return true


## Everything `DoBattle` spends before its first menu, so a turn driven after
## this is a turn rather than the ball still being thrown.
func _settle_entrance() -> void:
	for _step: int in MAX_STEPS:
		if not _screen.frames_running() and not _screen.entrance_running():
			return
		if _screen._audio_player != null:
			_screen._audio_player.stop_all()
		if _screen.frames_running():
			_screen.advance_frame()
			continue
		_screen.finish()
		_screen.advance()


## Settles the intro, teaches both Pokemon the move, takes the turn and walks the
## event queue to the first animation on the requested side.
func _drive() -> bool:
	if _move == 0:
		return _drive_entrance()
	_screen.show_matchup(16, 155, 20, 20)
	while _screen.intro_running():
		_screen.advance_frame()
	_settle_entrance()

	var battle: Gen2Battle = _screen._battle
	for side: int in [Gen2Battle.PLAYER, Gen2Battle.ENEMY]:
		var mon: Gen2BattleMon = battle.mon(side)
		mon.moves[0] = _move
		mon.pp[0] = 40
	_screen.take_turn_with(0, 0)

	for _step: int in MAX_STEPS:
		var snapshot: Dictionary = _screen.animation_snapshot()
		if bool(snapshot["running"]) \
				and bool(snapshot["enemy_turn"]) == _side_is_enemy:
			for _frame: int in _frames_in:
				_screen.advance_frame()
			_screen.finish()
			return true
		# `_PlayBattleAnim` ends on `WaitSFX`, which waits on real time while this
		# driver counts frames as fast as it can. Nothing is being listened to, so
		# the effect player is emptied rather than waited for.
		if _screen._audio_player != null:
			_screen._audio_player.stop_all()
		if _screen.frames_running():
			_screen.advance_frame()
			continue
		_screen.finish()
		_screen.advance()
	push_error("No animation on that side in %d steps. %s" % [MAX_STEPS, JSON.stringify(_screen.battle_snapshot())])
	return false
