extends GutTest

## A battle's own text box is the player's text box: `PrintLetterDelay` reads
## TEXT SPEED and `wTextboxFrame` reads FRAME, and neither knows it is in a
## battle. The box used to take the frame and leave the speed behind.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

var _data: GameData = null
var _screen: Gen2BattleScreen = null


func before_each() -> void:
	Gen2ModHost.reset()
	Fixture.build()
	_data = GameData.open_directory(Fixture.directory())
	Gen2OptionsStore.use_test_path()
	DirAccess.remove_absolute(Gen2OptionsStore.path())


func after_each() -> void:
	if is_instance_valid(_screen):
		_screen.free()
		_screen = null
	RomCache.clear(Fixture.directory())
	Gen2OptionsStore.use_test_path()
	DirAccess.remove_absolute(Gen2OptionsStore.path())
	Gen2ModHost.reset()


## The screen reads the options once, when it builds its box, so each speed is a
## fresh screen the way a battle entered from the overworld is.
func _open_with(text_speed: int, frame: int) -> Gen2BattleScreen:
	var options: Gen2Options = Gen2OptionsStore.current()
	options.text_speed = text_speed
	options.textbox_frame = frame
	var packed: PackedScene = load("res://game/battle/battle_screen.tscn")
	_screen = packed.instantiate() as Gen2BattleScreen
	_screen.set_data(_data)
	add_child(_screen)
	return _screen


func test_the_battle_box_takes_the_players_text_speed() -> void:
	for speed: int in Gen2Options.TEXT_DELAYS.size():
		var screen: Gen2BattleScreen = _open_with(speed, 0)
		var box: Gen2TextBox = screen.get("_box")
		assert_almost_eq(
			box.reveal_speed, Gen2OptionsStore.current().text_reveal_speed(), 0.001,
			"speed %d" % speed
		)
		screen.free()
		_screen = null


func test_the_battle_box_still_takes_the_players_frame() -> void:
	var box: Gen2TextBox = _open_with(0, 3).get("_box")
	assert_eq(box.frame_style, 3)
