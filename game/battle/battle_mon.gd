class_name Gen2BattleMon
extends RefCounted

## One Pokémon as a battle sees it: its stats, what it knows, how much of it is
## left, and how far its stats have been pushed around.
##
## [RefCounted] and scene-free, reading cartridge content through [GameData] and
## never a ROM.
##
## Stats are worked out once, at build time, because that is when the cartridge
## works them out; only a level up recalculates them. Stages are applied on the
## way out, to the unmodified stat every time, which is why they are stored
## separately rather than folded in.

## What a Pokémon can carry into a battle, which is the same four slots
## [Gen2Learnset] fills.
const MAX_MOVES: int = Gen2Learnset.MOVE_SLOTS

## The stats a stage can be applied to, in the order the cartridge keeps them.
const STAGED_STATS: Array = ["attack", "defense", "speed", "sp_attack", "sp_defense"]

## Accuracy and evasion are staged like a stat and are not stats: they have their
## own multiplier table, and there is no number behind them for a stage to
## multiply. They are kept in the same place because a battle raises and lowers
## all seven the same way. See [Gen2Accuracy].
const STAGED_ODDS: Array = ["accuracy", "evasion"]

## Every DV at its maximum. A caller that has not said otherwise gets a Pokémon
## that is as good as its species allows, which is the useful default for a test
## and for a screen with nothing behind it yet. A wild encounter rolls its own;
## see [method random_dvs].
const PERFECT_DVS: int = 0xFFFF

## `BASE_HAPPINESS` (`constants/pokemon_data_constants.asm`), what a Pokémon
## starts at and what a wild or trainer Pokémon is given outright.
const BASE_HAPPINESS: int = 70

var data: GameData = null

var species: int = 0
var level: int = 1
var dvs: int = PERFECT_DVS
var stat_exp: Dictionary = {}

## Total experience on this species' growth curve. Seeded at [method create] to
## what [param at_level] starts with, not zero: a level 7 Pidgey carries level
## 7's threshold, so the box and party screens agree with its level rather than
## reading level 1 until its first battle.
@warning_ignore("shadowed_global_identifier")
var exp: int = 0

## Move numbers and the PP left in each, one to one.
var moves: Array = []
var pp: Array = []

var hp: int = 0
var stats: Dictionary = {}
var stages: Dictionary = {}

## The status byte, as the cartridge packs it: see [Gen2Status]. It survives a
## switch and a battle, unlike a stage, which is why it sits with the health
## rather than with them.
var status: int = Gen2Status.NONE

## The second byte: see [Gen2Substatus]. Unlike [member status] this one clears
## on a switch, along with the counters below it, which is what makes it
## volatile rather than a status.
var substatus: int = Gen2Substatus.NONE

## How many turns of confusion are left, meaningful only while
## [constant Gen2Substatus.CONFUSED] is set.
var confusion_turns: int = 0

## The move a two-turn move locked this Pokémon into, meaningful only while
## [constant Gen2Substatus.CHARGING] is set. Zero means nothing is charged.
var charged_move: int = 0

## How many successful hits the current Rollout has made. Zero means the next
## Rollout hit is its first; a completed or interrupted chain resets this before
## the next Rollout starts.
var rollout_count: int = 0

## How many turns remain after the move that started a rampage. The move number
## is kept separately so the next turns can force the exact move used to start
## it, whether it was Thrash, Petal Dance or Outrage.
var rampage_turns: int = 0
var rampage_move: int = 0

## How many turns a badly poisoned Pokémon has been poisoned, which is what
## Toxic's damage ramps on. Zero unless actually toxic.
var toxic_counter: int = 0

## Which move slot Disable has locked, or -1 for none: -1 rather than 0 so
## "nothing disabled" is never confusable with the first slot, and so this alone
## answers whether anything is disabled, the way `wDisabledMove` does.
var disabled_slot: int = -1
## How many turns [member disabled_slot] stays locked.
var disable_turns: int = 0

