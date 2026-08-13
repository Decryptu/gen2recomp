class_name Gen2ModHost
extends RefCounted

## What a mod is allowed to change, and the only way it gets to change it.
##
## A mod never touches scene nodes or engine internals: it is handed this host,
## registers what it provides, and is done. All it can reach is cartridge content
## through [GameData] and live world state through [Gen2WorldAPI], both
## scene-free.
##
## Two things are replaceable this way: the world renderer and the battle
## renderer. Nothing about either requires the drawing to be 2D, so a renderer
## building geometry from the same block and collision data, or drawing a battle
## from the same display values, is a registration, not a fork.
## [method select_world_renderer] and [method select_battle_renderer] swap
## between registered renderers, which is why the contract is a factory rather
## than a one-time construction.
##
## Mods are interpreted GDScript: iOS forbids JIT and runtime native loading, so
## a compiled extension is not an option for a distributed mod.

## Where installed mods live. Under user:// because a mod is not part of the
## build and must survive an update of it.
const ROOT: String = "user://mods"
## The methods a world renderer has to provide. A registration that is missing
## one is refused at registration, where the mod's name is still in hand, rather
## than failing on the first frame it is asked to draw.
const WORLD_RENDERER_METHODS: Array[String] = [
	"set_world", "set_time_of_day", "refresh", "refresh_animation",
]
## The methods a battle renderer has to provide.
const BATTLE_RENDERER_METHODS: Array[String] = [
	"set_battle_data", "set_view", "refresh",
]
## Optional. A renderer defining this and answering false gets the screen's own
## rectangle at window resolution instead of the 160x144 viewport. A view built
## from geometry cannot be drawn into a 160x144 buffer and magnified, so this is
## what makes a 3D or HD renderer possible at all.
##
## A renderer that does not define it draws in hardware pixels, which is what the
## built-in ones do and what a tile-recolouring mod wants. Shared by both
## renderer kinds.
const RENDERER_SURFACE_METHOD: String = "uses_hardware_viewport"
## Optional. Called with the native layer's size in window pixels when it is
## created and whenever the window changes it. Only reached by a renderer that
## asked for the native layer. Shared by both renderer kinds.
const RENDERER_RESIZE_METHOD: String = "set_native_size"
## Optional, battle renderers only. Called with a [Gen2BattleWorldContext] once
## per battle, before the first [code]set_view[/code], when the battle was
## entered from the world. It is where the fight is happening: a renderer staging
## it on the map needs that, and one drawing the cartridge's white field ignores
## it. A development battle started outside the world passes null.
const RENDERER_WORLD_CONTEXT_METHOD: String = "set_world_context"
## Optional, world renderers only. Offered every input event the world screen
## chose not to use, so a renderer can own camera pitch, first person or
## free-roam. Answering true consumes the event.
##
## The screen decides first and offers what is left, so a renderer can never take
## a movement or interaction key: a renderer reads world state and must not write
## it, and moving the player is writing it. A renderer wanting free-roam movement
## is the separate pose layer docs/MODS.md describes, not this.
##
## Implement this rather than Godot's own [method Node._input] or
## [method Node._unhandled_input]: a node in the tree is offered events before
## the screen decides what it needs, so reading them directly races the gameplay
## keys instead of taking what is left.
const RENDERER_INPUT_METHOD: String = "handle_world_input"
## Optional, battle renderers only. The same seam on the battle side: every event
## [Gen2BattleScreen] did not claim, so a renderer composing its own shot can let
## someone steer it. Answering true consumes the event.
##
## A [Gen2Button] never arrives here, on either side. The screen routes every one
## of them to whatever owns it first, so a text box, the forget-move list and
## ball selection all take their press before a renderer could see it, and what
## is left is pointer and stick motion the screen has no opinion about.
const RENDERER_BATTLE_INPUT_METHOD: String = "handle_battle_input"
## Optional, both renderer kinds. How opaque the screen draws the field of its
## own text box while this renderer is on the native layer, from 0 for invisible
## to 1 for the cartridge's own solid white. The frame's lines and the glyphs are
## ink and stay opaque, so nothing becomes harder to read.
##
## Only honoured for a renderer that answered [constant
## RENDERER_SURFACE_METHOD] false: a renderer drawing in hardware pixels paints
## the background the box sits on, and a hole in the box would show the window
## behind the screen rather than the map.
const RENDERER_INTERFACE_OPACITY_METHOD: String = "interface_opacity"
## Optional, both renderer kinds. Called with the rectangle the screen's text box
## covers, in hardware pixels, whenever it changes, and with an empty rectangle
## when no box is on screen. A renderer composing around the box reads this
## instead of assuming the standard twenty by six at row twelve.
const RENDERER_TEXT_BOX_METHOD: String = "set_text_box_rect"
## The id of the built-in 2D renderer, which is always registered for both
## renderer kinds.
const BUILT_IN_RENDERER: StringName = &"gen2"

