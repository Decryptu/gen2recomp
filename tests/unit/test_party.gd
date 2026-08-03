extends GutTest

## A party: what is in it, who is out, and what a switch is allowed to do.
##
## No battle here. A party is a list and a cursor, and the rules about which of
## its members can be sent out are worth pinning down on their own, because
## everything above them assumes a party never puts a fainted Pokémon on the
## field.

const Fixture := preload("res://tests/unit/battle_fixture.gd")

var _directory: String = ""
var _data: GameData = null


func before_each() -> void:
	_directory = RomCache.directory_for(&"partytest", "0123456789abcdef")
	_data = Fixture.build(_directory)


func after_each() -> void:
	RomCache.clear(_directory)


func _mon(species: int = Fixture.PIKACHU) -> Gen2BattleMon:
	return Gen2BattleMon.create(_data, species, 20, [Fixture.TACKLE])


func _party(count: int) -> Gen2Party:
	var members: Array = []
	for _index: int in count:
		members.append(_mon())
	return Gen2Party.create(members)


func test_a_party_leads_with_its_first_member() -> void:
	var party: Gen2Party = _party(3)
	assert_eq(party.size(), 3)
	assert_eq(party.active, 0)
	assert_eq(party.active_mon(), party.at(0))


func test_a_wild_encounter_is_a_party_of_one() -> void:
	var party: Gen2Party = Gen2Party.of(_mon())
	assert_eq(party.size(), 1)
	assert_false(party.is_wiped())


func test_a_party_that_is_empty_or_too_big_is_refused() -> void:
	assert_null(Gen2Party.create([]))
	assert_null(Gen2Party.create([_mon(), null]))
	var too_many: Array = []
	for _index: int in Gen2Party.MAX_SIZE + 1:
		too_many.append(_mon())
	assert_null(Gen2Party.create(too_many))


func test_a_party_is_wiped_only_when_every_one_of_them_is_down() -> void:
	var party: Gen2Party = _party(2)
	party.at(0).take_damage(party.at(0).max_hp())
	assert_true(party.at(0).is_fainted())
	assert_false(party.is_wiped(), "one down is a replacement, not a defeat")
	assert_eq(party.healthy_count(), 1)

	party.at(1).take_damage(party.at(1).max_hp())
	assert_true(party.is_wiped())
	assert_eq(party.healthy_count(), 0)


func test_a_fainted_member_cannot_be_sent_out() -> void:
	var party: Gen2Party = _party(2)
	party.at(1).take_damage(party.at(1).max_hp())
	assert_false(party.can_send_out(1))
	assert_false(party.send_out(1))
	assert_eq(party.active, 0)


func test_the_one_already_out_cannot_be_sent_out_again() -> void:
	var party: Gen2Party = _party(2)
	assert_false(party.can_send_out(0))
	assert_false(party.send_out(0))


func test_a_position_that_is_not_there_is_refused() -> void:
	var party: Gen2Party = _party(2)
	assert_null(party.at(9))
	assert_false(party.send_out(9))
	assert_false(party.send_out(-1))


func test_the_first_healthy_member_is_what_a_caller_with_no_opinion_gets() -> void:
	var party: Gen2Party = _party(3)
	party.at(0).take_damage(party.at(0).max_hp())
	assert_eq(party.first_healthy(), 1)

	party.at(1).take_damage(party.at(1).max_hp())
	party.at(2).take_damage(party.at(2).max_hp())
	assert_eq(party.first_healthy(), -1)


func test_a_pokemon_called_back_keeps_its_health_and_loses_its_stages() -> void:
	# The cartridge's rule, and the reason a stage is reset rather than a Pokémon
	# rebuilt: health and PP are the Pokémon, a stage is only a lens on a stat.
	var party: Gen2Party = _party(2)
	var leaving: Gen2BattleMon = party.at(0)
	leaving.take_damage(3)
	leaving.stages["attack"] = 2
	var hurt: int = leaving.hp

	assert_true(party.send_out(1))
	assert_eq(party.active, 1)
	assert_eq(leaving.hp, hurt, "it comes back as hurt as it left")
	assert_eq(int(leaving.stages["attack"]), 0)
