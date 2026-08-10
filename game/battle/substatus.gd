class_name Gen2Substatus
extends RefCounted

## The volatile flags of battle state, for everything the status byte cannot
## hold.
##
## [Gen2Status] is one status at a time, the cartridge's rule. Confusion,
## flinching, a recharge turn, a two-turn charge, Disable, Attract, Encore, Mist,
## Focus Energy, flying and underground are independent of that and of each
## other, so they live apart from it.
##
## The cartridge keeps these as five bytes (`wPlayerSubStatus1` through
## `wPlayerSubStatus5`); this folds them into one int, since nothing here needs
## to address a byte in isolation.
##
## Some flags need a counter beside them (turns of confusion, the charged move,
## the disabled slot and its duration, Rollout or rampage turns), which
## [Gen2BattleMon] keeps as separate fields next to
## [member Gen2BattleMon.substatus]. This class is pure arithmetic and holds no
## state, the same shape as [Gen2Status].
##
## Every flag clears on a switch, which is what makes it volatile:
## [method Gen2BattleMon.reset_volatile] is the one place that happens, called
## from [method Gen2Party.send_out] beside
## [method Gen2BattleMon.reset_stages].

const CONFUSED: int = 1 << 0
const FLINCHED: int = 1 << 1
const RECHARGING: int = 1 << 2
const CHARGING: int = 1 << 3
## Bit 4 was a DISABLED flag. The cartridge has none: `wDisabledMove` and
## `wPlayerDisableCount` are the whole of it, which is what
## [member Gen2BattleMon.disabled_slot] and [member Gen2BattleMon.disable_turns]
## already are, and every reader tested those rather than the flag. It is left
## unused rather than reassigned so a bit number keeps meaning what it did.
const ATTRACTED: int = 1 << 5
const ENCORED: int = 1 << 6
const MIST: int = 1 << 7
const FOCUS_ENERGY: int = 1 << 8
const FLYING: int = 1 << 9
const UNDERGROUND: int = 1 << 10
const CURLED: int = 1 << 11
const ROLLOUT: int = 1 << 12
const RAMPAGING: int = 1 << 13

## `SUBSTATUS_CANT_RUN`, what Mean Look and Spider Web leave behind. It sits on
## the Pokémon that used the move rather than the one that cannot leave:
## `BattleCommand_ArenaTrap` sets `BATTLE_VARS_SUBSTATUS5`, the user's own, and
## `TryToRunAwayFromBattle` refuses the player by reading `wEnemySubStatus5`.
## The cartridge's name is kept for that reason.
const CANT_RUN: int = 1 << 14

## `SUBSTATUS_X_ACCURACY`, what an X Accuracy leaves on whoever used it: every
## move that Pokémon uses hits, checked in `CheckHit` ahead of the stat
## modifiers and the roll. Nothing clears it but a send-out, and only a trainer's
## AI sets it here, since the player's pack has no X items yet.
const X_ACCURACY: int = 1 << 15

## `SUBSTATUS_PERISH`, `wPlayerSubStatus1` bit 4 on the cartridge and a bit of
## its own here, since bit 4 of this int is the reserved one above. It sits on
## each Pokémon that heard the song, with
## [member Gen2BattleMon.perish_count] beside it.
##
## A switch cures it. `NewBattleMonStatus` and `NewEnemyMonStatus` zero all five
## substatus bytes on a send-out and leave `wPlayerPerishCount` alone, but every
## read of the count is behind the flag, so clearing both in
## [method Gen2BattleMon.reset_volatile] is the same behavior.
const PERISH: int = 1 << 16

## `SUBSTATUS_SUBSTITUTE`, `wPlayerSubStatus4` bit 4. The doll's own hit points
## sit beside it on [member Gen2BattleMon.substitute_hp].
const SUBSTITUTE: int = 1 << 17

## `SUBSTATUS_LEECH_SEED`, `wPlayerSubStatus4` bit 7. It sits on the Pokémon that
## was seeded rather than on the one that seeded it, which is why
## `BattleCommand_ClearHazards` reads the user's own flag.
const LEECH_SEED: int = 1 << 18

## `SUBSTATUS_NIGHTMARE` and `SUBSTATUS_CURSE`, `wPlayerSubStatus1` bits 0 and 1.
## Both cost a quarter at the end of the turn and both sit on the sufferer.
const NIGHTMARE: int = 1 << 19
const CURSE: int = 1 << 20

## `SUBSTATUS_PROTECT` and `SUBSTATUS_ENDURE`, `wPlayerSubStatus1` bits 2 and 5.
## Both sit on the Pokémon that used the move, and neither is spent by the hit it
## answers: `BattleCommand_CheckHit`'s `.Protect` and `BattleCommand_ApplyDamage`
## only read them, so every hit of a multi-hit move is turned away or clamped.
## What ends them is `EndOpponentProtectEndureDestinyBond`, behind the opponent's
## own action (engine/battle/core.asm).
const PROTECT: int = 1 << 21
const ENDURE: int = 1 << 22

## `SUBSTATUS_DESTINY_BOND`, `wPlayerSubStatus5` bit 6. On its user, and read by
## the *opponent's* `BattleCommand_CheckFaint`, which is the only reader.
## `EndUserDestinyBond` clears it in front of its user's own next action, so it
## covers exactly the opponent's next move.
const DESTINY_BOND: int = 1 << 23

const NONE: int = 0

## How many turns a confused Pokémon stays that way, rolled the same shape as
## [constant Gen2Status.MIN_SLEEP] and [constant Gen2Status.MAX_SLEEP]: the
## cartridge rolls the low bits until it gets something in range and the
## counter starts inclusive of both ends.
const MIN_CONFUSION: int = 2
const MAX_CONFUSION: int = 5

