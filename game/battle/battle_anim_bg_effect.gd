class_name Gen2BattleAnimBgEffect
extends RefCounted

## One `battle_bg_effect` (macros/ram.asm): the four bytes a `wActiveBGEffects`
## slot holds.
##
## `id` is `BG_EFFECT_STRUCT_FUNCTION`, and zero is what frees the slot, the way
## a zero index frees an animation object. It stays the cartridge's own effect
## number and is never normalised across the profiles: pokegold has no
## `BATTLE_BG_EFFECT_BODY_SLAM` and its list runs one lower from $25 on, so the
## same byte names a different effect in the two games.

var id: int = 0
var jumptable_index: int = 0
## `BG_EFFECT_STRUCT_BATTLE_TURN`, which starts as `BG_EFFECT_TARGET` or
## `BG_EFFECT_USER` and is then reused as working state by most effects.
var battle_turn: int = 0
var param: int = 0


static func create(effect_id: int, jumptable: int, turn: int, parameter: int
) -> Gen2BattleAnimBgEffect:
	var out := Gen2BattleAnimBgEffect.new()
	out.id = effect_id & 0xFF
	out.jumptable_index = jumptable & 0xFF
	out.battle_turn = turn & 0xFF
	out.param = parameter & 0xFF
	return out


## `EndBattleBGEffect`: zeroing the effect_id is what frees the slot.
func end() -> void:
	id = 0


func active() -> bool:
	return id != 0
