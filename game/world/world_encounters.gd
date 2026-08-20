class_name Gen2WorldEncounters
extends RefCounted

## Wild Pokemon a mod puts on the map instead of a step roll, driven and
## validated by the host. A mod registers a PROVIDER through
## [method Gen2ModHost.register_visible_encounters]; the screen gives it a
## snapshot of where a wild may stand and which table each method resolves to,
## spends one frame of it per hardware frame, and takes back a bounded list of
## entries.
##
## The division is the point. The PROVIDER owns the population: how many there
## are, where each one goes, how it moves and what it does after a battle. The
## HOST owns every rule a mod must not re-derive: which cells are eligible, which
## table is active, whether an entry is inside both, what a shiny is, and what
## meeting one starts. Nothing here reads a node.
##
## [Gen2WorldActors] is the layer next to this one and the two are different
## contracts: an actor is presentation and takes part in nothing, a visible
## encounter is met and fought.

## Checked at registration, where the mod's name is still in hand.
const PROVIDER_METHODS: Array[String] = [
	"set_context", "advance_frame", "encounters", "battle_finished",
]

## How many entries one frame may carry, over every provider. A population is
## the mod's to cap; this is the host refusing to draw a thousand of them.
const MAX_ENTRIES: int = 32

## `ANIM_SEND_OUT_MON` with `wBattleAnimParam` at 1, which is the whole of the
## cartridge's shiny sparkle: `BattleCheckEnemyShininess` plays the same
## animation a second time with the param set (engine/battle/core.asm).
const SHINY_ANIM: int = 0x101
const SHINY_ANIM_PARAM: int = 1

## A pulse for an id that pulsed fewer frames ago than this is dropped, so a
## provider may ask on every frame and get the cadence it asked for once.
const PULSE_FRAMES: int = 600

## The four `Gen2WorldSprite` facings.
const MAX_FACING: int = Gen2WorldSprite.FACING_RIGHT

var _providers: Array = []
var _world: Gen2WorldAPI = null
var _anim_data: Gen2BattleAnimData = null
## Bumped on every map change, and carried in the context so a provider can tell
## a stale snapshot from a fresh one.
var _generation: int = 0
var _context: Dictionary = {}
## Validated entries this frame, each with the provider that produced it.
var _entries: Array = []
## Entry id to the provider that owns it, so a battle result reaches the right
## one after the entry itself is gone.
var _owners: Dictionary = {}
var _frame: int = 0
## Entry id to the frame its last pulse started on.
var _pulsed: Dictionary = {}
var _pulse: Gen2BattleAnimPlayer = null
var _pulse_id: StringName = &""
## What the running pulse's commands asked for this frame: the screen owns the
## audio device, as the battle screen does.
var _frame_commands: Array = []


## [param providers] is [method Gen2ModHost.visible_encounter_providers], in
## registration order.
func set_providers(providers: Array) -> void:
	_providers = providers
	_reset()


func active() -> bool:
	return not _providers.is_empty()


## The map changed, or the view was created. Every entry, every sprite and any
## running pulse is discarded before the new map is drawn, and each provider is
## handed the new context.
func set_world(world: Gen2WorldAPI, anim_data: Gen2BattleAnimData = null) -> void:
	if anim_data != null:
		_anim_data = anim_data
	## Called again whenever a view is rebuilt, which a keybind swapping
	## renderers does mid-walk. Only a different MAP discards a population.
	var same: bool = world == _world and not _context.is_empty() \
		and world != null and world.map_id() == _context.get("map", Vector2i(-1, -1))
	_world = world
	if same:
		return
	_generation += 1
	_reset()


## One hardware frame: every provider steps, and what they answer becomes this
## frame's population. Answers whether anything a view draws changed.
func advance_frame() -> bool:
	if _providers.is_empty():
		return false
	_frame += 1
	_frame_commands = []
	_push_player_pose()
	for provider: Object in _providers:
		provider.call("advance_frame")
	var before: Array = _entries
	_collect()
	var moved: bool = _changed(before, _entries)
	return _advance_pulse() or moved


## The validated population, each entry `{id, cell, facing, species, level, dvs,
## shiny}`. `shiny` is the host's own answer from the DVs; a provider that sends
## one is refused.
func entries() -> Array:
	return _entries


## The population in the shape [Gen2WorldActors] resolves, so a visible encounter
## is drawn by the same pass a mod's actors are and reaches both views.
func actor_entries() -> Array:
	var out: Array = []
	if _world == null or _world.data == null:
		return out
	for entry: Dictionary in _entries:
		var icon: int = _world.data.mon_menu_icon(int(entry["species"]))
		if icon <= 0:
			continue
		out.append({
			"icon": icon,
			"facing": int(entry["facing"]),
			"position_cells": Vector2(entry["cell"]),
			# `GetMonNormalOrShinyPalettePointer`: the species' own four colours,
			# which is what makes a shiny one visible before the battle starts.
			"colors": _world.data.palette(int(entry["species"]), bool(entry["shiny"])),
		})
	return out


