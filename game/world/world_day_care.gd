class_name Gen2WorldDayCare
extends RefCounted

## `engine/events/daycare.asm` and `engine/pokemon/breeding.asm`, the rules half.
##
## The two Day-Care slots are world state rather than party members: the
## cartridge keeps them in `wBreedMon1` and `wBreedMon2`, which are boxmon
## structs beside the flag byte that says whether each is occupied. This answers
## what the three routines ask of that state and nothing else; the boxes,
## presses and party list are [Gen2DayCareScreen]'s.
##
## Every duration and every roll here is the source's own. What a reading gets
## wrong is which parent a field comes from: `wBreedMotherOrNonDitto` is set once
## in `DayCare_InitBreeding` and then read by four routines that each pick a
## *different* side of it, so it is computed once here as
## [method mother_or_non_ditto] and passed down.

## `wDayCareMan`'s four bits (constants/ram_constants.asm).
const MAN_HAS_MON: int = 1 << 0
const MAN_MONS_COMPATIBLE: int = 1 << 5
const MAN_HAS_EGG: int = 1 << 6
const MAN_ACTIVE: int = 1 << 7
## `wDayCareLady`'s two. `MONS_COMPATIBLE` and `HAS_EGG` live on the man's byte
## for both slots, which is why withdrawing from the lady clears a man's bit.
const LADY_HAS_MON: int = 1 << 0
const LADY_ACTIVE: int = 1 << 7

## Which slot a routine is acting on. `SLOT_MAN` is `wBreedMon1`.
const SLOT_MAN: int = 0
const SLOT_LADY: int = 1

const SPECIES_DITTO: int = 132
const SPECIES_NIDORAN_F: int = 29
const SPECIES_NIDORAN_M: int = 32
## `EGG_NONE`, the fifteenth egg group. `CheckBreedingGroupCompatibility`
## compares the whole byte against `EGG_NONE * $11`, so a species is refused only
## when *both* of its nibbles are this.
const EGG_GROUP_NONE: int = 15
## `EGG_LEVEL`, the level every egg hatches at.
const EGG_LEVEL: int = 5
## `MAX_LEVEL`, above which a deposited Pokemon stops gaining experience.
const MAX_LEVEL: int = 100
## `MAX_DAY_CARE_EXP`. The routine clamps the experience's *high byte* alone, on
## the pass a carry reaches it, which is why the cap is a plain 3-byte value here
## and not a mask.
const MAX_DAY_CARE_EXP: int = 0x500000

## `GetPriceToRetrieveBreedmon`: a hundred coins a level gained, plus a hundred
## for the stay itself.
const RETRIEVE_BASE_PRICE: int = 100
const RETRIEVE_PRICE_PER_LEVEL: int = 100

## `DayCare_InitBreeding`'s own `cp 150`: the first counter is a random byte of
## at least this, so the earliest possible egg is 150 step cycles away.
const FIRST_EGG_STEPS_MINIMUM: int = 150

## `DayCareStep`'s four bands, as [compatibility floor, chance out of 256]. The
## chances are the source's `percent` macro, which is `x * $ff / 100` with
## integer division: `31 percent + 1` is 80, `16 percent` 40, `12 percent` 30 and
## `4 percent` 10. Walked in order, the first floor a value reaches winning.
const EGG_CHANCE_BANDS: Array = [[230, 80], [170, 40], [110, 30], [0, 10]]

## `DayCareMonCompatibilityText`'s five answers, by the stub each loads. The
## walk is the routine's own order and its first match wins, so 255 is answered
## before the zero test that would otherwise never be reached for it.
const COMPATIBILITY_BRIMMING: String = "brimming_with_energy"
const COMPATIBILITY_NONE: String = "no_interest"
const COMPATIBILITY_CARES: String = "appears_to_care"
const COMPATIBILITY_FRIENDLY: String = "friendly"
const COMPATIBILITY_INTEREST: String = "shows_interest"

