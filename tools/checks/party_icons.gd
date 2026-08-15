extends RefCounted

var _r: RefCounted = null

## Verifies the menu mon icons a party page draws, against freshly imported real
## caches: `MonMenuIcons` (one of the 38 `ICON_*` shapes per species),
## `IconPointers`' art behind it, `HeldItemIcons` and `PartyMenuOBPals`.
##
## The whole corpus rather than a sample: every species on all three cartridges
## resolves to an icon whose eight tiles decode and carry ink. The table is a
## plain byte run, so a wrong offset lands on neighbouring data that still reads
## as numbers; what says it is the right run is that every entry is in range,
## that the first and last species are the shapes the source names, and that the
## three cartridges agree entry for entry.
##
##   Godot --headless --path . -s res://tools/validate.gd -- party_icons

## `constants/icon_constants.asm`, the entries the census names.
const ICON_BULBASAUR: int = 22
const ICON_HUMANSHAPE: int = 14
const ICON_UNOWN: int = 25

## `data/pokemon/menu_icons.asm`'s first and last rows, either side of the run.
const FIRST_SPECIES: int = 1
const LAST_SPECIES: int = 251
const UNOWN: int = 201

var _first_table: PackedByteArray = PackedByteArray()


func run(r: RefCounted) -> void:
	_r = r
	_first_table = PackedByteArray()
	_r.each_game(_check_game)


func _check_game() -> void:
	var table: PackedByteArray = _r.data.mon_menu_icon_table()
	if not _r.check(
		table.size() == LAST_SPECIES,
		"MonMenuIcons holds %d entries, not %d." % [table.size(), LAST_SPECIES]
	):
		return
	_r.check(
		_r.data.mon_menu_icon(FIRST_SPECIES) == ICON_BULBASAUR,
		"BULBASAUR draws icon %d, not ICON_BULBASAUR." % _r.data.mon_menu_icon(FIRST_SPECIES)
	)
	_r.check(
		_r.data.mon_menu_icon(LAST_SPECIES) == ICON_HUMANSHAPE,
		"CELEBI draws icon %d, not ICON_HUMANSHAPE." % _r.data.mon_menu_icon(LAST_SPECIES)
	)
	_r.check(
		_r.data.mon_menu_icon(UNOWN) == ICON_UNOWN,
		"UNOWN draws icon %d, not ICON_UNOWN." % _r.data.mon_menu_icon(UNOWN)
	)
	# A species past the cartridge's own range is what a mod would number, and
	# it has no row rather than a wrong one.
	_r.check(
		_r.data.mon_menu_icon(LAST_SPECIES + 1) == 0,
		"a species past the table answers an icon anyway."
	)
	if _first_table.is_empty():
		_first_table = table
	else:
		_r.check(
			_first_table == table, "MonMenuIcons differs from the other cartridges."
		)

	var used: Dictionary = {}
	for species: int in range(FIRST_SPECIES, LAST_SPECIES + 1):
		used[_r.data.mon_menu_icon(species)] = true
	var lit: int = 0
	for icon: int in range(1, RomLayout.MON_ICON_COUNT + 1):
		var strip: PackedByteArray = _r.data.overworld_icon_indices(icon)
		if not _r.check(
			strip.size() == RomLayout.MON_ICON_TILES * Gen2Tiles.TILE_PIXELS,
			"icon %d decoded %d pixels." % [icon, strip.size()]
		):
			continue
		var drawn: int = 0
		for index: int in strip:
			if index != 0:
				drawn += 1
		_r.check(drawn > 0, "icon %d is blank." % icon)
		lit += drawn
	_r.check(
		used.size() == RomLayout.MON_ICON_COUNT - 1,
		"%d of the %d shapes are used; only ICON_EGG should be spare." % [
			used.size(), RomLayout.MON_ICON_COUNT,
		]
	)

	_check_held_item_icons()
	_check_palette()
	_r.note("party icons: %d species over %d shapes, %d drawn pixels." % [
		LAST_SPECIES, used.size(), lit,
	])


## `HeldItemIcons`, both tiles, though only the item one is ever drawn.
func _check_held_item_icons() -> void:
	var held: PackedByteArray = _r.data.held_item_icon_indices()
	_r.check(
		held.size() == RomLayout.HELD_ITEM_ICON_TILES * Gen2Tiles.TILE_PIXELS,
		"HeldItemIcons decoded %d pixels." % held.size()
	)


## `PartyMenuOBPals`' first palette, the one every icon's OAM set names. Colour
## 0 is the transparent index, so an icon drawn in a palette whose colour 0 is
## not the light one the source ships would lose its outline instead of its
## background.
func _check_palette() -> void:
	var colors: PackedColorArray = _r.data.party_menu_icon_palette()
	if not _r.check(
		colors.size() == Gen2Palette.COLORS_PER_PIC,
		"the icon palette holds %d colours." % colors.size()
	):
		return
	_r.check(colors[3] == Color.BLACK, "the icon palette does not end in black.")
	_r.check(
		colors[0].get_luminance() > colors[2].get_luminance(),
		"the icon palette's transparent colour is darker than its third."
	)
