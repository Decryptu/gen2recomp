extends SceneTree

## Renders one imported audio record through the sound engine and the APU, and
## writes a WAV plus the per-frame hardware-register trace beside it.
##
## The trace is the parity artefact: any faithful implementation of the same
## driver has to write the same registers in the same order on the same frames.
##
## ```sh
## G=/Applications/Godot.app/Contents/MacOS/Godot
## $G --headless --path . -s res://tools/render_audio.gd -- crystal music 1 600 /tmp/out
## ```
## Kinds are `music`, `sfx`, `cry` and `mon_cry`; the id is the record index, or
## the species number for `mon_cry`, or `all` to sweep the whole table into
## `<prefix>_<index>`.


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() < 5:
		printerr("usage: render_audio.gd -- <game> <music|sfx|cry> <id|all> <frames> <out-prefix> [stereo]")
		quit(1)
		return
	var game: StringName = StringName(arguments[0])
	var kind: StringName = StringName(arguments[1])
	var frames: int = int(arguments[3])
	var prefix: String = arguments[4]
	var stereo: bool = arguments.size() > 5 and arguments[5] == "1"

	var data: GameData = GameData.open(game)
	if data == null:
		printerr("No imported cache for %s. Run tools/import_rom.gd first." % game)
		quit(1)
		return

	var assets: Dictionary = {
		"wave_samples": data.world_audio_asset(&"wave_samples"),
		"drumkits": data.world_audio_asset(&"drumkits"),
	}
	if arguments[2] == "all":
		var index: int = 1 if kind == &"mon_cry" else 0
		while true:
			var record: Dictionary = _record(data, kind, index)
			if record.is_empty():
				break
			_report(kind, index, record)
			if not _render(record, kind, assets, frames, stereo, "%s_%d" % [prefix, index]):
				quit(1)
				return
			index += 1
		print("Rendered %s records up to %d into %s_*" % [kind, index - 1, prefix])
		quit(0)
		return

	var record: Dictionary = _record(data, kind, int(arguments[2]))
	if record.is_empty():
		printerr("No %s record %s in the %s cache." % [kind, arguments[2], game])
		quit(1)
		return
	_report(kind, int(arguments[2]), record)
	if not _render(record, kind, assets, frames, stereo, prefix):
		quit(1)
		return
	print("%s.wav: %d frames" % [prefix, frames])
	quit(0)


func _record(data: GameData, kind: StringName, index: int) -> Dictionary:
	if kind == &"mon_cry":
		return data.species_cry(index)
	return data.world_audio(_table(kind), index)


## `mon_cry` resolves through `PokemonCries`, so the parameters it picked are
## worth printing: a parity run has to hand the same two to the other side.
func _report(kind: StringName, index: int, record: Dictionary) -> void:
	if kind != &"mon_cry":
		return
	print("species %d: cry index %d pitch %d length %d" % [
		index, int(record.get("index", -1)),
		int(record.get("cry_pitch", 0)), int(record.get("cry_length", 0)),
	])


func _render(
	record: Dictionary, kind: StringName, assets: Dictionary, frames: int,
	stereo: bool, prefix: String
) -> bool:
	var result: Dictionary = Gen2AudioRender.render(record, kind, assets, frames, stereo, true)
	if not bool(result.get("ok", false)):
		printerr("Render failed: %s" % result.get("reason", "unknown"))
		return false
	if not Gen2AudioRender.write_wav(prefix + ".wav", result["pcm"]):
		printerr("Cannot write %s.wav" % prefix)
		return false
	var trace := FileAccess.open(prefix + ".trace", FileAccess.WRITE)
	if trace == null:
		printerr("Cannot write %s.trace" % prefix)
		return false
	trace.store_string(result["trace"])
	trace.close()
	return true


func _table(kind: StringName) -> StringName:
	if kind == &"cry" or kind == &"cries" or kind == &"mon_cry":
		return &"cries"
	if kind == &"sfx" or kind == &"sound":
		return &"sfx"
	return &"music"
