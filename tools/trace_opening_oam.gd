extends SceneTree

## Dumps the opening's shadow OAM, one line per sprite per frame, against a real
## cache.
##
##   Godot --headless --path . -s res://tools/trace_opening_oam.gd -- <game> <phase> [out.txt]
##
## `phase` is `presents`, `intro` (Crystal's movie), `gs_intro` (Gold and
## Silver's) or `title`. The artefact is the one `.claude/verification.md`
## step 2 asks for: two faithful implementations of `PlaySpriteAnimations` put
## the same sprites in the same slots on the same frames, so a `diff` against a
## cartridge running under an emulator settles the port rather than a frame count
## measured from the port itself. `tools/render_audio.gd` is the same shape for
## the driver's register writes.
##
## A line is `frame slot y x tile`, with `y` and `x` the OAM bytes: a cartridge's
## own buffer is read at the frame boundary, where hDMATransfer copies it.
##
## A fourth argument writes the page's own picture for those frames, named after
## each, so the frame a diff points at can be looked at beside the emulator's.
## The page draws into an `Image`, so this stays headless;
## `tools/preview_intro.gd` photographs the same screen through the boot
## cinema, whose frames count from the copyright rather than from this phase.

const PHASES: Array[String] = ["presents", "intro", "gs_intro", "title"]

## The title screen runs until its own timeout, which is longer than anything
## worth diffing; this is well past `TitleScreenEnd`'s own count.
const TITLE_FRAME_CAP: int = 4000
## Either movie ends itself; this only stops a run that never does.
const MOVIE_FRAME_CAP: int = 4000

## Frames to write a PNG for, beside the trace's own output path.
var _shots: Dictionary = {}
var _shot_prefix: String = "res://presents"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2 or not PHASES.has(args[1]):
		push_error(
			"Usage: trace_opening_oam.gd -- <game> <%s> [out.txt]"
			% "|".join(PHASES)
		)
		quit(1)
		return
	var data: GameData = _open(StringName(args[0]))
	if data == null:
		quit(1)
		return
	if args.size() > 2:
		_shot_prefix = args[2].get_basename()
	if args.size() > 3:
		for value: String in args[3].split(","):
			_shots[int(value)] = true
	var lines: PackedStringArray
	match args[1]:
		"presents":
			lines = _trace_presents(data)
		"intro":
			lines = _trace_intro(data)
		"gs_intro":
			lines = _trace_gs_intro(data)
		_:
			lines = _trace_title(data)
	if args.size() > 2:
		var file := FileAccess.open(args[2], FileAccess.WRITE)
		if file == null:
			push_error("Could not write %s." % args[2])
			quit(1)
			return
		file.store_string("\n".join(lines) + "\n")
		print("%d lines to %s" % [lines.size(), args[2]])
	else:
		print("\n".join(lines))
	quit(0)


## `GameFreakPresentsScene` from its first frame to the one it sets its own exit
## bit on, which is what the phase's pinned budget counts.
func _trace_presents(data: GameData) -> PackedStringArray:
	var page: Gen2GameFreakPresentsPage = Gen2GameFreakPresentsPage.from_data(data)
	if page == null:
		push_error("%s has no GameFreak Presents art." % data.id)
		return PackedStringArray()
	var phase := Gen2GameFreakPresents.new()
	phase.start(data.id, Gen2BattleAnimData.from_game_data(data))
	var out := PackedStringArray()
	var frame: int = 0
	var words: int = -1
	while not phase.finished():
		_append_frame(out, frame, page.shadow_oam(phase))
		if _shots.has(frame):
			var image: Image = page.draw(phase)
			if image != null:
				image.save_png("%s_f%d.png" % [_shot_prefix, frame])
		# The words are background, so they are not in the trace; printing the
		# frame each is placed on is what aligns it, since a cartridge's own
		# tilemap says the same thing.
		if phase.words() != words:
			words = phase.words()
			print("frame %d: words %d" % [frame, words])
		phase.advance_frame()
		frame += 1
	_append_frame(out, frame, page.shadow_oam(phase))
	print("frame %d: finished" % frame)
	return out


