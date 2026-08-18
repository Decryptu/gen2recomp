class_name Gen2MonStatsScreen
extends RefCounted

## The stats screen's model (`engine/pokemon/stats_screen.asm`): which member of
## a list is shown, which of the three pages is open, and what each page has to
## say about it. [Gen2StatsScreenPage] draws the answer.
##
## `StatsScreenInit` is opened over whatever screen asked for it and hands
## control back on the way out, so this owns no nodes: whoever embedded it draws
## [method snapshot] and feeds it [method handle_button].
##
## The list is the party in the two places STATS is reached from today, the
## overworld's `MonMenu_Stats` and a battle's own party menu. `wMonType` picks a
## different list on the cartridge (`sBoxMons`, the enemy's party, `wBufferMon`);
## the shape here is the same for any of them, which is why the mons are passed
## in rather than read out of a save.

## `StatsScreen_Exit`: B, or A on the last page.
signal closed
## `PlayMonCry2`, which `StatsScreen_PlaceFrontpic` plays when a mon is loaded
## and not when a page is turned. Emitted rather than played: the audio player
## belongs to whoever embedded this.
signal cry_requested(species: int)

const PINK_PAGE: int = Gen2StatsScreenPage.PINK_PAGE
const BLUE_PAGE: int = Gen2StatsScreenPage.BLUE_PAGE

var _data: GameData = null
var _mons: Array = []
var _cursor: int = 0
## `wStatsScreenFlags`' page bits, `StatsScreenMain` opening on `PINK_PAGE`.
var _page: int = PINK_PAGE


static func create(data: GameData, mons: Array, cursor: int = 0) -> Gen2MonStatsScreen:
	var out := Gen2MonStatsScreen.new()
	out._data = data
	out._mons = mons
	out._cursor = clampi(cursor, 0, maxi(mons.size() - 1, 0))
	return out


## `MonStatsInit` reaches `StatsScreen_PlaceFrontpic`, which plays the cry unless
## the Pokémon is an egg or `CheckFaintedFrzSlp` answers yes. Called by the host
## once the screen is up, and again by [method handle_button] on every UP or DOWN.
func announce() -> void:
	var mon: Gen2SaveMon = current()
	if mon == null or mon.is_egg:
		return
	if mon.hp <= 0 or Gen2Status.has(mon.status, Gen2Status.FREEZE) \
		or Gen2Status.is_asleep(mon.status):
		return
	cry_requested.emit(mon.species)


func current() -> Gen2SaveMon:
	if _cursor < 0 or _cursor >= _mons.size():
		return null
	return _mons[_cursor] as Gen2SaveMon


func cursor() -> int:
	return _cursor


## `StatsScreen_JoypadAction`. Returns whether the button was used.
func handle_button(button: int) -> bool:
	## `EggStatsJoypad` masks the joypad down to `PAD_DOWN | PAD_UP | PAD_A |
	## PAD_B` before it reaches the same action, and answers A with the exit
	## rather than with a page: an egg has no pages to turn.
	var egg: bool = current() != null and current().is_egg
	match button:
		Gen2Button.B:
			closed.emit()
			return true
		Gen2Button.A:
			if egg or _page == BLUE_PAGE:
				closed.emit()
				return true
			_turn_page(1)
			return true
		Gen2Button.RIGHT:
			if egg:
				return false
			_turn_page(1)
			return true
		Gen2Button.LEFT:
			if egg:
				return false
			_turn_page(-1)
			return true
		Gen2Button.UP:
			return _move_cursor(-1)
		Gen2Button.DOWN:
			return _move_cursor(1)
	return false


## `.d_right` and `.d_left`: the pages wrap in both directions, and a page change
## reloads the lower half without reloading the Pokémon.
func _turn_page(delta: int) -> void:
	_page = wrapi(_page - PINK_PAGE + delta, 0, Gen2StatsScreenPage.NUM_PAGES) + PINK_PAGE


## `.d_up` and `.d_down`: neither wraps, and the row the party menu is left on
## follows the one this screen lands on (`wPartyMenuCursor`).
func _move_cursor(delta: int) -> bool:
	var next: int = _cursor + delta
	if next < 0 or next >= _mons.size():
		return false
	_cursor = next
	announce()
	return true