## `wShadowOAM` as the running pulse left it, empty when none is running. See
## [method Gen2BattleAnimPlayer.sprites].
func pulse_sprites() -> Array:
	return _pulse.sprites() if _pulse != null else []


## The tile window those sprites index. See [method Gen2BattleAnimPlayer.tiles].
func pulse_tiles() -> Array:
	return _pulse.tiles() if _pulse != null else []


## Where the pulse is anchored, in map pixels, or null when none is running. The
## animation is written in screen coordinates around a battler; over the world it
## follows the sprite it belongs to instead.
func pulse_anchor() -> Variant:
	if _pulse == null:
		return null
	for entry: Dictionary in _entries:
		if StringName(entry["id"]) == _pulse_id:
			return Vector2(entry["cell"]) * float(Gen2WorldAPI.CELL_PIXELS)
	return null


## The cartridge's own packed pair for the pulsing Pokemon, which is what battle
## object palette slot 0 is filled with on the field. Empty when no pulse runs.
func pulse_battler_pair() -> Array:
	if _pulse == null or _world == null or _world.data == null:
		return []
	for entry: Dictionary in _entries:
		if StringName(entry["id"]) != _pulse_id:
			continue
		var species: Dictionary = _world.data.species(int(entry["species"]))
		if species.is_empty():
			return []
		return (species["palette"] as Dictionary)["shiny" if bool(entry["shiny"]) else "normal"]
	return []


## `anim_sound` and `anim_cry` from the pulse's last frame, for the caller that
## owns the audio device.
func frame_commands() -> Array:
	return _frame_commands


## The battle to start when the player meets [param cell], or an empty dictionary
## when nothing stands there. The species, level and DVs are the entry's own and
## are not rolled again.
func battle_request_at(cell: Vector2i) -> Dictionary:
	for entry: Dictionary in _entries:
		if entry["cell"] != cell:
			continue
		return {
			"kind": &"battle_requested",
			"visible_encounter": StringName(entry["id"]),
			"values": {
				"kind": &"wild",
				"pokemon": int(entry["species"]),
				"level": int(entry["level"]),
				"dvs": int(entry["dvs"]),
			},
		}
	return {}


## Tells whichever provider owns [param id] how the battle ended. What it does
## with the entry, remove it or keep it, is the provider's one documented rule
## and not the host's.
func battle_finished(id: StringName, result: Variant) -> void:
	var provider: Object = _owners.get(id, null)
	if provider == null:
		return
	provider.call("battle_finished", id, result)


func _reset() -> void:
	_entries = []
	_owners = {}
	_pulsed = {}
	_pulse = null
	_pulse_id = &""
	_frame_commands = []
	_context = _build_context()
	for provider: Object in _providers:
		provider.call("set_context", _context.duplicate(true))


## The snapshot a provider plans against: where a wild may stand, what each
## method resolves to right now, and enough of the run to be deterministic. Every
## question in it is answered by [Gen2WorldAPI], never by the mod.
func _build_context() -> Dictionary:
	if _world == null:
		return {}
	return {
		"map": _world.map_id(),
		"eligible": _world.visible_encounter_cells(),
		"occupied": _occupied_cells(),
		"tables": _world.active_encounter_tables(),
		"player": {"cell": _world.player_cell, "facing": _world.player_facing},
		"run_seed": _world.random_seed,
		"generation": _generation,
	}


## The walk cells the map's own objects hold this frame, which is live state and
## deliberately NOT folded into `eligible`: which cells a wild MAY stand on is
## `CanEncounterWildMon`'s rule and does not change while the map is up, and
## [method _validate] drops an entry standing outside `eligible`, so folding the
## two together would delete a wild an NPC walks over.
##
## An object mid-step is DRAWN between two cells, so both are held: its committed
## `cell` and the cell its drawing laps into, which is what `step_offset_cells()`
## measures. A big object holds all four of the cells `occupies` answers for.
## The player is not in it; `player` is where that cell is.
func _occupied_cells() -> PackedVector2Array:
	var out := PackedVector2Array()
	if _world == null:
		return out
	var seen: Dictionary = {}
	for object: Gen2WorldObject in _world.visible_objects():
		var drawn: Vector2 = Vector2(object.cell) + object.step_offset_cells()
		for corner: Vector2i in [
			object.cell, Vector2i(drawn.floor()), Vector2i(drawn.ceil()),
		]:
			var span: int = Gen2WorldObject.BIG_OBJECT_SIZE if object.is_big_object() else 1
			for x: int in span:
				for y: int in span:
					var cell := Vector2(corner + Vector2i(x, y))
					if seen.has(cell):
						continue
					seen[cell] = true
					out.append(cell)
	return out