## The menus a mod may append an entry to. The cartridge's own entries are not
## registered here: they live in Gen2WorldStartMenu and Gen2WorldPack, which
## build their source list first and then append whatever is registered, so a
## mod can only add and never reorder or remove what the game shipped.
const MENU_START: StringName = &"start_menu"
const MENU_PACK_POCKET: StringName = &"pack_pocket"
const MENU_IDS: Array[StringName] = [MENU_START, MENU_PACK_POCKET]

## The event channels a mod may watch. Both carry the typed dictionaries the
## engine already produces, published where the screen reads them, so a
## subscriber sees exactly the events a player sees and in the same order.
const CHANNEL_WORLD: StringName = &"world"
const CHANNEL_BATTLE: StringName = &"battle"
const CHANNELS: Array[StringName] = [CHANNEL_WORLD, CHANNEL_BATTLE]
## Pocket type numbers 1 to 4 are the cartridge's ITEM, KEY_ITEM, BALL and TM_HM,
## so a registered pocket has to claim a number above them, the same reservation
## [constant Gen2ContentOverlay.FIRST_MOD_NUMBER] makes for content.
const FIRST_MOD_POCKET: int = 5

## The two shapes a registered setting can take: a ladder of values the player
## steps along, and a button that does something the moment it is pressed. A
## button stores nothing, because "recentre the camera now" has no value to keep.
const OPTION_LADDER: StringName = &"ladder"
const OPTION_BUTTON: StringName = &"button"
const OPTION_KINDS: Array[StringName] = [OPTION_LADDER, OPTION_BUTTON]

## Emitted when a registered option's value changes, whichever surface changed
## it. A mod that has to rebuild something on a change connects to this rather
## than reading its options every frame.
signal option_changed(id: StringName, key: StringName, value: Variant)
## Emitted when one of a mod's own registered actions is pressed or released,
## whichever device produced it. See [method register_action].
signal action_changed(id: StringName, key: StringName, pressed: bool)

static var _instance: Gen2ModHost = null

var _manifests: Dictionary = {}
## Mod id to version for every entry script that ran. See [method loaded_mods].
var _loaded: Dictionary = {}
## The cartridge being played, which is what a mod's `games` declaration is
## checked against. Empty until one is chosen, and an empty target restricts
## nothing: the launcher runs before Play is pressed.
var _target_game: StringName = &""
var _options: Dictionary = {}
## Mod id to its registered actions. See [method register_action].
var _actions: Dictionary = {}
var _world_renderers: Dictionary = {}
var _selected_world_renderer: StringName = BUILT_IN_RENDERER
var _battle_renderers: Dictionary = {}
var _selected_battle_renderer: StringName = BUILT_IN_RENDERER
var _menu_entries: Dictionary = {}
var _subscribers: Dictionary = {}
var _failures: Array = []


## The shared host. Created with the built-in renderers already registered, so a
## caller that never loads a mod still goes through the same boundary.
static func instance() -> Gen2ModHost:
	if _instance == null:
		_instance = Gen2ModHost.new()
		_instance.register_world_renderer(
			BUILT_IN_RENDERER, Gen2WorldRenderer, "Game Boy Color 2D"
		)
		_instance.register_battle_renderer(
			BUILT_IN_RENDERER, Gen2BattleRenderer, "Game Boy Color 2D"
		)
	return _instance


## Discards every loaded mod and returns to the built-in renderers. For tests and
## for a launcher that reloads the mod list.
static func reset() -> void:
	_instance = null
	Gen2ContentOverlay.reset()
	Gen2MoveEffect.reset_registry()


## Registers a world renderer under [param id].
##
## [param script] is instantiated per world, so one registration serves a map
## change, a snapshot restore and a live switch between renderers.
func register_world_renderer(
	id: StringName, script: Script, label: String = ""
) -> Dictionary:
	return _register(_world_renderers, WORLD_RENDERER_METHODS, id, script, label)


func world_renderer_ids() -> Array:
	return _world_renderers.keys()


func world_renderer_label(id: StringName) -> String:
	return _renderer_label(_world_renderers, id)


func selected_world_renderer() -> StringName:
	return _selected_world_renderer


## Chooses which registered renderer new worlds are drawn with. The caller
## rebuilds its view; this only decides what [method create_world_renderer]
## hands back, so a keybind can flip between 2D and a mod's renderer.
func select_world_renderer(id: StringName) -> Dictionary:
	var result: Dictionary = _select(_world_renderers, id)
	if bool(result.get("ok", false)):
		_selected_world_renderer = id
	return result


## A fresh renderer node for the selected world renderer, falling back to the
## built-in one so a screen always has something to draw with.
func create_world_renderer() -> Node:
	return _create(_world_renderers, _selected_world_renderer, Gen2WorldRenderer)


## Registers a battle renderer under [param id]. See
## [method register_world_renderer]; the same registration rules apply.
func register_battle_renderer(
	id: StringName, script: Script, label: String = ""
) -> Dictionary:
	return _register(_battle_renderers, BATTLE_RENDERER_METHODS, id, script, label)


func battle_renderer_ids() -> Array:
	return _battle_renderers.keys()


func battle_renderer_label(id: StringName) -> String:
	return _renderer_label(_battle_renderers, id)


func selected_battle_renderer() -> StringName:
	return _selected_battle_renderer


