require "application_system_test_case"
require "support/tremor_checks"
require "support/kit_helpers"
require "support/account_helpers"

class AccessibilityTest < ApplicationSystemTestCase
  include TremorChecks
  include KitHelpers
  include AccountHelpers

  PUBLIC_PAGES = [ "/", "/privacy", "/accessibility", "/sources", "/guides/eyeliner-with-a-tremor", "/sign_in" ].freeze

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

  # Where a preview is paid for (signed out, signed in, out of credits) and the account pages, on a phone, at the
  # steady size.
  test "sign in, the price of a preview and the account pass axe with targets of 64 px" do
    user = make_user(credits: 5)
    kit = make_kit(hands_today: 0, tremor: 2)
    on_a_phone do
      visit kit_look_path(kit, "red_lip")
      assert_selector ".spend .btn--google"
      assert_axe_clean
      assert_targets_at_least 64
      assert_operator evaluate_script("document.querySelector('.btn--google').getBoundingClientRect().height"), :>=, 88

      sign_in_in_browser(user)
      kit.update!(user:, label: "Mrs Patel")
      [ kit_look_path(kit, "red_lip"), account_path, delete_account_path ].each do |path|
        visit path
        assert_selector "h1"
        assert_axe_clean
        assert_targets_at_least 64
      end
      find("details.menu > summary").click
      assert_button "Sign out"

      Credits.debit!(user, Credits.balance(user), reason: :admin, source: nil)
      visit kit_look_path(kit, "red_lip")
      assert_selector ".spend", text: "You are out of credits. Get more to see this on your face."
      assert_axe_clean
      assert_targets_at_least 64
    end
  end

  private
    def kit_pages(kit = make_kit)
      [ start_path, kit_consent_path(kit), kit_hand_path(kit, 1), kit_path(kit), delete_kit_path(kit) ]
    end
end
