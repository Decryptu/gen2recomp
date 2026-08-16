class_name Gen2WorldProgression
extends RefCounted

## Whether a proposed placement can still be finished, answered by the host.
##
## A mod shuffling badges and key items can write a seed nobody can beat, and it
## cannot tell on its own: the gates are the cartridge's. This walks the
## [Gen2WorldCatalog] as a dependency graph and answers deterministically, with
## the FIRST requirement that was never satisfiable so generation can retry
## against a reason rather than a guess.
##
## What it proves is one thing, exactly: that nothing critical is locked behind
## itself. Start with nothing in hand, take every check whose requirements are
## met, take what those checks hand over, and repeat until no new check opens.
## A placement passes when every critical check is inside that closure.
##
## What it does NOT model, and why:
##
## - Story EVENTS. `checkevent` guards are set by story scripts a placement does
##   not move, so an event requirement is treated as satisfiable. A shuffle that
##   only moves rewards cannot make one unreachable.
##
## - A site the catalog could not attribute to a MAP. It is taken as standing
##   wherever the player already is, which can pass a seed a walk would not; the
##   opposite would reject good ones.
##
## The gates it DOES model are the ones a placement can break: an item or badge a
## check asks for, the badge an HM needs before its move works at all, and
## whether the map a check stands on can be WALKED to with the field moves in
## hand, which [Gen2WorldReachability] answers off the cartridge's own collision.

## What a validation answers with when it fails: which check could not be
## reached, and the one requirement of it that never became satisfiable.
const REASON_UNREACHABLE: StringName = &"unreachable_check"
const REASON_NO_CATALOG: StringName = &"missing_catalog"

## How many rounds the closure may take before it is called stuck. One round per
## check is the theoretical worst case, so this is a runaway guard rather than a
## limit anything real reaches.
const MAX_ROUNDS: int = 64

## `Gen2WorldSpawn`'s own new-game map, which is where every walk starts.
const START_MAP := Vector2i(Gen2WorldSpawn.NEW_BARK_GROUP, Gen2WorldSpawn.PLAYERS_HOUSE_2F)

## Cache directory to the scratch cache, overlay, catalog and map graph a
## validation runs against. See [method validate].
static var _scratch: Dictionary = {}


## Drops the scratch caches. For a test that rewrote a cache under the same path.
static func reset() -> void:
	_scratch.clear()


## Validates [param patches], a map of catalog check id to the fields a mod
## proposes for it, WITHOUT installing any of them: the rows are resolved through
## an overlay of this call's own, so the shared one and the live game are
## untouched and two validations of two seeds cannot see each other.
##
## Answers
## [code]{ok, reached, critical, missing: {check, requirement, kind}}[/code].
## Deterministic: every walk is over ids in sorted order, so one placement always
## answers the same way.
static func validate(data: GameData, patches: Dictionary = {}) -> Dictionary:
	if data == null:
		return {"ok": false, "reason": REASON_NO_CATALOG, "reached": 0, "critical": 0}
	## The scratch cache, its catalog and its map graph are built once per
	## cartridge and reused: a generator validates one seed after another, and
	## decoding the whole script corpus each time is seconds an hour of retries
	## cannot afford. Only the OVERLAY changes between calls, and rows are
	## resolved through it at read time rather than baked in.
	if not _scratch.has(data.directory):
		var opened: GameData = GameData.open_directory(data.directory)
		if opened == null:
			return {"ok": false, "reason": REASON_NO_CATALOG, "reached": 0, "critical": 0}
		var fresh := Gen2ContentOverlay.new()
		opened.set_content_overlay(fresh)
		_scratch[data.directory] = {
			"data": opened, "overlay": fresh,
			"catalog": opened.catalog(), "walk": Gen2WorldReachability.build(opened),
		}
	var held: Dictionary = _scratch[data.directory]
	var overlay: Gen2ContentOverlay = held["overlay"]
	overlay.clear_owner(&"progression")
	var ids: Array = patches.keys()
	ids.sort()
	for id: Variant in ids:
		overlay.patch(
			Gen2ContentOverlay.KIND_CHECK, &"progression", int(id), patches[id]
		)
	return _walk(held["catalog"], held["walk"])


