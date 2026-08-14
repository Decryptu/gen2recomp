extends RefCounted

var _r: RefCounted = null

## Verifies the Pokemon Center PC's imported menu tables against freshly
## imported real caches, in all three games.
##
## Expected values come from the pinned pokecrystal and pokegold sources:
## `engine/events/pokecenter_pc.asm`'s `PokemonCenterPC.Jumptable`, its
## `.WhichPC`, `PlayersPCMenuData.PlayersPCMenuPointers` and that menu's own
## `.WhichPC`, plus the fourteen `text_far` stubs the two routines print
## through.
##
## One pinned address per cartridge finds all of it, so what says the address is
## right is the content: two runs of `@`-terminated strings, five lists whose
## entries all name rows those runs have, and fourteen stubs that decode. The
## three games ship the block identical bar the two boxes that carry a
## `text_ram` and a `text_decimal` slot, whose addresses are each cartridge's own
## WRAM; that is checked here rather than assumed.
##
##   Godot --headless --path . -s res://tools/validate.gd -- pokecenter_pc

## `.Jumptable`'s strings, in its own order. The first keeps the `<PLAYER>`
## marker the cartridge stores.
const EXPECTED_ROWS: Dictionary = {
	"players_pc": "<PLAYER>'s PC",
	"bills_pc": "BILL's PC",
	"oaks_pc": "PROF.OAK's PC",
	"hall_of_fame": "HALL OF FAME",
	"turn_off": "TURN OFF",
}
## `PlayersPCMenuPointers`' strings. `.TurnOff` is laid down before `.LogOff`,
## which is not the jumptable's own order; the importer keys both by name so
## nothing downstream counts positions.
const EXPECTED_PLAYERS_ROWS: Dictionary = {
	"withdraw_item": "WITHDRAW ITEM",
	"deposit_item": "DEPOSIT ITEM",
	"toss_item": "TOSS ITEM",
	"mail_box": "MAIL BOX",
	"decoration": "DECORATION",
	"turn_off": "TURN OFF",
	"log_off": "LOG OFF",
}
## `.WhichPC` for each menu, as the jumptable rows every list offers.
const EXPECTED_LISTS: Array[Array] = [[1, 0, 4], [1, 0, 2, 4], [1, 0, 2, 3, 4]]
const EXPECTED_PLAYERS_LISTS: Array[Array] = [
	[0, 1, 2, 3, 5], [0, 1, 2, 3, 4, 6],
]
## The texts, by the opening of each: enough to say which stub decoded without
## pinning a whole box.
const EXPECTED_TEXT_OPENINGS: Dictionary = {
	"ask_what_do": "What do you want",
	"how_many_withdraw": "How many do you",
	"withdrew": "Withdrew ",
	"no_room_withdraw": "There's no room",
	"no_items": "No items here!",
	"how_many_deposit": "How many do you",
	"deposited": "Deposited ",
	"no_room_deposit": "There's no room to",
	"turn_on": "<PLAYER> turned on",
	"whose": "Access whose PC?",
	"bills_pc": "BILL's PC",
	"players_pc": "Accessed own PC.",
	"oaks_pc": "PROF.OAK's PC",
	"closed": "…",
}

var _blocks: Dictionary = {}


func run(r: RefCounted) -> void:
	_r = r
	for game_id: StringName in _r.GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_r.game_id = game_id
		_verify_rows(data)
		_verify_lists(data)
		_verify_texts(data)
		_blocks[game_id] = _flatten(data)
	_r.game_id = &""
	_verify_identical()


func _verify_rows(data: GameData) -> void:
	for name: String in EXPECTED_ROWS:
		_r.check(
			data.pokecenter_pc_row(name) == String(EXPECTED_ROWS[name]),
			"top row %s is \"%s\", not \"%s\"" % [
				name, data.pokecenter_pc_row(name), EXPECTED_ROWS[name],
			]
		)
	for name: String in EXPECTED_PLAYERS_ROWS:
		_r.check(
			data.pokecenter_pc_row(name, true) == String(EXPECTED_PLAYERS_ROWS[name]),
			"item PC row %s is \"%s\", not \"%s\"" % [
				name, data.pokecenter_pc_row(name, true), EXPECTED_PLAYERS_ROWS[name],
			]
		)


func _verify_lists(data: GameData) -> void:
	for players: bool in [false, true]:
		var expected: Array[Array] = EXPECTED_PLAYERS_LISTS if players else EXPECTED_LISTS
		var lists: Array = data.pokecenter_pc_lists(players)
		if not _r.check(
			lists.size() == expected.size(),
			"%s has %d lists, not %d" % [
				"the item PC" if players else "the top menu", lists.size(), expected.size(),
			]
		):
			continue
		for index: int in expected.size():
			_r.check(
				lists[index] == expected[index],
				"%s list %d is %s, not %s" % [
					"item PC" if players else "top menu", index,
					JSON.stringify(lists[index]), JSON.stringify(expected[index]),
				]
			)


func _verify_texts(data: GameData) -> void:
	for name: String in EXPECTED_TEXT_OPENINGS:
		var text: String = data.pokecenter_pc_text(name)
		_r.check(
			text.begins_with(String(EXPECTED_TEXT_OPENINGS[name])),
			"text %s opens \"%s\", not \"%s\"" % [
				name, text.substr(0, 24), EXPECTED_TEXT_OPENINGS[name],
			]
		)


## Everything the block holds, as one comparable value.
func _flatten(data: GameData) -> Array:
	var out: Array = []
	for name: String in EXPECTED_ROWS:
		out.append(data.pokecenter_pc_row(name))
	for name: String in EXPECTED_PLAYERS_ROWS:
		out.append(data.pokecenter_pc_row(name, true))
	for players: bool in [false, true]:
		out.append(data.pokecenter_pc_lists(players))
	for name: String in EXPECTED_TEXT_OPENINGS:
		out.append(_without_slots(data.pokecenter_pc_text(name)))
	return out


## A box's `<RAM_xxxx>` and `<NUM_xxxx>` markers with their addresses dropped.
static func _without_slots(text: String) -> String:
	var out: String = ""
	var rest: String = text
	while true:
		var start: int = rest.find("<")
		var end: int = rest.find(">", start)
		if start < 0 or end < 0:
			return out + rest
		var marker: String = rest.substr(start, end - start + 1)
		out += rest.substr(0, start)
		out += marker.split("_")[0] + ">" if marker.contains("_") else marker
		rest = rest.substr(end + 1)
	return out


## The three cartridges ship the block identical, so a wrong address on one of
## them shows up here even where the content checks above pass. The two boxes
## that name a WRAM slot are compared with the slot's own address dropped, since
## that is what legitimately differs.
func _verify_identical() -> void:
	var first: StringName = &""
	for game_id: StringName in _blocks:
		if first == &"":
			first = game_id
			continue
		_r.check(
			_blocks[game_id] == _blocks[first],
			"%s's PC block differs from %s's" % [game_id, first]
		)
	_r.note("pokecenter_pc: %d cartridges, %d rows, %d lists, %d texts" % [
		_blocks.size(),
		EXPECTED_ROWS.size() + EXPECTED_PLAYERS_ROWS.size(),
		EXPECTED_LISTS.size() + EXPECTED_PLAYERS_LISTS.size(),
		EXPECTED_TEXT_OPENINGS.size(),
	])
