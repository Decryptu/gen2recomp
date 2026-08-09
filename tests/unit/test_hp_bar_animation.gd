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
