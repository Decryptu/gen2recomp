extends GutTest

## `PlayBattleAnim`'s own framing, driven through the production battle screen:
## the six-frame lead, the hud coming off and going back on, the tilemap the
## effects edit and the OPTION menu's battle-scene row that skips the lot.
##
## The cache is synthetic, so no animation script resolves out of it; what is
## checked here is the framing the screen owes an animation event, which is the
## screen's own and not the player's.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

var _data: GameData = null
var _screen: Gen2BattleScreen = null


func before_each() -> void:
	Gen2ModHost.reset()
	Fixture.build()
	_data = GameData.open_directory(Fixture.directory())
	## The battle-scene row and the reveal speed are both read off the options
	## store, and a case here writes one: redirect the store first, so a test run
	## reads and writes the test path rather than the settings on this machine.
	Gen2OptionsStore.use_test_path()
	DirAccess.remove_absolute(Gen2OptionsStore.path())


func after_each() -> void:
	DirAccess.remove_absolute(Gen2OptionsStore.path())
	if is_instance_valid(_screen):
		_screen.free()
		_screen = null
	RomCache.clear(Fixture.directory())
	Gen2ModHost.reset()


func _open_battle() -> void:
	var packed: PackedScene = load("res://game/battle/battle_screen.tscn")
	_screen = packed.instantiate() as Gen2BattleScreen
	_screen.set_data(_data)
	add_child(_screen)
	await get_tree().process_frame
	_screen.show_matchup(16, 155, 5, 5)
	var guard: int = 4000
	while _screen.intro_running() and guard > 0:
		_screen.advance_frame()
		guard -= 1


func _animation_event(extra: Dictionary = {}) -> Dictionary:
	var event: Dictionary = {
		"type": Gen2Battle.ANIMATION, "side": Gen2Battle.PLAYER,
		"index": 33, "param": 0,
		"after_anim": Gen2BattleAnimPlayer.AFTER_ANIM_ENEMY_DAMAGE,
		"enemy_turn": false, "effectiveness": RomLayout.MATCHUP_EFFECTIVE,
		"restore_user_pic": false,
	}
	event.merge(extra, true)
	return event


func _settle_animation() -> int:
	var frames: int = 0
	while _screen.animation_running() and frames < 4000:
		_screen.advance_frame()
		frames += 1
	return frames


func test_an_animation_event_spends_frames_before_anything_else_is_shown() -> void:
	await _open_battle()
	_screen._begin_animation(_animation_event())
	assert_true(_screen.animation_running())
	# `PlayFXAnimID`'s three frames and `_PlayBattleAnim`'s own six plus one:
	# nothing happens for the first ten.
	for _frame: int in 10:
		assert_false(_screen.animation_snapshot()["playing"])
		_screen.advance_frame()
	assert_gt(_settle_animation(), 0)
	assert_false(_screen.animation_running())


func test_a_move_animation_takes_the_hud_off_and_puts_it_back() -> void:
	await _open_battle()
	_screen._begin_animation(_animation_event())
	var hidden: bool = false
	var guard: int = 4000
	while _screen.animation_running() and guard > 0:
		hidden = hidden or not bool(_screen.animation_snapshot()["hud_visible"])
		_screen.advance_frame()
		guard -= 1
	assert_true(hidden, "BattleAnimClearHud takes the panels off the map")
	assert_true(bool(_screen.animation_snapshot()["hud_visible"]))


func test_the_battle_scene_option_skips_the_move_animation() -> void:
	await _open_battle()
	var options: Gen2Options = Gen2OptionsStore.current()
	options.battle_scene = false
	Gen2OptionsStore.save(options)

	_screen._begin_animation(_animation_event())
	var hidden: bool = false
	var guard: int = 4000
	while _screen.animation_running() and guard > 0:
		hidden = hidden or not bool(_screen.animation_snapshot()["hud_visible"])
		_screen.advance_frame()
		guard -= 1
	# `CheckBattleScene` answers carry, so `BattleAnimClearHud` and the move's
	# own script are never reached and the field is untouched.
	assert_false(hidden)


