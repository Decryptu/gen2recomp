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
## The id of the built-in 2D renderer, which is always registered for both
## renderer kinds.
const BUILT_IN_RENDERER: StringName = &"gen2"

static var _instance: Gen2ModHost = null

var _manifests: Dictionary = {}
var _world_renderers: Dictionary = {}
var _selected_world_renderer: StringName = BUILT_IN_RENDERER
var _battle_renderers: Dictionary = {}
var _selected_battle_renderer: StringName = BUILT_IN_RENDERER
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


## Runs each discovered mod's entry script, which registers what it provides.
##
## A mod that will not load is reported and skipped: one broken mod must not
## stop the others, and it must not stop the game starting.
func load_discovered() -> Array:
	var loaded: Array = []
	for id: StringName in _manifests:
		var result: Dictionary = load_mod(_manifests[id])
		if bool(result.get("ok", false)):
			loaded.append(id)
		else:
			_failures.append(result)
	return loaded


func load_mod(manifest: Gen2ModManifest) -> Dictionary:
	var path: String = manifest.entry_path()
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": &"missing_entry_script", "detail": path}
	var script: Variant = load(path)
	if not script is Script:
		return {"ok": false, "reason": &"entry_not_a_script", "detail": path}
	var mod: Object = (script as Script).new()
	if mod == null or not mod.has_method("register"):
		return {"ok": false, "reason": &"entry_has_no_register", "detail": path}
	mod.call("register", self, manifest)
	return {"ok": true, "id": manifest.id}
