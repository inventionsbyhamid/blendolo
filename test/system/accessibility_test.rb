require "application_system_test_case"
require "support/tremor_checks"

class AccessibilityTest < ApplicationSystemTestCase
  include TremorChecks

  PUBLIC_PAGES = [ "/", "/privacy", "/accessibility", "/sources", "/guides/eyeliner-with-a-tremor" ].freeze

  test "home passes axe" do
    visit "/"

    assert_selector "h1", text: "same red lip"
    assert_axe_clean
  end

  test "public pages pass axe" do
    PUBLIC_PAGES.drop(1).each do |path|
      visit path
      assert_selector "h1"
      assert_axe_clean
    end
  end

  test "targets at least 64px" do
    on_a_phone do
      PUBLIC_PAGES.each do |path|
        visit path
        assert_selector "h1"
        assert_operator evaluate_script("window.innerWidth"), :<=, 400
        assert_targets_at_least 64
      end
    end
  end
end
