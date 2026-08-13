extends GutTest

## The overworld's one clock. `Gen2WorldScreen._process` is the only place real
## time becomes hardware frames, and `advance_frame()` is the only place a frame
## is spent, so nothing downstream banks a remainder of its own.
##
## The fixture is synthetic; the screen, the world API and the play timer are the
## production paths.

const Fixture := preload("res://tests/integration/world_trainer_fixture.gd")

const FRAME: float = Gen2WorldAnimation.FRAME_SECONDS

var _data: GameData = null
var _world_screen: Gen2WorldScreen = null


func before_each() -> void:
	_data = Fixture.build()
	_data = GameData.open_directory(Fixture.directory())


func after_each() -> void:
	if is_instance_valid(_world_screen):
		_world_screen.free()
		_world_screen = null
	RomCache.clear(Fixture.directory())


func _open_world(seed_value: int = 4242) -> Gen2WorldScreen:
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	var screen: Gen2WorldScreen = packed.instantiate() as Gen2WorldScreen
	screen.map_group = Fixture.MAP_GROUP
	screen.map_number = Fixture.MAP_NUMBER
	screen.start_cell = Vector2i(4, 5)
	screen.encounter_seed = seed_value
	screen.set_data(_data)
	add_child(screen)
	await get_tree().process_frame
	## The host's own frames belong to the host; every case here spends the
	## world's, so the numbers are the same on any machine. The one frame the
	## tree ran above left a remainder banked, which is the state a case that
	## counts frames has to start from zero.
	screen.set_process(false)
	screen._frame_elapsed = 0.0
	return screen


func test_a_partial_frame_of_real_time_spends_no_hardware_frame() -> void:
	_world_screen = await _open_world()
	var before: int = _world_screen._world.frame_number

	# A display faster than the hardware cannot make the world run faster.
	_world_screen._process(FRAME * 0.5)
	assert_eq(_world_screen._world.frame_number, before)

	# The remainder carries over: two half frames are one whole one.
	_world_screen._process(FRAME * 0.5)
	assert_eq(_world_screen._world.frame_number, before + 1)


## One stall must not hand the world a minute of frames at once, which is what
## every one of the accumulators this replaced capped separately.
func test_a_stall_drops_frames_instead_of_running_the_backlog() -> void:
	_world_screen = await _open_world()
	var before: int = _world_screen._world.frame_number
	_world_screen._process(10.0)
	assert_eq(
		_world_screen._world.frame_number - before,
		Gen2WorldAnimation.MAX_CATCHUP_FRAMES
	)


## The play timer, the tile animation, the walk step and the emote counters are
## all spent from the same call, so one world frame is one of each.
func test_one_world_frame_is_one_frame_of_everything_that_counts_them() -> void:
	_world_screen = await _open_world()
	var save := Gen2SaveData.new()
	_world_screen.set_save(save)
	var before: int = _world_screen._world.frame_number

	_world_screen.advance_frames(30)
	assert_eq(_world_screen._world.frame_number, before + 30)
	assert_eq(save.game_time.frames, 30, "the play timer counted the same thirty")


## The frame number is what makes a snapshot comparable at all, so it travels
## with one and comes back with it.
func test_the_frame_number_survives_a_snapshot_round_trip() -> void:
	_world_screen = await _open_world()
	_world_screen.advance_frames(17)
	var snapshot: Gen2WorldSnapshot = _world_screen._world.snapshot()
	assert_eq(snapshot.frame_number, _world_screen._world.frame_number)
	assert_eq(snapshot.random_seed, 4242)

	var restored: Gen2WorldAPI = Gen2WorldAPI.open_snapshot(
		_data, Gen2WorldSnapshot.from_dict(snapshot.to_dict())
	)
	assert_not_null(restored)
	assert_eq(restored.frame_number, snapshot.frame_number)
	assert_eq(restored.random_seed, 4242)


## The artefact this refactor is finished by, in miniature: the same seed and the
## same frame count reach the same world whatever the host's frame rate was.
## tools/replay_world.gd is the same comparison over real cartridge routes.
func test_the_same_seed_and_frame_count_reach_the_same_world_at_any_frame_rate() -> void:
	var snapshots: Array = []
	for host_fps: float in [30.0, 60.0, 144.0]:
		var screen: Gen2WorldScreen = await _open_world()
		var delta: float = 1.0 / host_fps
		var guard: int = 0
		## Pumped to just short of the frame and topped up exactly, the way
		## tools/replay_world.gd does it, because a host frame spends two or more
		## hardware frames at once and cannot be asked to land on a given one. A
		## loop running to 120 lands on 121 whenever an earlier call spent an odd
		## number, which is what made this assertion flake under load.
		while screen._world.frame_number < 120 - 1 and guard < 4096:
			screen._process(delta)
			guard += 1
		screen.advance_frames(maxi(0, 120 - screen._world.frame_number))
		assert_eq(screen._world.frame_number, 120, "%d fps reached the frame" % host_fps)
		snapshots.append(JSON.stringify(screen._world.snapshot().to_dict()))
		screen.free()
	assert_eq(snapshots[0], snapshots[1], "30 fps and 60 fps disagree")
	assert_eq(snapshots[1], snapshots[2], "60 fps and 144 fps disagree")


## `Gen2WorldClock` is deliberately not converted: Generation 2 keeps a
## real-time clock, so the day cycle reads wall time and only the day cycle does.
func test_the_day_cycle_stays_on_real_seconds() -> void:
	_world_screen = await _open_world()
	var before: Dictionary = _world_screen._world.world_clock()
	_world_screen.advance_frames(600)
	assert_eq(
		_world_screen._world.world_clock(), before,
		"ten seconds of frames move no clock, because frames are not what it reads"
	)
	_world_screen._process(Gen2WorldClock.SECONDS_PER_MINUTE)
	assert_eq(
		int(_world_screen._world.world_clock()["minute"]),
		(int(before["minute"]) + 1) % Gen2WorldClock.MINUTES_PER_HOUR,
		"a minute of real time is a cartridge minute"
	)

	## And a boundary is asked for rather than waited for, which is what keeps a
	## day cycle testable while it stays on wall time.
	var day: int = int(_world_screen._world.world_clock()["day"])
	_world_screen.advance_world_time(
		float(Gen2WorldClock.HOURS_PER_DAY) * 3600.0
	)
	assert_eq(
		int(_world_screen._world.world_clock()["day"]),
		(day + 1) % Gen2WorldClock.DAYS_PER_WEEK
	)
