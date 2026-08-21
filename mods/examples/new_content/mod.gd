extends RefCounted

## Everything a mod can register that is not a renderer, in one file.
##
## Nothing here is a scene node, a cartridge read or an engine internal: the mod
## is handed the host, registers, and returns. What it registers is then read
## back by the ordinary engine, which never learns that a mod defined any of it.
##
## Copy this directory into `user://mods/` to run it.

## Mod numbers start at Gen2ContentOverlay.FIRST_MOD_NUMBER, which is 256: every
## cartridge content number fits in a byte, so anything above one is
## unambiguously not the cartridge's, and these numbers mean the same thing on
## Gold, Silver and Crystal.
## Numbering is per kind, so the first species and the first move share one.
const VOLTLING: int = Gen2ContentOverlay.FIRST_MOD_NUMBER
## What VOLTLING becomes, a cartridge species so the evolution is visibly the
## engine's own rather than one more defined row.
const RAICHU: int = 26
const STATIC_FIELD: int = Gen2ContentOverlay.FIRST_MOD_NUMBER
## An effect byte no cartridge move carries.
const RECOIL_AND_PARALYSE: int = 0xF0

const ELECTRIC: int = RomLayout.TYPE_ELECTRIC
## A type of the mod's own. Types are the one kind numbered from zero, the
## cartridge chart being zero-based, so a DEFINED one still sits past 256.
const PLASMA: int = Gen2ContentOverlay.FIRST_MOD_NUMBER
## An item of the mod's own, and the pack pocket it lands in. A mod pocket is at
## or above Gen2ModHost.FIRST_MOD_POCKET; 1 to 4 are the cartridge's.
const CELL_BATTERY: int = Gen2ContentOverlay.FIRST_MOD_NUMBER
const CURIOS_POCKET: int = Gen2ModHost.FIRST_MOD_POCKET
## Cartridge numbers, for the two rows this mod changes rather than adds.
const PIKACHU: int = 25
const THUNDERBOLT: int = 85

func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	_add_a_type(host, manifest.id)
	_add_a_species(host, manifest.id)
	_add_a_move(host, manifest.id)
	_add_an_item_and_its_shelf(host, manifest.id)
	_add_a_control(host, manifest.id)
	_populate_the_map(host, manifest.id)
	_walk_something_behind_the_player(host, manifest.id)
	_add_a_stats_page(host, manifest.id)
	_rebalance(host, manifest.id)
	_watch(host, manifest.id)


## A type, and the two chart exceptions that make it mean something
## (`api_version` 4).
##
## The chart is a sparse table of exceptions, so a pair nobody names is already
## neutral: there is no row to define and matchups are patched even for a type
## this mod invented. `physical` is which stat pair the type uses, which
## Generation II decides by type number rather than per move, so a number past
## the cartridge chart has to say.
func _add_a_type(host: Gen2ModHost, id: StringName) -> void:
	host.register_content(Gen2ContentOverlay.KIND_TYPE, id, PLASMA, {
		"name": "PLASMA",
		"physical": false,
	})
	# Multipliers are in tenths, the way the damage formula divides.
	host.patch_type_matchup(id, PLASMA, RomLayout.TYPE_STEEL, {
		"multiplier": RomLayout.MATCHUP_SUPER_EFFECTIVE,
	})
	host.patch_type_matchup(id, RomLayout.TYPE_GROUND, PLASMA, {
		"multiplier": RomLayout.MATCHUP_NOT_VERY_EFFECTIVE,
	})


