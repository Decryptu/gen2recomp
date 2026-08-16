class_name Gen2BoxScreen
extends Control

## Bill's PC, on the hardware's own grid.
##
## [Gen2PCBoxPage] is the picture and `engine/pokemon/bills_pc.asm` is the model:
## `wBillsPC_LoadedBox` picks the party or one box, `CopyBoxmonSpecies` builds
## the list it walks with a CANCEL row on the end, and
## `BillsPC_PressUp`/`Down`/`Left`/`Right` are the cursor, the scroll and the box
## the D-pad changes.
##
## What the source splits between DEPOSIT, WITHDRAW and MOVE WITHOUT MAIL is one
## screen here: A on a party row deposits and A on a box row withdraws, through
## [Gen2SaveStorage]'s atomic transfers. The submenus behind those rows (STATS,
## RELEASE, MOVE) are not built; nothing calls them and the storage boundary is
## what the PC exists for.

signal closed(result: Dictionary)

## The PC is drawn in hardware pixels and the panel it is opened from is ordinary
## UI at window resolution, so the screen carries a [Gen2Screen] of its own, the
## way [Gen2TownMapScreen] does.
const SCREEN_SCENE: PackedScene = preload("res://game/render/gen2_screen.tscn")

## `PCString_ChooseaPKMN` and `.PartyPKMN`. Both are engine strings inside
## `bills_pc.asm` that no script points at, so nothing imports them and they are
## the host's, like the contest judging lines. "PKMN" is the two tiles `<PK>` and
## `<MN>`, which is what [method Gen2Text.encode] makes of it; "#" is the POKé
## ligature and has no tile in either font.
const PROMPT_CHOOSE: String = "Choose a PKMN."
const PARTY_NAME: String = "PARTY PKMN"

## `wBillsPC_LoadedBox`: zero is the party and the boxes follow it.
const LOADED_PARTY: int = 0

var _data: GameData = null
var _data_override: GameData = null
var _save: Gen2SaveData = null
var _save_override: Gen2SaveData = null
var _persist: bool = true
var _embedded: bool = false
var _box_index: int = 0
var _selected_box_slot: int = -1
var _selected_party_index: int = -1
## `wBillsPC_LoadedBox`, `wBillsPC_CursorPosition` and `wBillsPC_ScrollPosition`.
var _loaded: int = LOADED_PARTY
var _cursor: int = 0
var _scroll: int = 0
## The line the bottom box carries, which is `PCString_ChooseaPKMN` until a
## transfer answers.
var _prompt: String = PROMPT_CHOOSE
var _page: Gen2PCBoxPage = null
var _field: Control = null
var _backdrop: ColorRect = null
var _background: TextureRect = null
var _pic: TextureRect = null
var _cursor_sprites: Array[TextureRect] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_data = _data_override if _data_override != null else _resolve_data()
	_save = _save_override if _save_override != null else _resolve_save()
	_page = Gen2PCBoxPage.from_data(_data)
	_build()
	_refresh()
	# Not while embedded in the overworld: the world screen routes buttons here
	# itself, and a focus ring appearing over the map would be the map's.
	if not _embedded:
		Gen2FocusGuard.attach(self)


## Supplies the cache/save context. Embedded overworld use can keep the same
## atomic storage operations in memory while a selected runtime save persists.
func set_context(
	data: GameData, save: Gen2SaveData, persist: bool = true, embedded: bool = false
) -> void:
	_data_override = data
	_save_override = save
	_persist = persist
	_embedded = embedded
	_data = data
	_save = save
	if is_inside_tree():
		if _page == null:
			_page = Gen2PCBoxPage.from_data(_data)
		_refresh()


func box_snapshot() -> Dictionary:
	var boxes: Array = []
	if _save != null:
		for box_index: int in Gen2SaveData.BOX_COUNT:
			var slots: Array = []
			var box: Gen2SaveBox = _save.boxes[box_index] if box_index < _save.boxes.size() else null
			for slot: int in Gen2SaveBox.CAPACITY:
				var mon: Gen2SaveMon = box.slots[slot] if box != null and slot < box.slots.size() else null
				slots.append(_mon_snapshot(box_index, slot, mon))
			boxes.append({"index": box_index, "slots": slots})
	return {
		"box": _box_index,
		"selected_box_slot": _selected_box_slot,
		"selected_party_index": _selected_party_index,
		"loaded": _loaded,
		"cursor": _cursor,
		"scroll": _scroll,
		"prompt": _prompt,
		"boxes": boxes,
	}


