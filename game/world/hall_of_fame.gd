class_name Gen2HallOfFame
extends RefCounted

## The induction sequence `halloffame` asks for, as pages a screen can draw.
##
## `engine/events/halloffame.asm`'s AnimateHallOfFame walks the party built by
## GetHallOfFameParty, showing one panel per Pokémon and then the player's own,
## so the order and the contents here are that routine's, not a choice.
## `HOF_AnimatePlayerPic` ends on `farcall ProfOaksPCRating`, whose two texts
## print into the empty box that panel opens under itself, so the player's panel
## is answered once per box rather than once.
##
## What this does not carry is what the project has no source for. The panel's
## `<ID>№/` line needs the mon's OT ID, which the save does keep; the player's
## panel additionally wants the trainer ID and PLAY TIME, which the save model
## has neither of, so those lines are absent rather than drawn as zeros.

## GetHallOfFameParty's own cap: it copies at most a full party and stops on the
## -1 terminator.
const MAX_MONS: int = 6

const PAGE_MON: StringName = &"mon"
const PAGE_PLAYER: StringName = &"player"


## The pages, in AnimateHallOfFame's order: every non-egg party member, then the
## player. An empty or egg-only party still answers the player's page, matching
## LoadHOFTeam's carry falling straight through to HOF_AnimatePlayerPic.
##
## [param state] is what `Rate` counts; without it, or without the rating table,
## the player's page is the bare panel the source never stops on.
static func pages(
	data: GameData, save: Gen2SaveData, state: Gen2WorldState = null
) -> Array:
	var out: Array = []
	if data == null or save == null:
		return out
	for mon: Gen2SaveMon in save.party:
		if out.size() >= MAX_MONS:
			break
		## GetHallOfFameParty skips EGG without consuming a slot, so an egg is
		## not inducted and does not shorten the list either.
		if mon.is_egg:
			continue
		out.append(_mon_page(data, mon))
	out.append_array(_player_pages(data, save, state))
	return out


## `HOF_AnimatePlayerPic`'s panel, once per box `ProfOaksPCRating` prints into
## it: both its texts run past two lines, and `PrintText` waits at each break the
## way it does anywhere else. The last box carries the sound the rating picked,
## which is where `PlayMusic MUSIC_NONE` and `PlaySFX` both sit.
static func _player_pages(
	data: GameData, save: Gen2SaveData, state: Gen2WorldState
) -> Array:
	var panel: Dictionary = {"kind": PAGE_PLAYER, "player_name": save.player_name}
	var rating: Dictionary = Gen2ProfOaksPC.rate(data, state)
	if rating.is_empty():
		return [panel]
	var boxes: Array = []
	for text: Variant in rating["pages"] as Array:
		boxes.append_array(Gen2TextLayout.lay_out(
			String(text), Gen2HallOfFamePage.TEXT_COLUMNS, Gen2HallOfFamePage.TEXT_ROWS
		))
	var out: Array = []
	for index: int in boxes.size():
		var page: Dictionary = panel.duplicate()
		page["lines"] = Array(boxes[index] as PackedStringArray)
		if index == boxes.size() - 1:
			page["sfx"] = int(rating["sfx"])
		out.append(page)
	return out


static func _mon_page(data: GameData, mon: Gen2SaveMon) -> Dictionary:
	var species_name: String = String(data.species(mon.species).get("name", ""))
	## DisplayHOFMon prints the species name from GetBasePokemonName and the
	## nickname separately, so a mon that was never renamed shows the same word
	## twice. That is the cartridge's own panel, not a bug to collapse.
	var nickname: String = mon.nickname if not mon.nickname.is_empty() else species_name
	return {
		"kind": PAGE_MON,
		"species": mon.species,
		## Gen 2 species numbers are dex numbers, which is why DisplayHOFMon
		## prints wCurPartySpecies straight into the №. field.
		"dex_number": mon.species,
		"species_name": species_name,
		"nickname": nickname,
		"level": mon.level,
		"ot_id": mon.ot_id,
		"gender": Gen2BattleMon.gender_for(data, mon.species, mon.dvs),
	}
