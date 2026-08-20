class_name Gen2Rules
extends RefCounted

## Which behaviour a run is played under, where this project and the cartridge
## disagree on purpose.
##
## Separate from [Gen2Options], which is the installation's own settings: a rule
## changes what the engine DOES, so it belongs to the run that produced a save
## rather than to whichever machine is playing it. `HANDOFF.md`'s divergence table
## is what becomes named flags here, one at a time, each with a live branch on
## both sides and a test on each.
##
## Every flag is named for the cartridge's behaviour and answers "reproduce the
## hardware", so a flag that is off is this project's own corrected answer. That
## way a flag added later cannot silently change what an existing run did: the
## default for a new flag is whatever [constant MODE_CURRENT] says, which is the
## behaviour that shipped before the flag existed.

## Every named flag, mapped to what [constant MODE_CURRENT] does today. The
## descriptions belong beside the branch, not here; each key names the
## `docs/bugs_and_glitches.md` entry it switches.
const FLAGS: Dictionary = {
	## `BattleCommand_BellyDrum` calls `BattleCommand_AttackUp2` BEFORE the HP
	## check, so a failed Belly Drum has already raised Attack by two stages.
	&"belly_drum_boosts_below_half_hp": false,
	## `CalcExpAtLevel` runs its formula at level 1, where the medium slow curve's
	## `- 140` underflows three bytes.
	&"medium_slow_level_one_underflow": false,
	## `AI_Cautious`'s `ret nc` abandons the remaining move slots on a failed
	## roll rather than moving on to the next one.
	&"cautious_ai_abandons_remaining_moves": false,
	## `ShortHPBar_CalcPixelFrame`'s off-by-one, which changes the HP NUMBER
	## printed mid-drain under a 48-pixel maximum and never the bar.
	&"short_hp_bar_number_off_by_one": false,
	## `DittoMetalPowder` runs past `TruncateHL_BC`, so a defence byte over 170
	## carries, halves the attack and folds back below where it started.
	&"metal_powder_overflow": true,
}

## What each flag is, for a player choosing one. Keyed like [constant FLAGS] and
## in its order: `title` names the bug and `detail` says what the CARTRIDGE does,
## which is what the flag reproduces when it is on. Said without a source symbol,
## because the symbols are beside the branches; this is the only wording a
## settings screen has, so a second copy in the launcher would go stale.
const FLAG_TEXT: Dictionary = {
	&"belly_drum_boosts_below_half_hp": {
		"title": "Belly Drum below half HP",
		"detail": "Attack is raised by two stages before the HP is checked, so a"
			+ " Belly Drum that fails for want of HP has already paid the boost.",
	},
	&"medium_slow_level_one_underflow": {
		"title": "Medium Slow at level 1",
		"detail": "The experience formula is run at level 1, where the medium slow"
			+ " curve underflows and asks for about 16 million points.",
	},
	&"cautious_ai_abandons_remaining_moves": {
		"title": "Cautious trainer AI",
		"detail": "A trainer weighing its moves stops at the first one a roll"
			+ " passes over, leaving the rest of them unscored.",
	},
	&"short_hp_bar_number_off_by_one": {
		"title": "Short HP bar's number",
		"detail": "The HP number printed while a short bar drains is rounded down"
			+ " where the rest of the routine rounds up, so it reads one low."
			+ " Never the bar itself.",
	},
	&"metal_powder_overflow": {
		"title": "Metal Powder on Ditto",
		"detail": "Boosting a Defense above 170 overflows, halves the attacker's"
			+ " Attack instead and folds the defence back below where it started.",
	},
}

## `HANDOFF.md`'s mutual recoil faint row is deliberately NOT here: the award pass
## already refuses a fainted recipient, so clearing the participant as
## `UpdateFaintedPlayerMon` does changes no outcome that can be observed. It
## becomes a flag when turn-event ordering makes the difference visible, and a
## flag with both sides identical would be scaffolding.

## What each mode answers for a flag. `current` is what shipped and is the
## default; `vanilla` reproduces every listed bug; `qol` corrects every one.
const MODE_CURRENT: StringName = &"current"
const MODE_VANILLA: StringName = &"vanilla"
const MODE_QOL: StringName = &"qol"
## Not a mode a player picks: what [method mode_of] answers once a flag has been
## moved away from every preset.
const MODE_CUSTOM: StringName = &"custom"
const MODES: Array[StringName] = [MODE_CURRENT, MODE_VANILLA, MODE_QOL]

## Which AI layers a trainer scores with. `normal` is the trainer class's own
## imported mask, which is the cartridge's; the other two rewrite it rather than
## inventing numbers, since a level or a stat this project made up would not be
## this cartridge's game any more.
const DIFFICULTY_EASY: StringName = &"easy"
const DIFFICULTY_NORMAL: StringName = &"normal"
const DIFFICULTY_HARD: StringName = &"hard"
const DIFFICULTIES: Array[StringName] = [DIFFICULTY_EASY, DIFFICULTY_NORMAL, DIFFICULTY_HARD]

## `easy` keeps `AI_BASIC` alone, which is what the cartridge's own least
## thoughtful classes carry, and `hard` adds every layer a class does not already
## have. Neither can produce a mask the scorer does not understand, both being
## subsets of the imported one's own bits.
const DIFFICULTY_EASY_WEIGHTS: int = RomLayout.AI_BASIC
const DIFFICULTY_HARD_WEIGHTS: int = RomLayout.AI_MOVE_WEIGHTS_MASK