func select_box(box_index: int) -> bool:
	if _save == null or box_index < 0 or box_index >= _save.boxes.size():
		return false
	_box_index = box_index
	_selected_box_slot = -1
	if _loaded != LOADED_PARTY:
		_loaded = box_index + 1
	_cursor = 0
	_scroll = 0
	_refresh()
	return true


func select_box_slot(slot: int) -> bool:
	if slot < 0 or slot >= Gen2SaveBox.CAPACITY:
		return false
	_selected_box_slot = slot
	_selected_party_index = -1
	_refresh()
	return true


func select_party_member(index: int) -> bool:
	if _save == null or index < 0 or index >= _save.party.size():
		return false
	_selected_party_index = index
	_selected_box_slot = -1
	_refresh()
	return true


func deposit_selected_party() -> bool:
	if _save == null or _selected_party_index < 0:
		_prompt = "Choose a party PKMN."
		_refresh()
		return false
	var result: Dictionary = Gen2SaveStorage.deposit_party_to_box(
		_save, _data, _selected_party_index, _box_index, -1, _persist
	)
	if not bool(result.get("ok", false)):
		_prompt = String(result.get("message", result.get("reason", "Deposit refused.")))
		_refresh()
		return false
	_prompt = "Stored in BOX %d." % (int(result["box"]) + 1)
	_selected_party_index = -1
	_clamp_cursor()
	_refresh()
	return true


func withdraw_selected_box() -> bool:
	if _save == null or _selected_box_slot < 0:
		_prompt = "Choose a stored PKMN."
		_refresh()
		return false
	var result: Dictionary = Gen2SaveStorage.withdraw_box_to_party(
		_save, _data, _box_index, _selected_box_slot, _persist
	)
	if not bool(result.get("ok", false)):
		_prompt = String(result.get("message", result.get("reason", "Withdrawal refused.")))
		_refresh()
		return false
	_prompt = "Taken out of BOX %d." % (_box_index + 1)
	_selected_box_slot = -1
	_clamp_cursor()
	_refresh()
	return true


## `_StatsScreenDPad` and its siblings: up and down walk the list, left and right
## change the loaded box, A takes the row the cursor stands on and B leaves.
func handle_button(button: int) -> bool:
	match button:
		Gen2Button.UP:
			_press_up()
		Gen2Button.DOWN:
			_press_down()
		Gen2Button.LEFT:
			_press_left()
		Gen2Button.RIGHT:
			_press_right()
		Gen2Button.A:
			_confirm()
		Gen2Button.B:
			_back()
		_:
			return false
	return true


## The list `CopyBoxmonSpecies` builds: every occupied slot of the loaded list,
## then the CANCEL row its `ld a, -1` terminator becomes.
func rows() -> Array:
	var out: Array = []
	for entry: Array in _entries():
		var mon: Gen2SaveMon = entry[1]
		out.append({
			"name": _display_name(mon), "index": int(entry[0]), "cancel": false,
		})
	out.append({"name": Gen2PCBoxPage.CANCEL, "index": -1, "cancel": true})
	return out


func _entries() -> Array:
	var out: Array = []
	if _save == null:
		return out
	if _loaded == LOADED_PARTY:
		for index: int in _save.party.size():
			out.append([index, _save.party[index]])
		return out
	var box: Gen2SaveBox = _save.boxes[_box_index] if _box_index < _save.boxes.size() else null
	if box == null:
		return out
	for slot: int in Gen2SaveBox.CAPACITY:
		if slot < box.slots.size() and box.slots[slot] != null:
			out.append([slot, box.slots[slot]])
	return out


func _resolve_data() -> GameData:
	return Gen2GameRuntime.data_or_any()


func _resolve_save() -> Gen2SaveData:
	return Gen2GameRuntime.selected_save_or_null() if _data != null else null


func _build() -> void:
	var screen: Gen2Screen = SCREEN_SCENE.instantiate() as Gen2Screen
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	_field = Control.new()
	_field.size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	_field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.display(_field)
	## The page is drawn with colour 0 transparent so the pic shows through the
	## cell it is composed into, which leaves the backdrop to fill it.
	_backdrop = ColorRect.new()
	_backdrop.size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field.add_child(_backdrop)
	## The pic sits under the page so the listing's border stays drawn over it,
	## the way the hardware's own window does.
	_pic = _sprite()
	_background = _sprite()
	for _index: int in Gen2PCBoxPage.max_cursor_sprites():
		_cursor_sprites.append(_sprite())


func _sprite() -> TextureRect:
	var node := TextureRect.new()
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field.add_child(node)
	return node


