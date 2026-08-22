extends RefCounted

var _r: RefCounted = null

## Every effect byte's command list against the pins' own `data/moves/effects.asm`.
##
##   Godot --headless --path . -s res://tools/validate.gd -- move_effects
##
## A move is a short program and [Gen2MoveEffect] is the whole table of them
## transcribed by hand, so the comparable artefact is the command list itself:
## the pin's `MoveEffectsPointers` in order, each label's commands resolved
## through its fallthrough, against [method Gen2MoveEffect.sequence_for]. That
## catches a step in the wrong place, which no unit test of one move can, and it
## is the static half of the battle-command trace
## `.claude/oracle/battle/trace_move_commands.py` runs against a real cartridge.
##
## `pokecrystal` and `pokegold` ship the same two files byte for byte, so the
## corpus is one table read against all three caches.
##
## The checkouts are local-only, so a missing one skips rather than fails.

const PINS: Dictionary = {
	&"gold": "pokegold", &"silver": "pokegold", &"crystal": "pokecrystal",
}

## Cartridge commands this port spends inside another step, and the one it runs
## in front of the list. A row here is a claim that the step still happens, only
## not as a command of its own; anything not in it and not a name we use is an
## unread step and fails.
const FOLDED: Dictionary = {
	# `CheckTurn` is called before `DoMove` and `checkobedience` is the first
	# command of every list; both are the once-per-action gate `Gen2Battle._act`
	# runs as `checkstatus` in front of the sequence.
	&"checkturn": "",
	&"checkobedience": "",
	# Text and pacing. Every one of these prints what the step in front of it
	# decided, and here that step emits its own event.
	&"failuretext": "",
	&"criticaltext": "",
	&"supereffectivetext": "",
	&"supereffectivelooptext": "",
	# `checkhit` ends a missed move here, so the line `bidefailtext` would print
	# is the one that step already emitted.
	&"bidefailtext": "",
	&"cleartext": "",
	&"movedelay": "",
	# `wCurDamage` is not carried across a miss here: a missed turn ends before
	# anything reads it, so there is nothing to clear.
	&"clearmissdamage": "",
	# Renames, where the same step is named for what it does rather than for the
	# register it writes.
	&"constantdamage": "fixeddamage",
	&"eatdream": "draintarget",
	&"resetstats": "haze",
	&"rechargenextturn": "recharge",
	&"checkrollout": "rolloutcheck",
	&"checkcharge": "chargemove",
	&"poison": "poisontarget",
	&"paralyze": "paralyzetarget",
	&"confuse": "confusetarget",
	&"raisesubnoanim": "raisesub",
	&"healmorn": "timedheal",
	&"healday": "timedheal",
	&"healnite": "timedheal",
	&"doubleflyingdamage": "doubledamage",
	&"doubleundergrounddamage": "doubledamage",
	&"doubleminimizedamage": "doubledamage",
}

## `toxictarget` is the second half of `BattleCommand_Poison`, which reads the
## effect byte back to decide between a flat poison and a ramping one; the two
## readings are two commands here and one there.
##
## `checkimmune` is this port's own, and the one command with no cartridge name:
## `BattleCommand_Stab` writes `wAttackMissed` when the matchup is zero and the
## later steps read it back, so the immunity is split out of `stab` here rather
## than carried in a register. It is dropped from our side before the lists are
## compared.
const OURS_ONLY: Array[String] = ["checkimmune"]

## Ours named for what it does where the pin names the register it writes.
const RENAMED: Dictionary = {&"toxictarget": "poisontarget"}


func run(r: RefCounted) -> void:
	_r = r
	var root: String = _reference_root()
	var compared: int = 0
	for game_id: StringName in _r.GAME_IDS:
		var pin: String = root.path_join(String(PINS[game_id]))
		if not DirAccess.dir_exists_absolute(pin):
			print("%s is not checked out, so nothing was compared." % pin.get_file())
			continue
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_r.game_id = game_id
		compared += _compare(pin, data)
		_r.game_id = &""
	if compared == 0:
		print("no pin was checked out; move_effects compared nothing.")