## `PrintDayCareText`'s own indices, by the stub name `RomLayout` pins.
const TEXT_MAN_INTRO: String = "man_intro"
const TEXT_MAN_INTRO_EGG: String = "man_intro_egg"
const TEXT_LADY_INTRO: String = "lady_intro"
const TEXT_LADY_INTRO_EGG: String = "lady_intro_egg"
const TEXT_WHICH_ONE: String = "which_one"
const TEXT_DEPOSIT: String = "ill_raise"
const TEXT_CANT_BREED_EGG: String = "cant_accept_egg"
const TEXT_LAST_MON: String = "only_one_mon"
const TEXT_LAST_ALIVE_MON: String = "last_healthy_mon"
const TEXT_COME_BACK_LATER: String = "come_back_later"
const TEXT_REMOVE_MAIL: String = "remove_mail"
const TEXT_GENIUSES: String = "are_we_geniuses"
const TEXT_ASK_WITHDRAW: String = "has_grown"
const TEXT_WITHDRAW: String = "perfect_heres_your_mon"
const TEXT_GOT_BACK: String = "got_back"
const TEXT_TOO_SOON: String = "back_already"
const TEXT_PARTY_FULL: String = "have_no_room"
const TEXT_NOT_ENOUGH_MONEY: String = "not_enough_money"
const TEXT_OH_FINE: String = "oh_fine_then"
const TEXT_COME_AGAIN: String = "come_again"


## `GetGender` on a Day-Care slot, which runs under `wMonType` TEMPMON with the
## slot's own species and DVs loaded. Returns one of [Gen2BattleMon]'s three.
static func gender_of(data: GameData, mon: Gen2SaveMon) -> StringName:
	if data == null or mon == null:
		return Gen2BattleMon.GENDER_NONE
	return Gen2BattleMon.gender_for(data, mon.species, mon.dvs)


## `CheckBreedingGroupCompatibility`. Ditto is compatible with everything that is
## not in the No Eggs group, including a second Ditto: the pair test that stops
## two Dittos is `.genderless`'s, one caller up.
static func groups_compatible(data: GameData, mon1: Gen2SaveMon, mon2: Gen2SaveMon) -> bool:
	if data == null or mon1 == null or mon2 == null:
		return false
	if _breeds_no_eggs(data, mon2.species) or _breeds_no_eggs(data, mon1.species):
		return false
	if mon2.species == SPECIES_DITTO or mon1.species == SPECIES_DITTO:
		return true
	var groups1: Array = _egg_groups(data, mon1.species)
	var groups2: Array = _egg_groups(data, mon2.species)
	return groups1[0] in groups2 or groups1[1] in groups2


## `CheckBreedmonCompatibility`'s own byte. 0 refuses, 255 is the matching-DV
## refusal that still reads as "brimming with energy", and everything else is a
## live pair whose value decides how often an egg is offered.
static func compatibility(data: GameData, mon1: Gen2SaveMon, mon2: Gen2SaveMon) -> int:
	if not groups_compatible(data, mon1, mon2):
		return 0
	var gender1: StringName = gender_of(data, mon1)
	var gender2: StringName = gender_of(data, mon2)
	var opposite: bool = gender1 != Gen2BattleMon.GENDER_NONE \
		and gender2 != Gen2BattleMon.GENDER_NONE and gender1 != gender2
	if not opposite:
		## `.genderless`, reached by a genderless parent and by two of the same
		## gender alike: exactly one of the two has to be a Ditto.
		var ditto1: bool = mon1.species == SPECIES_DITTO
		var ditto2: bool = mon2.species == SPECIES_DITTO
		if ditto1 == ditto2:
			return 0
	if _dvs_match(mon1, mon2):
		return 255
	var value: int = 254 if mon1.species == mon2.species else 128
	## `.compare_ids`: a shared trainer ID is what lowers it, not a shared
	## species, and the subtraction happens on both branches above.
	if mon1.ot_id == mon2.ot_id:
		value -= 77
	return value


