extends RefCounted

## Sweeps the Day-Care and the breeding rules behind it on freshly imported real
## caches, all three cartridges, whole corpus.
##
## What this exists to catch is a rule that is right for the pair a test was
## written for and wrong for the corpus: `GetPreEvolution` is a search over every
## species, `CheckBreedmonCompatibility` reads two records at once, and
## `FillMoves` is the same routine the retrieval and the egg both go through. A
## sampled pair answers none of those.
##
## The real-cartridge counterpart to tests/unit/test_world_day_care.gd.
##
##   Godot --headless --path . -s res://tools/validate.gd -- day_care

## `PrintDayCareText.TextTable`'s twenty, `.NotYetText`, `DayCareManOutside`'s
## five and `engine/pokemon/breeding.asm`'s two plus five.
const EXPECTED_TEXTS: int = 33
## One stub per run, by the words that identify the run rather than the address.
const TEXT_ANCHORS: Dictionary = {
	"man_intro": "I'm the DAY-CARE",
	"not_yet": "Not yet",
	"found_an_egg": "it's you!",
	"left_with_man": "DAY-CARE MAN",
	"brimming_with_energy": "brimming with",
}

## `DITTO`, the one species compatible with everything that breeds at all.
const SPECIES_DITTO: int = 132

var _r: RefCounted = null


func run(r: RefCounted) -> void:
	_r = r
	for game_id: StringName in _r.GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_r.game_id = game_id
		_verify_texts(game_id, data)
		_verify_pre_evolutions(game_id, data)
		_verify_compatibility(game_id, data)
		_verify_egg_moves(game_id, data)
		_verify_fill_moves(game_id, data)
	_r.game_id = &""


## Every stub of the four runs decodes, and one per run carries the words that
## say the pin is that run and not its neighbour.
func _verify_texts(game_id: StringName, data: GameData) -> void:
	var found: int = 0
	for run: Array in RomLayout.DAY_CARE_TEXT_RUNS:
		for raw_name: Variant in run[1] as Array:
			var name: String = String(raw_name)
			var text: String = data.day_care_text(name)
			if _r.check(
				not text.is_empty(), "%s: the Day-Care's %s text is empty." % [game_id, name]
			):
				found += 1
	_r.check(
		found == EXPECTED_TEXTS,
		"%s: %d of %d Day-Care texts decoded." % [game_id, found, EXPECTED_TEXTS]
	)
	for name: String in TEXT_ANCHORS:
		_r.check(
			data.day_care_text(name).contains(String(TEXT_ANCHORS[name])),
			"%s: the Day-Care's %s text is \"%s\"." % [
				game_id, name, data.day_care_text(name)
			]
		)


## `DayCare_InitBreeding` calls `GetPreEvolution` exactly twice, so two passes
## have to reach a base form for every species on the cartridge: a third pass
## finding anything would mean a three-deep line whose egg is the middle stage.
func _verify_pre_evolutions(game_id: StringName, data: GameData) -> void:
	var deepest: int = 0
	for species: int in range(1, data.species_count() + 1):
		var once: int = Gen2WorldDayCare.pre_evolution(data, species)
		var twice: int = Gen2WorldDayCare.pre_evolution(data, once)
		var thrice: int = Gen2WorldDayCare.pre_evolution(data, twice)
		if once != species:
			deepest = maxi(deepest, 2 if twice != once else 1)
		if not _r.check(
			thrice == twice,
			"%s: species %d is still evolving from %d after two passes." % [
				game_id, species, thrice
			]
		):
			continue
		## Every species an egg can be has a hatch counter, since the counter is
		## what `DoEggStep` drains and a zero one hatches on the first step.
		_r.check(
			int(data.species(twice).get("hatch_cycles", 0)) > 0,
			"%s: base species %d has no hatch cycles." % [game_id, twice]
		)
	_r.check(deepest == 2, "%s: no species is two evolutions deep." % game_id)