## Chooses which registered renderer new battles are drawn with. See
## [method select_world_renderer].
func select_battle_renderer(id: StringName) -> Dictionary:
	var result: Dictionary = _select(_battle_renderers, id)
	if bool(result.get("ok", false)):
		_selected_battle_renderer = id
	return result


## A fresh renderer node for the selected battle renderer, falling back to the
## built-in one so a screen always has something to draw with.
func create_battle_renderer() -> Node:
	return _create(_battle_renderers, _selected_battle_renderer, Gen2BattleRenderer)


## Adds one entry to [param menu]. [param entry] needs a [code]label[/code]; the
## start menu takes an optional [code]handler[/code] Callable the screen calls
## when the entry is chosen, and a pack pocket needs a [code]pocket[/code] type
## number at or above [constant FIRST_MOD_POCKET], which is the number its items
## carry in their own definitions.
##
## An entry without a handler still appears, marked unavailable, which is what
## every unimplemented cartridge entry already does.
func register_menu_entry(menu: StringName, id: StringName, entry: Dictionary) -> Dictionary:
	if not MENU_IDS.has(menu):
		return {"ok": false, "reason": &"unknown_menu", "detail": String(menu)}
	if String(id).is_empty():
		return {"ok": false, "reason": &"invalid_menu_entry", "detail": String(menu)}
	var label: String = String(entry.get("label", ""))
	if label.is_empty():
		return {"ok": false, "reason": &"menu_entry_missing_label", "detail": String(id)}
	var registered: Dictionary = {"kind": id, "label": label}
	if menu == MENU_PACK_POCKET:
		var pocket: int = int(entry.get("pocket", 0))
		if pocket < FIRST_MOD_POCKET:
			return {"ok": false, "reason": &"reserved_pocket", "detail": String(id)}
		registered["pocket"] = pocket
	else:
		var handler: Variant = entry.get("handler", null)
		registered["available"] = handler is Callable and (handler as Callable).is_valid()
		if bool(registered["available"]):
			registered["handler"] = handler
	var entries: Array = _menu_entries.get(menu, [])
	for existing: Dictionary in entries:
		if StringName(existing.get("kind", &"")) == id:
			return {"ok": false, "reason": &"duplicate_menu_entry", "detail": String(id)}
	entries.append(registered)
	_menu_entries[menu] = entries
	return {"ok": true, "id": id}


## Every entry registered for [param menu], in registration order. The callers
## append these to their own source list rather than the other way round.
func menu_entries(menu: StringName) -> Array:
	var entries: Array = _menu_entries.get(menu, [])
	return entries.duplicate(true)


## Adds one setting the player can change, as a ladder of values.
##
## [param option] needs a [code]key[/code], a [code]label[/code] and a non-empty
## [code]values[/code] array; [code]labels[/code] is what each rung is shown as
## and defaults to the values themselves, and [code]default[/code] is the rung
## used until the player picks one and defaults to the first. A toggle is a
## two-rung ladder.
##
## A mod describes a setting rather than drawing one: the start menu's MODS entry
## and the launcher's mods page are both built from these registrations, so a mod
## never writes a settings screen and the two surfaces cannot disagree.
func register_option(id: StringName, option: Dictionary) -> Dictionary:
	var key: StringName = StringName(option.get("key", &""))
	if String(id).is_empty() or String(key).is_empty():
		return {"ok": false, "reason": &"invalid_option", "detail": String(id)}
	var label: String = String(option.get("label", ""))
	if label.is_empty():
		return {"ok": false, "reason": &"option_missing_label", "detail": _option_name(id, key)}
	var kind: StringName = StringName(option.get("kind", OPTION_LADDER))
	if not OPTION_KINDS.has(kind):
		return {"ok": false, "reason": &"unknown_option_kind", "detail": String(kind)}
	if kind == OPTION_BUTTON:
		return _register_button_option(id, key, label, option)
	var values: Array = option.get("values", []) as Array
	if values.is_empty():
		return {"ok": false, "reason": &"option_missing_values", "detail": _option_name(id, key)}
	var labels: Array = option.get("labels", []) as Array
	if labels.is_empty():
		labels = []
		for value: Variant in values:
			labels.append(str(value))
	elif labels.size() != values.size():
		return {"ok": false, "reason": &"option_labels_mismatch", "detail": _option_name(id, key)}
	var rows: Array = _options.get(id, [])
	for existing: Dictionary in rows:
		if StringName(existing.get("key", &"")) == key:
			return {"ok": false, "reason": &"duplicate_option", "detail": _option_name(id, key)}
	var fallback: int = maxi(_value_index(values, option.get("default", values[0])), 0)
	rows.append({
		"key": key, "label": label, "kind": OPTION_LADDER, "values": values.duplicate(),
		"labels": _strings(labels), "default": fallback,
	})
	_options[id] = rows
	return {"ok": true, "id": id, "key": key}