## Which of `DayCareMonCompatibilityText`'s five stubs [param value] reaches.
static func compatibility_text_key(value: int) -> String:
	if value == 255:
		return COMPATIBILITY_BRIMMING
	if value == 0:
		return COMPATIBILITY_NONE
	if value >= 230:
		return COMPATIBILITY_CARES
	if value >= 70:
		return COMPATIBILITY_FRIENDLY
	return COMPATIBILITY_INTEREST


## `wBreedMotherOrNonDitto`: 0 when `wBreedMon1` is the mother or the non-Ditto,
## 1 when `wBreedMon2` is. A Ditto in either slot decides it before any gender is
## read, which is why a Ditto pairing never asks about gender at all.
static func mother_or_non_ditto(data: GameData, mon1: Gen2SaveMon, mon2: Gen2SaveMon) -> int:
	if mon1 == null or mon2 == null:
		return SLOT_MAN
	if mon1.species == SPECIES_DITTO:
		return SLOT_LADY
	if mon2.species == SPECIES_DITTO:
		return SLOT_MAN
	return SLOT_MAN if gender_of(data, mon1) == Gen2BattleMon.GENDER_FEMALE else SLOT_LADY


## `GetPreEvolution`: the lowest-numbered species that evolves into
## [param species], or [param species] itself when nothing does. The walk is by
## species number and stops at the first match, so a species reached by two
## evolutions takes the smaller number.
static func pre_evolution(data: GameData, species: int) -> int:
	if data == null:
		return species
	for candidate: int in range(1, RomLayout.SPECIES_COUNT + 1):
		for row: Dictionary in data.evolutions(candidate):
			if int(row.get("target", 0)) == species:
				return candidate
	return species


## `DayCare_InitBreeding`'s two `callfar GetPreEvolution` and the Nidoran split
## behind them. Nidoran F is the one mother whose egg can be either sign, and the
## roll is `cp 50 percent + 1`, which is 128.
static func egg_species(data: GameData, mother_species: int, random: RandomNumberGenerator) -> int:
	var species: int = pre_evolution(data, pre_evolution(data, mother_species))
	if species != SPECIES_NIDORAN_F:
		return species
	return SPECIES_NIDORAN_F if _random_byte(random) < 128 else SPECIES_NIDORAN_M


## `GetHeritableMoves`: whose four moves the egg may inherit. The answer is the
## father in an ordinary pairing and the *non-Ditto* parent in a Ditto one, which
## is not the same side [method breedmon_move_source] takes.
static func heritable_move_source(
	data: GameData, mon1: Gen2SaveMon, mon2: Gen2SaveMon
) -> Gen2SaveMon:
	if mon1.species == SPECIES_DITTO:
		return mon1 if gender_of(data, mon2) == Gen2BattleMon.GENDER_FEMALE else mon2
	if mon2.species == SPECIES_DITTO:
		return mon2 if gender_of(data, mon1) == Gen2BattleMon.GENDER_FEMALE else mon1
	return mon2 if mother_or_non_ditto(data, mon1, mon2) == SLOT_MAN else mon1


## `GetBreedmonMovePointer`: the mother's four moves, or the Ditto's. `GetEggMove`
## reads these to decide whether a move the father knows is one the pair could
## have passed on at all.
static func breedmon_move_source(
	data: GameData, mon1: Gen2SaveMon, mon2: Gen2SaveMon
) -> Gen2SaveMon:
	if mon1.species == SPECIES_DITTO:
		return mon1
	if mon2.species == SPECIES_DITTO:
		return mon2
	return mon1 if mother_or_non_ditto(data, mon1, mon2) == SLOT_MAN else mon2


## `GetEggMove`, which answers whether one move the father knows reaches the egg.
## Three ways in, in the routine's own order: the egg species' own egg-move list,
## a move the mother knows that the egg species learns by level, and a TM or HM
## the egg species can be taught.
static func inherits_move(
	data: GameData, egg: int, move: int, mother: Gen2SaveMon
) -> bool:
	if data == null or move <= 0:
		return false
	if data.egg_moves(egg).has(move):
		return true
	if mother != null and mother.moves.has(move):
		for row: Dictionary in data.learnset(egg):
			if int(row.get("move", 0)) == move:
				return true
	var number: int = data.tmhm_number_for_move(move)
	return number > 0 and _can_learn_tm_hm(data, egg, number)