## `CheckBreedmonCompatibility` over the whole species square. Two things are
## swept: the answer does not depend on which slot a species is in, and every
## answer is one of the values `DayCareMonCompatibilityText` and
## `DayCare_InitBreeding` between them account for.
func _verify_compatibility(game_id: StringName, data: GameData) -> void:
	var count: int = data.species_count()
	var breeders: int = 0
	var asymmetric: int = 0
	var out_of_range: int = 0
	for first: int in range(1, count + 1):
		var mon1: Gen2SaveMon = _mon(first, 0x1234, 111)
		for second: int in range(first, count + 1):
			var mon2: Gen2SaveMon = _mon(second, 0x5678, 222)
			var forward: int = Gen2WorldDayCare.compatibility(data, mon1, mon2)
			var backward: int = Gen2WorldDayCare.compatibility(data, mon2, mon1)
			if forward != backward:
				asymmetric += 1
			if forward not in [0, 51, 128, 177, 254, 255]:
				out_of_range += 1
			if forward != 0 and forward != 255:
				breeders += 1
	_r.check(
		asymmetric == 0,
		"%s: %d species pairs answer differently by slot." % [game_id, asymmetric]
	)
	_r.check(
		out_of_range == 0,
		"%s: %d species pairs answer a value no branch reads." % [game_id, out_of_range]
	)
	_r.check(breeders > 0, "%s: no species pair breeds at all." % game_id)
	## Ditto's own row, which is the one species the group test lets through
	## whatever it is paired with.
	var ditto: Gen2SaveMon = _mon(SPECIES_DITTO, 0x1234, 111)
	for species: int in range(1, count + 1):
		var partner: Gen2SaveMon = _mon(species, 0x5678, 222)
		var breeds: bool = Gen2WorldDayCare.compatibility(data, ditto, partner) != 0
		_r.check(
			breeds == (species != SPECIES_DITTO
				and Gen2WorldDayCare.groups_compatible(data, ditto, partner)),
			"%s: DITTO and species %d disagree with their egg groups." % [game_id, species]
		)


## Every egg move names a move this cache has, and every one of them is one the
## egg species can actually receive: `GetEggMove`'s first test is the list
## itself, so a list entry that fails [method Gen2WorldDayCare.inherits_move]
## would mean the two readings of the same table disagree.
func _verify_egg_moves(game_id: StringName, data: GameData) -> void:
	var rows: int = 0
	for species: int in range(1, data.species_count() + 1):
		for move: int in data.egg_moves(species):
			rows += 1
			if not _r.check(
				move > 0 and move <= data.move_count(),
				"%s: species %d inherits move %d." % [game_id, species, move]
			):
				continue
			_r.check(
				Gen2WorldDayCare.inherits_move(data, species, move, null),
				"%s: species %d's own egg move %d is refused." % [game_id, species, move]
			)
	_r.check(rows > 0, "%s: no egg moves imported." % game_id)


## `FillMoves` over every species at every level, both branches. Four slots, no
## repeats and nothing above the level asked for is the whole of the routine's
## contract, and the skip branch may only ever be a subset of the plain one.
func _verify_fill_moves(game_id: StringName, data: GameData) -> void:
	for species: int in range(1, data.species_count() + 1):
		var learnset: Array = data.learnset(species)
		for level: int in range(1, Gen2Experience.MAX_LEVEL + 1):
			var known: Array = Gen2Learnset.moves_at_level(learnset, level)
			if not _r.check(
				known.size() <= Gen2Learnset.MOVE_SLOTS,
				"%s: species %d knows %d moves at level %d." % [
					game_id, species, known.size(), level
				]
			):
				return
			var seen: Dictionary = {}
			for move: Variant in known:
				if not _r.check(
					not seen.has(move),
					"%s: species %d knows move %d twice at level %d." % [
						game_id, species, int(move), level
					]
				):
					return
				seen[move] = true
			## The retrieval branch: filling from the level below teaches at most
			## what the whole walk would, and never a move it would not.
			var grown: Array = Gen2Learnset.moves_at_level(learnset, maxi(1, level - 1))
			Gen2Learnset.fill_moves(learnset, grown, level, maxi(1, level - 1))
			if not _r.check(
				grown.size() <= Gen2Learnset.MOVE_SLOTS,
				"%s: species %d grows into %d moves at level %d." % [
					game_id, species, grown.size(), level
				]
			):
				return


## A Day-Care slot with the DVs and trainer ID a sweep needs to be able to vary,
## since both of them are read by `CheckBreedmonCompatibility`.
func _mon(species: int, dvs: int, ot_id: int) -> Gen2SaveMon:
	var mon: Gen2SaveMon = Gen2SaveMon.new()
	mon.species = species
	mon.dvs = dvs
	mon.ot_id = ot_id
	mon.level = 20
	return mon