## A setting that is a press rather than a ladder: "recentre the camera now" has
## no values and nothing to persist, so it stores nothing and only emits.
func _register_button_option(
	id: StringName, key: StringName, label: String, option: Dictionary
) -> Dictionary:
	var rows: Array = _options.get(id, [])
	for existing: Dictionary in rows:
		if StringName(existing.get("key", &"")) == key:
			return {"ok": false, "reason": &"duplicate_option", "detail": _option_name(id, key)}
	rows.append({
		"key": key, "label": label, "kind": OPTION_BUTTON,
		"press_label": String(option.get("press_label", "Go")),
		"values": [], "labels": [], "default": 0,
	})
	_options[id] = rows
	return {"ok": true, "id": id, "key": key}


## Presses a button-kind setting. Nothing is stored: what a press means is the
## mod's, and [signal option_changed] carries a null value to say so.
func press_option(id: StringName, key: StringName) -> Dictionary:
	var row: Dictionary = _option_row(id, key)
	if row.is_empty():
		return {"ok": false, "reason": &"unknown_option", "detail": _option_name(id, key)}
	if StringName(row.get("kind", OPTION_LADDER)) != OPTION_BUTTON:
		return {"ok": false, "reason": &"option_is_not_a_button", "detail": _option_name(id, key)}
	option_changed.emit(id, key, null)
	return {"ok": true, "id": id, "key": key}


## The ids that registered at least one option, in registration order. Both
## surfaces list these: a mod that registered none has nothing to show and is
## deliberately absent rather than shown with an empty page.
func option_mod_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in _options:
		ids.append(id)
	return ids


## One mod's settings, in registration order, as
## `{key, label, values, labels, default, index, value}` per row. `index` and
## `value` are the live choice; the rest is what was registered.
func options(id: StringName) -> Array:
	var out: Array = []
	for row: Dictionary in _options.get(id, []) as Array:
		if StringName(row.get("kind", OPTION_LADDER)) == OPTION_BUTTON:
			out.append({
				"key": row["key"], "label": row["label"], "kind": OPTION_BUTTON,
				"press_label": row["press_label"],
				"values": [], "labels": [], "default": 0, "index": 0, "value": null,
			})
			continue
		var index: int = _stored_index(id, row)
		out.append({
			"key": row["key"], "label": row["label"], "kind": OPTION_LADDER,
			"values": (row["values"] as Array).duplicate(),
			"labels": (row["labels"] as Array).duplicate(),
			"default": row["default"], "index": index, "value": row["values"][index],
		})
	return out


## What [param key] is currently set to, which is the registered default until
## the player changes it, and null when nothing registered that key.
func option(id: StringName, key: StringName) -> Variant:
	var row: Dictionary = _option_row(id, key)
	if row.is_empty():
		return null
	return (row["values"] as Array)[_stored_index(id, row)]


## Which rung of the ladder [param key] is on, and -1 when nothing registered it.
func option_index(id: StringName, key: StringName) -> int:
	var row: Dictionary = _option_row(id, key)
	return -1 if row.is_empty() else _stored_index(id, row)


## Sets [param key] to [param value], which has to be one of the registered
## values. Persisted immediately, the way the cartridge's own OPTION menu commits
## each press, and [signal option_changed] follows the write.
func set_option(id: StringName, key: StringName, value: Variant) -> Dictionary:
	var row: Dictionary = _option_row(id, key)
	if row.is_empty():
		return {"ok": false, "reason": &"unknown_option", "detail": _option_name(id, key)}
	var index: int = _value_index(row["values"] as Array, value)
	if index < 0:
		return {"ok": false, "reason": &"invalid_option_value", "detail": _option_name(id, key)}
	return set_option_index(id, key, index)


## The same by rung rather than by value, which is what a menu stepping left and
## right has in hand.
func set_option_index(id: StringName, key: StringName, index: int) -> Dictionary:
	var row: Dictionary = _option_row(id, key)
	if row.is_empty():
		return {"ok": false, "reason": &"unknown_option", "detail": _option_name(id, key)}
	var values: Array = row["values"] as Array
	if index < 0 or index >= values.size():
		return {"ok": false, "reason": &"invalid_option_value", "detail": _option_name(id, key)}
	if not Gen2ModOptions.store(id, key, values[index]):
		return {"ok": false, "reason": &"option_not_written", "detail": Gen2ModOptions.PATH}
	option_changed.emit(id, key, values[index])
	return {"ok": true, "id": id, "key": key, "index": index, "value": values[index]}


