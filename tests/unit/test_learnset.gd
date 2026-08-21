extends GutTest

## What a Pokémon knows at a level, against learnsets copied out of the
## cartridges rather than invented.
##
## Two species cover everything worth testing. Golbat learns the same move twice,
## which is the duplicate check. Muk's list is not ascending, which is why the
## two questions give different answers: filling a fresh Pokémon stops at the
## first entry above its level, so a Muk caught at 40 is three moves short of one
## raised to 40.

const SCREECH: int = 103
const LEECH_LIFE: int = 141
const SUPERSONIC: int = 48
const BITE: int = 44
const CONFUSE_RAY: int = 109
const WING_ATTACK: int = 17
const MEAN_LOOK: int = 212
const HAZE: int = 114

const POISON_GAS: int = 139
const POUND: int = 1
const HARDEN: int = 106
const DISABLE: int = 50
const SLUDGE: int = 124
const MINIMIZE: int = 107
const ACID_ARMOR: int = 151
const SLUDGE_BOMB: int = 188


## Golbat, whose first four moves include Supersonic twice.
func _golbat() -> Array:
	return _learnset([
		[1, SCREECH], [1, LEECH_LIFE], [1, SUPERSONIC], [6, SUPERSONIC], [12, BITE],
		[19, CONFUSE_RAY], [30, WING_ATTACK], [42, MEAN_LOOK], [55, HAZE],
	])


## Muk, exactly as all three cartridges store it: the entries for levels 23, 31
## and 45 sit after the one for 45, which is not where an ascending list would
## put them.
func _muk() -> Array:
	return _learnset([
		[1, POISON_GAS], [1, POUND], [1, HARDEN], [33, HARDEN], [37, DISABLE], [45, SLUDGE],
		[23, MINIMIZE], [31, SCREECH], [45, ACID_ARMOR], [60, SLUDGE_BOMB],
	])


func _learnset(pairs: Array) -> Array:
	var out: Array = []
	for pair: Array in pairs:
		out.append({"level": pair[0], "move": pair[1]})
	return out


func test_a_pokemon_below_its_first_move_knows_nothing() -> void:
	assert_eq(Gen2Learnset.moves_at_level(_golbat(), 0), [])


func test_an_empty_learnset_teaches_nothing() -> void:
	assert_eq(Gen2Learnset.moves_at_level([], 50), [])


func test_the_first_moves_come_in_order() -> void:
	assert_eq(Gen2Learnset.moves_at_level(_golbat(), 1), [SCREECH, LEECH_LIFE, SUPERSONIC])


func test_a_move_already_known_is_not_learned_twice() -> void:
	# Supersonic is on the list at both 1 and 6, and a Golbat of 6 knows three
	# moves rather than four.
	assert_eq(Gen2Learnset.moves_at_level(_golbat(), 6), [SCREECH, LEECH_LIFE, SUPERSONIC])


func test_a_fifth_move_pushes_out_the_oldest() -> void:
	assert_eq(
		Gen2Learnset.moves_at_level(_golbat(), 19),
		[LEECH_LIFE, SUPERSONIC, BITE, CONFUSE_RAY]
	)


func test_a_full_set_is_the_last_four_learnable_moves() -> void:
	assert_eq(
		Gen2Learnset.moves_at_level(_golbat(), 100),
		[CONFUSE_RAY, WING_ATTACK, MEAN_LOOK, HAZE]
	)


func test_the_walk_stops_at_the_first_move_above_the_level() -> void:
	# The cartridge's behaviour, not a rounding of it. Muk's list reaches level 45
	# before it reaches levels 23 and 31, so a Muk of 40 never sees Minimize or
	# Screech even though it is well past both.
	assert_eq(
		Gen2Learnset.moves_at_level(_muk(), 40),
		[POISON_GAS, POUND, HARDEN, DISABLE]
	)


func test_a_full_grown_muk_reaches_the_moves_behind_the_break() -> void:
	assert_eq(
		Gen2Learnset.moves_at_level(_muk(), 100),
		[MINIMIZE, SCREECH, ACID_ARMOR, SLUDGE_BOMB]
	)


func test_levelling_up_finds_what_filling_a_new_pokemon_misses() -> void:
	# The other question, and the reason both are here: a Muk that levels up to 45
	# is offered both moves listed at 45, wherever in the list they sit.
	assert_eq(Gen2Learnset.moves_learned_at(_muk(), 45), [SLUDGE, ACID_ARMOR])
	assert_eq(Gen2Learnset.moves_learned_at(_muk(), 23), [MINIMIZE])


func test_a_level_that_teaches_nothing_offers_nothing() -> void:
	assert_eq(Gen2Learnset.moves_learned_at(_golbat(), 13), [])


func test_the_same_move_is_offered_once_at_a_level() -> void:
	assert_eq(Gen2Learnset.moves_learned_at(_golbat(), 1), [SCREECH, LEECH_LIFE, SUPERSONIC])
	assert_eq(Gen2Learnset.moves_learned_at(_muk(), 1), [POISON_GAS, POUND, HARDEN])


func test_four_slots_is_what_a_battler_carries() -> void:
	# The two constants are the same number seen from either side of the line, and
	# a Pokémon that knew five would be trimmed silently on its way into a battle.
	assert_eq(Gen2Learnset.MOVE_SLOTS, Gen2BattleMon.MAX_MOVES)


func test_the_skip_branch_teaches_only_the_levels_between_the_two() -> void:
	# `wSkipMovesBeforeLevelUp`, which is what a Day-Care retrieval fills with:
	# a Golbat deposited at 12 and taken back at 19 is offered Confuse Ray and
	# nothing it already knew.
	var known: Array = [SCREECH, LEECH_LIFE, SUPERSONIC, BITE]
	Gen2Learnset.fill_moves(_golbat(), known, 19, 12)
	assert_eq(known, [LEECH_LIFE, SUPERSONIC, BITE, CONFUSE_RAY])


func test_the_skip_branch_fills_an_empty_slot_before_it_shifts() -> void:
	var known: Array = [SCREECH, 0, 0, 0]
	Gen2Learnset.fill_moves(_golbat(), known, 19, 12)
	assert_eq(known, [SCREECH, CONFUSE_RAY, 0, 0])


func test_a_move_learned_at_the_level_deposited_at_is_not_offered_again() -> void:
	# `cp b / jr nc, .GetMove` skips the level itself, so a Golbat put in at 19
	# and taken out at 19 learns nothing.
	var known: Array = [SCREECH, 0, 0, 0]
	Gen2Learnset.fill_moves(_golbat(), known, 19, 19)
	assert_eq(known, [SCREECH, 0, 0, 0])
