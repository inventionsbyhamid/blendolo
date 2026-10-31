require "test_helper"

class ApiEaseTagsTest < ActionDispatch::IntegrationTest
  test "ease tags api returns tags and ease" do
    get "/api/ease_tags", params: { product_format: "stick", closure: "pull_cap", grip: "chunky", step: "tinted_balm" }

    assert_response :success
    assert_equal "application/json", response.media_type
    body = response.parsed_body
    assert_equal({ "product_format" => "stick", "closure" => "pull_cap", "grip" => "chunky", "step" => "tinted_balm" }, body["product"])
    keys = body["tags"].map { |tag| tag["key"] }
    assert_includes keys, "chunky"
    assert_includes keys, "easy_cap"
    assert_includes keys, "no_pinch_grip"
    assert_equal %w[steady tremor pinch_grip one_hand tires_fast close_vision], body["ease"].keys
    assert body["ease"].values.all? { |ease| ease["score"].between?(0, 100) && ease["words"].present? }
  end

  test "a twist cap and a slim grip are harder for sore hands than a pump" do
    get "/api/ease_tags", params: { product_format: "cream", closure: "twist_cap", grip: "slim" }
    twist = response.parsed_body["ease"]["pinch_grip"]["score"]
    get "/api/ease_tags", params: { product_format: "pump", closure: "pump", grip: "standard" }
    pump = response.parsed_body["ease"]["pinch_grip"]["score"]

    assert_operator pump, :>, twist
  end

  test "values we don't know are refused with the ones we do" do
    get "/api/ease_tags", params: { product_format: "stick", closure: "zip", grip: "chunky" }

    assert_response :unprocessable_content
    assert_includes response.parsed_body["allowed"]["closure"], "pump"
    assert_includes response.parsed_body["allowed"]["step"], "tinted_balm"
  end
end