## The pose moves and the map does not, so the sweep and the tables are not taken
## again: a provider is handed the same context with `player` and `occupied`
## refreshed, and only when one of the two has actually changed. An object walks
## while the player stands still, so the occupancy is on this pass rather than on
## the map change.
func _push_player_pose() -> void:
	if _world == null or _context.is_empty():
		return
	var pose: Dictionary = {"cell": _world.player_cell, "facing": _world.player_facing}
	var occupied: PackedVector2Array = _occupied_cells()
	if _context.get("player", {}) == pose \
	and _context.get("occupied", PackedVector2Array()) == occupied:
		return
	_context["player"] = pose
	_context["occupied"] = occupied
	for provider: Object in _providers:
		provider.call("set_context", _context.duplicate(true))


func _collect() -> void:
	_entries = []
	if _world == null or _world.data == null:
		return
	var seen: Dictionary = {}
	for provider: Object in _providers:
		var answer: Variant = provider.call("encounters")
		if not answer is Array:
			continue
		for raw: Variant in answer as Array:
			if _entries.size() >= MAX_ENTRIES:
				return
			var entry: Dictionary = _validate(raw)
			if entry.is_empty() or seen.has(entry["id"]):
				continue
			seen[entry["id"]] = true
			_owners[entry["id"]] = provider
			_entries.append(entry)
			if bool(entry["pulse"]):
				_start_pulse(entry)


## One entry against the context it was given. An id, a cell inside the eligible
## set, and a species and level the active table for that cell's own method
## offers: anything else is dropped rather than drawn, because a population the
## host cannot vouch for is a wild encounter a mod invented.
func _validate(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var row: Dictionary = raw as Dictionary
	if row.has("shiny"):
		return {}
	var id: StringName = StringName(row.get("id", &""))
	if String(id).is_empty():
		return {}
	var cell := Vector2i(row.get("cell", Vector2i(-1, -1)))
	var method: StringName = _eligible_method(cell)
	if method.is_empty():
		return {}
	var species: int = int(row.get("species", 0))
	var level: int = int(row.get("level", 0))
	if not _table_offers(method, species, level):
		return {}
	var dvs: int = int(row.get("dvs", 0))
	if dvs < 0 or dvs > 0xFFFF:
		return {}
	return {
		"id": id,
		"cell": cell,
		"facing": clampi(int(row.get("facing", Gen2WorldSprite.FACING_DOWN)), 0, MAX_FACING),
		"species": species,
		"level": level,
		"dvs": dvs,
		"shiny": Gen2Stats.is_shiny(dvs),
		"pulse": bool(row.get("pulse", false)),
	}


## Which method's eligible list [param cell] is in, empty when neither.
func _eligible_method(cell: Vector2i) -> StringName:
	var eligible: Dictionary = _context.get("eligible", {})
	for method: Variant in eligible:
		if (eligible[method] as PackedVector2Array).has(Vector2(cell)):
			return StringName(method)
	return &""


func _table_offers(method: StringName, species: int, level: int) -> bool:
	var table: Variant = (_context.get("tables", {}) as Dictionary).get(method, null)
	if not table is Dictionary:
		return false
	for slot: Variant in (table as Dictionary).get("slots", []):
		if not slot is Dictionary:
			continue
		if int((slot as Dictionary)["species"]) != species:
			continue
		if level >= int((slot as Dictionary)["min_level"]) \
			and level <= int((slot as Dictionary)["max_level"]):
			return true
	return false


## The cartridge's own sparkle over the map. Only a shiny gets one: the request
## is a presentation ask and shininess is the host's answer, so a pulse on an
## ordinary Pokemon is dropped rather than drawn as something the cartridge has
## no animation for.
func _start_pulse(entry: Dictionary) -> void:
	if not bool(entry["shiny"]) or _anim_data == null:
		return
	var id: StringName = StringName(entry["id"])
	if _pulse != null and _pulse_id == id:
		return
	if _pulsed.has(id) and _frame - int(_pulsed[id]) < PULSE_FRAMES:
		return
	var player: Gen2BattleAnimPlayer = Gen2BattleAnimPlayer.create(
		_anim_data, SHINY_ANIM, true, SHINY_ANIM_PARAM
	)
	if player == null:
		return
	_pulsed[id] = _frame
	_pulse = player
	_pulse_id = id


## One frame of the running pulse. The field and background layer is not run at
## all: the map is the background out here, and `BattleAnimCmd_*BGEffect` edits a
## battle tilemap this view does not have.
func _advance_pulse() -> bool:
	if _pulse == null:
		return false
	if _pulse.finished() or pulse_anchor() == null:
		_pulse = null
		_pulse_id = &""
		return true
	_pulse.advance_frame()
	_frame_commands = _pulse.frame_commands()
	return true


func _changed(before: Array, after: Array) -> bool:
	if before.size() != after.size():
		return true
	for index: int in before.size():
		var was: Dictionary = before[index]
		var now: Dictionary = after[index]
		if was["cell"] != now["cell"] or int(was["facing"]) != int(now["facing"]) \
			or int(was["species"]) != int(now["species"]) \
			or bool(was["shiny"]) != bool(now["shiny"]):
			return true
	return false
