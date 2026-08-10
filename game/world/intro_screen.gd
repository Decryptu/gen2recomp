class_name Gen2IntroScreen
extends Control

## `engine/menus/intro_menu.asm`'s `NewGame`, less the title screen that reaches
## it: `PlayerProfileSetup`'s gender question, then `OakSpeech`, then the world.
##
## It is its own screen rather than a state of the overworld because that is
## where the cartridge puts it: `NewGame` reaches `InitializeWorld` only after
## both have returned, so there is no world to be a state of yet.
##
## Nothing is written to disk until the run is over. The launcher stages a slot
## and a label on [GameRuntime], this adds the trainer name and the gender, and
## `Gen2SaveStore.create_new_game` is called once, at the end. That is also why
## `Gen2SaveValidator`'s rule that a save has a trainer needs no exception: the
## save does not exist until there is one.

## Emitted with the written save, for a driver that hosts this screen itself.
## The scene's own handler changes to the overworld.
signal finished(save: Gen2SaveData)
## Carries why the run could not be written, having written nothing.
signal failed(message: String)

const WORLD_SCENE: String = "res://game/world/world_screen.tscn"
const LAUNCHER_SCENE: String = "res://game/main/main.tscn"

var _data: GameData = null
var _slot: int = -1
var _label: String = ""
var _gender: int = Gen2SaveData.GENDER_MALE
var _standalone: bool = true

var _gender_screen: Gen2GenderScreen = null
var _speech: Gen2OakSpeechScreen = null
## Null when a driver builds this class directly rather than instancing the
## scene; the sub-screens are then plain children and draw at their own size.
var _viewport: Gen2Screen = null


## Runs the intro for [param slot] on [param data]. [param standalone] is false
## when a driver hosts the screen and wants the signals rather than a scene
## change.
func begin(
	data: GameData, slot: int, label: String = "", standalone: bool = true
) -> bool:
	_data = data
	_slot = slot
	_label = label
	_standalone = standalone
	_gender = Gen2SaveData.GENDER_MALE
	if _data == null or slot < 0:
		return false
	if is_inside_tree():
		_start()
	return true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport = get_node_or_null("%Screen") as Gen2Screen
	if _viewport == null:
		size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	if _data == null:
		_take_pending()
	if _data != null and _slot >= 0:
		_start()


## The eight hardware buttons and nothing else, the way every other screen here
## reads input; see `docs/CONTRIBUTING.md`.
func _unhandled_input(event: InputEvent) -> void:
	var button: int = Gen2Button.pressed_in(event)
	if button != 0 and handle_button(button):
		get_viewport().set_input_as_handled()


## Sub-screens draw in the 160x144 space, so they go inside the hardware
## viewport when there is one.
func _show_sub_screen(node: Control) -> void:
	if _viewport != null:
		_viewport.display(node)
		return
	add_child(node)


## The launcher's staged slot, for the scene entered through a scene change.
func _take_pending() -> void:
	_data = GameRuntime.selected_data()
	var pending: Dictionary = GameRuntime.take_pending_new_game()
	_slot = int(pending["slot"])
	_label = String(pending["label"])


## Which sub-screen is up, so a test or a driver can press into the right one.
func current() -> Control:
	if _gender_screen != null:
		return _gender_screen
	return _speech


func gender() -> int:
	return _gender


func handle_button(button: int) -> bool:
	var screen: Control = current()
	return screen.handle_button(button) if screen != null else false


## `PlayerProfileSetup` first. On Gold and Silver it has no gender screen to
## reach, so the run starts on Oak's speech and the save keeps GENDER_MALE.
func _start() -> void:
	_gender_screen = Gen2GenderScreen.new()
	if not _gender_screen.open(_data):
		# Never parented, so it is freed outright rather than queued.
		_gender_screen.free()
		_gender_screen = null
		_start_speech()
		return
	_gender_screen.closed.connect(_on_gender_chosen)
	_show_sub_screen(_gender_screen)


func _on_gender_chosen(chosen: int) -> void:
	_gender = chosen
	_gender_screen.queue_free()
	_gender_screen = null
	_start_speech()


func _start_speech() -> void:
	_speech = Gen2OakSpeechScreen.new()
	if not _speech.open(_data, _gender):
		_speech.free()
		_speech = null
		_fail("This cartridge cache carries no intro text.")
		return
	_speech.finished.connect(_on_speech_finished)
	_show_sub_screen(_speech)


## `InitializeWorld`'s place in `NewGame`: the save is built and written here,
## once, with the name the keyboard produced and the gender the menu chose.
func _on_speech_finished(player_name: String) -> void:
	var created: Gen2SaveData = Gen2SaveStore.create_new_game(_data, _slot, player_name)
	if created == null:
		_fail("The intro produced a name this save cannot hold.")
		return
	created.gender = _gender
	created.label = _label
	var result: Dictionary = Gen2SaveStore.save(created, _data)
	if not bool(result["ok"]):
		_fail(String(result["message"]))
		return
	GameRuntime.select_save_slot(_data.id, _slot)
	finished.emit(created)
	if _standalone:
		get_tree().change_scene_to_file.call_deferred(WORLD_SCENE)


## A failure here has written nothing, so the launcher is the right place to go
## back to rather than a half-made world.
func _fail(message: String) -> void:
	failed.emit(message)
	if _standalone:
		push_error("New game intro: %s" % message)
		get_tree().change_scene_to_file.call_deferred(LAUNCHER_SCENE)
