class_name Gen2Evolution
extends RefCounted

## The predicates used by `EvolveAfterBattle` in engine/pokemon/evolve.asm.
## Item and trade evolutions are intentionally exposed as predicates too, so
## field and link hosts can share the same source ordering later.

const HAPPINESS_TO_EVOLVE: int = 220
const EVERSTONE: int = 70
## Item effects.asm dispatches every one of these through EvoStoneEffect.
const STONE_ITEMS: Array[int] = [8, 0x16, 0x17, 0x18, 0x22, 0xA9]
## A trade evolution's parameter when it asks for no held item: `inc a / jr z`.
const TRADE_NO_ITEM: int = 0xFF

static func level_evolution(data: GameData, mon: Gen2BattleMon, time_of_day: int) -> Dictionary:
	if data == null or mon == null:
		return {}
	if mon.item == EVERSTONE:
		return {}
	for row: Dictionary in data.evolutions(mon.species):
		if _eligible(row, mon, time_of_day):
			return row.duplicate(true)
	return {}


## `.item`, which is the one branch of `EvolveAfterBattle` that never calls
## `IsMonHoldingEverstone`. The refusal is one level up, in `EvoStoneEffect`'s
## own `cp EVERSTONE`, so it belongs to whoever uses the item rather than here.
static func item_evolution(data: GameData, mon: Gen2BattleMon, item: int) -> Dictionary:
	if data == null or mon == null:
		return {}
	for row: Dictionary in data.evolutions(mon.species):
		if int(row.get("method", 0)) == RomLayout.EVOLVE_ITEM \
			and int(row.get("parameter", 0)) == item:
			return row.duplicate(true)
	return {}


## `.trade`: EVERSTONE refuses, a `$FF` parameter asks for nothing, and any other
## value is an item the Pokemon must be HOLDING. The cartridge zeroes
## `wTempMonItem` on the way through, so a held requirement is CONSUMED; that is
## the caller's to write, and [code]consumes_held_item[/code] says when.
static func trade_evolution(data: GameData, mon: Gen2BattleMon) -> Dictionary:
	if data == null or mon == null or mon.item == EVERSTONE:
		return {}
	for row: Dictionary in data.evolutions(mon.species):
		if int(row.get("method", 0)) != RomLayout.EVOLVE_TRADE:
			continue
		var parameter: int = int(row.get("parameter", TRADE_NO_ITEM))
		if parameter == TRADE_NO_ITEM:
			return row.duplicate(true)
		if mon.item != parameter:
			continue
		var out: Dictionary = row.duplicate(true)
		out["consumes_held_item"] = parameter
		return out
	return {}


## `EvolvingText` then `CongratulationsYourPokemonText` and `_EvolvedIntoText`,
## as the one line each. Verbatim from data/text/common_3.asm; the source shows
## them as two boxes with the animation between them.
static func evolving_text(mon_name: String) -> String:
	return "What? %s is evolving!" % mon_name


static func evolved_text(mon_name: String, new_species_name: String) -> String:
	return "Congratulations! Your %s evolved into %s!" % [mon_name, new_species_name]


## `UpdateSpeciesNameIfNotNicknamed`, which runs before `GetBaseData` reloads
## the new species: the comparison is against the OLD species' name, since
## `wBaseDexNo` still holds it. A Pokemon carrying its own species name is not
## nicknamed, so it takes the new one; anything else keeps what it was called.
static func nickname_after_evolution(
	data: GameData, nickname: String, old_species: int, new_species: int
) -> String:
	if data == null or old_species == new_species:
		return nickname
	# A cartridge party row always holds a name, so an empty one here is this
	# project's own way of saying un-nicknamed rather than a third case.
	if not nickname.is_empty() \
		and nickname != String(data.species(old_species).get("name", "")):
		return nickname
	return String(data.species(new_species).get("name", nickname))