## A whole Pokémon. Everything a species carries is a field on one row, so the
## learnset, the evolution and the TM flags are part of the definition rather
## than four separate registrations; anything left out gets the kind's default,
## which is why this does not have to name a hatch cycle or a gender ratio.
func _add_a_species(host: Gen2ModHost, id: StringName) -> void:
	host.register_content(Gen2ContentOverlay.KIND_SPECIES, id, VOLTLING, {
		"name": "VOLTLING",
		"stats": {
			"hp": 70, "attack": 65, "defense": 60,
			"speed": 115, "sp_attack": 110, "sp_defense": 70,
		},
		"types": [ELECTRIC, PLASMA],
		"catch_rate": 45,
		"base_exp": 180,
		"growth_rate": Gen2Experience.GROWTH_MEDIUM_FAST,
		"learnset": [
			{"level": 1, "move": 33},   # TACKLE
			{"level": 8, "move": 84},   # THUNDERSHOCK
			{"level": 20, "move": STATIC_FIELD},
			{"level": 36, "move": THUNDERBOLT},
		],
		# The item below names EVOLVE_TRADE, which is the method rather than the
		# target: a row with no held requirement ($FF) is what it answers.
		"evolutions": [{
			"method": RomLayout.EVOLVE_TRADE,
			"parameter": Gen2Evolution.TRADE_NO_ITEM,
			"condition": 0, "target": RAICHU,
		}],
		# The pic atlases hold the cartridge's own slots and nothing else, so a
		# defined species supplies decoded indices instead: two bits a pixel,
		# row-major, exactly tiles * tiles * 64 of them (`api_version` 4).
		"pics": {
			"front": {"tiles": 7, "indices": _plaid(7)},
			"back": {"tiles": 6, "indices": _plaid(6)},
		},
		# Eight tiles, the two 2x2 frames of the party menu's own strip. A
		# cartridge icon number, 1 to 38, borrows a picture that already exists.
		"icon": {"indices": _plaid(0, 8)},
		"palette": {"normal": [0x3F1F, 0x1084], "shiny": [0x7FE0, 0x1084]},
	})


## Two bits a pixel is four shades, and a readable placeholder is worth more here
## than a picture: the point of the example is the SHAPE the host takes.
func _plaid(tiles: int, count: int = 0) -> PackedByteArray:
	var pixels: int = count * 64 if count > 0 else tiles * tiles * 64
	var out: PackedByteArray = PackedByteArray()
	out.resize(pixels)
	for at: int in pixels:
		out[at] = ((at >> 3) + at) & 3
	return out


## A move, and the effect that decides what it does.
##
## The effect is registered before the move, because a move's effect byte is only
## a number until something answers for it, and a list naming a step that does
## not exist is refused at registration rather than failing mid-turn.
func _add_a_move(host: Gen2ModHost, id: StringName) -> void:
	# The cartridge's own lists are in Gen2MoveEffect and the steps in
	# Gen2EffectCommands. This is NORMAL_HIT with the recoil of Take Down and the
	# paralysis chance of Body Slam, which no cartridge effect combines.
	host.register_move_effect(id, RECOIL_AND_PARALYSE, [
		Gen2EffectCommands.USED_MOVE_TEXT,
		Gen2EffectCommands.DO_TURN,
		Gen2EffectCommands.DAMAGE_CALC,
		Gen2EffectCommands.CHECK_IMMUNE,
		Gen2EffectCommands.CHECK_HIT,
		Gen2EffectCommands.EFFECT_CHANCE,
		Gen2EffectCommands.APPLY_DAMAGE,
		Gen2EffectCommands.RECOIL,
		Gen2EffectCommands.CHECK_FAINT,
		Gen2EffectCommands.PARALYZE_TARGET,
		Gen2EffectCommands.END_MOVE,
	])
	host.register_content(Gen2ContentOverlay.KIND_MOVE, id, STATIC_FIELD, {
		"name": "STATICFIELD",
		"effect": RECOIL_AND_PARALYSE,
		"power": 95,
		"type": ELECTRIC,
		"accuracy": 230,
		"pp": 10,
		"effect_chance": 76,
	})


## An item, the pocket it lands in, and the mart shelf it is sold from
## (`api_version` 3).
##
## The shelf row is a MENU entry rather than content: the item exists whatever a
## mart sells, and `available` decides which marts carry it. A filter is handed
## the resolved mart, `mart_id` included, and a row is dropped when it answers
## false or when the cartridge shelf already sells that item.
func _add_an_item_and_its_shelf(host: Gen2ModHost, id: StringName) -> void:
	host.register_content(Gen2ContentOverlay.KIND_ITEM, id, CELL_BATTERY, {
		"name": "CELLBATTERY",
		"price": 800,
		"pocket": CURIOS_POCKET,
		# USE opens the party list, and the evolution it causes is a fact the
		# host acts on rather than a callback (`api_version` 9).
		"field_menu": Gen2WorldPack.ITEMMENU_PARTY,
		"evolution": {"method": RomLayout.EVOLVE_TRADE},
	})
	host.register_menu_entry(Gen2ModHost.MENU_PACK_POCKET, id, {
		"label": "CURIOS",
		"pocket": CURIOS_POCKET,
	})
	host.register_menu_entry(Gen2ModHost.MENU_MART, id, {
		"label": "CELLBATTERY",
		"item": CELL_BATTERY,
		# Half what the pack values it at, so the shelf price is visibly the
		# shelf's rather than the item's.
		"price": 400,
		"available": func(mart: Dictionary) -> bool:
			return int(mart.get("variant", 0)) == 0,
	})


