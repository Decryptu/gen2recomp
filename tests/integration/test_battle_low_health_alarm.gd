extends GutTest

## `HandleHPPals` and `wCryTracks`: the two driver inputs the battle screen owns.
## The alarm follows the player's own bar colour, and a cry is masked onto the
## side of the field its battler stands on.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

var _data: GameData = null
var _screen: Gen2BattleScreen = null


func before_each() -> void:
	Gen2ModHost.reset()
	Fixture.build()
	_data = GameData.open_directory(Fixture.directory())
	var packed: PackedScene = load("res://game/battle/battle_screen.tscn")
	_screen = packed.instantiate() as Gen2BattleScreen
	_screen.set_data(_data)
	add_child(_screen)


func after_each() -> void:
	if is_instance_valid(_screen):
		_screen.free()
		_screen = null
	RomCache.clear(Fixture.directory())
	Gen2ModHost.reset()


func _alarm() -> bool:
	return (_screen._audio_player as Gen2AudioPlayer).low_health_alarm()


## Every `PlayStereoCry` in `engine/battle/core.asm` writes $0f for the enemy's
## cry and $f0 for the player's.
func test_each_battler_cries_on_its_own_side() -> void:
	assert_eq(Gen2BattleScreen.cry_tracks(true), 0x0F)
	assert_eq(Gen2BattleScreen.cry_tracks(false), 0xF0)


## The bar's colour follows what is drawn, so a full bar is green and the alarm
## is silent.
func test_a_healthy_bar_leaves_the_alarm_off() -> void:
	_screen.set_hp(40, 40, 40, 40)
	assert_false(_alarm())


## HP_RED is what arms it, and only the player's own bar is read.
func test_a_red_player_bar_arms_the_alarm() -> void:
	_screen.set_hp(40, 40, 2, 40)
	assert_true(_alarm())

	_screen.set_hp(2, 40, 40, 40)
	assert_false(_alarm(), "the enemy's bar is not wPlayerHPPal")


## `StopDangerSound` runs before `FaintYourPokemon`'s cry, so a fainted Pokemon
## silences it rather than leaving it on the one lit pixel a zero bar keeps.
func test_a_fainted_player_silences_the_alarm() -> void:
	_screen.set_hp(40, 40, 2, 40)
	assert_true(_alarm())
	_screen.set_hp(40, 40, 0, 40)
	assert_false(_alarm())


## `CleanUpBattleRAM` zeroes the byte whole. When the driver belongs to the
## screen that opened this one it outlives the fight, so a battle left with the
## alarm armed would beep over the map music it hands back; the clear is where
## the screen leaves the tree, which is every way out of a battle.
func test_a_shared_driver_is_left_with_the_alarm_off() -> void:
	var driver := Gen2AudioPlayer.new()
	add_child(driver)
	var packed: PackedScene = load("res://game/battle/battle_screen.tscn")
	var borrower := packed.instantiate() as Gen2BattleScreen
	borrower.set_data(_data)
	borrower.set_audio_player(driver)
	add_child(borrower)
	borrower.set_hp(40, 40, 2, 40)
	assert_true(driver.low_health_alarm())

	remove_child(borrower)
	borrower.free()
	assert_false(driver.low_health_alarm())
	assert_true(is_instance_valid(driver), "and the driver is not the fight's to free")
	remove_child(driver)
	driver.free()