## The cursor's row is the selection whether or not there is anything to draw
## it with: a cache carrying no font still stores and withdraws.
## Drawing only. The selection is [method _sync_selection]'s, so a caller that
## picked a slot by hand keeps it and a cache carrying no font still draws
## nothing without losing one.
func _refresh() -> void:
	var mon: Gen2SaveMon = _selected_mon()
	if _page == null or _background == null:
		return
	var visible_rows: Array = []
	var all_rows: Array = rows()
	for index: int in Gen2PCBoxPage.LIST_HEIGHT:
		var at: int = _scroll + index
		if at < all_rows.size():
			visible_rows.append(all_rows[at])
	var indices: PackedByteArray = _page.draw({
		"box_name": _box_name(),
		"rows": visible_rows,
		"prompt": _prompt,
		"mon": _mon_state(mon),
	})
	var palette: PackedColorArray = _interface_palette()
	if _backdrop != null:
		_backdrop.color = palette[0]
	_background.texture = ImageTexture.create_from_image(Gen2PicImage.from_indices(
		indices, Gen2Screen.WIDTH, Gen2Screen.HEIGHT, palette, true
	))
	_background.size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	_refresh_pic(mon)
	_refresh_cursor(all_rows.size())


## `_CGB_BillsPC`'s background palette, PREDEFPAL_POKEDEX, which the Pokedex
## already imports as its own interface palette.
func _interface_palette() -> PackedColorArray:
	var colors: PackedColorArray = _data.pokedex_palette("interface") if _data != null \
		else PackedColorArray()
	if colors.is_empty():
		return Gen2Palette.pic_palette(PackedColorArray([Color.WHITE, Color.BLACK]))
	return colors


## Which slot the cursor stands on, kept in the two fields the transfers read so
## that walking the list and picking a slot by hand are the same selection.
func _sync_selection() -> void:
	if _selected_mon() == null:
		return
	var entries: Array = _entries()
	var at: int = _cursor + _scroll
	if at < 0 or at >= entries.size():
		return
	if _loaded == LOADED_PARTY:
		_selected_party_index = int(entries[at][0])
		_selected_box_slot = -1
		return
	_selected_box_slot = int(entries[at][0])
	_selected_party_index = -1


func _selected_mon() -> Gen2SaveMon:
	var entries: Array = _entries()
	var at: int = _cursor + _scroll
	if at < 0 or at >= entries.size():
		return null
	return entries[at][1]


## `PCMonInfo`'s own fields. An egg is drawn as its pic and nothing else, which
## is where the source returns.
func _mon_state(mon: Gen2SaveMon) -> Dictionary:
	if mon == null or _data == null:
		return {}
	if mon.is_egg:
		return {}
	return {
		"level": mon.level,
		"gender": _gender_glyph(Gen2BattleMon.gender_for(_data, mon.species, mon.dvs)),
		"species_name": String(_data.species(mon.species).get("name", "")),
		"item": mon.item,
		## `ItemIsMail` reads a list no importer reads, so no item is mail here
		## and the mail marker is unreachable; see HANDOFF.md.
		"mail": false,
	}


func _gender_glyph(gender: StringName) -> String:
	if gender == Gen2BattleMon.GENDER_MALE:
		return "♂"
	if gender == Gen2BattleMon.GENDER_FEMALE:
		return "♀"
	return " "


func _refresh_pic(mon: Gen2SaveMon) -> void:
	if _pic == null:
		return
	_pic.texture = null
	if mon == null or _data == null:
		return
	var pic: Dictionary = _data.species_pic(mon.species)
	if pic.is_empty():
		return
	var image: Image = Gen2PicImage.from_atlas(
		_data.atlas_indices(pic["atlas"]), _data.atlas(pic["atlas"]), pic,
		_data.palette(mon.species)
	)
	_pic.texture = ImageTexture.create_from_image(image)
	_pic.size = Vector2(image.get_size())
	## `_PrepMonFrontpic` places a pic smaller than the seven-tile cell at its
	## bottom, which is what keeps every species standing on the same line.
	var cell: int = Gen2PCBoxPage.pic_size()
	_pic.position = Vector2(Gen2PCBoxPage.pic_position()) + Vector2(
		float(cell - image.get_width()) * 0.5, float(cell - image.get_height())
	)


