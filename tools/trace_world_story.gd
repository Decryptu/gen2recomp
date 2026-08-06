extends SceneTree

## Prints the imported map event pointers and bounded script command streams for
## story tracing. This reads the derived cache only and never opens a cartridge.
##
##   Godot --headless --path . -s res://tools/trace_world_story.gd -- \
##     crystal 24 4 24 5 24 1

const DEFAULT_MAPS: Array[Vector2i] = [Vector2i(24, 4), Vector2i(24, 5), Vector2i(24, 1)]
const MAX_COMMANDS: int = 128

var _data: GameData = null
var _seen: Dictionary = {}


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Usage: trace_world_story.gd -- <game> [group map ...]")
		quit(1)
		return
	_data = GameData.open(StringName(args[0].to_lower()))
	if _data == null:
		push_error("No usable imported cache for %s." % args[0])
		quit(1)
		return
	var maps: Array[Vector2i] = []
	for index: int in range(1, args.size(), 2):
		if index + 1 >= args.size():
			break
		maps.append(Vector2i(int(args[index]), int(args[index + 1])))
	if maps.is_empty():
		maps = DEFAULT_MAPS.duplicate()
	for map_id: Vector2i in maps:
		_trace_map(map_id.x, map_id.y)
	quit(0)


func _trace_map(group: int, number: int) -> void:
	var map: Gen2WorldMap = _data.world_map(group, number)
	if map == null:
		print("MISSING MAP %d/%d" % [group, number])
		return
	print("\n=== MAP %d/%d bank=%d scripts=%s ===" % [
		group, number, int(map.events.get("bank", 0)), JSON.stringify(map.scripts),
	])
	for callback: Dictionary in map.scripts.get("callbacks", []):
		_trace_pointer(
			int(map.scripts.get("bank", 0)), int(callback.get("script", 0)),
			"callback type=%d" % int(callback.get("type", -1))
		)
	for scene: Dictionary in map.scripts.get("scenes", []):
		_trace_pointer(
			int(map.scripts.get("bank", 0)), int(scene.get("script", 0)),
			"scene id=%d" % int(scene.get("id", -1))
		)
	var events: Dictionary = map.events
	for kind: String in ["coord_events", "bg_events", "objects"]:
		for event: Dictionary in events.get(kind, []):
			if not event.has("script"):
				continue
			var label := "%s cell=(%d,%d)" % [
				kind, int(event.get("x", -1)), int(event.get("y", -1)),
			]
			if kind == "objects":
				label = "%s index=%d cell=(%d,%d) flag=%d sprite=%d" % [
					kind, (events[kind] as Array).find(event), int(event.get("x", -1)),
					int(event.get("y", -1)), int(event.get("event_flag", -1)),
					int(event.get("sprite", -1)),
				]
			_trace_pointer(
				int(events.get("bank", map.events.get("bank", 0))),
				int(event.get("script", 0)), label
			)


func _trace_pointer(bank: int, address: int, label: String) -> void:
	var key := "%d:%04X" % [bank, address]
	if _seen.has(key):
		print("SCRIPT %s %s (already traced)" % [label, key])
		return
	_seen[key] = true
	var raw: PackedByteArray = _data.world_script(bank, address)
	print("\nSCRIPT %s %s bytes=%d" % [label, key, raw.size()])
	if raw.is_empty():
		print("  MISSING")
		return
	var offset: int = 0
	for step: int in MAX_COMMANDS:
		var command: Dictionary = Gen2WorldScript.command_at(raw, offset, _data.id == &"crystal")
		if not bool(command.get("ok", false)):
			print("  @%d INVALID %s" % [offset, JSON.stringify(command)])
			break
		var display := command.duplicate(true)
		display.erase("ok")
		display.erase("offset")
		display.erase("width")
		print("  @%d %s" % [offset, JSON.stringify(display)])
		_print_text_pointer(bank, command)
		offset += int(command["width"])
		if Gen2WorldScript.is_terminal(int(command["opcode"]), _data.id == &"crystal"):
			break
		if offset >= raw.size():
			break


func _print_text_pointer(default_bank: int, command: Dictionary) -> void:
	var name := StringName(command.get("name", &""))
	if name not in [
		&"writetext", &"farwritetext",
		&"farjumptext", &"jumptext", &"jumptextfaceplayer",
	]:
		return
	var bank: int = int(command.get("bank", default_bank))
	var address: int = int(command.get("address", 0))
	var raw: PackedByteArray = _data.world_text(bank, address)
	var decoded: Dictionary = Gen2WorldScript.decode_text(raw)
	print("    TEXT %d:%04X %s" % [bank, address, JSON.stringify(decoded)])
