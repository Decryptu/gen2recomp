class_name Gen2OakSpeech
extends RefCounted

## `engine/menus/intro_menu.asm`'s OakSpeech as a list of beats.
##
## The routine is a straight run of pic-then-text pairs with one branch in it,
## `NamePlayer`, so the model is the sequence and nothing else: no timing, no
## palette rotation and no cry, which are the screen's or a boundary.
##
## Scene-free, so the order can be checked without drawing it.

## What a beat shows above its text.
enum Pic {
	## `Intro_PrepTrainerPic` with wTrainerClass POKEMON_PROF.
	OAK,
	## `PrepMonFrontpic` with zeroed DVs, on whichever species the profile
	## shows: see [method intro_species].
	MON,
	## `DrawIntroPlayerPic`: CAL's trainer pic in Gold and Silver, and the
	## uncompressed ChrisPic or KrisPic in Crystal.
	PLAYER,
}

## `constants/trainer_constants.asm`: POKEMON_PROF is class $0a, and its pic is
## in the same table every other trainer class's is.
const POKEMON_PROF: int = 0x0A
## The one species the speech shows, and it is not the same on both pins:
## `OakSpeech` is `ld a, MARILL` in pokegold and `ld a, WOOPER` in
## pokecrystal (`engine/menus/intro_menu.asm`). Numbers from
## `constants/pokemon_constants.asm`.
const MARILL: int = 183
const WOOPER: int = 194

## Where `NamePlayer` sits: after `_OakText6` and before `_OakText7`. The source
## reaches `ShowPlayerNamingChoices` first and only its NEW NAME row reaches
## `NamingScreen`.
const NAME_AFTER: String = "oak_6"

## `constants/music_constants.asm`: MUSIC_ROUTE_30.
const MUSIC_ROUTE_30: int = 0x2B

## `.PlayerNameString`, which the naming screen prints above its entry.
const NAME_PROMPT: String = "YOUR NAME?"

## `home/string.asm`'s InitName: an empty or all-spaces entry is replaced by the
## gendered default rather than kept, so a save never carries a blank trainer.
const DEFAULT_MALE: String = "CHRIS"
const DEFAULT_FEMALE: String = "KRIS"


## The beats in source order, each `{"pic": Pic, "text": String}`. `_OakText2`
## and `_OakText4` are two `PrintText` calls with one pic between them, so they
## are two beats on the same picture; `_OakText3` is a bare promptbutton and
## carries no words, so it is not one.
static func beats(data: GameData) -> Array:
	if data == null:
		return []
	var order: Array = [
		[Pic.OAK, "oak_1"],
		[Pic.MON, "oak_2"],
		[Pic.MON, "oak_4"],
		[Pic.OAK, "oak_5"],
		[Pic.PLAYER, "oak_6"],
		[Pic.PLAYER, "oak_7"],
	]
	var out: Array = []
	for row: Array in order:
		var key: String = String(row[1])
		var text: String = data.intro_text(key)
		if text == "":
			return []
		out.append({"pic": int(row[0]), "text": text, "key": key})
	return out


## `InitName`'s substitution, which is what makes the naming screen's END
## reachable with nothing typed: a blank entry becomes CHRIS or KRIS.
static func resolve_name(entered: String, gender: int) -> String:
	if entered.strip_edges() != "":
		return entered
	return DEFAULT_FEMALE if gender == Gen2SaveData.GENDER_FEMALE else DEFAULT_MALE


## `_OakText7` opens on `<PLAYER>`, which the text codec leaves as a marker
## because only the caller knows the name. This is that caller.
static func with_player_name(text: String, player_name: String) -> String:
	return text.replace("<PLAYER>", player_name)


## Which species `OakSpeech` puts on the two middle beats. Gold and Silver show
## a Marill where Crystal shows a Wooper.
static func intro_species(data: GameData) -> int:
	return WOOPER if Gen2WorldState.is_crystal_profile(data) else MARILL
