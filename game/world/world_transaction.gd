class_name Gen2WorldTransaction
extends RefCounted

## The commit boundary every world-owned transaction here shares.
##
## A mart purchase, Kurt's apricorns, a party request, a heal, a field item and
## the pack's TOSS all do the same four things around whatever they actually
## change: validate the save they were handed, build a candidate from it,
## validate that candidate against the world it now describes and write it, and
## put the live world back when any of the three refuses. That shape was
## repeated in three hosts; it lives here instead.
##
## Scene-free and save-model-free: it validates through [Gen2SaveValidator] and
## writes through [Gen2SaveStore], and knows nothing about what the caller
## changed.

## Validates [param save] and returns a candidate to work on, which is a full
## copy rather than a reference: nothing a caller writes to it reaches the live
## save until [method commit] succeeds.
static func begin(world: Gen2WorldAPI, save: Gen2SaveData) -> Dictionary:
	if world == null or world.data == null or save == null:
		return failure(&"missing_save", {})
	var validation: Dictionary = Gen2SaveValidator.validate(save, world.data)
	if not bool(validation.get("ok", false)):
		return failure(&"invalid_save", {"message": validation.get("message", "")})
	return {"ok": true, "candidate": Gen2SaveData.from_dict(save.to_dict())}


## Snapshots the world into [param candidate], validates it, writes it when
## [param persist], and copies it back over [param save]. Any refusal restores
## the world to [param before] and reports which step said no, so a caller never
## has to unwind by hand.
static func commit(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	candidate: Gen2SaveData,
	before: Gen2WorldSnapshot,
	persist: bool = true
) -> Dictionary:
	if world == null or world.data == null or save == null or candidate == null:
		return failure(&"missing_save", {})
	candidate.world = world.snapshot()
	var validation: Dictionary = Gen2SaveValidator.validate(candidate, world.data)
	if not bool(validation.get("ok", false)):
		restore(world, before)
		return failure(&"candidate_save_invalid", validation)
	if persist:
		var written: Dictionary = Gen2SaveStore.save(candidate, world.data)
		if not bool(written.get("ok", false)):
			restore(world, before)
			return failure(&"save_failed", written)
	copy_into(save, candidate)
	return {"ok": true}


## [method begin] and [method commit] in one call, for a caller whose only change
## is to the world rather than to the save. A null [param save] is a run with no
## save behind it, which succeeds without writing anything.
static func run(
	world: Gen2WorldAPI,
	save: Gen2SaveData,
	before: Gen2WorldSnapshot,
	persist: bool = true
) -> Dictionary:
	if save == null:
		return {"ok": true}
	var opened: Dictionary = begin(world, save)
	if not bool(opened.get("ok", false)):
		restore(world, before)
		return opened
	return commit(world, save, opened["candidate"], before, persist)


## Puts the live world back where [param before] left it. Nothing else is
## unwound: a caller that changed something outside the world state owns that.
static func restore(world: Gen2WorldAPI, before: Gen2WorldSnapshot) -> void:
	if world == null or world.state == null or before == null:
		return
	world.state.restore_from_dict(before.world_state.to_dict())


## The committed candidate over the live save, field by field. The party is
## copied as a new Array of the same members, so a caller holding the old one
## does not see the new party through it.
static func copy_into(target: Gen2SaveData, source: Gen2SaveData) -> void:
	if target == null or source == null:
		return
	target.format_version = source.format_version
	target.game_id = source.game_id
	target.rom_sha1 = source.rom_sha1
	target.slot = source.slot
	target.player_name = source.player_name
	target.party = source.party.duplicate(true)
	target.boxes = source.boxes
	target.world = source.world


static func failure(reason: StringName, details: Dictionary) -> Dictionary:
	return {"ok": false, "reason": reason, "details": details.duplicate(true)}
