require "test_helper"
require "support/dodo_webhooks"

class Billing::PlanTest < ActiveSupport::TestCase
  include DodoWebhooks

  test "the paid plans" do
    pack = Billing::Plan.fetch(:look_pack)
    clinic = Billing::Plan.fetch(:clinic)

    assert_equal [ "$7.99", 16, false ], [ pack.price, pack.credits, pack.subscription? ]
    assert_equal [ "$19", 40, true ], [ clinic.price, clinic.credits, clinic.subscription? ]
    assert_nil Billing::Plan.find(:gold)
  end

  # The owner's rule: every paid plan keeps at least half its price after the payment provider's worst case fee
  # (a card from abroad paying by PayPal) and every credit spent on a YouCam unit.
  test "every paid plan keeps at least the minimum margin in the worst case" do
    Billing::Plan.all.each do |plan|
      margin = Billing::Margin.for(plan, provider: dodo_provider)

      assert_operator margin.share, :>=, Billing::Margin.min_margin,
        "#{plan.name} keeps #{(margin.share * 100).round(1)}%; it needs #{Billing::Margin.floor_price_cents(plan, provider: dodo_provider)} cents"
    end
  end

  test "Dodo fees for one payment" do
    dodo = dodo_provider

    # A US card: 4% + 40 cents, and 0.5% more on a subscription.
    assert_equal 72, dodo.fee_cents(Billing::Plan.fetch(:look_pack), worst: false)
    assert_equal 126, dodo.fee_cents(Billing::Plan.fetch(:clinic), worst: false)
    # A card from abroad paying by PayPal: 1.5% and 3% more.
    assert_equal 108, dodo.fee_cents(Billing::Plan.fetch(:look_pack))
    assert_equal 211, dodo.fee_cents(Billing::Plan.fetch(:clinic))
  end
end