## Which move slot Encore has locked, or -1 for none, the same shape as
## [member disabled_slot]. Meaningful only while
## [constant Gen2Substatus.ENCORED] is set.
var encored_slot: int = -1
## How many turns [member encored_slot] stays locked.
var encore_turns: int = 0

## `wPlayerWrapCount` and `wPlayerTrappingMove`: how many turns this Pokémon
## stays bound by Bind, Wrap, Fire Spin, Clamp or Whirlpool, and which of them
## bound it. On the Pokémon that is trapped rather than the one that trapped it,
## which is the side `BattleCommand_TrapTarget` writes.
var trapped_turns: int = 0
var trapping_move: int = 0

## `wPlayerPerishCount`: how many turn ends this Pokémon has left before Perish
## Song finishes it. Read only while [constant Gen2Substatus.PERISH] is set.
var perish_count: int = 0

## `wPlayerSubstituteHP`: what the doll in front of this Pokémon has left. Read
## only while [constant Gen2Substatus.SUBSTITUTE] is set, which is why clearing
## both in [method reset_volatile] matches a cartridge that clears the flag and
## leaves the byte, the way [member perish_count] already does.
var substitute_hp: int = 0

## `wPlayerTurnsTaken`: how many turns this Pokémon has actually acted on since
## it came out. `BattleCommand_DoTurn` is the one place it rises, behind the same
## charging check that decides whether PP is spent, so a two-turn release does
## not count twice and Struggle does count. Zeroed on a switch, which is what
## makes "the first turn of this Pokémon" a question the AI can ask.
var turns_taken: int = 0

## The move this Pokémon last used, by move number, or zero for none: what
## Disable and Encore both search a target's own move list for. The cartridge's
## own `wLastPlayerMove`/`wLastEnemyMove` clear on a switch exactly the way this
## does, since a freshly sent-out Pokémon has not used a move yet.
var last_move_used: int = 0

## Mimic replaces one battle move but not the party move behind it. The source
## keeps those in separate structs; this model keeps the original row here so a
## switch and save writeback see the party copy while the active battle sees the
## mimicked one.
var mimicked_slot: int = -1
var mimic_original_move: int = 0
var mimic_original_pp: int = 0

## Conversion and Conversion2 write both type bytes in the active battle
## struct. Empty means the species row still supplies them. A switch clears the
## override with every other field-only change.
var battle_types: Array[int] = []

## The item this Pokémon is holding, by item number, or zero for none. Carried
## through from a trainer's party or a save; nothing in the engine reads it yet.
var item: int = 0

## `wPlayerFuryCutterCount`: how many times in a row Fury Cutter has connected.
## Zeroed on a switch, by a miss (`ResetFuryCutterCount`) and by choosing any
## other move, which is `ParsePlayerAction`'s own `cp EFFECT_FURY_CUTTER`:
## see [method Gen2Battle._reset_action_counters].
var fury_cutter_count: int = 0

## `wPlayerProtectCount`: how many times in a row this Pokémon has used Protect,
## Detect or Endure. `ProtectChance` halves the odds once per count and refuses
## outright at eight, and the same counter serves all three moves, so alternating
## Protect and Endure does not reset it.
var protect_count: int = 0

## `wPlayerMinimized`: whether this Pokémon has used Minimize since it came out,
## which is the whole of what Stomp's doubled damage reads. Set by
## `MinimizeDropSub` off the move being animated rather than off an effect byte,
## since Minimize carries the ordinary `EFFECT_EVASION_UP`. Zeroed on a switch.
var minimized: bool = false

## `wBattleMonHappiness`: what Return and Frustration read for their power, and
## the one field here that is party data rather than battle state, so a switch
## leaves it alone. `LoadEnemyMon.Happiness` writes [constant BASE_HAPPINESS]
## into `wEnemyMonHappiness` for every wild and trainer Pokémon, which is why
## that is the default rather than zero.
var happiness: int = BASE_HAPPINESS


