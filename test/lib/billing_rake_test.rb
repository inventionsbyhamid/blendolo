require "test_helper"
require "rake"

# bin/rails billing:unmatched lists what the owner should look at, and nothing else.
class BillingRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("billing:unmatched")
    Rake::Task["billing:unmatched"].reenable
  end

  test "lists unmatched events with their ids and why" do
    BillingEvent.create!(provider: "dodo", event_id: "msg_lost", event_type: "payment.succeeded", status: :unmatched,
      payment_id: "pay_lost", note: "no checkout of ours for this customer")
    BillingEvent.create!(provider: "dodo", event_id: "msg_fine", event_type: "payment.succeeded", status: :applied)

    out, = capture_io { Rake::Task["billing:unmatched"].invoke }

    assert_includes out, "event msg_lost"
    assert_includes out, "payment pay_lost"
    assert_includes out, "no checkout of ours for this customer"
    assert_not_includes out, "msg_fine"
  end
end