func _refresh_cursor(row_count: int) -> void:
	var sprites: Array = _page.cursor_sprites(_cursor, row_count)
	var sheet: PackedByteArray = _data.tile_indices("pc_select") if _data != null \
		else PackedByteArray()
	var palette: PackedColorArray = _data.party_menu_icon_palette(0) if _data != null \
		else PackedColorArray()
	for index: int in _cursor_sprites.size():
		var node: TextureRect = _cursor_sprites[index]
		node.visible = index < sprites.size() and not sheet.is_empty() \
			and not palette.is_empty()
		if not node.visible:
			continue
		var sprite: Dictionary = sprites[index]
		node.position = Vector2(sprite["position"])
		node.texture = ImageTexture.create_from_image(_cursor_image(
			sheet, palette, int(sprite["tile"]),
			bool(sprite["flip_x"]), bool(sprite["flip_y"])
		))


## One tile of `PCSelectLZ`, flipped the way its OAM attribute asks. `B_OAM_XFLIP`
## flips the tile where it stands rather than mirroring a square, which is why
## each object is drawn on its own.
func _cursor_image(
	sheet: PackedByteArray, palette: PackedColorArray, tile: int,
	flip_x: bool, flip_y: bool
) -> Image:
	var size: int = Gen2Font.TILE
	var cell := PackedByteArray()
	cell.resize(size * size)
	Gen2Font.blit_slot(
		sheet, RomLayout.PC_SELECT_TILES * size, tile, cell, size, 0, 0
	)
	var image: Image = Gen2PicImage.from_indices(cell, size, size, palette, true)
	if flip_x:
		image.flip_x()
	if flip_y:
		image.flip_y()
	return image


## `BillsPC_BoxName`, which names the party or the loaded box.
func _box_name() -> String:
	if _loaded == LOADED_PARTY:
		return PARTY_NAME
	return "BOX %d" % (_box_index + 1)


func _mon_snapshot(box: int, slot: int, mon: Gen2SaveMon) -> Dictionary:
	if mon == null:
		return {"empty": true, "box": box, "slot": slot}
	return {
		"empty": false, "box": box, "slot": slot,
		"name": _display_name(mon), "species": mon.species, "level": mon.level,
	}


func _display_name(mon: Gen2SaveMon) -> String:
	if mon == null:
		return ""
	if not mon.nickname.is_empty():
		return mon.nickname
	return String(_data.species(mon.species).get("name", "UNKNOWN")) if _data != null \
		else "UNKNOWN"


func _press_up() -> void:
	if _cursor > 0:
		_cursor -= 1
	elif _scroll > 0:
		_scroll -= 1
	else:
		return
	_sync_selection()
	_refresh()


## `BillsPC_PressDown`: the cursor stops one row short of the list's length and
## the scroll takes over at the bottom of the five rows on screen.
func _press_down() -> void:
	var count: int = rows().size()
	if _cursor + _scroll + 1 >= count:
		return
	if _cursor + 1 < Gen2PCBoxPage.LIST_HEIGHT:
		_cursor += 1
	else:
		_scroll += 1
	_sync_selection()
	_refresh()


## `BillsPC_PressLeft`/`Right`, which wrap the party and every box round.
func _press_left() -> void:
	_load(_loaded - 1 if _loaded > LOADED_PARTY else Gen2SaveData.BOX_COUNT)


func _press_right() -> void:
	_load(_loaded + 1 if _loaded < Gen2SaveData.BOX_COUNT else LOADED_PARTY)


func _load(loaded: int) -> void:
	_loaded = loaded
	if _loaded != LOADED_PARTY:
		_box_index = _loaded - 1
	_cursor = 0
	_scroll = 0
	_selected_box_slot = -1
	_selected_party_index = -1
	_prompt = PROMPT_CHOOSE
	_sync_selection()
	_refresh()


## A on the CANCEL row leaves, the way `.Cancel` does; on any other row it is the
## transfer the loaded list implies.
func _confirm() -> void:
	var all_rows: Array = rows()
	var at: int = _cursor + _scroll
	if at < 0 or at >= all_rows.size() or bool((all_rows[at] as Dictionary)["cancel"]):
		_back()
		return
	_sync_selection()
	if _loaded == LOADED_PARTY:
		deposit_selected_party()
		return
	withdraw_selected_box()


## After a transfer the list is one row shorter, so the cursor comes back inside
## it the way `CopyBoxmonSpecies` and the joypad bounds do together.
func _clamp_cursor() -> void:
	var count: int = rows().size()
	while _cursor + _scroll >= count and (_cursor > 0 or _scroll > 0):
		if _scroll > 0:
			_scroll -= 1
		else:
			_cursor -= 1
	_selected_box_slot = -1
	_selected_party_index = -1


func _back() -> void:
	if _embedded:
		close_embedded()
		return
	get_tree().change_scene_to_file.call_deferred("res://game/save/party_screen.tscn")


func close_embedded() -> void:
	if not _embedded:
		return
	closed.emit({"ok": true, "script_value": 0, "changed": false})
