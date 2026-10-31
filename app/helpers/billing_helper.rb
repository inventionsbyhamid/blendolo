# Words about prices, purchases and the Clinic plan.
module BillingHelper
  TEST_MODE = "Payments are in test mode. Use a test card.".freeze
  TEST_CARD = "Card 4242 4242 4242 4242, expiry 06/32, CVV 123. No money moves.".freeze

  # "once" or "a month", after the price.
  def plan_period_words(plan)
    plan.subscription? ? "a month" : "once"
  end

  # Credits for a whole look on your own face (classic and easy), and for a signature look (the transfer and its easy
  # version).
  def look_credits = Credits.look_cost
  def signature_credits = Credits.cost(:transfer) + Credits.cost(:makeup)

  # A line of the account's purchases list.
  def purchase_words(event)
    if event.refund?
      "Refund of #{money(event.amount_cents, event.currency)}"
    elsif (plan = event.plan_record)
      "#{plan.subscription? ? "#{plan.name} plan, one month" : plan.name}: #{pluralize(event.credits, "credit")}"
    else
      "Payment"
    end
  end

  # "$7.99"; other currencies by their code ("12.00 EUR").
  def money(cents, currency)
    return "" unless cents

    currency.to_s.upcase.in?([ "", "USD" ]) ? "$#{format("%.2f", cents / 100.0)}" : "#{format("%.2f", cents / 100.0)} #{currency.upcase}"
  end

  # "Renews on 1 December 2026." or "Ends on 1 December 2026." for an account whose Clinic plan is on.
  def clinic_status_words(user)
    renewing = BillingEvent.renewing_subscription_for(user)
    if renewing&.period_end
      "Your Clinic plan is on. It renews on #{l renewing.period_end.to_date, format: :long}."
    else
      "Your Clinic plan is on until #{l user.clinic_until.to_date, format: :long}. It won't renew."
    end
  end

  # The buy button for a paid plan: a form that goes on to the payment provider's own page (not a Turbo visit).
  def buy_button(plan, label)
    render "components/button", label:, url: checkout_path, params: { plan: plan.key }, variant: :primary,
      form: { data: { turbo: false } }
  end
end
