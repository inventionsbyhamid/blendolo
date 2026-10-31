namespace :billing do
  desc "List payment webhooks that matched no account (a static payment link, another customer, a product that isn't " \
    "ours): money may have been taken with nothing given for it, so look at each in the payment provider's dashboard"
  task unmatched: :environment do
    events = BillingEvent.unmatched.order(:id)
    puts "No unmatched payment events." if events.none?
    events.each do |event|
      puts [ event.created_at.utc.iso8601, event.provider, event.event_type, "event #{event.event_id}",
        ("payment #{event.payment_id}" if event.payment_id), ("subscription #{event.subscription_id}" if event.subscription_id),
        event.note ].compact.join("  ")
    end
  end
end