## `CrystalIntro` from its first frame to the one it sets its own exit bit on,
## driven with no buttons held so nothing skips it.
func _trace_intro(data: GameData) -> PackedStringArray:
	var page: Gen2IntroMoviePage = Gen2IntroMoviePage.from_data(data)
	if page == null:
		push_error("%s has no intro movie art." % data.id)
		return PackedStringArray()
	var movie: Gen2IntroMovie = Gen2IntroMovie.create(
		data, Gen2BattleAnimData.from_game_data(data)
	)
	var out := PackedStringArray()
	var frame: int = 0
	var scene: int = -1
	while not movie.finished() and frame < MOVIE_FRAME_CAP:
		_append_frame(out, frame, page.shadow_oam(movie))
		if _shots.has(frame):
			page.draw(movie).save_png("%s_f%d.png" % [_shot_prefix, frame])
		if movie.scene() != scene:
			scene = movie.scene()
			print("frame %d: scene %d" % [frame, scene])
		movie.advance_frame()
		frame += 1
	print("frame %d: finished" % frame)
	return out


## `GoldSilverIntro`, the same way.
func _trace_gs_intro(data: GameData) -> PackedStringArray:
	var page: Gen2GoldSilverIntroPage = Gen2GoldSilverIntroPage.from_data(data)
	if page == null:
		push_error("%s has no intro movie art." % data.id)
		return PackedStringArray()
	var movie: Gen2GoldSilverIntro = Gen2GoldSilverIntro.create(
		data, Gen2BattleAnimData.from_game_data(data)
	)
	var out := PackedStringArray()
	var frame: int = 0
	var scene: int = -1
	while not movie.finished() and frame < MOVIE_FRAME_CAP:
		_append_frame(out, frame, page.shadow_oam(movie))
		if _shots.has(frame):
			page.draw(movie).save_png("%s_f%d.png" % [_shot_prefix, frame])
		if movie.scene() != scene:
			scene = movie.scene()
			print("frame %d: scene %d" % [frame, scene])
		movie.advance_frame()
		frame += 1
	print("frame %d: finished" % frame)
	return out


## `TitleScreenScene` from its first frame, which is the entrance scrolling the
## screen in, to the one that answers. Driven with no buttons held, the way a
## cartridge left alone runs it, so the timeout is what ends it.
func _trace_title(data: GameData) -> PackedStringArray:
	var page: Gen2TitlePage = Gen2TitlePage.from_data(data)
	if page == null:
		push_error("%s has no title screen art." % data.id)
		return PackedStringArray()
	var scene: Gen2TitleScene = Gen2TitleScene.create(
		data.id, Gen2BattleAnimData.from_game_data(data)
	)
	var out := PackedStringArray()
	var frame: int = 0
	var where: StringName = &""
	while not scene.finished() and frame < TITLE_FRAME_CAP:
		_append_frame(out, frame, page.shadow_oam(scene))
		if _shots.has(frame):
			var image: Image = page.draw(scene)
			if image != null:
				image.save_png("%s_f%d.png" % [_shot_prefix, frame])
		if scene.scene() != where:
			where = scene.scene()
			print("frame %d: %s" % [frame, where])
		scene.advance_frame()
		frame += 1
	print("frame %d: finished" % frame)
	return out


func _append_frame(out: PackedStringArray, frame: int, entries: Array[Dictionary]) -> void:
	var slot: int = 0
	for entry: Dictionary in entries:
		out.append("%d %d %d %d %d" % [
			frame, slot, int(entry["y"]), int(entry["x"]), int(entry["tile"]),
		])
		slot += 1


func _open(game: StringName) -> GameData:
	var sha1: String = RomRegistry.sha1_for(game)
	var directory: String = RomCache.directory_for(game, sha1) if not sha1.is_empty() else ""
	if directory.is_empty() or not RomCache.is_usable(directory):
		push_error("No cache for %s. Run tools/import_rom.gd first." % game)
		return null
	var data: GameData = GameData.open_directory(directory)
	if data == null:
		push_error("Could not open the cache for %s." % game)
	return data