## A control of the mod's own, as the two halves of one named axis
## (`api_version` 3).
##
## A mod cannot see the cartridge's eight and the screen claims every one of them
## first, so a raw keycode read out of `handle_world_input` would produce a
## control that cannot be rebound and does not exist on a touchscreen. A default
## already bound to one of the eight is dropped and reported rather than
## silently never firing, which is why neither of these is `A` or `D`.
func _add_a_control(host: Gen2ModHost, id: StringName) -> void:
	host.register_action(id, {
		"key": "survey_left", "label": "Survey left",
		"default": [{"kind": "key", "code": KEY_Q}],
	})
	host.register_action(id, {
		"key": "survey_right", "label": "Survey right",
		"default": [{"kind": "key", "code": KEY_E}],
	})


## Wild Pokemon standing on the map instead of a roll on every step
## (`api_version` 2), and the run's own rules deciding how they behave
## (`api_version` 5).
##
## The provider owns its population and nothing else: which cells a wild may
## stand on, which table each is checked against and what a battle costs all stay
## the host's. It is a RefCounted and never a Node, and its four methods are
## refused by name at registration.
func _populate_the_map(host: Gen2ModHost, id: StringName) -> void:
	host.register_visible_encounters(id, Population.new())


## One sprite in the world, petted and picking things up (`api_version` 7).
##
## An actor is PRESENTATION: it occupies no cell, blocks nothing and is in no
## snapshot. The three methods below it are required; `interact`, `take_requests`
## and a `sprites()` entry's `emote` are the optional three that make it a pet.
func _walk_something_behind_the_player(host: Gen2ModHost, id: StringName) -> void:
	host.register_world_actor(id, Pet.new())


## A fourth page on a Pokémon's stats screen (`api_version` 8).
##
## The mod answers WHERE its strings go and the host writes them with the
## screen's own font, so a page needs no node, no renderer and no art of its own.
## The lower half is rows 8 to 17 and a placement outside it is dropped, which is
## what keeps a page off the name, the level and the front pic. The snapshot is
## the same one the cartridge pages are drawn from, plus the two halves of a
## Pokémon none of them prints: the packed DV word and the stat experience.
func _add_a_stats_page(host: Gen2ModHost, id: StringName) -> void:
	host.register_stats_page(id, {"build": _build_stats_page})


func _build_stats_page(page: Dictionary) -> Array:
	var dvs: int = int(page.get("dvs", 0))
	var trained: Dictionary = page.get("stat_exp", {})
	var out: Array = [
		## The pink and blue pages' own divider, so the columns line up when a
		## player turns between them.
		{"divider": 10},
		{"text": "DV", "at": Vector2i(8, 8)},
		{"text": "STAT EXP", "at": Vector2i(11, 8)},
	]
	## HP's DV is derived from the low bit of the other four rather than stored,
	## and both special stats read one stat-experience counter, so five rows is
	## what the hardware has to say.
	var rows: Array = [
		["HP", Gen2Stats.hp_dv(dvs), "hp"],
		["ATTACK", Gen2Stats.attack_dv(dvs), "attack"],
		["DEFENSE", Gen2Stats.defense_dv(dvs), "defense"],
		["SPECIAL", Gen2Stats.special_dv(dvs), "special"],
		["SPEED", Gen2Stats.speed_dv(dvs), "speed"],
	]
	for index: int in rows.size():
		## `wListMovesLineSpacing`'s two rows, which every list on this screen
		## steps.
		var row: int = 9 + index * 2
		out.append({"text": String(rows[index][0]), "at": Vector2i(0, row)})
		out.append({"text": str(int(rows[index][1])).lpad(2), "at": Vector2i(8, row)})
		out.append({
			"text": str(int(trained.get(String(rows[index][2]), 0))).lpad(5),
			"at": Vector2i(14, row),
		})
	return out


