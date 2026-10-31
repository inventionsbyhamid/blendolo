require "application_system_test_case"
require "support/tremor_checks"
require "support/kit_helpers"

class AccessibilityTest < ApplicationSystemTestCase
  include TremorChecks
  include KitHelpers

  PUBLIC_PAGES = [ "/", "/privacy", "/accessibility", "/sources", "/guides/eyeliner-with-a-tremor" ].freeze

  test "home passes axe" do
    visit "/"

    assert_selector "h1", text: "hands that shake"
    assert_axe_clean
  end

  test "public pages pass axe" do
    PUBLIC_PAGES.drop(1).each do |path|
      visit path
      assert_selector "h1"
      assert_axe_clean
    end
  end

  test "kit pages pass axe" do
    kit_pages.each do |path|
      visit path
      assert_selector "h1"
      assert_axe_clean
    end
  end

  # Five key pages of the app, and the public pages, on a phone. At the steady size every target is still 64 px.
  test "targets at least 64px" do
    kit = make_kit(hands_today: 0)
    on_a_phone do
      [ *PUBLIC_PAGES, *kit_pages(kit), new_kit_photo_path(kit), new_kit_photo_path(kit, kind: "reference") ].each do |path|
        visit path
        assert_selector "h1"
        assert_operator evaluate_script("window.innerWidth"), :<=, 400
        assert_targets_at_least 64
      end
    end
  end

  private
    def kit_pages(kit = make_kit)
      [ start_path, kit_consent_path(kit), kit_hand_path(kit, 1), kit_path(kit), delete_kit_path(kit) ]
    end
end