## `LoadEggMove`: the first empty slot, or the last one after the four have been
## shifted down. `FillPP` follows it, which is why the pp array is written here
## rather than by the caller.
static func load_egg_move(data: GameData, moves: Array, pp: Array, move: int) -> void:
	var slot: int = moves.find(0)
	if slot < 0:
		for index: int in Gen2SaveMon.MAX_MOVES - 1:
			moves[index] = moves[index + 1]
		slot = Gen2SaveMon.MAX_MOVES - 1
	moves[slot] = move
	for index: int in Gen2SaveMon.MAX_MOVES:
		var known: int = int(moves[index])
		pp[index] = int(data.move(known).get("pp", 0)) if known > 0 else 0


## `GetBreedMon1LevelGrowth`: how many levels the slot's experience has bought
## since it was deposited. `CalcLevel` reads the experience and the stored level
## is what it is compared against, so a slot at MAX_LEVEL still reports zero.
static func level_growth(data: GameData, mon: Gen2SaveMon) -> int:
	if data == null or mon == null:
		return 0
	return maxi(0, grown_level(data, mon) - mon.level)


## `CalcLevel`'s own answer for a slot, which is the level it will come out at.
static func grown_level(data: GameData, mon: Gen2SaveMon) -> int:
	if data == null or mon == null:
		return 0
	return Gen2Experience.level_for_exp(
		int(data.species(mon.species).get("growth_rate", 0)), mon.exp
	)


## `GetPriceToRetrieveBreedmon`.
static func price_to_retrieve(growth: int) -> int:
	return RETRIEVE_BASE_PRICE + RETRIEVE_PRICE_PER_LEVEL * maxi(0, growth)


## `DayCareStep`, the whole of it: a point of experience for each occupied slot
## and, once the pair is compatible, the counter that offers an egg.
##
## Returns true when this step set `DAYCAREMAN_HAS_EGG_F`, which is the one thing
## outside the state a caller can observe.
static func step(state: Gen2WorldState, data: GameData, random: RandomNumberGenerator) -> bool:
	if state == null or data == null:
		return false
	for slot: int in [SLOT_MAN, SLOT_LADY]:
		if not state.day_care_has_mon(slot):
			continue
		var mon: Gen2SaveMon = state.day_care_mon(slot)
		if mon == null or mon.level >= MAX_LEVEL:
			continue
		mon.exp = _day_care_exp_after(mon.exp)
		state.set_day_care_mon(slot, mon)
	if state.day_care_man_flags() & MAN_MONS_COMPATIBLE == 0:
		return false
	state.set_steps_to_egg(state.steps_to_egg() - 1)
	if state.steps_to_egg() > 0:
		return false
	## `call Random / ld [hl], a`: the counter is reloaded with a raw byte here
	## rather than with the `cp 150` roll `DayCare_InitBreeding` uses.
	state.set_steps_to_egg(_random_byte(random))
	var value: int = compatibility(
		data, state.day_care_mon(SLOT_MAN), state.day_care_mon(SLOT_LADY)
	)
	var chance: int = 10
	for band: Array in EGG_CHANCE_BANDS:
		if value >= int(band[0]):
			chance = int(band[1])
			break
	if _random_byte(random) >= chance:
		return false
	state.set_day_care_man_flags(
		(state.day_care_man_flags() & ~MAN_MONS_COMPATIBLE) | MAN_HAS_EGG
	)
	return true


