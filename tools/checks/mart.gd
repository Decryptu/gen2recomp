extends RefCounted

var _r: RefCounted = null

## Verifies the mart's own boxes and its buy screen against freshly imported
## real caches, over every mart the cartridge ships rather than a sampled one.
##
## Expected values come from the pinned pokecrystal and pokegold sources:
## `engine/items/mart.asm`'s `GetMartDialogGroup.MartTextFunctionPointers`, the
## twenty-nine `text_far` stubs behind it, and `MenuHeader_Buy`'s own geometry.
##
## One pinned address per cartridge finds every text, so what says the address
## is right is the content: each stub has to decode, each group's opening has to
## be that shop's own words, and every marker a box carries has to be one of the
## three values `MartConfirmPurchase` fills. The screen itself is swept by
## drawing all thirty-four marts: a name or a price that ran past the list's own
## columns is what a wrong geometry looks like.
##
##   Godot --headless --path . -s res://tools/validate.gd -- mart

## Enough of each group's boxes to say which stub decoded, without pinning a
## whole one. `bargain_sold_out` is the only refusal that is not shared.
const EXPECTED_TEXT_OPENINGS: Dictionary = {
	"welcome": "Welcome! How may I",
	"come_again": "Please come again!",
	"ask_more": "Can I do anything",
	"how_many": "How many?",
	"thanks": "Here you are.",
	"no_money": "You don't have",
	"pack_full": "You can't carry",
	"bitter_intro": "Hello, dear.",
	"bitter_come_again": "Come again, dear.",
	"bargain_intro": "Hiya! Care to see",
	"bargain_sold_out": "You bought that",
	"bargain_thanks": "Thanks.",
	"pharmacy_intro": "What's up? Need",
	"pharmacy_come_again": "All right.",
}

## The three values a mart box leaves a marker for. `hMoneyTemp` is HRAM and
## `wItemQuantityChange` is not, which is how the two numbers are told apart.
const HRAM_FIRST: int = 0xFF00

## Which boxes carry which markers, as the count of each. Read off the source's
## own `text_ram` and `text_decimal` lines.
const EXPECTED_MARKERS: Dictionary = {
	"final_price": {"name": 1, "quantity": 1, "total": 1},
	"bitter_final_price": {"name": 1, "quantity": 1, "total": 1},
	"pharmacy_final_price": {"name": 1, "quantity": 1, "total": 1},
	"bargain_final_price": {"name": 1, "quantity": 0, "total": 1},
}

## The screen's own width. A name prints from column 2 and its price from
## column 10 of the row below, so the two never collide however long the name
## is: what a wrong geometry looks like is a row running off the right edge.
const SCREEN_COLUMNS: int = 20


func run(r: RefCounted) -> void:
	_r = r
	for game_id: StringName in _r.GAME_IDS:
		var data: GameData = GameData.open(game_id)
		if data == null:
			_r.fail("%s cache is unavailable. Import roms/%s.gbc first." % [game_id, game_id])
			continue
		_r.game_id = game_id
		_verify_texts(data)
		_verify_markers(data)
		_verify_lists(data)
	_r.game_id = &""


func _verify_texts(data: GameData) -> void:
	var decoded: int = 0
	for name: String in RomLayout.MART_TEXT_AT:
		if not data.mart_text(name).is_empty():
			decoded += 1
	_r.check(
		decoded == RomLayout.MART_TEXT_AT.size(),
		"%d of %d mart texts decoded" % [decoded, RomLayout.MART_TEXT_AT.size()]
	)
	for name: String in EXPECTED_TEXT_OPENINGS:
		var text: String = data.mart_text(name)
		_r.check(
			text.begins_with(String(EXPECTED_TEXT_OPENINGS[name])),
			"text %s opens \"%s\", not \"%s\"" % [
				name, text.substr(0, 24), EXPECTED_TEXT_OPENINGS[name],
			]
		)


## Every marker in every box, counted by kind. A box carrying one the screen
## cannot fill would print `<NUM_C2DE>` at the player.
func _verify_markers(data: GameData) -> void:
	for name: String in RomLayout.MART_TEXT_AT:
		var counts: Dictionary = _markers(data.mart_text(name))
		var expected: Dictionary = EXPECTED_MARKERS.get(
			name, {"name": 0, "quantity": 0, "total": 0}
		)
		_r.check(
			counts == expected,
			"text %s carries %s, not %s" % [
				name, JSON.stringify(counts), JSON.stringify(expected),
			]
		)


func _markers(text: String) -> Dictionary:
	var out: Dictionary = {"name": 0, "quantity": 0, "total": 0}
	var at: int = 0
	while true:
		at = text.find(Gen2TextStream.NUMBER_MARKER, at)
		if at < 0:
			break
		var end: int = text.find(">", at)
		var address: int = text.substr(
			at + Gen2TextStream.NUMBER_MARKER.length(),
			end - at - Gen2TextStream.NUMBER_MARKER.length()
		).hex_to_int()
		out["total" if address >= HRAM_FIRST else "quantity"] += 1
		at = end + 1
	at = 0
	while true:
		at = text.find(Gen2TextStream.RAM_MARKER, at)
		if at < 0:
			break
		out["name"] += 1
		at += 1
	return out


## Every mart the cartridge ships, drawn through the buy screen's own columns.
func _verify_lists(data: GameData) -> void:
	var marts: Array = _marts(data)
	var rows: int = 0
	for mart: Dictionary in marts:
		for entry: Dictionary in Gen2WorldMartHost.entries(data, mart):
			rows += 1
			var name: String = String(entry.get("name", ""))
			_r.check(
				Gen2MartPage.NAME_AT.x + Gen2Text.encoded_length(name) <= SCREEN_COLUMNS,
				"%s is %d tiles, which runs past the screen" % [
					name, Gen2Text.encoded_length(name),
				]
			)
			var price: String = Gen2MartPage.money_string(int(entry.get("price", 0)))
			_r.check(
				Gen2MartPage.PRICE_COLUMN + price.length() <= SCREEN_COLUMNS,
				"%s costs %s, which runs past the screen" % [name, price.strip_edges()]
			)
	_r.check(rows > 0, "no mart in this cache carries a row")
	_r.note("%d marts, %d rows" % [marts.size(), rows])


## The indexed marts plus whichever specials this profile ships, which is what
## `OpenMartDialog` can reach.
func _marts(data: GameData) -> Array:
	var out: Array = []
	for index: int in data.world_mart_count():
		var mart: Dictionary = data.world_mart(index)
		if not mart.is_empty():
			out.append(mart)
	for special: StringName in [&"bargain", &"rooftop_mart_1", &"rooftop_mart_2"]:
		var mart: Dictionary = data.world_mart_special(special)
		if not mart.is_empty():
			out.append(mart)
	return out
