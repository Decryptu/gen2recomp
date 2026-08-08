extends GutTest

## Version rules and release parsing only. Nothing here touches the network:
## the launcher owns the request and hands the result to `status_for`.


func test_the_project_declares_a_version() -> void:
	assert_false(Gen2UpdateCheck.current_version().is_empty())
	assert_false(Gen2UpdateCheck.parse_version(Gen2UpdateCheck.current_version()).is_empty())


func test_a_tag_may_carry_a_leading_v() -> void:
	assert_eq(Gen2UpdateCheck.parse_version("v1.2.3"), [1, 2, 3] as Array[int])
	assert_eq(Gen2UpdateCheck.parse_version("1.2.3"), [1, 2, 3] as Array[int])


func test_a_prerelease_or_build_suffix_is_cut() -> void:
	assert_eq(Gen2UpdateCheck.parse_version("1.2.3-beta.1"), [1, 2, 3] as Array[int])
	assert_eq(Gen2UpdateCheck.parse_version("1.2.3+build7"), [1, 2, 3] as Array[int])


func test_a_version_without_numbers_parses_empty() -> void:
	assert_eq(Gen2UpdateCheck.parse_version("nightly"), [] as Array[int])


func test_missing_components_count_as_zero() -> void:
	assert_eq(Gen2UpdateCheck.compare_versions("1.2", "1.2.0"), 0)
	assert_eq(Gen2UpdateCheck.compare_versions("1.2", "1.2.1"), -1)


func test_versions_order_by_component_not_by_text() -> void:
	assert_eq(Gen2UpdateCheck.compare_versions("0.9.0", "0.10.0"), -1)
	assert_eq(Gen2UpdateCheck.compare_versions("1.0.0", "0.99.99"), 1)
	assert_eq(Gen2UpdateCheck.compare_versions("2.0.0", "2.0.0"), 0)


func test_a_release_document_reads_into_display_fields() -> void:
	var release: Dictionary = Gen2UpdateCheck.parse_release(JSON.stringify({
		"tag_name": "v0.2.0",
		"name": "Second release",
		"html_url": "https://github.com/Decryptu/gen2recomp/releases/tag/v0.2.0",
		"published_at": "2026-08-08T10:00:00Z",
	}))

	assert_true(release["ok"])
	assert_eq(release["version"], "v0.2.0")
	assert_eq(release["name"], "Second release")
	assert_string_contains(release["url"], "releases/tag/v0.2.0")


func test_a_release_url_that_is_not_https_falls_back_to_the_releases_page() -> void:
	var release: Dictionary = Gen2UpdateCheck.parse_release(JSON.stringify({
		"tag_name": "0.2.0", "html_url": "http://example.invalid/tricked",
	}))

	assert_true(release["ok"])
	assert_eq(release["url"], Gen2UpdateCheck.RELEASES_PAGE)


func test_a_release_without_a_usable_tag_is_refused() -> void:
	assert_false(Gen2UpdateCheck.parse_release(JSON.stringify({"name": "no tag"}))["ok"])
	assert_false(Gen2UpdateCheck.parse_release(JSON.stringify({"tag_name": "nightly"}))["ok"])


func test_unreadable_json_is_refused() -> void:
	assert_false(Gen2UpdateCheck.parse_release("{ not json")["ok"])


func test_a_newer_release_reports_an_update() -> void:
	var body: String = JSON.stringify({"tag_name": "v0.2.0"})
	var result: Dictionary = Gen2UpdateCheck.status_for(200, body, "0.1.0")

	assert_eq(result["status"], Gen2UpdateCheck.Status.UPDATE_AVAILABLE)
	assert_string_contains(Gen2UpdateCheck.describe(result), "0.2.0")


func test_the_same_release_reports_up_to_date() -> void:
	var body: String = JSON.stringify({"tag_name": "v0.1.0"})
	var result: Dictionary = Gen2UpdateCheck.status_for(200, body, "0.1.0")

	assert_eq(result["status"], Gen2UpdateCheck.Status.UP_TO_DATE)


func test_a_local_build_ahead_of_the_release_says_so() -> void:
	var body: String = JSON.stringify({"tag_name": "v0.1.0"})
	var result: Dictionary = Gen2UpdateCheck.status_for(200, body, "0.2.0")

	assert_eq(result["status"], Gen2UpdateCheck.Status.AHEAD)


## GitHub answers 404 for a repository that has published nothing. The check
## worked; there is simply nothing to compare against.
func test_a_repository_with_no_releases_is_an_answer_not_a_failure() -> void:
	var result: Dictionary = Gen2UpdateCheck.status_for(404, "", "0.1.0")

	assert_eq(result["status"], Gen2UpdateCheck.Status.NO_RELEASES)
	assert_string_contains(Gen2UpdateCheck.describe(result), "0.1.0")


func test_any_other_http_code_is_unreadable() -> void:
	assert_eq(
		Gen2UpdateCheck.status_for(503, "", "0.1.0")["status"],
		Gen2UpdateCheck.Status.UNREADABLE,
	)


func test_a_two_hundred_with_a_damaged_body_is_unreadable() -> void:
	assert_eq(
		Gen2UpdateCheck.status_for(200, "{ not json", "0.1.0")["status"],
		Gen2UpdateCheck.Status.UNREADABLE,
	)


func test_an_oversized_response_is_refused_before_parsing() -> void:
	var huge: String = "x".repeat(Gen2UpdateCheck.MAX_RESPONSE_BYTES + 1)
	assert_false(Gen2UpdateCheck.parse_release(huge)["ok"])
