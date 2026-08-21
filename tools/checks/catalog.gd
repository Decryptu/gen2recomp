extends RefCounted

var _r: RefCounted = null

## Verifies [Gen2WorldCatalog] against freshly imported real caches, on all three
## cartridges.
##
## The catalog is derived, not imported: it walks the decoded scripts and the map
## events and calls certain shapes starters, gifts, statics, trades, prizes,
## items, badges and shops. A derivation like that is exactly the thing that
## quietly stops being true, so what is pinned here is not a count alone but the
## SEMANTICS: the three starters are Chikorita, Cyndaquil and Totodile, the
## badges are sixteen distinct ones, the legendaries are among the statics at
## their own levels, and the Game Corner's prices are the cartridge's.
##
## A census pin catches a decode that drifts. A semantic pin catches a decode
## that drifts into something still plausible, which is the failure a census
## cannot see.
##
##   Godot --headless --path . -s res://tools/validate.gd -- catalog

## constants/pokemon_constants.asm.
const CHIKORITA: int = 152
const CYNDAQUIL: int = 155
const TOTODILE: int = 158
const LUGIA: int = 249
const HO_OH: int = 250
const CELEBI: int = 251
const SUICUNE: int = 245
const SUDOWOODO: int = 185
const SNORLAX: int = 143
const RED_GYARADOS: int = 130

## Per game: total rows, and the count under each kind in
## [constant Gen2WorldCatalog.KINDS]' own order.
const EXPECTED_CENSUS: Dictionary = {
	&"gold": [465, 3, 9, 15, 8, 9, 352, 16, 53],
	&"silver": [465, 3, 9, 15, 8, 9, 352, 16, 53],
	&"crystal": [532, 3, 11, 14, 9, 6, 419, 16, 54],
}

## The legendaries and set pieces every profile has to place, and at what level.
## `maps/*.asm`'s own `loadwildmon` operands.
const EXPECTED_STATICS: Dictionary = {
	&"gold": {LUGIA: [70, 40], HO_OH: [40, 70], SNORLAX: [50], SUDOWOODO: [20]},
	&"silver": {LUGIA: [70, 40], HO_OH: [40, 70], SNORLAX: [50], SUDOWOODO: [20]},
	&"crystal": {
		LUGIA: [60], HO_OH: [60], CELEBI: [30], SUICUNE: [40],
		SNORLAX: [50], SUDOWOODO: [20], RED_GYARADOS: [30],
	},
}

## `maps/GoldenrodGameCorner.asm` and `maps/CeladonGameCorner.asm`'s own
## `EQU` prices, in the order the corpus walk reaches them.
const EXPECTED_PRIZE_PRICES: Dictionary = {
	&"gold": [200, 700, 2100, 200, 700, 2100, 3333, 6666, 9999],
	&"silver": [200, 700, 2100, 200, 700, 2100, 3333, 6666, 9999],
	&"crystal": [100, 800, 1500, 2222, 5555, 8888],
}


func run(r: RefCounted) -> void:
	_r = r
	_r.each_game(func() -> void:
		var catalog: Gen2WorldCatalog = _r.data.catalog()
		_verify_census(catalog)
		_verify_starters(catalog)
		_verify_statics(catalog)
		_verify_prizes(catalog)
		_verify_badges(catalog)
		_verify_ids(catalog)
		_verify_patching(catalog)
		_verify_links(catalog)
		_verify_progression(catalog)
		_verify_sidecar(catalog)
	)


## The sidecar is what a player actually reads: the scan costs thirteen seconds
## and runs at import, and every check above this one ran against whatever
## [method GameData.catalog] handed back. So this asks the other question, that
## a restored catalog and a freshly scanned one are the same catalog, every row,
## every link and every kind's order.
func _verify_sidecar(catalog: Gen2WorldCatalog) -> void:
	var written: Variant = RomCache.read_json(
		RomCache.world_catalog_path(_r.data.directory)
	)
	if not _r.check(written is Dictionary, "the import wrote no catalog sidecar."):
		return
	var restored: Gen2WorldCatalog = Gen2WorldCatalog.from_dict(_r.data, written)
	if not _r.check(restored != null, "the catalog sidecar does not restore."):
		return
	var scanned: Gen2WorldCatalog = Gen2WorldCatalog.build(_r.data)
	_r.check(
		restored.to_dict() == scanned.to_dict(),
		"the sidecar and a fresh scan disagree."
	)
	## And the one thing `to_dict` cannot say: that what the runtime asks for
	## comes back the same, patches folded in and all.
	for kind: StringName in Gen2WorldCatalog.KINDS:
		_r.check(
			restored.ids(kind) == scanned.ids(kind),
			"%s ids differ between the sidecar and a fresh scan." % kind
		)
		for id: int in scanned.ids(kind):
			if restored.check(id) != scanned.check(id):
				_r.check(false, "row %d differs between the sidecar and a scan." % id)
				return


