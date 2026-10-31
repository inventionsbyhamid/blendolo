require "test_helper"
require "support/dodo_webhooks"
require "support/account_helpers"

class Webhooks::DodoControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include DodoWebhooks
  include AccountHelpers

  setup do
    Billing.provider = dodo_provider
    @user = make_user(credits: 0, email: "clinic@example.com")
    @period_end = 1.month.from_now.change(usec: 0)
  end

  teardown { Billing.provider = nil }

  test "rejects a bad signature and stores nothing" do
    body = dodo_body("payment_succeeded_pack", checkout: checkout_for(@user))
    headers = dodo_headers(body, id: "msg_bad").merge("webhook-signature" => "v1,#{Base64.strict_encode64('x' * 32)}")

    assert_no_difference -> { BillingEvent.count } do
      post dodo_webhook_path, params: body, headers: headers.merge("Content-Type" => "application/json")
    end
    assert_response :unauthorized
    assert_equal 0, Credits.balance(@user)
  end

  test "an old delivery replayed is rejected" do
    deliver dodo_body("payment_succeeded_pack", checkout: checkout_for(@user)), id: "msg_old", at: 10.minutes.ago

    assert_response :unauthorized
    assert_equal 0, Credits.balance(@user)
  end

  test "without the webhook secret it asks the provider to retry later" do
    Billing.provider = dodo_provider(webhook_secret: nil)
    deliver dodo_body("payment_succeeded_pack", checkout: checkout_for(@user)), id: "msg_nosecret"

    assert_response :service_unavailable
    assert_equal 0, BillingEvent.count
  end

  test "a paid pack from our checkout and the account's own customer adds 16 credits" do
    checkout = checkout_for(@user)
    deliver dodo_body("payment_succeeded_pack", checkout:), id: "msg_pack"

    assert_response :ok
    assert_equal 16, Credits.balance(@user)
    event = BillingEvent.sole
    assert_equal [ "pack_paid", "applied", "look_pack", 16, @user ], [ event.kind, event.status, event.plan, event.credits, event.user ]
    assert checkout.reload.paid?
  end

  test "credits are times the quantity paid for" do
    body = dodo_body("payment_succeeded_pack", checkout: checkout_for(@user), product_cart: [ { product_id: "pdt_test_look_pack", quantity: 2 } ])
    deliver body, id: "msg_two"

    assert_equal 32, Credits.balance(@user)
  end

  # Static payment links take any metadata_* and email: without our checkout, or with someone else's customer, a
  # payment is nobody's.
  test "forged or missing references, and another customer, pay nobody" do
    victim = make_user(credits: 0, email: "victim@example.com")
    victims = checkout_for(victim)

    deliver dodo_body("payment_succeeded_pack"), id: "msg_no_ref"
    deliver dodo_body("payment_succeeded_pack", metadata: { "ref" => victims.token }), id: "msg_other_customer"
    deliver dodo_body("payment_succeeded_pack", metadata: { "user_id" => victim.id.to_s }), id: "msg_user_id"

    assert_response :ok
    assert_equal %w[unmatched] * 3, BillingEvent.order(:id).pluck(:status)
    assert_equal [ 0, 0 ], [ Credits.balance(victim), Credits.balance(@user) ]
    assert BillingEvent.where(customer_id: "cus_test_0001").all? { it.user_id.nil? }
  end

  test "the same delivery twice adds credits once" do
    body = dodo_body("payment_succeeded_pack", checkout: checkout_for(@user))
    2.times do
      deliver body, id: "msg_twice"
      assert_response :ok
    end

    assert_equal 1, BillingEvent.count
    assert_equal 16, Credits.balance(@user)
  end

  test "one payment sent as two events adds credits once" do
    body = dodo_body("payment_succeeded_pack", checkout: checkout_for(@user))
    deliver body, id: "msg_first"
    deliver body, id: "msg_second"

    assert_equal 2, BillingEvent.count
    assert_equal 16, Credits.balance(@user)
    assert_match "already added", BillingEvent.order(:id).last.note
  end

  test "a clinic subscription adds 40 credits and the plan until the period ends, with three days' grace" do
    checkout = checkout_for(@user, :clinic)
    deliver clinic("subscription_active", checkout:), id: "msg_active"

    assert_response :ok
    @user.reload
    assert_equal 40, Credits.balance(@user)
    assert @user.clinic?
    assert_equal @period_end + 3.days, @user.clinic_until
    subscription = BillingSubscription.sole
    assert_equal [ @user, "active", true ], [ subscription.user, subscription.status, subscription.renewing? ]
  end

  test "a renewal adds the next month's credits; a period's first payment counts once" do
    checkout = checkout_for(@user, :clinic)
    deliver clinic("subscription_active", checkout:), id: "msg_active"
    deliver clinic("subscription_renewed", checkout:), id: "msg_renewed_first"
    assert_equal 40, Credits.balance(@user)

    next_end = @period_end + 1.month
    deliver clinic("subscription_renewed", checkout:, period_end: next_end), id: "msg_renewed_next"

    assert_equal 80, Credits.balance(@user)
    assert_equal next_end + 3.days, @user.reload.clinic_until
  end

  test "a renewal without our metadata follows the subscription, if the customer is still the account's" do
    checkout = checkout_for(@user, :clinic)
    deliver clinic("subscription_active", checkout:), id: "msg_active"
    deliver dodo_body("subscription_renewed", metadata: {}, customer: { "customer_id" => @user.billing_customer_id },
      next_billing_date: (@period_end + 1.month).iso8601), id: "msg_renewed"
    deliver dodo_body("subscription_renewed", metadata: {}, customer: { "customer_id" => "cus_someone" },
      next_billing_date: (@period_end + 2.months).iso8601), id: "msg_renewed_other"

    assert_equal 80, Credits.balance(@user)
    assert_equal %w[applied applied unmatched], BillingEvent.order(:id).pluck(:status)
  end

  test "a cancellation booked for the period end stops renewing; the plan runs to its end" do
    checkout = checkout_for(@user, :clinic)
    deliver clinic("subscription_active", checkout:), id: "msg_active"
    deliver clinic("subscription_active", checkout:, cancel_at_next_billing_date: true).sub('"subscription.active"', '"subscription.updated"'),
      id: "msg_updated"

    assert_not BillingSubscription.sole.renewing?
    assert @user.reload.clinic?
    assert_equal @period_end + 3.days, @user.clinic_until
  end

  test "cancelled keeps the plan to its paid end; expired ends it now; credits stay" do
    checkout = checkout_for(@user, :clinic)
    deliver clinic("subscription_active", checkout:), id: "msg_active"
    deliver clinic("subscription_cancelled", checkout:), id: "msg_cancelled"
    assert @user.reload.clinic?
    assert_equal "cancelled", BillingSubscription.sole.status

    deliver clinic("subscription_expired", checkout:), id: "msg_expired"
    assert_not @user.reload.clinic?
    assert_equal 40, Credits.balance(@user)
  end

  test "past due keeps the plan to the period end plus the grace" do
    checkout = checkout_for(@user, :clinic)
    deliver clinic("subscription_active", checkout:), id: "msg_active"
    deliver clinic("subscription_active", checkout:, status: "past_due").sub('"subscription.active"', '"subscription.past_due"'),
      id: "msg_past_due"

    assert_equal "past_due", BillingSubscription.sole.status
    assert_equal @period_end + 3.days, @user.reload.clinic_until
  end

  test "state follows when things happened, not when they arrived" do
    checkout = checkout_for(@user, :clinic)
    deliver at_time(clinic("subscription_active", checkout:), 1.hour.ago), id: "msg_active"
    deliver at_time(clinic("subscription_cancelled", checkout:), 10.minutes.ago), id: "msg_cancelled"
    # A retry of the start event, sent before the cancellation, arrives after it.
    deliver at_time(clinic("subscription_active", checkout:), 30.minutes.ago), id: "msg_active_retry"

    assert_equal "cancelled", BillingSubscription.sole.status
    assert_equal 40, Credits.balance(@user)
  end

  test "expiry of an old subscription doesn't end a newer one" do
    checkout = checkout_for(@user, :clinic)
    deliver clinic("subscription_active", checkout:), id: "msg_old_active"
    deliver clinic("subscription_active", checkout:, subscription_id: "sub_test_clinic_0002"), id: "msg_new_active"
    deliver clinic("subscription_expired", checkout:), id: "msg_old_expired"

    assert @user.reload.clinic?
    assert_equal @period_end + 3.days, @user.clinic_until
  end

  test "a refund takes back what is left of the pack, once" do
    deliver dodo_body("payment_succeeded_pack", checkout: checkout_for(@user)), id: "msg_pack"
    Credits.debit!(@user, 6, reason: :render, source: "render:1")
    deliver dodo_body("refund_succeeded", customer: { "customer_id" => @user.billing_customer_id }), id: "msg_refund"
    deliver dodo_body("refund_succeeded", customer: { "customer_id" => @user.billing_customer_id }), id: "msg_refund_again"

    assert_response :ok
    assert_equal 0, Credits.balance(@user)
    refund = BillingEvent.refund.order(:id).first
    assert_equal [ @user, -10 ], [ refund.user, refund.credits ]
    assert_match "the rest were spent", refund.note
  end

  test "partial refunds take back their share, counted over every refund of the payment" do
    deliver dodo_body("payment_succeeded_pack", checkout: checkout_for(@user)), id: "msg_pack"
    customer = { "customer_id" => @user.billing_customer_id }
    deliver dodo_body("refund_succeeded", refund_id: "ref_a", amount: 400, is_partial: true, customer:), id: "msg_r1"
    assert_equal 7, Credits.balance(@user), "400 of 799 back: 9 of 16 credits"

    deliver dodo_body("refund_succeeded", refund_id: "ref_b", amount: 399, is_partial: true, customer:), id: "msg_r2"
    assert_equal 0, Credits.balance(@user), "all of it back: all 16 credits"
    assert_equal [ -9, -7 ], BillingEvent.refund.order(:id).pluck(:credits)

    deliver dodo_body("refund_succeeded", refund_id: "ref_b", amount: 399, is_partial: true, customer:), id: "msg_r2_again"
    assert_equal 0, Credits.balance(@user)
  end

  test "a won dispute gives back what it took, once, and the account lists the dispute once" do
    deliver dodo_body("payment_succeeded_pack", checkout: checkout_for(@user)), id: "msg_pack"
    deliver dodo_body("dispute_opened"), id: "msg_dispute_opened"
    deliver dodo_body("dispute_opened").sub('"dispute.opened"', '"dispute.challenged"'), id: "msg_dispute_challenged"
    assert_equal 0, Credits.balance(@user)

    2.times { |n| deliver dodo_body("dispute_opened").sub('"dispute.opened"', '"dispute.won"'), id: "msg_dispute_won_#{n}" }

    assert_equal 16, Credits.balance(@user)
    listed = BillingEvent.purchases.where(user: @user).map { [ it.kind, it.credits ] }
    assert_equal [ [ "dispute_won", 16 ], [ "dispute", -16 ], [ "pack_paid", 16 ] ], listed
  end

  test "a chargeback takes the pack back once, whichever dispute events come" do
    deliver dodo_body("payment_succeeded_pack", checkout: checkout_for(@user)), id: "msg_pack"
    Credits.grant!(@user, 5, reason: :admin, source: nil)
    deliver dodo_body("dispute_opened"), id: "msg_dispute_opened"
    deliver dodo_body("dispute_opened").sub('"dispute.opened"', '"dispute.lost"'), id: "msg_dispute_lost"

    assert_equal 5, Credits.balance(@user)
    assert_equal [ -16, nil ], BillingEvent.dispute.order(:id).pluck(:credits)
  end

  test "a refunded Clinic month takes its credits back, ends the plan now and stops the subscription at Dodo" do
    checkout = checkout_for(@user, :clinic)
    deliver clinic("subscription_active", checkout:), id: "msg_active"
    deliver dodo_body("payment_succeeded_subscription", customer: { "customer_id" => @user.billing_customer_id }), id: "msg_payment"

    assert_enqueued_with(job: BillingCancelJob, args: [ "dodo", "sub_test_clinic_0001" ]) do
      deliver dodo_body("refund_succeeded", payment_id: "pay_test_clinic_0001", amount: 1900,
        customer: { "customer_id" => @user.billing_customer_id }), id: "msg_refund"
    end

    assert_not @user.reload.clinic?
    assert_equal 0, Credits.balance(@user)
    assert_not BillingSubscription.sole.renewing?
  end

  test "a subscription paid through a deleted account's checkout is stopped at Dodo; one with no reference is only listed" do
    checkout = checkout_for(@user, :clinic)
    @user.destroy_everything!
    assert checkout.reload.expired?

    assert_enqueued_with(job: BillingCancelJob, args: [ "dodo", "sub_test_clinic_0001" ]) do
      deliver dodo_body("subscription_active", metadata: { "ref" => checkout.token }, next_billing_date: @period_end.iso8601), id: "msg_orphan"
    end
    assert_no_enqueued_jobs(only: BillingCancelJob) do
      deliver dodo_body("subscription_active", subscription_id: "sub_no_ref", next_billing_date: @period_end.iso8601), id: "msg_no_ref"
    end
    assert_equal %w[unmatched unmatched], BillingEvent.order(:id).pluck(:status)
  end

  test "a refund for a payment that isn't ours is unmatched" do
    deliver dodo_body("refund_succeeded"), id: "msg_refund"

    assert_equal "unmatched", BillingEvent.sole.status
  end

  test "events we don't act on are stored as ignored" do
    deliver dodo_body("payment_succeeded_subscription"), id: "msg_sub_payment"
    deliver dodo_body("subscription_active").sub('"subscription.active"', '"dispute.challenged"'), id: "msg_dispute_challenged"

    assert_equal %w[ignored ignored], BillingEvent.pluck(:status)
    assert_equal 0, Credits.balance(@user)
  end

  test "another product of the business adds nothing" do
    deliver dodo_body("payment_succeeded_pack", checkout: checkout_for(@user), product_cart: [ { product_id: "pdt_other", quantity: 1 } ]), id: "msg_other"

    assert_equal [ "unmatched", "not one of our products" ], [ BillingEvent.sole.status, BillingEvent.sole.note ]
    assert_equal 0, Credits.balance(@user)
  end

  test "the stored payload keeps no name, email or card" do
    deliver dodo_body("payment_succeeded_pack", checkout: checkout_for(@user)), id: "msg_pack"

    stored = BillingEvent.sole.payload.to_json
    [ "buyer@example.com", "Test Buyer", "4242", "Test Street" ].each { |detail| assert_not_includes stored, detail }
  end

  test "deleting the account keeps the payment record without the link" do
    deliver dodo_body("payment_succeeded_pack", checkout: checkout_for(@user)), id: "msg_pack"
    @user.destroy_everything!

    assert_nil BillingEvent.sole.reload.user_id
  end

  private
    def clinic(name, checkout:, period_end: @period_end, **data)
      dodo_body(name, checkout:, next_billing_date: period_end.utc.iso8601, **data)
    end

    # The body as if the provider sent it at time.
    def at_time(body, time)
      JSON.generate(JSON.parse(body).merge("timestamp" => time.utc.iso8601(6)))
    end

    def deliver(body, id:, at: Time.current)
      post dodo_webhook_path, params: body, headers: dodo_headers(body, id:, at:).merge("Content-Type" => "application/json")
    end
end