func _compare(pin: String, data: GameData) -> int:
	var lists: Array = _lists(pin)
	if lists.is_empty():
		_r.fail("%s carries no move effect table." % pin.get_file())
		return 0
	var carried: Dictionary = _effects_in_use(data)
	var mismatched: int = 0
	## Effect bytes with a list of their own that no move in the table carries,
	## so nothing in the game can run one. Named rather than counted: the pair is
	## `DefrostOpponent` and `FakeOut`, and a third appearing means a move lost
	## its effect byte on import.
	var unused: PackedStringArray = []
	for effect: int in lists.size():
		var row: Dictionary = lists[effect]
		var want: PackedStringArray = row["commands"]
		var have: PackedStringArray = PackedStringArray()
		for command: StringName in Gen2MoveEffect.sequence_for(effect):
			if OURS_ONLY.has(String(command)):
				continue
			have.append(String(RENAMED.get(command, command)))
		if want == have:
			continue
		if not carried.has(effect):
			unused.append("%d (%s)" % [effect, row["label"]])
			continue
		mismatched += 1
		_r.fail("effect %d (%s)\n      pin: %s\n      ours: %s" % [
			effect, row["label"], " ".join(want), " ".join(have),
		])
	_r.check(
		unused.size() == 2,
		"%d effect lists are carried by no move, not 2: %s" % [unused.size(), " ".join(unused)]
	)
	_r.note("%d effect lists, %d differ; %s are carried by no move." % [
		lists.size(), mismatched, " ".join(unused),
	])
	return lists.size()


## Every effect byte at least one move in the cache carries. An effect no move
## names cannot be reached in play, so a list that differs there is a gap rather
## than a defect and is counted instead of failed.
func _effects_in_use(data: GameData) -> Dictionary:
	var out: Dictionary = {}
	for number: int in range(1, 252):
		var move: Dictionary = data.move(number)
		if move.is_empty():
			continue
		out[int(move.get("effect", 0))] = true
	return out


## `MoveEffectsPointers` in order, each label's commands resolved through the
## fallthrough a list without an `endmove` of its own takes.
func _lists(pin: String) -> Array:
	var commands: Dictionary = _command_names(pin)
	if commands.is_empty():
		return []
	var order: PackedStringArray = []
	var bodies: Dictionary = {}
	var label: String = ""
	for line: String in _lines(pin.path_join("data/moves/effects.asm")):
		if line.ends_with(":"):
			label = line.trim_suffix(":")
			order.append(label)
			bodies[label] = PackedStringArray()
			continue
		var word: String = line.split(" ")[0]
		if commands.has(word) and label != "":
			bodies[label].append(word)
	# A label with no `endmove` of its own runs on into the next one, and an
	# empty label is that list under a second name.
	for index: int in range(order.size() - 1, -1, -1):
		var body: PackedStringArray = bodies[order[index]]
		if body.is_empty() or body[body.size() - 1] != "endmove":
			if index + 1 < order.size():
				body.append_array(bodies[order[index + 1]])
				bodies[order[index]] = body
	var out: Array = []
	for line: String in _lines(pin.path_join("data/moves/effects_pointers.asm")):
		if not line.begins_with("dw "):
			continue
		var target: String = line.substr(3).strip_edges()
		if not bodies.has(target):
			_r.fail("effects_pointers names %s, which effects.asm does not define." % target)
			return []
		out.append({"label": target, "commands": _normalise(bodies[target])})
	return out


## The pin's list as the names this port uses, with the steps it spends inside
## another one dropped.
func _normalise(body: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = []
	for word: String in body:
		var name: String = word
		if FOLDED.has(StringName(word)):
			name = String(FOLDED[StringName(word)])
		if name == "":
			continue
		out.append(name)
	return out


## `macros/scripts/battle_commands.asm`, which is what tells a command apart from
## a label or a directive in the effect table.
func _command_names(pin: String) -> Dictionary:
	var out: Dictionary = {}
	for line: String in _lines(pin.path_join("macros/scripts/battle_commands.asm")):
		if line.begins_with("command "):
			out[line.substr(8).strip_edges()] = true
	return out


func _lines(path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return out
	while not file.eof_reached():
		var line: String = file.get_line()
		var comment: int = line.find(";")
		if comment >= 0:
			line = line.substr(0, comment)
		line = line.strip_edges()
		if line != "":
			out.append(line)
	return out


## `.references/` by default, the same root `tools/fetch_reference_sources.sh`
## and `docs/REFERENCES.md` use.
func _reference_root() -> String:
	var override: String = OS.get_environment("GEN2_REFERENCE_ROOT")
	if override != "":
		return override
	return ProjectSettings.globalize_path("res://").path_join(".references")
