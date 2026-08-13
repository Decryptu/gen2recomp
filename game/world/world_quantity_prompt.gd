class_name Gen2WorldQuantityPrompt
extends RefCounted

## `BuySellToss_InterpretJoypad` (`engine/items/buy_sell_toss.asm`), the dial
## every source quantity prompt reads its joypad through. It owns
## `wItemQuantity` (the ceiling) and `wItemQuantityChange` (the shown value) and
## nothing else; the caller owns the box the number is drawn in.
##
## `Kurt_SelectQuantity` is the first caller here. `SelectQuantityToToss` and the
## mart's own prompt are the same routine over their own headers, so the pack's
## TOSS needs this model and a box rather than a second dial.

const PAGE_STEP: int = 10

const PENDING: StringName = &"pending"
const CONFIRMED: StringName = &"confirmed"
const CANCELLED: StringName = &"cancelled"

## `wItemQuantity`, the ceiling the caller loaded before opening the box.
var maximum: int = 1
## `wItemQuantityChange`, which every caller opens on 1.
var value: int = 1


static func open(available: int) -> Gen2WorldQuantityPrompt:
	var prompt := Gen2WorldQuantityPrompt.new()
	prompt.maximum = maxi(1, available)
	prompt.value = 1
	return prompt


func press(button: int) -> StringName:
	match button:
		Gen2Button.A:
			return CONFIRMED
		Gen2Button.B:
			return CANCELLED
		Gen2Button.UP:
			_step_up()
		Gen2Button.DOWN:
			_step_down()
		Gen2Button.LEFT:
			_page_down()
		Gen2Button.RIGHT:
			_page_up()
	return PENDING


## `.down` decrements, and the byte reaching zero is what wraps it to the
## ceiling rather than a comparison against 1.
func _step_down() -> void:
	value -= 1
	if value == 0:
		value = maximum


func _step_up() -> void:
	value += 1
	if value > maximum:
		value = 1


func _page_down() -> void:
	value = 1 if value - PAGE_STEP <= 0 else value - PAGE_STEP


func _page_up() -> void:
	value = mini(value + PAGE_STEP, maximum)
