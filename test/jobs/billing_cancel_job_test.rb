require "test_helper"
require "support/dodo_webhooks"

# The job that stops a subscription at Dodo after the webhook that asked for it has committed.
class BillingCancelJobTest < ActiveJob::TestCase
  include DodoWebhooks

  setup do
    Billing.provider = dodo_provider
    @subscription = BillingSubscription.create!(provider: "dodo", subscription_id: "sub_stop", plan: "clinic", status: "active")
  end

  teardown { Billing.provider = nil }

  test "cancels at Dodo and marks the subscription cancelled" do
    cancel = stub_request(:patch, "#{API}/subscriptions/sub_stop").with(body: hash_including("status" => "cancelled"))
      .to_return(status: 200, headers: JSON_HEADERS, body: "{}")

    BillingCancelJob.perform_now("dodo", "sub_stop")

    assert_requested cancel
    assert_equal "cancelled", @subscription.reload.status
  end

  test "tries again later while Dodo can't be reached" do
    stub_request(:patch, "#{API}/subscriptions/sub_stop").to_return(status: 503, body: "{}")

    assert_enqueued_with(job: BillingCancelJob) { BillingCancelJob.perform_now("dodo", "sub_stop") }
    assert_equal "active", @subscription.reload.status
  end
end
