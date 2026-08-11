class_name Gen2PlayerNameChoices
extends RefCounted

## `data/player_names.asm`'s five-row `ShowPlayerNamingChoices` menu.

const NEW_NAME: String = "NEW NAME"


static func options(data: GameData, gender: int) -> Array[String]:
	if Gen2WorldState.is_crystal_profile(data):
		if gender == Gen2SaveData.GENDER_FEMALE:
			return [NEW_NAME, "KRIS", "AMANDA", "JUANA", "JODI"]
		return [NEW_NAME, "CHRIS", "MAT", "ALLAN", "JON"]
	if data != null and data.id == &"silver":
		return [NEW_NAME, "SILVER", "KAMON", "OSCAR", "MAX"]
	return [NEW_NAME, "GOLD", "HIRO", "TAYLOR", "KARL"]
