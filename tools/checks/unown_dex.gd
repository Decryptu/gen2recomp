extends RefCounted

var _r: RefCounted = null

## Verifies the Unown dex against freshly imported real caches: `UnownWords`, the
## twenty-six pics `Pokedex_LoadUnownFrontpicTiles` draws from, `GetUnownLetter`
## over every DV word a Pokemon can carry, and `UnownWalls` on the eight Ruins of
## Alph patterns that ask for one.
##
## The whole corpus rather than a sample: all 65,536 DV words on each cartridge,
## every letter, every form's picture and every chamber wall. The words are a
## plain byte run behind their own pointer table, so a wrong offset lands on
## neighbouring data that still reads as letters; what says it is the right run
## is that each word opens on its own letter, that the run starts where the table
## ends, and that the three cartridges agree word for word.
##
##   Godot --headless --path . -s res://tools/validate.gd -- unown_dex

## `data/pokemon/unown_words.asm`'s first and last, either side of the run.
const FIRST_WORD: String = "ANGRY"
const LAST_WORD: String = "ZOOM"
## `UnownWordX`, the one word that is not a word.
const X_WORD: String = "XXXXX"

## Every DV word, which is what `GetUnownLetter` divides down to a letter.
const DV_WORDS: int = 0x10000

## The four Ruins of Alph chambers, which carry the same map numbers on all
## three cartridges: the eight rooms pokecrystal inserts sit behind them, so the
## group's shift is measured from further down. Each has a wall pattern either
## side of its doorway, and `CHAMBER_STAND` is a walkable cell to open on.
const CHAMBER_GROUP: int = 3
const CHAMBER_MAPS: Array[int] = [23, 24, 25, 26]
const CHAMBER_STAND := Vector2i(3, 3)
const WALLS_PER_CHAMBER: int = 2
## Enough acknowledgements to drain a sign's own text and the word behind it.
const WALL_DRAIN_STEPS: int = 6

var _first_words: PackedStringArray = PackedStringArray()


func run(r: RefCounted) -> void:
	_r = r
	_first_words = PackedStringArray()
	_r.each_game(_check_game)


func _check_game() -> void:
	_check_words()
	_check_pics()
	_check_letters()
	_check_dex_order()
	_check_walls()


func _check_words() -> void:
	var words: PackedStringArray = PackedStringArray()
	for form: int in range(1, RomLayout.UNOWN_FORMS + 1):
		words.append(_r.data.unown_word(form))
	if not _r.check(
		words.size() == RomLayout.UNOWN_FORMS,
		"the cache holds %d Unown words." % words.size()
	):
		return
	for form: int in RomLayout.UNOWN_FORMS:
		var letter: String = char("A".unicode_at(0) + form)
		_r.check(
			words[form].begins_with(letter),
			"Unown %s's word is \"%s\"." % [letter, words[form]]
		)
	_r.check(words[0] == FIRST_WORD, "Unown A's word is \"%s\"." % words[0])
	_r.check(
		words[RomLayout.UNOWN_FORMS - 1] == LAST_WORD,
		"Unown Z's word is \"%s\"." % words[RomLayout.UNOWN_FORMS - 1]
	)
	_r.check(words[23] == X_WORD, "Unown X's word is \"%s\"." % words[23])
	# A form outside the range is what a caller reading an empty dex slot asks
	# for, and it answers nothing rather than the neighbouring word.
	_r.check(_r.data.unown_word(0).is_empty(), "form 0 answers a word.")
	_r.check(
		_r.data.unown_word(RomLayout.UNOWN_FORMS + 1).is_empty(),
		"a form past Z answers a word."
	)
	if _first_words.is_empty():
		_first_words = words
	else:
		_r.check(
			_first_words == words, "the Unown words differ from the other cartridges."
		)


## The twenty-six front pics, since the dex draws one per form and the battle
## now draws the letter a wild Unown's DVs name.
func _check_pics() -> void:
	var lit: int = 0
	for form: int in RomLayout.UNOWN_FORMS:
		for back: bool in [false, true]:
			var pic: Dictionary = _r.data.unown_pic(form, back)
			if not _r.check(not pic.is_empty(), "Unown form %d has no pic." % form):
				continue
			var indices: PackedByteArray = _r.data.atlas_indices(String(pic["atlas"]))
			var atlas: Dictionary = _r.data.atlas(String(pic["atlas"]))
			var cell: Dictionary = Gen2PicImage.atlas_cell(indices, atlas, pic)
			if not _r.check(
				not cell.is_empty(), "Unown form %d did not crop out of its atlas." % form
			):
				continue
			var drawn: int = 0
			for index: int in cell["indices"] as PackedByteArray:
				if index != 0:
					drawn += 1
			_r.check(drawn > 0, "Unown form %d's %s pic is blank." % [
				form, "back" if back else "front",
			])
			lit += drawn
	_r.check(
		_r.data.unown_pic(RomLayout.UNOWN_FORMS).is_empty(),
		"a form past Z answers a pic."
	)
	_r.note("unown pics: %d forms, %d drawn pixels." % [RomLayout.UNOWN_FORMS, lit])


