extends GutTest

## The read-only snapshot a battle renderer is handed when the battle was
## entered from the world. It is built from a real Gen2WorldAPI over the same
## synthetic cache the rest of the world unit tests use.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

var _data: GameData = null


func before_all() -> void:
	Fixture.build()
	_data = GameData.open_directory(Fixture.directory())


func after_all() -> void:
	RomCache.clear(Fixture.directory())


func _world() -> Gen2WorldAPI:
	return Gen2WorldAPI.open(_data, 1, 1, Vector2i(4, 4))


func test_capture_copies_the_map_tileset_cell_and_facing() -> void:
	var world: Gen2WorldAPI = _world()
	world.player_facing = Gen2WorldSprite.FACING_LEFT
	var context: Gen2BattleWorldContext = Gen2BattleWorldContext.capture(
		world, Gen2WorldPalette.TIME_NIGHT
	)
	assert_eq(context.map_id, Vector2i(1, 1))
	assert_eq(context.map_group(), 1)
	assert_eq(context.map_number(), 1)
	assert_eq(context.tileset, world.current_map.tileset)
	assert_eq(context.player_cell, Vector2i(4, 4))
	assert_eq(context.player_facing, Gen2WorldSprite.FACING_LEFT)
	assert_eq(context.time_of_day, Gen2WorldPalette.TIME_NIGHT)


## A copy, not a handle: the whole point is that a renderer cannot reach world
## state through it once the fight has started.
func test_the_snapshot_does_not_follow_the_world_it_was_taken_from() -> void:
	var world: Gen2WorldAPI = _world()
	var context: Gen2BattleWorldContext = Gen2BattleWorldContext.capture(world, 0)
	world.player_cell = Vector2i(6, 6)
	world.player_facing = Gen2WorldSprite.FACING_UP
	assert_eq(context.player_cell, Vector2i(4, 4))
	assert_eq(context.player_facing, Gen2WorldSprite.FACING_DOWN)


## The world's own row when the caller does not name one, which is the map's
## rather than the clock's: a dark cave is night until Flash is used.
func test_an_unnamed_time_of_day_falls_back_to_the_maps_own_row() -> void:
	var world: Gen2WorldAPI = _world()
	world.set_object_time(22, Gen2WorldPalette.TIME_NIGHT)
	var context: Gen2BattleWorldContext = Gen2BattleWorldContext.capture(world)
	assert_eq(context.time_of_day, world.map_time_of_day())


func test_a_world_without_a_map_answers_nothing() -> void:
	assert_null(Gen2BattleWorldContext.capture(null))


## `RegionCheck` reads `GetWorldMapLocation`, which is what `PlayBattleMusic`
## picks a wild track off, so the snapshot has to carry it.
func test_capture_copies_the_maps_landmark() -> void:
	var world: Gen2WorldAPI = _world()
	var context: Gen2BattleWorldContext = Gen2BattleWorldContext.capture(world)
	assert_eq(context.landmark, world.landmark())
	assert_eq(int(context.to_dictionary()["landmark"]), world.landmark())