## Declares a control of the mod's own, in the shape [method register_option]
## uses for a setting.
##
## [codeblock]
## host.register_action(manifest.id, {
##     "key": &"pitch_up",
##     "label": "Raise the camera",
##     "default": [{"kind": "key", "code": KEY_R}],
## })
## [/codeblock]
##
## `default` is [Gen2InputActions]' own binding shape, so a mod's action is bound
## by key, pad button or stick and is rebound by the controls card that rebinds
## the eight. A default already on one of the cartridge's buttons is dropped and
## reported: the screen claims those before a renderer is offered anything, so
## such a binding would never once fire.
func register_action(id: StringName, action: Dictionary) -> Dictionary:
	var key: StringName = StringName(action.get("key", &""))
	if String(id).is_empty() or String(key).is_empty():
		return {"ok": false, "reason": &"invalid_action", "detail": String(id)}
	var label: String = String(action.get("label", ""))
	if label.is_empty():
		return {"ok": false, "reason": &"action_missing_label", "detail": _option_name(id, key)}
	var rows: Array = _actions.get(id, [])
	for existing: Dictionary in rows:
		if StringName(existing.get("key", &"")) == key:
			return {"ok": false, "reason": &"duplicate_action", "detail": _option_name(id, key)}
	var scheme: Dictionary = _control_scheme()
	var defaults: Array = []
	var taken: Array[String] = []
	for row: Variant in action.get("default", []) as Array:
		if row is not Dictionary:
			continue
		# Through the same clamp the options file uses, so a declared binding and
		# a stored one are the same shape and can be compared at all.
		var binding: Dictionary = Gen2InputActions.sanitize_binding(row as Dictionary)
		if binding.is_empty():
			continue
		var button: int = Gen2InputActions.button_bound_to(scheme, binding)
		if button != Gen2Button.NONE:
			taken.append("%s is %s" % [
				Gen2InputActions.describe(binding), Gen2Button.label(button)
			])
			continue
		defaults.append(binding.duplicate())
	if not taken.is_empty():
		_failures.append({
			"ok": false, "reason": &"action_default_taken",
			"detail": "%s: %s" % [_option_name(id, key), ", ".join(taken)],
			"id": id,
		})
	rows.append({
		"key": key, "label": label, "default": defaults,
		"name": Gen2InputActions.mod_action_name(id, key),
	})
	_actions[id] = rows
	return {"ok": true, "id": id, "key": key, "dropped": taken.size()}


## Every registered action, in registration order, as `{id, key, label, name,
## default}`. [Gen2InputRuntime] installs these and the controls card lists them.
func actions() -> Array:
	var out: Array = []
	for id: StringName in _actions:
		for row: Dictionary in _actions[id] as Array:
			out.append({
				"id": id, "key": row["key"], "label": row["label"],
				"name": row["name"], "default": (row["default"] as Array).duplicate(true),
			})
	return out


## Whether a mod's action is held right now, whatever is holding it: a key, a
## pad button, a stick past the deadzone or a finger on the on-screen pad. The
## poll a camera wants; [signal action_pressed] is the edge.
func action_held(id: StringName, key: StringName) -> bool:
	var name: StringName = Gen2InputActions.mod_action_name(id, key)
	return InputMap.has_action(name) and Input.is_action_pressed(name)


## The same as a magnitude, 0 to 1. A stick bound to an action answers its travel
## past the deadzone, so a camera bound to the right stick moves at the rate the
## player is pushing it; a key answers 0 or 1.
func action_strength(id: StringName, key: StringName) -> float:
	var name: StringName = Gen2InputActions.mod_action_name(id, key)
	return Input.get_action_strength(name) if InputMap.has_action(name) else 0.0


## The registered action an event has just pressed or released, as
## `{id, key, pressed}`, or an empty dictionary. A screen asks this with what it
## did not claim, which is what keeps a mod's key out of a menu.
func action_in(event: InputEvent) -> Dictionary:
	for row: Dictionary in actions():
		var name: StringName = row["name"]
		if event.is_action_pressed(name):
			return {"id": row["id"], "key": row["key"], "pressed": true}
		if event.is_action_released(name):
			return {"id": row["id"], "key": row["key"], "pressed": false}
	return {}


## Announces an action to whoever subscribed. Called by the screen that offered
## the event, so a mod hears its own control rather than an [InputEvent].
func emit_action(id: StringName, key: StringName, pressed: bool) -> void:
	action_changed.emit(id, key, pressed)


## The live control scheme, or the stock one when no runtime owns it yet, which
## is every headless run.
static func _control_scheme() -> Dictionary:
	var runtime: Gen2InputRuntime = Gen2InputRuntime.instance()
	if runtime == null:
		return Gen2InputActions.defaults()
	var scheme: Dictionary = runtime.scheme()
	return scheme if not scheme.is_empty() else Gen2InputActions.defaults()


func _option_row(id: StringName, key: StringName) -> Dictionary:
	for row: Dictionary in _options.get(id, []) as Array:
		if StringName(row["key"]) == key:
			return row
	return {}


## The stored choice resolved against the ladder as it is registered now, so a
## value left by an older version of the mod falls back to the default instead of
## selecting nothing.
func _stored_index(id: StringName, row: Dictionary) -> int:
	var stored: Variant = Gen2ModOptions.value(id, StringName(row["key"]))
	if stored == null:
		return int(row["default"])
	var index: int = _value_index(row["values"] as Array, stored)
	return index if index >= 0 else int(row["default"])


## Which rung carries [param value], or -1. Two numbers of the same magnitude
## match whatever their type, because a value read back out of JSON is a float
## where the registration wrote an int.
static func _value_index(values: Array, value: Variant) -> int:
	for index: int in values.size():
		var candidate: Variant = values[index]
		if candidate is float or candidate is int:
			if (value is float or value is int) and is_equal_approx(
				float(candidate), float(value)
			):
				return index
		elif typeof(candidate) == typeof(value) and candidate == value:
			return index
	return -1