## `DayCare_InitBreeding`, run after every deposit and after the egg is handed
## over. An incompatible pair leaves the counter and the egg alone; a compatible
## one builds the egg now and holds it until the counter runs out, which is what
## the cartridge does and why a pair swapped mid-count changes nothing.
static func init_breeding(
	state: Gen2WorldState,
	data: GameData,
	player_name: String,
	player_id: int,
	random: RandomNumberGenerator
) -> bool:
	if state == null or data == null:
		return false
	if not state.day_care_has_mon(SLOT_MAN) or not state.day_care_has_mon(SLOT_LADY):
		return false
	var mon1: Gen2SaveMon = state.day_care_mon(SLOT_MAN)
	var mon2: Gen2SaveMon = state.day_care_mon(SLOT_LADY)
	var value: int = compatibility(data, mon1, mon2)
	if value == 0 or value == 255:
		return false
	state.set_day_care_man_flags(state.day_care_man_flags() | MAN_MONS_COMPATIBLE)
	## `.loop`: a random byte re-rolled until it is at least 150.
	var steps: int = _random_byte(random)
	while steps < FIRST_EGG_STEPS_MINIMUM:
		steps = _random_byte(random)
	state.set_steps_to_egg(steps)
	state.set_day_care_egg(make_egg(data, mon1, mon2, player_name, player_id, random))
	return true


## `.UselessJump` onward: the egg itself. Built in the source's own order, which
## matters twice over. The level-up moves are filled before the inherited ones,
## so an inherited move pushes the oldest level-up move out; and the DVs are
## rolled after both, so the gender that decides which parent the Defense DV
## comes from is the *egg's* own, read off the freshly rolled bytes.
static func make_egg(
	data: GameData,
	mon1: Gen2SaveMon,
	mon2: Gen2SaveMon,
	player_name: String,
	player_id: int,
	random: RandomNumberGenerator
) -> Gen2SaveMon:
	if data == null or mon1 == null or mon2 == null:
		return null
	var mother_slot: int = mother_or_non_ditto(data, mon1, mon2)
	var mother: Gen2SaveMon = mon1 if mother_slot == SLOT_MAN else mon2
	var species: int = egg_species(data, mother.species, random)
	var egg: Gen2SaveMon = Gen2SaveMon.new()
	egg.species = species
	egg.is_egg = true
	egg.nickname = "EGG"
	egg.original_trainer = player_name
	egg.ot_id = player_id
	egg.item = 0
	egg.level = EGG_LEVEL
	egg.caught_level = 0
	egg.moves = [0, 0, 0, 0]
	egg.pp = [0, 0, 0, 0]
	for move: Variant in Gen2Learnset.moves_at_level(data.learnset(species), EGG_LEVEL):
		load_egg_move(data, egg.moves, egg.pp, int(move))
	## `InitEggMoves`, which walks the father's four in order and stops at the
	## first empty slot rather than skipping it.
	var father: Gen2SaveMon = heritable_move_source(data, mon1, mon2)
	var move_source: Gen2SaveMon = breedmon_move_source(data, mon1, mon2)
	for slot: int in Gen2SaveMon.MAX_MOVES:
		var move: int = int(father.moves[slot])
		if move == 0:
			break
		if egg.moves.has(move):
			continue
		if inherits_move(data, species, move, move_source):
			load_egg_move(data, egg.moves, egg.pp, move)
	egg.exp = Gen2Experience.total_exp_at(
		int(data.species(species).get("growth_rate", 0)), EGG_LEVEL
	)
	for key: Variant in Gen2SaveMon.STAT_EXP_KEYS:
		egg.stat_exp[key] = 0
	egg.dvs = inherited_dvs(
		data, species, _random_byte(random) << 8 | _random_byte(random), mon1, mon2
	)
	## `FillPP` again, now that the DVs are settled: the moves have not changed,
	## so this is the same answer, and it is here because the source runs it here.
	for index: int in Gen2SaveMon.MAX_MOVES:
		var known: int = int(egg.moves[index])
		egg.pp[index] = int(data.move(known).get("pp", 0)) if known > 0 else 0
	## `ld a, [wBaseEggSteps]`: an egg's happiness byte is its hatch counter,
	## which is what `DoEggStep` drains.
	egg.happiness = int(data.species(species).get("hatch_cycles", 0))
	egg.hp = 0
	return egg


