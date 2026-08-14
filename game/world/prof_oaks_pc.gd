class_name Gen2ProfOaksPC
extends RefCounted

## `ProfOaksPCBoot` and `Rate` (engine/events/prof_oaks_pc.asm), as the pages a
## screen shows and the effect it plays.
##
## Presentation only: the routine counts `wPokedexSeen` and `wPokedexCaught` and
## writes nothing back. The three pages are the source's own order, and each
## waits for A or B, which is why the sound is on the last of them rather than on
## the whole run.

## `PrintNum` with `PRINTNUM_LEFTALIGN | 1, 3`. Left aligned without leading
## zeros means `.AdvancePointer` does not step past a suppressed digit, so the
## buffer holds the significant digits and nothing else; the `@` fill
## `.UpdateRatingBuffer` laid down terminates it.
const COUNT_DIGITS: int = 3


## The whole boot, as [code]{ seen, caught, sfx, pages }[/code]. Empty for a
## cache imported without the rating table, which is the caller's cue to leave
## the script's own `end` alone.
static func boot(data: GameData, state: Gen2WorldState) -> Dictionary:
	if data == null or data.oak_ratings().is_empty():
		return {}
	var seen: int = state.seen_count() if state != null else 0
	var caught: int = state.caught_count() if state != null else 0
	var rating: Dictionary = rating_for(data, caught)
	return {
		"seen": seen,
		"caught": caught,
		"sfx": int(rating.get("sfx", 0)),
		"pages": [
			data.oak_pc_text("level"),
			counts_text(data, seen, caught),
			String(rating.get("text", "")),
		],
	}


## `FindOakRating`: the first row whose threshold the caught count does not
## exceed. The table's last row is every species, so the walk always lands.
static func rating_for(data: GameData, caught: int) -> Dictionary:
	for row: Variant in data.oak_ratings():
		if caught <= int((row as Dictionary).get("threshold", -1)):
			return row
	return {}


## `_OakPCText3` with `.UpdateRatingBuffers`' two numbers in the `text_ram` slots
## it left for them.
static func counts_text(data: GameData, seen: int, caught: int) -> String:
	var text: String = data.oak_pc_text("counts")
	for value: int in [seen, caught]:
		text = Gen2TextStream.fill_marker(
			text, Gen2TextStream.RAM_MARKER, String.num_int64(value)
		)
	return text