static func _strings(values: Array) -> Array[String]:
	var out: Array[String] = []
	for value: Variant in values:
		out.append(String(value))
	return out


static func _option_name(id: StringName, key: StringName) -> String:
	return "%s/%s" % [id, key]


## Adds a species, move, item or trainer class the cartridge does not have.
##
## [param number] has to be at or above
## [constant Gen2ContentOverlay.FIRST_MOD_NUMBER], and [param row] is a partial
## row: whatever it leaves out comes from the kind's defaults. Everything a
## species carries is on that row, so a defined Pokémon's learnset, evolutions
## and TM compatibility are fields rather than separate registrations.
func register_content(
	kind: StringName, id: StringName, number: int, row: Dictionary
) -> Dictionary:
	return Gen2ContentOverlay.shared().define(kind, id, number, row)


## Changes named fields of a row the cartridge does have: a move's power, a
## species' types, an item's price. Dictionary fields merge, so patching one stat
## leaves the other five alone.
func patch_content(
	kind: StringName, id: StringName, number: int, fields: Dictionary
) -> Dictionary:
	return Gen2ContentOverlay.shared().patch(kind, id, number, fields)


## The overlay every opened [GameData] reads through, for a launcher listing what
## a mod changed before the player starts.
func content_overlay() -> Gen2ContentOverlay:
	return Gen2ContentOverlay.shared()


## Watches one of [constant CHANNELS]. [param handler] is called with each event
## dictionary as it reaches the screen showing it.
##
## Reading only. A subscriber is handed a copy, so writing to it changes nothing,
## and there is no return value the engine reads: observation cannot make two
## mods fight over the same state, which is what makes this safe to hand out
## before any mutation hook exists.
func subscribe(channel: StringName, id: StringName, handler: Callable) -> Dictionary:
	if not CHANNELS.has(channel):
		return {"ok": false, "reason": &"unknown_channel", "detail": String(channel)}
	if String(id).is_empty():
		return {"ok": false, "reason": &"invalid_subscriber", "detail": String(channel)}
	if not handler.is_valid():
		return {"ok": false, "reason": &"invalid_subscriber_handler", "detail": String(id)}
	var handlers: Dictionary = _subscribers.get(channel, {})
	if handlers.has(id):
		return {"ok": false, "reason": &"duplicate_subscriber", "detail": String(id)}
	handlers[id] = handler
	_subscribers[channel] = handlers
	return {"ok": true, "id": id}


func unsubscribe(channel: StringName, id: StringName) -> void:
	(_subscribers.get(channel, {}) as Dictionary).erase(id)


## Hands [param event] to whoever is watching [param channel].
##
## Static and null-safe on the instance, because this sits on the path every
## battle event and every world result takes: a game with no mods must not build
## a host, or copy an event, to publish to nobody.
static func publish(channel: StringName, event: Dictionary) -> void:
	if _instance == null:
		return
	var handlers: Dictionary = _instance._subscribers.get(channel, {})
	if handlers.is_empty():
		return
	for id: StringName in handlers.keys():
		var handler: Callable = handlers[id]
		if handler.is_valid():
			handler.call(event.duplicate(true))


## Adds a move effect, as the list of commands a move carrying [param effect]
## runs. See [Gen2MoveEffect] for the lists the cartridge's own effects use and
## [Gen2EffectCommands] for the steps one is built from.
func register_move_effect(id: StringName, effect: int, commands: Array) -> Dictionary:
	return Gen2MoveEffect.register_effect(id, effect, commands)


## Adds a step a move effect's list can name, as a Callable taking the
## [Gen2Turn]. Registered commands are tried after the engine's own, so a mod
## cannot shadow [constant Gen2EffectCommands.APPLY_DAMAGE] with something else.
func register_effect_command(id: StringName, command: StringName, handler: Callable) -> Dictionary:
	return Gen2MoveEffect.register_command(id, command, handler)


func _register(
	registry: Dictionary, methods: Array[String], id: StringName, script: Script,
	label: String,
) -> Dictionary:
	if String(id).is_empty() or script == null:
		return {"ok": false, "reason": &"invalid_renderer"}
	var probe: Object = script.new()
	if probe == null:
		return {"ok": false, "reason": &"renderer_not_instantiable", "detail": String(id)}
	var missing: Array[String] = []
	for method: String in methods:
		if not probe.has_method(method):
			missing.append(method)
	var is_node: bool = probe is Node
	if probe is RefCounted:
		probe = null
	elif probe is Node:
		(probe as Node).free()
	if not is_node:
		return {"ok": false, "reason": &"renderer_not_a_node", "detail": String(id)}
	if not missing.is_empty():
		return {
			"ok": false, "reason": &"renderer_missing_methods",
			"detail": "%s: %s" % [id, ", ".join(missing)],
		}
	# Two mods claiming one renderer id is a conflict a player wants named, the
	# same way two claiming a menu entry id is. Silently keeping the last loaded
	# would leave the earlier mod installed, listed and drawing nothing.
	if registry.has(id):
		return {"ok": false, "reason": &"duplicate_renderer", "detail": String(id)}
	registry[id] = {
		"script": script,
		"label": label if not label.is_empty() else String(id),
	}
	return {"ok": true, "id": id}


