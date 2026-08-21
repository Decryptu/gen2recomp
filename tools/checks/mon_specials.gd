extends RefCounted

var _r: RefCounted = null

## Verifies the two specials that open `SelectMonFromParty` against freshly
## imported real caches: the boxes each prints, the markers they carry, and every
## map script in the corpus that reaches either, rather than a sampled one.
##
## Expected values come from the pinned pokecrystal and pokegold sources:
## `engine/events/name_rater.asm` and `engine/events/move_deleter.asm`,
## `data/text/common_2.asm`'s ten `_NameRater*` texts and `common_3.asm`'s eight
## `_Deleter*` ones, `data/events/special_pointers.asm`, and the two
## `*NameRater.asm` maps beside `MoveDeletersHouse.asm`.
##
## One pinned address per cartridge finds every text, so what says the address is
## right is the content, the way the mart's own topic reads its stubs. The corpus
## half is the script sweep: the Name Rater's index differs by one between the two
## command profiles where the deleter's does not, so a wrong normalization shows
## up as a map reaching a different routine, and the surrounding `opentext`/`waitbutton`/`closetext` is
## what says the ending text is pressed once rather than twice.
##
##   Godot --headless --path . -s res://tools/validate.gd -- mon_specials

## Enough of each of the Name Rater's boxes to say which stub decoded. His two
## questions and the three endings that need no new name are the branches a
## reading gets wrong.
const EXPECTED_TEXT_OPENINGS: Dictionary = {
	"hello": "Hello, hello! I'm",
	"which_mon": "Which POKéMON's",
	"better_name": "Hm… ",
	"what_name": "All right. What",
	"finished": "That's a better",
	"come_again": "OK, then. Come",
	"perfect_name": "Hm… ",
	"egg": "Whoa… That's just",
	"same_name": "It might look the",
	"named": "All right. This",
}

## How many `text_ram wStringBuffer1` each of his boxes carries. `_NameRaterPerfectNameText`
## is the one with two, which is why the screen fills every marker rather than
## the first.
const EXPECTED_MARKERS: Dictionary = {
	"hello": 0,
	"which_mon": 0,
	"better_name": 1,
	"what_name": 0,
	"finished": 0,
	"come_again": 0,
	"perfect_name": 2,
	"egg": 0,
	"same_name": 0,
	"named": 1,
}

## `maps/GoldenrodNameRater.asm` and `maps/LavenderNameRater.asm` for one,
## `maps/MoveDeletersHouse.asm` for the other. Both counts are the same on every
## cartridge.
const EXPECTED_SITES: Dictionary = {"name_rater": 2, "move_deleter": 1}

## The move deleter's own eight, read the same way.
const EXPECTED_DELETER_OPENINGS: Dictionary = {
	"knows_one": "That POKéMON knows",
	"ask_delete": "Oh, make it forget",
	"forgot": "Done! Your POKéMON",
	"egg": "An EGG doesn't",
	"come_again": "No? Come visit me",
	"which_move": "Which move should",
	"intro": "Um… Oh, yes, I'm",
	"which_mon": "Which POKéMON?",
}

## `_AskDeleteMoveText` is the one of the eight that names `wStringBuffer1`.
const EXPECTED_DELETER_MARKERS: Dictionary = {
	"knows_one": 0, "ask_delete": 1, "forgot": 0, "egg": 0,
	"come_again": 0, "which_move": 0, "intro": 0, "which_mon": 0,
}

## The commands each site wraps the special in, in order. `waitbutton` is what
## presses the ending text `PrintText` left standing.
const EXPECTED_SHAPE: Array[String] = ["special", "waitbutton", "closetext"]

## The Crystal-canonical index each routine's special is numbered with.
const INDEX_OF: Dictionary = {
	"name_rater": Gen2WorldScriptRunner.SPECIAL_NAME_RATER,
	"move_deleter": Gen2WorldScriptRunner.SPECIAL_MOVE_DELETION,
}


func run(r: RefCounted) -> void:
	_r = r
	for game_id: StringName in _r.GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_r.game_id = game_id
		_verify_texts(data)
		_verify_deleter_texts(data)
		_verify_sites(data, game_id == &"crystal")
	_r.game_id = &""


func _verify_texts(data: GameData) -> void:
	var decoded: int = 0
	for name: String in RomLayout.NAME_RATER_TEXT_ORDER:
		if not data.name_rater_text(name).is_empty():
			decoded += 1
	_r.check(
		decoded == RomLayout.NAME_RATER_TEXT_ORDER.size(),
		"%d of %d Name Rater texts decoded" % [
			decoded, RomLayout.NAME_RATER_TEXT_ORDER.size(),
		]
	)
	for name: String in EXPECTED_TEXT_OPENINGS:
		var text: String = data.name_rater_text(name)
		_r.check(
			text.begins_with(String(EXPECTED_TEXT_OPENINGS[name])),
			"text %s opens \"%s\", not \"%s\"" % [
				name, text.substr(0, 24), EXPECTED_TEXT_OPENINGS[name],
			]
		)
	for name: String in EXPECTED_MARKERS:
		var markers: int = data.name_rater_text(name).count(Gen2TextStream.RAM_MARKER)
		_r.check(
			markers == int(EXPECTED_MARKERS[name]),
			"text %s carries %d nickname markers, not %d" % [
				name, markers, EXPECTED_MARKERS[name],
			]
		)
		## Every one of them has to be fillable, or the player is shown the
		## marker itself.
		var filled: String = Gen2TextStream.fill_all_markers(
			data.name_rater_text(name), Gen2TextStream.RAM_MARKER, "NICKNAME"
		)
		_r.check(
			not filled.contains(Gen2TextStream.RAM_MARKER),
			"text %s still carries a marker once filled" % name
		)