## `GetUnownLetter` over every DV word: each answers a letter in range, and the
## twenty-six bands are the divide's own, ten packed values each except Z's six.
## Only the middle two bits of each DV are read, so the 65,536 words collapse to
## 256 packed values and each letter is reached by 256 of them.
func _check_letters() -> void:
	var counts: Array[int] = []
	counts.resize(RomLayout.UNOWN_FORMS + 1)
	counts.fill(0)
	for dvs: int in DV_WORDS:
		var letter: int = Gen2Stats.unown_letter(dvs)
		if letter < 1 or letter > RomLayout.UNOWN_FORMS:
			_r.fail("DVs $%04X answer letter %d." % [dvs, letter])
			return
		counts[letter] += 1
	for letter: int in range(1, RomLayout.UNOWN_FORMS):
		_r.check(
			counts[letter] == 10 * 256,
			"letter %d is reached by %d DV words, not %d." % [
				letter, counts[letter], 10 * 256,
			]
		)
	_r.check(
		counts[RomLayout.UNOWN_FORMS] == 6 * 256,
		"Z is reached by %d DV words, not %d." % [
			counts[RomLayout.UNOWN_FORMS], 6 * 256,
		]
	)
	# The two ends, which say the packing is the source's rather than a shift
	# apart: every middle bit clear is A, every one set is Z.
	_r.check(Gen2Stats.unown_letter(0x0000) == 1, "all-zero DVs are not A.")
	_r.check(Gen2Stats.unown_letter(0xFFFF) == RomLayout.UNOWN_FORMS, "all-one DVs are not Z.")


## `DisplayUnownWords` on the maps that ask for it: the four Ruins of Alph
## chambers, both wall patterns of each. Crystal alone ships them, so this is
## eight words there and none on Gold and Silver, whose cells carry the puzzle
## sign instead.
func _check_walls() -> void:
	var said: PackedStringArray = PackedStringArray()
	for number: int in CHAMBER_MAPS:
		var chamber: Gen2WorldAPI = _r.open_world(
			CHAMBER_GROUP, number, CHAMBER_STAND
		)
		if chamber == null:
			continue
		for event: Dictionary in chamber.current_map.events.get("bg_events", []):
			var word: String = _wall_word(number, Vector2i(
				int(event["x"]), int(event["y"])
			))
			if not word.is_empty():
				said.append(word)
				_check_wall_box(number, word)
	if not _r.crystal:
		_r.check(said.is_empty(), "a Gold or Silver chamber said %s." % [said])
		return
	_r.check(
		said.size() == CHAMBER_MAPS.size() * WALLS_PER_CHAMBER,
		"the chambers said %d words, not %d." % [
			said.size(), CHAMBER_MAPS.size() * WALLS_PER_CHAMBER,
		]
	)
	var distinct: Dictionary = {}
	for word: String in said:
		distinct[word] = true
	_r.check(
		distinct.size() == RomLayout.UNOWN_WALL_COUNT,
		"the four chambers said %d distinct words: %s." % [distinct.size(), said]
	)
	_r.note("unown walls: %s." % " ".join(said))


