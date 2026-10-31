require "application_system_test_case"
require "support/tremor_checks"
require "support/kit_helpers"
require "support/account_helpers"
require "support/dodo_webhooks"

# Pricing, the legal pages, the page after paying, the account's billing sections and the clinic's client list: axe,
# and every target at least 64 px with 24 px between, on a phone. Buy buttons are primary: 88 px.
class BillingSystemTest < ApplicationSystemTestCase
  include TremorChecks
  include KitHelpers
  include AccountHelpers
  include DodoWebhooks

  setup { Billing.provider = dodo_provider }
  teardown { Billing.provider = nil }

  test "pricing, terms and refunds pass axe with big targets" do
    on_a_phone do
      [ pricing_path, terms_path, refunds_path ].each do |path|
        visit path
        assert_selector "h1"
        assert_axe_clean
        assert_targets_at_least 64
      end

      visit pricing_path
      shot("pricing-phone")
      heights = evaluate_script("Array.from(document.querySelectorAll('.plan .btn--primary')).map((b) => b.getBoundingClientRect().height)")
      assert_equal 2, heights.size
      heights.each { |height| assert_operator height, :>=, 88 }
    end
  end

  test "pricing shows three plans side by side on a wide screen" do
    visit pricing_path
    shot("pricing-wide")

    tops = evaluate_script("Array.from(document.querySelectorAll('.plans > li')).map((plan) => Math.round(plan.getBoundingClientRect().top))")
    assert_equal 1, tops.uniq.size, "one row: #{tops.inspect}"
  end

  test "the page after paying shows the credits when they arrive, by itself" do
    user = make_user(credits: 0)
    sign_in_in_browser(user)

    on_a_phone do
      visit billing_success_path(plan: "look_pack")
      assert_selector "[role=status]", text: "Your credits arrive in a few seconds."
      assert_axe_clean
      assert_targets_at_least 64

      receive_dodo(dodo_body("payment_succeeded_pack", checkout: checkout_for(user)), id: "msg_pack")

      using_wait_time(12) { assert_selector "[role=status]", text: "16 credits added. You have 18 credits." }
      shot("billing-success")
      assert_selector "h1", count: 1
      assert_axe_clean
      assert_targets_at_least 64
    end
  end

  test "the account's billing sections and the client list pass axe with big targets" do
    user = make_user(credits: 0)
    sign_in_in_browser(user)
    receive_dodo(dodo_body("payment_succeeded_pack", checkout: checkout_for(user)), id: "msg_pack")
    receive_dodo(dodo_body("subscription_active", checkout: checkout_for(user, :clinic), next_billing_date: 1.month.from_now.utc.iso8601), id: "msg_clinic")
    kit = make_kit(path: :helper, hands_today: 0)
    kit.update!(user:, label: "Mrs Patel")

    on_a_phone do
      visit account_path
      assert_selector "h2", text: "Clinic plan"
      assert_button "Manage"
      assert_axe_clean
      assert_targets_at_least 64

      visit clinic_path
      assert_selector "h1", text: "Your clients"
      assert_selector ".clients h3", text: "Mrs Patel"
      shot("clinic-clients")
      assert_axe_clean
      assert_targets_at_least 64

      fill_in "Client's name or initials", with: "J. R."
      click_on "New client kit"
      assert_current_path kit_consent_path(user.kits.find_by!(label: "J. R."))
    end
  end
end