## Builds a Pokémon at a level, at full health, knowing [param moves].
##
## Returns null for a species the cache does not have, because a battle with a
## Pokémon that has no base stats is not something to paper over.
static func create(
	game_data: GameData,
	species_number: int,
	at_level: int,
	known_moves: Array = [],
	dv_word: int = PERFECT_DVS,
	trained: Dictionary = {},
	held_item: int = 0
) -> Gen2BattleMon:
	if game_data == null:
		return null
	if game_data.species(species_number).is_empty():
		return null

	var out := Gen2BattleMon.new()
	out.data = game_data
	out.species = species_number
	out.level = maxi(at_level, 1)
	out.dvs = dv_word
	out.stat_exp = trained
	out.moves = known_moves.slice(0, MAX_MOVES)
	out.item = held_item
	out.reset_stages()
	out.recalculate()
	out.hp = out.max_hp()
	out.restore_pp()
	out.exp = Gen2Experience.total_exp_at(out.growth_rate(), out.level)
	return out


## Four DVs rolled the way a wild encounter rolls them.
static func random_dvs(rng: RandomNumberGenerator) -> int:
	return Gen2Stats.pack_dvs(
		rng.randi_range(0, Gen2Stats.MAX_DV), rng.randi_range(0, Gen2Stats.MAX_DV),
		rng.randi_range(0, Gen2Stats.MAX_DV), rng.randi_range(0, Gen2Stats.MAX_DV)
	)


## Works the six stats out from the base stats, the DVs and the stat experience.
## Called when the Pokémon is built and after a level up, and at no other time:
## a stage is not a change to a stat, it is a lens on one.
func recalculate() -> void:
	var base: Dictionary = data.species(species).get("stats", {})
	stats = {
		"hp": _stat(base, "hp", Gen2Stats.hp_dv(dvs), "hp", true),
		"attack": _stat(base, "attack", Gen2Stats.attack_dv(dvs), "attack"),
		"defense": _stat(base, "defense", Gen2Stats.defense_dv(dvs), "defense"),
		"speed": _stat(base, "speed", Gen2Stats.speed_dv(dvs), "speed"),
		# Special Attack and Special Defense have base stats of their own but
		# share a DV and a stat experience total, which is the half of the
		# special split that Generation 2 did not finish.
		"sp_attack": _stat(base, "sp_attack", Gen2Stats.special_dv(dvs), "special"),
		"sp_defense": _stat(base, "sp_defense", Gen2Stats.special_dv(dvs), "special"),
	}
	hp = mini(hp, max_hp())


func _stat(
	base: Dictionary, key: String, dv: int, exp_key: String, is_hp: bool = false
) -> int:
	return Gen2Stats.calculate(
		int(base.get(key, 0)), dv, int(stat_exp.get(exp_key, 0)), level, is_hp
	)


## A stat as the damage formula sees it, with its stage and then its status
## applied.
##
## The cartridge's order: copy the stat, apply the stage, then halve a burned
## Pokémon's Attack and quarter a paralysed one's Speed. Both land on the copy the
## stages did, which is why a critical hit reading [method unmodified_stat] is
## free of the burn as well as the stages.
func stat(key: String) -> int:
	var value: int = int(stats.get(key, 0))
	if not STAGED_STATS.has(key):
		return value

	var out: int = Gen2Stats.apply_stage(value, int(stages.get(key, 0)))
	if key == "attack" and Gen2Status.has(status, Gen2Status.BURN):
		out = Gen2Status.apply_burn(out)
	elif key == "speed" and Gen2Status.has(status, Gen2Status.PARALYSIS):
		out = Gen2Status.apply_paralysis(out)
	return out


## A stat with no stage applied, which is what a critical hit uses when the
## stages would work against the attacker.
func unmodified_stat(key: String) -> int:
	return int(stats.get(key, 0))


