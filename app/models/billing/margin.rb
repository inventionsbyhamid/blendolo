module Billing
  # What a paid plan keeps when every credit it adds is spent: price, less the provider's fees for one payment (the
  # worst case by default), less one YouCam unit per credit. Each paid plan must keep at least min_margin
  # (config/blendolo/plans.yml); the test suite checks it, so a price or fee change can't quietly lose money.
  module Margin
    Result = Data.define(:plan, :fee_cents, :unit_cents, :kept_cents) do
      def share = kept_cents.fdiv(plan.price_cents)
    end

    module_function

    def for(plan, provider: Billing.provider, worst: true)
      fee = provider.fee_cents(plan, worst:)
      units = plan.credits * unit_cost_cents
      Result.new(plan:, fee_cents: fee, unit_cents: units, kept_cents: plan.price_cents - fee - units)
    end

    # The lowest price that keeps min_margin for this plan's credits and fees, in whole cents.
    def floor_price_cents(plan, provider: Billing.provider)
      (plan.price_cents..).find do |cents|
        Margin.for(plan.with(price_cents: cents), provider:).share >= min_margin
      end
    end

    def unit_cost_cents = Plan.config.fetch(:unit_cost_cents)
    def min_margin = Plan.config.fetch(:min_margin)
  end
end
