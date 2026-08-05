extends GutTest


func test_source_ring_has_two_three_wait_cycles() -> void:
	var ring := Gen2WorldPhoneRing.new()
	assert_eq(ring.total_frames(), 120)
	assert_eq(ring.snapshot()["phase"], &"ringing")
	ring.advance(20.0 * Gen2WorldPhoneRing.FRAME_SECONDS)
	assert_eq(ring.snapshot()["phase"], &"caller_name")
	ring.advance(40.0 * Gen2WorldPhoneRing.FRAME_SECONDS)
	assert_eq(ring.snapshot()["ring"], 2)
	assert_eq(ring.snapshot()["phase"], &"ringing")
	assert_false(ring.is_finished())
	ring.advance(60.0 * Gen2WorldPhoneRing.FRAME_SECONDS)
	assert_true(ring.is_finished())
	assert_eq(ring.snapshot()["elapsed_frames"], 120)


func test_special_call_lead_precedes_the_same_two_rings() -> void:
	var ring := Gen2WorldPhoneRing.new(30)
	assert_eq(ring.total_frames(), 150)
	assert_eq(ring.snapshot()["phase"], &"pre_ring")
	ring.advance(30.0 * Gen2WorldPhoneRing.FRAME_SECONDS)
	assert_eq(ring.snapshot()["phase"], &"ringing")
	assert_eq(ring.snapshot()["ring"], 1)