## `.GotDVs` and the two parent checks in front of it. [param rolled] is the two
## random bytes the routine has just written; a genderless egg keeps both of them
## whole, and any other egg replaces its Defense DV and the low three bits of its
## Special DV with the chosen parent's.
static func inherited_dvs(
	data: GameData, species: int, rolled: int, mon1: Gen2SaveMon, mon2: Gen2SaveMon
) -> int:
	var source: Gen2SaveMon = null
	if mon1.species == SPECIES_DITTO:
		source = mon1
	elif mon2.species == SPECIES_DITTO:
		source = mon2
	else:
		var egg_gender: StringName = Gen2BattleMon.gender_for(data, species, rolled)
		if egg_gender == Gen2BattleMon.GENDER_NONE:
			return rolled
		var mother_slot: int = mother_or_non_ditto(data, mon1, mon2)
		if egg_gender == Gen2BattleMon.GENDER_FEMALE:
			## `.ParentCheck2`, which takes the slot the mother is *not* in.
			source = mon1 if mother_slot == SLOT_LADY else mon2
		else:
			source = mon1 if mother_slot == SLOT_MAN else mon2
	## The egg keeps its own Attack and Speed DVs and the Special DV's top bit;
	## the Defense DV and the Special DV's low three bits come from the parent.
	return (rolled & 0xF0F8) | (source.dvs & 0x0F00) | _low_bits(source.dvs)


## `DayCareAskDepositPokemon`'s refusals, in the routine's own order. Answers the
## `PrintDayCareText` stub the refusal prints, or `&""` when the member may go in.
static func deposit_refusal(save: Gen2SaveData, party_index: int) -> String:
	if save == null or save.party.size() < 2:
		return TEXT_LAST_MON
	if party_index < 0 or party_index >= save.party.size():
		return TEXT_OH_FINE
	var mon: Gen2SaveMon = save.party[party_index] as Gen2SaveMon
	if mon == null:
		return TEXT_OH_FINE
	if mon.is_egg:
		return TEXT_CANT_BREED_EGG
	## `CheckCurPartyMonFainted`, which refuses the *last* healthy member rather
	## than a fainted one: a fainted member may be deposited if another can walk.
	if _last_healthy(save, party_index):
		return TEXT_LAST_ALIVE_MON
	if Gen2HeldItem.is_mail(mon.item):
		return TEXT_REMOVE_MAIL
	return ""


## `DepositMonWithDayCareMan` and `RemoveMonFromPartyOrBox` behind it. The member
## leaves the party whole: the slot holds what the party held, so nothing is
## recomputed until it comes back out.
static func deposit(
	state: Gen2WorldState, save: Gen2SaveData, slot: int, party_index: int
) -> bool:
	if state == null or save == null \
		or party_index < 0 or party_index >= save.party.size():
		return false
	var mon: Gen2SaveMon = save.party[party_index] as Gen2SaveMon
	if mon == null:
		return false
	state.set_day_care_mon(slot, mon)
	save.party.remove_at(party_index)
	state.set_day_care_has_mon(slot, true)
	return true


## `RetrieveBreedmon`. The level comes from the experience, `HealPartyMon` fills
## HP, status and PP, and `FillMoves` teaches whatever the levels between the two
## carry.
##
## The last write is `CalcExpAtLevel`, which puts the experience *back* to the
## bottom of the level it just reached: that is
## `docs/bugs_and_glitches.md`'s "Pokemon deposited in the Day-Care might lose
## experience", and it is reproduced rather than corrected.
static func retrieve(
	state: Gen2WorldState, save: Gen2SaveData, data: GameData, slot: int
) -> Dictionary:
	if state == null or save == null or data == null:
		return {}
	var mon: Gen2SaveMon = state.day_care_mon(slot)
	if mon == null or save.party.size() >= Gen2SaveData.MAX_PARTY:
		return {}
	var previous_level: int = mon.level
	mon.level = clampi(grown_level(data, mon), previous_level, MAX_LEVEL)
	Gen2Learnset.fill_moves(
		data.learnset(mon.species), mon.moves, mon.level, previous_level
	)
	var growth_rate: int = int(data.species(mon.species).get("growth_rate", 0))
	mon.exp = Gen2Experience.total_exp_at(growth_rate, mon.level)
	mon.status = Gen2Status.NONE
	mon.hp = Gen2Stats.calculate(
		int((data.species(mon.species).get("stats", {}) as Dictionary).get("hp", 0)),
		Gen2Stats.hp_dv(mon.dvs), int(mon.stat_exp.get("hp", 0)), mon.level, true
	)
	for index: int in Gen2SaveMon.MAX_MOVES:
		var move: int = int(mon.moves[index])
		mon.pp[index] = int(data.move(move).get("pp", 0)) if move > 0 else 0
	save.party.append(mon)
	state.set_day_care_mon(slot, null)
	state.set_day_care_has_mon(slot, false)
	return {
		"party_index": save.party.size() - 1,
		"species": mon.species,
		"level": mon.level,
		"previous_level": previous_level,
	}