func test_a_status_animation_leaves_the_hud_up() -> void:
	# `BattleAnimRunScript` takes `.not_move` on an id past `wFXAnimID`'s low
	# byte, which skips `BattleAnimClearHud` and `BattleAnimRestoreHuds` alike,
	# so a status animation leaves the panels where they are. The move id in
	# [method test_a_move_animation_takes_the_hud_off_and_puts_it_back] is the
	# same event with the same battle-scene setting and does take them off, so
	# the id is what decides.
	await _open_battle()
	_screen._begin_animation(_animation_event({
		"index": Gen2BattleAnimPlayer.ANIM_BRN,
		"after_anim": Gen2BattleAnimPlayer.AFTER_ANIM_NONE,
		"enemy_turn": true,
	}))
	var hidden: bool = false
	var guard: int = 4000
	while _screen.animation_running() and guard > 0:
		hidden = hidden or not bool(_screen.animation_snapshot()["hud_visible"])
		_screen.advance_frame()
		guard -= 1
	assert_false(hidden, ".not_move reaches neither hud call")


func test_the_tilemap_is_the_battle_it_is_seeded_from() -> void:
	await _open_battle()
	var map: PackedByteArray = _screen._bg_map
	assert_eq(map.size(), Gen2BattleScreenMap.COLUMNS * Gen2BattleScreenMap.ROWS)
	# `GetEnemyFrontpicCoords` and `AppearUser`'s own `xor a` / `ld a, $31`.
	assert_eq(int(map[Gen2BattleScreenMap.ENEMY_AT.x]), Gen2BattleScreenMap.ENEMY_BASE_TILE)
	var player_at: int = Gen2BattleScreenMap.PLAYER_AT.y * Gen2BattleScreenMap.COLUMNS \
		+ Gen2BattleScreenMap.PLAYER_AT.x
	assert_eq(int(map[player_at]), Gen2BattleScreenMap.PLAYER_BASE_TILE)
	assert_eq(int(map[0]), Gen2BattleScreenMap.BLANK_TILE)


func test_a_blanked_picture_stays_blank_until_something_stamps_it_back() -> void:
	await _open_battle()
	# What `BattleBGEffect_HideMon` leaves behind, and what `AppearUserLowerSub`
	# is for: the map outlives the animation that edited it.
	_screen._bg_map[Gen2BattleScreenMap.ENEMY_AT.x] = Gen2BattleScreenMap.BLANK_TILE
	_screen._begin_animation(_animation_event())
	_settle_animation()
	assert_eq(
		int(_screen._bg_map[Gen2BattleScreenMap.ENEMY_AT.x]),
		Gen2BattleScreenMap.BLANK_TILE
	)

	_screen._begin_animation(_animation_event({"restore_user_pic": true, "enemy_turn": true}))
	_settle_animation()
	assert_eq(
		int(_screen._bg_map[Gen2BattleScreenMap.ENEMY_AT.x]),
		Gen2BattleScreenMap.ENEMY_BASE_TILE
	)


func test_the_view_carries_the_tilemap_and_the_palette_maps() -> void:
	await _open_battle()
	var view: Dictionary = (_screen._renderer as Gen2BattleRenderer)._view
	assert_eq(
		(view["bg_map"] as PackedByteArray).size(),
		Gen2BattleScreenMap.COLUMNS * Gen2BattleScreenMap.ROWS
	)
	assert_eq(
		(view["bg_palette_maps"] as PackedByteArray).size(),
		Gen2BattleAnimBackground.PALETTE_COUNT
	)
	# Nothing has remapped anything, so every palette is drawn as it was loaded.
	for value: int in view["bg_palette_maps"] as PackedByteArray:
		assert_eq(value, Gen2BattleAnimBackground.PALETTE_IDENTITY)
	assert_true(bool(view["hud_visible"]))
	assert_eq((view["anim_sprites"] as Array).size(), 0)


## Which picture a battler's square is showing. The synthetic cache resolves no
## animation script, so what is driven here is the `noanim` half: the two
## commands the battle-scene option reaches instead of the SUBSTITUTE animation,
## and the events that write the picture outside one.

func _substitute_event(param: int, enemy_turn: bool = false) -> Dictionary:
	return _animation_event({
		"index": Gen2EffectCommands.SUBSTITUTE_MOVE, "param": param,
		"after_anim": Gen2BattleAnimPlayer.AFTER_ANIM_NONE, "enemy_turn": enemy_turn,
	})


func _view() -> Dictionary:
	return (_screen._renderer as Gen2BattleRenderer)._view