func stage(key: String) -> int:
	return int(stages.get(key, 0))


## Whether [method change_stage] would move anything, asked without moving it:
## `BattleCommand_StatUp` and `..._StatDown` both settle "already at the end" on
## the way in, ahead of the checks that refuse for another reason.
func can_change_stage(key: String, by: int) -> bool:
	if not STAGED_STATS.has(key) and not STAGED_ODDS.has(key):
		return false
	var before: int = int(stages.get(key, 0))
	return clampi(before + by, Gen2Stats.MIN_STAGE, Gen2Stats.MAX_STAGE) != before


## Moves a stage, and answers whether it actually moved: at the top or the bottom
## the cartridge says so rather than silently doing nothing.
func change_stage(key: String, by: int) -> bool:
	if not STAGED_STATS.has(key) and not STAGED_ODDS.has(key):
		return false
	var before: int = int(stages.get(key, 0))
	var after: int = clampi(before + by, Gen2Stats.MIN_STAGE, Gen2Stats.MAX_STAGE)
	stages[key] = after
	return after != before


func reset_stages() -> void:
	stages = {}
	for key: String in STAGED_STATS + STAGED_ODDS:
		stages[key] = 0


## What Baton Pass hands to whoever comes in behind it.
##
## On the cartridge none of this is the Pokémon's: `wPlayerSubStatus1` through
## `5` and every counter beside them are battle-position state, and an ordinary
## entrance clears them only because `NewBattleMonStatus` says so.
## `PassedBattleMonEntrance` and `EnemySwitch_SetMode` do not, which is the whole
## of what Baton Pass is. Here the same state is per-Pokémon, so it is copied
## across instead, and `ResetBatonPassStatus` then names the few things that do
## not survive the trip: see [method Gen2Battle._reset_baton_pass_status].
##
## The list is exactly [method reset_volatile]'s, plus the stages, which is why
## the two sit together: a field added to one belongs in the other.
const PASSED_FIELDS: Array[String] = [
	"substatus", "confusion_turns", "charged_move", "rollout_count",
	"rampage_turns", "rampage_move", "toxic_counter", "disabled_slot",
	"disable_turns", "encored_slot", "encore_turns", "trapped_turns",
	"trapping_move", "perish_count", "substitute_hp", "turns_taken",
	"last_move_used", "fury_cutter_count", "protect_count", "minimized",
]


func capture_passed_state() -> Dictionary:
	var out: Dictionary = {"stages": stages.duplicate()}
	for key: String in PASSED_FIELDS:
		out[key] = get(key)
	return out


func apply_passed_state(state: Dictionary) -> void:
	stages = (state["stages"] as Dictionary).duplicate()
	for key: String in PASSED_FIELDS:
		set(key, state[key])


## Clears everything [Gen2Substatus] holds, and the counters that go with it.
## Called on a switch, alongside but separately from [method reset_stages]:
## Haze resets the stages on both sides without touching either one's
## volatiles, so the two have to stay two calls rather than become one.
func reset_volatile() -> void:
	restore_mimic()
	battle_types = []
	substatus = Gen2Substatus.NONE
	confusion_turns = 0
	charged_move = 0
	rollout_count = 0
	rampage_turns = 0
	rampage_move = 0
	toxic_counter = 0
	disabled_slot = -1
	disable_turns = 0
	encored_slot = -1
	encore_turns = 0
	trapped_turns = 0
	trapping_move = 0
	perish_count = 0
	substitute_hp = 0
	turns_taken = 0
	last_move_used = 0
	fury_cutter_count = 0
	protect_count = 0
	minimized = false