## Rewriting how an event is PRESENTED, without changing what happened
## (`api_version` 4).
##
## One mutator per channel, ahead of every watcher, and the host refuses a return
## that changed the event's own kind: a mutator may dress a result and may not
## turn one result into another. This is why the pair is registered rather than
## the subscriber doing both jobs.
func _rewrite_presentation(host: Gen2ModHost, id: StringName) -> void:
	host.register_event_mutator(Gen2ModHost.CHANNEL_WORLD, id, _dress_world_event)


## `status` is the world channel's routing key and is left exactly as it came:
## the text a waiting result is showing is presentation, and which screen
## operation the result is is not.
func _dress_world_event(result: Dictionary) -> Dictionary:
	var event: Dictionary = result.get("event", {})
	if StringName(event.get("type", &"")) == &"text":
		event["text"] = String(event.get("text", "")).replace("PIKACHU", "VOLTLING")
		result["event"] = event
	return result


## A Pokemon walking one cell behind the player, which is what a follower mod is,
## and every optional half of the actor contract in one object.
class Pet:
	extends RefCounted

	## How long the heart stays up after a press, in world frames. The mod owns
	## the duration because the emote is a pose the host draws while it is asked
	## for, rather than an edge the host times.
	const HEART_FRAMES: int = 60
	const CYNDAQUIL: int = 155

	var _world: Gen2WorldAPI = null
	var _heart: int = 0
	var _outbox: Array = []

	func set_world(world: Gen2WorldAPI) -> void:
		_world = world

	func advance_frame() -> void:
		_heart = maxi(0, _heart - 1)
		_pick_up_what_it_walked_over()

	func sprites() -> Array:
		if _world == null:
			return []
		var entry: Dictionary = {
			"icon": _world.data.mon_menu_icon(CYNDAQUIL),
			"facing": _world.player_facing,
			"position_cells": Vector2(_cell()),
		}
		if _heart > 0:
			entry["emote"] = Gen2WorldActors.EMOTE_HEART
		return [entry]

	## Offered only a press no cartridge object, background event or tile branch
	## answered, so this can never shadow one. Answering true consumes it.
	func interact(cell: Vector2i, _facing: int) -> bool:
		if _world == null or cell != _cell():
			return false
		_heart = HEART_FRAMES
		## A mod may not play a sound, so it asks and the host spends it.
		_outbox.append({"kind": Gen2WorldActors.REQUEST_CRY, "species": CYNDAQUIL})
		return true

	## The one-shot outbox, drained once a world frame and emptied by the drain.
	func take_requests() -> Array:
		var out: Array = _outbox
		_outbox = []
		return out

	## And the other half a follower wants: a hidden item under the cell it is
	## standing on. The mod reads the map and names the cell; taking one is the
	## HOST's, because it writes the bag, the flag and the save.
	func _pick_up_what_it_walked_over() -> void:
		if _world == null:
			return
		for record: Dictionary in _world.hidden_items():
			if bool(record["taken"]) or (record["cell"] as Vector2i) != _cell():
				continue
			Gen2ModHost.instance().request_hidden_item(record["cell"])
			return

	## One cell behind the player, which is where a follower walks: the faced
	## cell reflected through the player, so no direction table is needed here.
	func _cell() -> Vector2i:
		return _world.player_cell - (_world.facing_cell() - _world.player_cell)