## A rampage lasts one or two more turns after the move that starts it. The
## cartridge uses the low bit of a random byte and adds one.
const MIN_RAMPAGE_TURNS: int = 1
const MAX_RAMPAGE_TURNS: int = 2

## When a rampage ends, confusion lasts two or three turns. This is a separate
## roll from ordinary confusion, which can last through five turns.
const MIN_RAMPAGE_CONFUSION: int = 2
const MAX_RAMPAGE_CONFUSION: int = 3

## How many turns Disable lasts, from `BattleCommand_Disable`'s own roll: three
## bits of a random byte, rerolled on zero, plus one. The result is packed
## alongside the disabled slot on the cartridge's own single counter byte; here
## the two live as separate fields on [Gen2BattleMon] instead, since nothing
## else needs the packed form.
const MIN_DISABLE: int = 2
const MAX_DISABLE: int = 8

## How many turns Encore lasts. Unlike Disable's roll, this one does not
## reroll on the low end: two bits of a random byte, plus three.
const MIN_ENCORE: int = 3
const MAX_ENCORE: int = 6

## How long `BattleCommand_TrapTarget` binds a target: `BattleRandom` masked to
## two bits and then incremented three times, so three to six. The landing turn's
## own `HandleWrap` spends one of them without dealing damage, which is why the
## source comments the same roll as two to five turns.
const MIN_TRAP_TURNS: int = 3
const MAX_TRAP_TURNS: int = 6

## What a bound Pokémon loses each turn, `GetSixteenthMaxHP`'s at-least-one
## sixteenth (engine/battle/core.asm).
const TRAP_DIVISOR: int = 16

## `GetEighthMaxHP`, `GetQuarterMaxHP` and `GetHalfMaxHP`: what Leech Seed moves
## across the field, what a Nightmare and a Curse each cost their sufferer, and
## what a Ghost-type Curse cuts off its own user.
const LEECH_SEED_DIVISOR: int = 8
const QUARTER_DIVISOR: int = 4
const HALF_DIVISOR: int = 2

## What `BattleCommand_PerishSong` loads into each side's count. `HandlePerishSong`
## decrements before it prints, so the four counts printed are 3, 2, 1 and 0, and
## the song's own line says three turns.
const PERISH_TURNS: int = 4

## Whether an attracted Pokémon is too smitten to move, out of 256: the
## cartridge's own 128 in 256, a coin flip, rolled fresh every turn it tries to
## move rather than decided once when Attract lands.
const ATTRACT_IMMOBILE_CHANCE: int = 128

## Whether a confused Pokémon hurts itself instead of moving, out of 256: the
## cartridge's own 128 in 256, a coin flip.
const CONFUSION_HURTS_SELF_CHANCE: int = 128
const CHANCE_RANGE: int = 256


static func has(substatus: int, flag: int) -> bool:
	return (substatus & flag) != 0


## How long a newly confused Pokémon stays that way.
static func roll_confusion(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(MIN_CONFUSION, MAX_CONFUSION)


## How many more turns a newly started rampage lasts.
static func roll_rampage_turns(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(MIN_RAMPAGE_TURNS, MAX_RAMPAGE_TURNS)


## How long confusion lasts when a rampage ends.
static func roll_rampage_confusion(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(MIN_RAMPAGE_CONFUSION, MAX_RAMPAGE_CONFUSION)


## Whether a confused Pokémon hurts itself this turn instead of moving.
static func rolls_confusion_hit(rng: RandomNumberGenerator) -> bool:
	return rng.randi_range(0, CHANCE_RANGE - 1) < CONFUSION_HURTS_SELF_CHANCE


## How long a newly disabled move stays that way. The cartridge rolls three
## bits of a random byte and rerolls a zero, so the roll itself only ever
## produces 1 through 7; the constant one added afterward is folded in here
## rather than left for a caller to remember.
static func roll_disable(rng: RandomNumberGenerator) -> int:
	var roll: int = 0
	while roll == 0:
		roll = rng.randi_range(0, 7)
	return roll + 1


## How long a newly encored move stays that way.
static func roll_encore(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(0, 3) + MIN_ENCORE


## Whether an attracted Pokémon is too smitten to move this turn.
static func rolls_attract_immobile(rng: RandomNumberGenerator) -> bool:
	return rng.randi_range(0, CHANCE_RANGE - 1) < ATTRACT_IMMOBILE_CHANCE


## How long a newly bound Pokémon stays bound.
static func roll_trap_turns(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(MIN_TRAP_TURNS, MAX_TRAP_TURNS)


## What one turn of being bound costs.
static func trap_damage(max_hp: int) -> int:
	@warning_ignore("integer_division")
	return maxi(max_hp / TRAP_DIVISOR, 1)


static func leech_seed_damage(max_hp: int) -> int:
	@warning_ignore("integer_division")
	return maxi(max_hp / LEECH_SEED_DIVISOR, 1)


static func quarter_damage(max_hp: int) -> int:
	@warning_ignore("integer_division")
	return maxi(max_hp / QUARTER_DIVISOR, 1)


static func half_damage(max_hp: int) -> int:
	@warning_ignore("integer_division")
	return maxi(max_hp / HALF_DIVISOR, 1)


## Not [method quarter_damage]: `BattleCommand_Substitute` shifts the maximum
## right twice by hand and stores the low byte, with no `GetQuarterMaxHP` and so
## no floor at one, which is why a maximum under four makes a doll with no hit
## points at all rather than a one-point one.
static func substitute_hp_for(max_hp: int) -> int:
	return (max_hp >> 2) & 0xFF
