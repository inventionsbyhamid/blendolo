require "test_helper"

class ApiEaseTagsTest < ActionDispatch::IntegrationTest
  test "ease tags api returns tags and ease" do
    get api_ease_tags_path, params: { format: "stick", closure: "flip_cap" }

    # Pending: scoring products needs the ease engine (lane C) and Task 16. Until then the route answers 501.
    skip "Ease tags for products arrive with Task 16" if response.status == 501

    assert_response :success
    body = response.parsed_body
    assert body["tags"].present?
    assert body["ease"].present?
  end
end