static func _eligible(row: Dictionary, mon: Gen2BattleMon, time_of_day: int) -> bool:
	var method: int = int(row.get("method", 0))
	var parameter: int = int(row.get("parameter", 0))
	if method == RomLayout.EVOLVE_LEVEL:
		return mon.level >= parameter
	if method == RomLayout.EVOLVE_HAPPINESS:
		if mon.happiness < HAPPINESS_TO_EVOLVE:
			return false
		if parameter == RomLayout.TRIGGER_ANYTIME:
			return true
		if parameter == RomLayout.TRIGGER_MORNDAY:
			return time_of_day != Gen2WorldPalette.TIME_NIGHT
		return parameter == RomLayout.TRIGGER_NITE \
			and time_of_day == Gen2WorldPalette.TIME_NIGHT
	if method == RomLayout.EVOLVE_STAT:
		if mon.level < parameter:
			return false
		var attack: int = int(mon.stats.get("attack", 0))
		var defense: int = int(mon.stats.get("defense", 0))
		var condition: int = int(row.get("condition", 0))
		if condition == RomLayout.ATTACK_OVER_DEFENSE:
			return attack > defense
		if condition == RomLayout.ATTACK_UNDER_DEFENSE:
			return attack < defense
		return condition == RomLayout.ATTACK_EQUALS_DEFENSE \
			and attack == defense
	return false


static func evolve(mon: Gen2BattleMon, target: int) -> Dictionary:
	if mon == null or mon.data == null or target <= 0 \
		or target == mon.species or mon.data.species(target).is_empty():
		return {}
	var old_species: int = mon.species
	var old_hp: int = mon.hp
	var before_max_hp: int = mon.max_hp()
	mon.species = target
	mon.battle_types.clear()
	mon.hp = 0
	mon.recalculate()
	# `evolve.asm` adds the max-HP delta, preserving damage through evolution.
	mon.hp = clampi(old_hp + mon.max_hp() - before_max_hp, 0, mon.max_hp())
	return {"old_species": old_species, "new_species": target}


## `StoppedEvolvingText`, printed by `CancelEvolution` before the master loop
## moves on to the next party member.
static func stopped_evolving_text(mon_name: String) -> String:
	return "Huh? %s stopped evolving!" % mon_name


## `EvolveAfterBattle`'s master loop, as a list of plans rather than a walk that
## evolves as it goes: nothing here writes a party row, so a caller can show
## `EvolutionAnimation` for each and apply only the ones that were not cancelled.
##
## [param evolvable] is `wEvolvableFlags` as [method Gen2Battle.evolvable_indices]
## answers it: BATTLE-party indices, mapped here through the one rule that knows
## an egg keeps its party slot without being a combatant. Only `.level`,
## `.happiness` and `.stat` are reachable on this path: `wForceEvolution` is zero,
## which is what `.item` demands, and `.trade` demands a `wLinkMode` this project
## has none of.
static func after_battle(
	data: GameData, save: Gen2SaveData, evolvable: Array, time_of_day: int
) -> Array:
	var plans: Array = []
	if data == null or save == null:
		return plans
	var flagged: Array[int] = []
	for battle_index: int in evolvable:
		var mapped: int = Gen2SaveBattleAdapter.save_party_index(save, int(battle_index))
		if mapped >= 0:
			flagged.append(mapped)
	for index: int in save.party.size():
		if not flagged.has(index):
			continue
		var mon: Gen2SaveMon = save.party[index]
		if mon == null or mon.is_egg:
			continue
		var battle_mon: Gen2BattleMon = Gen2SaveBattleAdapter.to_battle_mon(data, mon)
		if battle_mon == null:
			continue
		var row: Dictionary = level_evolution(data, battle_mon, time_of_day)
		if row.is_empty():
			continue
		var target: int = int(row.get("target", 0))
		if target <= 0 or target == mon.species or data.species(target).is_empty():
			continue
		plans.append({
			"index": index,
			"old_species": mon.species,
			"new_species": target,
			"level": mon.level,
			# `GetNickname` / `CopyName1` fill wStringBuffer2 before the species is
			# replaced, and all four boxes read it, so every line of the sequence
			# names what the Pokemon was called on the way in.
			"evolving_name": mon.nickname if not mon.nickname.is_empty() \
				else String(data.species(mon.species).get("name", "")),
			# `.check_statused`'s `CheckFaintedFrzSlp`, which costs the cry and the
			# closing `AnimateFrontpic` both.
			"statused": is_statused(mon),
			# `.pressed_b` reads `wForceEvolution`: a level evolution is not
			# forced, so B cancels it, and an item's is and B does nothing.
			"can_cancel": true,
			"row": row.duplicate(true),
		})
	return plans


## `CheckFaintedFrzSlp`, which `EvolutionAnimation.check_statused` asks about the
## party row rather than about a battler: fainted, frozen or asleep.
static func is_statused(mon: Gen2SaveMon) -> bool:
	if mon == null:
		return true
	return mon.hp <= 0 or (mon.status & Gen2Status.FREEZE) != 0 \
		or Gen2Status.is_asleep(mon.status)