## The population itself. A separate object because a provider is a RefCounted
## the host holds by name, and because everything it is told is a SNAPSHOT: the
## context is a copy taken when the map or the player's pose changed, never a
## live handle on the world.
class Population:
	extends RefCounted

	## How many wanderers stand on a map, out of the cells the host says a wild
	## is allowed on at all.
	const POPULATION: int = 3

	var _context: Dictionary = {}
	var _entries: Array = []
	var _generation: int = -1

	func set_context(context: Dictionary) -> void:
		_context = context
		# `generation` is bumped on every map change, so this is the one test
		# that says "a new map" rather than "the player moved".
		if int(context.get("generation", -1)) == _generation:
			return
		_generation = int(context.get("generation", -1))
		_repopulate()

	func advance_frame() -> void:
		pass

	func encounters() -> Array:
		return _entries

	## This provider's rule, which every provider owes its reader: an entry the
	## player fought is gone whatever the battle did.
	func battle_finished(id: StringName, _result: Dictionary) -> void:
		for at: int in _entries.size():
			if StringName((_entries[at] as Dictionary)["id"]) == id:
				_entries.remove_at(at)
				return

	func _repopulate() -> void:
		_entries = []
		var cells: PackedVector2Array = (
			_context.get("eligible", {}).get("grass", PackedVector2Array())
		)
		var table: Array = _context.get("tables", {}).get("grass", {}).get("slots", [])
		if cells.is_empty() or table.is_empty():
			return
		# `occupied` is who is standing where this frame: NPCs, item balls and
		# every other map object. It is beside `eligible` rather than inside it,
		# because the host would delete an entry an NPC walked over; refusing a
		# taken cell on spawn is this provider's own rule.
		var taken: Dictionary = {}
		for cell: Vector2 in _context.get("occupied", PackedVector2Array()):
			taken[Vector2i(cell)] = true
		# The run's seed rather than a fresh generator, so the same save walking
		# back onto the same map meets the same population.
		var rolls := RandomNumberGenerator.new()
		rolls.seed = int(_context.get("run_seed", 0)) ^ _generation
		# `Gen2Rules` is the run's own divergence flags. A run reproducing the
		# cartridge's bugs is the one that wants the cartridge's density; read
		# it, never write it, since a rule that changed mid-run would make the
		# save it produced unreproducible.
		var count: int = POPULATION
		if Gen2Rules.active().difficulty == Gen2Rules.DIFFICULTY_HARD:
			count += 1
		for at: int in mini(count, cells.size()):
			var slot: Dictionary = table[rolls.randi_range(0, table.size() - 1)]
			var cell: Vector2i = Vector2i(cells[rolls.randi_range(0, cells.size() - 1)])
			if taken.has(cell):
				continue
			_entries.append({
				"id": StringName("voltling_%d_%d" % [_generation, at]),
				"cell": cell,
				"facing": Gen2WorldSprite.FACING_DOWN,
				"species": int(slot.get("species", 0)),
				"level": int(slot.get("min_level", 2)),
				"dvs": Gen2BattleMon.PERFECT_DVS,
				# Asked for on spawn; the host drops a repeat inside
				# Gen2WorldEncounters.PULSE_FRAMES and draws nothing over a
				# Pokemon that is not shiny.
				"pulse": true,
			})


## Changing what the cartridge shipped, rather than adding to it. A patch names
## only the fields it changes, and a Dictionary field merges, so this moves one
## stat and one number and leaves everything else on both rows alone.
func _rebalance(host: Gen2ModHost, id: StringName) -> void:
	host.patch_content(Gen2ContentOverlay.KIND_SPECIES, id, PIKACHU, {
		"stats": {"speed": 110},
	})
	host.patch_content(Gen2ContentOverlay.KIND_MOVE, id, THUNDERBOLT, {"power": 90})


## Watching the game without changing it. Both channels carry the typed
## dictionaries the engine already produces, handed over as copies where the
## screen shows them, so a subscriber sees what the player sees and writing to
## one reaches nothing.
func _watch(host: Gen2ModHost, id: StringName) -> void:
	host.subscribe(Gen2ModHost.CHANNEL_BATTLE, id, _on_battle_event)
	host.subscribe(Gen2ModHost.CHANNEL_WORLD, id, _on_world_event)
	_rewrite_presentation(host, id)


func _on_battle_event(event: Dictionary) -> void:
	if StringName(event.get("type", &"")) == Gen2Battle.FAINTED:
		print("[new_content] side %d fainted" % int(event.get("side", -1)))


func _on_world_event(event: Dictionary) -> void:
	if StringName(event.get("status", &"")) == &"waiting":
		print("[new_content] the world is waiting on %s" % event.get("event", {}).get("type", ""))
