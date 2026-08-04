extends Node

## Runtime selection shared by the launcher and screens opened from it.
##
## This stores only a registry ID. Cartridge bytes, decoded data and save data
## remain owned by their existing layers and are opened when a screen needs
## them.

var selected_game_id: StringName = &""


func select_game(game_id: StringName) -> bool:
	if RomRegistry.sha1_for(game_id).is_empty():
		return false
	selected_game_id = game_id
	return true


func has_selected_game() -> bool:
	return not selected_game_id.is_empty()


func selected_data() -> GameData:
	if not has_selected_game():
		return null
	return GameData.open(selected_game_id)