## The rules the engine is playing under right now.
##
## Statics reach the run through here: [Gen2Experience], [Gen2Damage] and
## [Gen2BattleAI] take no engine object, and threading a rules argument through
## every one of them would put the same value in two places to disagree. So there
## is exactly one installed set at a time, and the two objects that own a run
## ([Gen2WorldAPI] and [Gen2Battle]) install what they were built with.
static var _active: Gen2Rules = null

var mode: StringName = MODE_CURRENT
var difficulty: StringName = DIFFICULTY_NORMAL
## Only the flags moved away from [member mode], so a mode change carries every
## flag the player never touched.
var overrides: Dictionary = {}


## The installed rules, which are [constant MODE_CURRENT]'s until something
## installs otherwise. Never null, so a caller never branches on having a run.
static func active() -> Gen2Rules:
	if _active == null:
		_active = Gen2Rules.new()
	return _active


## Plays under [param rules]. A null one restores the shipped behaviour, which is
## what a tool, a check or a test with no run of its own wants.
static func install(rules: Gen2Rules) -> void:
	_active = rules


## Whether the cartridge's behaviour is reproduced for [param flag]. An unknown
## flag answers false rather than crashing: a mod or a save may name one this
## build does not have.
func reproduces(flag: StringName) -> bool:
	if not FLAGS.has(flag):
		return false
	if overrides.has(flag):
		return bool(overrides[flag])
	return _mode_value(mode, flag)


## Reads the installed rules, for a static that has no run object in hand.
static func hardware(flag: StringName) -> bool:
	return active().reproduces(flag)


## Moves one flag off its mode. Refuses a flag this build does not name, so a
## typo in a mod is a refusal rather than a setting that silently does nothing.
func set_flag(flag: StringName, reproduce_hardware: bool) -> bool:
	if not FLAGS.has(flag):
		return false
	if _mode_value(mode, flag) == reproduce_hardware:
		overrides.erase(flag)
	else:
		overrides[flag] = reproduce_hardware
	return true


## The mode the flags actually describe, which is [constant MODE_CUSTOM] once one
## of them is not any preset's answer. What a settings row shows.
func mode_of() -> StringName:
	for candidate: StringName in MODES:
		var all_match: bool = true
		for flag: StringName in FLAGS:
			if reproduces(flag) != _mode_value(candidate, flag):
				all_match = false
				break
		if all_match:
			return candidate
	return MODE_CUSTOM


## Switches every flag the player has not moved. The overrides are kept, which is
## what makes a mode a starting point rather than a reset; [method clear_flags]
## is the reset.
func set_mode(new_mode: StringName) -> void:
	mode = new_mode if MODES.has(new_mode) else MODE_CURRENT
	for flag: StringName in overrides.keys():
		if _mode_value(mode, flag) == bool(overrides[flag]):
			overrides.erase(flag)


func clear_flags() -> void:
	overrides = {}


## The AI layers a trainer class scores with, its imported mask under
## [constant DIFFICULTY_NORMAL]. Masked to the layers the scorer knows either
## way, so a patched trainer cannot ask for a bit nothing reads.
func ai_move_weights(imported: int) -> int:
	match difficulty:
		DIFFICULTY_EASY:
			return DIFFICULTY_EASY_WEIGHTS
		DIFFICULTY_HARD:
			return DIFFICULTY_HARD_WEIGHTS
	return imported & RomLayout.AI_MOVE_WEIGHTS_MASK


func duplicate_rules() -> Gen2Rules:
	var out := Gen2Rules.new()
	out.mode = mode
	out.difficulty = difficulty
	out.overrides = overrides.duplicate()
	return out


func matches(other: Gen2Rules) -> bool:
	if other == null:
		return false
	if difficulty != other.difficulty:
		return false
	for flag: StringName in FLAGS:
		if reproduces(flag) != other.reproduces(flag):
			return false
	return true


## Only what differs from the mode, so a saved run stays readable and a flag
## added later is not written into a file that never chose it.
func to_dict() -> Dictionary:
	var flags: Dictionary = {}
	for flag: StringName in overrides:
		flags[String(flag)] = bool(overrides[flag])
	return {
		"mode": String(mode),
		"difficulty": String(difficulty),
		"flags": flags,
	}


## Clamped rather than refused, the way [method Gen2Options.parse] is: one
## unreadable value must not cost the player the rest of the block.
static func parse(raw: Variant) -> Gen2Rules:
	var out := Gen2Rules.new()
	if raw is not Dictionary:
		return out
	var row: Dictionary = raw
	var raw_mode := StringName(String(row.get("mode", "")))
	out.mode = raw_mode if MODES.has(raw_mode) else MODE_CURRENT
	var raw_difficulty := StringName(String(row.get("difficulty", "")))
	out.difficulty = raw_difficulty if DIFFICULTIES.has(raw_difficulty) else DIFFICULTY_NORMAL
	var flags: Variant = row.get("flags", {})
	if flags is Dictionary:
		for key: Variant in flags as Dictionary:
			out.set_flag(StringName(String(key)), bool((flags as Dictionary)[key]))
	return out


## `current` is the table itself; `vanilla` and `qol` are its two ends.
static func _mode_value(for_mode: StringName, flag: StringName) -> bool:
	match for_mode:
		MODE_VANILLA:
			return true
		MODE_QOL:
			return false
	return bool(FLAGS.get(flag, false))
