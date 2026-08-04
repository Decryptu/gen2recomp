extends Node

## Runtime selection shared by the launcher and screens opened from it.
##
## This stores only identifiers. Cartridge bytes, decoded data and save data
## remain owned by their existing layers and are opened when a screen needs
## them.

var selected_game_id: StringName = &""
var selected_save_slot: int = -1


func select_game(game_id: StringName) -> bool:
	if RomRegistry.sha1_for(game_id).is_empty():
		return false
	if selected_game_id != game_id:
		selected_save_slot = -1
	selected_game_id = game_id
	return true


func has_selected_game() -> bool:
	return not selected_game_id.is_empty()


func selected_data() -> GameData:
	if not has_selected_game():
		return null
	return GameData.open(selected_game_id)


func select_save_slot(game_id: StringName, slot: int) -> bool:
	if slot < 0 or slot >= Gen2SaveStore.SLOT_COUNT:
		return false
	if not select_game(game_id):
		return false
	selected_save_slot = slot
	return true


func has_selected_save_slot() -> bool:
	return has_selected_game() and selected_save_slot >= 0


func selected_save() -> Gen2SaveData:
	if not has_selected_save_slot():
		return null
	var data: GameData = selected_data()
	if data == null:
		return null
	var result: Dictionary = Gen2SaveStore.load_result(
		data.id, data.sha1, selected_save_slot, data
	)
	return result["save"] if result["ok"] else null