func _verify_census(catalog: Gen2WorldCatalog) -> void:
	var found: Array = [catalog.size()]
	for kind: StringName in Gen2WorldCatalog.KINDS:
		found.append(catalog.ids(kind).size())
	var expected: Array = EXPECTED_CENSUS[_r.game_id]
	_r.note("catalog %d rows: %s." % [catalog.size(), str(found.slice(1))])
	_r.check(
		found == expected,
		"census is %s, not the pinned %s." % [str(found), str(expected)]
	)


## The one shape only Elm's three balls take: a `pokepic` of the species a
## `givepoke` in the same script hands over. If that stops being unique, this is
## where it shows.
func _verify_starters(catalog: Gen2WorldCatalog) -> void:
	var found: Array[int] = catalog.possible_starters()
	found.sort()
	var wanted: Array[int] = [CHIKORITA, CYNDAQUIL, TOTODILE]
	_r.check(
		found == wanted, "starters are %s, not the three Elm offers." % str(found)
	)
	for row: Dictionary in catalog.rows(Gen2WorldCatalog.KIND_STARTER):
		_r.check(
			int(row["level"]) == 5,
			"a starter is offered at level %d rather than 5." % int(row["level"])
		)


func _verify_statics(catalog: Gen2WorldCatalog) -> void:
	var levels: Dictionary = {}
	for row: Dictionary in catalog.rows(Gen2WorldCatalog.KIND_STATIC):
		var species: int = int(row["species"])
		var list: Array = levels.get(species, [])
		list.append(int(row["level"]))
		levels[species] = list
	for species: int in EXPECTED_STATICS[_r.game_id]:
		var wanted: Array = EXPECTED_STATICS[_r.game_id][species]
		var found: Array = levels.get(species, [])
		found.sort()
		var sorted_wanted: Array = wanted.duplicate()
		sorted_wanted.sort()
		_r.check(
			found == sorted_wanted,
			"species %d stands at %s, not the pinned %s." % [
				species, str(found), str(sorted_wanted),
			]
		)


## A prize is a give site with a `takecoins` behind it, and the price has to be
## the one for THAT branch rather than the first one in the vendor's script.
func _verify_prizes(catalog: Gen2WorldCatalog) -> void:
	var prices: Array = []
	for row: Dictionary in catalog.rows(Gen2WorldCatalog.KIND_PRIZE):
		prices.append(int(row["price"]))
	_r.check(
		prices == EXPECTED_PRIZE_PRICES[_r.game_id],
		"prize prices are %s, not the pinned %s." % [
			str(prices), str(EXPECTED_PRIZE_PRICES[_r.game_id]),
		]
	)


## Sixteen badges exist and each is granted somewhere. Gold and Silver set two of
## them from a second script as well, which is why the row count is not the badge
## count and why the test is over the SET rather than the list.
func _verify_badges(catalog: Gen2WorldCatalog) -> void:
	var seen: Dictionary = {}
	for row: Dictionary in catalog.rows(Gen2WorldCatalog.KIND_BADGE):
		seen[int(row["badge"])] = true
		_r.check(
			catalog.is_progression(row), "badge %d is not progression." % int(row["badge"])
		)
	var badges: Array = seen.keys()
	badges.sort()
	_r.check(
		badges.size() == Gen2WorldState.BADGE_ENGINE_FLAGS.size(),
		"%d distinct badges are granted, not %d." % [
			badges.size(), Gen2WorldState.BADGE_ENGINE_FLAGS.size(),
		]
	)


## An id has to name one site and be recomputable from the site's own address,
## since that is what a runtime reader does. Both directions, over every row.
func _verify_ids(catalog: Gen2WorldCatalog) -> void:
	var seen: Dictionary = {}
	for row: Dictionary in catalog.rows():
		var id: int = int(row["id"])
		if seen.has(id):
			_r.check(false, "id %d names two sites." % id)
			return
		seen[id] = true
		if not row.has("address"):
			continue
		var recomputed: int = Gen2WorldCatalog.pack_id(
			StringName(row["kind"]), int(row["bank"]), int(row["address"])
		)
		if recomputed != id:
			_r.check(false, "id %d does not recompute from its own address." % id)
			return
	_r.note("%d ids, each naming one site." % seen.size())


## The four fields whose effect is not at the command the site is: a starter's
## picture, and a prize's two coin commands. A patch that reached the `givepoke`
## alone would show one Pokemon and hand over another.
func _verify_links(catalog: Gen2WorldCatalog) -> void:
	for row: Dictionary in catalog.rows(Gen2WorldCatalog.KIND_STARTER):
		_r.check(
			row.has("picture_address"),
			"a starter has no linked pokepic, so its ball would show the old one."
		)
		if not row.has("picture_address"):
			return
		var linked: Dictionary = catalog.link_at(
			int(row["bank"]), int(row["picture_address"])
		)
		_r.check(
			int(linked.get("id", -1)) == int(row["id"])
				and StringName(linked.get("role", &"")) == &"picture",
			"a starter's pokepic does not link back to it."
		)
	for row: Dictionary in catalog.rows(Gen2WorldCatalog.KIND_PRIZE):
		for key: String in ["check_address", "take_address"]:
			_r.check(row.has(key), "a prize has no linked %s." % key)
			if not row.has(key):
				return
			var linked: Dictionary = catalog.link_at(int(row["bank"]), int(row[key]))
			_r.check(
				int(linked.get("id", -1)) == int(row["id"])
					and StringName(linked.get("role", &"")) == &"price",
				"a prize's %s does not link back to it." % key
			)
	var shops: Array = catalog.rows(Gen2WorldCatalog.KIND_SHOP)
	var stocked: int = 0
	for row: Dictionary in shops:
		if not (row.get("items", []) as Array).is_empty():
			stocked += 1
	_r.check(stocked > 0, "no shop site carries an inventory.")
	_r.note("%d of %d shop sites carry their own shelf." % [stocked, shops.size()])