func _renderer_label(registry: Dictionary, id: StringName) -> String:
	return String((registry.get(id, {}) as Dictionary).get("label", ""))


func _select(registry: Dictionary, id: StringName) -> Dictionary:
	if not registry.has(id):
		return {"ok": false, "reason": &"unknown_renderer", "detail": String(id)}
	return {"ok": true, "id": id}


func _create(registry: Dictionary, selected: StringName, fallback_script: Script) -> Node:
	var entry: Dictionary = registry.get(selected, {})
	var script: Variant = entry.get("script", null)
	if script is Script:
		var node: Object = (script as Script).new()
		if node is Node:
			return node as Node
	return fallback_script.new()


## Which of the screen's two layers [param renderer] is drawn on. See
## [constant RENDERER_SURFACE_METHOD]; not answering means hardware pixels, so a
## renderer written before this existed keeps the layer it was written for.
## Shared by both renderer kinds.
static func renderer_uses_hardware_viewport(renderer: Node) -> bool:
	if renderer == null or not renderer.has_method(RENDERER_SURFACE_METHOD):
		return true
	return bool(renderer.call(RENDERER_SURFACE_METHOD))


## Offers [param event] to a world [param renderer], returning whether it was
## consumed. See [constant RENDERER_INPUT_METHOD]; a renderer that does not take
## input leaves every event where it was.
static func renderer_handles_input(renderer: Node, event: InputEvent) -> bool:
	return _renderer_takes_input(renderer, RENDERER_INPUT_METHOD, event)


## The same for a battle renderer. See
## [constant RENDERER_BATTLE_INPUT_METHOD].
static func renderer_handles_battle_input(renderer: Node, event: InputEvent) -> bool:
	return _renderer_takes_input(renderer, RENDERER_BATTLE_INPUT_METHOD, event)


## How opaque [param renderer] wants the screen's own text box field drawn. See
## [constant RENDERER_INTERFACE_OPACITY_METHOD]; a renderer that does not ask,
## and every renderer drawing in hardware pixels, gets the cartridge's solid 1.0.
static func renderer_interface_opacity(renderer: Node) -> float:
	if renderer == null or not renderer.has_method(RENDERER_INTERFACE_OPACITY_METHOD):
		return 1.0
	if renderer_uses_hardware_viewport(renderer):
		return 1.0
	return clampf(float(renderer.call(RENDERER_INTERFACE_OPACITY_METHOD)), 0.0, 1.0)


## Tells [param renderer] where the screen's text box is, in hardware pixels. See
## [constant RENDERER_TEXT_BOX_METHOD]; a renderer that does not ask is not
## called.
static func renderer_set_text_box_rect(renderer: Node, rect: Rect2i) -> void:
	if renderer == null or not renderer.has_method(RENDERER_TEXT_BOX_METHOD):
		return
	renderer.call(RENDERER_TEXT_BOX_METHOD, rect)


static func _renderer_takes_input(renderer: Node, method: String, event: InputEvent) -> bool:
	if renderer == null or event == null or not renderer.has_method(method):
		return false
	return bool(renderer.call(method, event))


## Reads every installed mod's manifest without running any of them. The
## launcher lists these; refusals are kept so it can say why one is absent.
func discover(root: String = ROOT) -> Array:
	_manifests = {}
	_failures = []
	var directory: DirAccess = DirAccess.open(root)
	if directory == null:
		return []
	directory.list_dir_begin()
	var name: String = directory.get_next()
	while name != "":
		if directory.current_is_dir() and not name.begins_with("."):
			var result: Dictionary = Gen2ModManifest.read("%s/%s" % [root, name])
			if bool(result.get("ok", false)):
				var manifest: Gen2ModManifest = result["manifest"]
				if _manifests.has(manifest.id):
					_failures.append(_dependency_refusal(
						manifest, &"duplicate_mod_id", String(manifest.id)
					))
				else:
					_manifests[manifest.id] = manifest
			else:
				result["directory"] = name
				_failures.append(result)
		name = directory.get_next()
	directory.list_dir_end()
	return _manifests.values()


## What the last [method discover] accepted, without discovering again. A second
## discover would drop the load failures recorded after it.
func manifests() -> Array:
	return _manifests.values()


func failures() -> Array:
	return _failures.duplicate(true)


## Names the cartridge about to be played, before [method load_discovered] runs.
## Set by GameRuntime when a game is chosen; a host that is never told keeps
## every mod, which is what the launcher wants while nothing is selected.
func set_target_game(game_id: StringName) -> void:
	_target_game = game_id


func target_game() -> StringName:
	return _target_game


## A mod may read and replace only its own slot namespace. The exact manifest
## object handed to register() is the capability; inventing another object with
## the same id grants nothing.
func read_save_data(manifest: Gen2ModManifest, save: Gen2SaveData) -> Dictionary:
	if not _owns_manifest(manifest) or save == null:
		return {}
	return save.mod_data(manifest.id)


