require "test_helper"
require "support/dodo_webhooks"

class Webhooks::DodoControllerTest < ActionDispatch::IntegrationTest
  include DodoWebhooks

  setup do
    Billing.provider = dodo_provider
    @user = User.create!(provider: "google_oauth2", uid: "dodo-test-1", email: "clinic@example.com", name: "Test Clinic")
    @period_end = 1.month.from_now.change(usec: 0)
  end

  teardown { Billing.provider = nil }

  test "rejects a bad signature and stores nothing" do
    body = dodo_body("payment_succeeded_pack", user: @user)
    headers = dodo_headers(body, id: "msg_bad").merge("webhook-signature" => "v1,#{Base64.strict_encode64('x' * 32)}")

    assert_no_difference -> { BillingEvent.count } do
      post dodo_webhook_path, params: body, headers: headers.merge("Content-Type" => "application/json")
    end
    assert_response :unauthorized
    assert_equal 0, Credits.balance(@user)
  end

  test "an old delivery replayed is rejected" do
    deliver dodo_body("payment_succeeded_pack", user: @user), id: "msg_old", at: 10.minutes.ago

    assert_response :unauthorized
    assert_equal 0, Credits.balance(@user)
  end

  test "without the webhook secret it asks the provider to retry later" do
    Billing.provider = dodo_provider(webhook_secret: nil)
    deliver dodo_body("payment_succeeded_pack", user: @user), id: "msg_nosecret"

    assert_response :service_unavailable
    assert_equal 0, BillingEvent.count
  end

  test "a paid pack adds 16 credits" do
    deliver dodo_body("payment_succeeded_pack", user: @user), id: "msg_pack"

    assert_response :ok
    assert_equal 16, Credits.balance(@user)
    event = BillingEvent.sole
    assert_equal [ "pack_paid", "look_pack", 16, @user ], [ event.kind, event.plan, event.credits, event.user ]
    assert_equal "pack_purchase", @user.credit_entries.last.reason
  end

  test "the same delivery twice adds credits once" do
    body = dodo_body("payment_succeeded_pack", user: @user)
    2.times do
      deliver body, id: "msg_twice"
      assert_response :ok
    end

    assert_equal 1, BillingEvent.count
    assert_equal 16, Credits.balance(@user)
  end

  test "one payment sent as two events adds credits once" do
    body = dodo_body("payment_succeeded_pack", user: @user)
    deliver body, id: "msg_first"
    deliver body, id: "msg_second"

    assert_response :ok
    assert_equal 2, BillingEvent.count
    assert_equal 16, Credits.balance(@user)
    assert_match "already added", BillingEvent.order(:id).last.note
  end

  test "a clinic subscription adds 40 credits and the clinic plan until the period ends, with a day's grace" do
    deliver clinic("subscription_active"), id: "msg_active"

    assert_response :ok
    @user.reload
    assert_equal 40, Credits.balance(@user)
    assert @user.clinic?
    assert_equal @period_end + 1.day, @user.clinic_until
    assert_equal "clinic_grant", @user.credit_entries.last.reason
  end

  test "a renewal adds the next month's credits; a period's first payment counts once" do
    deliver clinic("subscription_active"), id: "msg_active"
    # Dodo can send subscription.renewed for the first month's payment too.
    deliver clinic("subscription_renewed"), id: "msg_renewed_first"
    assert_equal 40, Credits.balance(@user)

    next_end = @period_end + 1.month
    deliver clinic("subscription_renewed", period_end: next_end), id: "msg_renewed_next"

    assert_equal 80, Credits.balance(@user)
    assert_equal next_end + 1.day, @user.reload.clinic_until
  end

  test "cancelled keeps the clinic plan until the paid period ends" do
    deliver clinic("subscription_active"), id: "msg_active"
    deliver clinic("subscription_cancelled"), id: "msg_cancelled"

    @user.reload
    assert @user.clinic?
    assert_equal @period_end, @user.clinic_until
    assert_equal 40, Credits.balance(@user)
  end

  test "expired ends the clinic plan now; credits stay" do
    deliver clinic("subscription_active"), id: "msg_active"
    deliver clinic("subscription_expired"), id: "msg_expired"

    assert_not @user.reload.clinic?
    assert_equal 40, Credits.balance(@user)
  end

  test "a late event for an old subscription doesn't end a newer one" do
    deliver clinic("subscription_active"), id: "msg_old_active"
    deliver clinic("subscription_active", subscription_id: "sub_test_clinic_0002"), id: "msg_new_active"
    deliver clinic("subscription_expired"), id: "msg_old_expired"

    assert @user.reload.clinic?
    assert_equal "not the account's clinic subscription", BillingEvent.order(:id).last.note
  end

  test "a renewal without our metadata finds the account from the subscription" do
    deliver clinic("subscription_active"), id: "msg_active"
    deliver dodo_body("subscription_renewed", metadata: {}, next_billing_date: (@period_end + 1.month).iso8601), id: "msg_renewed"

    assert_equal 80, Credits.balance(@user)
    assert_equal @user, BillingEvent.order(:id).last.user
  end

  test "a refund is noted and takes no credits back" do
    deliver dodo_body("payment_succeeded_pack", user: @user), id: "msg_pack"
    deliver dodo_body("refund_succeeded"), id: "msg_refund"

    assert_response :ok
    assert_equal 16, Credits.balance(@user)
    refund = BillingEvent.refund.sole
    assert_equal @user, refund.user
    assert_match "noted", refund.note
  end

  test "a payment for nobody we know is stored and changes nothing" do
    deliver dodo_body("payment_succeeded_pack", metadata: { "user_id" => "999999" }), id: "msg_nobody"

    assert_response :ok
    assert_equal "no account for this payment", BillingEvent.sole.note
  end

  test "events we don't act on are stored and answered" do
    deliver dodo_body("payment_succeeded_subscription", user: @user), id: "msg_sub_payment"
    deliver dodo_body("subscription_active", user: @user).sub('"subscription.active"', '"dispute.opened"'), id: "msg_dispute"

    assert_response :ok
    assert_equal [ "not an event we act on" ] * 2, BillingEvent.pluck(:note)
    assert_equal 0, Credits.balance(@user)
  end

  test "another product of the business adds nothing" do
    deliver dodo_body("payment_succeeded_pack", user: @user, product_cart: [ { product_id: "pdt_other", quantity: 1 } ]), id: "msg_other"

    assert_equal "not one of our products", BillingEvent.sole.note
    assert_equal 0, Credits.balance(@user)
  end

  test "the stored payload keeps no name, email or card" do
    deliver dodo_body("payment_succeeded_pack", user: @user), id: "msg_pack"

    stored = BillingEvent.sole.payload.to_json
    [ "buyer@example.com", "Test Buyer", "4242", "Test Street" ].each { |detail| assert_not_includes stored, detail }
  end

  test "deleting the account keeps the payment record without the link" do
    deliver dodo_body("payment_succeeded_pack", user: @user), id: "msg_pack"
    @user.destroy_everything!

    assert_nil BillingEvent.sole.reload.user_id
  end

  private
    def clinic(name, period_end: @period_end, **data)
      dodo_body(name, user: @user, next_billing_date: period_end.utc.iso8601, **data)
    end

    def deliver(body, id:, at: Time.current)
      post dodo_webhook_path, params: body, headers: dodo_headers(body, id:, at:).merge("Content-Type" => "application/json")
    end
end
