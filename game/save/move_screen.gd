class_name Gen2MoveScreen
extends RefCounted

## The move screen's model (`MoveScreenLoop` in `engine/pokemon/mon_menu.asm`):
## which member of the party is shown, which of its moves the cursor is on, and
## which one is being moved. [Gen2MoveScreenPage] draws the answer.
##
## `ManagePokemonMoves` is opened over the party menu and hands control back on
## the way out, so this owns no nodes, exactly like [Gen2MonStatsScreen]. The two
## moves that trade places trade their PP with them, which is `.place_move`
## copying `wPartyMon1Moves` and `wPartyMon1PP` in the same shape.

## `.exit`, which is B with nothing held.
signal closed
## `PlayClickSFX` on every press this screen answers, and `SFX_SWITCH_POKEMON`
## twice once two moves have traded places.
signal sfx_requested(index: int, waited: bool)

## `constants/sfx_constants.asm`.
const SFX_READ_TEXT_2: int = 0x08
const SFX_SWITCH_POKEMON: int = Gen2PartyScreen.SFX_SWITCH_POKEMON

var _data: GameData = null
var _party: Array = []
var _cursor: int = 0
## `wMenuCursorY` less one: the row the arrow is on.
var _row: int = 0
## `wSwappingMove` less one: the row being moved, or -1 when nothing is held.
var _held: int = -1


static func create(data: GameData, party: Array, start_cursor: int = 0) -> Gen2MoveScreen:
	var out := Gen2MoveScreen.new()
	out._data = data
	out._party = party
	out._cursor = clampi(start_cursor, 0, maxi(party.size() - 1, 0))
	return out


func current() -> Gen2SaveMon:
	if _cursor < 0 or _cursor >= _party.size():
		return null
	return _party[_cursor] as Gen2SaveMon


func cursor() -> int:
	return _cursor


## `MoveScreenLoop`'s joypad block, which `ScrollingMenuJoypad` has already
## narrowed to the control pad, A and B. Returns whether the button was used.
func handle_button(button: int) -> bool:
	match button:
		Gen2Button.B:
			sfx_requested.emit(SFX_READ_TEXT_2, false)
			## `.b_button`: a held move is put back where it came from and the
			## screen stays up; nothing held is the way out.
			if _held >= 0:
				_row = _held
				_held = -1
				return true
			closed.emit()
			return true
		Gen2Button.A:
			sfx_requested.emit(SFX_READ_TEXT_2, false)
			if _held < 0:
				_held = _row
				return true
			_swap(_held, _row)
			_held = -1
			return true
		Gen2Button.UP:
			return _move_row(-1)
		Gen2Button.DOWN:
			return _move_row(1)
		Gen2Button.LEFT:
			return _cycle(-1)
		Gen2Button.RIGHT:
			return _cycle(1)
	return false


## `Load2DMenuData`'s own wrap: the list is a single column of `wNumMoves + 1`
## rows and the cursor runs round it.
func _move_row(delta: int) -> bool:
	var rows: int = _move_count()
	if rows <= 0:
		return false
	_row = wrapi(_row + delta, 0, rows)
	return true


## `.cycle_right` and `.cycle_left`: a step past either end and a step onto an
## egg both turn round, so the screen never lands on a member it cannot list.
## `.d_left` and `.d_right` refuse outright while a move is held.
func _cycle(delta: int) -> bool:
	if _held >= 0:
		return false
	var found: int = _next_listable(delta)
	if found < 0 or found == _cursor:
		return false
	_cursor = found
	_row = 0
	return true


## Whether there is a member that way worth an arrow, which is what
## `PlaceMoveScreenLeftArrow` and its sibling walk the party for.
func has_neighbour(delta: int) -> bool:
	var found: int = _next_listable(delta)
	return found >= 0 and found != _cursor


func _next_listable(delta: int) -> int:
	var at: int = _cursor + delta
	while at >= 0 and at < _party.size():
		var mon: Gen2SaveMon = _party[at] as Gen2SaveMon
		if mon != null and not mon.is_egg:
			return at
		at += delta
	return -1


func _move_count() -> int:
	var mon: Gen2SaveMon = current()
	if mon == null:
		return 0
	var count: int = 0
	for move: Variant in mon.moves:
		if int(move) <= 0:
			break
		count += 1
	return count


## `.place_move`: the two rows trade their move and their PP together, and the
## same row twice is a swap with itself, which the source performs and which
## changes nothing.
func _swap(from: int, to: int) -> void:
	var mon: Gen2SaveMon = current()
	if mon == null or from == to:
		return
	var move: int = int(mon.moves[from])
	mon.moves[from] = mon.moves[to]
	mon.moves[to] = move
	var pp: int = int(mon.pp[from])
	mon.pp[from] = mon.pp[to]
	mon.pp[to] = pp
	## `.swap_moves` plays the same effect twice, waiting for each.
	## `SwitchPartyMons` is `WaitPlaySFX`, twice over.
	sfx_requested.emit(SFX_SWITCH_POKEMON, true)
	sfx_requested.emit(SFX_SWITCH_POKEMON, true)


## Everything [Gen2MoveScreenPage] draws.
func snapshot() -> Dictionary:
	var mon: Gen2SaveMon = current()
	if mon == null or _data == null:
		return {"moves": [], "cursor": 0, "held": -1}
	var moves: Array = []
	for slot: int in mon.moves.size():
		var number: int = int(mon.moves[slot])
		if number <= 0:
			break
		var record: Dictionary = _data.move(number)
		moves.append({
			"name": String(record.get("name", "")),
			"pp": int(mon.pp[slot]) if slot < mon.pp.size() else 0,
			"max_pp": int(record.get("pp", 0)),
			"power": int(record.get("power", 0)),
			"type_name": _data.type_name(int(record.get("type", 0))),
			"description": String(record.get("description", "")),
		})
	## `SetUpMoveScreenBG`'s `SetHPPal` colours the box beside the nickname, and
	## the pixel count it reads is `wPlayerHPPal`'s last writer rather than a
	## fresh one, which in play is this Pokémon's own bar in the party list.
	var battle_mon: Gen2BattleMon = Gen2SaveBattleAdapter.to_battle_mon(_data, mon)
	return {
		"species": mon.species,
		"hp": mon.hp,
		"max_hp": battle_mon.max_hp() if battle_mon != null else 0,
		"nickname": mon.nickname if not mon.nickname.is_empty() \
			else String(_data.species(mon.species).get("name", "")),
		"level": mon.level,
		"moves": moves,
		"cursor": clampi(_row, 0, maxi(moves.size() - 1, 0)),
		"held": _held,
		"previous": has_neighbour(-1),
		"next": has_neighbour(1),
	}
