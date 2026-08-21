extends RefCounted

var _r: RefCounted = null

## Verifies every evolution row on freshly imported real caches against
## engine/pokemon/evolve.asm's `EvolveAfterBattle`, for all three cartridges.
##
## The predicates in [Gen2Evolution] are what the field host and any link host
## share, so the census is what pins them: every row of every species is walked
## and answered rather than spot checked, which is what catches a method the
## importer misread or a predicate that answers the wrong branch.
##
## The real-cartridge counterpart to tests/unit/test_evolution.gd.
##
##   Godot --headless --path . -s res://tools/validate.gd -- evolutions

## data/pokemon/evos_attacks.asm, counted from the pins: every `db EVOLVE_*` in
## the file. Identical across the three, since no evolution changed between them.
const EXPECTED_ROWS: int = 122
## The ten EVOLVE_TRADE rows, as species to the item the row asks be HELD.
## $FF is the four that ask for nothing: KADABRA, MACHOKE, GRAVELER and HAUNTER.
const EXPECTED_TRADES: Dictionary = {
	64: 0xFF, 67: 0xFF, 75: 0xFF, 93: 0xFF,
	61: 0x52,   # POLIWHIRL, KING'S ROCK
	79: 0x52,   # SLOWPOKE, KING'S ROCK
	95: 0x8F,   # ONIX, METAL COAT
	123: 0x8F,  # SCYTHER, METAL COAT
	117: 0x97,  # SEADRA, DRAGON SCALE
	137: 0xAC,  # PORYGON, UP-GRADE
}


func run(r: RefCounted) -> void:
	_r = r
	for game_id: StringName in _r.GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_census(game_id, data)
		_verify_trades(game_id, data)


## Every row of every species: the method is one the source defines, the target
## is a species this cache has, and `EVOLVE_STAT` carries the extra condition
## byte its four-byte entry is read for.
func _census(game_id: StringName, data: GameData) -> void:
	var rows: int = 0
	for species: int in range(1, data.species_count() + 1):
		for row: Dictionary in data.evolutions(species):
			rows += 1
			var method: int = int(row.get("method", 0))
			if not _r.check(
				method in RomLayout.EVOLVE_METHODS,
				"%s: species %d carries evolution method %d." % [game_id, species, method]
			):
				continue
			var target: int = int(row.get("target", 0))
			_r.check(
				target >= 1 and target <= data.species_count()
					and not data.species(target).is_empty(),
				"%s: species %d evolves into %d, which this cache has no row for." % [
					game_id, species, target,
				]
			)
			_r.check(
				method != RomLayout.EVOLVE_STAT or int(row.get("condition", 0)) in [
					RomLayout.ATTACK_OVER_DEFENSE, RomLayout.ATTACK_UNDER_DEFENSE,
					RomLayout.ATTACK_EQUALS_DEFENSE,
				],
				"%s: species %d's EVOLVE_STAT row has no Attack/Defense condition." % [
					game_id, species,
				]
			)
	_r.check(
		rows == EXPECTED_ROWS,
		"%s: %d evolution rows, not %d." % [game_id, rows, EXPECTED_ROWS]
	)


## `.trade`, over the whole corpus rather than the ten rows alone: every species
## is asked, so a predicate that answered the wrong row would be as loud as one
## that answered none. An EVERSTONE refuses; a row with a held requirement
## refuses until the item is held and then says it is spent.
func _verify_trades(game_id: StringName, data: GameData) -> void:
	var found: Dictionary = {}
	for species: int in range(1, data.species_count() + 1):
		var mon: Gen2BattleMon = Gen2BattleMon.create(data, species, 50)
		if mon == null:
			continue
		var bare: Dictionary = Gen2Evolution.trade_evolution(data, mon)
		var wanted: int = int(EXPECTED_TRADES.get(species, 0))
		if wanted == 0:
			_r.check(
				bare.is_empty(),
				"%s: species %d answered a trade evolution it has no row for." % [
					game_id, species,
				]
			)
			continue
		found[species] = true
		if wanted == Gen2Evolution.TRADE_NO_ITEM:
			_r.check(
				not bare.is_empty() and not bare.has("consumes_held_item"),
				"%s: species %d asks for a held item it should not." % [game_id, species]
			)
		else:
			_r.check(
				bare.is_empty(),
				"%s: species %d evolved without holding $%02X." % [game_id, species, wanted]
			)
			mon.item = wanted
			var held: Dictionary = Gen2Evolution.trade_evolution(data, mon)
			_r.check(
				int(held.get("consumes_held_item", 0)) == wanted,
				"%s: species %d does not spend the $%02X it evolved by." % [
					game_id, species, wanted,
				]
			)
		mon.item = Gen2Evolution.EVERSTONE
		_r.check(
			Gen2Evolution.trade_evolution(data, mon).is_empty(),
			"%s: species %d evolved by trade while holding an EVERSTONE." % [game_id, species]
		)
	_r.check(
		found.size() == EXPECTED_TRADES.size(),
		"%s: %d trade evolutions, not %d." % [game_id, found.size(), EXPECTED_TRADES.size()]
	)