## Everything [Gen2StatsScreenPage] draws, for the member the cursor is on.
func snapshot() -> Dictionary:
	var mon: Gen2SaveMon = current()
	if mon == null or _data == null:
		return {"egg": true, "page": _page, "egg_message": ""}
	if mon.is_egg:
		## `wTempMonHappiness` holds an egg's remaining step count rather than a
		## happiness value, which is what `EggStatsScreen` reads it as.
		return {
			"egg": true,
			"page": _page,
			"species": mon.species,
			"egg_message": Gen2StatsScreenPage.egg_message(mon.happiness),
		}

	var battle_mon: Gen2BattleMon = Gen2SaveBattleAdapter.to_battle_mon(_data, mon)
	var species: Dictionary = _data.species(mon.species)
	var out: Dictionary = {
		"egg": false,
		"page": _page,
		"species": mon.species,
		"dex_number": mon.species,
		"species_name": String(species.get("name", "")),
		"nickname": mon.nickname if not mon.nickname.is_empty() \
			else String(species.get("name", "")),
		"level": mon.level,
		"gender": Gen2BattleMon.gender_for(_data, mon.species, mon.dvs),
		"shiny": Gen2Stats.is_shiny(mon.dvs),
		"hp": mon.hp,
		"max_hp": battle_mon.max_hp() if battle_mon != null else 0,
		"status": mon.status,
		"fainted": mon.hp <= 0,
		"pokerus": mon.pokerus,
		"types": _types(species),
		"item_name": _data.item_name(mon.item) if mon.item != 0 \
			else Gen2StatsScreenPage.THREE_DASHES,
		"moves": _moves(mon),
		"ot_id": mon.ot_id,
		"ot_name": mon.original_trainer,
		## `.PlaceOTInfo` reads the whole caught-data byte, which this save model
		## splits into a gender bit and a location.
		"caught_gender": (mon.caught_gender << 7) | mon.caught_location,
		"stats": battle_mon.stats if battle_mon != null else {},
	}
	out.merge(_experience(mon))
	return out


## `PrintMonTypes`: a single-typed species really carries the same type twice and
## the second line is erased rather than printed.
func _types(species: Dictionary) -> Array:
	var pair: Array = species.get("types", [0, 0])
	var first: int = int(pair[0])
	var second: int = int(pair[1]) if pair.size() > 1 else first
	var out: Array = [_data.type_name(first)]
	if second != first:
		out.append(_data.type_name(second))
	return out


## `ListMoves` and `ListMovePP` over `wTempMonMoves`: an empty slot ends the list
## and the page draws dashes for the rest.
func _moves(mon: Gen2SaveMon) -> Array:
	var out: Array = []
	for slot: int in mon.moves.size():
		var number: int = int(mon.moves[slot])
		if number <= 0:
			break
		var record: Dictionary = _data.move(number)
		out.append({
			"name": String(record.get("name", "")),
			"pp": int(mon.pp[slot]) if slot < mon.pp.size() else 0,
			## `GetMaxPPOfMove` adds the PP Up bits, which this save model masks
			## off when it reads a party struct, so the base is the maximum.
			"max_pp": int(record.get("pp", 0)),
		})
	return out


## `.PrintNextLevel` and `.CalcExpToNextLevel`, which both leave a level 100
## Pokémon where it is: the next level is 100 again and the debt is zero.
func _experience(mon: Gen2SaveMon) -> Dictionary:
	var rate: int = int(
		_data.species(mon.species).get("growth_rate", Gen2Experience.GROWTH_MEDIUM_FAST)
	)
	if mon.level >= Gen2Experience.MAX_LEVEL:
		return {
			"exp": mon.exp,
			"next_level": Gen2Experience.MAX_LEVEL,
			"exp_to_next": 0,
			"exp_pixels": Gen2ExpBarAnimation.LENGTH_PX,
		}
	return {
		"exp": mon.exp,
		"next_level": mon.level + 1,
		"exp_to_next": maxi(Gen2Experience.total_exp_at(rate, mon.level + 1) - mon.exp, 0),
		"exp_pixels": Gen2ExpBarAnimation.pixels_for(rate, mon.level, mon.exp),
	}