func test_the_doll_is_drawn_and_taken_off_with_the_battle_scene_turned_off() -> void:
	await _open_battle()
	var options: Gen2Options = Gen2OptionsStore.current()
	options.battle_scene = false
	Gen2OptionsStore.save(options)

	assert_false(bool(_view()["player_substitute"]))
	_screen._begin_animation(_substitute_event(Gen2EffectCommands.SUBSTITUTE_ANIM_MADE))
	_settle_animation()
	assert_true(bool(_view()["player_substitute"]), "`.no_anim` calls RaiseSubNoAnim")
	assert_false(bool(_view()["enemy_substitute"]), "the actor's square alone")

	_screen._begin_animation(_substitute_event(Gen2EffectCommands.SUBSTITUTE_ANIM_DROP))
	_settle_animation()
	assert_false(bool(_view()["player_substitute"]))

	_screen._begin_animation(_substitute_event(Gen2EffectCommands.SUBSTITUTE_ANIM_RAISE, true))
	_settle_animation()
	assert_true(bool(_view()["enemy_substitute"]))
	assert_false(bool(_view()["player_substitute"]))


func test_a_move_animation_with_the_scene_off_leaves_the_doll_alone() -> void:
	await _open_battle()
	var options: Gen2Options = Gen2OptionsStore.current()
	options.battle_scene = false
	Gen2OptionsStore.save(options)

	_screen._apply_event({
		"type": Gen2Battle.SUBSTITUTE_PIC, "side": Gen2Battle.PLAYER, "raised": true,
	})
	_screen._begin_animation(_animation_event())
	_settle_animation()
	assert_true(bool(_view()["player_substitute"]))


func test_the_doll_comes_off_for_a_restored_user_picture() -> void:
	await _open_battle()
	# `AppearUserLowerSub`, which Fly and Dig reach: `LowerSubNoAnim` writes the
	# user's own picture back before `AppearUser` stamps it into the map.
	_screen._apply_event({
		"type": Gen2Battle.SUBSTITUTE_PIC, "side": Gen2Battle.ENEMY, "raised": true,
	})
	assert_true(bool(_view()["enemy_substitute"]))
	_screen._begin_animation(_animation_event({"restore_user_pic": true, "enemy_turn": true}))
	_settle_animation()
	assert_false(bool(_view()["enemy_substitute"]))


func test_a_send_out_draws_a_picture_rather_than_the_doll_the_last_one_had() -> void:
	await _open_battle()
	_screen._apply_event({
		"type": Gen2Battle.SUBSTITUTE_PIC, "side": Gen2Battle.PLAYER, "raised": true,
	})
	_screen._apply_event({
		"type": Gen2Battle.SENT_OUT, "side": Gen2Battle.PLAYER, "species": 16,
		"level": 5, "hp": 20, "max_hp": 20,
	})
	assert_false(bool(_view()["player_substitute"]))


func test_the_frames_an_animation_spends_do_not_owe_a_press() -> void:
	# `DoMove` reads no joypad between `PlayFXAnimID` and the command after it,
	# so the line behind an animation is said when its frames run out rather
	# than when the player presses A.
	await _open_battle()
	_screen._pending = [{
		"type": Gen2Battle.MISSED, "side": Gen2Battle.PLAYER, "move": 33,
	}]
	_screen._begin_animation(_animation_event())
	_settle_animation()
	assert_false(_screen.animation_running())
	assert_eq(_screen._pending.size(), 0, "the pump ran on without a press")
	assert_ne(String(_screen.battle_snapshot()["message"]), "",
		"the held line was said")


func test_a_line_on_screen_still_owes_its_press() -> void:
	# The same pump must not walk past a box: only a button dismisses one.
	await _open_battle()
	_screen.show_message("ATTACK MISSED!")
	_screen._pending = [{
		"type": Gen2Battle.MISSED, "side": Gen2Battle.PLAYER, "move": 33,
	}]
	_screen._begin_animation(_animation_event())
	_settle_animation()
	assert_eq(_screen._pending.size(), 1, "the line was not pressed past")
	## The reveal is a frame count at the OPTION menu's text speed, and a press
	## cannot shorten one, so the line is spent before the press that dismisses
	## it: how many frames the animation happened to cover is not the subject.
	_settle_message()
	assert_false(_screen._box.is_revealing(), "the line has finished printing")
	_screen.advance()
	assert_eq(_screen._pending.size(), 0)


## Spends the frames the box still owes, the way a player waits through them.
func _settle_message() -> void:
	var box: Gen2TextBox = _screen._box
	var guard: int = 4000
	while box != null and box.is_revealing() and guard > 0:
		_screen.advance_frame()
		guard -= 1