## The cartridge's own placement finishes, and one that hides Surf behind Surf
## does not. The second is the whole reason the validator exists.
func _verify_progression(catalog: Gen2WorldCatalog) -> void:
	var data: GameData = GameData.open(_r.game_id)
	if data == null:
		return
	var vanilla: Dictionary = Gen2WorldProgression.validate(data, {})
	_r.check(
		bool(vanilla["ok"]),
		"the cartridge's own placement does not validate: %s." % str(vanilla.get("missing", {}))
	)
	_r.note("progression: %d checks reached, %d of them critical." % [
		int(vanilla["reached"]), int(vanilla["critical"]),
	])

	var surf_item: int = 0
	for item: int in catalog.field_hm_items():
		if catalog.move_for_hm_item(item) == Gen2WorldFieldMove.MOVE_SURF:
			surf_item = item
	var walk: Gen2WorldReachability = Gen2WorldReachability.build(data)
	var dry: Dictionary = walk.reachable(Gen2WorldProgression.START_MAP, {})
	var behind: int = -1
	for row: Dictionary in catalog.rows(Gen2WorldCatalog.KIND_ITEM):
		if not row.has("map"):
			continue
		var key: int = Gen2WorldReachability.map_key(
			int((row["map"] as Vector2i).x), int((row["map"] as Vector2i).y)
		)
		if not dry.has(key):
			behind = int(row["id"])
			break
	if behind < 0 or surf_item <= 0:
		_r.check(false, "no site behind Surf to build a self-locking placement from.")
		return
	## Surf on a shore only Surf reaches, and nowhere else.
	var patches: Dictionary = {behind: {"item": surf_item}}
	for row: Dictionary in catalog.rows(Gen2WorldCatalog.KIND_ITEM):
		if int(row["item"]) == surf_item and int(row["id"]) != behind:
			patches[int(row["id"])] = {"item": RomLayout.ITEM_TM01}
	var locked: Dictionary = Gen2WorldProgression.validate(data, patches)
	_r.check(not bool(locked["ok"]), "a placement hiding Surf behind Surf validated.")
	_r.check(
		not (locked.get("missing", {}) as Dictionary).is_empty(),
		"a rejected placement named no unreachable requirement."
	)
	## And it is the same answer twice, which is what lets a generator retry.
	_r.check(
		Gen2WorldProgression.validate(data, patches) == locked,
		"two validations of one placement disagreed."
	)
	_r.check(
		bool(Gen2WorldProgression.validate(data, {})["ok"]),
		"a rejected placement was left installed."
	)


## The whole point of the catalog: a patch has to reach the row a runtime reader
## gets. Done on an overlay of this check's own, so the shared one is untouched.
func _verify_patching(catalog: Gen2WorldCatalog) -> void:
	var overlay := Gen2ContentOverlay.new()
	var data: GameData = GameData.open(_r.game_id)
	if data == null:
		return
	data.set_content_overlay(overlay)
	var patched: Gen2WorldCatalog = data.catalog()
	var moved: int = 0
	for kind: StringName in [
		Gen2WorldCatalog.KIND_STARTER, Gen2WorldCatalog.KIND_GIFT,
		Gen2WorldCatalog.KIND_STATIC, Gen2WorldCatalog.KIND_PRIZE,
	]:
		for row: Dictionary in patched.rows(kind):
			overlay.patch(Gen2ContentOverlay.KIND_CHECK, &"check", int(row["id"]), {
				"species": CELEBI, "level": 7,
			})
			var after: Dictionary = patched.check(int(row["id"]))
			if int(after["species"]) != CELEBI or int(after["level"]) != 7:
				_r.check(false, "row %d did not read its patch back." % int(row["id"]))
				return
			moved += 1
	for row: Dictionary in patched.rows(Gen2WorldCatalog.KIND_ITEM):
		overlay.patch(Gen2ContentOverlay.KIND_CHECK, &"check", int(row["id"]), {
			"item": 1, "quantity": 3,
		})
		var after: Dictionary = patched.check(int(row["id"]))
		if int(after["item"]) != 1 or int(after["quantity"]) != 3:
			_r.check(false, "item row %d did not read its patch back." % int(row["id"]))
			return
		moved += 1
	_r.note("%d rows patched and read back." % moved)
	_r.check(
		Gen2ContentOverlay.shared().is_empty(),
		"the check leaked into the shared overlay."
	)
