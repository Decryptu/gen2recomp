class_name Gen2OakSpeech
extends RefCounted

## `engine/menus/intro_menu.asm`'s OakSpeech as a list of beats: a run of
## pic-then-text pairs with one branch, `NamePlayer`. Timing, palette rotation
## and the cry belong to the screen, so this stays scene-free and checkable.

## What a beat shows above its text.
enum Pic {
	## `Intro_PrepTrainerPic` with wTrainerClass POKEMON_PROF.
	OAK,
	## `PrepMonFrontpic`, zeroed DVs, on [method intro_species].
	MON,
	## `DrawIntroPlayerPic`: CAL in Gold and Silver, ChrisPic or KrisPic here.
	PLAYER,
}

## How a beat's picture arrives, between `GetSGBLayout` and the `PrintText`.
enum Enter {
	## The beat keeps the picture the one before it drew.
	NONE,
	## `Intro_RotatePalettesLeftFrontpic`, the trainer pics' six-step fade.
	FRONTPIC,
	## `Intro_WipeInFrontpic`, which the species beat uses instead.
	WIPE,
}

## `constants/trainer_constants.asm`. CAL is the class Gold and Silver draw the
## player with, since they ship no ChrisPic.
const POKEMON_PROF: int = 0x0A
const CAL: int = 0x0C
## `OakSpeech` is `ld a, MARILL` in pokegold and `ld a, WOOPER` in pokecrystal.
const MARILL: int = 183
const WOOPER: int = 194

## Where `NamePlayer` sits. Only `ShowPlayerNamingChoices`' NEW NAME row reaches
## `NamingScreen`.
const NAME_AFTER: String = "oak_6"

## `constants/music_constants.asm`: MUSIC_ROUTE_30.
const MUSIC_ROUTE_30: int = 0x2B

## `ShrinkPlayer`, which `InitializeWorld` runs on the screen the speech left
## standing. SFX_ESCAPE_ROPE, then `ld a, 32` into wMusicFade on MUSIC_NONE.
const SHRINK_SFX: int = 0x10
const SHRINK_FADE_FRAMES: int = 32
## Its five `DelayFrames` operands: before the first shrink picture, between the
## two, before the box is cleared, before the sprite is placed, and while it
## stands there.
const SHRINK_WAITS: Array[int] = [8, 8, 8, 3, 50]
## `hlcoord 6, 5`, a row below `ShrinkFrame`'s (6,4), so `ClearBox` leaves the
## pictures' top tile row behind; both are blank there.
const SHRINK_CLEAR_AT: Vector2i = Vector2i(6, 5)
## `Intro_PlacePlayerSprite`'s four `dbsprite` entries are one 16x16 icon at
## y `9 * 8 + 4`, x `9 * 8`; hardware OAM counts from (-8, -16).
const SHRINK_SPRITE_AT: Vector2i = Vector2i(64, 60)

## `.PlayerNameString`, printed above the naming screen's entry.
const NAME_PROMPT: String = "YOUR NAME?"

## `home/string.asm`'s InitName replaces a blank entry with the gendered
## default, so a save never carries a blank trainer.
const DEFAULT_MALE: String = "CHRIS"
const DEFAULT_FEMALE: String = "KRIS"


## The beats in source order, each `{ pic, text, key, enter, clears_after }`.
##
## `_OakText2` and `_OakText4` are two `PrintText` calls over one pic, so they
## are two beats; `_OakText3` is a bare promptbutton and is not one.
## `clears_after` is the `RotateThreePalettesRight` and `ClearTilemap` behind a
## beat's text, which `_OakText4`'s neighbour and `_OakText6` do not have.
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
## reachable with nothing typed.
static func resolve_name(entered: String, gender: int) -> String:
	if entered.strip_edges() != "":
		return entered
	return DEFAULT_FEMALE if gender == Gen2SaveData.GENDER_FEMALE else DEFAULT_MALE


## `_OakText7` opens on `<PLAYER>`, which the text codec leaves as a marker
## because only the caller knows the name.
static func with_player_name(text: String, player_name: String) -> String:
	return text.replace("<PLAYER>", player_name)


## Which species `OakSpeech` puts on the two middle beats.
static func intro_species(data: GameData) -> int:
	return WOOPER if Gen2WorldState.is_crystal_profile(data) else MARILL