func _verify_deleter_texts(data: GameData) -> void:
	var decoded: int = 0
	for name: String in RomLayout.MOVE_DELETER_TEXT_ORDER:
		if not data.move_deleter_text(name).is_empty():
			decoded += 1
	_r.check(
		decoded == RomLayout.MOVE_DELETER_TEXT_ORDER.size(),
		"%d of %d move deleter texts decoded" % [
			decoded, RomLayout.MOVE_DELETER_TEXT_ORDER.size(),
		]
	)
	for name: String in EXPECTED_DELETER_OPENINGS:
		var text: String = data.move_deleter_text(name)
		_r.check(
			text.begins_with(String(EXPECTED_DELETER_OPENINGS[name])),
			"deleter text %s opens \"%s\", not \"%s\"" % [
				name, text.substr(0, 24), EXPECTED_DELETER_OPENINGS[name],
			]
		)
	for name: String in EXPECTED_DELETER_MARKERS:
		var markers: int = data.move_deleter_text(name).count(Gen2TextStream.RAM_MARKER)
		_r.check(
			markers == int(EXPECTED_DELETER_MARKERS[name]),
			"deleter text %s carries %d move-name markers, not %d" % [
				name, markers, EXPECTED_DELETER_MARKERS[name],
			]
		)


## Every cached script on the cartridge, walked for the two specials this topic
## owns.
func _verify_sites(data: GameData, crystal_commands: bool) -> void:
	var scripts: Variant = RomCache.read_json(RomCache.world_scripts_path(data.directory))
	if not scripts is Dictionary:
		_r.fail("the script table is missing")
		return
	var sites: Dictionary = {"name_rater": 0, "move_deleter": 0}
	var shaped: int = 0
	var total: int = 0
	for raw_key: Variant in (scripts as Dictionary):
		var parts: PackedStringArray = String(raw_key).split(":")
		if parts.size() != 2:
			continue
		var bytes: PackedByteArray = data.world_script(
			int(parts[0]), ("0x%s" % parts[1]).hex_to_int()
		)
		var names: PackedStringArray = _commands_from(bytes, crystal_commands)
		for routine: String in sites:
			var at: int = _special_at(bytes, crystal_commands, INDEX_OF[routine])
			if at < 0:
				continue
			sites[routine] = int(sites[routine]) + 1
			total += 1
			if names.slice(at, at + EXPECTED_SHAPE.size()) \
				== PackedStringArray(EXPECTED_SHAPE):
				shaped += 1
	for routine: String in EXPECTED_SITES:
		_r.check(
			int(sites[routine]) == int(EXPECTED_SITES[routine]),
			"%d scripts reach the %s special, not %d" % [
				sites[routine], routine, EXPECTED_SITES[routine],
			]
		)
	_r.check(
		shaped == total,
		"%d of %d scripts are opentext/special/waitbutton/closetext" % [shaped, total]
	)


## The command names one script's bytes decode to, stopping where the walk does.
func _commands_from(bytes: PackedByteArray, crystal_commands: bool) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var offset: int = 0
	var steps: int = 0
	while offset < bytes.size() and steps < Gen2WorldScript.MAX_COMMANDS:
		var command: Dictionary = Gen2WorldScript.command_at(bytes, offset, crystal_commands)
		if not bool(command.get("ok", false)):
			break
		out.append(String(command.get("name", "")))
		steps += 1
		offset += int(command["width"])
		if Gen2WorldScript.is_terminal(int(command["opcode"]), crystal_commands):
			break
	return out


## Which command index [param special] sits at, or -1. The operand is normalized
## before it is compared, so Gold and Silver's Name Rater at 86 and Crystal's at
## 87 are the same site.
func _special_at(bytes: PackedByteArray, crystal_commands: bool, special: int) -> int:
	var offset: int = 0
	var index: int = 0
	while offset < bytes.size() and index < Gen2WorldScript.MAX_COMMANDS:
		var command: Dictionary = Gen2WorldScript.command_at(bytes, offset, crystal_commands)
		if not bool(command.get("ok", false)):
			return -1
		if String(command.get("name", "")) == "special" \
			and Gen2WorldScript.special_index(
				int(command.get("value", -1)), crystal_commands
			) == special:
			return index
		index += 1
		offset += int(command["width"])
		if Gen2WorldScript.is_terminal(int(command["opcode"]), crystal_commands):
			return -1
	return -1