## The gender the cartridge's own `GetGender` would answer, from the species'
## gender ratio and this Pokémon's own Attack and Speed DVs.
##
## Not a coin flip and not a stat total: the cartridge folds the Attack DV into
## one byte's high nibble and the Speed DV into its low nibble, then compares
## that against the species ratio. Ratio 0 is always male and 254 always female
## with no comparison at all; 255 is genderless. Otherwise below the ratio is
## male and at or above it female, so a higher ratio means likelier female.
## [constant Gen2Species.GENDER_UNKNOWN] and the two extremes are named here
## rather than repeated at every caller.
const GENDER_F0: int = 0
const GENDER_F100: int = 254
const GENDER_UNKNOWN: int = 255

const GENDER_MALE: StringName = &"male"
const GENDER_FEMALE: StringName = &"female"
const GENDER_NONE: StringName = &"genderless"


func gender() -> StringName:
	return gender_for(data, species, dvs)


## The same answer for a Pokémon that is not in a battle, so the Hall of Fame's
## induction panel reads the rule from here rather than restating it.
static func gender_for(data_source: GameData, species_number: int, mon_dvs: int) -> StringName:
	var ratio: int = int(
		data_source.species(species_number).get("gender_ratio", GENDER_UNKNOWN)
	)
	if ratio == GENDER_UNKNOWN:
		return GENDER_NONE
	if ratio == GENDER_F0:
		return GENDER_MALE
	if ratio == GENDER_F100:
		return GENDER_FEMALE

	var combined: int = (Gen2Stats.attack_dv(mon_dvs) << 4) | Gen2Stats.speed_dv(mon_dvs)
	return GENDER_MALE if combined < ratio else GENDER_FEMALE


## The two type numbers, which are the same number twice for a single-type
## Pokémon: the cartridge fills both slots either way.
func types() -> Array:
	if battle_types.size() == 2:
		return battle_types.duplicate()
	var entry: Array = data.species(species).get("types", [])
	return [int(entry[0]), int(entry[1])] if entry.size() >= 2 else []


func set_battle_type(type: int) -> void:
	battle_types = [type, type]


func name_text() -> String:
	return String(data.species(species).get("name", ""))


## The curve [Gen2Experience] should read this species on, or medium fast for
## a species the cache does not have: the same fallback [method recalculate]
## already makes for a missing base stats entry.
func growth_rate() -> int:
	return int(data.species(species).get("growth_rate", Gen2Experience.GROWTH_MEDIUM_FAST))


func base_exp() -> int:
	return int(data.species(species).get("base_exp", 0))


## The five base stats [Gen2Experience.shared_block] wants when this Pokémon is
## the one fainting, keyed like [member stat_exp]. Special Attack's base value
## fills the shared [code]"special"[/code] slot, never Special Defense's: see
## [constant Gen2Experience.STAT_EXP_KEYS].
func base_stat_exp_shape() -> Dictionary:
	var base: Dictionary = data.species(species).get("stats", {})
	return {
		"hp": int(base.get("hp", 0)),
		"attack": int(base.get("attack", 0)),
		"defense": int(base.get("defense", 0)),
		"speed": int(base.get("speed", 0)),
		"special": int(base.get("sp_attack", 0)),
	}


## Adds experience, capped the way the cartridge's own three-byte total is.
func gain_exp(amount: int) -> void:
	exp = clampi(exp + amount, 0, Gen2Experience.MAX_EXP)


## Adds a level's worth of stat experience, one entry per key in [param gains],
## each capped the way a stat's own training already is in [method recalculate].
func gain_stat_exp(gains: Dictionary) -> void:
	for key: String in gains:
		var total: int = int(stat_exp.get(key, 0)) + int(gains[key])
		stat_exp[key] = clampi(total, 0, Gen2Stats.MAX_STAT_EXP)


## The level [member exp] has actually reached on this species' curve, which is
## not necessarily [member level]: a caller awards experience first and asks
## this after, one level at a time, so that a move learned partway up a
## multi-level jump is offered at the level that actually teaches it.
func level_for_exp() -> int:
	return Gen2Experience.level_for_exp(growth_rate(), exp)