## The box `DisplayUnownWords` draws that word in: `MenuHeaders_UnownWalls`'
## size, and every letter block drawn out of the chamber's own tileset rather
## than left as the frame's own blank. A letter whose tiles land outside the
## graphics the tileset ships is what this catches, since the charmap computes
## them rather than reading a table.
func _check_wall_box(number: int, word: String) -> void:
	var map: Gen2WorldMap = _r.data.world_map(CHAMBER_GROUP, number)
	var tileset: Gen2WorldTileset = _r.data.world_tileset(map.tileset) if map != null else null
	var image: Image = Gen2UnownWallPage.render(_r.data, tileset, map, word)
	if not _r.check(image != null, "map %d's \"%s\" box did not draw." % [number, word]):
		return
	var box: Gen2MenuBox = Gen2UnownWall.menu_box(word)
	_r.check(
		image.get_size() == box.border_size() * Gen2Font.TILE,
		"map %d's \"%s\" box is %s, not %s." % [
			number, word, image.get_size(), box.border_size() * Gen2Font.TILE,
		]
	)
	for index: int in word.length():
		var at: Vector2i = (
			Gen2UnownWall.block_position(box, index) - box.border_position()
		) * Gen2Font.TILE
		var colours: Dictionary = {}
		for y: int in Gen2Font.TILE * 2:
			for x: int in Gen2Font.TILE * 2:
				colours[image.get_pixelv(at + Vector2i(x, y))] = true
		_r.check(
			colours.size() > 1,
			"map %d's \"%s\" letter %d is one flat colour." % [number, word, index]
		)


## Faces the bg event at [param cell] and drains what it says, answering the
## word the wall spelled or an empty string when it said none. A refusal is a
## failure: every one of these cells is one a player walks up to and presses A on.
func _wall_word(number: int, cell: Vector2i) -> String:
	var world: Gen2WorldAPI = _r.open_world(
		CHAMBER_GROUP, number, cell + Vector2i(0, 1)
	)
	if world == null:
		return ""
	world.player_facing = Gen2WorldSprite.FACING_UP
	var results: Array = world.interact()
	var word: String = ""
	for step: int in WALL_DRAIN_STEPS:
		if results.is_empty():
			break
		var status: StringName = StringName(results[0].get("status", &""))
		if status == &"failed":
			# The puzzle sign shares these maps and has no host; a wall pattern
			# refusing is what this check exists to catch.
			if StringName(results[0].get("reason", &"")) != &"unsupported_phone_special":
				_r.fail("map %d's %s answered %s." % [
					number, cell, String(results[0].get("reason", &"failed")),
				])
			break
		if status != &"waiting":
			break
		var pending: Dictionary = world.pending_script_input()
		if pending.is_empty() or StringName(pending.get("type", &"")) != &"text":
			break
		var text: String = String(pending.get("text", ""))
		if pending.has("unown_wall"):
			word = text
		results = world.run_event_queue(true)
	return word


## `UpdateUnownDex` and `Pokedex_DrawUnownModeBG` over a real state: catching
## order, no duplicates, and the word the cursor lands on.
func _check_dex_order() -> void:
	var state := Gen2WorldState.new()
	var dex: Gen2Pokedex = Gen2Pokedex.open(_r.data, state, RomLayout.DEXMODE_NEW)
	_r.check(not dex.unown_unlocked(), "Unown mode is unlocked before the flag is set.")
	state.set_engine_flag(Gen2WorldState.ENGINE_UNOWN_DEX)
	_r.check(dex.unown_unlocked(), "the Unown dex flag does not unlock the mode.")
	_r.check(
		Gen2Pokedex.mode_rows(true).size() == Gen2Pokedex.MODE_ROWS.size(),
		"an unlocked OPTION screen does not offer four modes."
	)
	for form: int in [7, 26, 7, 1]:
		state.update_unown_dex(form)
	var caught: Array[int] = [7, 26, 1]
	_r.check(
		state.unown_dex() == caught,
		"the dex holds %s after G, Z, G, A." % [state.unown_dex()]
	)
	dex.open_unown_mode()
	_r.check(dex.selected_unown_form() == 7, "the cursor does not open on the first form.")
	_r.check(
		dex.unown_word() == _r.data.unown_word(7),
		"the cursor's word is \"%s\"." % dex.unown_word()
	)
	_r.check(dex.move_unown(Gen2Button.LEFT) == false, "the cursor moved left off the end.")
	_r.check(dex.move_unown(Gen2Button.RIGHT), "the cursor did not move right.")
	_r.check(dex.move_unown(Gen2Button.RIGHT), "the cursor did not reach the last form.")
	_r.check(dex.move_unown(Gen2Button.RIGHT) == false, "the cursor moved right off the end.")
	_r.check(
		dex.selected_unown_form() == 1 and dex.unown_word() == _r.data.unown_word(1),
		"the last form is %d." % dex.selected_unown_form()
	)
	# `.count_unown` stops at twenty-six however many times it is asked.
	for form: int in range(1, RomLayout.UNOWN_FORMS + 1):
		state.update_unown_dex(form)
	_r.check(
		state.unown_caught_count() == RomLayout.UNOWN_FORMS,
		"a full dex counts %d." % state.unown_caught_count()
	)
