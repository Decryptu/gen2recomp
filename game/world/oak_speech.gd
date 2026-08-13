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

## How a beat's picture arrives, which is the call between `GetSGBLayout` and
## the `PrintText` over it.
enum Enter {
	## The beat keeps the picture the one before it drew.
	NONE,
	## `Intro_RotatePalettesLeftFrontpic`, the six-step fade the three trainer
	## pics come in on.
	FRONTPIC,
	## `Intro_WipeInFrontpic`, which the species beat uses instead.
	WIPE,
}

## `constants/trainer_constants.asm`: POKEMON_PROF is class $0a, and its pic is
## in the same table every other trainer class's is. CAL is $0c, the class Gold
## and Silver draw the player with, since they ship no ChrisPic.
const POKEMON_PROF: int = 0x0A
const CAL: int = 0x0C
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

## `ShrinkPlayer`, which `InitializeWorld` calls the moment `OakSpeech` returns,
## on the screen the speech left standing. `constants/sfx_constants.asm`:
## SFX_ESCAPE_ROPE.
const SHRINK_SFX: int = 0x10
## `ld a, 32` into wMusicFade, on MUSIC_NONE.
const SHRINK_FADE_FRAMES: int = 32
## Its five `DelayFrames` operands, in order: before the first shrink picture,
## between the two, before the box is cleared, before the sprite is placed, and
## while the sprite stands there.
const SHRINK_WAITS: Array[int] = [8, 8, 8, 3, 50]
## `hlcoord 6, 5`, one row below the pictures `ShrinkFrame` places at (6,4), so
## the box `ClearBox` empties leaves their top tile row behind. Both shrink
## pictures are blank there, so nothing of it shows.
const SHRINK_CLEAR_AT: Vector2i = Vector2i(6, 5)
## `Intro_PlacePlayerSprite`'s four `dbsprite` entries are one 16x16 icon whose
## first OAM slot is y `9 * 8 + 4`, x `9 * 8`. Hardware OAM counts from
## (-8, -16), so the icon's top-left pixel is (72 - 8, 76 - 16).
const SHRINK_SPRITE_AT: Vector2i = Vector2i(64, 60)

## `.PlayerNameString`, which the naming screen prints above its entry.
const NAME_PROMPT: String = "YOUR NAME?"

## `home/string.asm`'s InitName: an empty or all-spaces entry is replaced by the
## gendered default rather than kept, so a save never carries a blank trainer.
const DEFAULT_MALE: String = "CHRIS"
const DEFAULT_FEMALE: String = "KRIS"


## The beats in source order, each `{ pic, text, key, enter, clears_after }`.
##
## `_OakText2` and `_OakText4` are two `PrintText` calls with one pic between
## them, so they are two beats on the same picture; `_OakText3` is a bare
## promptbutton and carries no words, so it is not one.
##
## `clears_after` is the `RotateThreePalettesRight` and `ClearTilemap` that
## follow a beat's text. The two beats without it are `_OakText4`'s neighbour,
## which keeps its picture, and `_OakText6`, which runs straight into
## `NamePlayer`.
static func beats(data: GameData) -> Array:
	if data == null:
		return []
	var order: Array = [
		[Pic.OAK, "oak_1", Enter.FRONTPIC, true],
		[Pic.MON, "oak_2", Enter.WIPE, false],
		[Pic.MON, "oak_4", Enter.NONE, true],
		[Pic.OAK, "oak_5", Enter.FRONTPIC, true],
		[Pic.PLAYER, "oak_6", Enter.FRONTPIC, false],
		[Pic.PLAYER, "oak_7", Enter.NONE, false],
	]
	var out: Array = []
	for row: Array in order:
		var key: String = String(row[1])
		var text: String = data.intro_text(key)
		if text == "":
			return []
		out.append({
			"pic": int(row[0]),
			"text": text,
			"key": key,
			"enter": int(row[2]),
			"clears_after": bool(row[3]),
		})
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