## Raises the level by one and recalculates every stat, the same call
## [method create] makes and the only other place this happens. Current HP gains
## the max-HP *difference* rather than refilling: a Pokémon one hit from fainting
## before the level up is still one hit from fainting after it.
func level_up() -> void:
	if level >= Gen2Experience.MAX_LEVEL:
		return
	var before_max: int = max_hp()
	level += 1
	recalculate()
	hp += max_hp() - before_max


func max_hp() -> int:
	return int(stats.get("hp", 1))


func is_fainted() -> bool:
	return hp <= 0


## Takes damage off, and answers how much actually landed. A Pokémon cannot be
## taken below zero, so the answer is not always the amount asked for, and a
## caller that wants to report the hit wants what landed.
func take_damage(amount: int) -> int:
	var dealt: int = clampi(amount, 0, hp)
	hp -= dealt
	return dealt


func heal(amount: int) -> int:
	var healed: int = clampi(amount, 0, max_hp() - hp)
	hp += healed
	return healed


## PP for a move slot, or zero for a slot that holds nothing.
func pp_left(slot: int) -> int:
	return int(pp[slot]) if slot >= 0 and slot < pp.size() else 0


func spend_pp(slot: int) -> void:
	if slot >= 0 and slot < pp.size():
		pp[slot] = maxi(int(pp[slot]) - 1, 0)


## Whether there is anything left to do with a move slot.
##
## A disabled slot answers false whatever its PP, as the cartridge's menu never
## offers it. [method Gen2Battle.effective_slot] and [method Gen2Battle.move_for]
## reroute a caller that still asks; [constant Gen2EffectCommands.CHECK_STATUS]
## catches the one path through neither.
func can_use(slot: int) -> bool:
	return slot >= 0 and slot < moves.size() and pp_left(slot) > 0 and slot != disabled_slot


## True when every slot is empty. The cartridge answers Struggle here; this
## answers the question and leaves that decision to the battle.
func is_out_of_pp() -> bool:
	for slot: int in moves.size():
		if can_use(slot):
			return false
	return true


## Learns a move into an empty slot, with its own full PP. Refuses if every
## slot is already taken: [method Gen2Battle.learn_move] is what overwrites one
## instead, because which one to give up is not this class's decision.
func learn_move(move: int) -> bool:
	if moves.size() >= MAX_MOVES:
		return false
	moves.append(move)
	pp.append(int(data.move(move).get("pp", 0)))
	return true


## Overwrites [param slot] with [param move], full PP, whatever was there.
func replace_move(slot: int, move: int) -> bool:
	if slot < 0 or slot >= moves.size():
		return false
	moves[slot] = move
	pp[slot] = int(data.move(move).get("pp", 0))
	return true


## Replaces Mimic for this stay on the field, with the source's fixed five PP.
func mimic_move(slot: int, move: int) -> bool:
	if slot < 0 or slot >= moves.size() or mimicked_slot >= 0:
		return false
	mimicked_slot = slot
	mimic_original_move = int(moves[slot])
	mimic_original_pp = pp_left(slot)
	moves[slot] = move
	pp[slot] = 5
	return true


func persistent_move(slot: int) -> int:
	if slot == mimicked_slot:
		return mimic_original_move
	return int(moves[slot]) if slot >= 0 and slot < moves.size() else 0


func persistent_pp(slot: int) -> int:
	if slot == mimicked_slot:
		return mimic_original_pp
	return pp_left(slot)


func restore_mimic() -> void:
	if mimicked_slot >= 0 and mimicked_slot < moves.size():
		moves[mimicked_slot] = mimic_original_move
		pp[mimicked_slot] = mimic_original_pp
	mimicked_slot = -1
	mimic_original_move = 0
	mimic_original_pp = 0


func restore_pp() -> void:
	pp = []
	for move: int in moves:
		pp.append(int(data.move(int(move)).get("pp", 0)))