## `DayCare_GiveEgg`. The egg the pair built when the counter started is the one
## handed over, which is why nothing is rolled here.
static func give_egg(state: Gen2WorldState, save: Gen2SaveData) -> Dictionary:
	if state == null or save == null or save.party.size() >= Gen2SaveData.MAX_PARTY:
		return {}
	var egg: Gen2SaveMon = state.day_care_egg()
	if egg == null:
		return {}
	save.party.append(egg)
	state.set_day_care_egg(null)
	state.set_day_care_man_flags(state.day_care_man_flags() & ~MAN_HAS_EGG)
	return {
		"party_index": save.party.size() - 1,
		"species": egg.species,
		"nickname": egg.nickname,
	}


static func _egg_groups(data: GameData, species: int) -> Array:
	var groups: Variant = data.species(species).get("egg_groups", [])
	if not groups is Array or (groups as Array).size() < 2:
		return [EGG_GROUP_NONE, EGG_GROUP_NONE]
	return [int((groups as Array)[0]), int((groups as Array)[1])]


static func _breeds_no_eggs(data: GameData, species: int) -> bool:
	var groups: Array = _egg_groups(data, species)
	return groups[0] == EGG_GROUP_NONE and groups[1] == EGG_GROUP_NONE


## `.CheckDVs`: the Defense DV and the low three bits of the Special DV. A pair
## matching on both is refused, which is the "brimming with energy" quirk.
static func _dvs_match(mon1: Gen2SaveMon, mon2: Gen2SaveMon) -> bool:
	return Gen2Stats.defense_dv(mon1.dvs) == Gen2Stats.defense_dv(mon2.dvs) \
		and _low_bits(mon1.dvs) == _low_bits(mon2.dvs)


## The low three bits of a DV word's second byte, which is the Special DV's own
## low three: the byte is the Speed DV over the Special DV.
static func _low_bits(dvs: int) -> int:
	return dvs & 0x07


static func _can_learn_tm_hm(data: GameData, species: int, number: int) -> bool:
	var flags: Variant = data.species(species).get("tmhm", [])
	if not flags is Array:
		return false
	var bit: int = number - 1
	var index: int = bit >> 3
	if index >= (flags as Array).size():
		return false
	return int((flags as Array)[index]) & (1 << (bit & 7)) != 0


## `CheckCurPartyMonFainted`, which is `.OutOfUsableMons` when no *other* member
## can still walk.
static func _last_healthy(save: Gen2SaveData, party_index: int) -> bool:
	for index: int in save.party.size():
		if index == party_index:
			continue
		var other: Gen2SaveMon = save.party[index] as Gen2SaveMon
		if other != null and not other.is_egg and other.hp > 0:
			return false
	return true


## `.day_care_lady`'s three `inc [hl]`: one point of experience, with the high
## byte held at `MAX_DAY_CARE_EXP`'s own on the pass a carry reaches it.
static func _day_care_exp_after(exp: int) -> int:
	var raised: int = (exp + 1) & 0xFFFFFF
	if raised & 0xFFFF == 0 and raised >> 16 >= MAX_DAY_CARE_EXP >> 16:
		return MAX_DAY_CARE_EXP
	return raised


static func _random_byte(random: RandomNumberGenerator) -> int:
	if random == null:
		return 0
	return random.randi_range(0, 255)
