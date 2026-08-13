extends GutTest


func _spend(ring: Gen2WorldPhoneRing, frames: int) -> void:
	for _frame: int in frames:
		ring.advance_frame()


func test_source_ring_has_two_three_wait_cycles() -> void:
	var ring := Gen2WorldPhoneRing.new()
	assert_eq(ring.total_frames(), 120)
	assert_eq(ring.snapshot()["phase"], &"ringing")
	_spend(ring, 20)
	assert_eq(ring.snapshot()["phase"], &"caller_name")
	_spend(ring, 40)
	assert_eq(ring.snapshot()["ring"], 2)
	assert_eq(ring.snapshot()["phase"], &"ringing")
	assert_false(ring.is_finished())
	_spend(ring, 60)
	assert_true(ring.is_finished())
	assert_eq(ring.snapshot()["elapsed_frames"], 120)


func test_special_call_lead_precedes_the_same_two_rings() -> void:
	var ring := Gen2WorldPhoneRing.new(30)
	assert_eq(ring.total_frames(), 150)
	assert_eq(ring.snapshot()["phase"], &"pre_ring")
	_spend(ring, 30)
	assert_eq(ring.snapshot()["phase"], &"ringing")
	assert_eq(ring.snapshot()["ring"], 1)
