extends GutTest

## Scene-level integration for the overworld trainer vertical slice. The cache
## is synthetic, but the scene, world API, script runner, battle adapter and
## battle overlay are the production paths.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")
const BattleFixture := preload("res://tests/unit/battle_fixture.gd")

var _data: GameData = null
var _world_screen: Gen2WorldScreen = null


func before_each() -> void:
	_data = Fixture.build()


func after_each() -> void:
	if is_instance_valid(_world_screen):
		_world_screen.free()
		_world_screen = null
	RomCache.clear(Fixture.directory())


func _open_world(with_save: bool = false) -> void:
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_world_screen = packed.instantiate() as Gen2WorldScreen
	_world_screen.map_group = Fixture.MAP_GROUP
	_world_screen.map_number = Fixture.MAP_NUMBER
	_world_screen.start_cell = Vector2i(4, 5)
	_world_screen.set_data(_data)
	if with_save:
		var player: Gen2BattleMon = Gen2BattleMon.create(
			_data, Fixture.TRAINER_SPECIES, 5, [BattleFixture.TACKLE]
		)
		var save: Gen2SaveData = Gen2SaveBattleAdapter.from_battle_party(
			_data.id, _data.sha1, 0, Gen2Party.of(player), "TEST"
		)
		_world_screen.set_save(save)
	add_child(_world_screen)
	await get_tree().process_frame


func _trigger_trainer() -> void:
	assert_true(_world_screen.move_player(Vector2i.RIGHT))
	await get_tree().process_frame
	await get_tree().process_frame


func _battle_host() -> Gen2BattleScreen:
	for child: Node in _world_screen.get_children():
		if child is Gen2BattleScreen:
			return child as Gen2BattleScreen
	return null


func test_trainer_sight_reaches_the_real_battle_overlay() -> void:
	await _open_world()
	var before: Dictionary = _world_screen.world_snapshot()
	await _trigger_trainer()

	var host: Gen2BattleScreen = _battle_host()
	assert_not_null(host)
	assert_eq(before["map"], Vector2i(Fixture.MAP_GROUP, Fixture.MAP_NUMBER))
	assert_eq(before["player_cell"], Vector2i(4, 5))
	assert_eq(_world_screen.world_snapshot()["player_cell"], Vector2i(5, 5))
	assert_true(host.is_ready())
	var snapshot: Dictionary = host.battle_snapshot()
	assert_eq(snapshot["enemy"], Fixture.TRAINER_SPECIES)
	assert_eq(snapshot["message"], "LEADER RIVAL wants to fight!")
	assert_eq(snapshot["world_battle_active"], true)


func test_victory_displays_imported_text_reloads_objects_and_keeps_player_cell() -> void:
	await _open_world()
	await _trigger_trainer()
	var host: Gen2BattleScreen = _battle_host()
	assert_not_null(host)

	for _hit: int in 12:
		host.hurt_enemy()
	host.finish()
	host.advance()
	var result_text: Dictionary = host.battle_snapshot()
	assert_eq(result_text["message"], "YOU WON.")

	host.finish()
	host.advance()
	await get_tree().process_frame
	var world: Dictionary = _world_screen.world_snapshot()
	assert_eq(world["map"], Vector2i(Fixture.MAP_GROUP, Fixture.MAP_NUMBER))
	assert_eq(world["player_cell"], Vector2i(5, 5))
	assert_eq(world["visible_objects"], 0)
	assert_true(world["just_battled"])


func test_defeat_displays_imported_loss_text_and_uses_save_recovery() -> void:
	await _open_world(true)
	await _trigger_trainer()
	var host: Gen2BattleScreen = _battle_host()
	assert_not_null(host)

	for _hit: int in 12:
		host.hurt_player()
	for member: Gen2BattleMon in host._battle.party(Gen2Battle.PLAYER).mons:
		member.hp = 0
	host.finish()
	host.advance()
	assert_eq(host.battle_snapshot()["message"], "YOU LOST.")

	host.finish()
	host.advance()
	assert_eq(host.battle_snapshot()["message"], "Blackout! Party restored.")

	host.finish()
	host.advance()
	await get_tree().process_frame
	var world: Dictionary = _world_screen.world_snapshot()
	assert_eq(world["player_cell"], Vector2i(5, 5))
	assert_eq(world["visible_objects"], 1)
	assert_false(world["just_battled"])


func test_emote_preview_reaches_the_production_world_renderer() -> void:
	await _open_world()
	_world_screen.preview_emote()
	await get_tree().process_frame

	assert_eq(_world_screen.world_snapshot()["script_prompt"], "Debug emote preview")
	assert_true((_world_screen._world.objects[0] as Gen2WorldObject).emote_visible)