## The closure itself. Split from [method validate] so a caller holding a catalog
## it built for another reason can ask directly.
static func _walk(catalog: Gen2WorldCatalog, walk: Gen2WorldReachability) -> Dictionary:
	## Resolved once: the overlay does not move during a walk, and re-resolving
	## every row every round is what made this seconds rather than milliseconds.
	var rows: Array = catalog.rows()
	rows.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return int(first["id"]) < int(second["id"])
	)
	var critical: Array = []
	for row: Dictionary in rows:
		if catalog.is_progression(row):
			critical.append(row)

	var items: Dictionary = {}
	var badges: Dictionary = {}
	var reached: Dictionary = {}
	var maps: Dictionary = {}
	## The flood only has to be taken again when the move set actually grows.
	var last_moves: Dictionary = {}
	for _round: int in MAX_ROUNDS:
		var opened: bool = false
		var usable: Dictionary = _usable_moves(catalog, items, badges)
		if usable != last_moves or maps.is_empty():
			last_moves = usable
			maps = walk.reachable(START_MAP, usable)
		for row: Dictionary in rows:
			var id: int = int(row["id"])
			if reached.has(id):
				continue
			if not _blocker(catalog, row, items, badges, maps).is_empty():
				continue
			reached[id] = true
			opened = true
			## What the check hands over is in hand from now on.
			if row.has("item") and int(row["item"]) > 0:
				items[int(row["item"])] = true
			if StringName(row["kind"]) == Gen2WorldCatalog.KIND_BADGE:
				badges[int(row["badge"])] = true
		if not opened:
			break

	for row: Dictionary in critical:
		if reached.has(int(row["id"])):
			continue
		var blocker: Dictionary = _blocker(catalog, row, items, badges, maps)
		return {
			"ok": false,
			"reason": REASON_UNREACHABLE,
			"reached": reached.size(),
			"critical": critical.size(),
			"missing": {
				"check": int(row["id"]),
				"kind": StringName(row["kind"]),
				"requirement": blocker,
			},
		}
	return {
		"ok": true, "reached": reached.size(), "critical": critical.size(),
		"missing": {},
	}


## The field moves the player can actually USE: an HM in the bag whose badge is
## also in hand. A move with no badge gate needs the HM alone.
static func _usable_moves(
	catalog: Gen2WorldCatalog, items: Dictionary, badges: Dictionary
) -> Dictionary:
	var out: Dictionary = {}
	for item: Variant in items:
		var move: int = catalog.move_for_hm_item(int(item))
		if move <= 0:
			continue
		var badge: int = Gen2WorldFieldMove.badge_for_move(move)
		if badge < 0 or badges.has(badge):
			out[move] = true
	return out


## The first thing standing between the player and [param row], or empty when
## nothing is. Walking there is asked first, since it is the gate a placement
## breaks most often.
static func _blocker(
	catalog: Gen2WorldCatalog, row: Dictionary, items: Dictionary, badges: Dictionary,
	maps: Dictionary
) -> Dictionary:
	if row.has("map"):
		var key: int = Gen2WorldReachability.map_key(
			int((row["map"] as Vector2i).x), int((row["map"] as Vector2i).y)
		)
		if not maps.has(key):
			return {"map": row["map"]}
	return _satisfied(catalog, row, items, badges)


## The first requirement of [param row] that is not met, or empty when all are.
##
## An `event` requirement is not one of them: see the class comment. An `item`
## requirement that is an HM brings its badge with it, which is the gate that
## makes a placement circular rather than merely late.
static func _satisfied(
	catalog: Gen2WorldCatalog, row: Dictionary, items: Dictionary, badges: Dictionary
) -> Dictionary:
	for requirement: Variant in row.get("requires", []):
		if not requirement is Dictionary:
			continue
		var entry: Dictionary = requirement as Dictionary
		if entry.has("item"):
			var item: int = int(entry["item"])
			if not items.has(item) and _is_placed(catalog, item):
				return {"item": item}
			var badge: int = _badge_for_item(catalog, item)
			if badge >= 0 and not badges.has(badge):
				return {"badge": badge, "for_item": item}
		elif entry.has("engine_flag"):
			## A gym script opens with `checkflag` of the badge it is about to
			## grant, which is its own "have I been done already" test rather
			## than a gate. Reading it as one makes every badge require itself.
			if int(entry["engine_flag"]) == int(row.get("engine_flag", -1)):
				continue
			var flag_badge: int = catalog.badge_for_engine_flag(int(entry["engine_flag"]))
			if flag_badge >= 0 and not badges.has(flag_badge):
				return {"badge": flag_badge}
	return {}


## Whether [param item] is something a check hands over at all. An item no check
## carries is bought, found in a mart or given by a story script a placement did
## not move, so asking for it gates nothing.
static func _is_placed(catalog: Gen2WorldCatalog, item: int) -> bool:
	return catalog.item_sources().has(item)


## The badge an HM's own move needs, or -1 for anything else.
static func _badge_for_item(catalog: Gen2WorldCatalog, item: int) -> int:
	return catalog.badge_for_hm_item(item)
