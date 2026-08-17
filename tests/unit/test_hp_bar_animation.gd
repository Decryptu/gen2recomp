extends GutTest

## engine/battle/anim_hp_bar.asm, as the bar's own walk.


func _settle(animation: Gen2HpBarAnimation, limit: int = 4000) -> int:
	var frames: int = 0
	while not animation.finished() and frames < limit:
		animation.advance_frame()
		frames += 1
	return frames


## `HPBarAnim_BGMapUpdate` waits two frames per redraw, and a redraw is one
## pixel, so a full bar takes twice its own width in frames.
func test_the_bar_moves_one_pixel_every_two_frames() -> void:
	var animation: Gen2HpBarAnimation = Gen2HpBarAnimation.create(48, 0, 48)
	assert_eq(animation.pixels(), Gen2HpBarAnimation.LENGTH_PX)
	assert_false(animation.advance_frame(), "the first frame of the pair draws nothing")
	assert_true(animation.advance_frame())
	assert_eq(animation.pixels(), Gen2HpBarAnimation.LENGTH_PX - 1)


func test_a_full_drain_takes_two_frames_per_pixel() -> void:
	var animation: Gen2HpBarAnimation = Gen2HpBarAnimation.create(48, 0, 48)
	assert_eq(
		_settle(animation),
		Gen2HpBarAnimation.LENGTH_PX * Gen2HpBarAnimation.FRAMES_PER_STEP
	)
	assert_eq(animation.pixels(), 0)


## A bar that is not moving never ticks, which is what lets the screen treat
## "no animation" and "arrived" as the same thing.
func test_a_bar_already_where_it_is_going_is_finished() -> void:
	var animation: Gen2HpBarAnimation = Gen2HpBarAnimation.create(20, 20, 20)
	assert_true(animation.finished())
	assert_false(animation.advance_frame())


## Healing walks the other way.
func test_the_bar_fills_as_well_as_drains() -> void:
	var animation: Gen2HpBarAnimation = Gen2HpBarAnimation.create(0, 100, 100)
	assert_eq(animation.pixels(), 0)
	_settle(animation)
	assert_eq(animation.pixels(), Gen2HpBarAnimation.LENGTH_PX)
	assert_eq(animation.hp(), 100)


## `ComputeHPBarPixels` keeps a surviving Pokemon on at least one pixel, so a
## drain to a single HP stops one pixel short of empty.
func test_a_survivor_keeps_a_pixel() -> void:
	var animation: Gen2HpBarAnimation = Gen2HpBarAnimation.create(200, 1, 200)
	_settle(animation)
	assert_eq(animation.pixels(), 1)
	assert_eq(animation.hp(), 1, "and the number is the real one once it arrives")


func test_a_faint_empties_the_bar() -> void:
	var animation: Gen2HpBarAnimation = Gen2HpBarAnimation.create(200, 0, 200)
	_settle(animation)
	assert_eq(animation.pixels(), 0)
	assert_eq(animation.hp(), 0)


## The number beside the bar counts down with it rather than jumping.
func test_the_printed_hp_follows_the_bar_down() -> void:
	var animation: Gen2HpBarAnimation = Gen2HpBarAnimation.create(100, 0, 100)
	var seen: Array = []
	while not animation.finished():
		animation.advance_frame()
		seen.append(animation.hp())
	assert_gt(seen.size(), 2, "a hundred HP over 48 pixels is a real walk")
	for index: int in range(1, seen.size()):
		assert_true(int(seen[index]) <= int(seen[index - 1]), "the number never goes back up")
	assert_eq(int(seen[-1]), 0)


## The two source branches are keyed on whether the maximum reaches the bar's
## own width; both redraw one pixel at a time, so both take the same walk.
func test_a_small_maximum_still_walks_pixel_by_pixel() -> void:
	var animation: Gen2HpBarAnimation = Gen2HpBarAnimation.create(20, 0, 20)
	assert_eq(animation.pixels(), Gen2HpBarAnimation.LENGTH_PX)
	assert_eq(
		_settle(animation),
		Gen2HpBarAnimation.LENGTH_PX * Gen2HpBarAnimation.FRAMES_PER_STEP
	)


## `ShortHPBar_CalcPixelFrame` is what prints the number under a 48-pixel
## maximum, and it rounds up: 20 HP over 48 pixels has no exact HP per pixel, so
## every pixel but the ends is a fraction the routine rounds rather than floors.
func test_a_small_maximum_prints_the_short_branchs_own_number() -> void:
	var animation: Gen2HpBarAnimation = Gen2HpBarAnimation.create(20, 0, 20)
	var seen: Array = []
	while not animation.finished():
		animation.advance_frame()
		seen.append(animation.hp())
	assert_eq(int(seen[0]), 20, "the first step is still the HP it started from")
	assert_eq(int(seen[-1]), 0)
	for index: int in range(1, seen.size()):
		assert_true(int(seen[index]) <= int(seen[index - 1]), "the number never goes back up")


## The routine's loop subtracts before it tests, so a product that lands exactly
## on a multiple of the bar's width is counted and then rounded up again: one HP
## too many, which pret's fix removes by stopping on the zero. 24 of 48 pixels of
## a 12 HP maximum is such a product (12 * 24 = 288 = 6 * 48).
func test_the_short_bar_off_by_one_is_switchable_at_an_exact_multiple() -> void:
	var corrected: Gen2HpBarAnimation = Gen2HpBarAnimation.create(12, 0, 12)
	var buggy: Gen2HpBarAnimation = Gen2HpBarAnimation.create(12, 0, 12)
	var rules := Gen2Rules.new()

	while corrected.pixels() > Gen2HpBarAnimation.LENGTH_PX / 2:
		corrected.advance_frame()
		buggy.advance_frame()
	assert_eq(corrected.pixels(), Gen2HpBarAnimation.LENGTH_PX / 2)

	Gen2Rules.install(null)
	assert_eq(corrected.hp(), 6, "the quotient itself")
	rules.set_flag(&"short_hp_bar_number_off_by_one", true)
	Gen2Rules.install(rules)
	assert_eq(buggy.hp(), 7, "and one HP more on hardware")
	Gen2Rules.install(null)


## `wCurHPAnimLowHP`/`wCurHPAnimHighHP`: the routine clamps its answer to the two
## ends of the animation, which is why the extra HP is invisible on most drains.
func test_the_short_bar_number_stays_inside_the_two_ends() -> void:
	var animation: Gen2HpBarAnimation = Gen2HpBarAnimation.create(10, 8, 20)
	while not animation.finished():
		animation.advance_frame()
		assert_true(animation.hp() >= 8 and animation.hp() <= 10, str(animation.hp()))
