require "test_helper"
require "support/kit_helpers"

class ShoppingTest < ActionDispatch::IntegrationTest
  include KitHelpers

  test "shopping list tags follow profile" do
    pinch = make_kit(tremor: 0, pinch: 2, one_hand: 0, fatigue: 0, near_vision: 0)
    tremor = make_kit(tremor: 2, pinch: 0, one_hand: 0, fatigue: 0, near_vision: 0)
    [ pinch, tremor ].each { |kit| post kit_routine_path(kit), params: { look_key: "everyday_fresh" } }

    get kit_shopping_path(pinch)
    assert_select "#avoid-title + ul li", text: "Twist caps and screw tops"
    pinch_matches = good_for_your_hands
    assert_includes pinch_matches, "No pinch grip"
    assert_not_includes pinch_matches, "Blends away wobbles"
    assert_select ".honest", /Demo products, all made up/

    get kit_shopping_path(tremor)
    assert_select "#avoid-title + ul li", text: "Thin liquid liners and fine brushes"
    tremor_matches = good_for_your_hands
    assert_includes tremor_matches, "Blends away wobbles"
    assert_not_includes tremor_matches, "No pinch grip"
  end

  test "demo products are listed easiest first for these hands" do
    kit = make_kit(tremor: 0, pinch: 2, one_hand: 0, fatigue: 0, near_vision: 0)
    profile = kit.hand_profile
    products = ProductEase.for_step("tinted_moisturiser_fingers")

    pump, tube = products.partition { |product| product.ease.closure == "pump" }.map(&:first)
    assert_operator pump.ease.score(profile), :>, tube.ease.score(profile)
  end

  test "every demo product is for a known step and has tags from the vocabulary" do
    ProductEase.catalogue.each do |product|
      assert product.ease.step, product.key
      product.ease.tags.each { |tag| assert Ease::Words::TAGS.key?(tag), "#{product.key}: #{tag}" }
    end
    assert_operator ProductEase.catalogue.size, :>=, 16
  end

  private
    # Tags listed under "Good for your hands:" (marked in words, not by colour).
    def good_for_your_hands
      Nokogiri::HTML(response.body)
        .xpath("//p[contains(@class, 'tags__heading') and starts-with(normalize-space(.), 'Good for')]/following-sibling::ul[1]/li")
        .map { |tag| tag.text.strip }.uniq
    end
end
