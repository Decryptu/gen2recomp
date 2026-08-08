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
const STATIC_FIELD: int = Gen2ContentOverlay.FIRST_MOD_NUMBER
## An effect byte no cartridge move carries.
const RECOIL_AND_PARALYSE: int = 0xF0

## Electric. RomLayout names only the types the engine itself names; the rest are
## reached by number, since a move's type byte is already one.
const ELECTRIC: int = 0x17
## Cartridge numbers, for the two rows this mod changes rather than adds.
const PIKACHU: int = 25
const THUNDERBOLT: int = 85


func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	_add_a_species(host, manifest.id)
	_add_a_move(host, manifest.id)
	_rebalance(host, manifest.id)
	_watch(host, manifest.id)


## A whole Pokémon. Everything a species carries is a field on one row, so the
## learnset, the evolution and the TM flags are part of the definition rather
## than four separate registrations; anything left out gets the kind's default,
## which is why this does not have to name a hatch cycle or a gender ratio.
##
## It has no pic: the atlas is decoded from the cartridge and holds 251 slots. A
## mod wanting art for its own species needs a renderer, which is the other half
## of docs/MODS.md.
func _add_a_species(host: Gen2ModHost, id: StringName) -> void:
	host.register_content(Gen2ContentOverlay.KIND_SPECIES, id, VOLTLING, {
		"name": "VOLTLING",
		"stats": {
			"hp": 70, "attack": 65, "defense": 60,
			"speed": 115, "sp_attack": 110, "sp_defense": 70,
		},
		# The second slot repeated is how the cartridge writes a single type.
		"types": [ELECTRIC, ELECTRIC],
		"catch_rate": 45,
		"base_exp": 180,
		"growth_rate": Gen2Experience.GROWTH_MEDIUM_FAST,
		"learnset": [
			{"level": 1, "move": 33},   # TACKLE
			{"level": 8, "move": 84},   # THUNDERSHOCK
			{"level": 20, "move": STATIC_FIELD},
			{"level": 36, "move": THUNDERBOLT},
		],
		"evolutions": [],
	})


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


func _on_battle_event(event: Dictionary) -> void:
	if StringName(event.get("type", &"")) == Gen2Battle.FAINTED:
		print("[new_content] side %d fainted" % int(event.get("side", -1)))


func _on_world_event(event: Dictionary) -> void:
	if StringName(event.get("status", &"")) == &"waiting":
		print("[new_content] the world is waiting on %s" % event.get("event", {}).get("type", ""))
