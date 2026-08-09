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
var _battle_scene: bool = true


func before_each() -> void:
	Gen2ModHost.reset()
	Fixture.build()
	_data = GameData.open_directory(Fixture.directory())
	_battle_scene = Gen2OptionsStore.current().battle_scene


func after_each() -> void:
	var options: Gen2Options = Gen2OptionsStore.current()
	options.battle_scene = _battle_scene
	Gen2OptionsStore.save(options)
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