func write_save_data(
	manifest: Gen2ModManifest, save: Gen2SaveData, value: Dictionary
) -> Dictionary:
	if not _owns_manifest(manifest):
		return {"ok": false, "reason": &"unknown_mod_save_owner"}
	if save == null:
		return {"ok": false, "reason": &"missing_mod_save"}
	return save.set_mod_data(manifest.id, value)


func _owns_manifest(manifest: Gen2ModManifest) -> bool:
	return manifest != null and _manifests.get(manifest.id) == manifest


## Runs each discovered mod's entry script, which registers what it provides.
##
## A mod that will not load is reported and skipped: one broken mod must not
## stop the others, and it must not stop the game starting. A mod the player
## switched off is skipped silently and is not a failure, and a mod for another
## cartridge is a recorded refusal the launcher can show.
func load_discovered() -> Array:
	var loaded: Array = []
	var pending: Array[StringName] = []
	var failed: Dictionary = {}
	for raw_id: Variant in _manifests:
		var id := StringName(raw_id)
		if not Gen2ModState.is_enabled(id):
			continue
		var manifest: Gen2ModManifest = _manifests[id]
		if not manifest.supports_game(_target_game):
			_failures.append(_dependency_refusal(
				manifest, &"incompatible_game", RomRegistry.title_for(_target_game)
			))
			continue
		pending.append(id)
	pending.sort()

	# Refuse unsatisfied declarations before running any entry code.
	for id: StringName in pending.duplicate():
		var manifest: Gen2ModManifest = _manifests[id]
		for raw_dependency: Variant in manifest.dependencies:
			var dependency := StringName(raw_dependency)
			if not _manifests.has(dependency):
				_failures.append(_dependency_refusal(
					manifest, &"missing_dependency", String(dependency)
				))
				failed[id] = true
				pending.erase(id)
				break
			if not Gen2ModState.is_enabled(dependency):
				_failures.append(_dependency_refusal(
					manifest, &"dependency_disabled", String(dependency)
				))
				failed[id] = true
				pending.erase(id)
				break
			var installed: Gen2ModManifest = _manifests[dependency]
			var wanted: String = String(manifest.dependencies[raw_dependency])
			if not Gen2ModVersion.matches(installed.version, wanted):
				_failures.append(_dependency_refusal(
					manifest, &"incompatible_dependency",
					"%s %s (installed %s)" % [dependency, wanted, installed.version]
				))
				failed[id] = true
				pending.erase(id)
				break

	while not pending.is_empty():
		var progressed: bool = false
		for id: StringName in pending.duplicate():
			var manifest: Gen2ModManifest = _manifests[id]
			var waiting: bool = false
			var broken: StringName = &""
			for raw_dependency: Variant in manifest.dependencies:
				var dependency := StringName(raw_dependency)
				if failed.has(dependency):
					broken = dependency
					break
				if not loaded.has(dependency):
					waiting = true
			if broken != &"":
				_failures.append(_dependency_refusal(
					manifest, &"dependency_failed", String(broken)
				))
				failed[id] = true
				pending.erase(id)
				progressed = true
				continue
			if waiting:
				continue
			var result: Dictionary = load_mod(manifest)
			if bool(result.get("ok", false)):
				loaded.append(id)
			else:
				_failures.append(result)
				failed[id] = true
			pending.erase(id)
			progressed = true
		if not progressed:
			for id: StringName in pending:
				var manifest: Gen2ModManifest = _manifests[id]
				_failures.append(_dependency_refusal(
					manifest, &"dependency_cycle", String(id)
				))
			break
	return loaded


func _dependency_refusal(
	manifest: Gen2ModManifest, reason: StringName, detail: String
) -> Dictionary:
	return {
		"ok": false, "reason": reason, "detail": detail,
		"id": manifest.id, "directory": manifest.directory,
	}


## Refusals carry the id as well as the reason, because a manifest that parsed
## is only reported by whatever the caller can name it with: without this the
## launcher and the startup warning both say "?".
func load_mod(manifest: Gen2ModManifest) -> Dictionary:
	var path: String = manifest.entry_path()
	if not FileAccess.file_exists(path):
		return _refuse_load(manifest, &"missing_entry_script", path)
	var script: Variant = load(path)
	if not script is Script:
		return _refuse_load(manifest, &"entry_not_a_script", path)
	var mod: Object = (script as Script).new()
	if mod == null or not mod.has_method("register"):
		return _refuse_load(manifest, &"entry_has_no_register", path)
	mod.call("register", self, manifest)
	_loaded[manifest.id] = manifest.version
	return {"ok": true, "id": manifest.id}


## Every mod whose entry script ran, as `id` and `version` pairs in id order.
## What a save records so a crash report or a replay can name what was loaded.
func loaded_mods() -> Array:
	var out: Array = []
	var ids: Array = _loaded.keys()
	ids.sort()
	for id: StringName in ids:
		out.append({"id": String(id), "version": String(_loaded[id])})
	return out


func _refuse_load(manifest: Gen2ModManifest, reason: StringName, path: String) -> Dictionary:
	return {
		"ok": false, "reason": reason, "detail": path,
		"id": manifest.id, "directory": manifest.directory,
	}
